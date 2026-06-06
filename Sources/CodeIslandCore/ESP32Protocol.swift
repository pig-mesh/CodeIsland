import Foundation

/// Protocol contract for the Buddy LCD companion device.
///
/// BLE service / characteristics:
/// - Service:        `0000beef-0000-1000-8000-00805f9b34fb`
/// - Write (host→Buddy, WRITE + WRITE_NR): `0000beef-0001-1000-8000-00805f9b34fb`
/// - Notify (Buddy→host):          `0000beef-0002-1000-8000-00805f9b34fb`
///
/// Downlink agent frame (≤ 20 bytes):
///   byte[0] = sourceId (0..15, MascotID)
///   byte[1] = statusId (0..4, MascotStatusCode)
///   byte[2] = toolLen  (0..17)
///   byte[3..] = toolName UTF-8 (truncated to 17 bytes)
///
/// Downlink workspace frame (≤ 20 bytes):
///   byte[0] = 0xFC
///   byte[1] = workspaceLen (0..18)
///   byte[2..] = workspace UTF-8 (truncated to 18 bytes)
///
/// Downlink message preview frame (≤ 20 bytes):
///   byte[0] = 0xFB
///   byte[1] = messageIndex (0-based)
///   byte[2] = messageCount
///   byte[3] = flagsAndLen (bit7 = isUser, low7 = textLen)
///   byte[4..] = preview UTF-8 (truncated to 16 bytes)
///
/// Brightness config frame:
///   byte[0] = 0xFE
///   byte[1] = brightness percentage (10..100)
///
/// Screen orientation config frame:
///   byte[0] = 0xFD
///   byte[1] = orientation (0=360/default, 1=180/legacy down, 2=90, 3=270)
///
/// Speaker volume config frame:
///   byte[0] = 0xEE
///   byte[1] = volume percentage (0..100)
///
/// Downlink pair request frame (7 bytes):
///   byte[0] = 0xE0
///   byte[1..6] = hostId (6-byte stable identifier for this Mac)
///
/// Downlink unpair frame (7 bytes):
///   byte[0] = 0xE1
///   byte[1..6] = hostId
///
/// Downlink task-run frame (≤ 20 bytes):
///   byte[0] = 0xEF
///   byte[1] = flags (bit0 active, bit1 completed, bit2 failed)
///   byte[2..3] = elapsedSeconds UInt16 big-endian, clamped to 0...6000
///   byte[4..5] = taskRunSeq UInt16 big-endian
///   byte[6..7] = sessionKey UInt16 big-endian (FNV-16 of session id; 0 = all/invalid)
///   byte[8] = taskIdLen (0..9)
///   byte[9..] = taskIdShort UTF-8 (truncated to 9 bytes)
/// Buddy keeps one timer slot per sessionKey (parallel sessions). flags == 0 with
/// sessionKey != 0 clears only that session's slot; flags == 0 with sessionKey == 0
/// clears all slots.
///
/// Uplink (button notify / notification action):
///   1 byte = currently displayed mascot sourceId (focus request), or
///   1 byte = control opcode (approve / deny / skip), or
///   1 byte = pairing response (0xE0 accepted, 0xE1 rejected, 0xE2 pending), or
///   2 bytes = battery report (0xED, percentage 0..100).
///
/// **Pairing security model:**
/// The application-layer pairing is NOT a cryptographic authentication mechanism.
/// BLE link-layer encryption (if configured) provides transport security. The 6-byte
/// `hostId` is a random stable identifier used solely to distinguish multiple Macs
/// attempting to drive the same Buddy — it prevents accidental conflicts in shared
/// office environments but does not resist an active attacker who can sniff BLE
/// traffic and replay the hostId. Physical confirmation (BOOT button press) is
/// required for initial pairing, providing a weak form of user-intent verification.
/// This is appropriate for a developer desk toy; do not rely on it for access control.
///
/// Buddy firmware exits AGENT mode after 60 s with no writes, so the host
/// should resend the current frame periodically (≥ every 30 s, 5 s is the
/// recommended sync interval).
public enum ESP32Protocol {
    public static let serviceUUID = "0000beef-0000-1000-8000-00805f9b34fb"
    public static let writeCharacteristicUUID = "0000beef-0001-1000-8000-00805f9b34fb"
    public static let notifyCharacteristicUUID = "0000beef-0002-1000-8000-00805f9b34fb"

