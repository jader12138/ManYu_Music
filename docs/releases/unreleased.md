# 下一版本（v1.0.0-beta2 测试版或 v1.0.0 正式版准备中）

- 发布状态：**v1.0.0-beta1 已于 2026-09-23 发布**（GitHub Releases，prerelease，不顶替 v0.5 稳定版；见文末附录）。本文件保留过程摘要与发布附录。
- 已发布 1.0 内测：`v1.0.0-beta1`；更早的内测在版本线重排后编号为 `v0.6`~`v0.10`（原 v3.13.0-beta1~beta5，见文中原附录）。
- 上一稳定版本：`v0.5`（原 v3.12.0）
- 当前 `VERSION`：`1.0.0-beta1`（已随 beta1 发布）

> 注：2026-09-23 起 GitHub 版本线重排，上文及后文各历史摘要中的 `v3.x` 旧标签名与新编号对照见下节；仓库内 `docs/releases/v3.*.md` 按永久历史记录规则保留原文件名、不重命名。

## 本轮摘要（2026-09-23，分支 `codex/renumber-versions-0x`：GitHub 版本号统一为 0.x）

主人决定：1.0 正式版尚未发布，以前的版本号都不算，GitHub 上全部历史版本改编号为 0.1 起的连续序列，下一步直接发布 1.0 测试版。

- **用户可见变化**：仅 GitHub Releases / Git 标签层面，应用本体无任何改动。
- **编号映射**（时间从旧到新）：

  | 旧标签 | 新标签 | 指向提交 | 说明 |
  | --- | --- | --- | --- |
  | `v3.8.0` | `v0.1` | `f52ba86` | 原仅有标签无 Release，本次补建 Release（无安装包，说明据 `docs/releases/v3.8.0.md` 整理） |
  | `v3.9.0` | `v0.2` | `526d1fa` | 稳定版 |
  | `v3.10.0` | `v0.3` | `09c92dd` | 稳定版 |
  | `v3.11.0` | `v0.4` | `daa8d34` | 稳定版 |
  | `v3.12.0` | `v0.5` | `26b16e0` | 稳定版，Latest；DMG 改名 `ManyuMusic-0.5.dmg` |
  | `v3.13.0-beta1` | `v0.6` | `cdd851e` | prerelease；DMG 改名 `ManyuMusic-0.6.dmg` |
  | `v3.13.0-beta2` | `v0.7` | `e2cfa7e` | prerelease；DMG 改名 `ManyuMusic-0.7.dmg` |
  | `v3.13.0-beta3` | `v0.8` | `b8125d0` | prerelease；DMG 改名 `ManyuMusic-0.8.dmg` |
  | `v3.13.0-beta4` | `v0.9` | `a1f2632` | prerelease；DMG 改名 `ManyuMusic-0.9.dmg` |
  | `v3.13.0-beta5` | `v0.10` | `6b4e352` | prerelease；DMG 改名 `ManyuMusic-0.10.dmg` |

- **技术变更**：新标签全部为 annotated tag，指向与旧标签相同的提交，tagger 日期保留原值（2026-09-13 ~ 2026-09-21）；Release 按时间从旧到新重建（稳定版 `--latest=false`，最后由 GitHub 自动把 Latest 落到 v0.5），标题/正文中的旧版本号字符串整体替换，6 个 DMG 下载后以新文件名重新上传；校验回下载 v0.5/v0.9 的 SHA-256 与原包逐字节一致（`0c5b00f5…`、`20fb6a53…`）；旧 10 个标签与 9 个旧 Release 全部删除（远端 + 本地）。
- **兼容性**：不改变任何代码、提交历史与资料库；旧 Release 链接（v3.x）失效，新链接为 `/releases/tag/v0.x`。

  同日完成软件本体改号：`VERSION` 与 Info.plist 模板由 `3.13.0-beta5` 改为 `1.0.0-beta1`（系统版本号 1.0.0），详见 [CHANGELOG](../../CHANGELOG.md) 中「软件本体版本号升级为 1.0 测试版」一节；下一个发布即为 v1.0.0-beta1。
- **验证**：`gh release list` 仅剩 10 个新 Release 且顺序/预发布标记正确；`git ls-remote --tags` 与本地 `git tag -l` 均仅剩 v0.1~v0.10；`releases/latest` 指向 v0.5；资产数量、文件名、字节数与迁移前一致。

## 本轮摘要（2026-09-23，分支 `codex/settings-appearance-previews`：设置页外观预览图 + 下拉框收窄）

主人在发布前验收截图时提出的两处设置页外观调整。

- **用户可见变化**：
  1. 设置 → 外观的「跟随系统 / 白天模式 / 夜间模式」三个选项，由原来的灰色/深色小色块 + play 图标占位，升级为**真实界面截图缩略图**（132×88pt，3:2）：跟随系统是同一主界面左明右暗对半合成、白天模式是全浅色界面、夜间模式是全深色界面；选中态仍为 hpAccent 2pt 圆角描边 + 标签变色，点击即时切换外观（已实测浅↔深切换与持久化正常）。
  2. 设置 → 播放的「歌词切换效果」下拉菜单此前宽度占满整行右侧（SwiftUI menu Picker 在 HStack 中默认吃满可用宽度），现固定为 88pt，贴合最长四字选项 + 箭头；七个选项里最长的「像素溶解/从左揭开/从右推入」闭合态完整显示不截断（弹出菜单本身按最长项自适应，不受控件宽度影响）。
- **技术变更**：
  1. 主人提供的三张 2120×1412 原图降采样到 600×400 存入 `Resources/AppearanceSystem.png`、`AppearanceLight.png`、`AppearanceDark.png`（每张约 195KB）；[build-app.sh](../../scripts/build-app.sh) 增加三条 install 打进 `Contents/Resources`（本项目无 asset catalog，图片资源一贯由打包脚本安装、运行时 `Bundle.main.url(forResource:)` 加载）。
  2. [SettingsView.swift](../../Sources/HarmonyPlayer/Views/SettingsView.swift) 的 `AppAppearance` 私有扩展新增 `previewImage: NSImage?`（按模式映射资源名，Bundle 取不到时回退旧色块占位）；外观选择器 label 由 70×46 色块改为 132×88 圆角裁剪截图。歌词效果 Picker 增加 `.frame(width: 88)` 与注释。
- **兼容性**：无设置/数据迁移，无新增 UserDefaults 键；三个模式枚举、标签（跟随系统/白天模式/夜间模式）与选中逻辑不变；Bundle 缺图时回退旧占位，不会白屏。
- **验证**：`swift build -c release` + `scripts/build-app.sh` 打包签名通过（无新增警告）；`swift test --disable-sandbox` 110/110 通过（8.6s）。真机截图验收：浅色设置页三缩略图清晰、选中描边正确；点击「夜间模式」整窗即时变深色且缩略图选中态跟随、再点「白天模式」恢复（`ManyuMusic.appearance` 持久化值 light 确认）；把 `ManyuMusic.lyricTransition` 直接置为最长的 `dissolve` 重启后，88pt 闭合控件内「像素溶解」四字 + 箭头完整无截断。注：合成 CGEvent 点击无法展开 NSPopUpButton 的跟踪菜单（测试注入限制，真实鼠标不受影响），故以"预置最长值看重置闭合态"方式验证宽度。

## 本轮摘要（2026-09-22，分支 `codex/stress-crash-fixes`：发布前极限排雷）

正式版发布前的稳定性总验收，目标是找出并消除会导致**闪退、打不开**的严重问题。先分析全部历史崩溃日志，再做冷启动、异常数据、UI 风暴、内存泄漏多维极限测试，静态扫描全代码库的致命陷阱，最后修复并全量回归。

