//
//  AppModel.swift
//  ThatWay
//
//  Simulated navigation state driving the Compass Nav concept screens.
//

import SwiftUI
import Combine

@MainActor
final class AppModel: ObservableObject {
    // Navigation
    @Published var screen: AppScreen = .compass
    @Published var storeTab: StoreTab = .themes
    @Published var mode: NavMode = .point
    @Published var skin: SkinID = .needle
    @Published var theme: ThemeID = .ember
    @Published var lastDark: ThemeID = .ember
    @Published var ownedSkins: Set<SkinID> = [.needle, .wheel, .clock]
    @Published var ownedAvatars: Set<AvatarID> = [.initials, .dot, .ring]
    @Published var avatar: AvatarID = .initials
    @Published var avatarSheet = false
    @Published var searchOpen = false
    @Published var dest = "Sunrise Bakery"
    @Published var destKind: DestKind = .place
    @Published var destColor: Color?

    // Simulation
    @Published var t = 0
    @Published var dist: Double = 1240
    @Published var stepIdx = 0
    @Published var stepDist: Double = 420
    @Published var speed: Double = 5

    // Profile
    @Published var vis: Visibility = .friends
    @Published var closeKm: Double = 8

    // Floating mode toggle
    @Published var togX: CGFloat = 244
    @Published var togY: CGFloat = 84
    @Published var dragging = false

    // Map
    @Published var mapX: CGFloat = 0
    @Published var mapY: CGFloat = 0
    @Published var mapZoom: CGFloat = 1
    @Published var mapRot: Double = 0
    @Published var mapTilt: Double = 0

    @Published var opts = NavOptions()

    private var timer: AnyCancellable?

    let tiltStrength: Double = 0.7
    static let togW: CGFloat = 132
    static let togH: CGFloat = 62
    static let exclusionRadius: CGFloat = 100
    static let cardExclusionRadius: CGFloat = 60

