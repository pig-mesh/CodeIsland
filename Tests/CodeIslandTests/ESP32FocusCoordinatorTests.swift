import XCTest
@testable import CodeIsland
import CodeIslandCore

@MainActor
final class ESP32FocusCoordinatorTests: XCTestCase {
    func testTargetSessionIgnoresIdleAndSelectsRunningForSameMascot() {
        let appState = AppState()
        appState.sessions["idle"] = makeSession(source: "codex", status: .idle, lastActivity: Date(timeIntervalSince1970: 200))
        appState.sessions["running"] = makeSession(source: "codex", status: .running, lastActivity: Date(timeIntervalSince1970: 100))

        let target = ESP32FocusCoordinator.targetSession(for: .codex, appState: appState)

        XCTAssertEqual(target?.sessionId, "running")
        XCTAssertEqual(target?.session.status, .running)
    }

    func testTargetSessionReturnsNilWhenMascotOnlyHasIdleSessions() {
        let appState = AppState()
        appState.sessions["idle"] = makeSession(source: "codex", status: .idle)

        let target = ESP32FocusCoordinator.targetSession(for: .codex, appState: appState)

        XCTAssertNil(target)
    }

    func testTargetSessionUsesStatusPriorityAcrossActiveSessions() {
        let appState = AppState()
        appState.sessions["processing"] = makeSession(source: "codex", status: .processing, lastActivity: Date(timeIntervalSince1970: 400))
        appState.sessions["running"] = makeSession(source: "codex", status: .running, lastActivity: Date(timeIntervalSince1970: 300))
        appState.sessions["question"] = makeSession(source: "codex", status: .waitingQuestion, lastActivity: Date(timeIntervalSince1970: 200))
        appState.sessions["approval"] = makeSession(source: "codex", status: .waitingApproval, lastActivity: Date(timeIntervalSince1970: 100))

        let target = ESP32FocusCoordinator.targetSession(for: .codex, appState: appState)

        XCTAssertEqual(target?.sessionId, "approval")
        XCTAssertEqual(target?.session.status, .waitingApproval)
    }

    func testTargetSessionUsesMostRecentActivityWithinSamePriority() {
        let appState = AppState()
        appState.sessions["older"] = makeSession(source: "codex", status: .running, lastActivity: Date(timeIntervalSince1970: 100))
        appState.sessions["newer"] = makeSession(source: "codex", status: .running, lastActivity: Date(timeIntervalSince1970: 200))

        let target = ESP32FocusCoordinator.targetSession(for: .codex, appState: appState)

        XCTAssertEqual(target?.sessionId, "newer")
    }

    func testTargetSessionDoesNotSelectActiveSessionFromDifferentMascot() {
        let appState = AppState()
        appState.sessions["claude"] = makeSession(source: "claude", status: .running)

        let target = ESP32FocusCoordinator.targetSession(for: .codex, appState: appState)

        XCTAssertNil(target)
    }

    private func makeSession(
        source: String,
        status: AgentStatus,
        lastActivity: Date = Date(timeIntervalSince1970: 100)
    ) -> SessionSnapshot {
        var session = SessionSnapshot()
        session.source = source
        session.status = status
        session.lastActivity = lastActivity
        return session
    }
}