- **用户可见变化**：正常使用无界面/交互变化；两类罕见但致命的闪退路径被消除（布局重入 trap、音频 Tap 创建失败即崩），异常资料库不再导致打不开。
- **历史崩溃日志分析**（`~/Library/Logs/DiagnosticReports`，13 份均为旧 build 210）：① 7 份签名相同的 `EXC_BREAKPOINT/SIGTRAP`，栈顶 SwiftUI `NSViewPlatformViewDefinition.initView → makeView`，发生在 NSHostingView.layout 期间创建 NSViewRepresentable 宿主时——应用符号已内联，结合代码定位到音量控件 `FrameReporterView` 在 AppKit layout pass 中**同步**执行 `onFrameHandler` 闭包，而 [PlayerBar.swift](../../Sources/HarmonyPlayer/Views/PlayerBar.swift) 两处闭包回写 SwiftUI 状态（`BarVolumeControl.controlFrame` 真 @State、播放页 `volumeState.hotFrame` 间接驱动更新），重入 SwiftUI ViewUpdater 即可能触发该 trap；② 6 份 `-[NSApplication _crashOnException:]`（17 点五连发 + 9-17 一份），`-[NSWindow(NSFullScreen) _inFullScreen]` 消息发给野对象、CATransaction commit 布局期间窗口 use-after-free——现版本压测未复现，代码侧菜单栏 popover 释放顺序正确（先 close 再置 nil 再 removeStatusItem），作为残余风险记录观察。
- **技术变更（修复 ①：布局重入）**：[NowPlayingView.swift](../../Sources/HarmonyPlayer/Views/NowPlayingView.swift) 的 `FrameReporterView` 新增 `lastReportedFrame`/`isReportScheduled`，`viewDidMoveToWindow()`、`layout()`、`reportFrame()`（updateNSView）统一走 `scheduleReport()`：合并到 `DispatchQueue.main.async` 下一轮 runloop 再算 `convert(bounds, to: nil)` 并回调，彻底跳出 AppKit layout pass 与 SwiftUI update；每轮 runloop 最多上报一次，相同 frame 去重，window 为 nil 时上报 nil。音量热区仅延迟一个 runloop 就绪，悬停滚轮/点击外部收起行为实测不变。
- **技术变更（修复 ②：EQ tap 致命错误）**：[Equalizer.swift](../../Sources/HarmonyPlayer/Services/Equalizer.swift) 的 `EQTap.makeTap` 签名由非可选改为 `MTAudioProcessingTap?`，`MTAudioProcessingTapCreate` 失败时释放 `passRetained` 的 context（+1 平衡，防泄漏）、写 NSLog 并返回 nil；`EQTap.attach` 用 `guard let tap` 提前返回。失败时该曲目仅跳过 EQ/频谱，不再 `precondition`/`fatalError` 崩溃（原调用点在 loadTracks 后台回调链上，失败即闪退）。
- **异常数据启动验证**：对真实库备份后注入四种损坏——`head -c 400` 截断、300 字节随机二进制、空文件、`{"tracks":"not-an-array"...}` 错结构——冷启动均成功开窗、零崩溃；截断版显示保护提示「资料库文件损坏，已暂停修改以保护原文件」（LibraryStore `.failed` → isPersistenceSuppressed=true，不会覆写原文件）。保存走 `data.write(to:options:.atomic)` 原子写，`kill -9` 不会写坏库。测试后真实库已还原（400 首、JSON 合法）。
- **兼容性**：无数据/设置/库结构迁移；两个修复均为内部行为，界面、交互、音频链路在正常路径下完全不变。
- **验证**：`swift test --disable-sandbox` 110/110 通过（8.3s，0 failures）；`scripts/build-app.sh` release 打包 + ad-hoc 签名成功（仅既有 DockArtworkController actor warning）。冷启动 `pkill -9` 后重开 11 轮全部 ALIVE、窗口数=1、零新崩溃报告；UI 压力共 8 轮（修复前 5 轮 + 含修复新包 3 轮，每轮狂切侧栏四页、三处甩滚、播放/暂停×8、切歌×8、随机/红心/队列、EQ 面板、歌词、搜索打字、播放页歌词甩滚）全部存活、终态界面正常；3.5 分钟播放+切歌+狂切页 churn，RSS 走平（约 +1MB 分配器抖动）、physical footprint 约 130MB、`leaks` 两次均 0 leaks / 0 bytes。音量控件专项：经 NSLog 坐标诊断确认滚轮事件能被本地监视器接收且热区判定正确（此前一次"滚轮无效"是测试注入点比真实热区高 17pt 的测试误差，非产品 bug），主播放条与播放页喇叭滚轮（45→90 等）、滑条拖动/点击跳值、点击静音/恢复、播放页滑块展开/点外收起均实测正常。静态全库扫描其余强解包均安全（IBOutlet 延迟初始化、已校验 count 的数组强解包、vDSP baseAddress），无 `try!`。

## 本轮摘要（2026-09-22，分支 `codex/perf-fast-scroll-artwork`：快速滑动封面秒出 + 播放 CPU 优化）

正式版前性能优化工程的第一步：先保用户体验不降级，再修性能。针对主人反馈「歌曲界面/专辑界面快速滑动时封面显示不出来」做根因修复；验证中顺带定位并修复了播放进度条导致的持续高 CPU（主线程空布局）。

- **用户可见变化**：
  1. 歌曲列表（400 首）、专辑网格（346 张）、艺术家网格（220 位）快速甩滚、甩到列表/网格底部、连续上下反向甩滚，滚动停下的瞬间所有可见封面均已完整显示，无灰块、无后补闪烁；慢滑与停留时的显示效果与之前一致（无封面专辑的「?」占位行为不变）。
  2. 播放音乐期间整机更安静省电：同一台机器（400 首曲库、播放中、菜单栏歌词开启）`top` 瞬时 CPU 从修复前约 20% 降到 3.8~6.6%；暂停播放/空闲时 CPU 接近 0%（修复前暂停也持续约 20%）。播放进度走动、seek 拖动、暂停/恢复、菜单栏歌词均正常。
- **根因（封面缺失）**：① 封面预热开关默认关闭，滚动全靠行进入可见区才发起加载；② `ArtworkPipeline` 单限并发池（4 槽），未命中需重新打开音频文件读取 MB 级内嵌图块并经 ImageIO 降采样，文件 I/O 一旦开始不可取消——快滑时 4 槽全被已滑走的行占住，停下后可见行只能排队等待，表现为长时间灰块；③ 原取消策略过激（最后一个等待者离开就取消整个 in-flight）；④ SwiftUI LazyVStack/LazyVGrid 没有 UIKit 式 prefetch 回调。
- **技术变更（封面管线）**：
  1. `ArtworkPipeline` 改双优先级池：urgent 池 4 槽（可见请求）、prefetch 池 2 槽（预取）；`artwork(for:pixelSize:urgent:)` 新增 urgent 参数（默认 true 保持既有调用语义）。InFlight 增加 urgent/started/token 字段：排队中的低优请求遇同 key urgent 请求会**升级**（取消旧排队 task、换新 urgent task，等待者取并集）；已 started 的不可中断 I/O 跑完后写入缓存（顺路暖缓存）；只有排队中的请求在最后等待者离开时取消。acquire/finish 以 token 校验，防止新 entry 被旧 task 误清。
  2. 新增 [ArtworkWindowPrefetcher.swift](../../Sources/HarmonyPlayer/Services/ArtworkWindowPrefetcher.swift)：`ScrollArtworkWindow`（@MainActor ObservableObject）每次 body 配置 listID/count/pixelSize/lead/provider，行 onAppear 调 `report(_:)` 维护最近 40 个可见索引（去重保序），120ms 防抖后取 `[min−lead, max+lead]` 窗口交 `ArtworkWindowPrefetcher.shared.updateWindow`，后者用 UUID 签名去重、取消上一轮 utility Task 后顺序以 `urgent:false` 预热；listID 变化时清空状态。挂载：歌曲列表 lead 16/small 档，专辑网格 lead 12/medium 档（provider 取专辑代表曲），艺术家网格 lead 12/medium 档。
  3. `LazyArtworkView`（AppTheme.swift）task await 返回后**以 ArtworkCache 为权威再查一次**写回 loadedImage，防止取消/合并竞态导致永久占位；无封面返回 nil 仍保持占位。`ArtworkPreloader` 两轮启动预热均改走低优池。
- **技术变更（CPU）**：`PlaybackProgressRow` 原用 `TimelineView(.animation(minimumInterval: 1/30))` 做 0.25s 时钟 tick 之间的航位推算插值。`sample` 实测：只要该 TimelineView 挂载（播放中挂载，且暂停态不卸载），SwiftUI 宿主就进入持续渲染——120Hz 显示器上每秒约 130 次 CA commit / 88 次整窗 `layoutIfNeeded`，其中应用自身代码几乎不耗时，20% CPU 全耗在空布局；改 minimumInterval（30→15fps）与换 `.periodic` 时间表均无效（仍按显示链接订阅）。最终方案：暂停/快切冻结态渲染静态内容（时间为零 CPU），播放中挂载新增的私有 `ProgressTicker`（`Timer.publish(every:0.1).autoconnect()` 驱动自身 @State，仅该子树 10Hz 重算）；进度条每秒前进约 1pt，10Hz 步进约 0.1pt（小于一个物理像素），视觉连续。锚点重钉、seek、快切冻结、时钟漂移兜底等既有逻辑全部保留。
- **兼容性**：无数据/设置/库结构迁移；`artwork(...)` 新参数有默认值，既有调用零改动；封面缓存键、tier 像素（128/384/768）、NSCache 限额（320 个/48MB）、无封面负缓存策略不变；进度条外观、帧率体感、拖动跟手逻辑不变（SmoothScrubber 仅更新注释，代码未动）。
- **验证**：`swift build -c release` 通过（仅 DockArtworkController 既有 actor warning）；`swift test --disable-sandbox` 110/110 通过（8.3s）；`scripts/build-app.sh` 打包+ad-hoc 签名+重启。真机用 CGEvent scrollWheel（line 单位 + began/changed/ended phase，cghidEventTap）模拟甩滚：歌曲列表中速/分组快滑/单组 150 事件极限甩到第 ~300 首/连续往返甩四个场景，专辑网格与艺术家网格各两轮（含甩到底部），每个场景在刚停（~0.1s）/0.5~0.7s/1.5~2s 多点截图，封面均刚停即全亮、零灰块。`sample` 3s 调用栈对比确认修复前主线程 460/2415 帧在 CA flush+整窗布局、修复后播放中降到 3.8% 瞬时 CPU、暂停 0%；进度走动（多截图时间连续）、暂停冻结、恢复续走、scrubber seek、菜单栏歌词逐句更新、连播切歌均实测正常。

