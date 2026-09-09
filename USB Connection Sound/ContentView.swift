import SwiftUI

struct ContentView: View {
    @Bindable var monitor: USBMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                Image(systemName: "cable.connector")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(.blue)
                    .frame(width: 60, height: 60)
                    .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 5) {
                    Text("USB Connection Sound").font(.title2.bold())
                    Text("A little sound. A clear connection.")
                        .foregroundStyle(.secondary)
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("USB sounds").font(.headline)
                            Text(monitor.enabled ? "Hear when devices come and go." : "Sounds are muted. Devices are still tracked.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 12)
                        Toggle("USB sounds", isOn: $monitor.enabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                    Divider()
                    HStack {
                        Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                        Slider(value: $monitor.volume, in: 0...1)
                            .accessibilityLabel("Sound volume")
                        Text(monitor.volume, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit().frame(width: 38, alignment: .trailing)
                    }
                    HStack {
                        preview("Connection", icon: "arrow.down.circle", connected: true)
                        preview("Disconnection", icon: "arrow.up.circle", connected: false)
                    }
                }.padding(10)
            }

            if let error = monitor.error {
                HStack {
                    Text(error).font(.caption).foregroundStyle(.red)
                    Spacer()
                    if !monitor.isRunning { Button("Retry") { monitor.start() } }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Connected devices").font(.headline)
                    Spacer()
                    Text("\(monitor.devices.count)").foregroundStyle(.secondary)
                }
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if monitor.devices.isEmpty {
                            Text("Plug in a USB device to get started.")
                                .foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 25)
                        }
                        ForEach(monitor.devices) { device in
                            HStack {
                                Image(systemName: "cable.connector").foregroundStyle(.secondary)
                                Text(device.name).lineLimit(1)
                                Spacer()
                                Circle().fill(.green).frame(width: 6, height: 6)
                            }.padding(.vertical, 9)
                        }
                    }
                }.frame(height: 112)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Latest activity").font(.headline)
                if let event = monitor.latestEvent {
                    HStack(alignment: .top) {
                        Image(systemName: event.connected ? "plus.circle.fill" : "minus.circle.fill")
                            .foregroundStyle(event.connected ? .green : .orange)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(event.name).lineLimit(1)
                            Text(event.connected ? "Connected" : "Disconnected").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(event.date, style: .time).foregroundStyle(.secondary)
                    }.font(.caption)
                } else {
                    Text("Ready for your next connection.").font(.caption).foregroundStyle(.secondary)
                }
            }.frame(height: 62, alignment: .top)

            HStack(spacing: 6) {
                Circle().fill(monitor.isRunning ? .green : .orange).frame(width: 6, height: 6)
                Text("\(monitor.isRunning ? "Listening" : "Offline") · Keeps running in the menu bar when you close this window.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(26)
        .frame(width: 480)
    }

    private func preview(_ title: String, icon: String, connected: Bool) -> some View {
        Button { monitor.preview(connected: connected) } label: {
            Label(title, systemImage: icon).frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .help("Preview the \(title.lowercased()) sound")
    }
}