    public static let advertisedDeviceName = "Buddy"
    public static let maxToolNameBytes = 17
    public static let maxFrameBytes = 3 + maxToolNameBytes
    public static let maxWorkspaceNameBytes = 18
    public static let maxWorkspaceFrameBytes = 2 + maxWorkspaceNameBytes
    public static let maxMessagePreviewBytes = 16
    public static let maxMessagePreviewFrameBytes = 4 + maxMessagePreviewBytes
    public static let brightnessFrameMarker: UInt8 = 0xFE
    public static let orientationFrameMarker: UInt8 = 0xFD
    public static let volumeFrameMarker: UInt8 = 0xEE
    public static let batteryFrameMarker: UInt8 = 0xED
    public static let workspaceFrameMarker: UInt8 = 0xFC
    public static let messagePreviewFrameMarker: UInt8 = 0xFB
    public static let modelFrameMarker: UInt8 = 0xF9
    public static let maxModelNameBytes = 18
    public static let statsFrameMarker: UInt8 = 0xFA
    public static let subagentFrameMarker: UInt8 = 0xF8
    public static let eventFrameMarker: UInt8 = 0xF7
    public static let timeHintFrameMarker: UInt8 = 0xF6
    public static let toolHistoryFrameMarker: UInt8 = 0xF5
    public static let maxToolHistoryNameBytes = 11
    public static let taskRunFrameMarker: UInt8 = 0xEF
    public static let maxTaskRunIdBytes = 9
    public static let taskRunSessionKeyBytes = 2
    public static let maxTaskRunFrameBytes = 9 + maxTaskRunIdBytes
    public static let maxTaskRunElapsedSeconds = 6000

    /// Stable 16-bit key for a session id (FNV-1a, 16-bit folded). 0 is reserved for
    /// "all/invalid", so a real session that hashes to 0 is bumped to 1.
    public static func sessionKey(for sessionId: String) -> UInt16 {
        var hash: UInt32 = 2166136261
        for byte in sessionId.utf8 {
            hash = (hash ^ UInt32(byte)) &* 16777619
        }
        let folded = UInt16(truncatingIfNeeded: hash) ^ UInt16(truncatingIfNeeded: hash >> 16)
        return folded == 0 ? 1 : folded
    }
    public static let approveCurrentPermissionMarker: UInt8 = 0xF0
    public static let denyCurrentPermissionMarker: UInt8 = 0xF1
    public static let skipCurrentQuestionMarker: UInt8 = 0xF2

    // Pairing protocol (application-layer handshake over BLE write/notify).
    // 0xE0/0xE1 are downlink pairing opcodes, and 0xE0...0xE2 are uplink
    // pairing responses. MascotID raw values MUST stay below 0xE0 to avoid
    // collision with pair response parsing in BuddyUplinkEvent. 0xEF is used
    // by the downlink task-run frame.
    public static let pairRequestMarker: UInt8 = 0xE0
    public static let unpairMarker: UInt8 = 0xE1
    public static let hostIdLength = 6
    public static let pairRequestFrameBytes = 1 + hostIdLength   // 0xE0 + 6-byte hostId
    public static let unpairFrameBytes = 1 + hostIdLength        // 0xE1 + 6-byte hostId
    // Uplink pairing responses (Buddy → Mac via notify)
    public static let pairAcceptedMarker: UInt8 = 0xE0
    public static let pairRejectedMarker: UInt8 = 0xE1
    public static let pairPendingMarker: UInt8 = 0xE2
    public static let pairResponseTimeoutSeconds: Double = 2.5
    public static let pairLegacyFallbackSeconds: Double = pairResponseTimeoutSeconds
    public static let pairConfirmTimeoutSeconds: Int = 30

    public static let minBrightnessPercent: UInt8 = 10
    public static let maxBrightnessPercent: UInt8 = 100
    public static let defaultBrightnessPercent: UInt8 = 70
    public static let minVolumePercent: UInt8 = 0
    public static let maxVolumePercent: UInt8 = 100
    public static let defaultVolumePercent: UInt8 = 60
    /// Firmware's Bluetooth inactivity timeout (ms). Host should stay well under this.
    public static let firmwareInactivityTimeoutMs: Int = 60_000