## 本轮摘要（2026-09-22，分支 `codex/tooltip-appearance`：全局禁用控件悬停 tooltip）

用户反馈：鼠标悬停在控件（上一首/下一首/返回等）上时，tooltip 显示为黑色或灰色小方块，没有文字；尝试外观校正方案仍不显示字后，用户决定软件内不再需要 tooltip，要求全部去掉，但不得影响菜单栏歌词。

- **根因**：`HarmonyPlayerApp.applicationDidFinishLaunching` 中 `NSApp.appearance = NSAppearance(named: .darkAqua)`（菜单栏黑底修复）让系统 tooltip 在浅色主题下文字/背景配色错乱，表现为无文字的黑/灰方块。
- **第一轮尝试（已弃用）**：0.25s 定时器扫描 NSToolTip 窗口、把 appearance 校正为主窗口实际主题。实测用户反馈仍不显示字，放弃。
- **最终方案（全局禁用，窗口层拦截）**：`disableAllToolTips()`（启动时、SwiftUI 窗口创建视图前调用一次）做多层 method swizzling：
  1. `-[NSView setToolTip:]`（`toolTip` 属性 setter）→ no-op；
  2. `-[NSView addToolTip:rect:]`（tracking rect 老式 API）→ no-op 并返回 tag 0；
  3. `-[NSView addTrackingArea:]` → userInfo 键名含 tooltip 的追踪区直接丢弃，普通 hover 追踪区（按钮高亮等）放行；
  4. **真正生效的关键层**：`-[NSWindow orderWindow:relativeTo:]`（mode 1=above / 2=below / 0=out；只拦上屏、放行 orderOut）连同 `orderFront:` / `orderFrontRegardless` / `makeKeyAndOrderFront:` 一起，对类名含 "tooltip" 的窗口拒绝上屏。
- **定位过程（修正第一轮误判）**：第 1~3 层经文件诊断日志证实对 SwiftUI `.help()` **全部零命中**——`.help()` 的 AppKit 后端绕过 NSView 基类直接操作。窗口扫描（Timer 需挂 `RunLoop.common`，否则悬停的 eventTracking 模式下扫描暂停）+ `class_copyMethodList` 确认：系统 tooltip 窗口真实类为 `NSToolTipPanel`（windowLevel 103），系统在首次悬停时预创建该对象复用（创建时 `isVisible=false`）；它自身只实现 `setToolTipString:` 等 13 个方法、**不重写** `orderWindow:relativeTo:`，故窗口层拦截是必经之路。第一轮曾误报"layer=103 已消失"，根因是 `CGWindowListCopyWindowInfo([.optionAll])` 会列出从未上屏的预创建窗口；改用 `.optionOnScreenOnly` + app 内 `isVisible` + 截图三重验证后才确认拦截真实生效。
- **不受影响项（已验证）**：菜单栏歌词用自定义 `LyricBarView`（NSTextField + CATransition）渲染、`NSStatusItem.view` 承载，完全不经过 tooltip，禁用后顶部歌词滚动正常；菜单栏黑底 CALayer swizzle 未改动。代码里各 `.help("…")` 保留（界面不再生效），将来恢复提示只需删除 swizzle。
- **验证**：`swift build -c release` 通过、`codesign -v` 签名正常；cliclick 真实悬停播放/上一首/下一首等按钮，`CGWindowListCopyWindowInfo([.optionOnScreenOnly])` 枚举 owner=漫域音乐 的窗口中无 layer=103 窗口，截图确认无任何弹层；菜单栏歌词全程正常。诊断设施（spy 定时器、/tmp 日志、SwizzleDiag）已全部移除，仅保留干净的拦截实现。

## 本轮摘要（2026-09-22，分支 `codex/play-stats`：侧栏统计入口 + 主窗口内统计页 + 天/周/月/年维度统计）

按用户三段式需求中的「1. 入口设置」+「2. 播放统计」实现（「3. 年度回顾」本轮不做）。侧栏底部新增「统计」按钮，点击与其他侧栏项一样在主窗口内容区切换到 StatsView（**首版曾做成独立 NSWindow，因用户反馈「不需要新开界面、白天模式背景却是黑色」改为内嵌页面**：独立窗口被强制 darkAqua appearance 导致 adaptive 的 hpNavy 永远解析成深色）；统计页按天/周/月/年切换时间维度，统计总播放次数与每首歌的具体播放次数，按次数从多到少排列，背景与配色全部跟随白天/夜间主题。

- **入口（侧栏 + 主窗口内容区）**：`LibraryDestination` 新增 `case stats`（id `"stats"`）。`SidebarView` 在「设置」按钮上方插入 `statsButton`（图标 `chart.bar.fill`、着色 hpMint、右侧角标为 `library.history.reduce(0) { $0 + $1.recentEvents.count }` 总播放事件数），点击 `select(.stats)`，选中态与其他侧栏项一致（hpAccent 浅色圆角块）。`MainView.detail` 在 settings 分支后新增 `destination == .stats` 分支挂载 `StatsView`（带 detailTransition 淡入）；主界面大标题栏显示「播放统计」+ 副标题「今天 / 本周 / 本月 / 本年的播放次数」，统计页隐藏搜索框与浏览快照加载角标。
- **数据扩展（PlayHistoryEntry）**：`Models.swift` 中 `PlayHistoryEntry` 新增 `var recentEvents: [Date]`，自定义 `init(from:)` 用 `decodeIfPresent` 兼容老 library.json（缺字段回退为空数组，旧 `lastPlayedAt` / `playCount` 不动），自定义 `encode(to:)` 同步写入。新增 `enum StatsRange: String, CaseIterable, Identifiable { case day/week/month/year }` 提供 `title`（"今天/本周/本月/本年"）与 `intervalStart: Date`（按 `Calendar.current` 的 `startOfDay` / `dateInterval(of: .weekOfYear)` / `.month` / `.year` 起始时刻）。
- **LibraryStore 接入**：`recordPlay(_:)` 在更新 `lastPlayedAt` / `playCount` 同时往 `recentEvents.append(.now)`，调用私有 `trimRecentEvents(&events)` 从头部丢弃早于 `now - 365*24*3600` 的事件避免无限增长；`history` 上限由 300 提到 1000 首不同的歌。新增 `playStats(for: StatsRange) -> [(track: Track, count: Int)]`：遍历 `history`，把 `entry.recentEvents` 中 `>= range.intervalStart` 的事件按 `trackID` 计数，仅保留 `derivedCache.tracksByID` 中仍存在的歌曲，按 count 降序、id 升序稳定排序。新增 `totalPlayCount(for:) -> Int` 返回区间内总播放次数（含已不在曲库的歌曲，仍反映真实播放量）。
- **StatsView（主窗口内嵌页面）**：`Sources/HarmonyPlayer/Views/StatsView.swift`。`@State range = .week`（默认本周），`entries: [(track, count)]`、`total: Int`、`loadedAt: Date`。布局：工具行左侧四段切换按钮（选中段 hpAccent 实底白字）、右侧「更新于 HH:mm」+ 重新统计按钮（Cmd+R）；三张汇总卡片（总播放次数/覆盖歌曲数/区间起点）按 hpAccent/hpPink/hpMint 着色；主体 ScrollView 列出每行（无行底板，直接依次排列）：排名 + 36pt 封面（`LazyArtworkView`，缓存命中首帧出图、未命中异步从文件抽取）+ 标题/歌手·专辑 + 右侧「N 次」+ 「播放」圆按钮；空状态显示「{区间}还没有播放记录」+ 引导文案。页面不带自有铺底（复用 detail 区 `Color.hpNavy.opacity(0.32)` 与 AppBackground），所有颜色用 hp* adaptive 色，昼夜模式自动切换。`reload()` 抓一份 `library.history.map { $0 }` 不可变快照避免渲染期间并发修改，`onChange(of: library.revision)` 自动刷新（`recordPlay` 会 bump revision，播放完一首歌后即时更新）。`play(_:)` 以当前 `entries` 为队列调用 `player.play(_:in:)`，列表行双击同效。
- **独立窗口方案移除**：删除 `AppDelegate.showStatsWindow()`、`statsWindow`、`.openStats` 观察者与 `deinit` 移除逻辑、`weak var library/player/theme` 及 `HarmonyPlayerApp.onAppear` 注入；删除 `Notification.Name.openStats` / `.statsShouldRefresh`（revision 驱动刷新后不再需要）；`ManyuMusic.statsWindow` 窗口存档不再产生（旧存档残留无副作用）。
- **兼容性**：`PlayHistoryEntry` 自定义 Codable 向后兼容老 library.json（缺 `recentEvents` 解码为 []），旧 `lastPlayedAt` / `playCount` 不动，老版本写的 history 在新版本仍可读、可写；无业务偏好新增。`LibraryBrowseSnapshot.build` 等既有调用零改动。
- **验证**：`swift build -c release` 通过（无新增警告）；dist 副本 `dist/漫域音乐-play-stats.app` 已签名并 `pkill` + `open` 重启，等主人验收内嵌统计页的昼夜主题、侧栏选中态、四段切换、按次数降序列表与播放按钮。
- **验收反馈修复（同日第二轮）**：① 个别歌曲（Time (remix)）统计行封面缺失——根因是行内直接同步读 `ArtworkCache.shared.image(for:tier:.small)`，未命中只画占位符且从不发起异步加载（播放条等其他位置走各自的加载路径，所以不是文件问题）；改为统一的 `LazyArtworkView(track:size:36, cornerRadius: ArtworkLayout.cornerRadius(for:36))`，缓存未命中时 `.task` 调 `AudioMetadataLoader.artwork` 从文件抽取后刷新。② 去掉每行 `Color.hpTextPrimary.opacity(0.03)` 的灰色圆角底板，歌曲直接依次往下排列（保留 contentShape 保证双击播放热区）。release 重新构建并重启，截图确认封面与列表样式均正常。

