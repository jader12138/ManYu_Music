# 下一版本（尚未分配版本号）

- 发布状态：待发布（资料库性能优化与三项功能更新已合并，等待发版）
- 上一稳定版本：`v3.10.0`
- 当前 `VERSION`：`3.10.0`

## 摘要

本批次包含资料库性能优化与三项功能更新：首页"最近添加"改为纵向网格平铺并新增亚克力快捷按钮（含"继续播放"）、左上角品牌图标随昼夜模式切换、修复"每次打开软件时更新"的首页推荐在切换页面后被重新随机的问题。

## 用户可见更新

### 新增

- 「回到顶部」悬浮按钮：在歌曲页、首页等内容页向下滚得较远（距顶超过约 300pt）后，只要向上滚动一下，内容区右下角会出现悬浮圆形按钮（浮在所有页面之上、不嵌进任何页面），点击后平滑滚回列表顶部；向下滚动或距顶部不足 80pt 时自动隐藏，侧栏与播放队列的滚动不会触发。
- 启动预加载：设置 → 资料库新增"启动时预加载封面"开关（默认关闭）。开启后软件启动（以及开关打开的那一刻）会在后台把封面按显示档位提前解码进缓存：小档（128px）覆盖全部曲目行缩略图，中档（384px）按专辑去重覆盖专辑/艺术家网格与首页卡片；逐项低优先级推进并周期让步，不抢占滚动与播放等前台工作。浏览歌曲页、首页、专辑/艺术家页时封面即取即用，不再等待解码。
- 播放页音量控制：控制行"喜欢"右侧新增小喇叭音量键——点击弹出横向滑块（可点击轨道或拖动小球调整），点击滑块与喇叭以外的任意位置自动收起（那次点击本身的功能照常执行）；滑块展开期间关闭悬停滚轮调节；收起时悬停喇叭上下滚动可调音量，图标下方小字实时显示音量数字。
- 播放模式互斥：开启随机播放自动退出循环模式，进入循环（含单曲循环）自动关闭随机；随机/循环移到"上一曲"左侧，选中时按钮本身不再亮起，改为图标下方主题色小点（顺序播放无点）。
- 播放页歌曲标题改用专辑封面主色与白色的混合渐变（浅色模式下文字端自动换成深色保证可读），切歌时颜色平滑过渡。
- 播放页背景渐变缓慢流动：主渐变 90 秒一个来回摆动、两个封面色光斑 55-68 秒漂移（遵循"减弱动态效果"设置）。
- 歌词进度微调：播放页歌词设置面板内新增"进度"行，按 0.2 秒步进把歌词整体提前或延后（上限 ±10 秒），实时生效并按歌曲自动记忆；重置按钮常驻，重置后仅置灰、面板不跳动。
- 播放页专辑图下方控件区最右侧新增收藏爱心：点击收藏/取消收藏当前歌曲，收藏后呈实心高亮，与"收藏"页面实时同步；底部播放栏歌曲信息旁同样提供爱心按钮。
- 首页新增"继续播放"按钮：恢复上次退出时的曲目与进度接着播放；无可恢复进度时置灰。
- 左上角品牌图标随昼夜模式切换：白天显示白色图标、夜间显示深色图标，带淡入过渡（遵循"减弱动态效果"设置）。

### 改进

