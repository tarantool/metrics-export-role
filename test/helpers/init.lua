local t = require("luatest")
local luatest_utils = require('luatest.utils')

local helpers = {}

local function tarantool_role_is_supported()
    local tarantool_version = luatest_utils.get_tarantool_version()
    return luatest_utils.version_ge(tarantool_version, luatest_utils.version(3, 0, 0))
end

function helpers.is_tarantool3_7_0()
    local tarantool_version = luatest_utils.get_tarantool_version()
    return luatest_utils.version_ge(tarantool_version, luatest_utils.version(3, 7, 0))
end

function helpers.skip_if_graphite_unsupported()
    t.skip_if(not helpers.is_tarantool3_7_0(), 'Only Tarantool 3.7.0 or newer supports Graphite')
end

function helpers.skip_if_unsupported()
    t.skip_if(not tarantool_role_is_supported(),
              'Tarantool role is supported only for Tarantool starting from v3.0.0')
end

return helpers
