# 下一版本（尚未分配版本号）

- 发布状态：内部测试中（首个预发布版本 `v3.13.0-beta1`）
- 上一稳定版本：`v3.12.0`
- 当前 `VERSION`：`3.13.0-beta1`

## 摘要

面向内部测试的可用性打磨版本：补齐唯一遗漏的设置项持久化、窗口状态记忆、首次使用空库引导，并在设置中提供版本信息与 GitHub Issues 反馈入口。本版本以 GitHub 预发布（prerelease）形式发布 DMG，不替代 v3.12.0 稳定版。

## 用户可见更新

### 新增

- 设置新增「关于」标签页：应用图标、完整版本号（含内部构建号）、「内部测试版」标识、适用系统（macOS 14+ / Apple 芯片）与版权信息；预发布版本下显示「在 GitHub 上反馈问题」按钮，一键打开 https://github.com/jader12138/ManYu_Music/issues 。
- DMG 内测资产 `ManyuMusic-3.13.0-beta1.dmg`（GitHub 预发布版，prerelease，不计为最新正式版）。

### 改进

- 「不扫描 60 秒以下的音频」开关持久化（UserDefaults 键 `ManyuMusic.filterShortAudio`），重启后保持设置；无记录时默认关闭，与历史行为一致。
- 主窗口大小与位置记忆：NSWindow autosave（键名 `ManyuMusic.mainWindow`），启动时先恢复存档再做超屏收缩兜底；首次启动保持默认 1080×650。
- 空库引导：空资料库时首页隐藏全部为禁用态的快捷操作区；空状态卡片按钮直接弹出导入面板（新通知 `HarmonyPlayer.openImportPanel`，由 MainView 接收后调用 `LibraryStore.presentImportPanel()`），文案改为「添加音乐文件夹」「也可以把音乐文件直接拖进窗口」。

### 修复

- 暂无。

## 技术变更

- 新增通知名 `Notification.Name.openImportPanel`；`EmptyLibraryView` 改发该通知。
- `LibraryStore.filterShortAudio` 改为初始化时读 UserDefaults、`didSet` 回写。
- `AppDelegate.fitWindowsToVisibleScreen()` 增加 `setFrameUsingName` + `setFrameAutosaveName`（当前 SDK 的 `frameAutosaveName` 属性只读，必须用方法）。
- Info.plist 模板新增 `ManyuMusicReleaseName`（完整版本号）与 `NSHumanReadableCopyright`（© 2026 漫域音乐），模板版本占位同步为 3.13.0。
- `scripts/build-app.sh`：解析 `VERSION` 的 `-betaN` 后缀——`CFBundleShortVersionString` 取 `-` 前纯数字版本，完整版本号写入 `ManyuMusicReleaseName`（先删后加，幂等）。
- 新增 `AppInfo`（设置页读取 Bundle 版本信息，releaseName 含 `-` 判定为预发布）。

## 兼容性与迁移

- 仅支持 Apple 芯片（arm64）、macOS 14 及以上；与 v3.12.0 相同的 ad-hoc 签名、未公证，他机首次打开需右键 → 打开。
- 全部既有偏好与 library.json 数据兼容；新增的 UserDefaults 键在老版本上无记录时按默认值处理。

## 验证

- `swift test --disable-sandbox`：42/42 通过。
- Release 构建：CFBundleShortVersionString=3.13.0、CFBundleVersion=166、ManyuMusicReleaseName=3.13.0-beta1；`codesign --verify --deep --strict` 通过。
- 待人工验收：短音频开关重启保持、窗口位置重启恢复、空库引导直出导入面板、关于页信息与 Issues 链接。

## 已知问题与后续

- 未做 Developer ID 签名与公证，正式售卖前必须接入。
- 封面与歌词仍为内存缓存（设计如此，可再生成）。
- 根据内测反馈继续修复，正式发布时版本号定为 3.13.0。
- 继续执行一功能一分支，合并和发布完成后删除已用完的分支。

## 修订记录

暂无。
