local urilib = require("uri")
local http_server = require('http.server')
local httpd_role = require('roles.httpd')

local M = {}

-- Сontains the module version.
-- Requires manual update in case of release commit.
M._VERSION = "0.3.2"

local function is_array(tbl)
    assert(type(tbl) == "table", "a table expected")
    for k, _ in pairs(tbl) do
        local found = false
        for idx, _ in ipairs(tbl) do
            if type(k) == type(idx) and k == idx then
                found = true
            end
        end
        if not found then
            return false
        end
    end
    return true
end

-- Removes extra '/' from start and end of the path to avoid paths duplication.
local function remove_side_slashes(path)
    if path:startswith('/') then
        path = string.lstrip(path, '/')
    end
    if path:endswith('/') then
        path = string.rstrip(path, '/')
    end
    return '/' .. path
end

local function parse_listen(listen)
    if type(listen) ~= "string" and type(listen) ~= "number" then
        return nil, nil, "must be a string or a number, got " .. type(listen)
    end

    local host
    local port
    if type(listen) == "string" then
        local uri, err = urilib.parse(listen)
        if err ~= nil then
            return nil, nil, "failed to parse URI: " .. err
        end

        if uri.scheme ~= nil then
            if uri.scheme == "unix" then
                uri.unix = uri.path
            else
                return nil, nil, "URI scheme is not supported"
            end
        end

        if uri.login ~= nil or uri.password then
            return nil, nil, "URI login and password are not supported"
        end

        if uri.query ~= nil then
            return nil, nil, "URI query component is not supported"
        end

        if uri.unix ~= nil then
            host = "unix/"
            port = uri.unix
        else
            if uri.service == nil then
                return nil, nil, "URI must contain a port"
            end

            port = tonumber(uri.service)
            if port == nil then
                return nil, nil, "URI port must be a number"
            end
            if uri.host ~= nil then
                host = uri.host
            elseif uri.ipv4 ~= nil then
                host = uri.ipv4
            elseif uri.ipv6 ~= nil then
                host = uri.ipv6
            else
                host = "0.0.0.0"
            end
        end
    elseif type(listen) == "number" then
        host = "0.0.0.0"
        port = listen
    end

    if type(port) == "number" and (port < 1 or port > 65535) then
        return nil, nil, "port must be in the range [1, 65535]"
    end
    return host, port, nil
end

local http_handlers = {
    json = function(req)
        local json_exporter = require('metrics.plugins.json')
        return req:render({ text = json_exporter.export() })
    end,
    prometheus = function(...)
        local http_handler = require('metrics.plugins.prometheus').collect_http
        return http_handler(...)
    end,
}
-- It is used as an error string with the predefined order.
local http_supported_formats_str = "json, prometheus"

local function validate_endpoint_metrics(metrics)
    if type(metrics) ~= 'table' then
        error("http endpoint 'metrics' must be a table, got " .. type(metrics), 5)
    end

    if is_array(metrics) then
        error("http endpoint 'metrics' must be a map, not an array", 5)
    end

    if metrics.enabled ~= nil and type(metrics.enabled) ~= 'boolean' then
        error("http endpoint metrics 'enabled' must be a boolean, got " .. type(metrics.enabled), 5)
    end
end

local function validate_http_endpoint(endpoint)
    if type(endpoint) ~= "table" then
        error("http endpoint must be a table, got " .. type(endpoint), 4)
    end
    if endpoint.path == nil then
        error("http endpoint 'path' must exist", 4)
    end
    if type(endpoint.path) ~= "string" then
        error("http endpoint 'path' must be a string, got " .. type(endpoint.path), 4)
    end
    if string.sub(endpoint.path, 1, 1) ~= '/' then
        error("http endpoint 'path' must start with '/', got " .. endpoint.path, 4)
    end

    if endpoint.format == nil then
        error("http endpoint 'format' must exist", 4)
    end
    if type(endpoint.format) ~= "string" then
        error("http endpoint 'format' must be a string, got " .. type(endpoint.format), 4)
    end

    if not http_handlers[endpoint.format] then
        error("http endpoint 'format' must be one of: " ..
              http_supported_formats_str .. ", got " .. endpoint.format, 4)
    end

    if endpoint.metrics ~= nil then
        validate_endpoint_metrics(endpoint.metrics)
    end
end

-- check_server_httpd_role validates that httpd configuration and provided name exists.
local function check_server_httpd_role(server)
    local httpd_roles_cfg = (require("config"):get("roles_cfg") or {})['roles.httpd']
    if httpd_roles_cfg == nil then
        error("there is no configuration for httpd role", 4)
    end
    if httpd_roles_cfg[server] == nil then
        error(("server with name %s not found in httpd role config"):format(server), 4)
    end
end