    init() {
        timer = Timer.publish(every: 0.09, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    func tick() {
        t += 1
        if mode == .point {
            dist -= 7
            if dist < 40 { dist = 1240 }
            speed = 4.6 + sin(Double(t) / 30) * 0.9
        } else {
            stepDist -= 9
            if stepDist <= 10 {
                stepIdx = (stepIdx + 1) % NavStep.all.count
                stepDist = NavStep.all[stepIdx].dist
            }
            speed = 52 + sin(Double(t) / 45) * 26
        }
    }

    // MARK: - Derived state

    var currentTheme: AppTheme { AppTheme.byId(theme) }
    var guiding: Bool { mode == .guidance }
    var step: NavStep { NavStep.all[stepIdx] }
    var nextStep: NavStep { NavStep.all[(stepIdx + 1) % NavStep.all.count] }
    var activeDist: Double { guiding ? stepDist : dist }
    var far: Double { max(0, min(1, activeDist / (guiding ? 500 : 1200))) }
    var sway: Double { sin(Double(t) / 11) * 9 }

    var needleDeg: Double {
        let p = 1 - far
        let sTurn: Double = step.dir == .left ? -1 : step.dir == .right ? 1 : 0
        let anticipate = p * p * (3 - 2 * p)
        let throughTurn = max(0, min(1, (p - 0.86) / 0.14))
        let threadRot = -sTurn * 58 * throughTurn * throughTurn
        return guiding ? sTurn * 58 * anticipate + threadRot + sway * 0.22 : sway
    }

    var threadRot: Double {
        let p = 1 - far
        let sTurn: Double = step.dir == .left ? -1 : step.dir == .right ? 1 : 0
        let throughTurn = max(0, min(1, (p - 0.86) / 0.14))
        return -sTurn * 58 * throughTurn * throughTurn
    }

    var dialScale: Double { guiding ? CompassGeometry.scaleGuide : CompassGeometry.scalePoint }
    var tiltDeg: Double { far * 54 * tiltStrength }
    var laneDeg: Double { guiding ? CompassGeometry.laneDeg(for: step.side) : 0 }

    var auto: String { speed < 7 ? "WALKING" : speed < 15 ? "RUNNING" : "DRIVING" }
    var activity: String { opts.activity == "Automatic" ? auto : opts.activity.uppercased() }
    var routeColor: Color { activity == "DRIVING" ? Color(hex: "3B82F6") : Color(hex: "2FCF9B") }
    var routeM: Double {
        (max(50, min(2000, 50 + ((speed - 40) / 80) * 1950)) / 10).rounded() * 10
    }

    var friendMode: Bool { destKind == .friend && destColor != nil }
    var accent: Color { friendMode ? (destColor ?? currentTheme.accent) : currentTheme.accent }

    /// The 2-3 tones the dial's glass rim gradient pulls from — the selected friend's
    /// colors when pointing at one, otherwise the theme's own accent pairing.
    var dialGlassColors: [Color] {
        friendMode ? (destColor ?? currentTheme.accent).dominantTrio
            : [currentTheme.accent, Color(hex: "34D6A5"), currentTheme.accent.hueShifted(24)]
    }

    var currentAvatar: AvatarOption { AvatarOption.byId(avatar) }
    var currentSkin: Skin { Skin.byId(skin) }

    func fmt(_ m: Double) -> String { CompassGeometry.fmt(m) }
    func aud(_ n: Double) -> String { CompassGeometry.aud(n) }

    // MARK: - Actions

    func flipMode() {
        if mode == .point {
            mode = .guidance
            stepIdx = 0
            stepDist = NavStep.all[0].dist
            speed = 52
        } else {
            mode = .point
            dist = 1240
            speed = 5
        }
    }

    func startGuidance() {
        mode = .guidance
        stepIdx = 0
        stepDist = NavStep.all[0].dist
        speed = 52
    }

    func endGuidance() {
        mode = .point
        dist = 1240
        speed = 5
    }

    func setTheme(_ id: ThemeID) {
        let th = AppTheme.byId(id)
        theme = id
        if !th.light { lastDark = id }
    }

    func toggleTheme() {
        setTheme(currentTheme.light ? lastDark : .paper)
    }

    func goToFriend(_ f: Friend) {
        dest = f.name
        destKind = .friend
        destColor = f.color
        mode = .point
        dist = 860
    }

    func pickPlace(_ name: String) {
        dest = name
        destKind = .place
        destColor = nil
        searchOpen = false
        mode = .point
        dist = 1240
    }

    func pickSkin(_ id: SkinID) {
        if ownedSkins.contains(id) {
            skin = id
            screen = .compass
        } else {
            ownedSkins.insert(id)
            skin = id
        }
    }

    func pickAvatar(_ id: AvatarID) {
        if ownedAvatars.contains(id) {
            avatar = id
        } else {
            ownedAvatars.insert(id)
            avatar = id
        }
    }

    func goDonate() {
        screen = .store
        storeTab = .donate
    }

    func selectTab(_ s: AppScreen) {
        screen = s
        searchOpen = false
        avatarSheet = false
    }

    /// Clamp the floating toggle inside the screen (20px edge padding) and, if it strays
    /// within 100px of the compass dial or 60px of the destination card, shove it sideways
    /// clear of whichever it's crowding.
    func placeToggle(_ x: CGFloat, _ y: CGFloat, in size: CGSize, dialCenter: CGPoint, cardFrame: CGRect?) -> CGPoint {
        let edgePadding: CGFloat = 20
        func clamp(_ px: CGFloat, _ py: CGFloat) -> CGPoint {
            CGPoint(
                x: max(edgePadding, min(size.width - Self.togW - edgePadding, px)),
                y: max(edgePadding, min(size.height - Self.togH - edgePadding, py))
            )
        }
        func pushHorizontally(_ p: CGPoint, awayFrom target: CGPoint, radius: CGFloat) -> CGPoint {
            let center = CGPoint(x: p.x + Self.togW / 2, y: p.y + Self.togH / 2)
            let dist = (pow(center.x - target.x, 2) + pow(center.y - target.y, 2)).squareRoot()
            guard dist < radius else { return p }
            let direction: CGFloat = center.x >= target.x ? 1 : -1
            let shift = (radius - dist) + 1
            return clamp(p.x + direction * shift, p.y)
        }

        var p = clamp(x, y)
        p = pushHorizontally(p, awayFrom: dialCenter, radius: Self.exclusionRadius)
        if let cardFrame {
            p = pushHorizontally(p, awayFrom: CGPoint(x: cardFrame.midX, y: cardFrame.midY), radius: Self.cardExclusionRadius)
        }
        return p
    }
}
