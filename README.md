# luci-app-overlay-backup

iStoreOS Overlay 文件系统备份和恢复 LuCI 插件（x86-64）

[本插件核心根据wukongdaily/OpenBackRestore项目](https://github.com/wukongdaily/OpenBackRestore)

## 功能

- 完整备份 overlay 文件系统（包含所有用户修改）
- 备份已安装软件包列表
- 备份软件源配置
- 自动检测已挂载的存储设备
- 智能文件命名（系统版本 + 时间戳）
- 一键恢复备份
- 支持恢复后自动重启
- 支持上传备份文件进行恢复

## 安装

从 [Releases](../../releases) 下载 ipk 文件，然后：

```bash
opkg install luci-app-overlay-backup_*.ipk
```

或者使用 wget 直接安装：

```bash
wget -O /tmp/overlay-backup.ipk <release_url>
opkg install /tmp/overlay-backup.ipk
```

## 使用

安装后访问：**系统 → Overlay Backup**

### 创建备份

1. 选择备份存储路径（默认 /tmp/upload，或选择外置存储）
2. 点击"立即创建备份"
3. 等待备份完成后下载备份文件

### 恢复备份

1. 从备份列表中选择要恢复的文件
2. 或上传之前下载的备份文件
3. 点击"恢复"按钮
4. 确认后系统将自动重启

## 文件命名规则

```
{系统名}_{版本}_{修订号}_backup_{年月日时分}.tar.gz
```

示例：`iStoreOS_24.10.2_2025092610_backup_202511291430.tar.gz`

## 备份内容

- overlay 文件系统完整内容
- 已安装软件包列表 (packages-list.txt)
- 用户安装的软件包列表 (packages-user.txt)
- 软件源配置 (distfeeds.conf)
- 系统版本信息 (openwrt_release)
- 备份元数据 (backup_meta.txt)

## 依赖

- luci-base
- tar
- gzip

## 支持架构

- x86-64 (仅)

## 兼容性

- OpenWrt 24.10.x
- iStoreOS

## 注意事项

1. 备份文件会根据 overlay 大小变化，请确保存储空间充足
2. 恢复操作会覆盖当前 overlay 内容，请谨慎操作
3. 建议恢复后重启系统以确保所有更改生效
4. 如果系统版本差异过大，恢复可能导致兼容性问题

## GitHub Actions

本项目配置了自动构建：
- 推送到 main/master 分支时自动构建
- 创建 v* 标签时自动发布到 Releases
- 手动触发工作流

### 发布新版本

```bash
git tag v1.1.0
git push origin v1.1.0
```

## License

GPL-3.0
