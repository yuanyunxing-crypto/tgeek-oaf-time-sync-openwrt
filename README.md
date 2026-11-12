# TGEEK OAF Time Sync V2.1.1

基于原生 OAF 应用过滤插件的时间规则兼容修复层，保留原版星期排版，让每条时间段独立保存星期。

> 本项目不是 OAF 官方项目，也不替代原生 OAF 过滤引擎。实际拦截效果取决于设备上的 OAF 实现，安装后必须用测试终端验证。

## 功能

- 复用原生星期一至星期日横向复选框，不新增重复星期列。
- 每条时间记录独立保存星期、开始时间和结束时间。
- 规则保存到 `/etc/oaf-time-sync.json`。
- 通过 procd 后台服务按约 10 秒间隔同步当天规则。
- 保留原生控制器、页面和 appfilter 配置备份，提供检查与卸载恢复脚本。

## 文档

- [完整中文安装与使用说明](INSTALL-CN.md)
- [V2.1.1 源码目录](src/v2.1.1/)

## 从源码目录安装

将 `src/v2.1.1/` 中的全部文件上传到 OpenWrt 的同一个目录（例如 `/tmp/TGEEK-OAF-Time-Sync-v2.1.1`），然后执行：

```sh
cd /tmp/TGEEK-OAF-Time-Sync-v2.1.1
sh install.sh
sh verify.sh
```

安装前请确认设备已安装原生 OAF，且存在兼容的 Lua LuCI 控制器、时间页面及 appfilter ubus 接口。建议在维护窗口安装。

## 卸载与回滚

安装后执行：

```sh
sh /root/oaf-time-sync-backup/uninstall.sh
```

卸载会恢复首次安装时备份的原生 OAF 控制器、时间页面和 appfilter 配置。卸载前请先备份安装后产生的自定义配置；原始备份目录会保留。

## 验证状态

源文件来自 TGEEK OAF Time Sync V2.1.1 安装包。`verify.sh` 只能检查安装状态，不能替代真实终端的限时访问测试。当天没有匹配时间段时使用“前一天 + 全天占位时间段”的机制依赖具体 OAF 实现，必须在目标固件上验证。
