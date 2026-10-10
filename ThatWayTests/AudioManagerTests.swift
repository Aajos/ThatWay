//
//  AudioManagerTests.swift
//  ThatWayTests
//

import Testing
import AVFoundation
import CoreLocation
@testable import ThatWay
import ThatWayCore

struct AudioManagerTests {
    @Test func announcementPointsDependOnTravelMode() {
        #expect(AudioCuePlan(mode: .drive).distances == [100, 50, 15])
        #expect(AudioCuePlan(mode: .cycle).distances == [50, 15])
        #expect(AudioCuePlan(mode: .walk).distances == [15])
        #expect(AudioCuePlan(mode: .run).distances == [15])
        // A point always carries the same number of beeps, whichever subset a mode uses.
        #expect(AudioCuePlan.toneCount(forDistance: 100) == 1)
        #expect(AudioCuePlan.toneCount(forDistance: 50) == 2)
        #expect(AudioCuePlan.toneCount(forDistance: 15) == 3)
    }

    @Test func pointsFireOnceAndNearestWinsOnAJump() {
        let plan = AudioCuePlan(mode: .drive)
        var fired = Set<Int>()
        #expect(plan.crossedPoint(currentDistance: 150, fired: &fired) == nil)
        #expect(plan.crossedPoint(currentDistance: 99, fired: &fired) == 100)
        #expect(plan.crossedPoint(currentDistance: 80, fired: &fired) == nil, "already announced")
        #expect(plan.crossedPoint(currentDistance: 49, fired: &fired) == 50)
        #expect(plan.crossedPoint(currentDistance: 10, fired: &fired) == 15)

        var jump = Set<Int>()
        #expect(plan.crossedPoint(currentDistance: 40, fired: &jump) == 50, "100m and 50m both crossed: announce the nearest only")
        #expect(plan.crossedPoint(currentDistance: 39, fired: &jump) == nil)

        var walk = Set<Int>()
        let walkPlan = AudioCuePlan(mode: .walk)
        #expect(walkPlan.crossedPoint(currentDistance: 60, fired: &walk) == nil, "walking stays quiet until the last point")
        #expect(walkPlan.crossedPoint(currentDistance: 14, fired: &walk) == 15)
    }

    @Test func voiceCueIsThreeSeparateParts() {
        let card = GuidanceCard(id: 1, kind: .turn, title: "", shortTitle: "", shortRoad: "", roadName: "",
                                turn: TurnShape(side: .left, severity: .normal), exitNumber: nil,
                                coordinate: .init(latitude: 0, longitude: 0), exitCoordinate: .init(latitude: 0, longitude: 0),
                                startAlong: 0, completeAlong: 0, legLength: 100)
        let cue = VoiceScript().cue(for: card, distanceMetres: 52, imperial: false)
        #expect(cue.utterances == ["Turn left", "at the junction", "in 50 metres"])

        let roundabout = GuidanceCard(id: 2, kind: .roundabout, title: "", shortTitle: "", shortRoad: "", roadName: "",
                                      turn: .straight, exitNumber: 2,
                                      coordinate: .init(latitude: 0, longitude: 0), exitCoordinate: .init(latitude: 0, longitude: 0),
                                      startAlong: 0, completeAlong: 0, legLength: 100)
        #expect(VoiceScript().cue(for: roundabout, distanceMetres: 100, imperial: false).utterances == ["Take the 2nd exit", "at the roundabout", "in 100 metres"])
    }

    @Test func tonePanCanBeSetFullyLeftOrRight() throws {
        for (pan, loudSide) in [(AudioPan.left, 0), (.right, 1)] {
            let (left, right) = try renderTone(count: 2, pan: pan)
            let loud = loudSide == 0 ? left : right
            let quiet = loudSide == 0 ? right : left
            #expect(loud > 0.05, "tone is audible on the panned side")
            #expect(quiet < 0.001, "and silent on the other side")
        }
        let (l, r) = try renderTone(count: 1, pan: .centre)
        #expect(l > 0.05 && r > 0.05)
    }

    /// Renders the real tone buffer through an offline AVAudioEngine and returns the peak
    /// amplitude of the left and right channels.
    private func renderTone(count: Int, pan: AudioPan) throws -> (Float, Float) {
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        let mono = AVAudioFormat(standardFormatWithSampleRate: AudioManager.sampleRate, channels: 1)!
        engine.connect(player, to: engine.mainMixerNode, format: mono)
        let stereo = AVAudioFormat(standardFormatWithSampleRate: AudioManager.sampleRate, channels: 2)!
        try engine.enableManualRenderingMode(.offline, format: stereo, maximumFrameCount: 4096)
        player.pan = pan.rawValue
        try engine.start()
        let buffer = try #require(AudioManager.toneBuffer(count: count))
        player.scheduleBuffer(buffer, at: nil)
        player.play()
        let out = AVAudioPCMBuffer(pcmFormat: stereo, frameCapacity: 4096)!
        var peakL: Float = 0, peakR: Float = 0
        var rendered = 0
        while rendered < Int(buffer.frameLength) {
            _ = try engine.renderOffline(4096, to: out)
            for i in 0..<Int(out.frameLength) {
                peakL = max(peakL, abs(out.floatChannelData![0][i]))
                peakR = max(peakR, abs(out.floatChannelData![1][i]))
            }
            rendered += Int(out.frameLength)
        }
        engine.stop()
        return (peakL, peakR)
    }

    // The one property that matters for "never stop the user's music": the session every cue is
    // played through mixes with other audio, and ducking is only ever added when asked for.
    // (Configures the session only — starting the audio engine in a test host can stall.)
    @MainActor
    @Test func sessionMixesWithOtherAudioAndOnlyDucksWhenAsked() {
        let manager = AudioManager()
        let session = AVAudioSession.sharedInstance()

        manager.activateSession(duck: false)
        #expect(session.category == .playback)
        #expect(session.categoryOptions.contains(.mixWithOthers))
        #expect(!session.categoryOptions.contains(.duckOthers))

        manager.activateSession(duck: true)
        #expect(session.categoryOptions.contains(.mixWithOthers))
        #expect(session.categoryOptions.contains(.duckOthers))
    }
}
