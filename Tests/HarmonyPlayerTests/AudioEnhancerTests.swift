import AudioToolbox
import Foundation
import XCTest

@testable import HarmonyPlayer

/// 音效增强：参数钳制/持久化/重置 + 实时引擎（直通恒等、输出控制、
/// 声场扩展、混响稳定性、滤波有界性、动态压缩）。不涉及 MTAudioProcessingTap
/// （需要真实音频管线，由人工试听验收）。
final class AudioEnhancerTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "HarmonyPlayerTests.fx-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    // MARK: 参数模型

    func testDefaultsAreAllOff() {
        let fx = AudioEnhancer(defaults: defaults)
        XCTAssertFalse(fx.enabled)
        XCTAssertTrue(fx.isBypassed)
        XCTAssertEqual(fx.lowBoost, 0)
        XCTAssertEqual(fx.dynamics, 0)
        XCTAssertEqual(fx.reverb, 0)
        XCTAssertEqual(fx.outputGainDB, 0)
        XCTAssertEqual(fx.balance, 0)
    }

    func testSettersClampToRanges() {
        let fx = AudioEnhancer(defaults: defaults)
        fx.setLowBoost(150)
        fx.setDynamics(-30)
        fx.setOutputGain(99)
        fx.setOutputGain(-99)
        fx.setBalance(7)
        fx.setBalance(-7)

        fx.setLowBoost(60)
        fx.setDynamics(40)
        fx.setOutputGain(6)
        fx.setBalance(0.5)
        XCTAssertEqual(fx.lowBoost, 60)
        XCTAssertEqual(fx.dynamics, 40)
        XCTAssertEqual(fx.outputGainDB, 6)
        XCTAssertEqual(fx.balance, 0.5, accuracy: 1e-9)
    }

    func testBypassMirrorsEnabledAndRevisionBumps() {
        let fx = AudioEnhancer(defaults: defaults)
        let before = fx.revision
        fx.setEnabled(true)
        XCTAssertFalse(fx.isBypassed)
        fx.setEnabled(false)
        XCTAssertTrue(fx.isBypassed)
        XCTAssertGreaterThan(fx.revision, before)

        let next = fx.revision
        fx.setReverb(80)
        XCTAssertGreaterThan(fx.revision, next)
    }

    func testParametersPersistAcrossInstances() {
        let fx = AudioEnhancer(defaults: defaults)
        fx.setEnabled(true)
        fx.setVocalEnhance(55)
        fx.setOutputGain(-4)
        fx.setBalance(-0.25)

        let reborn = AudioEnhancer(defaults: defaults)
        XCTAssertTrue(reborn.enabled)
        XCTAssertEqual(reborn.vocalEnhance, 55)
        XCTAssertEqual(reborn.outputGainDB, -4)
        XCTAssertEqual(reborn.balance, -0.25, accuracy: 1e-9)
    }

    func testResetAllKeepsEnabledState() {
        let fx = AudioEnhancer(defaults: defaults)
        fx.setEnabled(true)
        fx.setBassEnhance(70)
        fx.setSurround(90)
        fx.resetAll()

        XCTAssertEqual(fx.bassEnhance, 0)
        XCTAssertEqual(fx.surround, 0)
        XCTAssertEqual(fx.outputGainDB, 0)
        XCTAssertTrue(fx.enabled, "重置不应动总开关")
        XCTAssertEqual(fx.snapshot().surround, 0, "音频线程快照同步恢复")
    }

    // MARK: 实时引擎

    /// 用两声道非交织 AudioBufferList 跑一遍引擎，返回处理后的采样。
    private func runEngine(
        _ engine: EnhancerEngine,
        left: [Float],
        right: [Float]
    ) -> (l: [Float], r: [Float]) {
        var l = left
        var r = right
        let extra = MemoryLayout<AudioBuffer>.size
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: MemoryLayout<AudioBufferList>.size + extra,
            alignment: MemoryLayout<AudioBuffer>.alignment
        )
        defer { raw.deallocate() }
        let list = raw.bindMemory(to: AudioBufferList.self, capacity: 1)
        l.withUnsafeMutableBufferPointer { lb in
            r.withUnsafeMutableBufferPointer { rb in
                list.pointee.mNumberBuffers = 2
                let buffers = UnsafeMutableAudioBufferListPointer(list)
                buffers[0] = AudioBuffer(
                    mNumberChannels: 1,
                    mDataByteSize: UInt32(lb.count * MemoryLayout<Float>.size),
                    mData: lb.baseAddress
                )
                buffers[1] = AudioBuffer(
                    mNumberChannels: 1,
                    mDataByteSize: UInt32(rb.count * MemoryLayout<Float>.size),
                    mData: rb.baseAddress
                )
                engine.process(list, frames: lb.count)
            }
        }
        return (l, r)
    }

    private func makeEngine(_ configure: (AudioEnhancer) -> Void) -> EnhancerEngine {
        // 每个引擎用干净的参数域，避免同测试内前一个引擎的持久化值泄漏
        defaults.removePersistentDomain(forName: suiteName)
        let fx = AudioEnhancer(defaults: defaults)
        configure(fx)
        let engine = EnhancerEngine(enhancer: fx)
        engine.prepare(sampleRate: 48_000, channels: 2)
        return engine
    }

    func testDisabledEngineIsIdentity() {
        let engine = makeEngine { _ in }
        let inputL: [Float] = (0..<512).map { sin(Float($0) * 0.05) * 0.4 }
        let inputR: [Float] = (0..<512).map { cos(Float($0) * 0.03) * 0.3 }
        let out = runEngine(engine, left: inputL, right: inputR)
        XCTAssertEqual(out.l, inputL)
        XCTAssertEqual(out.r, inputR)
    }

    func testEnabledWithAllDefaultsIsIdentity() {
        let engine = makeEngine { $0.setEnabled(true) }
        let inputL: [Float] = (0..<512).map { sin(Float($0) * 0.05) * 0.4 }
        let inputR: [Float] = (0..<512).map { cos(Float($0) * 0.03) * 0.3 }
        let out = runEngine(engine, left: inputL, right: inputR)
        XCTAssertEqual(out.l, inputL)
        XCTAssertEqual(out.r, inputR)
    }

    func testOutputGainAndBalance() {
        // +6dB 增益：|out| = |in| × 1.9953
        let gainEngine = makeEngine { fx in
            fx.setEnabled(true)
            fx.setOutputGain(6)
        }
        let out = runEngine(gainEngine, left: [0.1], right: [-0.1])
        XCTAssertEqual(out.l[0], 0.19953, accuracy: 1e-3)
        XCTAssertEqual(out.r[0], -0.19953, accuracy: 1e-3)

        // 声道平衡拉到最右：左声道静音，右声道保持
        let balanceEngine = makeEngine { fx in
            fx.setEnabled(true)
            fx.setBalance(1)
        }
        let balanced = runEngine(balanceEngine, left: [0.5], right: [0.25])
        XCTAssertEqual(balanced.l[0], 0, accuracy: 1e-9)
        XCTAssertEqual(balanced.r[0], 0.25, accuracy: 1e-6)
    }

    func testSurroundWidensStereo() {
        // M/S 扩展：k = 0.6，L=0.5 / R=-0.5 → side × 1.6 → ±0.8
        let engine = makeEngine { fx in
            fx.setEnabled(true)
            fx.setSurround(100)
        }
        let out = runEngine(engine, left: [0.5], right: [-0.5])
        XCTAssertEqual(out.l[0], 0.8, accuracy: 1e-6)
        XCTAssertEqual(out.r[0], -0.8, accuracy: 1e-6)
    }

    func testReverbTailDecaysAndStaysBounded() {
        let engine = makeEngine { fx in
            fx.setEnabled(true)
            fx.setReverb(100)
        }
        var peak: Float = 0
        let chunk = 512
        for step in 0..<300 {  // 约 3.2 秒
            var l = [Float](repeating: 0, count: chunk)
            var r = [Float](repeating: 0, count: chunk)
            if step == 0 {
                l[0] = 1  // 单位冲激（干信号直通，不计入湿信号峰值）
                r[0] = 1
            }
            let out = runEngine(engine, left: l, right: r)
            if step == 0 { continue }  // 干信号冲激本身幅度 1.0，跳过
            for value in out.l where abs(value) > peak { peak = abs(value) }
            for value in out.r where abs(value) > peak { peak = abs(value) }
        }
        XCTAssertLessThan(peak, 0.6, "混响冲激响应不得发散")

        // 尾巴必须衰减干净（最后一块的最大幅度）
        let tail = runEngine(
            engine,
            left: .init(repeating: 0, count: chunk),
            right: .init(repeating: 0, count: chunk)
        )
        let tailPeak = max(tail.l.map(abs).max() ?? 0, tail.r.map(abs).max() ?? 0)
        XCTAssertLessThan(tailPeak, 1e-3, "3 秒后混响尾巴应基本消失")
    }

    func testFrequencyFiltersChangeSignalAndStayBounded() {
        let engine = makeEngine { fx in
            fx.setEnabled(true)
            fx.setLowBoost(100)
            fx.setClarity(100)
            fx.setTrebleBoost(100)
        }
        let input: [Float] = (0..<4096).map {
            sin(Float($0) * 0.013) * 0.5 + sin(Float($0) * 0.31) * 0.2
        }
        let out = runEngine(engine, left: input, right: input)
        let maxOutput = out.l.map(abs).max() ?? 0
        XCTAssertLessThan(maxOutput, 1.0, "滤波输出必须有界")
        XCTAssertFalse(out.l.elementsEqual(input), "提升曲线必须改变信号")
    }

    func testDynamicsCompressesLoudSignal() {
        let engine = makeEngine { fx in
            fx.setEnabled(true)
            fx.setDynamics(100)
        }
        let loud: [Float] = (0..<24_000).map { sin(Float($0) * 0.09) * 0.9 }  // 0.5 秒大信号
        let out = runEngine(engine, left: loud, right: loud)
        let inputPeak: Float = 0.9
        let outputPeak = out.l.map(abs).max() ?? 0
        XCTAssertLessThan(outputPeak, inputPeak * 0.5, "压缩动态范围必须显著压低响亮信号峰值")
        XCTAssertTrue(out.l.allSatisfy { $0.isFinite })
    }
}
