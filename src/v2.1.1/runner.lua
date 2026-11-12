#!/usr/bin/lua
local module = require 'luci.model.oaf_time_sync'
local nixio = require 'nixio'
local last_error = ''
while true do
    local ok, err = module.sync()
    if not ok and err ~= last_error then
        io.stderr:write(tostring(err or 'unknown sync error') .. '\n')
        io.stderr:flush()
    end
    last_error = ok and '' or tostring(err or '')
    nixio.nanosleep(10)
end
