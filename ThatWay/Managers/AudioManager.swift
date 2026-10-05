//
//  AudioManager.swift
//  ThatWay
//
//  Audio guidance cues. NOT wired into guidance yet — nothing calls `announce` today; the
//  setting in Profile only stores the user's choice. When wired, AppModel feeds each new
//  distance-to-next-instruction into `AudioCuePlan` and forwards whatever it returns here.
//
//  Two styles the user can pick between:
//  - Tone: 1, 2 or 3 soft beeps at 100m / 50m / 15m, panned to the side of the turn.
//  - Voice: three separate spoken parts — "[direction / exit]", "[turn type]", "[distance]" —
//    e.g. "Turn left" … "at the junction" … "in 50 metres", at the same distances.
//
//  Playback mixes with whatever else is playing (music, podcasts): it never pauses or
//  interrupts it. See `duckMusicDuringVoice` for the one optional exception.
//

import Foundation
import AVFoundation
import Combine

enum AudioGuidanceStyle: String, Codable, CaseIterable {
    case off, tone, voice

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .tone: return "Tone"
        case .voice: return "Voice"
        }
    }
}

/// Where a tone sits in the stereo field.
enum AudioPan: Float {
    case left = -1, centre = 0, right = 1

    init(turn: TurnDir) {
        switch turn {
        case .left: self = .left
        case .right: self = .right
        default: self = .centre
        }
    }
}

/// When cues fire. The three announcement points are 100m, 50m and 15m from the turn or
/// destination, carrying 1, 2 and 3 beeps; voice speaks at the same points so the two stay in
/// step. How many of them a mode gets: driving all three, cycling the last two, running and
/// walking only the last (nearest) one.
struct AudioCuePlan {
    static let allPoints: [Int] = [100, 50, 15]

    /// The announcement points active for this plan, farthest first.
    var distances: [Int]

    init(mode: TravelMode) {
        switch mode {
        case .drive: distances = Self.allPoints
        case .cycle: distances = Array(Self.allPoints.suffix(2))
        case .walk, .run: distances = Array(Self.allPoints.suffix(1))
        }
    }

    /// Beeps for a point: 100m → 1, 50m → 2, 15m → 3 (so a mode's tones always mean the same
    /// distance, whichever subset it uses).
    static func toneCount(forDistance distance: Int) -> Int {
        (allPoints.firstIndex(of: distance) ?? 0) + 1
    }

    /// The point to announce now, if one has just been crossed and not yet announced on this
    /// leg. Every point at or beyond the current distance is marked fired, so a GPS jump past
    /// two of them announces only the nearest one instead of replaying both.
    func crossedPoint(currentDistance: Double, fired: inout Set<Int>) -> Int? {
        var nearest: Int?
        for d in distances where currentDistance <= Double(d) && !fired.contains(d) {
            fired.insert(d)
            if nearest == nil || d < nearest! { nearest = d }
        }
        return nearest
    }
}

/// The three separately-spoken parts of a voice instruction.
struct VoiceCue: Equatable {
    var direction: String
    var turnType: String
    var distance: String
    var utterances: [String] { [direction, turnType, distance] }
}

/// All the wording in one editable place.
struct VoiceScript {
    var turnPhrases: [TurnSeverity: (left: String, right: String)] = [
        .slight: ("Bear left", "Bear right"),
        .normal: ("Turn left", "Turn right"),
        .sharp: ("Turn sharp left", "Turn sharp right"),
        .uTurn: ("Make a U-turn", "Make a U-turn"),
    ]
    var straight = "Continue straight"
    var arrive = "Arrive"
    var turnTypePhrases: [ManeuverKind: String] = [
        .turn: "at the junction",
        .roundabout: "at the roundabout",
        .fork: "at the fork",
        .merge: "at the merge",
        .ramp: "at the ramp",
        .keepGoing: "ahead",
        .depart: "ahead",
        .arrive: "at your destination",
    ]

