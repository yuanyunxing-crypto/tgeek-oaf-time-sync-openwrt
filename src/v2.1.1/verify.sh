#!/bin/sh
set -eu

[ "$(id -u)" = 0 ] || { echo '请使用 root 执行'; exit 1; }
PAGE=/usr/lib/lua/luci/view/admin_network/time.htm
CONTROLLER=/usr/lib/lua/luci/controller/appfilter.lua
MODEL=/usr/lib/lua/luci/model/oaf_time_sync.lua
SERVICE=/etc/init.d/oaf-time-sync
RUNNER=/usr/bin/oaf-time-sync-run

fail() { echo "检查失败：$*" >&2; exit 1; }

echo '===== TGEEK OAF Time Sync V2.1.1 检查 ====='
[ -s "$PAGE" ] || fail "页面不存在：$PAGE"
[ -s "$CONTROLLER" ] || fail "控制器不存在：$CONTROLLER"
[ -s "$MODEL" ] || fail "后端模块不存在：$MODEL"
[ -x "$SERVICE" ] || fail "服务脚本不存在：$SERVICE"
[ -x "$RUNNER" ] || fail "后台程序不存在：$RUNNER"

grep -q 'TGEEK OAF TIME SYNC V2.1.1 BEGIN' "$PAGE" || fail '页面未检测到 V2.1.1 补丁标记'
grep -q 'oaf_time_sync' "$CONTROLLER" || fail '控制器未接入时间同步后端'

lua -e "require('luci.model.oaf_time_sync'); print('Lua 后端加载正常')" || fail 'Lua 后端加载失败'
ubus call appfilter get_app_filter_time '{}' >/dev/null || fail '原生 appfilter 时间接口不可用'

if [ -s /etc/oaf-time-sync.json ]; then
    echo '规则文件：存在'
    lua -e "local j=require('luci.jsonc'); local f=assert(io.open('/etc/oaf-time-sync.json')); local s=f:read('*a'); f:close(); assert(type(j.parse(s))=='table'); print('规则 JSON：格式正常')" || fail '规则 JSON 无法解析'
else
    echo '规则文件：尚未保存（首次安装时正常）'
fi

if [ -L /etc/rc.d/S99oaf-time-sync ]; then echo '开机启动：已启用'; else echo '开机启动：未发现启用链接'; fi
if pgrep -af '/usr/bin/oaf-time-sync-run' >/dev/null 2>&1; then echo '后台进程：运行中'; else echo '后台进程：未检测到'; fi

echo '检查完成。真实限时效果仍需使用测试终端验证。'
