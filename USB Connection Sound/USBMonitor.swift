import AppKit
import IOKit
import Observation

struct USBDevice: Identifiable {
    let id: UInt64
    let name: String
    var vendorName: String? = nil
    var serialNumber: String? = nil
    var vendorID: Int? = nil
    var productID: Int? = nil
    var speed: String? = nil
}

struct USBEvent: Identifiable {
    let id = UUID()
    let name: String
    let connected: Bool
    let date = Date()
}

// Keep registry lookups separate from the sorted snapshot used by the UI.
struct USBDeviceInventory {
    private var entries: [UInt64: USBDevice] = [:]

    mutating func insert(_ device: USBDevice) -> Bool {
        guard entries[device.id] == nil else { return false }
        entries[device.id] = device
        return true
    }

    mutating func remove(id: UInt64) -> USBDevice? { entries.removeValue(forKey: id) }
    func contains(id: UInt64) -> Bool { entries[id] != nil }
    var sorted: [USBDevice] {
        entries.values.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }
}

@MainActor @Observable
final class USBMonitor {
    var devices: [USBDevice] = []
    var latestEvent: USBEvent?
    var error: String?
    var isRunning = false
    var enabled = UserDefaults.standard.object(forKey: "soundEnabled") as? Bool ?? true {
        didSet {
            guard enabled != oldValue else { return }
            UserDefaults.standard.set(enabled, forKey: "soundEnabled")
        }
    }
    var volume = UserDefaults.standard.object(forKey: "soundVolume") as? Double ?? 0.6 {
        didSet {
            guard volume != oldValue else { return }
            UserDefaults.standard.set(volume, forKey: "soundVolume")
        }
    }
    @ObservationIgnored private var port: IONotificationPortRef?
    @ObservationIgnored private var added: io_iterator_t = 0
    @ObservationIgnored private var removed: io_iterator_t = 0
    @ObservationIgnored private var initializing = true
    @ObservationIgnored private var sounds: [Bool: NSSound] = [:]
    @ObservationIgnored private var lastSound: [Bool: ContinuousClock.Instant] = [:]
    @ObservationIgnored private var inventory = USBDeviceInventory()

    init() {
        for connected in [true, false] {
            if let url = Bundle.main.url(forResource: connected ? "Connect" : "Disconnect", withExtension: "wav"),
               let sound = NSSound(contentsOf: url, byReference: false) {
                sounds[connected] = sound
            }
        }
        start()
    }

    func start() {
        guard port == nil else { return }
        error = nil
        initializing = true
        guard let newPort = IONotificationPortCreate(kIOMainPortDefault) else {
            error = "Couldn’t start USB monitoring. Try again."
            return
        }
        port = newPort
        // Both callbacks run on the main queue, matching the model's isolation.
        IONotificationPortSetDispatchQueue(newPort, DispatchQueue.main)
        let context = Unmanaged.passUnretained(self).toOpaque()
        let addResult = IOServiceAddMatchingNotification(newPort, kIOFirstMatchNotification,
            IOServiceMatching("IOUSBHostDevice"), { context, iterator in
                guard let context else { return }
                MainActor.assumeIsolated {
                    Unmanaged<USBMonitor>.fromOpaque(context).takeUnretainedValue().drain(iterator, connected: true)
                }
            }, context, &added)
        guard addResult == KERN_SUCCESS else { fail(addResult); return }
        drain(added, connected: true)
        let removeResult = IOServiceAddMatchingNotification(newPort, kIOTerminatedNotification,
            IOServiceMatching("IOUSBHostDevice"), { context, iterator in
                guard let context else { return }
                MainActor.assumeIsolated {
                    Unmanaged<USBMonitor>.fromOpaque(context).takeUnretainedValue().drain(iterator, connected: false)
                }
            }, context, &removed)
        guard removeResult == KERN_SUCCESS else { fail(removeResult); return }
        drain(removed, connected: false)
        initializing = false
        isRunning = true
    }

