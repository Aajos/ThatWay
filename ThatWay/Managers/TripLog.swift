//
//  TripLog.swift
//  ThatWay
//
//  Real-world test logs. While a trip is being guided, a sample is taken every 10 seconds — this
//  app's CPU use, memory, battery, thermal state, network traffic and a few counters — and a
//  summary is written when the trip ends. Files are plain JSON-lines in Documents/TripLogs, which
//  shows up in the Files app (On My iPhone ▸ ThatWay) and can be shared from Profile ▸ Test logs
//  or copied off the phone over a cable.
//
//  Numbers only: no coordinates, no place names, no route shapes, no account details ever go in a
//  log. A route is recorded as its length, duration and step count.
//

import Foundation
import UIKit
import Darwin

// MARK: - Pure helpers (unit-tested)

/// Turns a running CPU-seconds counter into a percentage between two readings.
struct CPUMeter {
    private var last: (cpu: Double, wall: Double)?

    /// Percent of one core used since the previous reading (nil for the first, or if time didn't advance).
    mutating func percent(cpuSeconds: Double, wall: Double, minimumInterval: Double = 2) -> Double? {
        guard let previous = last else { last = (cpuSeconds, wall); return nil }
        // A reading taken moments after the last one says nothing reliable: keep waiting.
        guard wall - previous.wall >= minimumInterval else { return nil }
        last = (cpuSeconds, wall)
        return max(0, (cpuSeconds - previous.cpu) / (wall - previous.wall) * 100)
    }
}

/// Difference of two 32-bit interface byte counters, which wrap around at 4 GB.
func counterDelta(_ new: UInt32, _ old: UInt32) -> UInt64 { UInt64(new &- old) }

struct TripSample: Codable, Equatable {
    var t: Double                 // seconds since the trip began
    var cpu: Double?              // % of one core, this app only
    var memMB: Double             // physical footprint
    var battery: Int              // 0-100, -1 unknown
    var charging: Bool
    var thermal: Int              // 0 nominal ... 3 critical
    var lowPower: Bool
    var screenOn: Bool
    var fixes: Int                // GPS fixes since the previous sample
    var headings: Int             // compass updates since the previous sample
    var cellRx: UInt64, cellTx: UInt64, wifiRx: UInt64, wifiTx: UInt64   // device-wide bytes since the previous sample
}

struct TripSummary: Codable, Equatable {
    var mode: String
    var reason: String
    var arrived: Bool
    var durationSec: Double
    var routeMetres: Double
    var progressMetres: Double
    var cpuMean: Double?, cpuP95: Double?, cpuMax: Double?
    var memStartMB: Double?, memPeakMB: Double?, memEndMB: Double?
    var batteryStart: Int, batteryEnd: Int
    var batteryDropPerHour: Double?
    var thermalMax: Int
    var screenOnFraction: Double
    var fixes: Int, headings: Int
    var cellRx: UInt64, cellTx: UInt64, wifiRx: UInt64, wifiTx: UInt64
    var counts: [String: Int]
    var freeDiskMBStart: Double?, freeDiskMBEnd: Double?, appStorageMB: Double?

    static func percentile(_ values: [Double], _ p: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        return sorted[min(sorted.count - 1, Int((Double(sorted.count - 1) * p).rounded(.up)))]
    }

    static func make(
        mode: String, reason: String, arrived: Bool, durationSec: Double, routeMetres: Double, progressMetres: Double,
        samples: [TripSample], counts: [String: Int],
        freeDiskMBStart: Double?, freeDiskMBEnd: Double?, appStorageMB: Double?
    ) -> TripSummary {
        let cpu = samples.compactMap(\.cpu)
        let known = samples.map(\.battery).filter { $0 >= 0 }
        let start = known.first ?? -1, end = known.last ?? -1
        let hours = durationSec / 3600
        let drop: Double? = (start >= 0 && end >= 0 && hours > 0.05) ? Double(start - end) / hours : nil
        let screenOn = samples.isEmpty ? 0 : Double(samples.filter(\.screenOn).count) / Double(samples.count)
        return TripSummary(
            mode: mode, reason: reason, arrived: arrived, durationSec: durationSec,
            routeMetres: routeMetres, progressMetres: progressMetres,
            cpuMean: cpu.isEmpty ? nil : cpu.reduce(0, +) / Double(cpu.count),
            cpuP95: percentile(cpu, 0.95), cpuMax: cpu.max(),
            memStartMB: samples.first?.memMB, memPeakMB: samples.map(\.memMB).max(), memEndMB: samples.last?.memMB,
            batteryStart: start, batteryEnd: end, batteryDropPerHour: drop,
            thermalMax: samples.map(\.thermal).max() ?? 0, screenOnFraction: screenOn,
            fixes: samples.reduce(0) { $0 + $1.fixes }, headings: samples.reduce(0) { $0 + $1.headings },
            cellRx: samples.reduce(0) { $0 + $1.cellRx }, cellTx: samples.reduce(0) { $0 + $1.cellTx },
            wifiRx: samples.reduce(0) { $0 + $1.wifiRx }, wifiTx: samples.reduce(0) { $0 + $1.wifiTx },
            counts: counts,
            freeDiskMBStart: freeDiskMBStart, freeDiskMBEnd: freeDiskMBEnd, appStorageMB: appStorageMB
        )
    }
}