    func cue(for card: GuidanceCard, distanceMetres: Double, imperial: Bool) -> VoiceCue {
        let direction: String
        if card.kind == .arrive {
            direction = arrive
        } else if card.isRoundabout, let exit = card.exitNumber {
            direction = "Take the \(Self.ordinal(exit)) exit"
        } else {
            switch card.turn.side {
            case .straight: direction = straight
            case .left: direction = turnPhrases[card.turn.severity]?.left ?? "Turn left"
            case .right: direction = turnPhrases[card.turn.severity]?.right ?? "Turn right"
            }
        }
        return VoiceCue(
            direction: direction,
            turnType: turnTypePhrases[card.kind] ?? "ahead",
            distance: "in \(Self.spokenDistance(distanceMetres, imperial: imperial))"
        )
    }

    static func spokenDistance(_ metres: Double, imperial: Bool) -> String {
        if imperial {
            let feet = Int((metres * 3.28084 / 10).rounded()) * 10
            return "\(max(10, feet)) feet"
        }
        return "\(max(5, Int((metres / 5).rounded()) * 5)) metres"
    }

    private static func ordinal(_ n: Int) -> String {
        switch n {
        case 1: return "1st"
        case 2: return "2nd"
        case 3: return "3rd"
        default: return "\(n)th"
        }
    }
}

