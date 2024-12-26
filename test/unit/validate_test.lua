local t = require('luatest')
local g = t.group()

local mocks = require('test.helpers.mocks')

local httpd_config = {
    default = {
        listen = 8081,
    },
    additional = {
        listen = '127.0.0.1:8082',
    },
}

local config_get_return_httpd_config = function(_, param)
    if param == "roles_cfg" then
        return {
            ['roles.httpd'] = httpd_config,
        }
    end
    return {}
end

local config_get_return_empty_httpd_config = function(_, _)
    return {}
end

g.before_all(function(gc)
    gc.role = require('roles.metrics-export')
end)

g.after_each(function(gc)
    gc.role.stop()
end)

local error_cases = {
    ["cfg_not_table"] = {
        cfg = 4,
        err = "configuration must be a table, got number",
    },
    ["export_tartget_not_string"] = {
        cfg = {
            [4] = {},
        },
        err = "export target must be a string, got number",
    },
    ["unsupported_export_target"] = {
        cfg = {
            unsupported = {},
        },
        err = "unsupported export target 'unsupported'"
    },
    ["http_not_table"] = {
        cfg = {
            http = 4,
        },
        err = "http configuration must be a table, got number",
    },
    ["http_is_map"] = {
        cfg = {
            http = {
                k = 123,
            },
        },
        err = "http configuration must be an array, not a map",
    },
    ["http_is_map_mixed_with_array"] = {
        cfg = {
            http = {
                k = 123,
                [1] = 234,
            },
        },
        err = "http configuration must be an array, not a map",
    },
    ["http_node_not_a_table"] = {
        cfg = {
            http = {
                1,
            },
        },
        err = "http configuration node must be a table, got number",
    },
    ["http_node_listen_not_string_and_not_number"] = {
        cfg = {
            http = {
                {
                    listen = {},
                    endpoints = {},
                },
            },
        },
        err = "failed to parse http 'listen' param: must be a string or a number, got table",
    },
    ["http_node_listen_port_too_small"] = {
        cfg = {
            http = {
                {
                    listen = 0,
                    endpoints = {},
                },
            },
        },
        err = "failed to parse http 'listen' param: port must be in the range [1, 65535]",
    },
    ["http_node_listen_port_too_big"] = {
        cfg = {
            http = {
                {
                    listen = 65536,
                    endpoints = {},
                },
            },
        },
        err = "failed to parse http 'listen' param: port must be in the range [1, 65535]",
    },
    ["http_node_listen_uri_no_port"] = {
        cfg = {
            http = {
                {
                    listen = "localhost",
                    endpoints = {},
                },
            },
        },
        err = "failed to parse http 'listen' param: URI must contain a port",
    },
    ["http_node_listen_uri_port_too_small"] = {
        cfg = {
            http = {
                {
                    listen = "localhost:0",
                    endpoints = {},
                },
            },
        },
        err = "failed to parse http 'listen' param: port must be in the range [1, 65535]",
    },
    ["http_node_listen_uri_port_too_big"] = {
        cfg = {
            http = {
                {
                    listen = "localhost:65536",
                    endpoints = {},
                },
            },
        },
        err = "failed to parse http 'listen' param: port must be in the range [1, 65535]",
    },
    ["http_node_listen_uri_port_not_number"] = {
        cfg = {
            http = {
                {
                    listen = "localhost:foo",
                    endpoints = {},
                },
            },
        },
        err = "failed to parse http 'listen' param: URI port must be a number",
    },
    ["http_node_listen_uri_non_unix_scheme"] = {
        cfg = {
            http = {
                {
                    listen = "http://localhost:123",
                    endpoints = {},
                },
            },
        },
        err = "failed to parse http 'listen' param: URI scheme is not supported",
    },
    ["http_node_listen_uri_login_password"] = {
        cfg = {
            http = {
                {
                    listen = "login:password@localhost:123",
                    endpoints = {},
                },
            },
        },
        err = "failed to parse http 'listen' param: URI login and password are not supported",
    },
    ["http_node_listen_uri_query"] = {
        cfg = {
            http = {
                {
                    listen = "localhost:123/?foo=bar",
                    endpoints = {},
                },
            },
        },
        err = "failed to parse http 'listen' param: URI query component is not supported",
    },
    ["http_node_endpoints_not_table"] = {
        cfg = {
            http = {
                {
                    listen = "localhost:123",
                    endpoints = 4,
                },
            },
        },
        err = "http 'endpoints' must be a table, got number",
    },
    ["http_node_endpoints_map"] = {
        cfg = {
            http = {
                {
                    listen = "localhost:123",
                    endpoints = {k = 123},
                },
            },
        },
        err = "http 'endpoints' must be an array, not a map",
    },
    ["http_node_endpoints_array_mixed_with_map"] = {
        cfg = {
            http = {
                {
                    listen = "localhost:123",
                    endpoints = {
                        k = 123,
                        [1] = {},
                    },
                },
            },
        },
        err = "http 'endpoints' must be an array, not a map",
    },
    ["http_node_endpoint_not_table"] = {
        cfg = {
            http = {
                {
                    listen = "localhost:123",
                    endpoints = {
                        4,
                    },
                },
            },
        },
        err = "http endpoint must be a table, got number",
    },
    ["http_node_endpoint_path_not_exist"] = {
        cfg = {
            http = {
                {
                    listen = "localhost:123",
                    endpoints = {
                        {
                            path = nil,
                            format = "json",
                        },
                    },
                },
            },
        },
        err = "http endpoint 'path' must exist",
    },
    ["http_node_endpoint_path_not_string"] = {
        cfg = {
            http = {
                {
                    listen = "localhost:123",
                    endpoints = {
                        {
                            path = 4,
                            format = "json",
                        },
                    },
                },
            },
        },
        err = "http endpoint 'path' must be a string, got number",
    },
    ["http_node_endpoint_path_invalid"] = {
        cfg = {
            http = {
                {
                    listen = "localhost:123",
                    endpoints = {
                        {
                            path = "asd",
                            format = "json",
                        },
                    },
                },
            },
        },
        err = "http endpoint 'path' must start with '/', got asd",
    },
    ["http_node_endpoint_format_not_exist"] = {
        cfg = {
            http = {
                {
                    listen = "localhost:123",
                    endpoints = {
                        {
                            path = "/foo",
                            format = nil,
                        },
                    },
                },
            },
        },
        err = "http endpoint 'format' must exist",
    },
    ["http_node_endpoint_format_not_string"] = {
        cfg = {
            http = {
                {
                    listen = "localhost:123",
                    endpoints = {
                        {
                            path = "/foo",
                            format = 123,
                        },
                    },
                },
            },
        },
        err = "http endpoint 'format' must be a string, got number",
    },
    ["http_node_endpoint_format_invalid"] = {
        cfg = {
            http = {
                {
                    listen = "localhost:123",
                    endpoints = {
                        {
                            path = "/foo",
                            format = "jeson",
                        },
                    },
                },
            },
        },
        err = "http endpoint 'format' must be one of: json, prometheus, got jeson",
    },
    ["http_node_endpoint_same_paths"] = {
        cfg = {
            http = {
                {
                    listen = "localhost:123",
                    endpoints = {
                        {
                            path = "/foo",
                            format = "json",
                        },
                        {
                            path = "/foo",
                            format = "prometheus",
                        },
                    },
                },
            },
        },
        err = "http 'endpoints' must have different paths",
    },
    ["http_node_endpoint_duplicate_paths"] = {
        cfg = {
            http = {
                {
                    listen = "localhost:123",
                    endpoints = {
                        {
                            path = "//foo///",
                            format = "json",
                        },
                        {
                            path = "////foo/////",
                            format = "prometheus",
                        },
                    },
                },
            },
        },
        err = "http 'endpoints' must have different paths",
    },
    ["http_nodes_same_listen"] = {
        cfg = {
            http = {
                {
                    listen = "localhost:123",
                    endpoints = {},
                },
                {
                    listen = "localhost:123",
                    endpoints = {},
                },
            },
        },
        err = "http configuration nodes must have different listen targets",
    },
    ["http_endpoint_metrics_is_not_table "] = {
        cfg = {
            http = {
                {
                    listen = "localhost:123",
                    endpoints = {
                        {
                            path = "/",
                            format = "json",
                            metrics = "",
                        },
                    },
                },
            },
        },
        err = "http endpoint 'metrics' must be a table, got string",
    },
    ["http_endpoint_metrics_is_array"] = {
        cfg = {
            http = {
                {
                    listen = "localhost:123",
                    endpoints = {
                        {
                            path = "/",
                            format = "json",
                            metrics = {1},
                        },
                    },
                },
            },
        },
        err = "http endpoint 'metrics' must be a map, not an array",
    },
    ["http_endpoint_metrics_enabled_is_not_bool"] = {
        cfg = {
            http = {
                {
                    listen = "localhost:123",
                    endpoints = {
                        {
                            path = "/",
                            format = "json",
                            metrics = {
                                enabled = 'true',
                            },
                        },
                    },
                },
            },
        },
        err = "http endpoint metrics 'enabled' must be a boolean, got string",
    },
    ["integration_with_httpd_role_server_is_not_string"] = {
        cfg = { http = { { server = 1 } } },
        err = "server configuration sould be a string, got number",
    },
    ["integration_with_httpd_role_server_and_listen_simultaneously"] = {
        cfg = {
            http = {
                {
                    server = "additional",
                    listen = 8001,
                }
            }
        },
        err = "it is not possible to provide 'server' and 'listen' blocks simultaneously",
    },
    ["integration_with_httpd_role_servers_not_unique"] = {
        cfg = {
            http = {
                {
                    server = "additional",
                },
                {
                    listen = 8001,
                },
                {
                    server = "additional",
                },
            }
        },
        mocks = {
            {
                module = "config",
                method = "get",
                implementation = config_get_return_httpd_config,
            },
        },
        err = "server names must have different targets in httpd",
    },
    ["integration_with_httpd_role_default_servers_not_unique_straight"] = {
        cfg = {
            http = {
                {
                    server = "default",
                },
                {},
            }
        },
        mocks = {
            {
                module = "config",
                method = "get",
                implementation = config_get_return_httpd_config,
            },
        },
        err = "server names must have different targets in httpd",
    },
    ["integration_with_httpd_role_default_servers_not_unique_reverse"] = {
        cfg = {
            http = {
                {},
                {
                    server = "default",
                },
            }
        },
        mocks = {
            {
                module = "config",
                method = "get",
                implementation = config_get_return_httpd_config,
            },
        },
        err = "server names must have different targets in httpd",
    },
    ["integration_with_httpd_role_cfg_missing"] = {
        cfg = { http = { { server = "additional" } } },
        mocks = {
            {
                module = "config",
                method = "get",
                implementation = config_get_return_empty_httpd_config,
            },
        },
        err = "there is no configuration for httpd role",
    },
    ["integration_with_httpd_role_server_not_found"] = {
        cfg = { http = { { server = "not_existing_server" } } },
        mocks = {
            {
                module = "config",
                method = "get",
                implementation = config_get_return_httpd_config,
            },
        },
        err = "server with name not_existing_server not found in httpd role config",
    },
    ["ssl_key_file_not_string"] = {
        cfg = {
            http = {
                {
                    listen = "localhost:123",
                    ssl_key_file = {},
                },
            },
        },
        err = "ssl_key_file sould be a string, got table",
    },
    ["ssl_cert_file_not_string"] = {
        cfg = {
            http = {
                {
                    listen = "localhost:123",
                    ssl_cert_file = {},
                },
            },
        },
        err = "ssl_cert_file sould be a string, got table",
    },
    ["ssl_ca_file_not_string"] = {
        cfg = {
            http = {
                {
                    listen = "localhost:123",
                    ssl_ca_file = {},
                },
            },
        },
        err = "ssl_ca_file sould be a string, got table",
    },
    ["ssl_ciphers_file_not_string"] = {
        cfg = {
            http = {
                {
                    listen = "localhost:123",
                    ssl_ciphers = {},
                },
            },
        },
        err = "ssl_ciphers_file sould be a string, got table",
    },
    ["ssl_password_not_string"] = {
        cfg = {
            http = {
                {
                    listen = "localhost:123",
                    ssl_password = {},
                },
            },
        },
        err = "ssl_password sould be a string, got table",
    },
    ["ssl_password_file_not_string"] = {
        cfg = {
            http = {
                {
                    listen = "localhost:123",
                    ssl_password_file = {},
                },
            },
        },
        err = "ssl_password_file sould be a string, got table",
    },
    ["ssl_params_with_tls_opts"] = {
        cfg = {
            http = {
                {
                    server = "default",
                    ssl_key_file = "/path/to/key_file",
                    ssl_cert_file = "/path/to/cert_file",
                    ssl_ca_file = "/path/to/ca_file",
                    ssl_ciphers = "ciphers",
                    ssl_password = "ssl_password",
                    ssl_password_file = "ssl_password_file",
                },
            }
        },
        mocks = {
            {
                module = "config",
                method = "get",
                implementation = config_get_return_httpd_config,
            },
        },
        err = "tls options are availabe only with 'listen' parameter",
    },
}