- 长时间听歌内存防护与占用优化：系统内存吃紧时自动清空可再生成缓存（封面缓存），播放状态不受影响；「回到顶部」滚动位置记录改为弱键 NSMapTable，滚动视图销毁后条目自动清除；新增"连续切歌 300 次"压力测试，防止未来改动引入逐首累积的泄漏。占用实测从约 290MB 降至约 170MB（大量快速切歌后）：背景模糊与光斑渲染迁移到 vImage/CG 纯 CPU 路径（消除 CoreImage 进程级 IOSurface 表面池的逐首滞留，探针实证 CI 路径每首滞留 0.5-1MB 而 CPU 路径零驻留）；封面缓存预算 48MB（LRU 淘汰，最近浏览优先）；切歌后延迟把 malloc 空闲页归还系统；播放前向缓冲上限 45 秒；已知时长曲目跳过 AVURLAsset 创建。
- 播放页转场全面丝滑化：封面转场按入口区分动效（播放栏小封面原位放大成长为大图、主页推荐封面平移就位，退出按原路返回对应封面）；换歌时后台 CoreImage 预烘焙全屏模糊背景与两个光斑，转场期间 GPU 零实时模糊滤镜；启动静默期以近乎透明方式预挂载完整播放页（含歌词、渐变、光斑、几何配对），首次打开播放页不再有冷启动停顿；歌词面板延迟到转场动画结束后（0.65s）淡入，首次歌词布局不再与转场收尾帧争抢。
- 进入播放页更顺滑：修复背景重复实例化——播放页背景此前会被创建两份（视图内部一份 + 挂载层一份），每份都含全屏 72px 模糊封面与两组动画光斑，转场瞬间开销翻倍；现在只保留覆盖完整窗口的一份。
- 滚动更流畅：滚动条隐藏扫描改为仅在滚动视图仍开启滑块时写回，消除重复赋值触发的 NSScrollView 重布局（此前表现为滚动中每 1.5 秒一次的周期性顿挫）。
- 切歌不再卡主线程：封面主色提取从主线程移到后台任务；Dock 图标（512px 画布 + 阴影 + 渐变 + 二次主色提取）整体移到后台串行队列渲染，回主线程仅做赋值，并带代数号丢弃过期的在途渲染。点击歌曲进入播放页的瞬间，主线程不再被这些工作阻塞。
- 所有界面不再显示滚动条（含横向）：滚动操作本身不受影响，触控板/滚轮照常使用，界面两侧不再有滑块闪现。
- 歌词解析过滤"制作人员名单"行（词：/曲：/编曲：/混音：/OP： 等）与平台版权声明行：这类行以 0.1 秒间隔密集挤在歌词开头，此前会被当成歌词疯狂滚过，造成歌词与歌曲对不齐的观感；现在正文从第一句唱词开始显示。
- 歌词左右边距各加宽约一个字的宽度，长行歌词提前换行，不再被视口裁掉半个字；歌词字号/行距/行数/字体/颜色/进度微调统一收进"Aa"歌词设置面板。
- 歌词界面彻底重构：放弃 ScrollView 程序化滚动，改为自管偏移量 + 原生动画——逐行推进 0.7s、点击跳转 1.5s，任何距离都是一条连续缓动滑行；支持拖动浏览歌词，松手后下次换行自动归位。当前行的放大/缩小改为 0.45s easeInOut 渐变，不再瞬间跳大（遵循"减弱动态效果"设置）。
- 进度条重构为 TimelineView 按帧插值（30fps）：显示进度与时钟 tick 的到达时刻完全无关，消除"一跳一跳"；拖动小球实时跟手，悬停才显示小球。
- 歌曲列表排序改为点击列头：点"标题/专辑/时长"分别按歌名、专辑名字母序、时长排列，再点同一列头切换升降序；激活列旁显示深色小尖角（固定占位，不影响列头文字），与文字留约一个字宽间距。搜索框旁原排序按钮已移除，功能融合进列头；点击行播放时队列跟随当前排序。
- 窗口左上角红黄绿三键整体右移 6pt、下移 6pt，缩放窗口后保持位置。
- 首页快捷操作顺序调整为"继续播放 → 播放全部 → 随机播放"，动效一致。"继续播放"配合设置 → 播放记忆（默认开启）实现跨启动恢复：重新打开软件后点击即从上次的歌曲与进度继续。