@MainActor
final class AudioManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var style: AudioGuidanceStyle = .off
    /// Which points announce — set from the selected travel mode when audio is wired up.
    var plan = AudioCuePlan(mode: .walk)
    var script = VoiceScript()
    /// Off by default: voice plays over music at full music volume. iOS offers no control over
    /// how far other apps are ducked (its own ducking is much deeper than a couple of percent),
    /// so turning this on is all-or-nothing.
    var duckMusicDuringVoice = false

    private let synthesizer = AVSpeechSynthesizer()
    private var tonePlayers: [Int: AVAudioPlayer] = [:]
    private var sessionActive = false
    /// Bumped by every cue; a delayed "give the audio session back" only runs if no newer cue started.
    private var cueGeneration = 0
    private var observers: [NSObjectProtocol] = []

    override init() {
        super.init()
        synthesizer.delegate = self
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            Task { @MainActor in self?.handleInterruption(typeRaw: raw) }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            Task { @MainActor in self?.handleRouteChange(reasonRaw: raw) }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.tonePlayers = [:]; self?.sessionActive = false }
        })
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    /// Plays a tone cue: `count` soft beeps (1...3) panned to `pan`. Ignores the style so a
    /// settings screen can preview it; callers gate on `style` themselves.
    ///
    /// Uses one pre-rendered AVAudioPlayer per beep count and keeps the audio session active for
    /// the whole trip. (Starting and stopping an AVAudioEngine and re-activating the session for
    /// every cue was the biggest CPU cost measured in guidance: ~0.6 points over two minutes.)
    func playTones(count: Int, pan: AudioPan) {
        cueGeneration += 1
        prepareForGuidance()
        guard let player = tonePlayers[max(1, min(3, count))] else { return }
        player.pan = pan.rawValue
        player.currentTime = 0
        player.play()
    }

    /// Builds the tone players and activates the (mixing) session once, ahead of the first cue.
    /// Safe to call repeatedly.
    func prepareForGuidance() {
        if !sessionActive { activateSession(duck: false); sessionActive = true }
        guard tonePlayers.isEmpty else { return }
        for n in 1...3 {
            guard let buffer = Self.toneBuffer(count: n), let player = try? AVAudioPlayer(data: Self.wavData(from: buffer)) else { continue }
            player.prepareToPlay()
            tonePlayers[n] = player
        }
    }

    /// Ends the trip's audio: stops anything playing, drops the players and hands the session back.
    func finishGuidance() {
        cueGeneration += 1
        synthesizer.stopSpeaking(at: .immediate)
        for player in tonePlayers.values { player.stop() }
        tonePlayers = [:]
        if sessionActive { deactivateSession(); sessionActive = false }
    }

    /// Speaks the three parts as separate utterances, in order.
    func speak(_ cue: VoiceCue) {
        cueGeneration += 1
        if duckMusicDuringVoice || !sessionActive { activateSession(duck: duckMusicDuringVoice); sessionActive = true }
        synthesizer.stopSpeaking(at: .word)
        for text in cue.utterances {
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier.replacingOccurrences(of: "_", with: "-"))
            utterance.postUtteranceDelay = 0.1
            synthesizer.speak(utterance)
        }
    }

    func stop() { finishGuidance() }

    // MARK: Interruptions and routes

    /// A phone call (or Siri, an alarm) takes the audio session: drop whatever is mid-cue. The
    /// next cue re-activates the session itself, so nothing needs resuming.
    private func handleInterruption(typeRaw: UInt?) {
        guard let typeRaw, AVAudioSession.InterruptionType(rawValue: typeRaw) == .began else { return }
        synthesizer.stopSpeaking(at: .immediate)
        for player in tonePlayers.values { player.stop() }
        sessionActive = false
    }

    /// Headphones or a Bluetooth speaker going away must not suddenly play a cue out loud.
    private func handleRouteChange(reasonRaw: UInt?) {
        guard let reasonRaw, AVAudioSession.RouteChangeReason(rawValue: reasonRaw) == .oldDeviceUnavailable else { return }
        synthesizer.stopSpeaking(at: .immediate)
        for player in tonePlayers.values { player.stop() }
    }

    // MARK: Tone synthesis

    nonisolated static let toneFrequency: Double = 740
    nonisolated static let toneDuration: Double = 0.14
    nonisolated static let toneGap: Double = 0.1
    /// Soft: well under full scale so it sits quietly on top of music.
    nonisolated static let toneAmplitude: Double = 0.3
    nonisolated static let sampleRate: Double = 44_100

    /// Mono on purpose: a mono source is what lets the mixer pan it fully to one side.
    nonisolated static func toneBuffer(count: Int) -> AVAudioPCMBuffer? {
        let beeps = max(1, min(3, count))
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return nil }
        let beepFrames = Int(toneDuration * sampleRate)
        let gapFrames = Int(toneGap * sampleRate)
        let total = beeps * beepFrames + (beeps - 1) * gapFrames
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(total)),
              let data = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(total)
        for i in 0..<total { data[i] = 0 }
        for b in 0..<beeps {
            let start = b * (beepFrames + gapFrames)
            for i in 0..<beepFrames {
                let t = Double(i) / sampleRate
                // Short fade in/out so it doesn't click.
                let envelope = min(1, t / 0.015, (toneDuration - t) / 0.03)
                data[start + i] = Float(sin(2 * .pi * toneFrequency * t) * toneAmplitude * envelope)
            }
        }
        return buffer
    }

    /// 16-bit mono WAV of a tone buffer, so it can be played by a plain AVAudioPlayer.
    nonisolated static func wavData(from buffer: AVAudioPCMBuffer) -> Data {
        let frames = Int(buffer.frameLength)
        var data = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; data.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; data.append(Data(bytes: &x, count: 2)) }
        data.append("RIFF".data(using: .ascii)!); u32(UInt32(36 + frames * 2))
        data.append("WAVEfmt ".data(using: .ascii)!); u32(16); u16(1); u16(1)
        u32(UInt32(sampleRate)); u32(UInt32(sampleRate) * 2); u16(2); u16(16)
        data.append("data".data(using: .ascii)!); u32(UInt32(frames * 2))
        if let samples = buffer.floatChannelData?[0] {
            for i in 0..<frames { u16(UInt16(bitPattern: Int16(max(-1, min(1, samples[i])) * 32767))) }
        }
        return data
    }

    // MARK: Session

    /// `.mixWithOthers` is what keeps music/podcasts playing untouched: no pause, no resume.
    /// `.playback` also sounds with the silent switch on and the screen locked.
    func activateSession(duck: Bool) {
        let session = AVAudioSession.sharedInstance()
        var options: AVAudioSession.CategoryOptions = [.mixWithOthers]
        if duck { options.insert(.duckOthers) }
        try? session.setCategory(.playback, mode: .default, options: options)
        try? session.setActive(true)
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self, !self.synthesizer.isSpeaking, self.duckMusicDuringVoice else { return }
            // Ducked audio only returns to full volume once the session is released.
            self.deactivateSession(); self.sessionActive = false
        }
    }
}
