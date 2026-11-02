import Foundation

public enum DashButton: Equatable { case up, down }

/// Things the app should react to (the frames to send are returned separately).
public enum SessionEvent: Equatable {
    case screen(ScreenSize)
    case startStreaming
    case stopStreaming
    case button(DashButton)
    case speed(Int, isMph: Bool)
}

public struct SessionOutput: Equatable {
    public var send: [Frame] = []
    public var events: [SessionEvent] = []
    public init(send: [Frame] = [], events: [SessionEvent] = []) { self.send = send; self.events = events }
}

/// The Link A session logic: handshake, init, show/pause, handlebar buttons, one map frame in flight.
///
/// Pure logic, no I/O and no clock of its own: the transport feeds it decoded frames and the current time,
/// and sends whatever comes back. That is what lets the vectors test it at home (lifecycle.md).
///
/// Rules (docs/protocol/link-a-dash.md):
/// - On 66: send 81 then 33. A new 66 resets everything.
/// - Send the init only after seeing 83 and then an 82. An 82 before 83 does not count;
///   a repeated 83 starts over. If that never happens, send the init 2 s after the first 82.
/// - On 55 `01 00`: resend state (2, 14, 13, 3, 10, 11) and start streaming.
/// - On 56: stop streaming and reply 20 (documented, not yet observed).
/// - After every handlebar press (51/52): reply 14 flag 1 `07 1A 00 00`.
/// - One map frame in flight: the next one goes only after its ACK (80).
public struct DashSession {
    private enum Stage { case waiting, challengeSeen, initSent }

    public static let initFallbackDelay: TimeInterval = 2.0
    /// assumed (a design choice, not a bike rule): give up waiting for an ACK so a lost one cannot stall the map.
    public static let ackTimeout: TimeInterval = 3.0

    public var homeSaved = false
    public var workSaved = false
    /// Resent on every 55: the dash forgets it across a pause.
    public private(set) var bottomBarText = ""

    public private(set) var screen = ScreenSize(width: 480, height: 234)
    public private(set) var isStreaming = false

    private var stage: Stage = .waiting
    private var firstAuthAt: TimeInterval?
    private var inFlightSince: TimeInterval?
    private var nextFrameID: UInt16 = 1

    public init() {}

    /// True when the rider has pressed Home and no map frame is waiting for its ACK.
    public var isReadyForMapFrame: Bool { isStreaming && inFlightSince == nil }

    // MARK: Receiving

    public mutating func receive(_ frame: Frame, now: TimeInterval) -> SessionOutput {
        var out = SessionOutput()
        switch BikeMessage.parse(frame) {
        case .serial:
            resetLink()
            out.send = LinkA.hello()

        case .challenge(_, let key, let size):
            screen = size
            stage = .challengeSeen
            out.send = [LinkA.challengeResponse(key: key)]
            out.events = [.screen(size)]

        case .authenticated(let accepted):
            guard accepted else { break }
            switch stage {
            case .challengeSeen:
                stage = .initSent
                out.send = initFrames()
            case .waiting:
                if firstAuthAt == nil { firstAuthAt = now }   // early 82: only starts the 2 s fallback
            case .initSent:
                break
            }

        case .showFrames:
            isStreaming = true
            inFlightSince = nil
            out.send = LinkA.showFramesReply(homeSaved: homeSaved, workSaved: workSaved, bottomBar: bottomBarText)
            out.events = [.startStreaming]

        case .pause:
            let wasStreaming = isStreaming
            isStreaming = false
            inFlightSince = nil
            out.send = [LinkA.pauseAck()]
            if wasStreaming { out.events = [.stopStreaming] }

        case .up:
            out.send = [LinkA.rearmButtons()]
            out.events = [.button(.up)]

        case .down:
            out.send = [LinkA.rearmButtons()]
            out.events = [.button(.down)]

        case .speed(let value, let isMph):
            out.events = [.speed(value, isMph: isMph)]

        case .ack:
            inFlightSince = nil

        case .other:
            break
        }
        return out
    }

    /// Call about once a second (or on any timer). Returns frames to send, if any.
    public mutating func tick(now: TimeInterval) -> SessionOutput {
        var out = SessionOutput()
        if stage != .initSent, let first = firstAuthAt, now - first >= DashSession.initFallbackDelay {
            stage = .initSent
            out.send = initFrames()
        }
        if let since = inFlightSince, now - since >= DashSession.ackTimeout {
            inFlightSince = nil
        }
        return out
    }

    // MARK: Sending

    /// The next map frame, or nil if the dash is not showing frames, one is still in flight,
    /// or the JPEG is too small to be safe. Sends one frame, then waits for its ACK.
    public mutating func makeMapFrame(jpeg: [UInt8], now: TimeInterval) -> Frame? {
        guard isStreaming, inFlightSince == nil,
              let frame = LinkA.mapFrame(id: nextFrameID, jpeg: jpeg) else { return nil }
        nextFrameID = nextFrameID == UInt16.max ? 1 : nextFrameID + 1
        inFlightSince = now
        return frame
    }

    /// Change the bottom-bar text (street name). Empty clears it. Returns the frame to send now.
    public mutating func setBottomBar(_ text: String) -> Frame {
        bottomBarText = text
        return LinkA.bottomBar(text)
    }

    // MARK: Private

    private func initFrames() -> [Frame] {
        LinkA.initSequence(homeSaved: homeSaved, workSaved: workSaved, bottomBar: bottomBarText)
    }

    private mutating func resetLink() {
        stage = .waiting
        firstAuthAt = nil
        inFlightSince = nil
        isStreaming = false
    }
}
