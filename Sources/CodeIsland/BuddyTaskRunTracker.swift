import Foundation
import CodeIslandCore

/// 把会话状态变化转换成下发给 Buddy 的任务计时帧（0xEF）。
///
/// Mac 端权威计时：每个用户 prompt 视为一次 task run，从进入处理态开始计秒，回到 idle 时
/// 产出一帧 completed/failed 收尾帧。tracker 负责三件事：
/// - 去重：同一秒内重复调用只发一次（`lastSentElapsed`）。
/// - 收尾：任务结束只发一次最终帧（`finalSent`），其后调用返回 `.clear()`。
/// - 轮播：多个 active session 同时存在时，为每个 task run 保留独立计时。
struct BuddyTaskRunTracker {
    private struct RunKey: Hashable {
        let sessionId: String
        let promptSequence: UInt16
    }

    /// 当前正在计时的一次 task run 的内部状态。
    private struct ActiveRun: Equatable {
        let taskIdShort: String
        let startedAt: Date
        /// 上一次已下发的已用秒数，用于同秒去重。
        var lastSentElapsed: UInt16?
        /// 是否已发送过 completed/failed 收尾帧。
        var finalSent: Bool = false
    }

    private var runs: [RunKey: ActiveRun] = [:]

    /// 清空计时状态并返回一帧 `.clear()`，用于关闭计时或切换会话时通知 Buddy 停止显示。
    mutating func reset() -> BuddyTaskRunPayload {
        runs.removeAll()
        return .clear()
    }
}

extension BuddyTaskRunTracker {
    private static func isTaskActiveStatus(_ status: AgentStatus) -> Bool {
        switch status {
        case .processing, .running, .waitingApproval, .waitingQuestion:
            return true
        case .idle:
            return false
        }
    }

    private static func taskIdShort(sessionId: String, promptSequence: UInt16) -> String {
        let compact = sessionId
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "/", with: "")
        let suffix = String(compact.suffix(6))
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_ "))
        let base = suffix.isEmpty ? "run" : suffix
        return "\(base)-\(promptSequence)"
    }

    private static func elapsedSeconds(startedAt: Date, now: Date) -> Int {
        max(0, Int(now.timeIntervalSince(startedAt).rounded(.down)))
    }
}

extension BuddyTaskRunTracker {
    mutating func update(
        displaySessionId: String?,
        session: SessionSnapshot?,
        now: Date,
        failedWhenEnding: Bool
    ) -> BuddyTaskRunPayload? {
        guard let displaySessionId, let session else {
            if !runs.isEmpty {
                return reset()
            }
            return nil
        }

        let promptSequence = session.userPromptSequence
        let isActiveStatus = Self.isTaskActiveStatus(session.status)
        let key = RunKey(sessionId: displaySessionId, promptSequence: promptSequence)

        if isActiveStatus && promptSequence > 0 {
            if runs[key] == nil {
                runs[key] = ActiveRun(
                    taskIdShort: Self.taskIdShort(sessionId: displaySessionId, promptSequence: promptSequence),
                    startedAt: session.userPromptStartedAt ?? now
                )
            }

            guard var run = runs[key] else { return nil }
            let elapsed = UInt16(min(Self.elapsedSeconds(startedAt: run.startedAt, now: now), ESP32Protocol.maxTaskRunElapsedSeconds))
            if run.lastSentElapsed == elapsed {
                return nil
            }
            run.lastSentElapsed = elapsed
            runs[key] = run
            return .active(elapsedSeconds: Int(elapsed), taskRunSeq: Int(key.promptSequence), taskIdShort: run.taskIdShort)
        }

        guard var run = runs[key] else { return nil }
        guard !run.finalSent else {
            runs.removeValue(forKey: key)
            return .clear()
        }

        let elapsed = Self.elapsedSeconds(startedAt: run.startedAt, now: now)
        run.finalSent = true
        runs[key] = run

        if failedWhenEnding {
            return .failed(elapsedSeconds: elapsed, taskRunSeq: Int(key.promptSequence), taskIdShort: run.taskIdShort)
        }
        return .completed(elapsedSeconds: elapsed, taskRunSeq: Int(key.promptSequence), taskIdShort: run.taskIdShort)
    }
}
