import SwiftUI

struct TrackInfoView: View {
    let track: Track

    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("歌曲信息")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Text(track.displayTitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                IconButton(systemName: "xmark", help: "关闭", size: 12) {
                    dismiss()
                }
            }

            infoRow("标题", track.displayTitle)
            infoRow("艺人", track.displayArtist)
            infoRow("专辑", track.displayAlbum)
            infoRow("时长", Track.formatTime(track.duration))
            // 格式行单独着色：与列表/播放条徽标同色，便于快速辨识文件类型
            HStack(alignment: .top, spacing: 18) {
                Text("格式")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 62, alignment: .trailing)
                Text(track.url.pathExtension.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.formatColor(forExtension: track.url.pathExtension))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            infoRow("比特率", formattedBitrate)
            infoRow("采样率", formattedSampleRate)
            infoRow("通道", formattedChannels)
            infoRow("播放次数", "\(library.playCount(for: track))")
            infoRow("文件大小", fileSize)
            infoRow("文件位置", track.url.path)
        }
        .padding(24)
        .frame(width: 520)
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 18) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .trailing)

            Text(value)
                .font(.system(size: 11, weight: .medium))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var fileSize: String {
        guard let values = try? track.url.resourceValues(forKeys: [.fileSizeKey]),
              let bytes = values.fileSize else {
            return "未知"
        }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    /// 比特率：bps → kbps / Mbps。320 kbps MP3、1411 kbps CD- WAV、≥1 Mbps 用 Mbps。
    private var formattedBitrate: String {
        guard let bps = track.bitrate, bps > 0 else { return "未知" }
        if bps >= 1_000_000 {
            return String(format: "%.2f Mbps", Double(bps) / 1_000_000)
        }
        return "\(Int((Double(bps) / 1000).rounded())) kbps"
    }

    /// 采样率：Hz → kHz。44100 → "44.1 kHz"，48000 → "48 kHz"，96000 → "96 kHz"。
    private var formattedSampleRate: String {
        guard let hz = track.sampleRate, hz > 0 else { return "未知" }
        if hz % 1000 == 0 {
            return "\(hz / 1000) kHz"
        }
        return String(format: "%.1f kHz", Double(hz) / 1000)
    }

    /// 通道：1 → 单声道，2 → 立体声，其他 → "N 声道"。
    private var formattedChannels: String {
        guard let ch = track.channels, ch > 0 else { return "未知" }
        switch ch {
        case 1: return "单声道"
        case 2: return "立体声"
        default: return "\(ch) 声道"
        }
    }
}