for name, case in pairs(error_cases) do
    g["test_validate_error_" .. name] = function(gc)
        if case.mocks ~= nil then
            mocks.apply(case.mocks)
        end

        t.assert_error_msg_contains(case.err, function()
            gc.role.validate(case.cfg)
        end)

        if case.mocks ~= nil then
            mocks.clear()
        end
    end
end

for name, case in pairs(error_cases) do
    g["test_apply_validate_error_" .. name] = function(gc)
        if case.mocks ~= nil then
            mocks.apply(case.mocks)
        end

        t.assert_error_msg_contains(case.err, function()
            gc.role.apply(case.cfg)
        end)

        if case.mocks ~= nil then
            mocks.clear()
        end
    end
end

local ok_cases = {
    ["nil"] = {
        cfg = nil,
    },
    ["empty"] = {
        cfg = {},
    },
    ["empty_http"] = {
        cfg = {
            http = {},
        },
    },
    ["http_node_listen_port_min"] = {
        cfg = {
            http = {
                {
                    listen = 1,
                },
            },
        },
    },
    ["http_node_listen_port_max"] = {
        cfg = {
            http = {
                {
                    listen = 65535,
                },
            },
        },
    },
    ["http_node_listen_uri_port_min"] = {
        cfg = {
            http = {
                {
                    listen = "localhost:1",
                },
            },
        },
    },
    ["http_node_listen_uri_port_max"] = {
        cfg = {
            http = {
                {
                    listen = "localhost:65535",
                },
            },
        },
    },
    ["http_node_listen_uri_unix_scheme"] = {
        cfg = {
            http = {
                {
                    listen = "unix:///foo/bar/some.sock",
                },
            },
        },
    },
    ["http_node_listen_uri_unix_scheme_tt_style"] = {
        cfg = {
            http = {
                {
                    listen = "unix:/foo/bar/some.sock",
                },
            },
        },
    },
    ["http_node_listen_uri_unix"] = {
        cfg = {
            http = {
                {
                    listen = "/foo/bar/some.sock",
                },
            },
        },
    },
    ["http_node_endpoints_empty"] = {
        cfg = {
            http = {
                {
                    listen = "localhost:123",
                    endpoints = {},
                },
            },
        },
    },
    ["http_node_endpoints_format_json"] = {
        cfg = {
            http = {
                {
                    listen = "localhost:123",
                    endpoints = {
                        {
                            path = "/foo",
                            format = "json",
                        },
                    },
                },
            },
        },
    },
    ["http_node_endpoints_format_prometheus"] = {
        cfg = {
            http = {
                {
                    listen = "localhost:123",
                    endpoints = {
                        {
                            path = "/foo",
                            format = "prometheus",
                        },
                    },
                },
            },
        },
    },
    ["http_node_endpoints_with_different_paths"] = {
        cfg = {
            http = {
                {
                    listen = "localhost:123",
                    endpoints = {
                        {
                            path = "/foo",
                            format = "prometheus",
                        },
                        {
                            path = "/fooo",
                            format = "prometheus",
                        },
                    },
                },
            },
        },
    },
    ["http_node_endpoints_with_different_listens"] = {
        cfg = {
            http = {
                {
                    listen = "localhost:123",
                    endpoints = {},
                },
                {
                    listen = "localhost:124",
                    endpoints = {},
                },
            },
        },
    },
    ["http_endpoint_metrics_enabled_true"] = {
        cfg = {
            http = {
                {
                    listen = "localhost:123",
                    endpoints = {
                        {
                            path = "/",
                            format = "json",
                            metrics = {
                                enabled = true,
                            },
                        },
                    },
                },
            },
        },
    },
    ["integration_with_httpd_role_additional"] = {
        cfg = { http = { { server = "additional" } } },
        mocks = {
            {
                module = "config",
                method = "get",
                implementation = config_get_return_httpd_config,
            },
        },
    },
    ["integration_with_httpd_role_default"] = {
        cfg = { http = { { } } },
        mocks = {
            {
                module = "config",
                method = "get",
                implementation = config_get_return_httpd_config,
            },
        },
    },
    ["integration_with_httpd_role_different_servers"] = {
        cfg = {
            http = {
                { server = "additional" },
                {},
            },
        },
        mocks = {
            {
                module = "config",
                method = "get",
                implementation = config_get_return_httpd_config,
            },
        },
    },
    ["integration_with_httpd_role_different_variations"] = {
        cfg = {
            http = {
                { server = "additional" },
                { listen = 8083 },
            },
        },
        mocks = {
            {
                module = "config",
                method = "get",
                implementation = config_get_return_httpd_config,
            },
        },
    },
    ["listen_ssl_params_ok"] = {
        cfg = {
            http = {
                {
                    listen = "localhost:123",
                    ssl_key_file = "/path/to/key_file",
                    ssl_cert_file = "/path/to/cert_file",
                    ssl_ca_file = "/path/to/ca_file",
                    ssl_ciphers = "ciphers",
                    ssl_password = "ssl_password",
                    ssl_password_file = "ssl_password_file",
                },
            },
        },
    },
}

for name, case in pairs(ok_cases) do
    g["test_validate_ok_" .. name] = function(gc)
        if case.mocks ~= nil then
            mocks.apply(case.mocks)
        end

        t.assert_equals(gc.role.validate(case.cfg), nil)

        if case.mocks ~= nil then
            mocks.clear()
        end
    end
end