- 界面扁平化（椒盐风格）：侧栏改为纯色平面，选中项为主题色浅色圆角块（移除左侧竖条）；底部播放条改为实色平面。首页"推荐曲目"卡片保留原有玻璃质感。
- 新增设计令牌：`HPMetrics` 圆角层级（行 10 / 卡片 16 / 瓦片 20）与 `Color.hpHairline` 发丝线。
- 全应用交互动效（Apple Music 风格）：默认无背景的按钮悬停时以圆角矩形渐显主题色，主操作按钮悬停轻微提亮上浮；侧栏导航、设置页签、详情页工具栏等均已接入。
- 所有交互按钮取消椭圆造型，统一圆角矩形；"最近添加"列表行去除常驻灰底。
- "最近添加"改为按歌曲展示：卡片显示歌曲名与演唱者，封面调小、行距更紧凑；右上角新增"封面网格 / 横向文件名列表"切换并持久保存。
- 首页改版：移除"最近播放"横滑区块，"最近添加"改为纵向平铺网格（每行约 5~6 张卡片，随窗口自适应）；快捷操作新增"继续播放"。
- 首页快捷操作改为无底色按钮（悬停显示高亮），并新增"继续播放"。
- 设置中的推荐频率选项更名为"每次打开软件时更新 / 每天更新"，并说明切换页面时推荐保持不变。
- 左上角品牌图标不再受设置中"应用图标"风格固定的限制；该设置现在只影响 Dock 图标。
- 大曲库浏览更流畅：列表、专辑、歌手、文件夹的分组与搜索结果改为后台预计算，一次事务刷新界面，浏览和滚动期间不再在渲染中排序分组。
- 封面渲染更快、内存占用更低：封面按显示尺寸分 128/384/768 三级降采样加载，列表小图不再解码原图；小尺寸缩略图不再叠加投影。
- 播放中界面更稳定：播放进度（0.25s）与睡眠定时器倒计时（1s）独立刷新，不再触发整个界面重算。
- 播放/暂停图标与详情页切换动画遵循系统"减弱动态效果"设置。

### 修复

- 修复部分 FLAC 歌曲进度条拖到最后一秒后音乐仍继续播放十几秒、歌词与歌声对不齐的问题（codex/progress-drift-fix 分支内容）：根因是播放路径的两处 `AVPlayerItem(url:)` 没有开启 `AVURLAssetPreferPreciseDurationAndTimingKey`（资料库扫描路径本来就开着，播放路径遗漏），AVPlayer 对部分 FLAC 采用估算时序，实际收尾可超出元数据声明时长近 20 秒（实测《阴天快乐》声明 261.48s、播放路径却播到 280.96s，而 afinfo / AVAssetReader / 逐帧解码与资料库时长均为 261.48s）。恢复播放与切歌两个播放入口、以及 `refreshDuration` 的兜底读取统一改为带精确解析选项创建资产，歌曲现在精确在真实时长处结束。
- 修复进度条逐渐超前于歌声：周期时间观察器的 tick 投递到主线程存在几十毫秒延迟，该延迟会逐次累积进锚点墙钟，而旧的"单次相对偏差 > 1 秒才重同步"判定永远触发不了，显示进度越跑越超前。改为检查"显示插值与真实媒体时间的绝对偏差 > 0.35 秒"立即重锚，累积误差最多存活一个 tick（0.25 秒），tick 之间的按帧插值平滑保持不变。
- Dock 图标启动跳变修复（codex/dock-icon-persist 分支内容）：`AppIconStyleManager.apply()` 每次解析出具体图标（深色/浅色）时持久化到 UserDefaults（`ManyuMusic.lastResolvedAppIconStyle`）；新增 `applyLastUsedIcon()` 在 `applicationDidFinishLaunching` 第一步直接恢复上一次会话的具体图标，跳过启动早期不可靠的 `effectiveAppearance` 解析（SwiftUI 首窗创建前可能返回错误外观，导致图标从深色跳成浅色）；启动约 0.8 秒后执行一次 `apply()` 校正，仅在两次会话之间系统/主题外观真的变化时才会产生一次可见切换。
- 预加载效果修复（codex/preload-cache-hit 分支内容）：`LazyArtworkView` 缓存命中后改为在 body 中同步解析、随首帧渲染，不再"占位图 → task 下一帧换图"闪烁；封面图状态带请求标识，视图复用换曲目时不会闪上一首的封面。封面缓存成本上限 128MB→256MB、条目上限 900→1200（预热总量约等于小档全部曲目 + 中档全部专辑，此前超出 128MB 会被 NSCache 挤掉一部分，表现为部分封面仍需现加载）。预热循环对已缓存项目跳过让步等待、直接快进。
- 修复点击歌词/进度条跳转后进度显示与时钟"乒乓"冲突的问题：seek 落位完成前丢弃观察器的旧位置回调，跳转后进度条不再回跳抖动。
- 修复"每次打开软件时更新"的首页推荐在切换页面后被重新随机的问题：推荐现在在整个运行期间保持稳定，重启应用后才更换。
- 补齐歌单/专辑/歌手详情页缺失的过渡动画定义（编译错误修复）。

