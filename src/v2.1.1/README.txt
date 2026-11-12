TGEEK OAF Time Sync V2.1.1
==========================

本版本基于 V2.1.0 修复星期界面重复问题。

本次修复
--------
- 不再向时间表追加新的星期表头或星期单元格。
- 直接复用原生 OAF 时间表每条记录左侧“星期”列中的星期一至星期日复选框。
- 保留原版横向星期排版、原版表格列宽、开始时间/结束时间/删除按钮布局。
- 每条时间记录仍独立读取、保存自己的 weekday_list。
- 页面刷新后按 JSON 中每条记录的 weekday_list 恢复勾选状态。
- 如果原生每条记录的星期控件不完整，保存时明确报错，不再偷偷新增第二列。

用途
----
为原生 OAF appfilter 固定时间模式增加“每个时间段独立选择星期”的数据保存与后台同步兼容层。
不替换 OAF 核心程序，通过原生 appfilter ubus 接口同步当天规则。

适用条件
--------
- OpenWrt / 衍生固件，具备 LuCI、Lua、ubus、procd。
- 原生文件：/usr/lib/lua/luci/controller/appfilter.lua 和 /usr/lib/lua/luci/view/admin_network/time.htm。
- ubus 对象 appfilter 提供 get_app_filter_time 与 set_app_filter_time。
- 原生时间表每个时间段的第一列含 7 个星期复选框（value 为 1,2,3,4,5,6,0）。
- 页面保留原生函数 submitHandle、getTimeFormData、renderTimeData，以及 timeTableBody、start-time、end-time 等元素/类名。

安装/升级
---------
将整个目录上传到路由器，例如 /tmp/tgeek-oaf-time-sync-v211，SSH 登录 root 后执行：
  cd /tmp/tgeek-oaf-time-sync-v211
  sh install.sh
  sh verify.sh
安装器会复用 /root/oaf-time-sync-backup，不覆盖最初原始备份。

从 V2.1.0 升级
-------------
直接使用本包执行 sh install.sh。安装器先保存当前 V2.1.0 页面/控制器/服务现场作为事务回滚点，再移除旧版注入脚本并写入 V2.1.1。如果升级失败，会尝试恢复升级前现场；原始备份和 /etc/oaf-time-sync.json 规则文件保留。

规则格式
--------
每个 time_list 项包含 start、end、weekday_list。星期编号：0=周日，1=周一，...，6=周六。每段至少一个星期；结束时间必须晚于开始时间。跨午夜请拆成两段。最多 64 段。

运行机制
--------
- 规则持久化到 /etc/oaf-time-sync.json。
- procd 服务每 10 秒检查本地星期并通过 appfilter ubus 同步当天规则。
- 页面保存后调用 get 接口读回核对。
- 当天无生效时间段时，后端使用前一天作为不匹配星期的全天占位规则；该行为必须在实际 OAF 固件上验证。

回滚/卸载
---------
执行 sh /root/oaf-time-sync-backup/uninstall.sh，会恢复最初备份的控制器、页面与 /etc/config/appfilter，并移除兼容层服务与规则文件。原始备份目录保留。

重要限制与验证
--------------
本包基于用户提供的 V2.1.0 源码、原生控制器片段和界面截图制作。没有在用户的真实路由器上执行安装、ubus set 写入或实际设备限时测试。安装成功和页面读回成功不等于真实限时效果已经验证。请先使用测试终端和短时间规则验证允许/禁止边界。
