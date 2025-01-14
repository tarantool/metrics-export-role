local json = require('json')
local http_client = require('http.client'):new()
local metrics = require('metrics')
local mocks = require('test.helpers.mocks')
local fio = require('fio')

local t = require('luatest')
local g = t.group()

local httpd_config = {
    default = {
        listen = 8085,
    },
    additional = {
        listen = '127.0.0.1:8086',
    },
    ["127.0.0.1:8081"] = {
        listen = 8087,
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

g.before_all(function(cg)
    cg.role = require('roles.metrics-export')
    cg.httpd_role = require('roles.httpd')
end)

g.before_each(function(cg)
    cg.httpd_role.apply(httpd_config)
    cg.counter = metrics.counter('some_counter')
    cg.counter:inc(1, {label = 'ANY'})
end)

g.after_each(function(cg)
    cg.httpd_role.stop()
    cg.role.stop()
    metrics.registry:unregister(cg.counter)
end)

local function assert_none(uri, tls_opts)
    local response = http_client:get(uri, tls_opts)
    t.assert_not_equals(response.status, 200)
    t.assert_not(response.body)
end

local function assert_json(uri, tls_opts)
    local response = http_client:get(uri, tls_opts)
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

local function assert_prometheus(uri, tls_opts)
    local response = http_client:get(uri, tls_opts)
    t.assert(response.body)

    local data = response.body
    -- luacheck: ignore
    local expected_prometheus = [[# HELP some_counter 
# TYPE some_counter counter
some_counter{label="ANY"} 1
]]
    t.assert_equals(data, expected_prometheus)
end

local test_json_endpoint_cases = {
    ['listen'] = {
        cfg = {
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
        },
        expected_url = "http://127.0.0.1:8081/json_metrics",
    },
    ['httpd'] = {
        cfg = {
            http = {
                {
                    server = "additional",
                    endpoints = {
                        {
                            path = "/json_metrics",
                            format = "json",
                        },
                    },
                },
            },
        },
        mocks = {
            {
                module = "config",
                method = "get",
                implementation = config_get_return_httpd_config,
            },
        },
        expected_url = "http://127.0.0.1:8086/json_metrics"
    },
}

for name, case in pairs(test_json_endpoint_cases) do
    g['test_json_endpoint_' .. name] = function(cg)
        if case.mocks ~= nil then
            mocks.apply(case.mocks)
        end

        cg.role.apply(case.cfg)
        assert_json(case.expected_url)

        if case.mocks ~= nil then
            mocks.clear()
        end
    end
end

local test_prometheus_endpoint_cases = {
    ["listen"] = {
        cfg = {
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
        },
        expected_url = "http://127.0.0.1:8081/prometheus_metrics",
    },
    ["httpd"] = {
        cfg = {
            http = {
                {
                    server = "additional",
                    endpoints = {
                        {
                            path = "/prometheus_metrics",
                            format = "prometheus",
                        },
                    },
                },
            },
        },
        mocks = {
            {
                module = "config",
                method = "get",
                implementation = config_get_return_httpd_config,
            },
        },
        expected_url = "http://127.0.0.1:8086/prometheus_metrics",
    },
}

for name, case in pairs(test_prometheus_endpoint_cases) do
    g['test_prometheus_endpoint_' .. name] = function(cg)
        if case.mocks ~= nil then
            mocks.apply(case.mocks)
        end

        cg.role.apply(case.cfg)
        assert_prometheus(case.expected_url)

        if case.mocks ~= nil then
            mocks.clear()
        end
    end
end

local test_mixed_cases = {
    ["listen"] = {
        cfg = {
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
        },
        expected_json = {
            "http://127.0.0.1:8081/metrics1",
            "http://127.0.0.1:8082/metrics3",
        },
        expected_prometheus = {
            "http://127.0.0.1:8081/metrics2",
            "http://127.0.0.1:8082/metrics4",
        },
        expected_none = {
            "http://127.0.0.1:8082/metrics1",
            "http://127.0.0.1:8082/metrics2",
            "http://127.0.0.1:8081/metrics3",
            "http://127.0.0.1:8081/metrics4",
        },
    },
    ["httpd"] = {
        cfg = {
            http = {
                {
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
                    server = "additional",
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
        },
        mocks = {
            {
                module = "config",
                method = "get",
                implementation = config_get_return_httpd_config,
            },
        },
        expected_json = {
            "http://127.0.0.1:8085/metrics1",
            "http://127.0.0.1:8086/metrics3",
        },
        expected_prometheus = {
            "http://127.0.0.1:8085/metrics2",
            "http://127.0.0.1:8086/metrics4",
        },
        expected_none = {
            "http://127.0.0.1:8086/metrics1",
            "http://127.0.0.1:8086/metrics2",
            "http://127.0.0.1:8085/metrics3",
            "http://127.0.0.1:8085/metrics4",
        },
    },
    ["listen_httpd"] = {
        cfg = {
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
                    server = "additional",
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
        },
        mocks = {
            {
                module = "config",
                method = "get",
                implementation = config_get_return_httpd_config,
            },
        },
        expected_json = {
            "http://127.0.0.1:8081/metrics1",
            "http://127.0.0.1:8086/metrics3",
        },
        expected_prometheus = {
            "http://127.0.0.1:8081/metrics2",
            "http://127.0.0.1:8086/metrics4",
        },
        expected_none = {
            "http://127.0.0.1:8086/metrics1",
            "http://127.0.0.1:8086/metrics2",
            "http://127.0.0.1:8081/metrics3",
            "http://127.0.0.1:8081/metrics4",
        },
    },
    ["listen_httpd_collision"] = {
        cfg = {
            http = {
                {
                    listen = "127.0.0.1:8081",
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
                    server = "127.0.0.1:8081",
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
        },
        mocks = {
            {
                module = "config",
                method = "get",
                implementation = config_get_return_httpd_config,
            },
        },
        expected_json = {
            "http://127.0.0.1:8081/metrics1",
            "http://127.0.0.1:8087/metrics3",
        },
        expected_prometheus = {
            "http://127.0.0.1:8081/metrics2",
            "http://127.0.0.1:8087/metrics4",
        },
        expected_none = {
            "http://127.0.0.1:8087/metrics1",
            "http://127.0.0.1:8087/metrics2",
            "http://127.0.0.1:8081/metrics3",
            "http://127.0.0.1:8081/metrics4",
        },
    },
}

for name, case in pairs(test_mixed_cases) do
    g['test_mixed_' .. name] = function(cg)
        if case.mocks ~= nil then
            mocks.apply(case.mocks)
        end

        cg.role.apply(case.cfg)

        for _, url in pairs(case.expected_json) do
            assert_json(url)
        end
        for _, url in pairs(case.expected_prometheus) do
            assert_prometheus(url)
        end
        for _, url in pairs(case.expected_none) do
            assert_none(url)
        end

        if case.mocks ~= nil then
            mocks.clear()
        end
    end
end

local test_reapply_delete_cases = {
    ["listen"] = {
        apply_cases = {
            {
                cfg = {
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
                },
                expected_json_urls = {
                    "http://127.0.0.1:8081/metrics1",
                    "http://127.0.0.1:8082/metrics/1",
                },
                expected_prometheus_urls = {
                    "http://127.0.0.1:8081/metrics2"
                },
                expected_none_urls = {},
            },
            {
                cfg = {
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
                },
                expected_json_urls = {},
                expected_prometheus_urls = {
                    "http://127.0.0.1:8081/metrics1",
                },
                expected_none_urls = {
                    "http://127.0.0.1:8081/metrics2",
                    "http://127.0.0.1:8082/metrics/1",
                },
            },
        },
    },
    ["httpd"] = {
        apply_cases = {
            {
                cfg = {
                    http = {
                        {
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
                            server = "additional",
                            endpoints = {
                                {
                                    path = "/metrics/1",
                                    format = "json",
                                },
                            },
                        },
                    },
                },
                expected_json_urls = {
                    "http://127.0.0.1:8085/metrics1",
                    "http://127.0.0.1:8086/metrics/1",
                },
                expected_prometheus_urls = {
                    "http://127.0.0.1:8085/metrics2"
                },
                expected_none_urls = {},
            },
            {
                cfg = {
                    http = {
                        {
                            endpoints = {
                                {
                                    path = "/metrics1",
                                    format = "prometheus",
                                },
                            },
                        },
                    },
                },
                expected_json_urls = {},
                expected_prometheus_urls = {
                    "http://127.0.0.1:8085/metrics1",
                },
                expected_none_urls = {
                    "http://127.0.0.1:8085/metrics2",
                    "http://127.0.0.1:8086/metrics/1",
                },
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
    ["listen_httpd"] = {
        apply_cases = {
            {
                cfg = {
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
                            server = "additional",
                            endpoints = {
                                {
                                    path = "/metrics/1",
                                    format = "json",
                                },
                            },
                        },
                    },
                },
                expected_json_urls = {
                    "http://127.0.0.1:8081/metrics1",
                    "http://127.0.0.1:8086/metrics/1",
                },
                expected_prometheus_urls = {
                    "http://127.0.0.1:8081/metrics2"
                },
                expected_none_urls = {},
            },
            {
                cfg = {
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
                },
                expected_json_urls = {},
                expected_prometheus_urls = {
                    "http://127.0.0.1:8081/metrics1",
                },
                expected_none_urls = {
                    "http://127.0.0.1:8081/metrics2",
                    "http://127.0.0.1:8086/metrics/1",
                },
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
    ["listen_httpd_collision"] = {
        apply_cases = {
            {
                cfg = {
                    http = {
                        {
                            listen = "127.0.0.1:8081",
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
                            server = "127.0.0.1:8081",
                            endpoints = {
                                {
                                    path = "/metrics/1",
                                    format = "json",
                                },
                            },
                        },
                    },
                },
                expected_json_urls = {
                    "http://127.0.0.1:8081/metrics1",
                    "http://127.0.0.1:8087/metrics/1",
                },
                expected_prometheus_urls = {
                    "http://127.0.0.1:8081/metrics2"
                },
                expected_none_urls = {},
            },
            {
                cfg = {
                    http = {
                        {
                            listen = "127.0.0.1:8081",
                            endpoints = {
                                {
                                    path = "/metrics1",
                                    format = "prometheus",
                                },
                            },
                        },
                    },
                },
                expected_json_urls = {},
                expected_prometheus_urls = {
                    "http://127.0.0.1:8081/metrics1",
                },
                expected_none_urls = {
                    "http://127.0.0.1:8081/metrics2",
                    "http://127.0.0.1:8087/metrics/1",
                },
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
}

for name, case in pairs(test_reapply_delete_cases) do
    g["test_reapply_delete_" .. name] = function (cg)
        if case.mocks ~= nil then
            mocks.apply(case.mocks)
        end

        for _, apply_iter in ipairs(case.apply_cases) do
            cg.role.apply(apply_iter.cfg)
            for _, url in ipairs(apply_iter.expected_json_urls) do
                assert_json(url)
            end
            for _, url in ipairs(apply_iter.expected_prometheus_urls) do
                assert_prometheus(url)
            end
            for _, url in ipairs(apply_iter.expected_none_urls) do
                assert_none(url)
            end
        end

        if case.mocks~= nil then
            mocks.clear()
        end
    end
end

local test_reapply_add_cases = {
    ["listen"] = {
        apply_cases = {
            {
                cfg = {
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
                },
                expected_json_urls = {},
                expected_prometheus_urls = {
                    "http://127.0.0.1:8081/metrics1"
                },
                expected_none_urls = {
                    "http://127.0.0.1:8081/metrics2",
                    "http://127.0.0.1:8082/metrics/1",
                },
            },
            {
                cfg = {
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
                },
                expected_json_urls = {
                    "http://127.0.0.1:8081/metrics1",
                    "http://127.0.0.1:8082/metrics/1",
                },
                expected_prometheus_urls = {
                    "http://127.0.0.1:8081/metrics2",
                },
                expected_none_urls = {},
            },
        },
    },
    ["httpd"] = {
        apply_cases = {
            {
                cfg = {
                    http = {
                        {
                            endpoints = {
                                {
                                    path = "/metrics1",
                                    format = "prometheus",
                                },
                            },
                        },
                    },
                },
                expected_json_urls = {},
                expected_prometheus_urls = {
                    "http://127.0.0.1:8085/metrics1"
                },
                expected_none_urls = {
                    "http://127.0.0.1:8085/metrics2",
                    "http://127.0.0.1:8086/metrics/1",
                },
            },
            {
                cfg = {
                    http = {
                        {
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
                            server = "additional",
                            endpoints = {
                                {
                                    path = "/metrics/1",
                                    format = "json",
                                },
                            },
                        },
                    },
                },
                expected_json_urls = {
                    "http://127.0.0.1:8085/metrics1",
                    "http://127.0.0.1:8086/metrics/1",
                },
                expected_prometheus_urls = {
                    "http://127.0.0.1:8085/metrics2",
                },
                expected_none_urls = {},
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
}

for name, case in pairs(test_reapply_add_cases) do
    g["test_reapply_add_" .. name] = function (cg)
        if case.mocks ~= nil then
            mocks.apply(case.mocks)
        end

        for _, apply_iter in ipairs(case.apply_cases) do
            cg.role.apply(apply_iter.cfg)
            for _, url in ipairs(apply_iter.expected_json_urls) do
                assert_json(url)
            end
            for _, url in ipairs(apply_iter.expected_prometheus_urls) do
                assert_prometheus(url)
            end
            for _, url in ipairs(apply_iter.expected_none_urls) do
                assert_none(url)
            end
        end

        if case.mocks~= nil then
            mocks.clear()
        end
    end
end

local test_stop_cases = {
    ['listen'] = {
        cfg = {
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
        },
        expected_json_url = "http://127.0.0.1:8081/metrics1",
        expected_none_url = "http://127.0.0.1:8082/metrics/1",
    },
    ['httpd'] = {
        cfg = {
            http = {
                {
                    endpoints = {
                        {
                            path = "/metrics1",
                            format = "json",
                        },
                    },
                },
            },
        },
        mocks = {
            {
                module = "config",
                method = "get",
                implementation = config_get_return_httpd_config,
            },
        },
        expected_json_url = "http://127.0.0.1:8085/metrics1",
        expected_none_url = "http://127.0.0.1:8086/metrics/1",
    },
}

for name, case in pairs(test_stop_cases) do
    g['test_stop_' .. name] = function(cg)
        if case.mocks ~= nil then
            mocks.apply(case.mocks)
        end

        cg.role.apply(case.cfg)
        assert_json(case.expected_json_url)

        cg.role.stop()
        assert_none(case.expected_none_url)

        if case.mocks ~= nil then
            mocks.clear()
        end
    end
end

local test_endpoint_and_slashes_cases = {
    ['listen'] = {
        cfg = {
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
        },
        expected_json_urls = {
            "http://127.0.0.1:8081/endpoint",
            "http://127.0.0.1:8081/endpoint/",
            "http://127.0.0.1:8081/endpoint/2",
            "http://127.0.0.1:8081/endpoint/2/",
        },
    },
    ['httpd'] = {
        cfg = {
            http = {
                {
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
        },
        expected_json_urls = {
            "http://127.0.0.1:8085/endpoint",
            "http://127.0.0.1:8085/endpoint/",
            "http://127.0.0.1:8085/endpoint/2",
            "http://127.0.0.1:8085/endpoint/2/",
        },
        mocks = {
            {
                module = "config",
                method = "get",
                implementation = config_get_return_httpd_config,
            },
        },
    },
}

for name, case in pairs(test_endpoint_and_slashes_cases) do
    g['test_endpoint_and_slashes_test_' .. name] = function(cg)
        if case.mocks ~= nil then
            mocks.apply(case.mocks)
        end

        cg.role.apply(case.cfg)
        for _, url in pairs(case.expected_json_urls) do
            assert_json(url)
        end

        if case.mocks ~= nil then
            mocks.clear()
        end
    end
end

local test_tls_cases = {
    ["listen_tls_basic"] = {
        cfg = {
            http = {
                {
                    listen = 8081,
                    ssl_key_file = fio.pathjoin("test", "ssl_data", "server.key"),
                    ssl_cert_file = fio.pathjoin("test", "ssl_data", "server.crt"),
                    endpoints = {
                        {
                            path = "/metrics1",
                            format = "json",
                        },
                    },
                },
            },
        },
        expected_json = {
            "https://localhost:8081/metrics1",
        },
        client_tls_opts = {
            ca_file = fio.pathjoin("test", "ssl_data", "ca.crt"),
        },
    },
    ["listen_tls_encrypted_key_password_file"] = {
        cfg = {
            http = {
                {
                    listen = 8081,
                    ssl_key_file = fio.pathjoin("test", "ssl_data", "server.enc.key"),
                    ssl_cert_file = fio.pathjoin("test", "ssl_data", "server.crt"),
                    ssl_password_file = fio.pathjoin("test", "ssl_data", "passwd"),
                    endpoints = {
                        {
                            path = "/metrics1",
                            format = "json",
                        },
                    },
                },
            },
        },
        expected_json = {
            "https://localhost:8081/metrics1",
        },
        client_tls_opts = {
            ca_file = fio.pathjoin("test", "ssl_data", "ca.crt"),
        },
    },
    ["listen_tls_encrypted_key_password"] = {
        cfg = {
            http = {
                {
                    listen = 8081,
                    ssl_key_file = fio.pathjoin("test", "ssl_data", "server.enc.key"),
                    ssl_cert_file = fio.pathjoin("test", "ssl_data", "server.crt"),
                    ssl_password = "1q2w3e",
                    endpoints = {
                        {
                            path = "/metrics1",
                            format = "json",
                        },
                    },
                },
            },
        },
        expected_json = {
            "https://localhost:8081/metrics1",
        },
        client_tls_opts = {
            ca_file = fio.pathjoin("test", "ssl_data", "ca.crt"),
        },
    },
    ["listen_tls_ca"] = {
        cfg = {
            http = {
                {
                    listen = 8081,
                    ssl_key_file = fio.pathjoin("test", "ssl_data", "server.key"),
                    ssl_cert_file = fio.pathjoin("test", "ssl_data", "server.crt"),
                    ssl_ca_file = fio.pathjoin("test", "ssl_data", "ca.crt"),
                    ssl_ciphers = "ECDHE-RSA-AES256-GCM-SHA384",
                    endpoints = {
                        {
                            path = "/metrics1",
                            format = "json",
                        },
                    },
                },
            },
        },
        expected_json = {
            "https://localhost:8081/metrics1",
        },
        client_tls_opts = {
            ca_file = fio.pathjoin("test", "ssl_data", "ca.crt"),
            ssl_cert = fio.pathjoin("test", 'ssl_data', 'client.crt'),
            ssl_key = fio.pathjoin("test", 'ssl_data', 'client.key'),
        },
    },
}

for name, case in pairs(test_tls_cases) do
    g['test_tls_listen_' .. name] = function(cg)
        if case.mocks ~= nil then
            mocks.apply(case.mocks)
        end

        cg.role.apply(case.cfg)

        for _, url in pairs(case.expected_json) do
            assert_json(url, case.client_tls_opts)
        end

        if case.mocks ~= nil then
            mocks.clear()
        end
    end
end

local function assert_content_type(uri, expected_content_type, tls_opts)
    local response = http_client:get(uri, tls_opts)
    t.assert_equals(response.status, 200)
    t.assert_equals(response.headers['content-type'], expected_content_type)
end

local test_content_type_cases = {
    ['json'] = {
        cfg = {
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
        },
        expected_url = "http://127.0.0.1:8081/json_metrics",
        expected_content_type = "application/json; charset=utf-8",
    },
    ['prometheus'] = {
        cfg = {
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
        },
        expected_url = "http://127.0.0.1:8081/prometheus_metrics",
        expected_content_type = "text/plain; charset=utf8",
    },
}

for name, case in pairs(test_content_type_cases) do
    g['test_content_type_' .. name] = function(cg)
        cg.role.apply(case.cfg)
        assert_content_type(case.expected_url, case.expected_content_type)
    end
end
