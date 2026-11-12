local M = {}
local json = require 'luci.jsonc'
local fs = require 'nixio.fs'
local util = require 'luci.util'
local nixio = require 'nixio'

local STATE = '/etc/oaf-time-sync.json'
local LOCK = '/var/lock/oaf-time-sync'

local function copy(value)
    return json.parse(json.stringify(value))
end

local function sorted_days(value)
    if type(value) ~= 'table' then error('星期列表无效') end
    local result, seen = {}, {}
    for _, day in ipairs(value) do
        day = tonumber(day)
        if not day or day % 1 ~= 0 or day < 0 or day > 6 then
            error('星期必须为 0–6（周日为 0）')
        end
        if not seen[day] then
            seen[day] = true
            result[#result + 1] = day
        end
    end
    table.sort(result)
    return result
end

local function minute(value)
    if type(value) ~= 'string' then error('时间无效') end
    local hour, min = value:match('^(%d%d):(%d%d)$')
    hour, min = tonumber(hour), tonumber(min)
    if not hour or hour > 23 or not min or min > 59 then
        error('时间格式应为 HH:MM')
    end
    return hour * 60 + min
end

function M.validate(request)
    if type(request) ~= 'table' or tonumber(request.mode) ~= 0 then
        error('仅固定时间模式使用独立星期规则')
    end
    if type(request.time_list) ~= 'table' or #request.time_list < 1 or #request.time_list > 64 then
        error('请添加 1–64 个时间段')
    end

    local result = { mode = 0, weekday_list = {}, time_list = {} }
    local union = {}
    for _, item in ipairs(request.time_list) do
        if type(item) ~= 'table' then error('时间段格式无效') end
        local weekdays = sorted_days(item.weekday_list)
        if #weekdays == 0 then error('每段至少选择一个星期') end
        if minute(item.start) >= minute(item['end']) then
            error('结束时间须晚于开始时间；跨午夜请拆成两段')
        end
        for _, day in ipairs(weekdays) do union[day] = true end
        result.time_list[#result.time_list + 1] = {
            start = item.start,
            ['end'] = item['end'],
            weekday_list = weekdays
        }
    end
    for day = 0, 6 do
        if union[day] then result.weekday_list[#result.weekday_list + 1] = day end
    end
    return result
end

function M.compile(request, weekday)
    local ranges, seen = {}, {}
    for _, item in ipairs(request.time_list) do
        for _, day in ipairs(item.weekday_list) do
            if day == weekday then
                local key = item.start .. '-' .. item['end']
                if not seen[key] then
                    seen[key] = true
                    ranges[#ranges + 1] = { start = item.start, ['end'] = item['end'] }
                end
                break
            end
        end
    end
    table.sort(ranges, function(a, b)
        return a.start .. a['end'] < b.start .. b['end']
    end)

    if #ranges == 0 then
        -- Native OAF expects a non-empty interval list. Use yesterday as a non-matching weekday.
        return {
            mode = 0,
            weekday_list = { (weekday + 6) % 7 },
            time_list = { { start = '00:00', ['end'] = '23:59' } }
        }
    end
    return { mode = 0, weekday_list = { weekday }, time_list = ranges }
end

local function signature(value)
    local ranges = {}
    for _, item in ipairs(value.time_list or {}) do
        ranges[#ranges + 1] = tostring(item.start) .. '-' .. tostring(item['end'])
    end
    table.sort(ranges)
    return tostring(value.mode) .. '|' .. table.concat(sorted_days(value.weekday_list or {}), ',') .. '|' .. table.concat(ranges, ',')
end

local function raw_get()
    local result = util.ubus('appfilter', 'get_app_filter_time', {})
    if type(result) ~= 'table' or type(result.data) ~= 'table' then
        error('无法读取原生 appfilter 时间配置')
    end
    return result
end

local function apply(payload)
    local before = raw_get().data
    if signature(before) == signature(payload) then return true end
    local result = util.ubus('appfilter', 'set_app_filter_time', payload)
    if type(result) ~= 'table' or (result.code ~= nil and tonumber(result.code) ~= 0) then
        error('原生 appfilter 拒绝时间设置')
    end
    if signature(raw_get().data) ~= signature(payload) then
        error('原生 appfilter 读回核对失败')
    end
    return true
end

local function load_state()
    local content = fs.readfile(STATE)
    if not content then return nil end
    local decoded = json.parse(content)
    if type(decoded) ~= 'table' then error('规则文件无法解析') end
    return M.validate(decoded)
end

local function save_state(request)
    local temp = STATE .. '.new'
    assert(fs.writefile(temp, json.stringify(request)), '规则写入失败')
    assert(fs.rename(temp, STATE), '规则文件原子替换失败')
end

local function locked(callback)
    if not fs.mkdir(LOCK) then
        local owner = tonumber(fs.readfile(LOCK .. '/pid') or '')
        local stat = fs.stat(LOCK)
        local stale = owner and not nixio.kill(owner, 0)
        if not owner and stat and os.time() - stat.mtime > 30 then stale = true end
        if stale then
            fs.unlink(LOCK .. '/pid')
            fs.rmdir(LOCK)
        end
        if not stale or not fs.mkdir(LOCK) then
            return nil, '时间规则正在同步，请稍后重试'
        end
    end
    if not fs.writefile(LOCK .. '/pid', tostring(nixio.getpid())) then
        fs.rmdir(LOCK)
        return nil, '无法创建同步锁'
    end
    local ok, value = pcall(callback)
    fs.unlink(LOCK .. '/pid')
    fs.rmdir(LOCK)
    if not ok then return nil, tostring(value) end
    return value
end

function M.sync()
    return locked(function()
        local request = load_state()
        if request then apply(M.compile(request, tonumber(os.date('%w')))) end
        return true
    end)
end

function M.get()
    local result, err = locked(function()
        local request = load_state()
        if not request then return raw_get() end
        apply(M.compile(request, tonumber(os.date('%w')))
        )
        local response = raw_get()
        response.data.mode = 0
        response.data.time_list = copy(request.time_list)
        response.data.weekday_list = copy(request.weekday_list)
        response.data.time_sync_compat = 1
        return response
    end)
    return result or { code = -1, message = err }
end

function M.set(request)
    local result, err = locked(function()
        if type(request) ~= 'table' then error('提交内容无效') end
        if tonumber(request.mode) ~= 0 then
            local native = util.ubus('appfilter', 'set_app_filter_time', request)
            if type(native) ~= 'table' or (native.code ~= nil and tonumber(native.code) ~= 0) then
                error('原生时间模式保存失败')
            end
            if tonumber(raw_get().data.mode) ~= tonumber(request.mode) then
                error('模式切换读回核对失败')
            end
            if fs.access(STATE) then assert(fs.unlink(STATE), '清理固定时间规则失败') end
            return { code = 0, message = '已切换原生时间模式' }
        end

        local validated = M.validate(request)
        local before = raw_get().data
        local old_state = fs.readfile(STATE)
        local ok, why = pcall(function()
            save_state(validated)
            apply(M.compile(validated, tonumber(os.date('%w'))))
        end)
        if not ok then
            if old_state then
                fs.writefile(STATE, old_state)
            else
                fs.unlink(STATE)
            end
            local restored = pcall(apply, before)
            error(tostring(why) .. (restored and '；原生时间配置已尝试还原' or '；警告：原生配置回滚未确认'))
        end
        return { code = 0, message = '时间规则已保存，当天规则已同步并读回核对' }
    end)
    return result or { code = -1, message = err }
end

M.signature = signature
return M
