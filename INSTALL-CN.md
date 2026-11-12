# TGEEK OAF Time Sync V2.1.1 安装使用说明

## 项目定位

本项目是基于原生 OAF 应用过滤插件的时间规则兼容修复层，不是独立过滤引擎，也不是 OAF 官方发布。实际限时行为仍由设备上的原生 appfilter 组件执行。

V2.1.1 沿用原生时间表的星期一至星期日横向复选框，不增加第二个星期列；每条时间记录独立保存自己的 `weekday_list`。

## 适用条件

- OpenWrt 或兼容衍生固件，采用传统 Lua LuCI。
- 已安装原生 OAF，且 LuCI 时间页面可正常打开。
- 存在 `/usr/lib/lua/luci/controller/appfilter.lua`。
- 存在 `/usr/lib/lua/luci/view/admin_network/time.htm`。
- ubus 对象 `appfilter` 提供 `get_app_filter_time` 和 `set_app_filter_time`。
- 原生时间表每一行的第一列有 7 个星期复选框，value 为 1、2、3、4、5、6、0。
- 使用 root 执行安装。

安装前只读检查：

```sh
test -f /usr/lib/lua/luci/controller/appfilter.lua && echo "controller OK"
test -f /usr/lib/lua/luci/view/admin_network/time.htm && echo "page OK"
lua -e "require('luci.jsonc');require('nixio.fs');require('luci.util');require('nixio')"
ubus call appfilter get_app_filter_time '{}'
```

## 安装

将 Linux 包 `TGEEK-OAF-Time-Sync-v2.1.1-Linux.tar.gz` 上传至路由器 `/tmp/`：

```sh
cd /tmp
tar -xzf TGEEK-OAF-Time-Sync-v2.1.1-Linux.tar.gz
cd /tmp/TGEEK-OAF-Time-Sync-v2.1.1
sh install.sh
sh verify.sh
```

安装器会检查 Lua 依赖和原生接口；首次安装时创建 `/root/oaf-time-sync-backup`，后续安装复用原始备份，不覆盖。安装过程中会重启 appfilter，并尝试重启 uhttpd，请在维护窗口执行。失败时安装器会尝试恢复安装前文件，但不能视为绝对保证。

安装完成后强制刷新 LuCI 的 OAF 时间配置页，确认只显示原生星期列，没有重复星期列。

## 配置时间

1. 选择 OAF 固定时间模式。
2. 每行在原生星期列独立勾选星期。
3. 设置开始和结束时间并保存。
4. 等待保存与读回核对提示。
5. 刷新页面，确认每行星期选择仍保留。

星期编号：0=周日，1=周一，…，6=周六。每条规则必须至少选择一个星期；最多 64 条；结束时间必须晚于开始时间。跨午夜请拆成两条规则，并分别指定星期。

规则文件为 `/etc/oaf-time-sync.json`。顶层 weekday_list 是各时间段星期的并集；每个 time_list 项中的 weekday_list 才是独立星期设置。

## 检查与排障

```sh
sh /tmp/TGEEK-OAF-Time-Sync-v2.1.1/verify.sh
cat /etc/oaf-time-sync.json
ubus call appfilter get_app_filter_time '{}'
pgrep -af oaf-time-sync
logread | grep -i oaf-time-sync | tail -30
```

verify.sh 只检查文件、模块、服务、JSON 语法和原生 ubus 读接口；不能证明真实拦截已经生效。请使用测试终端和短时间规则分别验证允许与阻断边界。

## 卸载恢复

先备份安装后的自定义规则及 appfilter 配置，再执行：

```sh
cp -p /etc/config/appfilter /root/appfilter-before-uninstall.conf
[ ! -f /etc/oaf-time-sync.json ] || cp -p /etc/oaf-time-sync.json /root/oaf-time-sync-before-uninstall.json
sh /root/oaf-time-sync-backup/uninstall.sh
```

卸载会恢复首次安装备份的原生控制器、时间页面和 appfilter 配置，并删除兼容层规则文件及服务。可能覆盖安装后对原生 OAF 配置所做的更改，因此务必先备份。原始备份目录会保留。

## 实现限制

当天没有匹配时间段时，后端使用“前一天 + 全天占位时间段”写入原生 OAF 接口。这依赖 OAF 对星期规则的具体解释，必须在实际固件验证。尚未在所有 OAF 分支或你的真实设备上验证实际拦截效果。
