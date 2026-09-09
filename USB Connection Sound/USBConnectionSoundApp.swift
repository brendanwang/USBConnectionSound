import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
struct USBConnectionSoundApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var monitor = USBMonitor()

    var body: some Scene {
        Window("USB Connection Sound", id: "main") {
            ContentView(monitor: monitor)
        }
        .defaultSize(width: 480, height: 590)
        .windowResizability(.contentSize)

        MenuBarExtra("USB Connection Sound", systemImage: monitor.enabled ? "cable.connector" : "speaker.slash") {
            MenuContent(monitor: monitor)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuContent: View {
    @Bindable var monitor: USBMonitor
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Label("USB Connection Sound", systemImage: "cable.connector")
                    .font(.headline)
                Text(monitor.isRunning ? "Listening · \(monitor.devices.count) USB devices" : "Monitoring unavailable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Toggle("Play USB sounds", isOn: $monitor.enabled)
                .toggleStyle(.switch)

            VStack(spacing: 6) {
                HStack {
                    Text("Volume")
                    Spacer()
                    Text(monitor.volume, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    Image(systemName: "speaker.fill")
                    Slider(value: $monitor.volume, in: 0...1)
                        .accessibilityLabel("USB sound volume")
                    Image(systemName: "speaker.wave.3.fill")
                }
                .foregroundStyle(.secondary)
            }

            HStack {
                Button("Connection") { monitor.preview(connected: true) }
                    .help("Preview the connection sound")
                Button("Disconnection") { monitor.preview(connected: false) }
                    .help("Preview the disconnection sound")
            }
            .frame(maxWidth: .infinity)

            if let error = monitor.error {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            Divider()
            HStack {
                Button("Open App") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button("Quit") {
                    monitor.stop()
                    NSApp.terminate(nil)
                }.keyboardShortcut("q")
            }
        }
        .padding(16)
        .frame(width: 280)
    }
}
