# 下一版本（v3.13.0 正式版或后续 beta 准备中）

- 发布状态：截至 2026-09-20 的三轮 UI/默认主题改动已随 **`v3.13.0-beta3`** 内测预发布版发布（GitHub Releases，prerelease，不顶替 3.12.0 稳定版）；`CHANGELOG.md` 已归档 beta3 区块，本文件保留过程摘要。beta3 之后的封面包边与图标尺寸标准化已本地合并，等待下一次发版。
- 已发布内测：`v3.13.0-beta1`、`v3.13.0-beta2`、`v3.13.0-beta3`（见文末附录）
- 上一稳定版本：`v3.12.0`
- 当前 `VERSION`：`3.13.0-beta3`

## 本轮摘要（2026-09-20，分支 `codex/equalizer`，待合并）

均衡器参考 MoeKoe EQ 插件全面重做：升级为 31 段参数均衡器（20Hz~20kHz ISO 三分之一倍频程，±6dB，每段 Q 值 0.1~18 独立可调默认 1.4），页面为「头部（标题/运行状态灯/关闭EQ/重置）+ 三页签（均衡器/音效增强/高级功能，后两个占位）+ 实时频谱 + 预设 chips + 31 根垂直滑杆（双击归零）」结构；内置 35 个预设曲线（取自参考项目）+ 自定义预设；旧版十段曲线与自定义预设按对数频率轴插值迁移。入口两处：播放栏「定时」左侧快捷图标（弹窗带关闭钮）与设置独立「均衡器」页。

- **DSP**：RBJ biquad 级联——最低频段 low shelf、最高频段 high shelf、中间 29 段 peaking（各段独立 Q）；0 dB 段使用恒等系数直通。`EQTapContext` 每个 tap 持有独立延迟状态（转置直接 II 型，声道×段），共享 `Equalizer` 参数（NSLock 保护），`revision` 号变化时在音频线程重建一次系数并清零状态；增益与 Q 变化都推进 revision。
- **tap 常驻**：音频 tap 不再随 EQ 开关挂/摘，四条 item 创建路径（cut 切歌、crossfade 新曲、gapless 预载、重启恢复）一律 `EQTap.attach`；EQ 关闭时 process 直通（`isBypassed` 锁内镜像，不碰 UserDefaults），频谱喂送恒定进行，开关即时生效。
- **实时频谱**：`EQSpectrumRing`（16384 样本环形缓冲 + NSLock，音频线程写入下混单声道、prepare 时写入采样率）→ `EQSpectrumAnalyzer`（主线程 30fps 定时器，4096 点 Hann 加窗 + vDSP 实数 FFT，20Hz~20kHz 对数频轴 64 点峰值聚合，dB 归一化 + 快攻慢放平滑，暂停时谱线衰减归零；相位每 tick 缓慢推进驱动水波基线）→ `EQSpectrumView` Canvas 绘制：Catmull-Rom 平滑波浪线 + 渐变填充 + 缓慢起伏水波基线（静默时也有波浪感）+ 相位错开的回声波 + 频率刻度。纯本地 Accelerate/vDSP 计算。
- **UI**：`EqualizerPanelView` 整页重做——头部（标题 + 状态指示灯 + 关闭EQ/开启EQ + 重置 + 弹窗关闭钮）、Layout 协议 `FlowLayout` 预设 chips（选中高亮、+ 保存预设、自定义预设删除）、自绘 `EQVerticalSlider`（中心 0dB 基线、0.5 步进、双击归零）、`EQBandColumn`（增益值 + Q 值点击弹编辑滑杆 + 斜排频率标签）；「音效增强」「高级功能」页签为占位文案。播放栏弹窗宽 540，设置页整页嵌入。
- **迁移**：旧十段增益（31/62/125/250/500/1k/2k/4k/8k/16Hz）与新自定义预设在对数频率轴上线性插值为 31 段并回写；Q 值为新键（默认 1.4×31）。
- **验证**：`swift test` 68/68 通过（EQ 相关 12 项：默认/Q 镜像/钳制/重置/恒等/全预设稳定性/自定义存取/预设持久化/十段迁移/旧预设迁移/频谱环形缓冲）；release 构建通过。频谱观感与 31 段听感待主人验收。

## 本轮摘要（2026-09-20，分支 `codex/gapless-crossfade`，待合并）

播放核心新增两个可开关的连播增强，默认都关闭，关闭时播放链路与历史完全一致。技术上把单一 `AVPlayer` 扩展为「双引擎乒乓」：`engineA/engineB` 两个固定 `AVPlayer`，`activeEngine` 为当前出声引擎、`standbyEngine` 为备用，所有既有内部代码通过计算属性 `player` 仍访问当前引擎；实际音量 = 用户音量 × 每引擎 `gain`（0...1）。