## 技术变更

- 播放精确时序（codex/progress-drift-fix）：`AudioPlayer` 新增 `private static func makePlaybackItem(url:)`，以 `AVURLAsset(url:options:[AVURLAssetPreferPreciseDurationAndTimingKey: true])` 构建 `AVPlayerItem`；恢复播放（`resumeSavedPlayback`）、切歌（`play(_:)`）两处 `replaceCurrentItem` 与 `refreshDuration` 的兜底时长读取统一走该入口，资料库扫描路径原本就带此选项。
- 进度漂移兜底：`PlaybackProgressRow.onChange(of: clock.currentTime)` 的重同步判定由"tick 增量与墙钟增量的相对偏差 > 1 秒"改为计算当前显示插值（`anchorTime + Date() - anchorWall`，暂停时直接取锚点值）与新媒体时间的**绝对偏差**，超过 0.35 秒或处于暂停态立即重锚；正常推进分支不变，tick 间仍由 TimelineView 按帧插值。
- 内存防护：新增 `MemoryPressureMonitor`（`DispatchSource.makeMemoryPressureSource` 监听 warning/critical，主线程回调清空 `ArtworkCache`（新增 `removeAllObjects()`），启动时在 AppDelegate 安装）；`BackToTopController.lastYByKey` 由 `[ObjectIdentifier: CGFloat]` 改为弱键 `NSMapTable`（滚动视图销毁后条目自动清除，消除应用内唯一无界集合）；新增 `LongSessionMemoryTests`（真实 WAV 文件 + 真实 AudioPlayer 连续切歌 300 次，phys_footprint 增长 < 80MB 断言，测试前后快照/恢复 UserDefaults 项目键以保护用户真实播放状态）；`BlurredBackdropRenderer` 重写为 vImage 三通盒式模糊 + CG 径向渐变（import Accelerate，全程无 CoreImage）；`AudioPlayer` 切歌后 4 秒 `malloc_zone_pressure_relief` 归还空闲页、`AVPlayerItem.preferredForwardBufferDuration = 45`、`refreshDuration` 仅在曲目无时长时建 AVURLAsset；封面缓存预算 48MB / 320 条。
- 转场与预热：`NowPlayingView` 接受 `artworkEntry`（`NowPlayingEntry`）按入口选择大封面 matched geometry 目标（播放栏放大成长 / 主页推荐平移就位），转场其余元素纯 opacity 淡入淡出；`BlurredBackdropRenderer` 新增 `image(from:)`（512px 高斯模糊背景）与 `blurredOrb(color:diameter:blurRadius:)`（1/4 分辨率烘焙光斑，返回图与显示尺寸）；`AudioPlayer` 新增 `orbPrimaryImage/orbSecondaryImage` 发布属性，调色板就绪后在后台并行烘焙光斑，`NowPlayingBackdrop` 光斑优先用预烘焙图、未就绪回退实时模糊；`MainView` 启动 1.5s 后以 0.01 透明度挂载完整 `NowPlayingView` 预热实例 1.2s（专用 `@Namespace`，与真实转场互不干扰），首次打开无冷启动停顿；歌词 `lyricsReady` 延迟 0.65s（> spring 0.56s）+ 0.25s 淡入。
- 回到顶部：新增 `BackToTopController`——监听窗口内所有 NSScrollView 的 clipView bounds 通知（SwiftUI ScrollView/List 底层即 NSScrollView），切页懒创建的新滚动视图由 didBecomeMain 通知 + 2 秒低频扫描兜底开启 `postsBoundsChangedNotifications`；按窗口横坐标（24–320pt）过滤出主内容区，排除侧栏与队列面板；方向判定用相邻两次 origin.y 差值（>0.5pt 才计入）。按钮由 `MainView.detail` 的 `overlay(alignment: .bottomTrailing)` 挂载；点击回顶为 60fps 逐帧 easeInOutCubic 插值动画（时长 0.4–0.9s 随距离自适应，NSScrollView 隐式动画在 SwiftUI 滚动视图上不生效），动画期间忽略自身驱动的回调、用户手动滚动（与上一帧偏差 >2pt）即打断动画转入正常判定。
- Dock 图标持久化：`AppIconStyleManager` 新增 `lastResolvedStyleKey` 持久化与 `applyLastUsedIcon()`；`applicationDidFinishLaunching` 改为先恢复上次图标、延迟 0.8 秒再校正。
- 预加载调优：`LazyArtworkView` 用 `currentImage`（缓存同步查找 + 带请求标识的加载状态）在 body 内解析封面；`ArtworkCache.countLimit` 900→1200、`totalCostLimit` 128MB→256MB。
- 启动预加载：新增 `ArtworkPreloader`（MainActor 单例，低优先级 Task 逐项调用 `ArtworkPipeline`，每项间隔 3ms 让步；开关 key `ManyuMusic.preloadArtwork`，幂等防重入，运行中检测开关关闭即中止）。触发点：MainView 在资料库加载完成时、设置里打开开关时。
- 性能优化：`NowPlayingView` 不再在内部 ZStack 重复挂载 `NowPlayingBackdrop`（由 MainView 统一挂载一份）；`AudioPlayer.loadArtwork` 的 `ArtworkPaletteExtractor.palette(from:)` 改为 `Task.detached` 后台执行（带当前曲目校验防串歌）；`DockArtworkController` 新增后台串行渲染队列与 `renderGeneration` 代数号，`makeDockIcon`/`aspectFillRect` 改为 static 以脱离 MainActor 隔离。
- 全局隐藏滚动条：`AppDelegate` 启动时安装扫描器（1.5 秒低频定时 + 启动后延迟扫描 + 窗口成为主窗口通知），递归遍历可见窗口视图树，把所有 `NSScrollView` 的 `hasVerticalScroller`/`hasHorizontalScroller` 置为 false（仅在仍开启时写回，避免重复赋值触发布局），覆盖 SwiftUI 懒创建的滚动视图；纯 Swift 实现，无 swizzle/hook。
- `AudioPlayer` 新增按歌曲记忆的歌词时间轴偏移（`lyricOffset`，UserDefaults 字典存储，键为 track UUID，不动 library.json 格式）；`LyricTimelineView.lineIndex` 按偏移平移歌词时间轴，偏移变化时立即重算当前行。
- `NowPlayingView` 音量滑块为浮层（不占控制行布局，展开/收起不影响其他控件）；"点击热区外收起"由 `NSEvent.addLocalMonitorForEvents` 全局鼠标监视实现——共享展开状态与热区坐标存放于引用类型 `VolumeDismissState`（从 NSEvent 闭包读 `@State` 会拿到旧快照），热区坐标由挂在喇叭上的 `VolumeFrameReporter`（NSView `convert` 到窗口坐标）实时上报；监视器只观察不拦截事件，点击穿透照常。
- `NowPlayingView` 标题渐变与背景流动：标题用 `ArtworkPalette` 主色 → 白色（浅色模式换深色）`LinearGradient`，背景 `TimelineView` 驱动极慢相位摆动。
- `LyricsParser` 新增 credits 行过滤：冒号前缀匹配分工词白名单（支持"鼓/打击乐"组合前缀、排除含正文字符的行）+ 英文 "by" 格式 + 平台版权声明，带时间戳与纯文本两种路径均不输出名单行。
- `PlaybackClock` 新增 seek 在途标记：`seek(to:)` 落位回调前丢弃周期观察器的旧位置，时钟不再与显示层乒乓；落位后写入实测位置并强制持久化。
- `LyricTimelineView` 重写为自管偏移视图：普通 VStack + 预测量行高解析计算居中，滚动只改 `currentOffset`；行字号字重恒定，强调仅靠 `scaleEffect`（带 0.45s 渐变），行位置测量不受滚动平移污染。
- `PlaybackProgressRow` 记录 tick 锚点（媒体时间 + 墙钟）由 `TimelineView(.animation)` 按帧插值，tick 投递延迟不进入显示；`SmoothScrubber` 拖动期间本地覆盖显示值。
- 新增 `LibraryBrowseSnapshot` / `LibraryBrowseRequest`：浏览结果在主线程外构建为不可变快照，视图仅读取数组。
- 新增 `ArtworkPipeline`：ImageIO 按三级像素档位降采样，缓存键为"文件 + 档位"，缓存上限 320 条 / 128MB。
- 新增 `PlaybackClock`：高频进度从 `AudioPlayer` 拆出，`objectWillChange` 不再被进度 tick 触发。
- `LibraryStore` 新增会话级 `sessionRecommendationTrackID`："每次打开"模式的首页推荐在整个运行期间稳定，重启后重新挑选。
- `BrandMark` 不再读取图标风格设置，直接按当前 colorScheme 解析 AppIconLight / AppIconDark。
- `HomeView`："最近添加"改用 `LazyVGrid`，`HomeAlbumCard` 封面随列宽自适应（GeometryReader 保持方形）；移除"最近播放"区块、`HomeTrackCard` 与 `recentTracks` 参数；快捷按钮抽为 `quickActionButton`。
- `AppTheme` 缩略图按尺寸跳过投影；新增 `PlaybackPressButtonStyle` 支持 Reduce Motion。
- 新增 `Tests/HarmonyPlayerTests`：资料库持久化、浏览快照（含性能基准）、封面管线、播放时钟隔离共 20 个测试。

