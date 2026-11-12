#!/bin/sh
set -eu

BASE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
BACK=/root/oaf-time-sync-backup
TXN=/tmp/oaf-time-sync-txn.$$
CONTROLLER=/usr/lib/lua/luci/controller/appfilter.lua
PAGE=/usr/lib/lua/luci/view/admin_network/time.htm
MODEL_DIR=/usr/lib/lua/luci/model
SERVICE=/etc/init.d/oaf-time-sync
RUNNER=/usr/bin/oaf-time-sync-run
MODEL=$MODEL_DIR/oaf_time_sync.lua

say() { printf '%s\n' "$*"; }
fail() { say "错误：$*" >&2; exit 1; }

[ "$(id -u)" = 0 ] || fail '请使用 root 执行安装器'
[ -f "$CONTROLLER" ] || fail "找不到原生控制器：$CONTROLLER"
[ -f "$PAGE" ] || fail "找不到原生时间页面：$PAGE"
command -v lua >/dev/null 2>&1 || fail '缺少 Lua'
command -v ubus >/dev/null 2>&1 || fail '缺少 ubus'

lua -e "require('luci.jsonc');require('nixio.fs');require('luci.util');require('nixio')" || fail '缺少 LuCI Lua 运行依赖'
lua -e "assert(loadfile('$BASE/oaf_time_sync.lua')); assert(loadfile('$BASE/patch.lua')); print('Lua syntax OK')" || fail 'Lua 源码语法检查失败'
sh -n "$BASE/uninstall.sh" || fail '卸载脚本语法错误'
ubus call appfilter get_app_filter_time '{}' >/dev/null 2>&1 || fail '原生 appfilter 时间接口不可用'

# 原始备份只创建一次；已有备份必须完整，绝不覆盖。
if [ ! -e "$BACK" ]; then
    BACK_TMP="$BACK.new.$$"
    rm -rf "$BACK_TMP"
    mkdir -m 700 "$BACK_TMP"
    cp -p "$CONTROLLER" "$BACK_TMP/appfilter.lua"
    cp -p "$PAGE" "$BACK_TMP/time.htm"
    cp -p /etc/config/appfilter "$BACK_TMP/appfilter.config"
    cp -p "$BASE/uninstall.sh" "$BACK_TMP/uninstall.sh"
    mv "$BACK_TMP" "$BACK"
    say "已创建原始备份：$BACK"
else
    [ -s "$BACK/appfilter.lua" ] || fail '已有备份缺少 appfilter.lua，拒绝覆盖'
    [ -s "$BACK/time.htm" ] || fail '已有备份缺少 time.htm，拒绝覆盖'
    [ -s "$BACK/appfilter.config" ] || fail '已有备份缺少 appfilter.config，拒绝覆盖'
    say "复用现有原始备份：$BACK"
fi
[ -f "$BACK/uninstall.sh" ] || cp -p "$BASE/uninstall.sh" "$BACK/uninstall.sh"

# 事务备份当前现场，用于安装失败时回到安装前状态（包括旧 V2）。
rm -rf "$TXN"
mkdir -m 700 "$TXN"
cp -p "$CONTROLLER" "$TXN/appfilter.lua"
cp -p "$PAGE" "$TXN/time.htm"
[ ! -e "$MODEL" ] || { cp -p "$MODEL" "$TXN/model.lua"; touch "$TXN/had-model"; }
[ ! -e "$SERVICE" ] || { cp -p "$SERVICE" "$TXN/service"; touch "$TXN/had-service"; }
[ ! -e "$RUNNER" ] || { cp -p "$RUNNER" "$TXN/runner"; touch "$TXN/had-runner"; }
[ ! -L /etc/rc.d/S99oaf-time-sync ] || touch "$TXN/had-enabled"
for proc in /proc/[0-9]*; do
    [ -r "$proc/cmdline" ] || continue
    cmdline=$(tr '\000' ' ' < "$proc/cmdline" 2>/dev/null || true)
    case "$cmdline" in *'/usr/bin/oaf-time-sync-run'*) touch "$TXN/had-running"; break ;; esac
done

rollback() {
    rc=$?
    trap - 0
    say '安装未完成，正在恢复安装前现场……'
    /etc/init.d/oaf-time-sync stop >/dev/null 2>&1 || true
    cp -p "$TXN/appfilter.lua" "$CONTROLLER" 2>/dev/null || true
    cp -p "$TXN/time.htm" "$PAGE" 2>/dev/null || true
    if [ -f "$TXN/had-model" ]; then cp -p "$TXN/model.lua" "$MODEL"; else rm -f "$MODEL"; fi
    if [ -f "$TXN/had-service" ]; then cp -p "$TXN/service" "$SERVICE"; else rm -f "$SERVICE"; fi
    if [ -f "$TXN/had-runner" ]; then cp -p "$TXN/runner" "$RUNNER"; else rm -f "$RUNNER"; fi
    if [ -f "$TXN/had-enabled" ]; then /etc/init.d/oaf-time-sync enable >/dev/null 2>&1 || true; else /etc/init.d/oaf-time-sync disable >/dev/null 2>&1 || true; fi
    rm -f /tmp/luci-indexcache
    rm -rf /tmp/luci-modulecache
    /etc/init.d/appfilter restart >/dev/null 2>&1 || true
    if [ -f "$TXN/had-running" ]; then /etc/init.d/oaf-time-sync start >/dev/null 2>&1 || true; fi
    rm -rf "$TXN"
    say "已尝试恢复安装前状态。原始备份仍保留在 $BACK"
    exit "$rc"
}
trap rollback 0

/etc/init.d/oaf-time-sync stop >/dev/null 2>&1 || true
mkdir -p "$MODEL_DIR"
lua "$BASE/patch.lua" "$BASE" --check
cp "$BASE/oaf_time_sync.lua" "$MODEL"
chmod 644 "$MODEL"
lua "$BASE/patch.lua" "$BASE"
cp "$BASE/runner.lua" "$RUNNER"
chmod 755 "$RUNNER"
cp "$BASE/oaf-time-sync.init" "$SERVICE"
chmod 755 "$SERVICE"

# 检查模块加载与原生读接口；无规则文件时不改变原生规则。
lua -e "local m=require('luci.model.oaf_time_sync'); local r=m.get(); assert(type(r)=='table'); print('backend readback OK')"
/etc/init.d/oaf-time-sync enable
/etc/init.d/oaf-time-sync start
sleep 2
service_found=0
for proc in /proc/[0-9]*; do
    [ -r "$proc/cmdline" ] || continue
    cmdline=$(tr '\000' ' ' < "$proc/cmdline" 2>/dev/null || true)
    case "$cmdline" in *'/usr/bin/oaf-time-sync-run'*) service_found=1; break ;; esac
done
[ "$service_found" -eq 1 ] || fail '后台同步服务未能启动'
rm -f /tmp/luci-indexcache
rm -rf /tmp/luci-modulecache
/etc/init.d/appfilter restart
/etc/init.d/uhttpd restart 2>/dev/null || true

trap - 0
rm -rf "$TXN"
say 'TGEEK OAF Time Sync V2.1.1 安装完成。'
say '原始备份：/root/oaf-time-sync-backup'
say '卸载恢复：sh /root/oaf-time-sync-backup/uninstall.sh'
say '请强制刷新浏览器，再逐段设置星期并保存。'
