import SwiftUI

struct LyricTimelineView: View {
    let lines: [LyricLine]
    let currentTime: Double
    let seek: (Double) -> Void
    var baseFontSize: CGFloat = 18
    var fontDesign: Font.Design = .rounded
    var textColor: Color = .hpTextPrimary
    var lineSpacingScale: CGFloat = 0.9
    var visibleLineCount: Int = 9

    var body: some View {
        GeometryReader { geometry in
            let stackSpacing = max(8, baseFontSize * 0.72 * lineSpacingScale)
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: stackSpacing) {
                        ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                            lyricLine(line, index: index)
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
                    scroll(to: currentIndex, proxy: proxy, animated: false)
                }
                .onChange(of: currentIndex) { _, index in
                    scroll(to: index, proxy: proxy, animated: true)
                }
            }
        }
    }

    private var currentIndex: Int {
        guard lines.contains(where: { $0.time != nil }) else { return -1 }

        var result = -1
        for (index, line) in lines.enumerated() {
            guard let time = line.time else { continue }
            if time <= currentTime + 0.12 {
                result = index
            } else {
                break
            }
        }
        return result
    }

    private func lyricLine(_ line: LyricLine, index: Int) -> some View {
        let isCurrent = index == currentIndex
        let distance = currentIndex >= 0 ? abs(index - currentIndex) : 0
        let visibleRadius = max(2, visibleLineCount / 2)
        let fadeStep = 0.46 / Double(visibleRadius)
        let visibleOpacity = max(0.10, 0.58 - Double(distance) * fadeStep)

        return Button {
            guard let time = line.time else { return }
            seek(time)
        } label: {
            Text(line.text)
                .font(.system(
                    size: isCurrent ? baseFontSize * 1.34 : baseFontSize,
                    weight: isCurrent ? .bold : .medium,
                    design: fontDesign
                ))
                .foregroundStyle(lineForegroundStyle(isCurrent: isCurrent, opacity: visibleOpacity))
                .multilineTextAlignment(.center)
                .lineSpacing(max(3, baseFontSize * 0.22))
                .padding(.horizontal, 14)
                .padding(.vertical, max(1.5, baseFontSize * 0.12 * lineSpacingScale))
                .scaleEffect(isCurrent ? 1.025 : max(0.92, 1 - CGFloat(distance) * 0.012))
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
        .animation(.easeInOut(duration: 0.34), value: currentIndex)
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
        if animated {
            withAnimation(.spring(response: 0.52, dampingFraction: 0.86)) {
                proxy.scrollTo(index, anchor: .center)
            }
        } else {
            proxy.scrollTo(index, anchor: .center)
        }
    }
}