// MARK: - System readings

enum DeviceStats {
    /// Total CPU time (user + system) this process has used, in seconds.
    static func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        func secs(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1_000_000 }
        return secs(usage.ru_utime) + secs(usage.ru_stime)
    }

    /// The app's physical memory footprint (what Xcode's memory gauge shows), in MB.
    static func memoryMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }

    /// Device-wide bytes received/sent on the cellular (pdp_ip0) and Wi-Fi (en0) interfaces.
    static func network() -> (cellRx: UInt32, cellTx: UInt32, wifiRx: UInt32, wifiTx: UInt32) {
        var result: (UInt32, UInt32, UInt32, UInt32) = (0, 0, 0, 0)
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return result }
        defer { freeifaddrs(head) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            let name = String(cString: entry.pointee.ifa_name)
            if let addr = entry.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK), let raw = entry.pointee.ifa_data {
                let data = raw.assumingMemoryBound(to: if_data.self).pointee
                if name == "pdp_ip0" { result.0 &+= data.ifi_ibytes; result.1 &+= data.ifi_obytes }
                else if name == "en0" { result.2 &+= data.ifi_ibytes; result.3 &+= data.ifi_obytes }
            }
            cursor = entry.pointee.ifa_next
        }
        return result
    }

    static func freeDiskMB() -> Double? {
        let values = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage.map { Double($0) / 1_048_576 }
    }

    /// Size of everything the app keeps on disk (Documents, Library), in MB.
    static func appStorageMB() -> Double {
        var total: Int64 = 0
        for dir in [NSHomeDirectory() + "/Documents", NSHomeDirectory() + "/Library"] {
            guard let walker = FileManager.default.enumerator(atPath: dir) else { continue }
            for case let path as String in walker {
                if let size = (try? FileManager.default.attributesOfItem(atPath: dir + "/" + path))?[.size] as? Int64 { total += size }
            }
        }
        return Double(total) / 1_048_576
    }

    static var modelIdentifier: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return "\(simulated) (simulator)" }
        var system = utsname()
        uname(&system)
        return withUnsafePointer(to: &system.machine) { $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) } }
    }
}

// MARK: - Logger

@MainActor
final class TripLogger {
    /// What the logger asks the app for at each sample.
    struct Live {
        var fixes: Int
        var headings: Int
        var screenOn: Bool
    }

    static let sampleInterval: TimeInterval = 10
    static let keepAtMost = 60

    let directory: URL
    private let live: () -> Live
    private(set) var isRecording = false

    private var handle: FileHandle?
    private var startedAt = Date()
    private var timer: Timer?
    private var samples: [TripSample] = []
    private var counts: [String: Int] = [:]
    private var cpu = CPUMeter()
    private var lastNet = DeviceStats.network()
    private var lastFixes = 0, lastHeadings = 0
    private var mode = "", routeMetres = 0.0
    private var freeDiskStart: Double?
    private var lowPowerNow = false

    init(directory: URL? = nil, live: @escaping () -> Live) {
        self.directory = directory ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents/TripLogs", isDirectory: true)
        self.live = live
    }

    // MARK: Session

    func begin(mode: String, restored: Bool) {
        guard !isRecording else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        prune()
        let stamp = DateFormatter.fileStamp.string(from: Date())
        let url = directory.appendingPathComponent("\(stamp)-\(mode).jsonl")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try? FileHandle(forWritingTo: url)
        isRecording = true
        startedAt = Date()
        samples = []; counts = [:]; cpu = CPUMeter()
        self.mode = mode; routeMetres = 0
        lastNet = DeviceStats.network()
        let snapshot = live()
        lastFixes = snapshot.fixes; lastHeadings = snapshot.headings
        freeDiskStart = DeviceStats.freeDiskMB()
        UIDevice.current.isBatteryMonitoringEnabled = true
        lowPowerNow = ProcessInfo.processInfo.isLowPowerModeEnabled

        let info = Bundle.main.infoDictionary
        write(["type": "session",
               "started": ISO8601DateFormatter().string(from: startedAt),
               "mode": mode, "restored": restored,
               "device": DeviceStats.modelIdentifier, "os": UIDevice.current.systemVersion,
               "app": "\(info?["CFBundleShortVersionString"] ?? "?") (\(info?["CFBundleVersion"] ?? "?"))",
               "lowPower": lowPowerNow, "sampleEverySec": Self.sampleInterval])
        _ = cpu.percent(cpuSeconds: DeviceStats.cpuSeconds(), wall: 0)    // primes the meter
        timer = Timer.scheduledTimer(withTimeInterval: Self.sampleInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
        timer?.tolerance = 1
    }

    func end(reason: String, arrived: Bool, progressMetres: Double) {
        guard isRecording else { return }
        sample()
        timer?.invalidate(); timer = nil
        let summary = TripSummary.make(
            mode: mode, reason: reason, arrived: arrived, durationSec: Date().timeIntervalSince(startedAt),
            routeMetres: routeMetres, progressMetres: progressMetres, samples: samples, counts: counts,
            freeDiskMBStart: freeDiskStart, freeDiskMBEnd: DeviceStats.freeDiskMB(), appStorageMB: DeviceStats.appStorageMB()
        )
        if let data = try? JSONEncoder.line.encode(summary), var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            object["type"] = "summary"
            write(object)
        }
        try? handle?.close(); handle = nil
        isRecording = false
        UIDevice.current.isBatteryMonitoringEnabled = false
    }

