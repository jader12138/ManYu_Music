import Foundation

enum LyricsParser {
    private static let timestampPattern = #"\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]"#
    private static let metadataPattern = #"^\[(ar|ti|al|by|re|ve|length):.*\]$"#

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
}
