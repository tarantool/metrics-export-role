local graphite_helpers = require('test.helpers.graphite')
local metrics = require('metrics')

local t = require('luatest')
local g = t.group()

g.before_all(function(cg)
    cg.role = require('roles.metrics-export')
end)

g.before_each(function(cg)
    -- Add custom metric.
    cg.counter = metrics.counter('some_counter')
    cg.counter:inc(1, {label = 'ANY'})
end)

g.after_each(function(cg)
    cg.role.stop()

    -- Unregister custom metric.
    metrics.registry:unregister(cg.counter)
end)

local test_graphite_server_cases = {
    ["default"] = {
        cfg = {
            graphite = {},
        },
    },
    ["custom"] = {
        cfg = {
            graphite = {
                {
                    prefix = "master",
                    host = "127.0.0.1",
                    port = 3333,
                    send_interval = 1,
                },
            },
        },
    },
    ["array"] = {
        cfg = {
            graphite = {
                {
                    prefix = "master",
                    host = "127.0.0.1",
                    port = 3333,
                    send_interval = 1,
                },
                {
                    prefix = "tarantool",
                    host = "127.0.0.1",
                    port = 4444,
                    send_interval = 1,
                },
            },
        },
    },
}

for name, case in pairs(test_graphite_server_cases) do
    g['test_graphite_server_' .. name] = function(cg)
        cg.role.apply(case.cfg)

        for i in pairs(case.cfg.graphite) do
            t.assert_ge(graphite_helpers.count_graphite_frames(
                case.cfg.graphite[i].prefix, case.cfg.graphite[i].host,
                case.cfg.graphite[i].port, case.cfg.graphite[i].send_interval),
                1)
        end
    end
end

local test_graphite_invalid_cases = {
    ["cfg_number"] = {
        cfg = {
            graphite = 123,
        },
        err = "graphite configuration must be a table, got number"
    },
    ["cfg_map"] = {
        cfg = {
            graphite = {
                [1] = "first",
                ["space key"] = "space value"
            },
        },
        err = "graphite configuration must be an array, not a map"
    },
    ["invalid_prefix"] = {
        cfg = {
            graphite = {
                {
                    prefix = 123456,
                    host = "127.0.0.1",
                    port = 3333,
                    send_interval = 1,
                },
            },
        },
        err = "graphite 'prefix' must be a 'string', got number"
    },
    ["invalid_host"] = {
        cfg = {
            graphite = {
                {
                    prefix = "master",
                    host = 123,
                    port = 3333,
                    send_interval = 1,
                },
            },
        },
        err = "graphite 'host' must be a 'string', got number"
    },
    ["invalid_port"] = {
        cfg = {
            graphite = {
                {
                    prefix = "master",
                    host = "127.0.0.1",
                    port = "3333",
                    send_interval = 1,
                },
            },
        },
        err = "graphite 'port' must be a 'number', got string"
    },
    ["invalid_send_interval"] = {
        cfg = {
            graphite = {
                {
                    prefix = "master",
                    host = "127.0.0.1",
                    port = 3333,
                    send_interval = "1",
                },
            },
        },
        err = "graphite 'send_interval' must be a 'number', got string"
    },
}

for name, case in pairs(test_graphite_invalid_cases) do
    g['test_graphite_invalid_' .. name] = function(cg)
        local ok, err = pcall(cg.role.apply, case.cfg)

        t.assert_str_contains(err, case.err)
        t.assert_not(ok)
    end
end

