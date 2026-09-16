import Foundation

enum LyricsParser {
    private static let timestampPattern = #"\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]"#
    private static let metadataPattern = #"^\[(ar|ti|al|by|re|ve|length):.*\]$"#

    /// 识别歌词开头的“制作人员名单”行（词：/曲：/编曲：/混音：/OP： 等）。
    /// 这类行通常以 0.1 秒间隔密集出现，不属于演唱内容，会导致歌词开局
    /// 疯狂滚动、正文看起来与歌曲错位，因此解析阶段直接跳过。
    private static let creditStartPattern = try? NSRegularExpression(
        pattern: #"^(?:作词|作曲|填词|改编词|原曲|编曲|改编|词|曲|监制|执行监制|联合监制|制作|制作人|制作统筹|执行制作|音乐总监|艺术总监|音乐统筹|混音|混音助理|混音师|母带|母带处理|母带工程师|和声|和音|和声编写|和声配唱|和声录音|配唱|主唱|伴唱|合唱|录音|录音师|录音棚|录音室|录音助理|吉他|木吉他|电吉他|贝斯|低音吉他|鼓|鼓组|打击乐|键盘|钢琴|弦乐|管乐|铜管|木管|萨克斯|小号|长号|圆号|长笛|单簧管|双簧管|二胡|琵琶|古筝|笛子|笛|箫|唢呐|口琴|尤克里里|编程|电脑编程|音乐编程|指挥|乐团|乐队|OP|SP|出品|出品人|发行|发行方|唱片公司|厂牌|统筹|企划|企宣|宣传|宣发|文案|策划|封面|视觉|美术|设计|摄影|导演|执行导演|剪辑|调色|后期|推广|商务|鸣谢|特别鸣谢|致谢|感谢|艺人|艺人统筹|经纪|助理|翻译|字幕|字体|海报|插画|服装|造型|化妆|发型|灯光|舞美|编舞|领舞|伴舞|授权|独家|版权|乐器)"#
    )

    /// 冒号前的前缀（允许“鼓/打击乐”“钢琴/电脑编程”这类组合分工）。
    private static let creditPrefixCapture = try? NSRegularExpression(
        pattern: #"^([^：:，。！？\n]{1,16})[：:]"#
    )

    /// 前缀里若出现这些常见正文字符（代词/语气词/动词等），视为演唱行而非名单。
    private static let nonCreditCharacters = Set("我你他她它们谁吗呢吧啊呀哦欸噢的了不没很都也就还再又才刚将要想看听说走来到在是给让被把对从向因所但可与跟同")

    private static let englishCreditPattern = try? NSRegularExpression(
        pattern: #"(?i)^\s*(?:lyrics?|composed?|composition|arranged?|arrangement|produced?|producer|mixed?|mastered?|written?|vocal(?:s)?|music)(?:\s+by\b|\s*[：:])"#,
        options: []
    )

    static func parse(_ rawLyrics: String?) -> [LyricLine] {
        guard let rawLyrics, !rawLyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        let normalized = rawLyrics
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var offset = 0.0
        for line in normalized.components(separatedBy: "\n") {
            if let value = captureOffset(line), let parsed = Double(value) {
                offset = parsed / 1000.0
                break
            }
        }

        let timestampRegex = try? NSRegularExpression(pattern: timestampPattern)
        let metadataRegex = try? NSRegularExpression(pattern: metadataPattern, options: [.caseInsensitive])
        var parsedLines: [LyricLine] = []
        var hasTimeline = false

        for sourceLine in normalized.components(separatedBy: "\n") {
            let line = sourceLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            let fullRange = NSRange(line.startIndex..<line.endIndex, in: line)
            if metadataRegex?.firstMatch(in: line, range: fullRange) != nil {
                continue
            }

            guard let timestampRegex else { continue }
            let matches = timestampRegex.matches(in: line, range: fullRange)
            let textRange = NSRange(
                location: (matches.last?.range.location ?? 0) + (matches.last?.range.length ?? 0),
                length: max(0, fullRange.length - ((matches.last?.range.location ?? 0) + (matches.last?.range.length ?? 0)))
            )
            let text = (line as NSString)
                .substring(with: textRange)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if matches.isEmpty {
                if !line.hasPrefix("[") {
                    parsedLines.append(LyricLine(id: parsedLines.count, time: nil, text: line))
                }
                continue
            }

            hasTimeline = true

            // 跳过制作人员名单与版权声明行：它们不是演唱内容。
            guard !isCreditLine(text) else { continue }

            for match in matches {
                guard match.numberOfRanges >= 3,
                      let minuteRange = Range(match.range(at: 1), in: line),
                      let secondRange = Range(match.range(at: 2), in: line),
                      let minutes = Double(line[minuteRange]),
                      let seconds = Double(line[secondRange]) else {
                    continue
                }

                var fraction = 0.0
                if match.numberOfRanges > 3,
                   let fractionRange = Range(match.range(at: 3), in: line),
                   !fractionRange.isEmpty {
                    let fractionText = String(line[fractionRange])
                    let value = Double(fractionText) ?? 0
                    fraction = value / pow(10.0, Double(fractionText.count))
                }

                let time = max(0, minutes * 60 + seconds + fraction + offset)
                parsedLines.append(LyricLine(id: parsedLines.count, time: time, text: text))
            }
        }

        if hasTimeline {
            parsedLines = parsedLines
                .filter { $0.time != nil }
                .sorted {
                    if $0.time == $1.time { return $0.id < $1.id }
                    return ($0.time ?? 0) < ($1.time ?? 0)
                }
                .enumerated()
                .map { index, line in
                    LyricLine(id: index, time: line.time, text: line.text)
                }
        } else {
            parsedLines = parsedLines
                .filter { !$0.text.isEmpty }
                .enumerated()
                .map { index, line in
                    LyricLine(id: index, time: nil, text: line.text)
                }
        }

        return parsedLines
    }

    private static func captureOffset(_ line: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"\[offset:([+-]?\d+)\]"#, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: line) else {
            return nil
        }
        return String(line[valueRange])
    }

    private static func isCreditLine(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= 80 else { return false }
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        if englishCreditPattern?.firstMatch(in: trimmed, range: range) != nil { return true }

        // 中文分工行：冒号前缀以已知分工词开头（支持“鼓/打击乐”这类组合），
        // 且不含正文中常见的代词、语气词等字符。
        if let match = creditPrefixCapture?.firstMatch(in: trimmed, range: range),
           match.numberOfRanges > 1,
           let prefixRange = Range(match.range(at: 1), in: trimmed) {
            let prefix = String(trimmed[prefixRange])
            let prefixRangeNS = NSRange(prefix.startIndex..<prefix.endIndex, in: prefix)
            if creditStartPattern?.firstMatch(in: prefix, range: prefixRangeNS) != nil,
               !prefix.contains(where: { nonCreditCharacters.contains($0) }) {
                return true
            }
        }

        // 流媒体平台常见的结尾推广/版权声明行。
        if trimmed.hasPrefix("本歌曲来自") || trimmed.hasPrefix("此歌曲来自") || trimmed.hasPrefix("本作品来自") {
            return true
        }
        return false
    }
}
