local http_client = require('http.client')
local http_middleware = require('metrics.http_middleware')
local metrics = require('metrics')

local t = require('luatest')
local g = t.group()

g.before_all(function(cg)
    cg.role = require('roles.metrics-export')
end)

g.before_each(function(cg)
    cg.collector_name = http_middleware.get_default_collector().name
end)

g.after_each(function(cg)
    metrics.clear()
    http_middleware.set_default_collector(nil)

    cg.role.stop()
end)

local function assert_contains_http(cg, uri, path_pattern)
    local response = http_client.get(uri)
    t.assert(response.body)

    local data = response.body
    local expected = ("%s_count"):format(cg.collector_name)
    if path_pattern ~= nil then
        expected = expected .. ".*" .. path_pattern
    end
    t.assert_str_contains(data, expected, true)
end

local function assert_not_contains_http(cg, uri, path_pattern)
    local response = http_client.get(uri)
    t.assert(response.body)

    local data = response.body
    local expected = ("%s_count"):format(cg.collector_name)
    if path_pattern ~= nil then
        expected = expected .. ".*" .. path_pattern
    end
    t.assert_not_str_contains(data, expected, true)
end

local function trigger_http(uri)
    local response = http_client.get(uri)
    t.assert(response.body)
end

g.test_http_metrics_disabled_by_default = function(cg)
    cg.role.apply({
        http = {
            {
                listen = 8081,
                endpoints = {
                    {
                        path = "/prometheus",
                        format = "prometheus",
                    },
                    {
                        path = "/json",
                        format = "json",
                    },
                },
            },
        },
    })

    trigger_http("http://127.0.0.1:8081/prometheus")
    trigger_http("http://127.0.0.1:8081/json")


    assert_not_contains_http(cg, "http://127.0.0.1:8081/prometheus")
    assert_not_contains_http(cg, "http://127.0.0.1:8081/json")
end

g.test_enabled_http_metrics = function(cg)
    cg.role.apply({
        http = {
            {
                listen = 8081,
                endpoints = {
                    {
                        path = "/prometheus",
                        format = "prometheus",
                        metrics = {enabled = true},
                    },
                    {
                        path = "/json",
                        format = "json",
                        metrics = {enabled = true},
                    },
                },
            },
        },
    })

    trigger_http("http://127.0.0.1:8081/prometheus")
    trigger_http("http://127.0.0.1:8081/json")

    assert_contains_http(cg, "http://127.0.0.1:8081/prometheus", [[path="/prometheus"]])
    assert_contains_http(cg, "http://127.0.0.1:8081/prometheus", [[path="/json"]])

    assert_contains_http(cg, "http://127.0.0.1:8081/json", [["path":"/prometheus"]])
    assert_contains_http(cg, "http://127.0.0.1:8081/json", [["path":"/json"]])
end

g.test_enabled_http_metrics_for_one_endpoint = function(cg)
    cg.role.apply({
        http = {
            {
                listen = 8081,
                endpoints = {
                    {
                        path = "/prometheus",
                        format = "prometheus",
                        metrics = {enabled = true},
                    },
                    {
                        path = "/json",
                        format = "json",
                    },
                },
            },
        },
    })

    trigger_http("http://127.0.0.1:8081/prometheus")
    trigger_http("http://127.0.0.1:8081/json")

    assert_contains_http(cg, "http://127.0.0.1:8081/prometheus", [[path="/prometheus"]])
    assert_contains_http(cg, "http://127.0.0.1:8081/json", [["path":"/prometheus"]])

    assert_not_contains_http(cg, "http://127.0.0.1:8081/prometheus", [[path="/json"]])
    assert_not_contains_http(cg, "http://127.0.0.1:8081/json", [["path":"/json"]])
end
