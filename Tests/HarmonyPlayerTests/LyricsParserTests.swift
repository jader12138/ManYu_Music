import XCTest
@testable import HarmonyPlayer

final class LyricsParserTests: XCTestCase {
    func testFiltersCreditLinesAndKeepsSungLines() {
        let raw = """
        [00:00.00]慢慢喜欢你 - 莫文蔚 (Karen Mok)
        [00:00.11]词：李荣浩
        [00:00.22]曲：李荣浩
        [00:00.33]编曲：冯翰铭
        [00:00.44]制作人：荒井十一
        [00:00.56]鼓/打击乐：荒井十一
        [00:01.00]和声：Karen Mok
        [00:01.90]SP：酷亚音乐 (深圳) 有限公司
        [00:02.02]书里总爱写到喜出望外的傍晚
        [00:09.80]骑的单车还有他和她的对谈
        """

        let lines = LyricsParser.parse(raw)

        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0].text, "慢慢喜欢你 - 莫文蔚 (Karen Mok)")
        XCTAssertEqual(lines[0].time ?? 0, 0.0, accuracy: 0.001)
        XCTAssertEqual(lines[1].text, "书里总爱写到喜出望外的傍晚")
        XCTAssertEqual(lines[1].time ?? 0, 2.02, accuracy: 0.001)
        XCTAssertEqual(lines[2].text, "骑的单车还有他和她的对谈")
        XCTAssertEqual(lines[2].time ?? 0, 9.80, accuracy: 0.001)
    }

    func testFiltersEnglishCreditLines() {
        let raw = """
        [00:01.00]Lyrics by: Someone
        [00:01.20]Composed by Someone
        [00:05.00]First real line
        """

        let lines = LyricsParser.parse(raw)
        XCTAssertEqual(lines.map(\.text), ["First real line"])
    }

    func testAppliesOffsetTag() {
        let raw = """
        [offset:500]
        [00:10.00]line one
        """

        let lines = LyricsParser.parse(raw)
        XCTAssertEqual(lines.first?.time ?? 0, 10.5, accuracy: 0.001)
    }

    func testExpandsMultipleTimestamps() {
        let raw = "[00:12.00][00:45.00]chorus line"

        let lines = LyricsParser.parse(raw)
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0].time ?? 0, 12.0, accuracy: 0.001)
        XCTAssertEqual(lines[1].time ?? 0, 45.0, accuracy: 0.001)
    }

    func testHandlesThreeDecimalFractions() {
        let raw = "[01:02.123]precise line"

        let lines = LyricsParser.parse(raw)
        XCTAssertEqual(lines.first?.time ?? 0, 62.123, accuracy: 0.0005)
    }

    func testFallsBackToPlainTextWithoutTimestamps() {
        let raw = "just\nplain\nlines"

        let lines = LyricsParser.parse(raw)
        XCTAssertEqual(lines.count, 3)
        XCTAssertNil(lines[0].time)
        XCTAssertEqual(lines.map(\.text), ["just", "plain", "lines"])
    }

    /// 双语 LRC：相同时间戳的相邻两行（原文 + 译文）合并为一行，
    /// 译文写入 translation 字段。
    func testMergesBilingualPairByEqualTimestamp() {
        let raw = """
        [00:01.00]Hello world
        [00:01.00]你好世界
        [00:05.00]Second line
        [00:05.00]第二行
        """

        let lines = LyricsParser.parse(raw)

        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0].text, "Hello world")
        XCTAssertEqual(lines[0].translation, "你好世界")
        XCTAssertEqual(lines[0].time ?? 0, 1.0, accuracy: 0.001)
        XCTAssertEqual(lines[1].text, "Second line")
        XCTAssertEqual(lines[1].translation, "第二行")
        XCTAssertEqual(lines[1].time ?? 0, 5.0, accuracy: 0.001)
    }

    /// 单语 LRC：所有行 translation 应为 nil，行为不变。
    func testMonolingualLyricsHaveNilTranslation() {
        let raw = """
        [00:01.00]only original
        [00:05.00]another line
        """

        let lines = LyricsParser.parse(raw)

        XCTAssertEqual(lines.count, 2)
        XCTAssertNil(lines[0].translation)
        XCTAssertNil(lines[1].translation)
    }

    /// 多时间戳同行（`[00:12.00][00:45.00]chorus`）不应被误判为双语：
    /// 解析后两行 text 相同、time 不同，不合并。
    func testDoesNotMergeMultiTimestampSameText() {
        let raw = "[00:12.00][00:45.00]chorus line"

        let lines = LyricsParser.parse(raw)
        XCTAssertEqual(lines.count, 2)
        XCTAssertNil(lines[0].translation)
        XCTAssertNil(lines[1].translation)
        XCTAssertEqual(lines.map(\.text), ["chorus line", "chorus line"])
    }
}