- **Crossfade**：正在播放时切歌走 `beginCrossfade`——旧引擎保持出声、新曲在备用引擎从 gain 0 起播，30fps smoothstep ramp（时长由设置 3~12s，默认 6）令旧 1→0、新 0→1；UI（封面/歌名/歌词）立即切新曲，周期时间观察器重绑到新引擎使进度条从 0 走新曲。`fadeGeneration` 代数号支持在淡变中途再次切歌（以各引擎瞬时增益为新 ramp 起点，旧 ramp 自动作废）。暂停、seek、cut 切换、改播放模式、队列增删移动都会 `abortInFlightFade`/`disarmGapless` 立即收敛到单引擎。暂停时切歌、首播、连续快切（<0.7s）不走淡变。
- **Gapless**：crossfade 关闭且 gapless 开启时，周期 tick 在结尾前 2s 把下一首装入备用引擎并 `preroll(atRate:1)`，同时在当前引擎注册 `addBoundaryTimeObserver`（结尾前 60ms）；boundary 触发时备用引擎 `play()` 接管、翻转 active、重绑时钟，旧引擎自然走完最后约 60ms 后于 0.5s 延迟清理。预载未就绪则回退普通自动连播。boundary observer 记录所属引擎，保证只在同一 player 上移除。
- 自动连播候选由 `nextAutoPlaybackIndex()` 统一计算（随机/顺序/列表循环；列表结束且循环关闭返回 nil 交由原结束通知停止）；单曲循环（`repeatMode == .one`）完全不预载，仍走 seek(0) 重播。crossfade 与 gapless 同开时自动连播走 crossfade（主人确认 crossfade 优先）。
- 设置：`SettingsView.playbackPane` 新增两个开关与 crossfade 时长滑块；UserDefaults 键 `ManyuMusic.gaplessPlayback`、`ManyuMusic.crossfadeEnabled`（均默认 false）、`ManyuMusic.crossfadeDuration`（默认 6）。
- 验证：`swift test` 53/53 通过（默认关闭，cut 路径行为不变）；release 构建通过。待主人试听确认 gapless 衔接与 crossfade 时长/手感。

## 本轮摘要（2026-09-20 本地合并，分支 `codex/dock-badge-crossfade`）

Dock 专辑封面模式的播放/暂停蓝白徽标往左上内收（右/底边距 16/6→34/24，512 画布单位），完全退入亚克力底板；播放页封面切歌改方向性转场——新封面从旧封面后面顶出（上浮 14pt + 放大 5% + 淡入，zIndex 在后），旧封面在前景向左滑 36pt 并淡出（zIndex 在前），固定尺寸 ZStack 不推动布局，0.5s easeOut，遵循 reduceMotion。

## 本轮摘要（2026-09-20 本地合并，分支 `codex/artwork-acrylic-border` + `codex/icon-size-standard`）

播放条左下角封面加亚克力包边（hero 同款 ultraThinMaterial，外框 54/封面 48，0.6pt 灰发丝线+轻阴影，不参与播放页转场）；Dock 三种状态图标（白色/黑色/专辑封面）与启动台图标统一缩到 macOS 标准网格占比（内容 87.5%→80.5%，1024 母版留 10% 透明边，PNG/icns 重新生成；封面模式 512 渲染整体缩到 440 居中），与系统其他 App 图标同档。纯资源与展示层改动。

## 本轮摘要（2026-09-20 合并，分支 `codex/heart-format-colors`）

三处「我喜欢」爱心选中色统一为玫红（`hpPink`）；文件格式徽标按容器格式分色（FLAC 金 / MP3 蓝 / MP4 家族淡红等，未识别回退灰），底部播放条、歌曲列表、歌曲信息页三处统一；底部播放条格式徽标移到歌名正后方并下移居中，曲目区封面与文字整体略放大（封面 48pt、歌名 12pt、歌手名 11pt）、整体右移 20pt；新增 `ArtworkLayout.cornerRadius(for:)` 把 7:48 圆角比例推广到除播放页大封面与艺术家圆形头像外的全部专辑封面（含悬停遮罩与空态占位）。纯展示层改动，未触碰播放逻辑。

## 本轮摘要（2026-09-20 合并，分支 `codex/default-light-theme`）