    public static func clampedBrightnessPercent(_ percent: Double) -> UInt8 {
        guard percent.isFinite else { return defaultBrightnessPercent }
        let rounded = Int(percent.rounded())
        let minValue = Int(minBrightnessPercent)
        let maxValue = Int(maxBrightnessPercent)
        return UInt8(min(max(rounded, minValue), maxValue))
    }

    public static func clampedVolumePercent(_ percent: Double) -> UInt8 {
        guard percent.isFinite else { return defaultVolumePercent }
        let rounded = Int(percent.rounded())
        let minValue = Int(minVolumePercent)
        let maxValue = Int(maxVolumePercent)
        return UInt8(min(max(rounded, minValue), maxValue))
    }
}

public enum BuddyControlCommand: UInt8, Equatable, Sendable {
    case approveCurrentPermission = 0xF0
    case denyCurrentPermission = 0xF1
    case skipCurrentQuestion = 0xF2
}

public enum BuddyPairResponse: UInt8, Equatable, Sendable {
    case accepted = 0xE0
    case rejected = 0xE1
    case pending = 0xE2
}

/// Battery percentage reported by Buddy over the notify characteristic.
public struct BuddyBatteryPayload: Equatable, Sendable {
    public let percent: UInt8

    public init(percent: Int) {
        self.percent = UInt8(min(100, max(0, percent)))
    }

    public init?(data: Data) {
        guard data.count >= 2,
              data[0] == ESP32Protocol.batteryFrameMarker else {
            return nil
        }
        self.init(percent: Int(data[1]))
    }
}

public enum BuddyUplinkEvent: Equatable, Sendable {
    case focus(MascotID)
    case command(BuddyControlCommand)
    case pairResponse(BuddyPairResponse)
    case battery(BuddyBatteryPayload)

    public init?(payload: Data) {
        guard let first = payload.first else { return nil }
        if let battery = BuddyBatteryPayload(data: payload) {
            self = .battery(battery)
            return
        }
        // Pair responses (0xE0–0xE2) are checked first. This is safe because
        // MascotID raw values are 0..15, well below the 0xE0 reserved range.
        // If MascotID ever grows past 0xDF this ordering MUST be revisited.
        if let pairResp = BuddyPairResponse(rawValue: first) {
            self = .pairResponse(pairResp)
            return
        }
        if let mascot = MascotID(rawValue: first) {
            self = .focus(mascot)
            return
        }
        if let command = BuddyControlCommand(rawValue: first) {
            self = .command(command)
            return
        }
        return nil
    }
}

/// Physical screen rotation for Buddy.
public enum BuddyScreenOrientation: String, CaseIterable, Identifiable, Sendable {
    case degrees90 = "90"
    case degrees180 = "180"
    case degrees270 = "270"
    case degrees360 = "360"

    public var id: String { rawValue }

    public var wireValue: UInt8 {
        switch self {
        case .degrees360: return 0
        case .degrees180: return 1
        case .degrees90: return 2
        case .degrees270: return 3
        }
    }

    public init(settingsValue: String?) {
        switch settingsValue {
        case Self.degrees90.rawValue: self = .degrees90
        case Self.degrees180.rawValue, "down": self = .degrees180
        case Self.degrees270.rawValue: self = .degrees270
        case Self.degrees360.rawValue, "up": self = .degrees360
        default: self = .degrees360
        }
    }

    public init(wireValue: UInt8) {
        switch wireValue {
        case 1: self = .degrees180
        case 2: self = .degrees90
        case 3: self = .degrees270
        default: self = .degrees360
        }
    }

    public var nextQuarterTurn: BuddyScreenOrientation {
        switch self {
        case .degrees360: return .degrees90
        case .degrees90: return .degrees180
        case .degrees180: return .degrees270
        case .degrees270: return .degrees360
        }
    }
}

/// Mascot slot on Buddy (0..15). The index is the on-wire `sourceId`.
/// Raw values MUST stay below 0xE0 (see ESP32Protocol pairing reserved range).
public enum MascotID: UInt8, CaseIterable, Sendable {
    case claude = 0
    case codex = 1
    case gemini = 2
    case cursor = 3
    case copilot = 4
    case trae = 5
    case qoder = 6
    case droid = 7            // "Factory Droid"
    case codebuddy = 8
    case stepfun = 9
    case opencode = 10
    case qwen = 11
    case antigravity = 12
    case workbuddy = 13
    case hermes = 14
    case kimi = 15

