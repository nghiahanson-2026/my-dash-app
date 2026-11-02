import SwiftUI
import DashProtocol

@main
struct MyDashApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

struct ContentView: View {
    @StateObject private var dash = DashController()

    var body: some View {
        NavigationStack {
            List {
                Section("Dash") {
                    row("Trạng thái", dash.status)
                    row("Màn hình", dash.screenText)
                    row("Đã gửi", "\(dash.framesSent) khung (\(dash.lastJPEGBytes) byte/khung)")
                    row("Tốc độ xe", dash.bikeSpeed.map { "\($0) km/h" } ?? "—")
                    row("Nút tay lái", dash.lastButton)
                }
                Section("Nhật ký (gửi cho trợ lý nếu có lỗi)") {
                    if dash.log.isEmpty {
                        Text("Chưa có gì").foregroundStyle(.secondary)
                    }
                    ForEach(dash.log.reversed()) { line in
                        Text(line.text).font(.caption.monospaced())
                    }
                }
            }
            .navigationTitle("MyDash")
        }
        .onAppear { dash.start() }
    }

    private func row(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value)
        }
    }
}