local function validate_http_node(node)
    if type(node) ~= "table" then
        error("http configuration node must be a table, got " .. type(node), 3)
    end

    local is_tls = false

    if node.ssl_key_file ~= nil then
        is_tls = true
        if type(node.ssl_key_file) ~= 'string' then
            error("ssl_key_file sould be a string, got " .. type(node.ssl_key_file), 3)
        end
    end
    if node.ssl_cert_file ~= nil then
        is_tls = true
        if type(node.ssl_cert_file) ~= 'string' then
            error("ssl_cert_file sould be a string, got " .. type(node.ssl_cert_file), 3)
        end
    end
    if node.ssl_ca_file ~= nil then
        is_tls = true
        if type(node.ssl_ca_file) ~= 'string' then
            error("ssl_ca_file sould be a string, got " .. type(node.ssl_ca_file), 3)
        end
    end
    if node.ssl_ciphers ~= nil then
        is_tls = true
        if type(node.ssl_ciphers) ~= 'string' then
            error("ssl_ciphers_file sould be a string, got " .. type(node.ssl_ciphers), 3)
        end
    end
    if node.ssl_password ~= nil then
        is_tls = true
        if type(node.ssl_password) ~= 'string' then
            error("ssl_password sould be a string, got " .. type(node.ssl_password), 3)
        end
    end
    if node.ssl_password_file ~= nil then
        is_tls = true
        if type(node.ssl_password_file) ~= 'string' then
            error("ssl_password_file sould be a string, got " .. type(node.ssl_password_file), 3)
        end
    end

    if node.server ~= nil then
        if type(node.server) ~= 'string' then
            error("server configuration sould be a string, got " .. type(node.server), 3)
        end

        if is_tls then
            error("tls options are availabe only with 'listen' parameter", 3)
        end

        if node.listen ~= nil then
            error("it is not possible to provide 'server' and 'listen' blocks simultaneously", 3)
        end

        check_server_httpd_role(node.server)
    elseif node.listen ~= nil then
        local _, _, err = parse_listen(node.listen)
        if err ~= nil then
            error("failed to parse http 'listen' param: " .. err, 3)
        end
    else
        check_server_httpd_role(httpd_role.DEFAULT_SERVER_NAME)
    end

    node.endpoints = node.endpoints or {}
    if type(node.endpoints) ~= "table" then
        error("http 'endpoints' must be a table, got " .. type(node.endpoints), 3)
    end
    if not is_array(node.endpoints) then
        error("http 'endpoints' must be an array, not a map", 3)
    end
    for _, endpoint in ipairs(node.endpoints) do
        validate_http_endpoint(endpoint)
    end

    for i, ei in ipairs(node.endpoints) do
        local pathi = remove_side_slashes(ei.path)
        for j, ej in ipairs(node.endpoints) do
            if i ~= j then
                local pathj = remove_side_slashes(ej.path)
                if pathi == pathj then
                    error("http 'endpoints' must have different paths", 3)
                end
            end
        end
    end
end

local http_servers = nil

local function validate_http(conf)
    if conf ~= nil and type(conf) ~= "table" then
        error("http configuration must be a table, got " .. type(conf), 2)
    end
    conf = conf or {}

    if not is_array(conf) then
        error("http configuration must be an array, not a map", 2)
    end

    for _, http_node in ipairs(conf) do
        validate_http_node(http_node)
    end

    for i, nodei in ipairs(conf) do
        local listen_address, server_name = nodei.listen, nodei.server
        local hosti, porti = nil, nil
        if listen_address ~= nil then
            local erri
            hosti, porti, erri = parse_listen(listen_address)
            assert(erri == nil) -- We should already successfully parse the URI.
        end
        for j, nodej in ipairs(conf) do
            if i ~= j then
                listen_address = nodej.listen
                if listen_address == nil then
                    if server_name ~= nil and server_name == nodej.server or
                       server_name == httpd_role.DEFAULT_SERVER_NAME and nodej.server == nil or
                       server_name == nil and nodej.server == httpd_role.DEFAULT_SERVER_NAME then
                        error("server names must have different targets in httpd", 2)
                    end
                    goto continue
                end
                local hostj, portj, errj = parse_listen(listen_address)
                assert(errj == nil) -- The same.
                if hosti == hostj and porti == portj then
                    error("http configuration nodes must have different listen targets", 2)
                end
            end
            ::continue::
        end
    end
end

local function wrap_handler(handler, metrics)
    if metrics ~= nil and metrics.enabled == true then
        local http_middleware = require('metrics.http_middleware')
        return http_middleware.v1(handler)
    end
    return handler
end

local function routes_equal(old, new)
    assert(type(old.metrics) == 'table')
    assert(type(new.metrics) == 'table')

    if old.format ~= new.format or old.metrics.enabled ~= new.metrics.enabled then
        return false
    end

    return true
end

