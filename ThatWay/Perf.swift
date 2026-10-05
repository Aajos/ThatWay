//
//  Perf.swift
//  ThatWay
//
//  Test-only instrumentation, compiled in only with the PERF flag (never in a shipping build).
//  `-TW_OFF a,b,c` switches individual links of the chain off so each one's cost can be measured
//  by A/B; counters are sampled once a second and written to Documents/perf-result.json.
//  Records numbers only — never coordinates or routes.
//

import Foundation
import SwiftUI

enum Perf {
    #if PERF
    static let off: Set<String> = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-TW_OFF"), i + 1 < args.count else { return [] }
        return Set(args[i + 1].split(separator: ",").map(String.init))
    }()
    static func on(_ link: String) -> Bool { !off.contains(link) }
    /// `-TW_GHOST 1` forces the "compass may be off" overlay so it can be inspected in the simulator
    /// (which has no compass to go wrong).
    static let ghost = ProcessInfo.processInfo.arguments.contains("-TW_GHOST")
    static func anim(_ a: Animation) -> Animation? { on("anim") ? a : nil }

    private static let lock = NSLock()
    private static var counts: [String: Int] = [:]
    private static var stamps: [String: [Double]] = [:]
    private static var timer: Timer?
    private static var samples: [[String: Double]] = []
    private static var lastCounts: [String: Int] = [:]
    private static var lastCPU = 0.0
    private static var lastMain = 0.0
    private static var lastWall = 0.0
    private static var mainThread: mach_port_t = 0

    static func hit(_ key: String) {
        lock.lock(); counts[key, default: 0] += 1; lock.unlock()
    }

    /// Records a timestamp for jitter statistics (gap between consecutive events).
    static func stamp(_ key: String) {
        lock.lock(); stamps[key, default: []].append(Date().timeIntervalSinceReferenceDate); lock.unlock()
    }

    static func start() {
        guard ProcessInfo.processInfo.arguments.contains("-TW_PERF"), timer == nil else { return }
        mainThread = mach_thread_self()
        lastWall = Date().timeIntervalSinceReferenceDate
        lastCPU = processCPU()
        lastMain = mainThreadCPU()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in sample() }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private static func sample() {
        let now = Date().timeIntervalSinceReferenceDate
        let cpu = processCPU(), main = mainThreadCPU()
        let dt = max(0.001, now - lastWall)
        lock.lock()
        var row: [String: Double] = ["t": now, "cpu_pct": 100 * (cpu - lastCPU) / dt, "main_pct": 100 * (main - lastMain) / dt]
        for (k, v) in counts { row[k] = Double(v - lastCounts[k, default: 0]) / dt }
        lastCounts = counts
        samples.append(row)
        let result = summary()
        let flush = samples.count % 15 == 0
        lock.unlock()
        lastCPU = cpu; lastMain = main; lastWall = now
        // File writes are not free (rename/fsync showed up as ~17 % of the profile), so flush every 15 s.
        guard flush else { return }
        if let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("perf-result.json"),
           let data = try? JSONSerialization.data(withJSONObject: result) {
            try? data.write(to: url)
        }
    }

    private static func summary() -> [String: Any] {
        var out: [String: Any] = ["off": Array(off).sorted(), "seconds": samples.count]
        var keys = Set<String>()
        for s in samples { keys.formUnion(s.keys) }
        keys.remove("t")
        let measured = samples.dropFirst(15) // 15 s warm-up is dropped
        var means: [String: Double] = [:]
        for k in keys {
            let v = measured.map { $0[k] ?? 0 }
            if !v.isEmpty { means[k] = v.reduce(0, +) / Double(v.count) }
        }
        out["mean"] = means
        let cpus = measured.map { $0["cpu_pct"] ?? 0 }.sorted()
        if !cpus.isEmpty { out["cpu_p95"] = cpus[min(cpus.count - 1, Int(Double(cpus.count) * 0.95))]; out["cpu_max"] = cpus.last! }
        var jitter: [String: [String: Double]] = [:]
        for (k, ts) in stamps where ts.count > 4 {
            let gaps = zip(ts.dropFirst(), ts).map { ($0 - $1) * 1000 }.sorted()
            jitter[k] = ["p95_ms": gaps[min(gaps.count - 1, Int(Double(gaps.count) * 0.95))], "max_ms": gaps.last ?? 0, "n": Double(gaps.count)]
        }
        out["gaps"] = jitter
        return out
    }

    private static func processCPU() -> Double {
        var info = task_thread_times_info()
        var count = mach_msg_type_number_t(MemoryLayout<task_thread_times_info>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_THREAD_TIMES_INFO), $0, &count) }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        // Time of live threads; the task total below adds threads that already exited.
        var basic = mach_task_basic_info()
        var bcount = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let kr2 = withUnsafeMutablePointer(to: &basic) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(bcount)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &bcount) }
        }
        guard kr2 == KERN_SUCCESS else { return 0 }
        func secs(_ t: time_value_t) -> Double { Double(t.seconds) + Double(t.microseconds) / 1_000_000 }
        return secs(basic.user_time) + secs(basic.system_time) + secs(info.user_time) + secs(info.system_time)
    }

    private static func mainThreadCPU() -> Double {
        var info = thread_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { thread_info(mainThread, thread_flavor_t(THREAD_BASIC_INFO), $0, &count) }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        func secs(_ t: time_value_t) -> Double { Double(t.seconds) + Double(t.microseconds) / 1_000_000 }
        return secs(info.user_time) + secs(info.system_time)
    }
    #else
    @inline(__always) static func on(_ link: String) -> Bool { true }
    static let ghost = false
    @inline(__always) static func anim(_ a: Animation) -> Animation? { a }
    @inline(__always) static func hit(_ key: String) {}
    @inline(__always) static func stamp(_ key: String) {}
    @inline(__always) static func start() {}
    #endif
}
