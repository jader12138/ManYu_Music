import Foundation
import XCTest

@testable import HarmonyPlayer

/// 十段均衡器：系数设计、增益钳制、预设存取与自定义预设管理。
/// 不涉及 MTAudioProcessingTap（需要真实音频管线，由人工试听验收）。
@MainActor
final class EqualizerTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "HarmonyPlayerTests.eq-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testDefaultsAreFlatAndDisabled() {
        let eq = Equalizer(defaults: defaults)
        XCTAssertFalse(eq.isEnabled, "EQ 默认关闭")
        XCTAssertEqual(eq.gains, Equalizer.flat.gains, "默认平直曲线")
        XCTAssertEqual(eq.selectedPresetID, Equalizer.flat.id)
        XCTAssertTrue(eq.customPresets.isEmpty)
    }

    func testSetGainsClampsToRangeAndBumpsRevision() {
        let eq = Equalizer(defaults: defaults)
        let before = eq.revision

        var extreme = (0..<Equalizer.bandCount).map { Double($0) * 100 }
        extreme[0] = -99
        eq.setGains(extreme)

        XCTAssertEqual(eq.gains[0], -12, "越界增益下限钳制到 -12")
        XCTAssertEqual(eq.gains[9], 12, "越界增益上限钳制到 +12")
        XCTAssertGreaterThan(eq.revision, before, "曲线变化必须推进 revision 让 tap 重建系数")
    }

    func testFlatCurveYieldsIdentitySections() {
        let eq = Equalizer(defaults: defaults)
        let sections = eq.coefficients(sampleRate: 44_100)
        XCTAssertEqual(sections.count, Equalizer.bandCount)
        for section in sections {
            XCTAssertEqual(section.b0, 1, accuracy: 1e-9)
            XCTAssertEqual(section.b1, 0, accuracy: 1e-9)
            XCTAssertEqual(section.b2, 0, accuracy: 1e-9)
            XCTAssertEqual(section.a1, 0, accuracy: 1e-9)
            XCTAssertEqual(section.a2, 0, accuracy: 1e-9)
        }
    }

    func testBoostedCurveProducesStableSections() {
        // 稳定性：所有极点（a1、a2 决定）都在单位圆内，滤波器不会自激。
        let eq = Equalizer(defaults: defaults)
        eq.setGains(Equalizer.builtInPresets[2].gains)  // 古典
        let sections = eq.coefficients(sampleRate: 44_100)
        for s in sections {
            // |根| < 1 等价于 |a2| < 1 且 |a1| < 1 + a2
            XCTAssertLessThan(abs(s.a2), 1)
            XCTAssertLessThan(abs(s.a1), 1 + abs(s.a2))
        }
    }

    func testCustomPresetRoundTrip() {
        let eq = Equalizer(defaults: defaults)
        eq.apply(preset: Equalizer.builtInPresets[1])  // 流行
        XCTAssertEqual(eq.gains, Equalizer.builtInPresets[1].gains)
        XCTAssertEqual(eq.selectedPresetID, "pop")

        let saved = eq.saveCustomPreset(named: "  我的音色  ")
        XCTAssertEqual(saved.name, "我的音色", "名称去首尾空白")
        XCTAssertEqual(eq.gains, saved.gains, "保存时抓取当前曲线")
        XCTAssertEqual(eq.selectedPresetID, saved.id)
        XCTAssertEqual(eq.customPresets.count, 1)
        XCTAssertNotNil(eq.selectedPreset(), "保存后应能按 ID 找回预设")

        // 新实例（模拟重启）仍能读回自定义预设
        let reborn = Equalizer(defaults: defaults)
        XCTAssertEqual(reborn.customPresets.first?.name, "我的音色")
        XCTAssertEqual(reborn.selectedPresetName(), "我的音色")

        reborn.removeCustomPreset(id: saved.id)
        XCTAssertTrue(reborn.customPresets.isEmpty)
        XCTAssertEqual(reborn.selectedPresetID, Equalizer.flat.id, "删除选中预设后回退平直")
    }

    func testApplyingPresetPersistsAcrossInstances() {
        let eq = Equalizer(defaults: defaults)
        eq.apply(preset: Equalizer.builtInPresets[3])  // 摇滚

        let reborn = Equalizer(defaults: defaults)
        XCTAssertEqual(reborn.gains, Equalizer.builtInPresets[3].gains)
        XCTAssertEqual(reborn.selectedPresetID, "rock")
        XCTAssertEqual(reborn.selectedPresetName(), "摇滚")
    }
}
