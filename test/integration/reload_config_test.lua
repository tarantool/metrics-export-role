local fio = require('fio')
local yaml = require('yaml')
local socket = require('socket')
local helpers = require('test.helpers')
local server = require('test.helpers.server')
local http_client = require('http.client'):new()

local t = require('luatest')
local g = t.group()

g.before_all(function()
    helpers.skip_if_unsupported()
end)

g.before_each(function(cg)
    cg.workdir = fio.tempdir()
    fio.mktree(cg.workdir)

    fio.copytree(".rocks", fio.pathjoin(cg.workdir, ".rocks"))
    fio.copytree("roles", fio.pathjoin(cg.workdir, "roles"))
    fio.copytree(fio.pathjoin("test", "ssl_data"), fio.pathjoin(cg.workdir, "ssl_data"))
    fio.copyfile(fio.pathjoin('test', 'entrypoint', 'config.yaml'), cg.workdir)
end)

g.after_each(function(cg)
    cg.server:stop()
    fio.rmtree(cg.workdir)
end)

local function is_tcp_connect(host, port)
    local tcp = socket.tcp()
    tcp:settimeout(0.3)
    local ok, _ = tcp:connect(host, port)
    tcp:close()

    return ok
end

local function change_listen_target_in_config(cg, old_addr, new_addr)
    local file = fio.open(fio.pathjoin(cg.workdir, 'config.yaml'), {'O_RDONLY'})
    t.assert(file ~= nil)

    local cfg = file:read()
    file:close()

    cfg = yaml.decode(cfg)
    local export_instances = cfg.groups['group-001'].replicasets['replicaset-001'].
                             instances.master.roles_cfg['roles.metrics-export'].http

    for i, v in pairs(export_instances) do
        if v.listen ~= nil and v.listen == old_addr then
            export_instances[i].listen = new_addr
        end
    end

    file = fio.open(fio.pathjoin(cg.workdir, 'config.yaml'), {'O_CREAT', 'O_WRONLY', 'O_TRUNC'}, tonumber('644', 8))
    file:write(yaml.encode(cfg))
    file:close()
end

local function change_http_addr_in_config(cg, new_addr, server_name)
    if server_name == nil then
      server_name = 'default'
    end

    local file = fio.open(fio.pathjoin(cg.workdir, 'config.yaml'), {'O_RDONLY'})
    t.assert(file ~= nil)

    local cfg = file:read()
    file:close()

    cfg = yaml.decode(cfg)
    cfg.groups['group-001'].replicasets['replicaset-001'].
                             instances.master.roles_cfg['roles.httpd'][server_name].listen = new_addr

    file = fio.open(fio.pathjoin(cg.workdir, 'config.yaml'), {'O_CREAT', 'O_WRONLY', 'O_TRUNC'}, tonumber('644', 8))
    file:write(yaml.encode(cfg))
    file:close()
end

g.test_reload_config_update_addr = function(cg)
    cg.server = server:new({
        config_file = fio.pathjoin(cg.workdir, 'config.yaml'),
        chdir = cg.workdir,
        alias = 'master',
        workdir = cg.workdir,
    })

    cg.server:start({wait_until_ready = true})

    t.assert(is_tcp_connect('127.0.0.1', 8082))
    t.assert_not(is_tcp_connect('127.0.0.2', 8082))

    change_listen_target_in_config(cg, '127.0.0.1:8082', '0.0.0.0:8082')
    cg.server:eval("require('config'):reload()")

    t.assert(is_tcp_connect('127.0.0.1', 8082))
    t.assert(is_tcp_connect('127.0.0.2', 8082))
    t.assert(is_tcp_connect('127.1.2.3', 8082))

    change_listen_target_in_config(cg, '0.0.0.0:8082', '127.0.0.1:8082')
    cg.server:eval("require('config'):reload()")

    t.assert_not(is_tcp_connect('127.0.0.2', 8082))
    t.assert(is_tcp_connect('127.0.0.1', 8082))
end

g.test_reload_config_global_addr_conflict = function(cg)
    cg.server = server:new({
        config_file = fio.pathjoin(cg.workdir, 'config.yaml'),
        chdir = cg.workdir,
        alias = 'master',
        workdir = cg.workdir,
    })

    cg.server:start({wait_until_ready = true})

    change_listen_target_in_config(cg, 8081, '0.0.0.0:8082')
    t.assert_error_msg_content_equals(
      "Can't create tcp_server: Address already in use",
      function() cg.server:eval("require('config'):reload()") end
    )
end

g.test_reload_config_routes_exists = function(cg)
    cg.server = server:new({
        config_file = fio.pathjoin(cg.workdir, 'config.yaml'),
        chdir = cg.workdir,
        alias = 'master',
        workdir = cg.workdir,
    })

    cg.server:start({wait_until_ready = true})

    local response = http_client:get('localhost:8085/metrics/prometheus')
    t.assert_equals(response.status, 200)
    t.assert(response.body)

    local _, err = cg.server:eval("require('config'):reload()")
    t.assert_not(err)

    response = http_client:get('localhost:8085/metrics/prometheus')
    t.assert_equals(response.status, 200)
    t.assert(response.body)

    change_http_addr_in_config(cg, 8088)
    _, err = cg.server:eval("require('config'):reload()")
    t.assert_not(err)

    response = http_client:get('localhost:8085/metrics/prometheus')
    t.assert_equals(response.status, 595)

    response = http_client:get('localhost:8088/metrics/prometheus')
    t.assert_equals(response.status, 200)
    t.assert(response.body)
end