## 本轮摘要（2026-09-22，分支 `codex/fixed-window-frame`：主窗口固定启动位置与尺寸）

用户要求软件每次打开都在固定位置、固定尺寸，不要跑到屏幕右上角。System Events 实测确认目标布局：窗口左上角 (568, 193)（主屏左上角原点，逻辑点）、尺寸 1060×706（主屏 1920×1080 逻辑空间，可见区 1920×1055）。

- **病根**：UserDefaults 里 `NSWindow Frame ManyuMusic.mainWindow` 存的是 `"649 -24 185 24 0 -900 1440 875"`——一个 185×24 的畸形框架（疑似旧外接屏 1440×875 时代残留）。旧 `fitWindowsToVisibleScreen()` 每次启动先 `setFrameUsingName` 恢复该框架再钳制到最小 840×520，恢复/钳制与 SwiftUI 自身窗口状态恢复（按根视图类型名存的 `NSWindow Frame SwiftUI.ModifiedContent<…>` 键）互相打架，窗口最终位置不稳定、表现为跑到右上角。
- **固定布局**：新增文件级 `enum FixedWindowLayout { static let size = NSSize(1060, 706); static let topLeft = NSPoint(568, 193) }`；`WindowGroup.defaultSize` 同步改为 1060×706（首帧尺寸即正确）。`fitWindowsToVisibleScreen()` 删除 `setFrameUsingName` / `setFrameAutosaveName` 恢复逻辑，改为对所有 visible 且 `styleMask.contains(.titled)` 的窗口（状态栏 NSPanel 不含 titled，天然排除）调用新私有方法 `applyFixedFrame(to:)`：按 `window.screen`（兜底 `NSScreen.main`）的 **screen.frame**（含菜单栏全框，与 System Events 左上角原点一致）换算 origin = `(frame.minX + 568, frame.maxY − 193 − height)`，再夹进 `screen.visibleFrame`（窗口大于可见区时先收缩到可见区尺寸），与目标不同才 `setFrame(_:display:animate:false)`，避免无谓布局。
- **强制时基**：启动后 0s（下一个 runloop）/ 0.25s / 0.9s 三次执行 `fitWindowsToVisibleScreen()`；新增的 0.9s 一轮用于覆盖 SwiftUI WindowGroup 晚于首屏的状态恢复。
- **一次性迁移**：`migrateLegacyWindowFramesIfNeeded()` 以 `ManyuMusic.fixedWindowLayout.v1` 为标记，首轮删除 `NSWindow Frame ManyuMusic.mainWindow`、`NSWindow Frame ManyuMusic.statsWindow`（统计独立窗口遗留）及全部前缀 `NSWindow Frame SwiftUI.ModifiedContent<` 的键。SwiftUI 退出时仍会重写自己的内部键，但应用不再读取，强制校正保证其无效。仅删单个键，未做整域删除。
- **验证**：`swift build -c release` 通过；分支副本 `dist/漫域音乐-fixed-window-frame.app` 签名后 `pkill` + `open`，System Events 读回 `position=(568,193) size=(1060,706)`；彻底退出进程后再次打开仍为 `568,193 / 1060×706`；迁移标记为 1，旧畸形键与 statsWindow 键均已消失。

## 本轮摘要（2026-09-22，分支 `codex/duplicate-detect`：重复歌曲检测 + 手动保留 + 显示过滤）

设置 → 资料库新增「过滤重复歌曲」开关；开启后可点「重新检测」唤起审查面板，对所有重复组手动选择保留哪一首，未保留项从浏览列表隐藏（不从 library.json 删除、不删源文件，可逆）。

- **判定规则（用户 2026-09-22 确认）**：歌名去掉尾缀数字与空白后相同（「海阔天空」与「海阔天空 2」「海阔天空2」视为同名；非数字尾缀如「(Live)」保持原样不归一），歌手/专辑去首尾空格并忽略大小写后一致，时长容差 ±2 秒；满足以上全部条件归为同一重复组。同名但歌手/专辑/时长超容差不判为重复。
- **算法（纯函数）**：`Sources/HarmonyPlayer/Services/DuplicateDetector.swift` 提供 `normalizeTitle(_:)` / `normalizeField(_:)` / `detectGroups(in:) -> [[Track]]`——按 `(normTitle, normArtist, normAlbum)` 分桶后桶内按时长升序聚类（相邻差 ≤2 秒归簇、超容差拆簇），每个 ≥2 首的簇作为一组返回；组内按 `dateAdded` 降序、组间按组首 `dateAdded` 降序稳定排序。无类状态、无 I/O，便于单测覆盖。
- **接入（LibraryStore）**：新增 `@Published var duplicateFilterEnabled`（持久化 `ManyuMusic.duplicateFilter`，`didSet` 触发 `revision &+= 1` 让浏览快照刷新）、`@Published private(set) var hiddenDuplicateIDs: Set<UUID>`（init 从 UserDefaults 字符串数组恢复，`hideDuplicates(_:)` / `clearHiddenDuplicates()` 写回）；`detectDuplicateGroups()` 仅对**未隐藏**的 tracks 调用 `DuplicateDetector.detectGroups`，避免每次弹同样的旧组；`clearLibrary()` 一并清空隐藏集合防止悬空 id。
- **接入（LibraryBrowseSnapshot）**：`build` 新增 `hiddenDuplicateIDs: Set<UUID> = []` 参数（默认空集合，所有现有调用零改动）；空集合时直接走原数组不拷贝（快速路径），非空时一次性 filter 出 `visibleTracks`/`visibleRecent`，所有段（home/favorites/history/all/albums/artists/folders）都基于过滤后的集合构建。
- **接入（MainView）**：`refreshBrowseSnapshot` 读 `library.duplicateFilterEnabled ? library.hiddenDuplicateIDs : []` 透传给 `LibraryBrowseSnapshot.build`——开关关闭时永远不过滤，开关打开时按用户选择过滤；开关切换或隐藏集合变化通过 `revision` 自增触发 `browseRequest` 变化 → 快照重建。
- **审查面板（`DuplicateReviewSheet`，SettingsView.swift 末尾）**：点「重新检测」按钮唤起 `.sheet`，列出所有重复组——每组卡片显示「第 N 组 · 首数 · 代表曲标题」标题与组内每行的 radio button + 标题 + 歌手/专辑/时长/文件名/添加时间；`selections: [Int: UUID]` 在 `onAppear` 默认选每组第一首，用户点击切换单选；底部「应用并隐藏未选中项」一次性把所有组未选中的 id 经 `library.hideDuplicates(_:)` 加入隐藏集合，「重置已隐藏」调 `clearHiddenDuplicates()` 清空历史决定，「取消」(`.escape`) 不改动。键盘：回车 = 应用，Esc = 取消。
- **设置页布局**：`SettingsView.libraryPane` 在「不扫描 60 秒以下音频」与「屏蔽文件夹」之间插入「过滤重复歌曲」开关行；开关打开时下挂一行显示已隐藏数量（`已隐藏 N 首重复歌曲` 或 `暂未隐藏任何重复歌曲`）+ 副提示「隐藏仅作用于显示，不从资料库删除」+ 「重新检测」按钮（`tracks.count < 2` 或 `isLoading` 时禁用）。
- **测试**：新增 `Tests/HarmonyPlayerTests/DuplicateDetectorTests.swift`（13 例：normalizeTitle 4 例覆盖纯文本/尾缀数字/非数字尾缀，detectGroups 9 例覆盖同名+全字段一致分组、歌手/专辑不同不分组、时长容差 ±2 秒内分组、超容差拆组、多组排序、单首不构成组、桶内时长簇拆分、大小写/空白归一）；`swift test` 全部 110/110 通过（含 13 新增）。
- **兼容性**：无数据/设置迁移；开关默认关闭，关闭时浏览行为与历史完全一致（`hiddenDuplicateIDs` 传空集合走快速路径不 filter）；新增 UserDefaults 键 `ManyuMusic.duplicateFilter`（默认 false）、`ManyuMusic.hiddenDuplicateIDs`（默认 []），老版本偏好不受影响；隐藏集合只作用于显示，library.json 与磁盘文件不动，关闭开关立即恢复全部可见。
- **验证**：`swift test` 110/110 通过（8.1 秒）；`swift build -c release` 通过（仅既有非新增 warning）；dist 副本 `dist/漫域音乐-duplicate-detect.app`（CFBundleVersion 250）已替换签名并 `pkill` + `open` 重启，等主人验收开关、检测面板与列表过滤效果。

