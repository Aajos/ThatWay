//
//  HeadingBlender.swift
//  ThatWayCore
//
//  A wrist compass can't trust its magnetometer while the wearer is running (the arm swings, the
//  watch tilts, iOS's fusion lags), but GPS course is excellent once you're moving and useless when
//  you stand still. The blender uses GPS *course* above a speed threshold and the *magnetometer*
//  below it, with:
//    - hysteresis: enter GPS at `courseEnterSpeed`, leave it only below `magnetometerEnterSpeed`, so
//      speed hovering around one number can't make the needle flip between sources;
//    - a dwell time on top, so a one-sample speed spike can't switch the source either;
//    - a circular low-pass filter (exponential, time-constant based, shortest-arc) so the needle
//      is steady and never swings the long way round at the 359°/0° wraparound.
//  Foundation only; pure and unit-tested. Takes a monotonic clock value so tests control time.
//

import Foundation

public struct HeadingSample {
    /// Speed over ground in m/s; negative when the system couldn't measure one.
    public var speed: Double
    /// GPS direction of travel, degrees clockwise from true north; negative when invalid.
    public var course: Double
    /// Reported uncertainty of `course` in degrees; negative when unknown.
    public var courseAccuracy: Double
    /// Seconds since the fix that produced speed/course was taken.
    public var fixAge: TimeInterval
    /// Magnetometer heading, degrees clockwise from true north; nil when there's no valid reading.
    public var magnetometer: Double?
    /// Reported uncertainty of the magnetometer heading in degrees; negative when unknown.
    public var magnetometerAccuracy: Double
    /// Monotonic seconds (e.g. `ProcessInfo.systemUptime`).
    public var time: TimeInterval

    public init(speed: Double, course: Double, courseAccuracy: Double = -1, fixAge: TimeInterval = 0,
                magnetometer: Double?, magnetometerAccuracy: Double = -1, time: TimeInterval) {
        self.speed = speed; self.course = course; self.courseAccuracy = courseAccuracy; self.fixAge = fixAge
        self.magnetometer = magnetometer; self.magnetometerAccuracy = magnetometerAccuracy; self.time = time
    }
}

public struct HeadingOutput: Equatable {
    public enum Source: String, Codable { case gps, magnetometer, none }
    /// The filtered heading, 0..<360; nil until any source has produced a reading.
    public var heading: Double?
    public var source: Source
    /// The raw reading of the source in use, before filtering.
    public var raw: Double?
    /// True on the update where the source changed.
    public var switched: Bool
}

public struct HeadingBlender {
    public struct Config: Equatable {
        /// Switch to GPS course when speed reaches this (m/s)…
        public var courseEnterSpeed = 1.5
        /// …and back to the magnetometer only when it falls below this (m/s).
        public var magnetometerEnterSpeed = 0.8
        /// How long a switching condition must hold before the switch happens (seconds).
        public var dwell: TimeInterval = 1.0
        /// A course whose reported accuracy is worse than this (degrees) isn't used.
        public var maxCourseAccuracy = 35.0
        /// A fix older than this (seconds) isn't used.
        public var maxFixAge: TimeInterval = 3
        /// Low-pass time constants (seconds): smaller = snappier, larger = steadier.
        public var courseTimeConstant: TimeInterval = 0.5
        public var magnetometerTimeConstant: TimeInterval = 0.4
        /// A jump bigger than this (degrees) snaps instead of smoothing — a source switch or a flipped
        /// magnetometer shouldn't make the needle crawl across half the dial.
        public var snapAbove = 120.0
        public init() {}
    }

    public var config: Config
    public private(set) var source: HeadingOutput.Source = .none
    public private(set) var filtered: Double?
    private var lastTime: TimeInterval?
    private var pendingSince: TimeInterval?
    private var sourceSince: TimeInterval = 0

    public init(config: Config = Config()) { self.config = config }

    public mutating func reset() {
        source = .none; filtered = nil; lastTime = nil; pendingSince = nil; sourceSince = 0
    }

    private func courseUsable(_ s: HeadingSample) -> Bool {
        s.course >= 0 && s.course < 360 && s.speed >= 0 && s.fixAge <= config.maxFixAge
            && (s.courseAccuracy < 0 || s.courseAccuracy <= config.maxCourseAccuracy)
    }

    @discardableResult
    public mutating func update(_ s: HeadingSample) -> HeadingOutput {
        let usableCourse = courseUsable(s)
        let hasMag = s.magnetometer != nil
        var switched = false

        // What the speed says we *want* to be using.
        var wanted = source
        switch source {
        case .none:
            wanted = (usableCourse && s.speed >= config.courseEnterSpeed) ? .gps : (hasMag ? .magnetometer : (usableCourse ? .gps : .none))
        case .magnetometer:
            if usableCourse && s.speed >= config.courseEnterSpeed { wanted = .gps }
        case .gps:
            if !usableCourse { wanted = hasMag ? .magnetometer : .gps }
            else if s.speed < config.magnetometerEnterSpeed && hasMag { wanted = .magnetometer }
        }

        if wanted != source {
            // First choice, or the current source became unusable: switch at once. Otherwise the
            // condition has to hold for the dwell time.
            let urgent = source == .none || (source == .gps && !usableCourse) || (source == .magnetometer && !hasMag)
            if urgent || config.dwell <= 0 {
                source = wanted; sourceSince = s.time; pendingSince = nil; switched = true
            } else if let since = pendingSince {
                if s.time - since >= config.dwell { source = wanted; sourceSince = s.time; pendingSince = nil; switched = true }
            } else {
                pendingSince = s.time
            }
        } else {
            pendingSince = nil
        }

        // The raw reading of the source now in use.
        let raw: Double?
        switch source {
        case .gps: raw = usableCourse ? s.course : nil
        case .magnetometer: raw = s.magnetometer
        case .none: raw = nil
        }

        if let raw {
            if let current = filtered {
                let diff = AngleMath.signedDifference(raw, from: current)
                if abs(diff) > config.snapAbove {
                    filtered = AngleMath.normalized(raw)
                } else {
                    let dt = max(0, s.time - (lastTime ?? s.time))
                    let tau = source == .gps ? config.courseTimeConstant : config.magnetometerTimeConstant
                    let alpha = tau <= 0 ? 1 : 1 - exp(-dt / tau)
                    filtered = AngleMath.normalized(current + alpha * diff)
                }
            } else {
                filtered = AngleMath.normalized(raw)
            }
        }
        lastTime = s.time
        return HeadingOutput(heading: filtered, source: source, raw: raw, switched: switched)
    }
}