    func stop() {
        if let port { IONotificationPortSetDispatchQueue(port, nil) }
        if added != 0 { IOObjectRelease(added); added = 0 }
        if removed != 0 { IOObjectRelease(removed); removed = 0 }
        if let port { IONotificationPortDestroy(port) }
        port = nil
        isRunning = false
        devices = []
        inventory = USBDeviceInventory()
        lastSound.removeAll(keepingCapacity: true)
        for sound in sounds.values where sound.isPlaying { sound.stop() }
    }

    private func fail(_ result: kern_return_t) {
        stop()
        error = "USB monitoring couldn’t start (\(result)). Try again."
    }

    private func drain(_ iterator: io_iterator_t, connected: Bool) {
        var changed = false
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            defer { IOObjectRelease(service) }
            var id: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(service, &id) == KERN_SUCCESS else { continue }
            if connected {
                guard !inventory.contains(id: id) else { continue }
                let name = stringProperty("USB Product Name", from: service) ?? "USB device"
                let vendorID = integerProperty("idVendor", from: service)
                let device = USBDevice(
                    id: id,
                    name: name,
                    vendorName: vendorName(from: service, vendorID: vendorID),
                    serialNumber: stringProperty("USB Serial Number", from: service),
                    vendorID: vendorID,
                    productID: integerProperty("idProduct", from: service),
                    speed: usbSpeedDescription(integerProperty("USBSpeed", from: service))
                )
                changed = inventory.insert(device) || changed
                record(name: name, connected: true)
            } else if let device = inventory.remove(id: id) {
                changed = true
                record(name: device.name, connected: false)
            }
        }
        // One sort and UI snapshot per delivered batch; sounds still start immediately.
        if changed { devices = inventory.sorted }
    }

    private func stringProperty(_ key: String, from service: io_service_t) -> String? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String
    }

    private func integerProperty(_ key: String, from service: io_service_t) -> Int? {
        let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
        return (value as? NSNumber)?.intValue
    }

    private func vendorName(from service: io_service_t, vendorID: Int?) -> String? {
        if let reportedName = stringProperty("USB Vendor Name", from: service)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !reportedName.isEmpty {
            return reportedName
        }

        // Some USB firmware supplies only the standardized numeric vendor ID.
        guard let vendorID else { return nil }
        return Self.commonVendorNames[vendorID]
    }

    private static let commonVendorNames: [Int: String] = [
        0x0502: "Acer",
        0x0781: "SanDisk",
        0x05AC: "Apple",
        0x045E: "Microsoft",
        0x046D: "Logitech",
        0x04E8: "Samsung",
        0x0951: "Kingston",
        0x1058: "Western Digital",
        0x0BC2: "Seagate",
        0x0BDA: "Realtek",
        0x8087: "Intel"
    ]

    private func usbSpeedDescription(_ value: Int?) -> String? {
        switch value {
        case 0: "Low speed (1.5 Mb/s)"
        case 1: "Full speed (12 Mb/s)"
        case 2: "High speed (480 Mb/s)"
        case 3: "SuperSpeed (5 Gb/s)"
        case 4: "SuperSpeed+ (10 Gb/s)"
        default: nil
        }
    }

    private func record(name: String, connected: Bool) {
        guard !initializing else { return }
        latestEvent = USBEvent(name: name, connected: connected)
        guard enabled, volume > 0 else { return }
        // A hub can publish several devices at once; avoid a chorus of alerts.
        let now = ContinuousClock.now
        if let last = lastSound[connected], last.duration(to: now) <= .milliseconds(500) { return }
        lastSound[connected] = now
        preview(connected: connected)
    }

    func preview(connected: Bool) {
        guard volume > 0 else { return }
        guard let sound = sounds[connected] else {
            error = "The sound file couldn’t be loaded. Rebuild the app and try again."
            return
        }
        for sound in sounds.values where sound.isPlaying { sound.stop() }
        sound.volume = Float(volume)
        if !sound.play() { error = "Couldn’t play audio. Check your Mac’s sound output." }
    }
}
