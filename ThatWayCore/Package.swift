// swift-tools-version: 5.9
import PackageDescription

// ThatWayCore — the pure, platform-neutral heart of ThatWay: route models, bearing/distance maths, travel-mode tuning,
//   route progress and the compass heading blender. Foundation + CoreLocation only — no UIKit, no SwiftUI — so the iOS app and
//   the watchOS app compile exactly the same code, and `swift test` runs it on the Mac.
// ThatWayUI — the shared *look*: theme palette, glow/lift helpers, the Nunito font, and the compass needle art. SwiftUI only
//   (no UIKit), so it renders identically on iPhone and Apple Watch.
let package = Package(
    name: "ThatWayCore",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v14)],
    products: [
        .library(name: "ThatWayCore", targets: ["ThatWayCore"]),
        .library(name: "ThatWayUI", targets: ["ThatWayUI"]),
    ],
    targets: [
        .target(name: "ThatWayCore"),
        .target(name: "ThatWayUI", dependencies: ["ThatWayCore"], resources: [.copy("Resources/Nunito.ttf")]),
        .testTarget(name: "ThatWayCoreTests", dependencies: ["ThatWayCore"]),
    ]
)
