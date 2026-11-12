# TGEEK OAF Time Sync V2.1.1

## 本次更新

- 修复时间段星期选择重复显示的问题，目标是沿用原生 OAF 星期横向排版。
- 每条时间记录独立保存星期列表。
- 增加后端保存与读回核对。
- 增加安装前检查、原始备份复用、安装失败现场回滚尝试。
- 提供检查和卸载恢复脚本。

## 发布附件

请在 GitHub Release 附件区上传以下三个文件：

1. `TGEEK-OAF-Time-Sync-v2.1.1-Linux.tar.gz` — OpenWrt/Linux 安装包。
2. `TGEEK-OAF-Time-Sync-v2.1.1-Full.zip` — 完整源码、文档及安装包合集。
3. `TGEEK-OAF-Time-Sync-V2.1.1-安装使用说明-完整版.docx` — Word 安装使用说明。

校验值见仓库根目录 `RELEASE-SHA256SUMS.txt`。

## 安装摘要

```sh
cd /tmp
tar -xzf TGEEK-OAF-Time-Sync-v2.1.1-Linux.tar.gz
cd TGEEK-OAF-Time-Sync-v2.1.1
sh install.sh
sh verify.sh
```

## 重要说明

本项目是原生 OAF 插件的兼容修复层，不是 OAF 官方项目。verify.sh 检查安装状态，不等同于真实设备限时放行/阻断验证。当天无匹配规则时的“前一天 + 全天占位”逻辑依赖目标 OAF 固件，必须实机测试。