软件默认主题从「夜间模式」改为「跟随系统」，并将 `AppIcon` 资源对齐白色版（`AppIconLight`），使首次安装呈现白色（白天）模式、DMG 图标永远白色、Dock 图标与界面随系统外观切换。纯默认值与资源对齐改动，未触碰播放逻辑与既有图标切换流程。

## 本轮摘要（2026-09-20 合并，分支 `codex/playback-ui-polish`）

主页进播放页的交互优化 + 播放页底部渐变色效果调整；均为 UI 层改动，未触碰任何播放逻辑（AudioPlayer / PlaybackClock / LyricsCache / 队列 / seek / 恢复均未受影响）。

## 用户可见更新

### 新增

- 主页底部播放条整条空白区域均可点击进入播放页：除播放/暂停、循环模式、上一首/下一首、收藏、音量、睡眠定时、队列等已有具体功能的控件以外，曲目区、Spacer、padding 与进度条之外的空白处点击都会触发进入播放页；封面按钮原入口保留不变。
- 播放页底部渐变色效果调整：
  - 颜色更重：深色模式主色不透明度 0.58 → 0.82，副色 0.34 → 0.55，新增第三色（accent）层 0.46；浅色模式相应加深；模糊背景图层与两枚光斑 opacity 同步上调。
  - 抽取的颜色样本更多：封面缩略图改为按 3×3 网格分块，每块独立做饱和度加权平均得到区域代表色；`secondary` 与 `accent` 不再只是 `primary` 旋转色相派生，而是从九宫格里挑选与 `primary` 色相距离最大、饱和度合理的真实区域色（单色封面回退派生保持兼容）。
  - 渐变色动起来：动画 duration 从 40~90 秒缩到 9~16 秒，肉眼可见；各层节奏错相（9/11/13/16s）配合偏移与不对称角度，背景扫动不再呈现机械的左右对称。
  - 设置 → 播放新增「播放页背景动画」开关：关闭时背景渐变完全静止；开启时按上述节奏缓慢扫动（reduceMotion 用户始终关闭，开关无效）。

## 技术变更

- `PlayerBar.body`：最外层 `Group` 上加 `.contentShape(Rectangle()).onTapGesture`，触发进入播放页；SwiftUI 中 Button/IconButton/Menu/进度条 DragGesture 都会先吞掉点击，因此空白处才会落到这一层。`onNowPlayingEntrySelected()` 与 `showNowPlaying = true` 调用复用既有入口标记，大封面 matched geometry 来源仍是 `.playerBar`。
- `ArtworkPaletteExtractor`：新增 `regionSamples(pixels:width:height:)` 把 32×32 缩略图按 3×3 网格分块采样；`pickSecondary`/`pickAccent` 在九宫格区域色里按色相距离挑选真实区域色，回退时仍走原 `adjusted` hueShift 派生；`ArtworkPalette` 结构与 `palette(from:)` 签名不变，所有调用方（`DockArtworkController`、`AudioPlayer`、`AppTheme`、`HomeView`、`NowPlayingView`）零改动兼容。
- `NowPlayingBackdrop`：渐变层从两色扩为三色 + navy 兜底，opacity 上调；动画 duration 改为 9/11/13/16s 各自 `repeatForever(autoreverses: true)`；新增第二层 accent 色 `RadialGradient` 不对称偏移与节奏；`@AppStorage(BackdropAnimation.enabledKey)` 控制开关，关闭时 drift 全置 false 且 `animation` 传 nil，整个背景冻结。
- `SettingsView.playbackPane` 新增一行「播放页背景动画」开关，绑定同一 `@AppStorage` 键。

## 兼容性与迁移

- 仅影响播放页背景视觉与主页播放条点击热区，不触碰任何播放、队列、歌词、恢复逻辑；`AudioPlayer` / `PlaybackClock` / `LyricsCache` / `AVPlayerItem` 全部未改动。
- 抽色算法对外接口签名与返回结构均不变，`DockArtworkController` Dock 底色、`AudioPlayer.orbPrimaryImage/orbSecondaryImage` 预烘焙光斑继续按 `primary/secondary` 工作；Dock 视觉上颜色更准，但功能无变化。
- 新增 UserDefaults 键 `ManyuMusic.nowPlayingBackdropAnimation`（默认 true），未记录时按默认值开启，老版本偏好不受影响。
- 单元测试：53/53 通过。

## 验证

- `swift build -c release --disable-sandbox`：编译通过（除既有 `DockArtworkController`/`VolumeFrameReporter` 的非新增 warning 外无新错误）。
- `swift test --disable-sandbox`：53/53 通过（6.6 秒）。
- 人工验收（主人 2026-09-20 检查效果）：底部播放条空白处点击可进播放页；播放页背景渐变颜色加深、肉眼可见缓慢扫动；设置开关可关闭/开启动画；未观察到播放/切歌/进度/歌词同步异常。