## 本轮摘要（2026-09-22，分支 `codex/bilingual-lyrics`：播放页双语歌词识别 + 右下角开关）

播放页歌词支持识别双语 LRC 文件，并加一个右下角开关控制是否显示译文。

- **新增（双语识别）**：`LyricLine` 模型新增 `translation: String?` 字段（默认 nil，向后兼容所有现有构造点）；`LyricsParser.parse` 在按时间戳排序后做一轮双语合并——**相同 time 的相邻两行**（原文在前、译文在后）合并为一行，译文写入 `translation`。合并条件严格：仅当 `next.time == current.time` 且 `next.text != current.text` 且原文非空时配对；多时间戳同行（`[00:12.00][00:45.00]chorus`，解析后 text 相同、time 不同）不会被误判为双语；三行同 time 时前两行配对、第三行单独保留。无时间轴的纯文本歌词不参与合并。
- **新增（右下角开关）**：`LyricTimelineView` 新增 `showTranslation: Bool` 参数；`NowPlayingView` 歌词面板右下角 HStack（"点击歌词可跳转" + "Aa" 设置钮）在 "Aa" 左侧加「译」按钮——点击切换 `@AppStorage("ManyuMusic.lyricsBilingual")`（默认关闭），开启态用主题色 `hpAccent` 高亮，关闭态用半透明灰。渲染：`showTranslation && line.translation != nil` 时在原文下方以 `baseFontSize * 0.78` 字号、`medium` 字重、较淡透明度（当前行 0.62 / 非当前行按距离衰减 ×0.62）渲染译文；VStack 整体随原文一起 `scaleEffect` 放大/缩小，行高由 `GeometryReader` 测量自动反映到滚动定位（`centerActive` 无需改动）。
- **兼容性**：无设置/数据迁移；单语歌词 `translation` 为 nil，开关对其无影响；双语开关默认关闭，首次开启才显示译文。不影响内嵌歌词读取、缓存、预热、滚动定位任何既有路径。
- **验证**：`swift test --disable-sandbox` 97/97 通过（新增 3 例：双语配对合并、单语 translation 为 nil、多时间戳同行不误合并）；`swift build -c release --disable-sandbox` 通过；`scripts/build-app.sh` 打包替换签名成功，dist 副本 `dist/漫域音乐-bilingual-lyrics.app`（CFBundleVersion 248）已重启。

## 本轮摘要（2026-09-22，分支 `codex/auto-folder-rescan`：启动时自动扫描已添加文件夹）

添加过文件夹后，软件每次启动自动遍历这些来源，把新增的音频文件入库到曲库，无需手动点"重新扫描"。

- **功能（自动扫描入库）**：`LibraryStore.apply(_:)` 在 `.loaded` case 加载完 `library.json`、写完 `sources` 等状态并置 `isLoading = false` 后，调用新增的 `rescanSourcesForNewTracks()`——它收集 `sources.map(\.url)`，复用 `expandAndFilter` 递归枚举文件夹、过滤屏蔽目录与已知路径，再用 `readTracks` 并发构造新 Track，按 `filterShortAudio` 过滤后合并进 `tracks` 并 `libraryContentDidChange()` 保存。**增量 diff**：只对真正的新文件读 metadata，老文件不重读，启动开销可控。
- **静默体验**：无新歌时 `importNotice` 置为 nil（不弹"没有发现新的可播放音频文件"，不打扰用户）；发现新歌时提示"自动扫描到 N 首新歌"。复用 `isImporting` 状态机与 `clearGeneration`/`tracksGeneration` 双重并发保护，与 `add(urls:)` 同款，启动后用户手动点"添加音乐"会被 `guard !isImporting` 拦截（启动扫描很快，可接受）。
- **边界**：`library.json` 加载失败（`isPersistenceSuppressed`）时 `canEdit` 为 false，guard 拦截不扫描，保护原文件不被覆写；首次启动无 `library.json`（`.missing`）时 sources 为空，guard 拦截。
- **兼容性**：无设置/数据迁移；不新增 UserDefaults 键；不影响播放、队列、歌词、恢复、推荐、均衡器任何业务路径。自动扫描是默认行为，未做成开关（用户原话"每次打开软件时自动扫描"）。
- **验证**：`swift test` 94/94 通过；`swift build -c release` 通过。

## 本轮摘要（2026-09-22，分支 `codex/search-volume-rework`）

主界面顶栏搜索框移除与音量控件搬家两项界面调整。

- **调整（搜索框）**：移除主界面顶栏搜索框（`MainView` 头部 236pt 搜索胶囊整体删除）。搜索功能将重新设计，`searchText` 过滤逻辑与 `.focusLibrarySearch` 焦点通知暂时保留，供新搜索入口直接复用。
- **调整（音量控件统一）**：底部播放条右侧原音量控件（窄屏：喇叭+数字+滚轮；宽屏：喇叭+76pt 滑杆）替换为 `BarVolumeControl`——喇叭（下方音量数字）+ **右侧常驻横向滑条**（与播放页同款 `HorizontalVolumeSlider`，65pt，点击轨道跳转、按住拖动，右侧为最大音量），悬停滚轮仍可调（NSEvent scrollWheel 本地监视器按控件窗口坐标判断并吞掉事件，不影响背后列表滚动）。播放页（爱心右侧）保持浮出式 `PlayerVolumeControl`：点击喇叭从**右方**弹出横向滑块、再点收起、点滑块外自动收起（NSEvent leftMouseDown 监视器 + `VolumeFrameReporter` 上报窗口坐标）、收起时悬停滚轮调节。**播放条喇叭新增点击静音**：点击直接静音（图标切 `speaker.slash.fill`、数字变 0，内部以音量 0 实现），再次点击恢复静音前音量（`preMuteVolume` 会话内记忆）；**静音动画**——滑条几何不动、仍显示静音前音量，仅整条平滑变灰（`HorizontalVolumeSlider` 新增 `isMuted` 参数：填充/拇指变灰 + 0.18s 颜色过渡），喇叭图标切换带缩放淡入过渡（`id` 随图标名变化 + spring）。静音中拖动滑条或滚轮调音量即脱离静音态（滚动以显示值为基准）。滚轮调节均走 NSEvent 本地监视器——不再使用 NSView 捕获层，原生视图盖在图标上方会截断 SwiftUI 命中测试，导致点击漏给祖先容器（曾造成"点喇叭误入播放页"）。
- **兼容性**：无设置/数据迁移；音量调节途径不变（控件滚轮/滑块、系统音量键）。
- **验证**：Release 编译通过、单元测试全绿、应用启动后人工核对顶栏无搜索框、播放条音量控件展开/收起/滚轮调节正常。

## 本轮摘要（2026-09-22，分支 `codex/track-audio-info`：歌曲信息弹层新增音频技术参数）

歌曲信息弹层（三个点 → 歌曲信息）补充三项音频工程参数，便于查看每首曲目的码率/采样率/声道规格。

