//
//  HapticPlayer.swift
//  ThatWayWatch
//
//  Plays a platform-neutral `HapticPattern` using only the WKHapticType presets watchOS gives apps.
//

import WatchKit
import ThatWayCore

enum HapticPlayer {
    static func wk(_ kind: HapticKind) -> WKHapticType {
        switch kind {
        case .notification: return .notification
        case .directionUp: return .directionUp
        case .directionDown: return .directionDown
        case .success: return .success
        case .failure: return .failure
        case .retry: return .retry
        case .start: return .start
        case .stop: return .stop
        case .click: return .click
        }
    }

    @MainActor
    static func play(_ pattern: HapticPattern) {
        Task { @MainActor in
            for beat in pattern.beats {
                WKInterfaceDevice.current().play(wk(beat.kind))
                if beat.gapAfter > 0 { try? await Task.sleep(for: .seconds(beat.gapAfter)) }
            }
        }
    }
}
