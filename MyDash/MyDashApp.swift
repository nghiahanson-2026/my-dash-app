import SwiftUI
import DashProtocol

@main
struct MyDashApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

/// Part 1 skeleton: proves the protocol package is linked into the app.
/// The dash connection, share target, route and map renderer come in the next parts.
struct ContentView: View {
    private let selfTest: String = {
        // The same check the vectors run: CRC-32/MPEG-2 of "123456789" must be 0x0376E6E7.
        let crc = CRC32MPEG2.checksum(Array("123456789".utf8))
        return crc == 0x0376_E6E7 ? "Protocol code: OK" : "Protocol code: ERROR"
    }()

    var body: some View {
        VStack(spacing: 12) {
            Text("MyDash").font(.largeTitle).bold()
            Text(selfTest)
            Text("Dash: not connected yet").foregroundStyle(.secondary)
        }
        .padding()
    }
}