- **新增（弹层展示）**：`TrackInfoView` 在"格式"行后插入三行——**比特率**（bps / 1000 取整 + " KBPS"，如 320 KBPS、FLAC 1593 KBPS）、**采样率**（直接以 "Hz" 显示，如 44100 Hz、48000 Hz、96000 Hz）、**通道**（1 → "单声道"、2 → "立体声"、其他 → "N 声道"）。未读取到时显示"未知"，加载中显示"读取中…"。
- **实现**：`Track` 模型新增 `bitrate: Int?`（bps）/ `sampleRate: Int?`（Hz）/ `channels: Int?`（声道数）三个可选字段；`init` 增加三个默认 `nil` 参数，老调用点零改动；`Codable` 走 synthesized `decodeIfPresent`，旧 library.json 缺键解码为 nil。
- **抽取来源**：[AudioMetadataLoader.swift](Sources/HarmonyPlayer/Services/AudioMetadataLoader.swift) 的 `loadAudioTechParameters(from:)` 用 **AudioFile API**（与 macOS 自带 `afinfo` 同源）：`AudioFileOpenURL` 打开文件 → `kAudioFilePropertyBitRate` 取整轨平均比特率（bps，VBR 也是平均值）→ `kAudioFilePropertyDataFormat` 取 `AudioStreamBasicDescription` 的 `mSampleRate` / `mChannelsPerFrame`。可靠支持 MP3/M4A/FLAC/WAV/AIFF/CAF 等全部支持格式；同步函数包在 `Task.detached(.utility)` 中跑，不阻塞 UI。
- **现场加载**：`TrackInfoView` 用 `.task(id: track.id)` 调 `AudioMetadataLoader.loadAudioTechParameters(for:)` 现场抽取——Track 已持久化的字段优先用，缺的从 AudioFile 现读并取并集。**老库无需重新扫描**即可显示真实值，重新扫描后字段持久化（下次显示更快）。
- **兼容性**：无设置/数据迁移；不影响播放、队列、歌词、恢复、推荐、均衡器任何业务路径。文件大小行不变（`ByteCountFormatter` 已以 MB 显示典型音频文件）。
- **验证**：`afinfo` 对 FLAC "慢慢喜欢你 - 莫文蔚.flac" 报告 `2 ch / 48000 Hz / 1592745 bps`，软件弹层显示 `1593 KBPS / 48000 Hz / 立体声`（数学一致：1592745 / 1000 ≈ 1593）；`swift test --disable-sandbox` 94/94 通过；`swift build -c release --disable-sandbox` 通过。

## 本轮摘要（2026-09-22，分支 `codex/search-pinyin`：搜索回归 + 拼音检索）

顶栏搜索框回归原位置并新增拼音检索。

- **新增（搜索框回归）**：`MainView` header 恢复 236pt 搜索胶囊（放大镜 + 输入框 + 清空按钮，位于夜间模式按钮左侧，`destination != .settings` 时显示），`searchText` → `LibraryBrowseRequest.search` 链路复用原过滤逻辑。**修复历史 bug（输入文字不可见）**：SwiftUI `TextField` 的输入文字颜色受系统字段编辑器影响且不可控（本应用 `NSApp.appearance` 被强制 `darkAqua`、`foregroundStyle`/`foregroundColor` 均无效），改用 `SearchTextField`（`NSViewRepresentable` 包装原生 `NSTextField`，[SearchTextField.swift](Sources/HarmonyPlayer/Views/SearchTextField.swift)）——**固定色值**（浅色主题蓝黑 RGB 0.07/0.13/0.26、深色主题 0.92 灰白；占位文字固定灰），字段编辑器继承控件 `textColor`，编辑中文字颜色 100% 生效；`NSTextFieldDelegate` 同步 `@FocusState`。
- **新增（拼音检索）**：`PinyinIndex`（Sources/Support/PinyinIndex.swift）基于 `CFStringTransform`（`kCFStringTransformMandarinLatin` + `kCFStringTransformStripDiacritics`）生成 `PinyinKeys{full, initials}`——汉字逐字转拼音后去声调、去空白拼接为全拼（"周杰伦"→"zhoujielun"），取每个 token 首字母为首字母键（"zjl"；英文按词："Jay Chou"→"jc"），数字保留；结果按原文缓存（`NSLock` 保护的 static let 缓存盒，后台线程安全，重复按键零转换开销）。`LibraryBrowseSnapshot.SearchRow.matches(query:loweredQuery:)` 三通道匹配：原文包含 / 全拼包含 / 首字母包含（均含子串），title/artist/album 三字段任一命中即匹配；拼音转换仅在查询非空时进行。
- **测试**：新增 `PinyinIndexTests`（9 例：中文全拼/首字母、英文词、数字保留、空串与纯符号、缓存一致性、`LibraryBrowseSnapshot` 端到端 zjl/zhoujielun 命中与未命中）。
- **兼容性**：无设置/数据迁移；搜索入口与交互不变，仅匹配能力增强。
- **验证**：单元测试全绿（86+9=95 预期）、Release 编译通过、应用启动后人工核对搜索框样式/输入文字可见/拼音与首字母过滤结果。

## 本轮摘要（2026-09-21，分支 `codex/background-playback`，2026-09-22 从备份恢复合入）

新增「关闭窗口后继续后台播放」设置项、播放条菜单栏歌词开关，以及菜单栏迷你播放器的进度条与按钮动效打磨。

- **功能（后台播放）**：设置 → 播放新增「关闭窗口后继续后台播放」开关（UserDefaults 键 `ManyuMusic.keepPlayingAfterWindowClose`，默认关闭）。开启后点击主窗口红叉不再退出应用，音乐继续在后台播放；点击 Dock 图标可重新打开主窗口。
- **实现（后台播放）**：`AppDelegate.applicationShouldTerminateAfterLastWindowClosed` 改为读取该设置决定是否退出（开启时返回 false）；新增 `applicationShouldHandleReopen(_:hasVisibleWindows:)` 在无可见窗口时遍历 `NSApp.windows` 调用 `makeKeyAndOrderFront` 唤回主窗口。
- **功能（歌词开关）**：底部播放条中央控制区「喜欢」爱心右侧放置「歌词」按钮（「词」字图标，IconButton 新增 textLabel 文字形态），点击切换菜单栏实时歌词显示/隐藏；开启态不铺高亮底色，而在「词」字底部显示一枚主题色小圆点（IconButton 新增 showsActivityDot 形态，与播放模式按钮同款 3.5pt 圆点，带弹性出现动画），关闭时圆点消失；偏好持久化（UserDefaults 键 `ManyuMusic.menuBarLyricsVisible`），歌词刷新逻辑尊重用户偏好。
- **改进（迷你播放器打磨）**：菜单栏迷你播放器进度条 thumb 从空心圆环改为实心蓝色圆点 + 柔和阴影；非拖动时进度推进加 0.25s ease-out 动画，拖动时禁用动画严格跟手且仅在 mouseUp 时 seek，避免频繁 seek 卡顿；播放/暂停/上一首/下一首按钮新增 0.19s 按压缩放回弹（0.88 → 1.0）。
- **兼容性**：后台播放默认关闭，原有行为（关窗即退出）不变；歌词开关与动效无数据迁移。
- **验证**：见本次恢复合入后的构建与测试记录（本分支提交）。

## 本轮摘要（2026-09-21，分支 `codex/menubar-icon-fix`）

菜单栏双状态项的内测问题修复（主人截图反馈：歌词区出现黑色背景板、图标形状与原设计完全不符）。

- **歌词区消除黑色背景板**：根因是歌词项用 NSButton + 自定义 NSButtonCell，AppKit 的点击高亮直接写 `highlighted` 属性、绕过方法覆写，黑底色板仍会出现。歌词项改为纯自定义 `LyricStatusView`（NSView）：只覆写 `draw(_:)` 绘制单行文本（`NSFont.menuBarFont` + `labelColor` 随菜单栏深浅外观切换 + 截断省略），不经过 NSButton/NSCell 的高亮与 bezel 绘制路径，点击零反应、零底色，与菜单栏亚克力背景完全融合；`viewDidChangeEffectiveAppearance` 触发重绘。`lyricWidth` 提为 `fileprivate` 供视图取固定宽度。
- **图标恢复主人设计原样**：根因是 SVG→Swift 转换脚本只翻转了 M（move）命令的 y 坐标、漏翻 C（curve）命令的控制点与终点，导致图形一半翻转、形状完全走样（渲染成窄"S"形）。修正 `/tmp/gen_menubar_logo.js` 的 C 分支（y = 2048 − y）后重新生成 `MenuBarLogo.swift`（114 段，全部 y 翻转，nonZero 填充、18pt 模板图不变），转换后用 qlmanage 渲染调试 SVG 与主人原图比对一致。
- **兼容性**：无数据/设置迁移；菜单栏开关（`ManyuMusic.menuBarPlayer`）与交互（图标左/右键弹播放/暂停菜单、歌词纯展示）均不变。
- **验证**：`swift build` / `swift test` 86/86 通过；`swift build -c release` 通过；`./scripts/build-app.sh` 打包替换签名成功；实机冒烟——重启 dist 应用后菜单栏截图（整条 + 局部放大）确认歌词文本直接落在亚克力菜单栏上、无任何底色板，图标渲染为主人设计的书法 swirl 原样；点击图标弹菜单交互待主人验收。

## 本轮摘要（2026-09-21，分支 `codex/dock-menu`）

系统集成两项：macOS 菜单栏实时歌词/播放控制 + Dock 图标右键菜单。目标是不开主窗口也能看当前歌词、随手控制播放。菜单栏方案按主人要求两度改版：初版为「应用图标 + 点击弹出迷你播放面板（封面/歌名/歌词预览/进度条/切歌）」，弹出面板代码（`MiniPlayerView`、`appIconDidChange` 通知链路、`nextLyricText`）已删除；二版为「单状态项：歌词（左）+ `play.fill` 占位图标（右）」；最终版修复内测问题后定稿为下述「双状态项 + 主人正式图标」设计。

