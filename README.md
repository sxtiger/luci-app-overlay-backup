# luci-app-overlay-backup

OpenWrt/iStoreOS Overlay 文件系统备份和恢复 LuCI 插件

## 功能特点

- **备份功能**
  - 备份 overlay 文件系统
  - 备份已安装软件包列表
  - 备份软件源配置
  - 自动检测已挂载的存储设备
  - 智能文件命名（包含系统版本和时间戳）

- **恢复功能**
  - 支持上传备份文件
  - 二次确认恢复操作
  - 自动或手动重启选项
  - 显示备份文件信息

- **其他特性**
  - 中英文多语言支持
  - 操作日志查看
  - 实时进度显示

## 依赖包

- luci-base
- luci-compat
- tar
- gzip
- block-mount

## 安装方法

### 方法一：在 OpenWrt SDK 中编译

1. 将 `luci-app-overlay-backup` 目录复制到 SDK 的 `package/` 目录下

2. 更新 feeds：
   ```bash
   ./scripts/feeds update -a
   ./scripts/feeds install -a
   ```

3. 选择软件包：
   ```bash
   make menuconfig
   # 在 LuCI -> Applications 中选择 luci-app-overlay-backup
   ```

4. 编译：
   ```bash
   make package/luci-app-overlay-backup/compile V=s
   ```

5. 在 `bin/packages/` 目录下找到生成的 ipk 文件

### 方法二：直接安装（手动部署）

如果没有 SDK 环境，可以手动部署：

1. 将 `root/` 目录下的所有文件复制到路由器对应位置
2. 将 `luasrc/` 目录下的文件复制到 `/usr/lib/lua/luci/`
3. 运行初始化脚本：
   ```bash
   sh /etc/uci-defaults/luci-app-overlay-backup
   ```
4. 重启 uhttpd 或重启路由器

## 使用说明

安装后在 LuCI 界面访问：**系统 → Overlay 备份恢复**

### 备份

1. 选择备份保存路径（支持 USB/硬盘）
2. 查看将要生成的备份文件名
3. 点击"创建备份"按钮
4. 下载生成的备份文件

### 恢复

1. 上传备份文件（或从列表选择已有备份）
2. 选择要恢复的备份文件
3. 点击"恢复所选备份"
4. 确认恢复操作（二次确认）
5. 等待系统重启

### 设置

- 默认备份路径
- 恢复后是否自动重启

## 文件命名规则

备份文件名格式：`{DISTRIB_ID}_{DISTRIB_RELEASE}_{DISTRIB_REVISION}_backup_{YYYYMMDDHHMM}.tar.gz`

示例：`iStoreOS_24.10.2_2025092610_backup_202511291430.tar.gz`

## 目录结构

```
luci-app-overlay-backup/
├── Makefile                                    # OpenWrt 构建文件
├── README.md                                   # 本文档
├── root/
│   ├── etc/
│   │   ├── config/
│   │   │   └── overlay_backup                  # UCI 配置文件
│   │   └── uci-defaults/
│   │       └── luci-app-overlay-backup         # 初始化脚本
│   └── usr/
│       ├── bin/
│       │   ├── overlay-backup.sh               # 备份脚本
│       │   └── overlay-restore.sh              # 恢复脚本
│       └── share/
│           └── rpcd/
│               └── acl.d/
│                   └── luci-app-overlay-backup.json  # ACL 权限
├── luasrc/
│   ├── controller/
│   │   └── overlay_backup.lua                  # 控制器
│   ├── model/
│   │   └── cbi/
│   │       └── overlay_backup/
│   │           └── settings.lua                # 设置页面
│   └── view/
│       └── overlay_backup/
│           ├── backup.htm                      # 备份页面
│           ├── restore.htm                     # 恢复页面
│           └── log.htm                         # 日志页面
└── po/
    ├── zh-cn/
    │   └── overlay_backup.po                   # 中文翻译
    └── en/
        └── overlay_backup.po                   # 英文翻译
```

## 许可证

GPL-3.0

## 问题反馈

如有问题，请提交 Issue。
