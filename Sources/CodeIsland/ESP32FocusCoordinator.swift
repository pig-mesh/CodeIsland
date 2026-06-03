import Foundation
import os
import CodeIslandCore

/// Turns a button press from Buddy (1-byte `sourceId`) into a real
/// "focus that agent's terminal/window" action.
///
/// This keeps focus routing aligned with the mascot currently shown on Buddy.
/// We pick the best active session belonging to the requested mascot and hand
/// it to `TerminalActivator`, whose tab-level matchers already know how to land
/// inside the exact iTerm2 session / Ghostty tab / Kitty window / tmux pane /
/// Cursor project window / etc.
@MainActor
enum ESP32FocusCoordinator {
    private static let log = Logger(subsystem: "com.codeisland", category: "esp32-focus")

    /// Ordered status priority — richer statuses win the tiebreak so that a
    /// button press preferentially lands on the session actually needing
    /// attention, not a forgotten idle one.
    private static func priority(_ status: AgentStatus) -> Int {
        switch status {
        case .waitingApproval: return 5
        case .waitingQuestion: return 4
        case .running:         return 3
        case .processing:      return 2
        case .idle:            return 0
        }
    }

    static func targetSession(for mascot: MascotID, appState: AppState) -> (sessionId: String, session: SessionSnapshot)? {
        let targetSource = mascot.sourceName

        return appState.sessions
            .filter { $0.value.source == targetSource && $0.value.status != .idle }
            .sorted { a, b in
                let pa = priority(a.value.status)
                let pb = priority(b.value.status)
                if pa != pb { return pa > pb }
                return a.value.lastActivity > b.value.lastActivity
            }
            .first
            .map { (sessionId: $0.key, session: $0.value) }
    }

    static func handle(mascot: MascotID, appState: AppState) {
        let targetSource = mascot.sourceName

        if let (sessionId, session) = targetSession(for: mascot, appState: appState) {
            log.info("Focus \(targetSource): session=\(sessionId) status=\(String(describing: session.status))")
            TerminalActivator.activate(session: session, sessionId: sessionId)
            return
        }

        log.info("Focus \(targetSource): no active session — ignored")
    }
}