---

## 附录：v3.13.0-beta2 摘要

修复内测中发现的两个关联问题——重启后播放栏不恢复上次曲目（歌库异步加载导致恢复从未执行），以及窄窗口（840～1040pt）下播放条布局变形；同时把内嵌歌词识别从仅 FLAC 扩展到所有支持的音频格式（MP3 读 ID3v2 USLT、MP4 读 moov.udta.©lyr）。

## beta2 用户可见更新

### 修复

- 重启软件后底部播放栏正确恢复上次曲目、整个播放队列、播放位置与模式（beta1 中播放栏为空）。
- 窗口较窄时播放条不再变形：曲目信息区固定宽度、格式徽标紧贴歌名、播放控件居中、右侧工具对齐；宽屏（≥1040pt）保持音量滑块布局不变。
- 窗口记忆恢复的尺寸若小于最小窗口（840×520）会自动放大到合法尺寸并居中。
- 内嵌歌词识别扩展到所有支持的音频格式：MP3 读取 ID3v2 USLT 帧，MP4/M4A/M4B/MOV 读取 `moov.udta.©lyr` atom；软件支持什么格式就识别什么格式的内嵌歌词，外置 `.lrc` 维持不变。

## beta2 技术变更

- `MainView`：在 `library.isLoading` 变 false 的回调中调用 `player.restorePlaybackState(from:)`（此前只在 `onAppear` 且库已加载时调用，而启动瞬间库必然还在加载）。
- `AudioPlayer.restorePlaybackState`：可用曲目为空时提前返回且不置位 `didAttemptPlaybackRestore`，为加载完成后的重试保留机会。
- `AudioPlayer` 新增 `init(defaults: UserDefaults = .standard)` 依赖注入，全部 UserDefaults 访问收敛到实例属性；生产路径行为不变，测试使用独立 suite 不污染真实偏好。
- 新增 `Tests/HarmonyPlayerTests/PlaybackRestoreTests.swift`（3 个用例：空库不消耗恢复机会并在二次调用时完整恢复、无队列存档退化为单曲队列、无存档保持空白）。
- `PlayerBar.compactContent` 重排：定宽 240 曲目区 + 两个 Spacer + 最大 380 居中控件 + 78 宽工具区，结构与 `wideContent` 同构。
- `AppDelegate.fitWindowsToVisibleScreen()`：恢复存档后窗口尺寸双向钳制到 [840×520, 屏幕可见区-32]；过小时居中，超屏时保持左上角锚点收缩。
- `EmbeddedMetadataReader.readLyrics` 按扩展名分发：flac/mp3/m4a/m4b/mp4/mov 各走自家解析，其余返回 nil 交 AVFoundation 兜底。
- 新增 `readMP3Lyrics`：解析 ID3v2.3/2.4 头与帧，定位 USLT，支持 UTF-8/UTF-16(BOM)/UTF-16BE/ISO-8859-1 四种文本编码。
- 新增 `readMP4Lyrics` + `scanMP4Atom`：深度优先扫描 MP4 atom 树（仅下钻 moov/udta/meta/ilst，跳过 trak 等大块），定位 `©lyr` atom 并读取 UTF-8 文本。
- 新增 `Tests/HarmonyPlayerTests/EmbeddedLyricsFormatTests.swift`（5 个用例覆盖 MP3 ID3v2.3/2.4、UTF-16-BOM、无 ID3；MP4 m4a/mp4 有/无歌词；不支持格式）。

## beta2 兼容性与迁移

- 仅支持 Apple 芯片（arm64）、macOS 14 及以上；ad-hoc 签名、未公证。
- beta1 已写入的播放存档（trackID/queueIDs/currentTime）在 beta2 首次启动即被正确恢复，无需用户操作。
- 单元测试：50/50 通过（合并后）。
- Release 构建编译通过、签名校验通过。
- 人工验证（2026-09-19）：窗口宽度 840/925/1040/1180pt 四档截图比对，窄宽两套播放条布局均无重叠、无异常空隙；重启后曲目与队列恢复。
- 待人工验收：含内嵌 USLT 的 MP3、含 `©lyr` 的 M4A 在歌词面板正确显示。

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
- beta2 修复 beta1 内测发现的播放恢复、窄屏播放条与歌词格式识别问题；根据后续反馈继续修复，正式发布时版本号定为 3.13.0。
- 继续执行一功能一分支，合并和发布完成后删除已用完的分支。

## 修订记录

暂无。
