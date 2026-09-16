import SwiftUI

/// Apple Music 风格的歌词时间轴。
///
/// 刻意不使用 ScrollView/ScrollViewReader：macOS 上程序化 scrollTo 的动画
/// 不可靠（远距离经常不播动画直接跳变），这是此前歌词跳转"僵硬"的根因。
/// 这里改为自管内容偏移量——行位置在布局后测量一次，之后所有滚动都只是
/// 对单个 offset 值的原生动画（平移变换，逐帧合成、不触发布局），任何
/// 距离都必然是一条连续的缓动滑行，且渲染开销极低，不会与进度条动画
/// 互相争抢主线程。
struct LyricTimelineView: View {
    let lines: [LyricLine]
    // 故意不用 @ObservedObject：时钟每秒发布约四次，若直接观察会带动
    // 整个歌词列表以同样频率整表重算。这里只订阅 currentTime，
    // 在当前行真正变化时才更新 @State。
    let clock: PlaybackClock
    let seek: (Double) -> Void
    var baseFontSize: CGFloat = 18
    var fontDesign: Font.Design = .rounded
    var textColor: Color = .hpTextPrimary
    var lineSpacingScale: CGFloat = 0.9
    var visibleLineCount: Int = 9

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var activeIndex: Int = -1
    @State private var linePositions: [Int: CGFloat] = [:]
    @State private var currentOffset: CGFloat = 0
    @State private var dragBase: CGFloat?

    var body: some View {
        GeometryReader { geometry in
            let stackSpacing = max(8, baseFontSize * 0.72 * lineSpacingScale)
            let topPad = max(60, geometry.size.height * 0.34)
            let bottomPad = topPad + 56
            VStack(spacing: stackSpacing) {
                ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                    lyricLine(line, index: index, activeIndex: activeIndex)
                        .background(
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: LyricLinePositionsKey.self,
                                    value: [line.id: proxy.frame(in: .named("LyricContent")).midY]
                                )
                            }
                        )
                }
            }
            // 内容坐标系：行位置在内容空间内测量，外层平移不影响读数，
            // 因此拖动/滑行过程中不会触发偏好值重算。
            .coordinateSpace(name: "LyricContent")
            .padding(.top, topPad)
            .padding(.bottom, bottomPad)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .top)
            .offset(y: -currentOffset)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            .clipped()
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
            .contentShape(Rectangle())
            .gesture(dragGesture(in: geometry.size))
            .onPreferenceChange(LyricLinePositionsKey.self) { positions in
                guard positions != linePositions else { return }
                linePositions = positions
                centerActive(in: geometry.size.height, animated: false)
            }
            .onAppear {
                activeIndex = lineIndex(at: clock.currentTime)
            }
            .onReceive(clock.$currentTime) { time in
                let index = lineIndex(at: time)
                if index != activeIndex {
                    activeIndex = index
                }
            }
            .onChange(of: activeIndex) { _, _ in
                centerActive(in: geometry.size.height, animated: !reduceMotion)
            }
            .onChange(of: lines.first?.id) { _, _ in
                linePositions = [:]
                currentOffset = 0
                dragBase = nil
                activeIndex = lineIndex(at: clock.currentTime)
            }
        }
    }

    // MARK: - 滚动控制

    /// 把当前行滑到视口中心。长距离跳转与逐行推进都用同一条原生缓动，
    /// 区别只在时长：跳转 1.5 秒从容滑到，逐行 0.7 秒缓冲跟进。
    private func centerActive(in height: CGFloat, animated: Bool) {
        guard lines.indices.contains(activeIndex),
              let centerY = linePositions[lines[activeIndex].id] else { return }
        let maxOffset = max(0, contentHeight(in: height) - height)
        let target = min(max(centerY - height / 2, 0), maxOffset)
        guard animated, !reduceMotion else {
            currentOffset = target
            return
        }
        let distance = abs(target - currentOffset)
        let isLongJump = distance > max(240, height * 0.9)
        withAnimation(.easeInOut(duration: isLongJump ? 1.5 : 0.70)) {
            currentOffset = target
        }
    }

    private func contentHeight(in height: CGFloat) -> CGFloat {
        let topPad = max(60, height * 0.34)
        let bottomPad = topPad + 56
        guard let lastID = lines.last?.id, let lastY = linePositions[lastID] else { return height }
        return lastY + bottomPad + baseFontSize * 1.6
    }

    /// 拖动浏览：直接改 currentOffset（不带动画、实时跟手），
    /// 松手后停留在原地，下一次换行自动归位到当前句。
    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                if dragBase == nil { dragBase = currentOffset }
                let maxOffset = max(0, contentHeight(in: size.height) - size.height)
                currentOffset = min(max((dragBase ?? 0) - value.translation.height, 0), maxOffset)
            }
            .onEnded { _ in
                dragBase = nil
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

    // MARK: - 行渲染

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
            // 字号与字重保持恒定：只靠 scaleEffect 做强调，行高不随播放变化，
            // 测量好的行位置始终有效。
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
}

/// 汇总每行歌词在内容坐标系里的纵向中心，用于计算目标偏移。
private struct LyricLinePositionsKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] { [:] }
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