    /// Canonical source name used throughout CodeIsland (matches
    /// `SessionSnapshot.supportedSources` keys).
    public var sourceName: String {
        switch self {
        case .claude:       return "claude"
        case .codex:        return "codex"
        case .gemini:       return "gemini"
        case .cursor:       return "cursor"
        case .copilot:      return "copilot"
        case .trae:         return "trae"
        case .qoder:        return "qoder"
        case .droid:        return "droid"
        case .codebuddy:    return "codebuddy"
        case .stepfun:      return "stepfun"
        case .opencode:     return "opencode"
        case .qwen:         return "qwen"
        case .antigravity:  return "antigravity"
        case .workbuddy:    return "workbuddy"
        case .hermes:       return "hermes"
        case .kimi:         return "kimi"
        }
    }

    /// Fold a CodeIsland source string (including aliases like `traecn`,
    /// `traecli`, `codybuddycn`, `factory`, `ag`) into one of the 16 slots
    /// supported by the Buddy firmware.
    public init?(sourceName: String?) {
        guard let raw = sourceName,
              let canonical = SessionSnapshot.normalizedSupportedSource(raw) else {
            return nil
        }
        switch canonical {
        case "claude":                               self = .claude
        case "codex":                                self = .codex
        case "gemini":                               self = .gemini
        case "cursor", "cursor-cli":                 self = .cursor
        case "copilot":                              self = .copilot
        case "trae", "traecn", "traecli":            self = .trae
        case "qoder", "qoder-cli":                   self = .qoder
        case "droid":                                self = .droid
        case "codebuddy", "codybuddycn":             self = .codebuddy
        case "stepfun":                              self = .stepfun
        case "opencode":                             self = .opencode
        case "qwen":                                 self = .qwen
        case "antigravity":                          self = .antigravity
        case "workbuddy":                            self = .workbuddy
        case "hermes":                               self = .hermes
        case "kimi":                                 self = .kimi
        default:                                     return nil
        }
    }
}

/// On-wire status code. Matches the Buddy firmware's `statusToScene` table:
/// 0 → SLEEP, 1/2 → WORK (toolName is drawn), 3 → ALERT, 4 → QUESTION.
public enum MascotStatusCode: UInt8, Sendable {
    case idle = 0
    case processing = 1
    case running = 2
    case waitingApproval = 3
    case waitingQuestion = 4

    public init(_ status: AgentStatus) {
        switch status {
        case .idle:              self = .idle
        case .processing:        self = .processing
        case .running:           self = .running
        case .waitingApproval:   self = .waitingApproval
        case .waitingQuestion:   self = .waitingQuestion
        }
    }
}

/// Encoded frame ready to ship over the BLE write characteristic.
public struct MascotFramePayload: Equatable, Sendable {
    public let mascot: MascotID
    public let status: MascotStatusCode
    public let toolName: String?

    public init(mascot: MascotID, status: MascotStatusCode, toolName: String? = nil) {
        self.mascot = mascot
        self.status = status
        self.toolName = toolName
    }

    /// Build a frame from a canonical source string + CodeIsland AgentStatus.
    /// Returns `nil` if `source` doesn't fold to a known mascot slot.
    public init?(source: String?, status: AgentStatus, toolName: String? = nil) {
        guard let mascot = MascotID(sourceName: source) else { return nil }
        self.init(mascot: mascot, status: MascotStatusCode(status), toolName: toolName)
    }

    /// Serialize to the on-wire byte layout.
    /// Tool name is always UTF-8 and byte-truncated to `maxToolNameBytes`;
    /// the truncation may split a multi-byte codepoint — acceptable since the
    /// Buddy uses the bytes only for a marquee label.
    public func encode() -> Data {
        var data = Data()
        data.reserveCapacity(ESP32Protocol.maxFrameBytes)
        data.append(mascot.rawValue)
        data.append(status.rawValue)

        let toolBytes: [UInt8]
        if let toolName, !toolName.isEmpty {
            let raw = Array(toolName.utf8)
            if raw.count > ESP32Protocol.maxToolNameBytes {
                toolBytes = Array(raw.prefix(ESP32Protocol.maxToolNameBytes))
            } else {
                toolBytes = raw
            }
        } else {
            toolBytes = []
        }
        data.append(UInt8(toolBytes.count))
        data.append(contentsOf: toolBytes)
        return data
    }
}

