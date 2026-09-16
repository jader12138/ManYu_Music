import SwiftUI

struct LyricTimelineView: View {
    let lines: [LyricLine]
    // 故意不用 @ObservedObject：时钟每秒发布约十次，若直接观察会让
    // 整个歌词列表以同样频率整表重算，造成滚动"一卡一卡"。
    // 这里只订阅其 currentTime，在当前行真正变化时才更新 @State。
    let clock: PlaybackClock
    let seek: (Double) -> Void
    var baseFontSize: CGFloat = 18
    var fontDesign: Font.Design = .rounded
    var textColor: Color = .hpTextPrimary
    var lineSpacingScale: CGFloat = 0.9
    var visibleLineCount: Int = 9

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var activeIndex: Int = -1
    @State private var lastScrolledIndex: Int = -1
    @State private var glideTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geometry in
            let stackSpacing = max(8, baseFontSize * 0.72 * lineSpacingScale)
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    // 普通 VStack：行数有限（歌词通常几百行以内），
                    // 避免 Lazy 版本在滚动过程中逐行实例化造成的顿挫。
                    VStack(spacing: stackSpacing) {
                        ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                            lyricLine(line, index: index, activeIndex: activeIndex)
                                .id(index)
                        }
                    }
                    // 底部留白比顶部多一截，让歌词整体视觉重心上移一点。
                    .padding(.top, max(60, geometry.size.height * 0.34))
                    .padding(.bottom, max(60, geometry.size.height * 0.34) + 56)
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity)
                }
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black.opacity(0.20), location: 0.11),
                            .init(color: .black.opacity(0.86), location: 0.30),
                            .init(color: .black, location: 0.42),
                            .init(color: .black, location: 0.58),
                            .init(color: .black.opacity(0.86), location: 0.70),
                            .init(color: .black.opacity(0.20), location: 0.89),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .onAppear {
                    activeIndex = lineIndex(at: clock.currentTime)
                    scroll(to: activeIndex, proxy: proxy, animated: false)
                }
                .onReceive(clock.$currentTime) { time in
                    let index = lineIndex(at: time)
                    if index != activeIndex {
                        activeIndex = index
                    }
                }
                .onChange(of: activeIndex) { _, index in
                    scroll(to: index, proxy: proxy, animated: !reduceMotion)
                }
                .onChange(of: lines.first?.id) { _, _ in
                    glideTask?.cancel()
                    lastScrolledIndex = -1
                    activeIndex = lineIndex(at: clock.currentTime)
                }
            }
        }
    }

    /// 与播放位置匹配的行下标；无可匹配行时为 -1。
    private func lineIndex(at time: Double) -> Int {
        let threshold = time + 0.12
        var result = -1
        for (index, line) in lines.enumerated() {
            guard let lineTime = line.time else { continue }
            if lineTime <= threshold {
                result = index
            } else {
                break
            }
        }
        return result
    }

    private func lyricLine(_ line: LyricLine, index: Int, activeIndex: Int) -> some View {
        let isCurrent = index == activeIndex
        let distance = activeIndex >= 0 ? abs(index - activeIndex) : 0
        let visibleRadius = max(2, visibleLineCount / 2)
        let fadeStep = 0.46 / Double(visibleRadius)
        let visibleOpacity = max(0.10, 0.58 - Double(distance) * fadeStep)

        return Button {
            guard let time = line.time else { return }
            seek(time)
        } label: {
            // 字号与字重保持恒定：只靠 scaleEffect 做强调，避免行高变化
            // 在滚动动画进行时改变布局、造成"卡一下"的观感。
            Text(line.text)
                .font(.system(size: baseFontSize, weight: .semibold, design: fontDesign))
                .foregroundStyle(lineForegroundStyle(isCurrent: isCurrent, opacity: visibleOpacity))
                .multilineTextAlignment(.center)
                .lineSpacing(max(3, baseFontSize * 0.22))
                .padding(.horizontal, 14)
                .padding(.vertical, max(1.5, baseFontSize * 0.12 * lineSpacingScale))
                .scaleEffect(isCurrent ? 1.30 : max(0.92, 1 - CGFloat(distance) * 0.012))
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.50), value: activeIndex)
        .help(line.time == nil ? "" : "点击跳到这一句")
    }

    private func lineForegroundStyle(isCurrent: Bool, opacity: Double) -> AnyShapeStyle {
        if isCurrent {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        textColor.opacity(0.72),
                        textColor,
                        textColor.opacity(0.78)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        }
        return AnyShapeStyle(textColor.opacity(opacity))
    }

    private func scroll(to index: Int, proxy: ScrollViewProxy, animated: Bool) {
        guard index >= 0, lines.indices.contains(index) else { return }
        glideTask?.cancel()
        guard animated, !reduceMotion else {
            proxy.scrollTo(index, anchor: .center)
            lastScrolledIndex = index
            return
        }

        let start = lastScrolledIndex
        let distance = index - start
        lastScrolledIndex = index

        // 近距离（正常逐行推进）：一段长缓动，观感是缓慢的缓冲。
        guard abs(distance) > 4 else {
            withAnimation(.easeInOut(duration: 0.70)) {
                proxy.scrollTo(index, anchor: .center)
            }
            return
        }

        // 远距离（点击跳转）：macOS 对超长距离的 scrollTo 常常直接跳变、
        // 不播动画；改为分多段滑行。中段用 linear 且各段时长一致，段与段
        // 之间速度完全连续，观感是一条匀速滑行；起段加速、末段减速。
        // 段数压低、每行不叠加阴影，控制滚动时的渲染负担，
        // 避免和左侧进度条的动画互相抢主线程。
        let hopCount = min(10, max(2, abs(distance) / 6))
        let step = Double(distance) / Double(hopCount)
        glideTask = Task { @MainActor in
            for hop in 1...hopCount {
                if Task.isCancelled { return }
                let target: Int
                let duration: Double
                switch hop {
                case 1:
                    target = min(max(start + Int(step.rounded()), 0), lines.count - 1)
                    duration = 0.22
                case hopCount:
                    target = index
                    duration = 0.38
                default:
                    target = min(max(start + Int((step * Double(hop)).rounded()), 0), lines.count - 1)
                    duration = 0.30
                }
                let curve: Animation = hop == 1
                    ? .easeIn(duration: duration)
                    : (hop == hopCount ? .easeOut(duration: duration) : .linear(duration: duration))
                withAnimation(curve) {
                    proxy.scrollTo(target, anchor: .center)
                }
                if hop < hopCount {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                }
            }
        }
    }
}