## 兼容性与迁移

- 无数据格式或用户配置迁移；`library.json` 持久化格式保持不变，旧文件可正常加载。

## 验证

- 进度漂移修复分支（codex/progress-drift-fix）合并前：`swift test` 27/27 通过；用户实测两首 FLAC 精确在显示终点结束、音乐完整、歌词对齐；另以 `AVAudioFile` 全速逐帧解码到 EOF 的方式静态比对 7 首 FLAC（Creep、南山南、平凡之路、浮夸、我记得、tired、阴天快乐）的声明时长与实际采样时长，偏差全部 0.00s（CLI 内驱动 AVPlayer 异步播放探针收不到结束通知、不可靠，故改用静态解码验证）；关键案例《阴天快乐》声明 261.48s，修复前播放路径播到 280.96s（超 19.5s），afinfo / AVAssetReader / 资料库时长三方均为 261.48s，确认唯一跑偏环节是播放路径的估算解析；联网佐证 Apple Developer Forums thread/665417 中 Apple 工程师确认 `AVURLAssetPreferPreciseDurationAndTimingKey: true` 为 FLAC seek/时长偏差的正确解法。Release 构建签名后实际运行由用户验证通过。
- 内存防护分支（codex/memory-leak-guard）合并前：`swift test` 27/27 通过；vmmap 实测定位 IOSurface 滞留（CoreImage 表面池）并用独立探针对比三种渲染策略后实施 CPU 渲染方案；用户实测大量快速切歌后驻留内存约 170MB（此前 290-300MB 不回落），慢速听歌约 100MB；Release 构建签名后实际运行验证背景/光斑观感不变。
- 播放页转场丝滑化分支（codex/nowplaying-warmup，叠加 codex/nowplaying-transition 与 codex/hero-transition 已合并内容）合并前：以临时探针实测（2ms 主线程心跳看门狗 + 事件打点）定位出首次进入播放页 191ms 冷启动停顿与歌词挂载 26-39ms 尾部顿挫；实施完整播放页启动预热、光斑预烘焙与歌词延迟挂载后复测无主线程停顿；移除探针后 `swift test` 26/26 通过，Release 构建签名后实际运行验证：重复进出播放页无可感顿挫，首次点击仅剩切歌内容中途换入的极轻微感（收益递减，未再深挖）。
- `swift build` 通过（macOS 14, arm64）。
- `swift test` 20 个测试全部通过（0 失败），含 10,000 首内存基准测量。
- 三个功能分支逐一合并入 main 后，在合并结果上重新执行 `swift test`（20/20 通过）并完成 Release 打包与签名验证。
- 收藏爱心与歌词/进度条重构分支（codex/favorite-lyrics-smoothness）合并前：`swift test` 20/20 通过，Release 构建签名后实际运行验证——歌词滚动与点击跳转连续缓动、进度条无回跳抖动、收藏状态两处同步。
- 歌词偏移与 credits 过滤分支（codex/lyric-offset）合并前：`swift test` 26/26 通过（含 6 个新增解析器测试：credits 过滤、offset 标签、多时间戳、小数精度、纯文本回退）；Release 构建签名后实际运行验证进度微调实时生效、按歌记忆、面板不跳动。
- 播放页视觉与音量分支（codex/nowplaying-cover-gradient）合并前：`swift test` 26/26 通过；Release 构建签名后实际运行验证标题渐变随封面切换、背景缓慢流动、音量滑块展开/拖动/点击外部收起全链路（热区外点击收起且功能穿透、滑块内拖动不误收）。

