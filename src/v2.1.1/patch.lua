local root = assert(arg[1], 'package directory required')
local check_only = arg[2] == '--check'
local function read(path)
    local f = assert(io.open(path, 'rb'), 'cannot read ' .. path)
    local data = f:read('*a')
    f:close()
    return data
end
local function write(path, data)
    local f = assert(io.open(path, 'wb'), 'cannot write ' .. path)
    assert(f:write(data))
    assert(f:close())
end

local controller_path = '/usr/lib/lua/luci/controller/appfilter.lua'
local page_path = '/usr/lib/lua/luci/view/admin_network/time.htm'
local controller = read(controller_path)
local page = read(page_path)

assert(page:find('function getTimeFormData', 1, true), 'native getTimeFormData function not found')
assert(page:find('function renderTimeData', 1, true), 'native renderTimeData function not found')
assert(page:find('timeTableBody', 1, true), 'native timeTableBody not found')
assert(page:find('start-time', 1, true), 'native start-time field not found')
assert(page:find('end-time', 1, true), 'native end-time field not found')

local set_start = assert(controller:find('function set_app_filter_time%s*%('), 'native set_app_filter_time handler not found')
local get_start = assert(controller:find('function get_dev_visit_time%s*%(', set_start), 'next native controller handler not found')
local replacement = [[function set_app_filter_time()
    local json = require 'luci.jsonc'
    luci.http.prepare_content('application/json')
    local req = json.parse(luci.http.formvalue('data') or '')
    if type(req) ~= 'table' then
        luci.http.write_json({ code = -1, message = '提交内容无效' })
        return
    end
    luci.http.write_json(require('luci.model.oaf_time_sync').set(req))
end

function get_app_filter_time()
    luci.http.prepare_content('application/json')
    luci.http.write_json(require('luci.model.oaf_time_sync').get())
end

]]
controller = controller:sub(1, set_start - 1) .. replacement .. controller:sub(get_start)
assert(loadstring(controller), 'patched controller syntax invalid')

local anchor = '//]]></script>'
local marker_list = {
    '/* TGEEK OAF TIME SYNC V2.1.1 BEGIN */',
    '/* TGEEK OAF TIME SYNC V2.1 BEGIN */',
    '/* TGEEK OAF INDEPENDENT WEEKDAYS V2 */',
    '/* T GEEK OAF TIME COMPAT V1 */'
}
for _, marker in ipairs(marker_list) do
    local marker_pos = page:find(marker, 1, true)
    if marker_pos then
        local close_pos = assert(page:find(anchor, marker_pos, true), 'old injected script closing anchor not found')
        page = page:sub(1, marker_pos - 1) .. page:sub(close_pos)
    end
end
local close_pos = assert(page:find(anchor, 1, true), 'native page script closing anchor not found')
local frontend = read(root .. '/frontend.js')
page = page:sub(1, close_pos - 1) .. '\n' .. frontend .. '\n' .. page:sub(close_pos)

if check_only then
    assert(loadstring(controller), 'controller compile check failed')
    assert(page:find('TGEEK OAF TIME SYNC V2.1.1 BEGIN', 1, true), 'frontend marker missing')
    io.write('Patch preflight OK\n')
    return
end

write(controller_path .. '.oaf-v211-new', controller)
write(page_path .. '.oaf-v211-new', page)
assert(os.rename(controller_path .. '.oaf-v211-new', controller_path), 'controller atomic replace failed')
assert(os.rename(page_path .. '.oaf-v211-new', page_path), 'page atomic replace failed')
io.write('LuCI controller and time page patched\n')
