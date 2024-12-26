local fio = require('fio')
local json = require('json')
local helpers = require('test.helpers')
local http_client = require('http.client'):new()
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
    fio.copytree(fio.pathjoin("test", "ssl_data"), fio.pathjoin(cg.workdir, "ssl_data"))

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

local function assert_json(uri, tls_opts)
    local response = http_client:get(uri, tls_opts)
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

local function assert_prometheus(uri, tls_opts)
    local response = http_client:get(uri, tls_opts)
    t.assert_equals(response.status, 200)
    t.assert(response.body)

    -- It’s not very clear how to keep the check simple and clear here. So we
    -- just took a line from `prometheus` format which should be in the future
    -- releases and don't clash with JSON to avoid false-positive.
    t.assert_str_contains(response.body, "# TYPE tnt_info_uptime gauge")
    local ok = pcall(json.decode, response.body)
    t.assert_not(ok)
end

local function assert_observed(host, path, tls_opts)
    -- Trigger observation.
    http_client:get(host .. path, tls_opts)

    local response = http_client:get(host .. path, tls_opts)
    t.assert_equals(response.status, 200)
    t.assert(response.body)

    local pattern = "http_server_request_latency_count.*" .. path
    t.assert_str_contains(response.body, pattern, true)
    local ok = pcall(json.decode, response.body)
    t.assert_not(ok)
end

local function assert_not_observed(host, path, tls_opts)
    -- Trigger observation.
    http_client:get(host .. path, tls_opts)

    local response = http_client:get(host .. path, tls_opts)
    t.assert_equals(response.status, 200)
    t.assert(response.body)

    local pattern = "http_server_request_latency_count.*" .. path
    t.assert_not_str_contains(response.body, pattern, true)
    local ok = pcall(json.decode, response.body)
    t.assert_not(ok)
end

g.test_endpoints = function()
    assert_json("http://127.0.0.1:8081/metrics/json")
    assert_json("http://127.0.0.1:8081/metrics/json/")
    assert_prometheus("http://127.0.0.1:8081/metrics/prometheus")
    assert_prometheus("http://127.0.0.1:8081/metrics/prometheus/")
    assert_not_observed("http://127.0.0.1:8081", "/metrics/prometheus")

    assert_prometheus("http://127.0.0.1:8082/metrics/prometheus")
    assert_prometheus("http://127.0.0.1:8082/metrics/prometheus/")
    assert_json("http://127.0.0.1:8082/metrics/json")
    assert_json("http://127.0.0.1:8082/metrics/json/")
    assert_not_observed("http://127.0.0.1:8082", "/metrics/prometheus")
    assert_observed("http://127.0.0.1:8082", "/metrics/observed/prometheus")

    assert_prometheus("http://127.0.0.1:8085/metrics/prometheus")
    assert_prometheus("http://127.0.0.1:8085/metrics/prometheus/")
    assert_json("http://127.0.0.1:8085/metrics/json")
    assert_json("http://127.0.0.1:8085/metrics/json/")
    assert_not_observed("http://127.0.0.1:8085", "/metrics/prometheus")

    assert_prometheus("http://127.0.0.1:8086/metrics/prometheus")
    assert_prometheus("http://127.0.0.1:8086/metrics/prometheus/")
    assert_json("http://127.0.0.1:8086/metrics/json")
    assert_json("http://127.0.0.1:8086/metrics/json/")
    assert_not_observed("http://127.0.0.1:8086", "/metrics/prometheus")
    assert_observed("http://127.0.0.1:8086", "/metrics/observed/prometheus/1")
end

g.test_endpoint_with_tls = function(cg)
    local client_tls_opts = {
        ca_file = fio.pathjoin(cg.workdir, 'ssl_data', 'ca.crt'),
        ssl_cert = fio.pathjoin(cg.workdir, 'ssl_data', 'client.crt'),
        ssl_key = fio.pathjoin(cg.workdir, 'ssl_data', 'client.key'),
    }

    assert_prometheus("https://localhost:8087/metrics/prometheus", client_tls_opts)
    assert_prometheus("https://localhost:8087/metrics/prometheus/", client_tls_opts)
    assert_json("https://localhost:8087/metrics/json", client_tls_opts)
    assert_json("https://localhost:8087/metrics/json/", client_tls_opts)
    assert_not_observed("https://localhost:8087", "/metrics/prometheus", client_tls_opts)
    assert_observed("https://localhost:8087", "/metrics/observed/prometheus/1", client_tls_opts)
end
