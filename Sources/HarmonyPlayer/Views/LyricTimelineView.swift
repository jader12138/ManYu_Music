import SwiftUI

struct LyricTimelineView: View {
    let lines: [LyricLine]
    let currentTime: Double
    let seek: (Double) -> Void
    var baseFontSize: CGFloat = 18
    var fontDesign: Font.Design = .rounded
    var textColor: Color = .hpTextPrimary

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: max(13, baseFontSize * 0.82)) {
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
                        colors: [.clear, .black, .black, .black, .clear],
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
        let visibleOpacity = max(0.16, 0.56 - Double(distance) * 0.11)

        return Button {
            guard let time = line.time else { return }
            seek(time)
        } label: {
            Text(line.text)
                .font(.system(
                    size: isCurrent ? baseFontSize * 1.28 : baseFontSize,
                    weight: isCurrent ? .bold : .medium,
                    design: fontDesign
                ))
                .foregroundStyle(
                    isCurrent
                        ? textColor
                        : textColor.opacity(visibleOpacity)
                )
                .multilineTextAlignment(.center)
                .lineSpacing(max(3, baseFontSize * 0.22))
                .padding(.horizontal, 14)
                .padding(.vertical, 3)
                .scaleEffect(isCurrent ? 1.015 : max(0.94, 1 - CGFloat(distance) * 0.01))
                .blur(radius: distance > 3 ? 0.25 : 0)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.34), value: currentIndex)
        .help(line.time == nil ? "" : "点击跳到这一句")
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
