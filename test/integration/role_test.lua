local fio = require('fio')
local json = require('json')
local helpers = require('test.helpers')
local http_client = require('http.client')
local server = require('test.helpers.server')

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

    cg.router = server:new({
        config_file = fio.abspath(fio.pathjoin('test', 'entrypoint', 'config.yaml')),
        chdir = cg.workdir,
        alias = 'master',
        workdir = cg.workdir,
    })

    -- It takes around 1s to start an instance, which considering small amount
    -- of integration tests is not a problem. But at the same time, we have a
    -- clean work environment.
    cg.router:start{wait_until_ready = true}
end)

g.after_each(function(cg)
    cg.router:stop()
    fio.rmtree(cg.workdir)
end)

local function assert_json(uri)
    local response = http_client.get(uri)
    t.assert_equals(response.status, 200)
    t.assert(response.body)

    local decoded = json.decode(response.body)
    t.assert(#decoded > 0)

    local found = false
    for _, metric in ipairs(decoded) do
        if metric.metric_name == "tnt_info_uptime" then
            found = true
        end
    end
    t.assert(found)
end

local function assert_prometheus(uri)
    local response = http_client.get(uri)
    t.assert_equals(response.status, 200)
    t.assert(response.body)

    -- It’s not very clear how to keep the check simple and clear here. So we
    -- just took a line from `prometheus` format which should be in the future
    -- releases and don't clash with JSON to avoid false-positive.
    t.assert_str_contains(response.body, "# TYPE tnt_info_uptime gauge")
    local ok = pcall(json.decode, response.body)
    t.assert_not(ok)
end

g.test_endpoints = function()
    assert_json("http://127.0.0.1:8081/metrics/json")
    assert_json("http://127.0.0.1:8081/metrics/json/")
    assert_prometheus("http://127.0.0.1:8081/metrics/prometheus")
    assert_prometheus("http://127.0.0.1:8081/metrics/prometheus/")

    assert_prometheus("http://127.0.0.1:8082/metrics/prometheus")
    assert_prometheus("http://127.0.0.1:8082/metrics/prometheus/")
    assert_json("http://127.0.0.1:8082/metrics/json")
    assert_json("http://127.0.0.1:8082/metrics/json/")
end
