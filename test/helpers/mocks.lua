-- M is a mocks module that uses for changing methods behaviour.
-- It could be useful in unit tests when we neeed to determine
-- behaviour of methods that we don't need to test in it.
local M = {}

local validate = function(mocks)
    if type(mocks) ~= "table" then
        error("mocks should have a table type, got " .. type(mocks))
    end

    for _, mock in ipairs(mocks) do
        if type(mock.module) ~= "string" then
            error("module name should have a string type, got " .. type(mock.module))
        end
        local ok, _ = pcall(require, mock.module)
        if not ok then
            error("cannot require module " .. mock.module)
        end

        if type(mock.method) ~= "string" then
            error("method name should have a string type, got " .. type(mock.method))
        end
        if require(mock.module)[mock.method] == nil then
            error("there is no method called " .. mock.method .. " in " .. mock.module)
        end

        if type(mock.implementation) ~= "function" then
            error("implementation type should be a function, got " .. mock.implementation)
        end
    end
end

-- M.apply validates mocks, initializes it and if everything
-- is fine replaces methods from initialized list.
M.apply = function(mocks)
    validate(mocks)
    M.mocks = mocks

    for _, mock in ipairs(M.mocks) do
        mock.original_implementation = require(mock.module)[mock.method]
        require(mock.module)[mock.method] = mock.implementation
    end
end

-- M.delete returns original implementation from mocked method.
M.clear = function()
    for _, mock in ipairs(M.mocks) do
       require(mock.module)[mock.method] = mock.original_implementation
    end
end

return M