public struct BuddyWorkspacePayload: Equatable, Sendable {
    public let workspaceName: String?

    public init(workspaceName: String?) {
        let trimmed = workspaceName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.workspaceName = (trimmed?.isEmpty == false) ? trimmed : nil
    }

    public func encode() -> Data {
        var data = Data()
        data.reserveCapacity(ESP32Protocol.maxWorkspaceFrameBytes)
        data.append(ESP32Protocol.workspaceFrameMarker)
        let bytes = Self.truncatedUTF8Bytes(workspaceName, limit: ESP32Protocol.maxWorkspaceNameBytes)
        data.append(UInt8(bytes.count))
        data.append(contentsOf: bytes)
        return data
    }

    private static func truncatedUTF8Bytes(_ text: String?, limit: Int) -> [UInt8] {
        guard let text, !text.isEmpty else { return [] }
        return Array(text.utf8.prefix(limit))
    }
}

public struct BuddyMessagePreviewPayload: Equatable, Sendable {
    public let index: UInt8
    public let total: UInt8
    public let isUser: Bool
    public let text: String?

    public init(index: UInt8, total: UInt8, isUser: Bool, text: String?) {
        self.index = index
        self.total = total
        self.isUser = isUser
        self.text = Self.normalizedPreviewText(text)
    }

    public init(index: Int, total: Int, isUser: Bool, text: String?) {
        self.init(index: UInt8(max(0, min(255, index))), total: UInt8(max(0, min(255, total))), isUser: isUser, text: text)
    }

    public func encode() -> Data {
        var data = Data()
        data.reserveCapacity(ESP32Protocol.maxMessagePreviewFrameBytes)
        data.append(ESP32Protocol.messagePreviewFrameMarker)
        data.append(index)
        data.append(total)
        let bytes = Array((text ?? "").utf8.prefix(ESP32Protocol.maxMessagePreviewBytes))
        let flags = (isUser ? 0x80 : 0x00) | UInt8(bytes.count)
        data.append(flags)
        data.append(contentsOf: bytes)
        return data
    }

    private static func normalizedPreviewText(_ text: String?) -> String? {
        guard let text,
              text.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.inverted) != nil
        else {
            return nil
        }
        return text
    }
}

/// Encoded Buddy screen brightness config.
///
/// Kept as a 2-byte frame so older firmware treats it as an ignored short
/// payload instead of misreading it as an agent status update.
public struct BuddyBrightnessPayload: Equatable, Sendable {
    public let percent: UInt8

    public init(percent: Double) {
        self.percent = ESP32Protocol.clampedBrightnessPercent(percent)
    }

    public init(percent: UInt8) {
        self.percent = ESP32Protocol.clampedBrightnessPercent(Double(percent))
    }

    public func encode() -> Data {
        Data([ESP32Protocol.brightnessFrameMarker, percent])
    }
}

/// Encoded Buddy speaker cue volume config.
public struct BuddyVolumePayload: Equatable, Sendable {
    public let percent: UInt8

    public init(percent: Double) {
        self.percent = ESP32Protocol.clampedVolumePercent(percent)
    }

    public init(percent: UInt8) {
        self.percent = ESP32Protocol.clampedVolumePercent(Double(percent))
    }

    public func encode() -> Data {
        Data([ESP32Protocol.volumeFrameMarker, percent])
    }
}

/// Encoded Buddy screen orientation config.
public struct BuddyScreenOrientationPayload: Equatable, Sendable {
    public let orientation: BuddyScreenOrientation

    public init(orientation: BuddyScreenOrientation) {
        self.orientation = orientation
    }

    public func encode() -> Data {
        Data([ESP32Protocol.orientationFrameMarker, orientation.wireValue])
    }
}

/// Model info frame for Buddy (0xF9).
public struct BuddyModelPayload: Equatable, Sendable {
    public let modelName: String?

    public init(modelName: String?) { self.modelName = modelName }

    public func encode() -> Data {
        var data = Data()
        data.append(ESP32Protocol.modelFrameMarker)
        let bytes = Array((modelName ?? "").utf8.prefix(ESP32Protocol.maxModelNameBytes))
        data.append(UInt8(bytes.count))
        data.append(contentsOf: bytes)
        return data
    }
}

