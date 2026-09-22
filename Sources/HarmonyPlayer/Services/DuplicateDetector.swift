import Foundation

/// 重复歌曲检测：纯函数实现，便于单测。
///
/// 判定规则（用户 2026-09-22 确认）：
/// 1. 标题去掉尾缀数字/空格后相同（"海阔天空" 与 "海阔天空 2" / "海阔天空2" 判为同名）
/// 2. 歌手、专辑去首尾空格并忽略大小写后一致
/// 3. 时长容差 ±2 秒
enum DuplicateDetector {
    /// 时长容差：±2 秒视为同时长。
    static let durationTolerance: Double = 2.0

    /// 标题归一化：循环去掉末尾的空白和数字。
    /// - "海阔天空" → "海阔天空"
    /// - "海阔天空 2" → "海阔天空"
    /// - "海阔天空2" → "海阔天空"
    /// - "海阔天空 12" → "海阔天空"
    /// - "海阔天空 (Live)" → "海阔天空 (Live)"（不去掉非数字尾缀）
    static func normalizeTitle(_ raw: String) -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var changed = true
        while changed {
            changed = false
            while let last = trimmed.last, last.isWhitespace {
                trimmed.removeLast()
                changed = true
            }
            var digits = 0
            for ch in trimmed.reversed() {
                if ch.isNumber { digits += 1 } else { break }
            }
            if digits > 0 {
                trimmed.removeLast(digits)
                changed = true
            }
        }
        return trimmed
    }

    /// 歌手/专辑归一化：去首尾空格并小写。
    static func normalizeField(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private struct GroupKey: Hashable {
        let title: String
        let artist: String
        let album: String
    }

    /// 返回重复组列表。每个组至少有 2 首歌。
    /// 组间顺序：按组内最早添加的歌曲 dateAdded 降序；平局按组首 id 升序。
    /// 组内顺序：dateAdded 降序（最新添加的在前）。
    static func detectGroups(in tracks: [Track]) -> [[Track]] {
        var buckets: [GroupKey: [Track]] = [:]
        for track in tracks {
            let key = GroupKey(
                title: normalizeTitle(track.displayTitle),
                artist: normalizeField(track.displayArtist),
                album: normalizeField(track.displayAlbum)
            )
            buckets[key, default: []].append(track)
        }

        var groups: [[Track]] = []
        for (_, bucket) in buckets {
            guard bucket.count >= 2 else { continue }
            // 按时长升序排，便于相邻差聚类。
            let sortedByDuration = bucket.sorted { $0.duration < $1.duration }
            var current: [Track] = [sortedByDuration[0]]
            for i in 1..<sortedByDuration.count {
                let prev = sortedByDuration[i - 1]
                let curr = sortedByDuration[i]
                if abs(curr.duration - prev.duration) <= durationTolerance {
                    current.append(curr)
                } else {
                    if current.count >= 2 {
                        groups.append(current.sorted { $0.dateAdded > $1.dateAdded })
                    }
                    current = [curr]
                }
            }
            if current.count >= 2 {
                groups.append(current.sorted { $0.dateAdded > $1.dateAdded })
            }
        }

        groups.sort { lhs, rhs in
            let lHead = lhs[0]
            let rHead = rhs[0]
            if lHead.dateAdded == rHead.dateAdded {
                return lHead.id.uuidString < rHead.id.uuidString
            }
            return lHead.dateAdded > rHead.dateAdded
        }
        return groups
    }
}