    // MARK: Events

    /// Counts something that happened (reroutes, offline spells, compass warnings…).
    func count(_ name: String) {
        guard isRecording else { return }
        counts[name, default: 0] += 1
        write(["type": "event", "t": rounded(Date().timeIntervalSince(startedAt)), "name": name])
    }

    /// The route's size only — never its shape.
    func routeInfo(metres: Double, seconds: Double, steps: Int) {
        guard isRecording else { return }
        routeMetres = metres
        write(["type": "route", "t": rounded(Date().timeIntervalSince(startedAt)),
               "metres": rounded(metres), "etaSec": rounded(seconds), "steps": steps])
    }

    func noteLowPower(_ on: Bool) { lowPowerNow = on; if isRecording { count(on ? "lowPowerOn" : "lowPowerOff") } }

    // MARK: Sampling

    private func sample() {
        guard isRecording else { return }
        let now = Date()
        let snapshot = live()
        let net = DeviceStats.network()
        let level = UIDevice.current.batteryLevel
        let state = UIDevice.current.batteryState
        let sample = TripSample(
            t: rounded(now.timeIntervalSince(startedAt)),
            cpu: cpu.percent(cpuSeconds: DeviceStats.cpuSeconds(), wall: now.timeIntervalSince(startedAt)).map(rounded),
            memMB: rounded(DeviceStats.memoryMB()),
            battery: level < 0 ? -1 : Int((level * 100).rounded()),
            charging: state == .charging || state == .full,
            thermal: ProcessInfo.processInfo.thermalState.rawValue,
            lowPower: lowPowerNow,
            screenOn: snapshot.screenOn,
            fixes: max(0, snapshot.fixes - lastFixes), headings: max(0, snapshot.headings - lastHeadings),
            cellRx: counterDelta(net.cellRx, lastNet.cellRx), cellTx: counterDelta(net.cellTx, lastNet.cellTx),
            wifiRx: counterDelta(net.wifiRx, lastNet.wifiRx), wifiTx: counterDelta(net.wifiTx, lastNet.wifiTx)
        )
        lastNet = net; lastFixes = snapshot.fixes; lastHeadings = snapshot.headings
        samples.append(sample)
        if let data = try? JSONEncoder.line.encode(sample), var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            object["type"] = "sample"
            write(object)
        }
    }

    // MARK: Files

    private func write(_ object: [String: Any]) {
        guard let handle,
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return }
        handle.write(data + Data([0x0A]))
    }

    private func rounded(_ v: Double) -> Double { (v * 100).rounded() / 100 }

    /// Newest first.
    func logFiles() -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "jsonl" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// Keeps the folder from growing without bound.
    private func prune() {
        for url in logFiles().dropFirst(Self.keepAtMost - 1) { try? FileManager.default.removeItem(at: url) }
    }

    func totalSizeKB() -> Double {
        logFiles().reduce(0.0) { $0 + Double((try? FileManager.default.attributesOfItem(atPath: $1.path))?[.size] as? Int64 ?? 0) } / 1024
    }

    func clear() {
        guard !isRecording else { return }
        for url in logFiles() { try? FileManager.default.removeItem(at: url) }
    }

    /// One file holding every saved trip (oldest first), ready to share.
    func exportCombined() -> URL? {
        let files = logFiles().reversed()
        guard !files.isEmpty else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ThatWay-testlogs-\(DateFormatter.fileStamp.string(from: Date())).jsonl")
        var combined = Data()
        for file in files { if let data = try? Data(contentsOf: file) { combined.append(data) } }
        try? combined.write(to: url)
        return url
    }
}

private extension DateFormatter {
    static let fileStamp: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"; return f }()
}

private extension JSONEncoder {
    static let line: JSONEncoder = { let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]; return e }()
}