## 已知问题与后续

- 后续继续执行一功能一分支，合并和发布完成后删除已用完的分支
- 性能基准为本机相对测量值，不代表 FPS 或启动耗时等用户可见指标

## 修订记录

- 2026-09-16：首次记录资料库性能优化分支的合并内容。
- 2026-09-17：补充收藏爱心与歌词/进度条重构分支（codex/favorite-lyrics-smoothness）的合并内容；补充歌词进度微调、credits 过滤与歌词边距分支的合并内容。
- 2026-09-17：补充播放页视觉与音量分支（codex/nowplaying-cover-gradient）的合并内容——标题封面渐变、背景缓慢流动、小喇叭音量滑块（含点击外部收起）、随机/循环互斥与小点选中样式。
- 2026-09-17：补充隐藏滚动条分支（codex/hide-scrollbars）的合并内容——所有界面不再显示滚动条。
- 2026-09-17：补充性能优化分支（codex/perf-smooth-scroll）的内容——去重播放页背景、主色提取与 Dock 图标后台化、滚动条扫描幂等化。
- 2026-09-17：补充启动预加载分支（codex/startup-preload）的内容——设置新增启动预加载开关与 ArtworkPreloader。
- 2026-09-17：补充预加载调优分支（codex/preload-cache-hit）的内容——缓存命中同步渲染、缓存上限放宽、预热快进。
- 2026-09-17：补充 Dock 图标持久化分支（codex/dock-icon-persist）的内容——启动直接恢复上次会话的具体图标样式。
- 2026-09-17：补充回到顶部悬浮按钮分支（codex/back-to-top）的内容。
- 2026-09-17：补充播放页转场丝滑化与启动预热分支（codex/nowplaying-transition、codex/hero-transition 已合并，codex/nowplaying-warmup 待合并）的内容——分入口封面动效、背景/光斑 CoreImage 预烘焙、完整播放页启动预热、歌词延迟至转场结束后淡入。
- 2026-09-18：补充进度漂移修复分支（codex/progress-drift-fix）的内容——播放路径两处入口与时长兜底开启 AVURLAsset 精确时序解析，修复 FLAC 收尾超长与歌词不同步；进度显示改为与真实媒体时间的绝对偏差兜底重同步。
