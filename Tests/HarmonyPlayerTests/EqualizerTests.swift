import Foundation
import XCTest

@testable import HarmonyPlayer

/// 三十一段均衡器：系数设计、增益/Q 钳制、预设存取、自定义预设管理、
/// 旧版十段数据迁移与频谱环形缓冲。不涉及 MTAudioProcessingTap
/// （需要真实音频管线，由人工试听验收）。
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

    private func preset(id: String) -> Equalizer.Preset {
        guard let preset = Equalizer.builtInPresets.first(where: { $0.id == id }) else {
            fatalError("内置预设 \(id) 应存在")
        }
        return preset
    }

    func testDefaultsAreFlatAndDisabled() {
        let eq = Equalizer(defaults: defaults)
        XCTAssertFalse(eq.isEnabled, "EQ 默认关闭")
        XCTAssertTrue(eq.isBypassed, "关闭时音频线程应走直通")
        XCTAssertEqual(eq.gains, Equalizer.flat.gains, "默认平直曲线")
        XCTAssertEqual(eq.qValues, .init(repeating: Equalizer.defaultQ, count: Equalizer.bandCount))
        XCTAssertEqual(eq.selectedPresetID, Equalizer.flat.id)
        XCTAssertTrue(eq.customPresets.isEmpty)
        XCTAssertEqual(Equalizer.bandCount, 31)
        XCTAssertEqual(Equalizer.builtInPresets.count, 35)
        for preset in Equalizer.builtInPresets {
            XCTAssertEqual(preset.gains.count, Equalizer.bandCount, "预设 \(preset.name) 曲线必须是 31 段")
        }
    }

    func testEnabledFlagMirrorsIntoBypassState() {
        let eq = Equalizer(defaults: defaults)
        eq.isEnabled = true
        XCTAssertFalse(eq.isBypassed, "开启后音频线程立即退出直通")
        eq.isEnabled = false
        XCTAssertTrue(eq.isBypassed)
    }

    func testSetGainsClampsToRangeAndBumpsRevision() {
        let eq = Equalizer(defaults: defaults)
        let before = eq.revision

        var extreme = (0..<Equalizer.bandCount).map { Double($0) * 100 }
        extreme[0] = -99
        eq.setGains(extreme)

        XCTAssertEqual(eq.gains[0], -6, "越界增益下限钳制到 -6")
        XCTAssertEqual(eq.gains[Equalizer.bandCount - 1], 6, "越界增益上限钳制到 +6")
        XCTAssertGreaterThan(eq.revision, before, "曲线变化必须推进 revision 让 tap 重建系数")
    }

    func testQValuesClampAndPersistAcrossInstances() {
        let eq = Equalizer(defaults: defaults)
        let before = eq.revision
        var q = eq.qValues
        q[3] = 99
        q[7] = -5
        eq.setQValues(q)

        XCTAssertEqual(eq.qValues[3], Equalizer.qRange.upperBound, "Q 上限钳制到 18")
        XCTAssertEqual(eq.qValues[7], Equalizer.qRange.lowerBound, "Q 下限钳制到 0.1")
        XCTAssertGreaterThan(eq.revision, before, "Q 变化推进 revision 让 tap 重建系数")

        let reborn = Equalizer(defaults: defaults)
        XCTAssertEqual(reborn.qValues[3], Equalizer.qRange.upperBound, "Q 值跨实例持久化")

        eq.setQ(at: 5, to: 2.5)
        XCTAssertEqual(eq.qValues[5], 2.5, accuracy: 1e-9)
    }

    func testResetAllRestoresFlatAndDefaultQ() {
        let eq = Equalizer(defaults: defaults)
        eq.apply(preset: preset(id: "edm"))
        eq.setQ(at: 4, to: 3)
        eq.resetAll()

        XCTAssertEqual(eq.gains, Equalizer.flat.gains)
        XCTAssertEqual(eq.qValues, .init(repeating: Equalizer.defaultQ, count: Equalizer.bandCount))
        XCTAssertEqual(eq.selectedPresetID, Equalizer.flat.id)
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
        // 逐个跑全部内置预设（含每段独立 Q）。
        for preset in Equalizer.builtInPresets {
            let eq = Equalizer(defaults: defaults)
            eq.setQValues((0..<Equalizer.bandCount).map { 0.4 + Double($0 % 9) * 2 })
            eq.setGains(preset.gains)
            let sections = eq.coefficients(sampleRate: 44_100)
            for s in sections {
                // |根| < 1 等价于 |a2| < 1 且 |a1| < 1 + a2
                XCTAssertLessThan(abs(s.a2), 1, "预设 \(preset.name)")
                XCTAssertLessThan(abs(s.a1), 1 + abs(s.a2), "预设 \(preset.name)")
            }
        }
    }

    func testCustomPresetRoundTrip() {
        let eq = Equalizer(defaults: defaults)
        eq.apply(preset: preset(id: "pop"))
        XCTAssertEqual(eq.gains, preset(id: "pop").gains)
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
        eq.apply(preset: preset(id: "rock"))

        let reborn = Equalizer(defaults: defaults)
        XCTAssertEqual(reborn.gains, preset(id: "rock").gains)
        XCTAssertEqual(reborn.selectedPresetID, "rock")
        XCTAssertEqual(reborn.selectedPresetName(), "摇滚")
    }

    func testLegacyTenBandGainsMigrateTo31Bands() {
        // 旧版十段曲线（31Hz~16k）写入旧存储 → 初始化时插值成 31 段。
        let legacy: [Double] = [-12, -6, 0, 3, 6, 5, 4, 2, 1, 0]
        defaults.set(legacy, forKey: "ManyuMusic.eqGains")

        let eq = Equalizer(defaults: defaults)
        XCTAssertEqual(eq.gains.count, Equalizer.bandCount)
        // 与旧频率重合/几乎重合的频点取旧值（钳制到 ±6）：
        XCTAssertEqual(eq.gains[2], -6, accuracy: 0.5, "31.5Hz ≈ 旧 31Hz")
        XCTAssertEqual(eq.gains[17], 5, accuracy: 0.01, "1k 处取旧值")
        XCTAssertEqual(eq.gains[29], 0, accuracy: 0.5, "16k 处取旧值")
        // 中间频点落在相邻旧值之间
        XCTAssertEqual(eq.gains[17], 5, accuracy: 0.01)
        XCTAssertTrue(eq.gains.allSatisfy { Equalizer.gainRange.contains($0) })

        // 迁移结果已持久化为 31 段
        let reborn = Equalizer(defaults: defaults)
        XCTAssertEqual(reborn.gains, eq.gains)
    }

    func testLegacyCustomPresetMigratesTo31Bands() {
        var legacyPreset = Equalizer.Preset(id: "old1", name: "旧预设", gains: [])
        legacyPreset.gains = [1, 1, 1, 1, 1, 1, 1, 1, 1, 1]
        let data = try! JSONEncoder().encode([legacyPreset])
        defaults.set(data, forKey: "ManyuMusic.eqCustomPresets")

        let eq = Equalizer(defaults: defaults)
        XCTAssertEqual(eq.customPresets.count, 1)
        XCTAssertEqual(eq.customPresets[0].gains.count, Equalizer.bandCount, "旧十段自定义预设插值为 31 段")
        XCTAssertEqual(eq.customPresets[0].name, "旧预设")

        // 迁移已回写，第二次读取不再变化
        let reborn = Equalizer(defaults: defaults)
        XCTAssertEqual(reborn.customPresets, eq.customPresets)
    }

    func testSpectrumRingRoundTrip() {
        let ring = EQSpectrumRing()
        ring.sampleRate = 44_100
        let written: [Float] = (0..<5000).map { Float($0 % 7) }
        written.withUnsafeBufferPointer { buffer in
            ring.write(buffer.baseAddress!, count: written.count)
        }
        XCTAssertEqual(ring.writeCount, UInt64(written.count))

        var output = [Float](repeating: -1, count: 4096)
        let copied = ring.latest(into: &output)
        XCTAssertEqual(copied, 4096)
        // 最新 4096 个样本 = written 的后 4096 个
        for index in 0..<4096 {
            XCTAssertEqual(output[index], written[5000 - 4096 + index])
        }

        // 样本数不足时前面补零
        var small = [Float](repeating: -1, count: 6000)
        let copiedSmall = ring.latest(into: &small)
        XCTAssertEqual(copiedSmall, 5000)
        XCTAssertTrue(small.prefix(1000).allSatisfy { $0 == 0 })
        XCTAssertEqual(small[1000], written[0])
    }

    func testSpectrumComputeLevelsDistribution() {
        // 模拟 48kHz / 4096 点 FFT 归一化后的幅度谱：
        // 445Hz（bin 38）强峰 0.5、8kHz（bin 683）弱峰 0.1、其余近静音。
        let fftSize = 4096
        let sampleRate = 48_000.0
        let binHz = sampleRate / Double(fftSize)
        var magnitudes = [Float](repeating: 0.0001, count: fftSize / 2)
        magnitudes[Int(445 / binHz)] = 0.5
        magnitudes[Int(8000 / binHz)] = 0.1

        let levels = EQSpectrumAnalyzer.computeLevels(
            magnitudes: magnitudes,
            sampleRate: sampleRate,
            fftSize: fftSize
        )

        XCTAssertEqual(levels.count, EQSpectrumAnalyzer.pointCount)
        // 无满格平顶：全轴最多个别点接近 1，绝大多数在 1 以下。
        XCTAssertLessThan(levels.max() ?? 1, 0.999)
        XCTAssertLessThanOrEqual(levels.filter { $0 > 0.95 }.count, 20)

        func peakIn(_ range: ClosedRange<Int>) -> Double {
            range.compactMap { levels.indices.contains($0) ? levels[$0] : nil }.max() ?? 0
        }
        // 445Hz 强峰区显著隆起。
        let lowPeak = peakIn(165...180)
        XCTAssertGreaterThan(lowPeak, 0.5)
        // 8kHz 弱峰区可辨，但明显低于强峰。
        let highPeak = peakIn(320...345)
        XCTAssertGreaterThan(highPeak, 0.3)
        XCTAssertLessThan(highPeak, lowPeak - 0.1)
        // 超高频静区贴地（山谷）。
        XCTAssertLessThan(peakIn(370...383), 0.05)
    }
}
