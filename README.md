# luci-app-overlay-backup

OpenWrt/iStoreOS Overlay 文件系统备份和恢复 LuCI 插件

## 功能

- 备份 overlay 文件系统
- 备份已安装软件包列表
- 备份软件源配置
- 自动检测已挂载的存储设备
- 智能文件命名（系统版本 + 时间戳）
- 一键恢复备份
- 支持恢复后自动重启

## 安装

从 [Releases](../../releases) 或 [Actions](../../actions) 下载对应架构的 ipk 文件，然后：

```bash
opkg install luci-app-overlay-backup_*.ipk
```

## 使用

安装后访问：**系统 → Overlay Backup**

## 文件命名规则

```
{系统名}_{版本}_{修订号}_backup_{年月日时分}.tar.gz
```

示例：`iStoreOS_24.10.2_2025092610_backup_202511291430.tar.gz`

## 依赖

- luci-base
- tar
- gzip

## 支持架构

- x86-64
- rockchip-armv8
- mediatek-filogic
- ramips-mt7621

## License

GPL-3.0