/// Session stats frame for Buddy (0xFA).
public struct BuddyStatsPayload: Equatable, Sendable {
    public let activeSessionCount: UInt8
    public let totalSessionCount: UInt8
    public let toolCallCount: UInt16
    public let sessionDurationMinutes: UInt8

    public init(activeSessionCount: Int, totalSessionCount: Int,
                toolCallCount: Int, sessionDurationMinutes: Int) {
        self.activeSessionCount = UInt8(min(255, max(0, activeSessionCount)))
        self.totalSessionCount = UInt8(min(255, max(0, totalSessionCount)))
        self.toolCallCount = UInt16(min(65535, max(0, toolCallCount)))
        self.sessionDurationMinutes = UInt8(min(255, max(0, sessionDurationMinutes)))
    }

    public func encode() -> Data {
        Data([
            ESP32Protocol.statsFrameMarker,
            activeSessionCount,
            totalSessionCount,
            UInt8(toolCallCount >> 8),
            UInt8(toolCallCount & 0xFF),
            sessionDurationMinutes,
        ])
    }
}

/// Subagent count frame for Buddy (0xF8).
public struct BuddySubagentPayload: Equatable, Sendable {
    public let count: UInt8

    public init(count: Int) {
        self.count = UInt8(min(15, max(0, count)))
    }

    public func encode() -> Data {
        Data([ESP32Protocol.subagentFrameMarker, count])
    }
}

/// Event frame for Buddy (0xF7) — triggers transient animations.
public struct BuddyEventPayload: Equatable, Sendable {
    public let eventId: UInt8

    public static let start    = BuddyEventPayload(eventId: 0)
    public static let complete = BuddyEventPayload(eventId: 1)
    public static let error    = BuddyEventPayload(eventId: 2)
    public static let approval = BuddyEventPayload(eventId: 3)
    public static let submit   = BuddyEventPayload(eventId: 4)

    public init(eventId: UInt8) { self.eventId = eventId }

    public func encode() -> Data {
        Data([ESP32Protocol.eventFrameMarker, eventId])
    }
}

/// Time hint frame for Buddy (0xF6).
public struct BuddyTimeHintPayload: Equatable, Sendable {
    public let hour: UInt8

    public init(hour: Int) {
        self.hour = UInt8(min(23, max(0, hour)))
    }

    public func encode() -> Data {
        Data([ESP32Protocol.timeHintFrameMarker, hour])
    }
}

public struct BuddyTaskRunFlags: OptionSet, Equatable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let active = BuddyTaskRunFlags(rawValue: 1 << 0)
    public static let completed = BuddyTaskRunFlags(rawValue: 1 << 1)
    public static let failed = BuddyTaskRunFlags(rawValue: 1 << 2)
}

/// Task-run elapsed timer frame for Buddy (0xEF).
public struct BuddyTaskRunPayload: Equatable, Sendable {
    public let flags: BuddyTaskRunFlags
    public let elapsedSeconds: UInt16
    public let taskRunSeq: UInt16
    /// Stable per-session key so Buddy can keep parallel timers (0 = all/invalid).
    public let sessionKey: UInt16
    public let taskIdShort: String?

    public init(
        flags: BuddyTaskRunFlags,
        elapsedSeconds: Int,
        taskRunSeq: Int,
        sessionKey: UInt16,
        taskIdShort: String?
    ) {
        self.flags = flags
        self.elapsedSeconds = UInt16(min(max(elapsedSeconds, 0), ESP32Protocol.maxTaskRunElapsedSeconds))
        self.taskRunSeq = UInt16(min(max(taskRunSeq, 0), Int(UInt16.max)))
        self.sessionKey = sessionKey

        let trimmed = taskIdShort?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.taskIdShort = trimmed?.isEmpty == false ? trimmed : nil
    }

    public static func active(elapsedSeconds: Int, taskRunSeq: Int, sessionKey: UInt16, taskIdShort: String?) -> BuddyTaskRunPayload {
        BuddyTaskRunPayload(flags: [.active], elapsedSeconds: elapsedSeconds, taskRunSeq: taskRunSeq, sessionKey: sessionKey, taskIdShort: taskIdShort)
    }

    public static func completed(elapsedSeconds: Int, taskRunSeq: Int, sessionKey: UInt16, taskIdShort: String?) -> BuddyTaskRunPayload {
        BuddyTaskRunPayload(flags: [.completed], elapsedSeconds: elapsedSeconds, taskRunSeq: taskRunSeq, sessionKey: sessionKey, taskIdShort: taskIdShort)
    }

