import Foundation

@main
struct MonitorSmoke {
    @MainActor static func main() {
        let monitor = USBMonitor()
        precondition(monitor.isRunning, monitor.error ?? "Monitor did not start")
        precondition(monitor.latestEvent == nil, "Existing devices should not trigger events")
        let ids = monitor.devices.map(\.id)
        precondition(Set(ids).count == ids.count, "Duplicate USB registry entries")
        print("Monitoring started; \(ids.count) existing devices; no startup alerts")
        monitor.start()
        precondition(monitor.devices.map(\.id) == ids, "Starting twice changed devices")
        monitor.stop()
        precondition(!monitor.isRunning && monitor.devices.isEmpty)
        monitor.start()
        precondition(monitor.isRunning, "Restart failed")
        precondition(monitor.latestEvent == nil, "Restart generated false events")
        monitor.stop()
        print("Idempotent start, stop, and restart passed")
        var inventory = USBDeviceInventory()
        precondition(inventory.insert(USBDevice(id: 2, name: "Hub")))
        precondition(!inventory.insert(USBDevice(id: 2, name: "Duplicate")))
        precondition(inventory.insert(USBDevice(id: 3, name: "Audio")))
        precondition(inventory.insert(USBDevice(id: 1, name: "Hub")))
        precondition(inventory.sorted.map(\.id) == [3, 1, 2])
        precondition(inventory.remove(id: 2)?.name == "Hub")
        precondition(inventory.remove(id: 2) == nil)
        precondition(inventory.sorted.map(\.id) == [3, 1])
        print("Duplicate arrivals, stable ordering, and repeated removals passed")
    }
}