local test_graphite_reapply_cases = {
    ["prefix_change"] = {
        apply_cases = {
            {
                cfg = {
                    graphite = {
                        {
                            prefix = "master",
                            host = "127.0.0.1",
                            port = 3333,
                            send_interval = 1,
                        },
                    },
                },
            },
            {
                cfg = {
                    graphite = {
                        {
                            prefix = "tarantool",
                            host = "127.0.0.1",
                            port = 3333,
                            send_interval = 1,
                        },
                    },
                },
            },
        },
    },
    ["add_new_server"] = {
        apply_cases = {
            {
                cfg = {
                    graphite = {
                        {
                            prefix = "master",
                            host = "127.0.0.1",
                            port = 3333,
                            send_interval = 1,
                        },
                    },
                },
            },
            {
                cfg = {
                    graphite = {
                        {
                            prefix = "master",
                            host = "127.0.0.1",
                            port = 3333,
                            send_interval = 1,
                        },
                        {
                            prefix = "tarantool",
                            host = "127.0.0.1",
                            port = 4444,
                            send_interval = 1,
                        },
                    },
                },
            },
        },
    },
    ["remove_server"] = {
        apply_cases = {
            {
                cfg = {
                    graphite = {
                        {
                            prefix = "master",
                            host = "127.0.0.1",
                            port = 3333,
                            send_interval = 1,
                        },
                        {
                            prefix = "tarantool",
                            host = "127.0.0.1",
                            port = 4444,
                            send_interval = 1,
                        },
                    },
                },
            },
            {
                cfg = {
                    graphite = {
                        {
                            prefix = "master",
                            host = "127.0.0.1",
                            port = 3333,
                            send_interval = 1,
                        },
                    },
                },
                stopped = {
                    graphite = {
                        {
                            prefix = "tarantool",
                            host = "127.0.0.1",
                            port = 4444,
                            send_interval = 1,
                        },
                    },
                },
            },
        },
    },
}

for name, case in pairs(test_graphite_reapply_cases) do
    g["test_graphite_reapply_" .. name] = function (cg)
        for _, apply_iter in ipairs(case.apply_cases) do
            cg.role.apply(apply_iter.cfg)

            for i in pairs(apply_iter.cfg.graphite) do
                t.assert_equals(graphite_helpers.count_graphite_frames(
                    apply_iter.cfg.graphite[i].prefix, apply_iter.cfg.graphite[i].host,
                    apply_iter.cfg.graphite[i].port, apply_iter.cfg.graphite[i].send_interval),
                    1)
            end

            if apply_iter.stopped ~= nil then
                for i in pairs(apply_iter.stopped.graphite) do
                    t.assert_equals(graphite_helpers.count_graphite_frames(
                        apply_iter.stopped.graphite[i].prefix, apply_iter.stopped.graphite[i].host,
                        apply_iter.stopped.graphite[i].port, apply_iter.stopped.graphite[i].send_interval),
                        0)
                end
            end
        end
    end
end


local test_graphite_stop_cases = {
    ["one_server"] = {
        apply_cases = {
            {
                cfg = {
                    graphite = {
                        {
                            prefix = "master",
                            host = "127.0.0.1",
                            port = 3333,
                            send_interval = 1,
                        },
                    },
                },
            },
        },
    },
    ["two_servers"] = {
        apply_cases = {
            {
                cfg = {
                    graphite = {
                        {
                            prefix = "master",
                            host = "127.0.0.1",
                            port = 3333,
                            send_interval = 1,
                        },
                        {
                            prefix = "tarantool",
                            host = "127.0.0.1",
                            port = 4444,
                            send_interval = 1,
                        },
                    },
                },
            },
        },
    },
}

for name, case in pairs(test_graphite_stop_cases) do
    g["test_graphite_stop_" .. name] = function (cg)
        for _, apply_iter in ipairs(case.apply_cases) do
            cg.role.apply(apply_iter.cfg)

            for i in pairs(apply_iter.cfg.graphite) do
                t.assert_ge(graphite_helpers.count_graphite_frames(
                    apply_iter.cfg.graphite[i].prefix, apply_iter.cfg.graphite[i].host,
                    apply_iter.cfg.graphite[i].port, apply_iter.cfg.graphite[i].send_interval),
                    1)
            end

            cg.role.stop()

            for i in pairs(apply_iter.cfg.graphite) do
                t.assert_equals(graphite_helpers.count_graphite_frames(
                    apply_iter.cfg.graphite[i].prefix, apply_iter.cfg.graphite[i].host,
                    apply_iter.cfg.graphite[i].port, apply_iter.cfg.graphite[i].send_interval),
                    0)
            end
        end
    end
end