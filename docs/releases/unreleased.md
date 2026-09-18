# 下一版本（v3.13.0-beta2 准备中）

- 发布状态：beta2 待发布（内测反馈修复）
- 已发布内测：`v3.13.0-beta1`（见文末附录）
- 上一稳定版本：`v3.12.0`
- 当前 `VERSION`：`3.13.0-beta1`（发布 beta2 时改为 `3.13.0-beta2`）

## beta2 摘要

修复内测中发现的两个关联问题：重启后播放栏不恢复上次曲目（歌库异步加载导致恢复从未执行），以及窄窗口（840～1040pt）下播放条布局变形。

## beta2 用户可见更新（修复）

- 重启软件后底部播放栏正确恢复上次曲目、整个播放队列、播放位置与模式（beta1 中播放栏为空）。
- 窗口较窄时播放条不再变形：曲目信息区固定宽度、格式徽标紧贴歌名、播放控件居中、右侧工具对齐；宽屏（≥1040pt）保持音量滑块布局不变。
- 窗口记忆恢复的尺寸若小于最小窗口（840×520）会自动放大到合法尺寸并居中。

## beta2 技术变更

- `MainView`：在 `library.isLoading` 变 false 的回调中调用 `player.restorePlaybackState(from:)`（此前只在 `onAppear` 且库已加载时调用，而启动瞬间库必然还在加载）。
- `AudioPlayer.restorePlaybackState`：可用曲目为空时提前返回且不置位 `didAttemptPlaybackRestore`，为加载完成后的重试保留机会。
- `AudioPlayer` 新增 `init(defaults: UserDefaults = .standard)` 依赖注入，全部 UserDefaults 访问收敛到实例属性；生产路径行为不变，测试使用独立 suite 不污染真实偏好。
- 新增 `Tests/HarmonyPlayerTests/PlaybackRestoreTests.swift`（3 个用例：空库不消耗恢复机会并在二次调用时完整恢复、无队列存档退化为单曲队列、无存档保持空白）。
- `PlayerBar.compactContent` 重排：定宽 240 曲目区 + 两个 Spacer + 最大 380 居中控件 + 78 宽工具区，结构与 `wideContent` 同构。
- `AppDelegate.fitWindowsToVisibleScreen()`：恢复存档后窗口尺寸双向钳制到 [840×520, 屏幕可见区-32]；过小时居中，超屏时保持左上角锚点收缩。

## beta2 兼容性与迁移

- 仅支持 Apple 芯片（arm64）、macOS 14 及以上；ad-hoc 签名、未公证。
- beta1 已写入的播放存档（trackID/queueIDs/currentTime）在 beta2 首次启动即被正确恢复，无需用户操作。
- 单元测试：45/45 通过。
- 人工验证（2026-09-19）：窗口宽度 840/925/1040/1180pt 四档截图比对，窄宽两套播放条布局均无重叠、无异常空隙；重启后曲目「希望」与队列恢复。

---

# 附录：v3.13.0-beta1 发布记录（2026-09-18 已发布）

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

- `swift test --disable-sandbox`：42/42 通过（合并结果 cdd851e 上复跑同样 42/42）。
- Release 构建：CFBundleShortVersionString=3.13.0、CFBundleVersion=169、ManyuMusicReleaseName=3.13.0-beta1；`lipo -archs` = arm64；`codesign --verify --deep --strict` 通过。
- DMG：`ManyuMusic-3.13.0-beta1.dmg`（8,762,229 字节，SHA-256 `84f8391eb41bbfd0cff0e198010062ab8f6bce852677970ceed32f8c18f820a0`），挂载校验含 app + Applications 软链、卷内 app 版本与签名通过；公开下载链接 HEAD 200、Content-Length 一致。
- GitHub Release：id 391573124，https://github.com/jader12138/ManYu_Music/releases/tag/v3.13.0-beta1 ，prerelease、make_latest=false（不顶替 v3.12.0 稳定版）；资产 id 572876043。
- v3.12.0 Release（id 391546007）正文已 PATCH 更正：仅 Apple 芯片（arm64），不支持 Intel。
- 人工验收（主人 2026-09-18 确认 OK）：短音频开关重启保持、窗口位置重启恢复、关于页信息与 Issues 入口。

## 已知问题与后续

- 未做 Developer ID 签名与公证，正式售卖前必须接入。
- 封面与歌词仍为内存缓存（设计如此，可再生成）。
- beta2 修复 beta1 内测发现的播放恢复与窄屏播放条问题；根据后续反馈继续修复，正式发布时版本号定为 3.13.0。
- 继续执行一功能一分支，合并和发布完成后删除已用完的分支。

## 修订记录

暂无。
