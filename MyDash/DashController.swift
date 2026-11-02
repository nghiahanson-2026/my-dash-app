import ExternalAccessory
import SwiftUI
import DashProtocol

struct LogLine: Identifiable {
    let id = UUID()
    let text: String
}

/// Opens the dash link (Link A) over ExternalAccessory, runs the protocol session, and streams frames.
/// Everything runs on the main thread: the streams are scheduled on the main run loop.
///
/// Part 2 of the build: it sends a TEST picture, not a map yet. A wrong byte gives no error from the dash,
/// so the log below shows what the bike sent and what the app answered.
final class DashController: NSObject, ObservableObject {
    @Published var status = "Chờ xe… (bật khóa điện, đóng app Yamaha)"
    @Published var screenText = "—"
    @Published var framesSent = 0
    @Published var lastJPEGBytes = 0
    @Published var bikeSpeed: Int?
    @Published var lastButton = "—"
    @Published var log: [LogLine] = []

    private let protocolString = "com.garmin.navilite.data"
    private var session = DashSession()
    private var decoder = FrameDecoder()
    private var eaSession: EASession?
    private var outBuffer: [UInt8] = []
    private var timer: Timer?
    private var testCounter = 0
    private var warnedTooSmall = false

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    // MARK: Start

    func start() {
        guard timer == nil else { return }
        EAAccessoryManager.shared().registerForLocalNotifications()
        NotificationCenter.default.addObserver(self, selector: #selector(accessoryConnected(_:)),
                                               name: .EAAccessoryDidConnect, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(accessoryDisconnected(_:)),
                                               name: .EAAccessoryDidDisconnect, object: nil)
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
        addLog("App đã chạy. Đang tìm dash…")
        if let accessory = EAAccessoryManager.shared().connectedAccessories
            .first(where: { $0.protocolStrings.contains(protocolString) }) {
            open(accessory)
        }
    }

    // MARK: Accessory notifications

    @objc private func accessoryConnected(_ note: Notification) {
        guard let accessory = note.userInfo?[EAAccessoryKey] as? EAAccessory,
              accessory.protocolStrings.contains(protocolString) else { return }
        addLog("Phát hiện dash: \(accessory.name)")
        open(accessory)
    }

    @objc private func accessoryDisconnected(_ note: Notification) {
        guard let accessory = note.userInfo?[EAAccessoryKey] as? EAAccessory,
              accessory.protocolStrings.contains(protocolString) else { return }
        addLog("Dash đã ngắt kết nối")
        closeSession()
    }

    // MARK: Session

    private func open(_ accessory: EAAccessory) {
        closeSession()
        guard let s = EASession(accessory: accessory, forProtocol: protocolString) else {
            addLog("Không mở được phiên với dash (app khác đang giữ? Tắt/bật lại khóa điện)")
            return
        }
        eaSession = s
        session = DashSession()
        decoder = FrameDecoder()
        outBuffer = []
        framesSent = 0
        warnedTooSmall = false
        let streams: [Stream?] = [s.inputStream, s.outputStream]
        for stream in streams {
            stream?.delegate = self
            stream?.schedule(in: .main, forMode: .common)
            stream?.open()
        }
        status = "Đã kết nối dash. Bấm nút Home trên tay lái."
        addLog("Đã mở phiên với \(accessory.name)")
    }

    private func closeSession() {
        let streams: [Stream?] = [eaSession?.inputStream, eaSession?.outputStream]
        for stream in streams {
            stream?.close()
            stream?.remove(from: .main, forMode: .common)
            stream?.delegate = nil
        }
        eaSession = nil
        outBuffer = []
        status = "Chờ xe… (bật khóa điện, đóng app Yamaha)"
    }

    // MARK: Receiving

    private func handleIncoming(_ bytes: [UInt8]) {
        for event in decoder.feed(bytes) {
            switch event {
            case .badCRC(let command):
                addLog("Khung lỗi CRC (lệnh \(command)), bỏ qua")
            case .frame(let frame):
                let out = session.receive(frame, now: now)
                queue(out.send)
                handle(out.events)
                if frame.command != LinkA.Command.bikeSpeed && frame.command != LinkA.Command.frameAck {
                    addLog("Xe gửi lệnh \(frame.command), app trả lời \(out.send.count) khung")
                }
            }
        }
    }

    private func handle(_ events: [SessionEvent]) {
        for event in events {
            switch event {
            case .screen(let size):
                screenText = "\(size.width)×\(size.height)"
                addLog("Màn hình dash: \(size.width)×\(size.height)")
            case .startStreaming:
                status = "Đang gửi hình thử lên dash"
                addLog("Bạn đã bấm Home: bắt đầu gửi hình")
            case .stopStreaming:
                status = "Dash tạm dừng (bấm Home để tiếp tục)"
                addLog("Dash tạm dừng")
            case .button(let button):
                lastButton = button == .up ? "UP" : "DOWN"
            case .speed(let value, _):
                bikeSpeed = value
            }
        }
    }

    // MARK: Sending

    private func queue(_ frames: [Frame]) {
        guard !frames.isEmpty else { return }
        for frame in frames { outBuffer += frame.encoded() }
        flushOutput()
    }

    private func flushOutput() {
        guard let out = eaSession?.outputStream else { return }
        while !outBuffer.isEmpty, out.hasSpaceAvailable {
            let written = out.write(outBuffer, maxLength: outBuffer.count)
            if written <= 0 { break }
            outBuffer.removeFirst(written)
        }
    }

    /// Runs every 0.1 s: the session's timers, and the next test frame when the dash is ready for one.
    private func tick() {
        guard eaSession != nil else { return }
        queue(session.tick(now: now).send)
        guard session.isReadyForMapFrame else { return }

        testCounter += 1
        guard let jpeg = testJPEG() else {
            if !warnedTooSmall { warnedTooSmall = true; addLog("Ảnh JPEG quá nhỏ, không gửi được") }
            return
        }
        if let frame = session.makeMapFrame(jpeg: jpeg, now: now) {
            queue([frame])
            framesSent += 1
        }
    }

    /// A JPEG of at least 2049 bytes (smaller ones are padded by the dash: never send them).
    private func testJPEG() -> [UInt8]? {
        for quality in [0.5, 0.8, 0.95] as [CGFloat] {
            if let jpeg = TestFrameRenderer.jpeg(width: session.screen.width, height: session.screen.height,
                                                 counter: testCounter, quality: quality),
               jpeg.count >= LinkA.minSafeJPEGBytes {
                lastJPEGBytes = jpeg.count
                return jpeg
            }
        }
        return nil
    }

    // MARK: Log

    private func addLog(_ text: String) {
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        log.append(LogLine(text: "\(stamp)  \(text)"))
        if log.count > 40 { log.removeFirst(log.count - 40) }
    }
}

extension DashController: StreamDelegate {
    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        switch eventCode {
        case .hasBytesAvailable:
            guard let input = aStream as? InputStream else { return }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while input.hasBytesAvailable {
                let count = input.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                handleIncoming(Array(buffer[0..<count]))
            }
        case .hasSpaceAvailable:
            flushOutput()
        case .endEncountered, .errorOccurred:
            addLog("Đường truyền với dash đã đóng")
            closeSession()
        default:
            break
        }
    }
}