local function disable_server(name)
    local server = (http_servers or {})[name]

    if server ~= nil then
        if server.httpd_name ~= nil then
            for path in pairs(server.routes) do
                server.httpd:delete(path)
            end
        else
            if server.httpd.is_run == true then
                server.httpd:stop()
            end
        end

        http_servers[name] = nil
    end
end

local function apply_http(conf)
    local listen_servers_to_start = {}
    local applied_servers = {}

    for _, node in ipairs(conf) do
        if #(node.endpoints or {}) > 0 then
            local host, port, target
            if node.server ~= nil then
                target = {
                    value = 'httpd_' .. node.server,
                    httpd_name = node.server,
                }
            elseif node.listen ~= nil then
                local err
                host, port, err = parse_listen(node.listen)
                if err ~= nil then
                    error("failed to parse URI: " .. err, 2)
                end
                target = {
                    value = 'listen_' .. host .. ':' .. tostring(port),
                }
            else
                target = {
                    value = 'httpd_' .. httpd_role.DEFAULT_SERVER_NAME,
                    httpd_name = httpd_role.DEFAULT_SERVER_NAME,
                }
            end

            http_servers = http_servers or {}
            applied_servers[target.value] = {}

            if http_servers[target.value] == nil then
                local httpd
                if node.listen ~= nil then
                    httpd = http_server.new(host, port, {
                        ssl_cert_file = node.ssl_cert_file,
                        ssl_key_file = node.ssl_key_file,
                        ssl_ca_file = node.ssl_ca_file,
                        ssl_ciphers = node.ssl_ciphers,
                        ssl_password = node.ssl_password,
                        ssl_password_file = node.ssl_password_file
                    })
                else
                    httpd = httpd_role.get_server(target.httpd_name)
                    if httpd == nil then
                        error(('failed to get server by name %q, check that roles.httpd was' ..
                              ' already applied'):format(target.httpd_name))
                    end
                end

                http_servers[target.value] = {
                    httpd = httpd,
                    routes = {},
                    httpd_name = target.httpd_name,
                }

                if node.listen ~= nil then
                    -- Defer starting a server with `listen` key to not trigger
                    -- "already in use" error of running servers that should be stopped
                    -- if it isn't in applying config.
                    table.insert(listen_servers_to_start, http_servers[target.value])
                end
            elseif target.httpd_name ~= nil then
                -- Update httpd value because it could change.
                http_servers[target.value].httpd = httpd_role.get_server(target.httpd_name)
            end

            local server = http_servers[target.value]
            local httpd = server.httpd
            local old_routes = server.routes

            local new_routes = {}
            for _, endpoint in ipairs(node.endpoints) do
                local path = remove_side_slashes(endpoint.path)
                new_routes[path] = {
                    format = endpoint.format,
                    metrics = endpoint.metrics or {},
                }
            end

            -- Remove old routes.
            for path, e in pairs(old_routes) do
                if new_routes[path] == nil or not routes_equal(e, new_routes[path]) then
                    httpd:delete(path)
                    old_routes[path] = nil
                end
            end

            -- Add new routes.
            for path, endpoint in pairs(new_routes) do
                if old_routes[path] == nil or httpd.iroutes[path] == nil then
                    httpd:route({
                        method = "GET",
                        path = path,
                        name = path,
                    }, wrap_handler(http_handlers[endpoint.format], endpoint.metrics))
                else
                    assert(old_routes[path] == nil
                           or routes_equal(old_routes[path], new_routes[path]))
                end
            end

            -- Update routers for a server.
            server.routes = new_routes
        end
    end

    for name in pairs(http_servers or {}) do
        if applied_servers[name] == nil then
            disable_server(name)
        end
    end

    for _, server in pairs(listen_servers_to_start) do
        server.httpd:start()
    end
end

local function stop_http()
    for name in pairs(http_servers or {}) do
        disable_server(name)
    end
    http_servers = nil
end

local export_targets = {
    ["http"] = {
        validate = validate_http,
        apply = apply_http,
        stop = stop_http,
    },
}

M.validate = function(conf)
    if conf ~= nil and type(conf) ~= "table" then
        error("configuration must be a table, got " .. type(conf))
    end

    for export_target, opts in pairs(conf or {}) do
        if type(export_target) ~= "string" then
            error("export target must be a string, got " .. type(export_target))
        end
        if export_targets[export_target] == nil then
            error("unsupported export target '" .. tostring(export_target) .. "'")
        end
        export_targets[export_target].validate(opts)
    end
end

M.apply = function(conf)
    -- This should be called on the role's lifecycle, but it's better to give
    -- a meaningful error if something goes wrong.
    M.validate(conf)

    for export_target, opts in pairs(conf or {}) do
        export_targets[export_target].apply(opts)
    end
end

M.stop = function()
    for _, callbacks in pairs(export_targets) do
        callbacks.stop()
    end
end

return M
