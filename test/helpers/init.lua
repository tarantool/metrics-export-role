local t = require("luatest")

local helpers = {}

local function tarantool_version()
    local major_minor_patch = _G._TARANTOOL:split('-', 1)[1]
    local major_minor_patch_parts = major_minor_patch:split('.', 2)

    local major = tonumber(major_minor_patch_parts[1])
    local minor = tonumber(major_minor_patch_parts[2])
    local patch = tonumber(major_minor_patch_parts[3])

    return major, minor, patch
end

local function tarantool_role_is_supported()
    local major, _, _ = tarantool_version()
    return major >= 3
end

function helpers.skip_if_unsupported()
    t.skip_if(not tarantool_role_is_supported(),
              'Tarantool role is supported only for Tarantool starting from v3.0.0')
end

return helpers
