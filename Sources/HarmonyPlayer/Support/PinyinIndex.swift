import Foundation

/// 拼音检索键：full = 去分隔的全拼（英文按原词并入），initials = 逐字/逐词首字母。
/// 例：「周杰伦」→ full "zhoujielun"、initials "zjl"；
/// "Jay Chou" → full "jaychou"、initials "jc"。
struct PinyinKeys: Equatable, Sendable {
    let full: String
    let initials: String

    /// 查询串（已小写）是否命中全拼或首字母（均为包含匹配）。
    func matches(_ query: String) -> Bool {
        guard !query.isEmpty else { return false }
        return full.contains(query) || initials.contains(query)
    }
}

/// 基于 CFStringTransform 的拼音键生成器（无第三方依赖）。
/// 结果按原文缓存：库搜索在后台线程随每次按键触发，
/// 缓存必须线程安全（NSLock 保护，static let 持有保证并发安全）。
enum PinyinIndex {
    private final class CacheBox {
        let lock = NSLock()
        var cache: [String: PinyinKeys] = [:]
    }
    private static let box = CacheBox()

    static func keys(for text: String) -> PinyinKeys {
        box.lock.lock()
        if let hit = box.cache[text] {
            box.lock.unlock()
            return hit
        }
        box.lock.unlock()

        let value = computeKeys(for: text)

        box.lock.lock()
        box.cache[text] = value
        box.lock.unlock()
        return value
    }

    /// 测试辅助：清空缓存。
    static func clearCacheForTesting() {
        box.lock.lock()
        box.cache.removeAll()
        box.lock.unlock()
    }

    private static func computeKeys(for text: String) -> PinyinKeys {
        let mutable = NSMutableString(string: text)
        // 汉字 → 带声调拼音（逐字以空格分隔，如「周杰伦」→ "zhōu jié lún"），
        // 再剥离声调符号；非中文文本原样保留（词间自带空格）。
        CFStringTransform(mutable, nil, kCFStringTransformMandarinLatin, false)
        CFStringTransform(mutable, nil, kCFStringTransformStripDiacritics, false)
        let lowered = (mutable as String).lowercased()

        var full = ""
        var initials = ""
        for token in lowered.split(whereSeparator: \.isWhitespace) {
            let letters = token.filter { $0.isLetter || $0.isNumber }
            guard let first = letters.first else { continue }
            full += letters
            initials.append(first)
        }
        return PinyinKeys(full: full, initials: initials)
    }
}
