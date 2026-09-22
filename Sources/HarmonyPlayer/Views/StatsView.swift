import AppKit
import SwiftUI

/// 播放统计页：嵌入主窗口内容区（侧栏「统计」入口），跟随白天/夜间主题。
///
/// 顶部切换「今天 / 本周 / 本月 / 本年」时间维度；
/// 主体列出该区间内每首歌的播放次数（按次数降序），
/// 顶部汇总卡片显示区间总播放次数与覆盖歌曲数。
struct StatsView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: AudioPlayer

    @State private var range: StatsRange = .week
    @State private var entries: [(track: Track, count: Int)] = []
    @State private var total: Int = 0
    @State private var loadedAt: Date = .distantPast

    var body: some View {
        VStack(spacing: 0) {
            toolbar
                .padding(.horizontal, 24)
                .padding(.top, 14)
                .padding(.bottom, 14)

            summaryCard
                .padding(.horizontal, 24)

            if entries.isEmpty {
                emptyState
            } else {
                statsList
            }
        }
        .onAppear { reload() }
        .onChange(of: range) { _, _ in reload() }
        // 播放完一首歌后 recordPlay 会 bump revision，统计自动刷新。
        .onChange(of: library.revision) { _, _ in reload() }
    }

    // MARK: - 工具行（维度切换 + 刷新）

    private var toolbar: some View {
        HStack(spacing: 6) {
            ForEach(StatsRange.allCases) { option in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        range = option
                    }
                } label: {
                    Text(option.title)
                        .font(.system(size: 12, weight: range == option ? .semibold : .medium))
                        .foregroundStyle(range == option ? Color.white : Color.hpTextPrimary.opacity(0.6))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(range == option ? Color.hpAccent : Color.hpTextPrimary.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
                .help(option.title)
            }

            Spacer()

            Text("更新于 \(loadedAt.formatted(date: .omitted, time: .shortened))")
                .font(.system(size: 10))
                .foregroundStyle(Color.hpTextPrimary.opacity(0.45))
            Button {
                reload()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.65))
                    .frame(width: 22, height: 22)
                    .background(Color.hpTextPrimary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .help("重新统计")
            .keyboardShortcut("r", modifiers: .command)
        }
    }

    // MARK: - 汇总卡片

    private var summaryCard: some View {
        HStack(spacing: 14) {
            summaryTile(
                title: "总播放次数",
                value: "\(total)",
                systemImage: "play.circle.fill",
                tint: .hpAccent
            )
            summaryTile(
                title: "覆盖歌曲数",
                value: "\(entries.count)",
                systemImage: "music.note",
                tint: .hpPink
            )
            summaryTile(
                title: "区间起点",
                value: range.intervalStart.formatted(date: .abbreviated, time: .shortened),
                systemImage: "calendar.badge.clock",
                tint: .hpMint
            )
        }
    }

    private func summaryTile(
        title: String,
        value: String,
        systemImage: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.55))
                Text(value)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.hpTextPrimary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.hpTextPrimary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - 列表

    private var statsList: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(Array(entries.enumerated()), id: \.element.track.id) { idx, item in
                    row(idx: idx, item: item)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
    }

    private func row(idx: Int, item: (track: Track, count: Int)) -> some View {
        HStack(spacing: 12) {
            Text("\(idx + 1)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.hpTextPrimary.opacity(0.4))
                .frame(width: 24, alignment: .trailing)

            if let artwork = ArtworkCache.shared.image(for: item.track.url, tier: .small) {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.hpTextPrimary.opacity(0.06))
                    Image(systemName: "music.note")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.hpTextPrimary.opacity(0.35))
                }
                .frame(width: 36, height: 36)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.track.displayTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.hpTextPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(item.track.displayArtist)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.hpTextPrimary.opacity(0.55))
                        .lineLimit(1)
                    Text("·").font(.system(size: 11))
                        .foregroundStyle(Color.hpTextPrimary.opacity(0.3))
                    Text(item.track.displayAlbum)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.hpTextPrimary.opacity(0.55))
                        .lineLimit(1)
                }
            }

            Spacer()

            Text("\(item.count) 次")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Color.hpAccent)
                .monospacedDigit()
            Button {
                play(item.track)
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.7))
                    .frame(width: 26, height: 26)
                    .background(Color.hpTextPrimary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .help("播放这首歌")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.hpTextPrimary.opacity(0.03))
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            play(item.track)
        }
    }

    /// 以当前列表作为播放队列从指定歌曲开始播放。
    private func play(_ track: Track) {
        let tracks = entries.map(\.track)
        if let idx = tracks.firstIndex(where: { $0.id == track.id }) {
            player.play(tracks[idx], in: tracks)
        } else {
            player.play(track, in: [track])
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 36))
                .foregroundStyle(Color.hpTextPrimary.opacity(0.25))
            Text("\(range.title)还没有播放记录")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.hpTextPrimary.opacity(0.6))
            Text("播放任意一首歌后，统计会自动累计")
                .font(.system(size: 11))
                .foregroundStyle(Color.hpTextPrimary.opacity(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - 数据加载

    private func reload() {
        let start = range.intervalStart
        let snapshot = historySnapshot()
        var counts: [UUID: Int] = [:]
        for entry in snapshot {
            for event in entry.recentEvents where event >= start {
                counts[entry.trackID, default: 0] += 1
            }
        }
        var rows: [(track: Track, count: Int)] = []
        rows.reserveCapacity(counts.count)
        for (id, count) in counts {
            if let track = library.tracks.first(where: { $0.id == id }) {
                rows.append((track: track, count: count))
            }
        }
        rows.sort { lhs, rhs in
            if lhs.count == rhs.count {
                return lhs.track.id.uuidString < rhs.track.id.uuidString
            }
            return lhs.count > rhs.count
        }
        withAnimation(.easeInOut(duration: 0.15)) {
            entries = rows
            total = counts.values.reduce(0, +)
            loadedAt = Date()
        }
    }

    /// 抓一份当前历史的不可变快照，避免 SwiftUI 渲染期间 store 被并发修改。
    private func historySnapshot() -> [PlayHistoryEntry] {
        library.history.map { $0 }
    }
}
