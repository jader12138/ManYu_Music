import SwiftUI

struct LyricTimelineView: View {
    let lines: [LyricLine]
    @ObservedObject var clock: PlaybackClock
    let seek: (Double) -> Void
    var baseFontSize: CGFloat = 18
    var fontDesign: Font.Design = .rounded
    var textColor: Color = .hpTextPrimary
    var lineSpacingScale: CGFloat = 0.9
    var visibleLineCount: Int = 9

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let stackSpacing = max(8, baseFontSize * 0.72 * lineSpacingScale)
            // Resolved once per pass and handed to the rows, which previously
            // recomputed the same scan for every line.
            let activeIndex = currentLineIndex
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
                    .padding(.vertical, max(60, geometry.size.height * 0.34))
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
                    scroll(to: activeIndex, proxy: proxy, animated: false)
                }
                .onChange(of: activeIndex) { _, index in
                    scroll(to: index, proxy: proxy, animated: !reduceMotion)
                }
            }
        }
    }

    /// Index of the line matching the current playback position, or -1 when
    /// none has been reached yet. Lines without a timestamp are skipped, so
    /// the result stays -1 when nothing in the list is timed.
    private var currentLineIndex: Int {
        let threshold = clock.currentTime + 0.12
        var result = -1
        for (index, line) in lines.enumerated() {
            guard let time = line.time else { continue }
            if time <= threshold {
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
                .blur(radius: distance > 2 ? 0.35 : 0)
                .shadow(
                    color: textColor.opacity(isCurrent ? 0.18 : 0),
                    radius: isCurrent ? 4 : 0,
                    y: isCurrent ? 1 : 0
                )
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.30), value: activeIndex)
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
        if animated, !reduceMotion {
            // 临界阻尼弹簧：平滑滑到位、不回弹，连续换行时观感连贯。
            withAnimation(.spring(response: 0.45, dampingFraction: 1.0)) {
                proxy.scrollTo(index, anchor: .center)
            }
        } else {
            proxy.scrollTo(index, anchor: .center)
        }
    }
}
