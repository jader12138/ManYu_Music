import Foundation

/// 临时探针（诊断完成后移除）：定位「主页推荐封面 → 播放页」转场卡顿来源。
/// - mark(_:) 在关键事件点打点，输出距上次事件的间隔；
/// - install() 装一个主线程心跳（2ms Timer）+ 后台看门狗线程，
///   心跳间隔超过阈值即判定主线程发生卡顿并记录时长。
/// 输出走 NSLog（统一日志），检索关键字：[PROBE]
enum TransitionProbe {
    private static let boot = CACurrentMediaTime()
    private static let state = ProbeState()
    private static var installed = false

    private final class ProbeState: @unchecked Sendable {
        let lock = NSLock()
        var lastBeat = CACurrentMediaTime()
        var lastMark = CACurrentMediaTime()
    }

    static func install() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !installed else { return }
        installed = true

        // 主线程心跳：正常时每 2ms 刷新时间戳。
        Timer.scheduledTimer(withTimeInterval: 0.002, repeats: true) { _ in
            state.lock.lock()
            state.lastBeat = CACurrentMediaTime()
            state.lock.unlock()
        }

        // 看门狗线程：心跳间隔超阈值 → 主线程卡顿，记录后归零避免刷屏。
        Thread.detachNewThread {
            while true {
                Thread.sleep(forTimeInterval: 0.002)
                state.lock.lock()
                let gap = CACurrentMediaTime() - state.lastBeat
                if gap > 0.012 {
                    state.lastBeat = CACurrentMediaTime()
                    state.lock.unlock()
                    NSLog(String(format: "[PROBE] ⚠️ 主线程疑似卡顿 %.0fms", gap * 1000))
                } else {
                    state.lock.unlock()
                }
            }
        }
    }

    static func mark(_ event: String) {
        let now = CACurrentMediaTime()
        state.lock.lock()
        let sinceLast = now - state.lastMark
        state.lastMark = now
        state.lock.unlock()
        NSLog(String(format: "[PROBE] +%.2fs %@ (距上次事件 %.1fms)", now - boot, event, sinceLast * 1000))
    }
}
