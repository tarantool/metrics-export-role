local json = require('json')
local http_client = require('http.client')
local metrics = require('metrics')

local t = require('luatest')
local g = t.group()

g.before_all(function(cg)
    cg.role = require('roles.metrics-export')
end)

g.before_each(function(cg)
    cg.counter = metrics.counter('some_counter')
    cg.counter:inc(1, {label = 'ANY'})
end)

g.after_each(function(cg)
    cg.role.stop()
    metrics.registry:unregister(cg.counter)
end)

local function assert_none(uri)
    local response = http_client.get(uri)
    t.assert_not_equals(response.status, 200)
    t.assert_not(response.body)
end

local function assert_json(uri)
    local response = http_client.get(uri)
    t.assert(response.body)

    local data = response.body
    local decoded = json.decode(data)
    for _, node in ipairs(decoded) do
        node.timestamp = nil
    end
    t.assert_equals(decoded, {
        {
            label_pairs = {label = "ANY"},
            metric_name = "some_counter",
            value = 1,
        },
    })
end

local function assert_prometheus(uri)
    local response = http_client.get(uri)
    t.assert(response.body)

    local data = response.body
    -- luacheck: ignore
    local expected_prometheus = [[# HELP some_counter 
# TYPE some_counter counter
some_counter{label="ANY"} 1
]]
    t.assert_equals(data, expected_prometheus)
end

g.test_json_endpoint = function(cg)
    cg.role.apply({
        http = {
            {
                listen = 8081,
                endpoints = {
                    {
                        path = "/json_metrics",
                        format = "json",
                    },
                },
            },
        },
    })
    assert_json("http://127.0.0.1:8081/json_metrics")
end

g.test_prometheus_endpoint = function(cg)
    cg.role.apply({
        http = {
            {
                listen = 8081,
                endpoints = {
                    {
                        path = "/prometheus_metrics",
                        format = "prometheus",
                    },
                },
            },
        },
    })
    assert_prometheus("http://127.0.0.1:8081/prometheus_metrics")
end

g.test_mixed = function(cg)
    cg.role.apply({
        http = {
            {
                listen = 8081,
                endpoints = {
                    {
                        path = "/metrics1",
                        format = "json",
                    },
                    {
                        path = "/metrics2",
                        format = "prometheus",
                    },
                },
            },
            {
                listen = 8082,
                endpoints = {
                    {
                        path = "/metrics3",
                        format = "json",
                    },
                    {
                        path = "/metrics4",
                        format = "prometheus",
                    },
                },
            },
        },
    })
    assert_json("http://127.0.0.1:8081/metrics1")
    assert_prometheus("http://127.0.0.1:8081/metrics2")
    assert_none("http://127.0.0.1:8081/metrics3")
    assert_none("http://127.0.0.1:8081/metrics4")

    assert_none("http://127.0.0.1:8082/metrics1")
    assert_none("http://127.0.0.1:8082/metrics2")
    assert_json("http://127.0.0.1:8082/metrics3")
    assert_prometheus("http://127.0.0.1:8082/metrics4")
end

g.test_reapply_delete = function(cg)
    cg.role.apply({
        http = {
            {
                listen = 8081,
                endpoints = {
                    {
                        path = "/metrics1",
                        format = "json",
                    },
                    {
                        path = "/metrics2",
                        format = "prometheus",
                    },
                },
            },
            {
                listen = 8082,
                endpoints = {
                    {
                        path = "/metrics/1",
                        format = "json",
                    },
                },
            },
        },
    })
    assert_json("http://127.0.0.1:8081/metrics1")
    assert_prometheus("http://127.0.0.1:8081/metrics2")
    assert_json("http://127.0.0.1:8082/metrics/1")

    cg.role.apply({
        http = {
            {
                listen = 8081,
                endpoints = {
                    {
                        path = "/metrics1",
                        format = "prometheus",
                    },
                },
            },
        },
    })
    assert_prometheus("http://127.0.0.1:8081/metrics1")
    assert_none("http://127.0.0.1:8081/metrics2")
    assert_none("http://127.0.0.1:8082/metrics/1")
end

g.test_reapply_add = function(cg)
    cg.role.apply({
        http = {
            {
                listen = 8081,
                endpoints = {
                    {
                        path = "/metrics1",
                        format = "prometheus",
                    },
                },
            },
        },
    })
    assert_prometheus("http://127.0.0.1:8081/metrics1")
    assert_none("http://127.0.0.1:8081/metrics2")
    assert_none("http://127.0.0.1:8082/metrics/1")

    cg.role.apply({
        http = {
            {
                listen = 8081,
                endpoints = {
                    {
                        path = "/metrics1",
                        format = "json",
                    },
                    {
                        path = "/metrics2",
                        format = "prometheus",
                    },
                },
            },
            {
                listen = 8082,
                endpoints = {
                    {
                        path = "/metrics/1",
                        format = "json",
                    },
                },
            },
        },
    })
    assert_json("http://127.0.0.1:8081/metrics1")
    assert_prometheus("http://127.0.0.1:8081/metrics2")
    assert_json("http://127.0.0.1:8082/metrics/1")
end

g.test_stop = function(cg)
    cg.role.apply({
        http = {
            {
                listen = 8081,
                endpoints = {
                    {
                        path = "/metrics1",
                        format = "json",
                    },
                },
            },
        },
    })
    assert_json("http://127.0.0.1:8081/metrics1")

    cg.role.stop()
    assert_none("http://127.0.0.1:8082/metrics/1")
end

g.test_endpoint_and_slashes = function(cg)
    cg.role.apply({
        http = {
            {
                listen = 8081,
                endpoints = {
                    {
                        path = "/endpoint",
                        format = "json",
                    },
                    {
                        path = "/endpoint/2/",
                        format = "json",
                    },
                },
            },
        },
    })
    assert_json("http://127.0.0.1:8081/endpoint")
    assert_json("http://127.0.0.1:8081/endpoint/")
    assert_json("http://127.0.0.1:8081/endpoint/2")
    assert_json("http://127.0.0.1:8081/endpoint/2/")
end
