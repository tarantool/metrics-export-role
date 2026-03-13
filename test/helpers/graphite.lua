local checks = require('checks')
local socket = require('socket')

local M = {}

-- Default values
local DEFAULT_PREFIX = 'tarantool'
local DEFAULT_HOST = '127.0.0.1'
local DEFAULT_PORT = 2003
local DEFAULT_SEND_INTERVAL = 2

M.count_graphite_frames = function (prefix, host, port, send_interval)
    checks('?string', '?string', '?number', '?number')

    prefix = prefix or DEFAULT_PREFIX
    host = host or DEFAULT_HOST
    port = port or DEFAULT_PORT
    send_interval = send_interval or DEFAULT_SEND_INTERVAL

    -- Create socket to recieve data from the role.
    local sock = socket('AF_INET', 'SOCK_DGRAM', 'udp')
    sock:bind(host, port)

    sock:readable(send_interval * 2)

    local frame_counter = 0

    -- It’s not very clear how to keep the check simple and clear here. So we
    -- just took lines in `graphite` format, and check that:
    -- 1) metric name contains a valid prefix
    -- 2) metric value is not missing
    -- 3) metric timestamp is greater than 0.
    while true do
        local graphite_obs = sock:recvfrom()
        if graphite_obs == nil then
            break
        end

        local obs_table = graphite_obs:split(' ')

        if string.find(obs_table[1], prefix) and (obs_table[2] ~= nil) and (tonumber(obs_table[3]) > 0) then
            frame_counter = frame_counter + 1
        end
    end

    sock:close()

    return frame_counter
end

return M
