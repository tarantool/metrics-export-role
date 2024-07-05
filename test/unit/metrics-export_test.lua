local t = require('luatest')
local helpers = require('test.helper')

local g = t.group('metrics_export_unit_test')

g.before_all(function()
    t.skip_if(not helpers.tarantool_role_is_supported(),
             'Tarantool role is supported only for Tarantool starting from v3.0.0')
    g.default_cfg = { }
end)

g.before_each(function()
    g.role = require('roles.metrics-export')
end)

g.after_each(function()
    g.role.stop()
end)

function g.test_dummy()
    t.assert_equals(g.role.validate(), nil)
end
