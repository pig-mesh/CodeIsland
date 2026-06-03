import XCTest
@testable import CodeIsland
import CodeIslandCore

@MainActor
final class AppStatePrimarySourceTests: XCTestCase {

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: SettingsKey.defaultSource)
        super.tearDown()
    }

    /// #149 regression: when sessions exist but none are actively working
    /// (all .idle), the primary source / mascot should reflect the user's
    /// configured default rather than echoing whichever source spoke last.
    func testIdleSessionsRespectUserDefaultMascot() {
        UserDefaults.standard.set("codex", forKey: SettingsKey.defaultSource)

        let appState = AppState()
        var session = SessionSnapshot()
        session.source = "claude"
        session.status = .idle
        session.lastActivity = Date()
        appState.sessions["s1"] = session

        appState.refreshDerivedState()

        XCTAssertEqual(appState.primarySource, "codex",
            "All-idle sessions must fall back to user-configured default mascot (#149)")
    }

    /// Sanity: an active session always wins over the default mascot — we
    /// don't want to mute "what's actually running right now" just because
    /// the user picked a preferred idle mascot.
    func testActiveSessionWinsOverUserDefaultMascot() {
        UserDefaults.standard.set("codex", forKey: SettingsKey.defaultSource)

        let appState = AppState()
        var session = SessionSnapshot()
        session.source = "claude"
        session.status = .running
        session.lastActivity = Date()
        appState.sessions["s1"] = session

        appState.refreshDerivedState()

        XCTAssertEqual(appState.primarySource, "claude",
            "Active work overrides the user default — show what's actually running")
    }

    /// #102 still holds: with no sessions at all, default mascot wins.
    func testEmptyStateRespectsUserDefaultMascot() {
        UserDefaults.standard.set("codex", forKey: SettingsKey.defaultSource)

        let appState = AppState()
        appState.refreshDerivedState()

        XCTAssertEqual(appState.primarySource, "codex")
    }

    /// Mixed: one active, one idle — active source wins regardless of default.
    func testMixedActiveAndIdleSessionsUseActiveSource() {
        UserDefaults.standard.set("codex", forKey: SettingsKey.defaultSource)

        let appState = AppState()
        var idleSession = SessionSnapshot()
        idleSession.source = "claude"
        idleSession.status = .idle
        idleSession.lastActivity = Date()
        appState.sessions["s1"] = idleSession

        var runningSession = SessionSnapshot()
        runningSession.source = "gemini"
        runningSession.status = .running
        runningSession.lastActivity = Date()
        appState.sessions["s2"] = runningSession

        appState.refreshDerivedState()

        XCTAssertEqual(appState.primarySource, "gemini",
            "When at least one session is running, surface that source not the user default")
    }

    // MARK: - Buddy (ESP32) frame alignment with island display

    /// When a session is idle, esp32DisplayFrame must use the user-configured
    /// default mascot — matching the island's CompactLeftWing.displaySource.
    func testESP32DisplayFrameUsesDefaultSourceWhenIdle() {
        UserDefaults.standard.set("codex", forKey: SettingsKey.defaultSource)

        let appState = AppState()
        var session = SessionSnapshot()
        session.source = "cursor"
        session.status = .idle
        session.lastActivity = Date()
        appState.sessions["s1"] = session
        appState.refreshDerivedState()

        let frame = appState.esp32DisplayFrame(session: session)
        XCTAssertEqual(frame.mascot, .codex,
            "Idle session must show user-configured default mascot on Buddy, not the session source")
        XCTAssertEqual(frame.status, .idle)
    }

    /// When a session is actively running, esp32DisplayFrame must use the
    /// session's own source — not the user default.
    func testESP32DisplayFrameUsesSessionSourceWhenActive() {
        UserDefaults.standard.set("codex", forKey: SettingsKey.defaultSource)

        let appState = AppState()
        var session = SessionSnapshot()
        session.source = "cursor"
        session.status = .running
        session.lastActivity = Date()
        appState.sessions["s1"] = session
        appState.refreshDerivedState()

        let frame = appState.esp32DisplayFrame(session: session)
        XCTAssertEqual(frame.mascot, .cursor,
            "Active session must show its own source on Buddy, not the user default")
        XCTAssertEqual(frame.status, .running)
    }

    /// With no sessions, esp32DisplayFrame falls back to the user default.
    func testESP32DisplayFrameFallsBackToDefaultWhenNoSession() {
        UserDefaults.standard.set("gemini", forKey: SettingsKey.defaultSource)

        let appState = AppState()
        appState.refreshDerivedState()

        let frame = appState.esp32DisplayFrame(session: nil)
        XCTAssertEqual(frame.mascot, .gemini,
            "No-session state must show user-configured default mascot on Buddy")
        XCTAssertEqual(frame.status, .idle)
    }

    func testESP32StatsUseGlobalToolCountAcrossSessions() {
        let appState = AppState()

        var first = SessionSnapshot()
        first.recordTool("Read", description: nil, success: true, agentType: nil, maxHistory: 20)
        first.recordTool("Edit", description: nil, success: true, agentType: nil, maxHistory: 20)
        appState.sessions["s1"] = first

        var second = SessionSnapshot()
        second.recordTool("Bash", description: nil, success: false, agentType: nil, maxHistory: 20)
        appState.sessions["s2"] = second
        appState.refreshDerivedState()

        let stats = appState.esp32StatsPayload(session: second)
        XCTAssertEqual(stats.toolCallCount, 3)
    }

    func testESP32DisplayIdentityStaysStableAcrossStatusAndDefaultMascotChanges() {
        UserDefaults.standard.set("codex", forKey: SettingsKey.defaultSource)

        let appState = AppState()
        var session = SessionSnapshot()
        session.source = "cursor"
        session.status = .running
        appState.sessions["s1"] = session
        appState.activeSessionId = "s1"

        XCTAssertEqual(appState.esp32DisplayIdentity(), "session:s1")

        session.status = .idle
        appState.sessions["s1"] = session

        XCTAssertEqual(appState.esp32DisplayIdentity(), "session:s1",
            "Completion/error animations should still be scoped to the same session even when idle display falls back to the default mascot")
    }

    func testESP32DisplayIdentityChangesWhenDisplayedSessionChanges() {
        let appState = AppState()
        appState.sessions["s1"] = SessionSnapshot()
        appState.sessions["s2"] = SessionSnapshot()

        appState.activeSessionId = "s1"
        XCTAssertEqual(appState.esp32DisplayIdentity(), "session:s1")

        appState.activeSessionId = "s2"
        XCTAssertEqual(appState.esp32DisplayIdentity(), "session:s2")
    }

    func testBuddyTaskRunTrackerStartsAndTicksActivePrompt() {
        var tracker = BuddyTaskRunTracker()
        let start = Date(timeIntervalSince1970: 100)
        var session = SessionSnapshot()
        session.status = .processing
        session.userPromptSequence = 1

        let first = tracker.update(displaySessionId: "session-alpha", session: session, now: start, failedWhenEnding: false)
        XCTAssertEqual(first, .active(elapsedSeconds: 0, taskRunSeq: 1, taskIdShort: "alpha-1"))

        let duplicate = tracker.update(displaySessionId: "session-alpha", session: session, now: start.addingTimeInterval(0.4), failedWhenEnding: false)
        XCTAssertNil(duplicate)

        let second = tracker.update(displaySessionId: "session-alpha", session: session, now: start.addingTimeInterval(1.2), failedWhenEnding: false)
        XCTAssertEqual(second, .active(elapsedSeconds: 1, taskRunSeq: 1, taskIdShort: "alpha-1"))
    }

    func testBuddyTaskRunTrackerKeepsCountingWhileWaiting() {
        var tracker = BuddyTaskRunTracker()
        let start = Date(timeIntervalSince1970: 100)
        var session = SessionSnapshot()
        session.status = .running
        session.userPromptSequence = 1
        _ = tracker.update(displaySessionId: "s1", session: session, now: start, failedWhenEnding: false)

        session.status = .waitingApproval
        let waiting = tracker.update(displaySessionId: "s1", session: session, now: start.addingTimeInterval(3), failedWhenEnding: false)
        XCTAssertEqual(waiting, .active(elapsedSeconds: 3, taskRunSeq: 1, taskIdShort: "s1-1"))
    }

    func testBuddyTaskRunTrackerPreservesTimersAcrossRotatedSessions() {
        var tracker = BuddyTaskRunTracker()
        let start = Date(timeIntervalSince1970: 100)
        var first = SessionSnapshot()
        first.status = .running
        first.userPromptSequence = 1
        var second = SessionSnapshot()
        second.status = .running
        second.userPromptSequence = 1

        XCTAssertEqual(
            tracker.update(displaySessionId: "s1", session: first, now: start, failedWhenEnding: false),
            .active(elapsedSeconds: 0, taskRunSeq: 1, taskIdShort: "s1-1")
        )
        XCTAssertEqual(
            tracker.update(displaySessionId: "s2", session: second, now: start.addingTimeInterval(2), failedWhenEnding: false),
            .active(elapsedSeconds: 0, taskRunSeq: 1, taskIdShort: "s2-1")
        )
        XCTAssertEqual(
            tracker.update(displaySessionId: "s1", session: first, now: start.addingTimeInterval(4), failedWhenEnding: false),
            .active(elapsedSeconds: 4, taskRunSeq: 1, taskIdShort: "s1-1")
        )
    }

    func testBuddyTaskRunTrackerUsesPromptStartWhenFirstDisplayedLater() {
        var tracker = BuddyTaskRunTracker()
        let start = Date(timeIntervalSince1970: 100)
        var session = SessionSnapshot()
        session.status = .running
        session.userPromptSequence = 1
        session.userPromptStartedAt = start

        let delayedDisplay = tracker.update(
            displaySessionId: "s1",
            session: session,
            now: start.addingTimeInterval(5),
            failedWhenEnding: false
        )

        XCTAssertEqual(delayedDisplay, .active(elapsedSeconds: 5, taskRunSeq: 1, taskIdShort: "s1-1"))
    }

    func testBuddyTaskRunTrackerFinalizesAndRestartsForSecondPrompt() {
        var tracker = BuddyTaskRunTracker()
        let start = Date(timeIntervalSince1970: 100)
        var session = SessionSnapshot()
        session.status = .running
        session.userPromptSequence = 1
        _ = tracker.update(displaySessionId: "s1", session: session, now: start, failedWhenEnding: false)

        session.status = .idle
        let complete = tracker.update(displaySessionId: "s1", session: session, now: start.addingTimeInterval(4), failedWhenEnding: false)
        XCTAssertEqual(complete, .completed(elapsedSeconds: 4, taskRunSeq: 1, taskIdShort: "s1-1"))

        session.status = .processing
        session.userPromptSequence = 2
        let next = tracker.update(displaySessionId: "s1", session: session, now: start.addingTimeInterval(8), failedWhenEnding: false)
        XCTAssertEqual(next, .active(elapsedSeconds: 0, taskRunSeq: 2, taskIdShort: "s1-2"))
    }

    func testBuddyTaskRunTrackerEmitsFailedFinalFrame() {
        var tracker = BuddyTaskRunTracker()
        let start = Date(timeIntervalSince1970: 100)
        var session = SessionSnapshot()
        session.status = .running
        session.userPromptSequence = 7
        _ = tracker.update(displaySessionId: "s1", session: session, now: start, failedWhenEnding: false)

        session.status = .idle
        let failed = tracker.update(displaySessionId: "s1", session: session, now: start.addingTimeInterval(2), failedWhenEnding: true)
        XCTAssertEqual(failed, .failed(elapsedSeconds: 2, taskRunSeq: 7, taskIdShort: "s1-7"))
    }
}
