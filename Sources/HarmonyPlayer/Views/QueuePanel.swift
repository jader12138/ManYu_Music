import SwiftUI

struct QueuePanel: View {
    let close: () -> Void

    @EnvironmentObject private var player: AudioPlayer

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("播放队列")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Text("\(player.queue.count) 首歌曲")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !player.queue.isEmpty {
                    IconButton(systemName: "trash", help: "清空队列", size: 12) {
                        player.clearQueue()
                    }
                }
                IconButton(systemName: "xmark", help: "关闭队列", size: 12, action: close)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider().opacity(0.55)

            if player.queue.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 26))
                        .foregroundStyle(.tertiary)
                    Text("队列还是空的")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        // 把 queue 旋转：当前播放的放最上，后面依次是接下来要播的。
                        // 点击"下一首"或随机挑一首后 currentIndex 自然后移，列表顺序跟着转。
                        let queue = player.queue
                        let base = player.currentIndex ?? 0
                        let rotated = Array(queue[base...]) + Array(queue[..<base])
                        ForEach(Array(rotated.enumerated()), id: \.element.id) { offset, track in
                            // rotated[0] 是当前正在播的，它在 queue 里的原索引才是 currentIndex。
                            let originalIndex = (base + offset) % queue.count
                            queueRow(track: track, index: originalIndex, displayOffset: offset)
                        }
                    }
                    .padding(8)
                }
            }
        }
        .frame(width: 276)
        .background(Color.hpSurface.opacity(0.94))
    }

    private func queueRow(track: Track, index: Int, displayOffset: Int) -> some View {
        let isCurrent = player.currentIndex == index
        return Button {
            player.playFromQueue(at: index)
        } label: {
            HStack(spacing: 10) {
                Group {
                    if isCurrent {
                        Image(systemName: player.isPlaying ? "waveform" : "pause.fill")
                            .foregroundStyle(Color.hpAccent)
                    } else {
                        // 序号按旋转后的显示顺序：当前在 0 位，下一首显示 1，依次递增。
                        Text("\(displayOffset + 1)")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.displayTitle)
                        .font(.system(size: 11, weight: isCurrent ? .semibold : .medium))
                        .foregroundStyle(isCurrent ? Color.hpAccent : Color.primary)
                        .lineLimit(1)
                    Text(track.displayArtist)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                Text(track.formattedDuration)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .frame(height: 47)
            .background(
                isCurrent ? Color.hpAccent.opacity(0.09) : Color.clear,
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("下一首播放") {
                player.playNext(track)
            }

            if player.currentIndex != index {
                Button(role: .destructive) {
                    player.removeFromQueue(at: IndexSet(integer: index))
                } label: {
                    Label("从队列移除", systemImage: "minus.circle")
                }
            }
        }
    }
}