- **Dock 右键菜单**：`applicationDockMenu(_:)` 每次右键现做新菜单（系统每次都重新取，无需常驻观察者），内容为歌曲名（加粗）+ 歌手·专辑（次色）+ 播放/暂停（文案与 SF Symbol 随播放状态切换）+ 上一首/下一首；无曲目时显示「未在播放」占位且三条命令置灰。菜单规格抽成纯数据 `PlayerMenuSpec`（无 AppKit 依赖），标题/占位/禁用逻辑由单元测试覆盖；`DockMenuController` 把 spec 渲染为 NSMenu，target-action 直接调 `AudioPlayer.shared`。菜单顶部的「漫域音乐 + 对勾」是系统自动附加的窗口列表项（WindowGroup 默认以应用名为窗口标题），已通过 `window.isExcludedFromWindowsMenu = true` 移除。
- **菜单栏双状态项（最终版）**：拆为两个相邻 `NSStatusItem`——
  - **歌词项（左）**：固定宽度 160pt，逐句更新只改文本、宽度不变，消除可变宽度下菜单栏整块伸缩的「一闪一闪」；LRC 整句留白的间隙沿用上一句（`lastLyricText`），无歌词时整项 `isVisible = false` 隐藏。~~按钮换自定义 `LyricButtonCell`~~（该方案后被 `codex/menubar-icon-fix` 取代：AppKit 点击高亮直接写 `highlighted` 属性、绕过方法覆写，黑底色板仍会出现；最终改为纯自定义 `LyricStatusView`，见上方修复摘要），点击歌词区域零高亮、零底色、零反应。
  - **图标项（右）**：主人设计的任务栏图标（`macOS任务栏图标.svg` 主体 path 代码化为 `MenuBarLogo`：SVG 的 M/C/Z 命令转 `NSBezierPath` 段落数组、y 轴翻成 AppKit 上正方向、nonZero 填充、18pt 模板图），模板图自动适配深浅色菜单栏（旧版整块黑底问题的另一半根因即非模板底色）。挂常驻 NSMenu，左/右键点击图标弹「播放 / 暂停」（`NSMenuDelegate.menuNeedsUpdate` 每次弹出前重建，`autoenablesItems = false` 手动控制两项可用态）。
  - 歌词取 `AudioPlayer.currentLyricText`，订阅 `currentTrack`/`lyricLines`/`clock.currentTime`（0.25s tick）三流 CombineLatest 重算，`LyricState`（Equatable）`removeDuplicates` 防重绘。
- **开关**：设置 → 播放新增「菜单栏播放控制」（UserDefaults 键 `ManyuMusic.menuBarPlayer`，未记录默认开启），切换即时装卸两个状态项（`syncWithSetting()`），关闭时同时移除歌词订阅。
- **单例接线**：`AudioPlayer` 新增 `static let shared`；`HarmonyPlayerApp` 的 `@StateObject` 改引同一实例（App 场景与 AppDelegate/控制器共享，init 副作用只跑一次）。`AudioPlayer` 歌词取数抽出 `currentLyricIndex()`，`currentLyricText` 供菜单栏直接取当前句。
- **验证**：`swift test` 86/86 通过（新增 `PlayerMenuSpecTests` 5 项：无曲目占位与禁用、空标题视为无曲目、播放中显示暂停、暂停显示播放、空副标题省略次行）；`swift build -c release` 通过；`./scripts/build-app.sh` 打包签名校验通过；实机冒烟——重启应用后菜单栏截图（整条 + 局部放大）确认「固定宽度歌词（白色纯文本、无底框）+ 主人螺旋形图标」渲染与布局正确；点击歌词无高亮、点击图标弹菜单的交互待主人验收。

## 本轮摘要（2026-09-20，分支 `codex/equalizer`，已随 beta4 发布）

均衡器参考 MoeKoe EQ 插件全面重做：升级为 31 段参数均衡器（20Hz~20kHz ISO 三分之一倍频程，±6dB，每段 Q 值 0.1~18 独立可调默认 1.4），设置页为「头部（标题/运行状态灯/关闭EQ/重置）+ 三页签（均衡器/音效增强/高级功能，后两个占位）+ 实时频谱 + 预设 chips + 31 根垂直滑杆（双击归零）」结构；内置 35 个预设曲线（取自参考项目）+ 自定义预设；旧版十段曲线与自定义预设按对数频率轴插值迁移。入口两处：播放栏「定时」左侧快捷图标弹出精简面板（仅头部 + 预设 chips，带关闭钮）与设置独立「均衡器」页（完整面板）。

- **DSP**：RBJ biquad 级联——最低频段 low shelf、最高频段 high shelf、中间 29 段 peaking（各段独立 Q）；0 dB 段使用恒等系数直通。`EQTapContext` 每个 tap 持有独立延迟状态（转置直接 II 型，声道×段），共享 `Equalizer` 参数（NSLock 保护），`revision` 号变化时在音频线程重建一次系数并清零状态；增益与 Q 变化都推进 revision。
- **tap 常驻**：音频 tap 不再随 EQ 开关挂/摘，四条 item 创建路径（cut 切歌、crossfade 新曲、gapless 预载、重启恢复）一律 `EQTap.attach`；EQ 关闭时 process 直通（`isBypassed` 锁内镜像，不碰 UserDefaults），频谱喂送恒定进行，开关即时生效。
- **实时频谱（本轮重构为山峰风格，分支 `codex/spectrum-peaks`）**：`EQSpectrumRing`（16384 样本环形缓冲 + NSLock，音频线程写入下混单声道、prepare 时写入采样率）→ `EQSpectrumAnalyzer`（主线程 30fps 定时器，4096 点 Hann 加窗 + vDSP 实数 FFT，FFT 幅度乘 2/N 归一化修复平顶高原，20Hz~20kHz 对数频轴 384 点峰值聚合，dB 归一化窗口 -70~0dB + 高频倾斜补偿 +8dB 对数 tilt + 幂次 ^1.5 对比拉伸，快攻慢放 0.75，暂停时谱线衰减归零；聚合逻辑提取为纯函数 `computeLevels` 并由单元测试覆盖分布）→ `EQSpectrumView` Canvas 绘制（面板 180pt 高、参考线五等分）：弱张力（1/9）Catmull-Rom 峰形曲线 + 渐变填充 + 矮化慢衰减「远山影」第二层（`trailing`）+ 频率刻度；移除旧版人工水波基线、相位回声波与 phase 属性，轮廓随真实频谱高低错落。纯本地 Accelerate/vDSP 计算。
- **UI**：`EqualizerPanelView` 双模式——完整模式（设置页整页嵌入）：头部（标题 + 状态指示灯 + 关闭EQ/开启EQ + 重置）、Layout 协议 `FlowLayout` 预设 chips（选中高亮、+ 保存预设、自定义预设删除）、自绘 `EQVerticalSlider`（中心 0dB 基线、0.5 步进、双击归零）、`EQBandColumn`（增益值 + Q 值点击弹编辑滑杆 + 斜排频率标签），「音效增强」「高级功能」页签为占位文案；精简模式（播放栏弹窗宽 540）：仅头部 + 预设 chips。
- **音效增强（页签完整实现）**：`AudioEnhancer` 参数类（锁内镜像 + revision + UserDefaults 持久化，挂于 `Equalizer.enhancer`）+ `EnhancerEngine` 实时引擎（EQ 之后级联、独立开关）。频率调节：60Hz low shelf / 100Hz / 250Hz / 3kHz / 4kHz / 8kHz peaking / 8kHz high shelf（百分比映射 0~8dB、0~6dB 等上限）+ 动态增强压缩器（峰值包络 limiter，阈值 -14~-28dB、attack 5ms / release 150ms、makeup 补偿）；空间效果：早反射（20ms 缓冲 4 taps，L/R 错开）做环境感、Schroeder 4-comb + 每声道 2-allpass（freeverb 经典长度按采样率缩放）做环境混响（L/R comb 分组去相关）、M/S 立体声扩展做环绕声；输出控制：线性声道平衡 + ±12dB 输出增益 + 限幅。prepare 时按采样率一次性预分配全部缓冲，音频线程无分配；UI 为开关 + 分组重置 + 13 张滑杆卡片（LazyVGrid 双列）。
- **迁移**：旧十段增益（31/62/125/250/500/1k/2k/4k/8k/16Hz）与新自定义预设在对数频率轴上线性插值为 31 段并回写；Q 值为新键（默认 1.4×31）。
- **验证**：`swift test` 81/81 通过（新增频谱分布测试：模拟 445Hz 强峰 + 8kHz 弱峰 + 超高频静区，断言无满格平顶、峰谷分离、静区贴地；其余 80 项回归通过）；release 构建通过；实机播放验收频谱呈高低错落山峰形态（特别高峰 + 连绵丘陵 + 两端贴地）。31 段与音效增强听感待主人验收。

