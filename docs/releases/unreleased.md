# 下一版本（v3.13.0-beta2 准备中）

- 发布状态：beta2 待发布（内测反馈修复 + 歌词格式扩展）
- 已发布内测：`v3.13.0-beta1`（见下方记录）
- 上一稳定版本：`v3.12.0`
- 当前 `VERSION`：`3.13.0-beta1`

## beta2 拟并入：歌词格式扩展

修复内嵌歌词识别：此前只有 FLAC 的 Vorbis LYRICS 能被自家解析识别，MP3/MP4 的内嵌歌词需依赖 AVFoundation 兜底（实际经常读不到）。本次为 MP3 和 MP4 家族新增与 FLAC 同级的自家二进制解析，放在 AVFoundation 之前生效。

### 用户可见更新

- 内嵌歌词识别扩展到所有支持的音频格式：MP3 读取 ID3v2 USLT 帧，MP4/M4A/M4B/MOV 读取 `moov.udta.©lyr` atom；软件支持什么格式就识别什么格式的内嵌歌词，外置 `.lrc` 维持不变。

### 技术变更

- `EmbeddedMetadataReader.readLyrics` 按扩展名分发：flac/mp3/m4a/m4b/mp4/mov 各走自家解析，其余返回 nil 交 AVFoundation 兜底。
- 新增 `readMP3Lyrics`：解析 ID3v2.3/2.4 头与帧，定位 USLT，支持 UTF-8/UTF-16(BOM)/UTF-16BE/ISO-8859-1 四种文本编码。
- 新增 `readMP4Lyrics` + `scanMP4Atom`：深度优先扫描 MP4 atom 树（仅下钻 moov/udta/meta/ilst，跳过 trak 等大块），定位 `©lyr` atom 并读取 UTF-8 文本。
- 新增 `Tests/HarmonyPlayerTests/EmbeddedLyricsFormatTests.swift`（5 个用例覆盖 MP3 ID3v2.3/2.4、UTF-16-BOM、无 ID3；MP4 m4a/mp4 有/无歌词；不支持格式）。

### 兼容性与迁移

- 仅支持 Apple 芯片（arm64）、macOS 14 及以上；ad-hoc 签名、未公证。
- 单元测试：50/50 通过。
- Release 构建编译通过、签名校验通过。
- 待人工验收：含内嵌 USLT 的 MP3、含 `©lyr` 的 M4A 在歌词面板正确显示。

---

# v3.13.0-beta1 发布记录（2026-09-18 已发布）

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

- `swift test --disable-sandbox`：42/42 通过（合并结果 cdd851e 上复跑同样 42/42）。
- Release 构建：CFBundleShortVersionString=3.13.0、CFBundleVersion=169、ManyuMusicReleaseName=3.13.0-beta1；`lipo -archs` = arm64；`codesign --verify --deep --strict` 通过。
- DMG：`ManyuMusic-3.13.0-beta1.dmg`（8,762,229 字节，SHA-256 `84f8391eb41bbfd0cff0e198010062ab8f6bce852677970ceed32f8c18f820a0`），挂载校验含 app + Applications 软链、卷内 app 版本与签名通过；公开下载链接 HEAD 200、Content-Length 一致。
- GitHub Release：id 391573124，https://github.com/jader12138/ManYu_Music/releases/tag/v3.13.0-beta1 ，prerelease、make_latest=false（不顶替 v3.12.0 稳定版）；资产 id 572876043。
- v3.12.0 Release（id 391546007）正文已 PATCH 更正：仅 Apple 芯片（arm64），不支持 Intel。
- 人工验收（主人 2026-09-18 确认 OK）：短音频开关重启保持、窗口位置重启恢复、关于页信息与 Issues 入口。

## 已知问题与后续

- 未做 Developer ID 签名与公证，正式售卖前必须接入。
- 封面与歌词仍为内存缓存（设计如此，可再生成）。
- 根据内测反馈继续修复，正式发布时版本号定为 3.13.0。
- 继续执行一功能一分支，合并和发布完成后删除已用完的分支。

## 修订记录

暂无。
