#!/bin/sh
set -eu
BACK=/root/oaf-time-sync-backup
CONTROLLER=/usr/lib/lua/luci/controller/appfilter.lua
PAGE=/usr/lib/lua/luci/view/admin_network/time.htm

[ "$(id -u)" = 0 ] || { echo '请使用 root 执行'; exit 1; }
[ -s "$BACK/appfilter.lua" ] || { echo "缺少原始控制器备份：$BACK/appfilter.lua"; exit 1; }
[ -s "$BACK/time.htm" ] || { echo "缺少原始页面备份：$BACK/time.htm"; exit 1; }
[ -s "$BACK/appfilter.config" ] || { echo "缺少原始配置备份：$BACK/appfilter.config"; exit 1; }

/etc/init.d/oaf-time-sync stop 2>/dev/null || true
/etc/init.d/oaf-time-sync disable 2>/dev/null || true
cp -p "$BACK/appfilter.lua" "$CONTROLLER"
cp -p "$BACK/time.htm" "$PAGE"
if [ -f /etc/config/appfilter ]; then
    cp -p /etc/config/appfilter "$BACK/appfilter.config.pre-uninstall.$(date +%Y%m%d%H%M%S)"
fi
cp -p "$BACK/appfilter.config" /etc/config/appfilter
rm -f /etc/oaf-time-sync.json /etc/oaf-time-sync.json.new
rm -f /etc/init.d/oaf-time-sync /usr/bin/oaf-time-sync-run
rm -f /usr/lib/lua/luci/model/oaf_time_sync.lua
rm -f /var/lock/oaf-time-sync/pid
rmdir /var/lock/oaf-time-sync 2>/dev/null || true
rm -f /tmp/luci-indexcache
rm -rf /tmp/luci-modulecache
/etc/init.d/appfilter restart
/etc/init.d/uhttpd restart 2>/dev/null || true
echo 'TGEEK OAF Time Sync 已卸载，已恢复最初备份。原始备份目录保留。请强制刷新浏览器。'
