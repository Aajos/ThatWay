//
//  SpikeLog.swift
//  ThatWayWatch
//
//  Numbers-only JSON-lines log for the spike: speed, heading, course, accuracy, source, battery, update
//  counts, haptic trial answers. NEVER coordinates, places or routes. Files live in Documents/SpikeLogs
//  (copy them off over the cable: see docs/watch-spike.md).
//

import Foundation

@MainActor
final class SpikeLog {
    static let shared = SpikeLog()
    private var handle: FileHandle?
    private var startedAt = Date()
    private(set) var label = ""
    var isOpen: Bool { handle != nil }

    private var directory: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents/SpikeLogs", isDirectory: true)
    }

    func open(label: String) {
        close()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"
        let url = directory.appendingPathComponent("\(f.string(from: Date()))-\(label).jsonl")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try? FileHandle(forWritingTo: url)
        startedAt = Date()
        self.label = label
        write(["type": "open", "label": label, "started": ISO8601DateFormatter().string(from: startedAt)])
    }

    func close() {
        guard handle != nil else { return }
        write(["type": "close"])
        try? handle?.close()
        handle = nil
    }

    func write(_ object: [String: Any]) {
        guard let handle else { return }
        var o = object
        o["t"] = (Date().timeIntervalSince(startedAt) * 100).rounded() / 100
        guard let data = try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys]) else { return }
        handle.write(data + Data([0x0A]))
    }
}
