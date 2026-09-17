import AppKit
import Foundation
import XCTest

@testable import HarmonyPlayer

/// 长时间听歌会话的内存防护测试：模拟连续切歌几百首（真实 WAV 文件、
/// 真实 AudioPlayer 播放管线），断言内存不出现"逐首累积"级别的增长。
/// 阈值故意放宽到 80MB——只捕捉结构性泄漏（NSImage/AVAsset/任务滞留），
/// 不对正常运行的小幅波动报警。
@MainActor
final class LongSessionMemoryTests: XCTestCase {
    func testRepeatedTrackSwitchingDoesNotAccumulateMemory() throws {
        // 保护用户真实数据：AudioPlayer 会把播放状态写入 standard UserDefaults，
        // 测试前快照所有项目键，结束后原样恢复。
        let protectedPrefixes = ["ManyuMusic.", "HarmonyPlayer."]
        let snapshot = UserDefaults.standard.dictionaryRepresentation().filter { key, _ in
            protectedPrefixes.contains { key.hasPrefix($0) }
        }
        defer {
            for key in UserDefaults.standard.dictionaryRepresentation().keys
            where protectedPrefixes.contains(where: { key.hasPrefix($0) }) {
                UserDefaults.standard.removeObject(forKey: key)
            }
            for (key, value) in snapshot {
                UserDefaults.standard.set(value, forKey: key)
            }
        }

        // 生成 20 首极短的静音 WAV（0.3 秒、单声道、22.05kHz），循环切歌 300 次。
        let workspace = TempWorkspace()
        let audioDir = try workspace.makeDirectory("stress-audio")
        let sampleRate = 22050.0
        let frameCount = Int(sampleRate * 0.3)
        var tracks: [Track] = []
        tracks.reserveCapacity(20)
        for index in 0..<20 {
            let url = audioDir.appendingPathComponent("stress-\(index).wav")
            try Self.silentWAVData(frameCount: frameCount, sampleRate: sampleRate)
                .write(to: url)
            tracks.append(
                Track(url: url, title: "压力测试 \(index)", artist: "测试", album: "内存", duration: 0.3)
            )
        }

        let player = AudioPlayer()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        let before = Self.physFootprint()

        for index in 0..<300 {
            player.play(tracks[index % tracks.count], in: tracks)
            if index % 25 == 0 {
                // 周期性放行主线程，让在途的封面/歌词/时长任务落地。
                RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            }
        }
        RunLoop.main.run(until: Date().addingTimeInterval(2.0))

        // 当前曲目应为最后一次切的歌曲（AVPlayer 单条目结构天然不累积队列）。
        XCTAssertEqual(player.currentTrack?.title, "压力测试 \(299 % 20)")

        let growth = Self.physFootprint() - before
        XCTAssertLessThan(
            growth,
            80 * 1024 * 1024,
            "连续切歌 300 次后内存增长 \(growth / 1024 / 1024)MB，疑似逐首累积泄漏"
        )
    }

    // MARK: - 工具

    /// 进程物理占用（phys_footprint），与 Xcode 内存条口径一致。
    private static func physFootprint() -> Int64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Int64(info.phys_footprint)
    }

    /// 生成静音 WAV（PCM 16-bit 单声道）。
    private static func silentWAVData(frameCount: Int, sampleRate: Double) -> Data {
        var data = Data()
        let dataSize = frameCount * 2
        func append(_ text: String) { data.append(text.data(using: .ascii)!) }
        func append32(_ value: UInt32) { var v = value.littleEndian; data.append(Data(bytes: &v, count: 4)) }
        func append16(_ value: UInt16) { var v = value.littleEndian; data.append(Data(bytes: &v, count: 2)) }

        append("RIFF")
        append32(UInt32(36 + dataSize))
        append("WAVE")
        append("fmt ")
        append32(16)
        append16(1)                       // PCM
        append16(1)                       // 单声道
        append32(UInt32(sampleRate))
        append32(UInt32(sampleRate) * 2)  // 字节率
        append16(2)                       // 块对齐
        append16(16)                      // 位深
        append("data")
        append32(UInt32(dataSize))
        data.append(Data(count: dataSize))
        return data
    }
}