    public static func failed(elapsedSeconds: Int, taskRunSeq: Int, sessionKey: UInt16, taskIdShort: String?) -> BuddyTaskRunPayload {
        BuddyTaskRunPayload(flags: [.failed], elapsedSeconds: elapsedSeconds, taskRunSeq: taskRunSeq, sessionKey: sessionKey, taskIdShort: taskIdShort)
    }

    /// Clear timer slots. `sessionKey == 0` clears every slot; a non-zero key
    /// clears only that session's slot.
    public static func clear(sessionKey: UInt16 = 0) -> BuddyTaskRunPayload {
        BuddyTaskRunPayload(flags: [], elapsedSeconds: 0, taskRunSeq: 0, sessionKey: sessionKey, taskIdShort: nil)
    }

    public func encode() -> Data {
        var data = Data()
        data.reserveCapacity(ESP32Protocol.maxTaskRunFrameBytes)
        data.append(ESP32Protocol.taskRunFrameMarker)
        data.append(flags.rawValue)
        data.append(UInt8(elapsedSeconds >> 8))
        data.append(UInt8(elapsedSeconds & 0xFF))
        data.append(UInt8(taskRunSeq >> 8))
        data.append(UInt8(taskRunSeq & 0xFF))
        data.append(UInt8(sessionKey >> 8))
        data.append(UInt8(sessionKey & 0xFF))

        let idBytes = Array((taskIdShort ?? "").utf8.prefix(ESP32Protocol.maxTaskRunIdBytes))
        data.append(UInt8(idBytes.count))
        data.append(contentsOf: idBytes)
        return data
    }
}

/// Tool history entry frame for Buddy (0xF5).
public struct BuddyToolHistoryPayload: Equatable, Sendable {
    public let index: UInt8
    public let success: Bool
    public let toolName: String

    public init(index: Int, success: Bool, toolName: String) {
        self.index = UInt8(min(255, max(0, index)))
        self.success = success
        self.toolName = toolName
    }

    public func encode() -> Data {
        var data = Data()
        data.append(ESP32Protocol.toolHistoryFrameMarker)
        data.append(index)
        let nameBytes = Array(toolName.utf8.prefix(ESP32Protocol.maxToolHistoryNameBytes))
        let flags = (success ? 0x80 : 0x00) | UInt8(nameBytes.count)
        data.append(flags)
        data.append(contentsOf: nameBytes)
        return data
    }
}

/// Tool history clear frame for Buddy (0xF5, index 0, len 0).
public struct BuddyToolHistoryClearPayload: Equatable, Sendable {
    public init() {}

    public func encode() -> Data {
        Data([ESP32Protocol.toolHistoryFrameMarker, 0, 0])
    }
}

/// Pair request frame (Mac → Buddy, 0xE0).
/// `hostId` is a stable 6-byte identifier unique to this Mac instance.
public struct BuddyPairRequestPayload: Equatable, Sendable {
    public let hostId: Data

    public init(hostId: Data) {
        self.hostId = hostId.prefix(ESP32Protocol.hostIdLength)
    }

    public func encode() -> Data {
        var data = Data()
        data.reserveCapacity(ESP32Protocol.pairRequestFrameBytes)
        data.append(ESP32Protocol.pairRequestMarker)
        var padded = hostId.prefix(ESP32Protocol.hostIdLength)
        while padded.count < ESP32Protocol.hostIdLength { padded.append(0) }
        data.append(padded)
        return data
    }
}

/// Unpair frame (Mac → Buddy, 0xE1).
/// Sent before disconnecting when the user forgets a Buddy.
public struct BuddyUnpairPayload: Equatable, Sendable {
    public let hostId: Data

    public init(hostId: Data) {
        self.hostId = hostId.prefix(ESP32Protocol.hostIdLength)
    }

    public func encode() -> Data {
        var data = Data()
        data.reserveCapacity(ESP32Protocol.unpairFrameBytes)
        data.append(ESP32Protocol.unpairMarker)
        var padded = hostId.prefix(ESP32Protocol.hostIdLength)
        while padded.count < ESP32Protocol.hostIdLength { padded.append(0) }
        data.append(padded)
        return data
    }
}