## 本轮摘要（2026-09-20，分支 `codex/gapless-crossfade`，已随 beta4 发布）

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

## 附录：v3.13.0-beta4 发布记录（2026-09-20 已发布）

### 摘要

beta3 之后最大的一次内测版本：引入 31 段参数均衡器（参考 MoeKoe EQ）、音效增强页签、实时山峰频谱，以及 Gapless 无缝播放与 Crossfade 淡入淡出两个默认关闭的连播增强；同时包含播放条封面亚克力包边、Dock 徽标内收与播放页切歌方向性转场、图标尺寸标准化等外观打磨。以 GitHub 预发布（prerelease，make_latest=false）形式发布 DMG，不替代 v3.12.0 稳定版。

对应代码区间：`v3.13.0-beta3`（b8125d0）→ beta4 标签（main HEAD，含合并提交 6511b52 均衡器链与 037c5dd 频谱链）。

### beta4 用户可见更新

#### 新增

- **31 段参数均衡器**：设置 → 均衡器整页 + 播放栏「定时」左侧快捷图标两处入口。20Hz~20kHz ISO 三分之一倍频程，每段 ±6dB（0.5 步进）、Q 值 0.1~18 独立可调（默认 1.4，点击 Q 值弹编辑滑杆），双击滑杆归零；头部含运行状态灯、开启/关闭 EQ、重置；内置 35 个预设（平直/摇滚/古典/流行/爵士/低音增强/人声/母带处理/黑胶温暖/Hi-Res 解析等）+ 自定义预设保存/删除；旧十段曲线与自定义预设自动按对数频轴插值迁移。
- **实时频谱（山峰风格）**：30fps FFT 绿色谱线 + 渐变填充 + 频率刻度，暂停平滑归零；对数频轴 384 点采样，面板高 180pt、参考线五等分；高低错落山峰轮廓 + 矮化「远山影」第二层。EQ 开关不影响频谱。
- **音效增强页签**：独立总开关 + 区内重置，13 项实时调节并自动持久化——频率调节 8 项（低频提升/低音增强/温暖感/人声增强/临场感/清晰度/高频提升/动态增强）、空间效果 3 项（环境感/环绕声/环境混响）、输出控制 2 项（输出增益 ±12dB、声道平衡）。「高级功能」页签本轮占位。
- **无缝播放（Gapless）**：设置 → 播放开关，默认关闭；结尾前预载预热下一首，近无间隙接管。
- **淡入淡出（Crossfade）**：设置 → 播放开关 + 3~12 秒时长滑块（默认 6 秒），默认关闭；切歌时两曲短暂重叠、smoothstep 缓动；暂停/seek/改模式/队列变动立即撤销未完成过渡。
- 底部播放条左下角封面加亚克力玻璃包边（外框 54/封面 48，发丝线 + 轻阴影）。
- Dock 封面模式播放/暂停徽标内收进亚克力底板；播放页切歌改方向性转场（新封面从后顶出上浮淡入、旧封面前景左滑淡出，0.5s，遵循减弱动态效果）。
- Dock/启动台图标内容占比对齐 macOS 标准网格（约 80.5%，四周留 10% 透明边）。

### beta4 技术变更

- 均衡器：MTAudioProcessingTap 常驻全部播放条目（cut/crossfade/gapless/恢复四路径统一 attach），RBJ biquad 级联（low shelf + 29 peaking + high shelf），0dB 段恒等直通；EQ 关闭时 tap 直通、频谱照常取流。系数 revision 机制在音频线程无锁重建。
- 音效增强：EQ 之后级联独立 `EnhancerEngine`——shelf/peaking biquad、峰值包络压缩器、早反射、Schroeder 4-comb + 2-allpass 混响（长度按采样率缩放、L/R 去相关）、M/S 声场扩展、平衡/增益/限幅；prepare 时预分配全部缓冲，实时线程零分配。
- 频谱：`EQSpectrumRing`（16384 样本环形缓冲）→ `EQSpectrumAnalyzer`（4096 点 Hann + vDSP FFT）；**修复 FFT 幅度未归一化导致的平顶高原**（vDSP_HANN_DENORM 输出乘 2/N 恢复真实幅度），dB 窗口 -70~0dB、8dB 高频倾斜、^1.5 对比拉伸；聚合提取为纯函数 `computeLevels` 并由单元测试覆盖。
- 连播增强：单 AVPlayer 扩展为 engineA/engineB 双引擎乒乓，active/standby 翻转，gain 叠加用户音量；crossfade 30fps ramp + fadeGeneration 代数号；gapless preroll + boundaryTimeObserver（结尾前 60ms 接管）。
- 新增 UserDefaults 键：`ManyuMusic.gaplessPlayback`、`ManyuMusic.crossfadeEnabled`、`ManyuMusic.crossfadeDuration` 及音效增强/31 段 Q 值相关键，全部有默认值，老版本偏好不受影响。

### beta4 兼容性与迁移

- 仅支持 Apple 芯片（arm64）、macOS 14 及以上；ad-hoc 签名、未公证，他机首次打开需右键 → 打开。
- Gapless/Crossfade/音效增强/EQ 默认全部关闭，关闭状态播放链路与 beta3 完全一致。
- 旧十段 EQ 增益与自定义预设首次启动自动插值迁移为 31 段，不丢数据。
- 81/81 单元测试通过（均衡器 12 + 音效增强 12 + 连播增强 8 + 频谱 2 + 既有回归 47）。

### beta4 验证

- `swift build -c release --disable-sandbox`：编译通过。
- `swift test --disable-sandbox`：81/81 通过。
- DMG 资产 `ManyuMusic-3.13.0-beta4.dmg`（10,064,380 字节，SHA-256 `20fb6a538521c87e9f54e88bfd2d776d9780d8a7f51b96808a5b214bb5e294f4`），挂载校验含 app + Applications 软链、卷内 app 版本/签名通过；卷宗白色图标；发布后从 GitHub 回下载比对 SHA256 一致。
- GitHub Release：https://github.com/jader12138/ManYu_Music/releases/tag/v3.13.0-beta4 ，prerelease、make_latest=false（不顶替 v3.12.0，「最新正式版」仍为 v3.12.0）。
- 标签 `v3.13.0-beta4`（annotated，对象 361d670）打在 main a1f2632 上；main 已推送（20+ 提交全部入库）。
- 待人工验收：EQ/音效增强实际听感、Gapless 衔接与 Crossfade 手感。

### 已知问题与后续

- 未做 Developer ID 签名与公证，正式发布前必须接入。
- 「高级功能」页签仍为占位。
- 听感类参数（频谱动态、crossfade 默认时长、增强上限）根据内测反馈继续微调；正式发布时版本号定为 3.13.0。

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

## 附录：v1.0.0-beta1 发布记录（2026-09-23 已发布）

- GitHub Release：https://github.com/jader12138/ManYu_Music/releases/tag/v1.0.0-beta1 ，prerelease=true、make_latest=false（「最新正式版」仍为 v0.5）。
- 标签 `v1.0.0-beta1`（annotated，对象 `e3ffe08`）打在 main 合并提交 `8b89fcd` 上（合并分支 `codex/version-1.0-beta1`，内含版本线文档 `541f5db`、改号 `c2d6b5c`、侧栏旧 Logo 修复 `8506c04`）；功能分支合并后已从远端与本地删除。
- 版本：`VERSION=1.0.0-beta1`，包内 `CFBundleShortVersionString=1.0.0`、`CFBundleVersion=269`、`ManyuMusicReleaseName=1.0.0-beta1`，设置 → 关于显示「1.0.0-beta1（build 269）/ 内部测试版」。
- DMG 资产 `ManyuMusic-1.0.0-beta1.dmg`（10,857,682 字节，SHA-256 `e4c39c8ba4301a85e26d489360d413b89b7203c927f627aa7858a1d3b9246184`），UDZO 压缩、卷宗白色图标（`.VolumeIcon.icns` + SetFile C/V）；挂载校验含 app + Applications 软链、包内版本/签名（`codesign --verify --deep --strict`）通过、`lipo -archs` = arm64；发布后从 GitHub 回下载 SHA-256 一致。
- 内容范围：自 v0.10（原 beta5）以来合入 main 的全部工作——播放 CPU/封面性能优化、发布前极限排雷两处闪退修复、侧栏旧代码 Logo 删除、设置外观预览缩略图、全局 tooltip 禁用、主窗口固定位置、播放统计、重复歌曲检测、双语歌词、启动自动扫库、拼音搜索、音频参数弹层、音量控件重做与静音、后台播放与迷你播放器打磨等（详见 CHANGELOG 的 v1.0.0-beta1 区块）。
- 验证：`swift test --disable-sandbox` 全部套件 0 failures；release 打包 + ad-hoc 签名成功；合并后在 main 重新构建 `dist/漫域音乐.app` 并强杀旧进程（按 PID，中文名 pkill 会静默失败）启动新包，进程路径与侧栏新 Logo 实拍确认。

## 修订记录

暂无。
