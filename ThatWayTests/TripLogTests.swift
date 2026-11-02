//
//  TripLogTests.swift
//  ThatWayTests
//
//  The test-log maths (CPU %, counter wrap, summary) and the file behaviour, with no phone needed.
//

import Testing
import Foundation
@testable import ThatWay

struct TripLogMathTests {
    @Test func cpuPercentIsCpuTimeOverWallTime() {
        var meter = CPUMeter()
        #expect(meter.percent(cpuSeconds: 1.0, wall: 0) == nil, "first reading primes the meter")
        let p = meter.percent(cpuSeconds: 1.1, wall: 10)
        #expect(abs((p ?? 0) - 1.0) < 0.0001)
        #expect(meter.percent(cpuSeconds: 1.2, wall: 10.5) == nil, "too soon after the last reading to be reliable")
        let q = meter.percent(cpuSeconds: 1.3, wall: 20)
        #expect(abs((q ?? 0) - 2.0) < 0.0001, "measured from the last accepted reading, not the ignored one")
    }

    @Test func byteCountersSurviveWrapAround() {
        #expect(counterDelta(100, 40) == 60)
        #expect(counterDelta(5, UInt32.max - 4) == 10)
    }

    private func sample(t: Double, cpu: Double?, mem: Double, battery: Int, screen: Bool = true, fixes: Int = 2) -> TripSample {
        TripSample(t: t, cpu: cpu, memMB: mem, battery: battery, charging: false, thermal: 0, lowPower: false, screenOn: screen,
                   fixes: fixes, headings: 10, cellRx: 1000, cellTx: 100, wifiRx: 0, wifiTx: 0)
    }

    @Test func summaryAggregatesSamples() {
        let samples = [
            sample(t: 10, cpu: 1, mem: 50, battery: 80),
            sample(t: 20, cpu: 2, mem: 60, battery: 80, screen: false),
            sample(t: 30, cpu: 3, mem: 55, battery: 79),
            sample(t: 40, cpu: 10, mem: 52, battery: 79, screen: false),
        ]
        let s = TripSummary.make(mode: "walk", reason: "arrived", arrived: true, durationSec: 1800, routeMetres: 2400, progressMetres: 2390,
                                 samples: samples, counts: ["reroute": 1], freeDiskMBStart: 9000, freeDiskMBEnd: 8999, appStorageMB: 12)
        #expect(s.cpuMean == 4)
        #expect(s.cpuMax == 10)
        #expect(s.memPeakMB == 60 && s.memStartMB == 50 && s.memEndMB == 52)
        #expect(s.batteryStart == 80 && s.batteryEnd == 79)
        #expect(abs((s.batteryDropPerHour ?? 0) - 2) < 0.0001, "1 point in half an hour = 2 per hour")
        #expect(s.screenOnFraction == 0.5)
        #expect(s.fixes == 8 && s.headings == 40)
        #expect(s.cellRx == 4000 && s.cellTx == 400)
        #expect(s.counts["reroute"] == 1)
    }

    @Test func shortTripsDoNotInventABatteryRate() {
        let s = TripSummary.make(mode: "walk", reason: "ended", arrived: false, durationSec: 60, routeMetres: 0, progressMetres: 0,
                                 samples: [sample(t: 10, cpu: 1, mem: 50, battery: 80), sample(t: 20, cpu: 1, mem: 50, battery: 79)],
                                 counts: [:], freeDiskMBStart: nil, freeDiskMBEnd: nil, appStorageMB: nil)
        #expect(s.batteryDropPerHour == nil)
    }

    @Test func percentileHandlesEdges() {
        #expect(TripSummary.percentile([], 0.95) == nil)
        #expect(TripSummary.percentile([5], 0.95) == 5)
        #expect(TripSummary.percentile([1, 2, 3, 4, 100], 0.95) == 100)
    }
}

@MainActor
struct TripLogFileTests {
    private func makeDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("triplog-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func aTripWritesSessionEventsRouteAndSummaryAsJSONLines() throws {
        let dir = makeDir()
        let logger = TripLogger(directory: dir) { .init(fixes: 0, headings: 0, screenOn: true) }
        logger.begin(mode: "walk", restored: false)
        logger.routeInfo(metres: 1500, seconds: 1100, steps: 9)
        logger.count("reroute")
        logger.end(reason: "ended", arrived: false, progressMetres: 700)
        #expect(!logger.isRecording)

        let files = logger.logFiles()
        #expect(files.count == 1)
        let lines = try String(contentsOf: files[0], encoding: .utf8).split(separator: "\n")
        let objects = try lines.map { try JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any] }
        let types = objects.compactMap { $0["type"] as? String }
        #expect(types.first == "session")
        #expect(types.contains("route") && types.contains("event"))
        #expect(types.last == "summary")
        let summary = objects.last!
        #expect(summary["mode"] as? String == "walk")
        #expect(summary["progressMetres"] as? Double == 700)
        #expect((summary["counts"] as? [String: Int])?["reroute"] == 1)
    }

    @Test func logsNeverContainCoordinatesOrNames() throws {
        let dir = makeDir()
        let logger = TripLogger(directory: dir) { .init(fixes: 3, headings: 4, screenOn: true) }
        logger.begin(mode: "drive", restored: true)
        logger.routeInfo(metres: 2400, seconds: 300, steps: 12)
        logger.count("failure.offline")
        logger.end(reason: "arrived", arrived: true, progressMetres: 2390)
        let text = try String(contentsOf: logger.logFiles()[0], encoding: .utf8).lowercased()
        for forbidden in ["latitude", "longitude", "coordinate", "\"lat\"", "\"lon\"", "street", "destination"] {
            #expect(!text.contains(forbidden), "log contains '\(forbidden)'")
        }
    }

    @Test func keepsOnlyTheNewestSixtyAndExportsEverythingTogether() throws {
        let dir = makeDir()
        let logger = TripLogger(directory: dir) { .init(fixes: 0, headings: 0, screenOn: true) }
        for i in 0..<65 {
            try Data("{\"type\":\"session\",\"n\":\(i)}\n".utf8).write(to: dir.appendingPathComponent(String(format: "20260101-0000%02d-walk.jsonl", i)))
        }
        logger.begin(mode: "walk", restored: false)
        logger.end(reason: "ended", arrived: false, progressMetres: 0)
        #expect(logger.logFiles().count <= TripLogger.keepAtMost)

        let export = try #require(logger.exportCombined())
        let combined = try String(contentsOf: export, encoding: .utf8)
        #expect(combined.contains("\"type\":\"summary\""))
        try? FileManager.default.removeItem(at: export)

        logger.clear()
        #expect(logger.logFiles().isEmpty)
    }

    @Test func eventsAreIgnoredWhenNothingIsRecording() {
        let dir = makeDir()
        let logger = TripLogger(directory: dir) { .init(fixes: 0, headings: 0, screenOn: true) }
        logger.count("reroute")
        logger.routeInfo(metres: 1, seconds: 1, steps: 1)
        #expect(logger.logFiles().isEmpty)
    }
}
