//
//  NearbySession.swift
//  ThatWay
//
//  The real Nearby Interaction session behind `ProximitySession`: one `NISession`, this phone's discovery token, and a
//  peer configuration once the friend's token arrives. Needs a phone with the U1/U2 chip; the simulator and the
//  iPhone SE report `.unsupported` and never reach this code.
//

import Foundation
import NearbyInteraction
import ThatWayCore

@MainActor
final class NearbySession: NSObject, ProximitySession, NISessionDelegate {
    var onUpdate: ((Double, Double?) -> Void)?
    var onEnded: (() -> Void)?
    var onCoaching: ((String?) -> Void)?

    private let session = NISession()
    private var peerConfiguration: NINearbyPeerConfiguration?
    private var peerToken: NIDiscoveryToken?
    private var cameraAssistance = false

    /// iPhone 14 and later only give a direction with camera assistance: ARKit tracks exactly how the phone moves, and the
    /// changing UWB distances over that movement locate the friend. (The camera does not look for the person.)
    nonisolated static var supportsCameraAssistance: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return NISession.deviceCapabilities.supportsCameraAssistance
        #endif
    }

    /// Whether this phone gives a direction from the radio alone (iPhone 11 to 13).
    nonisolated static var directionWithoutCamera: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return NISession.deviceCapabilities.supportsDirectionMeasurement
        #endif
    }

    /// What this phone's hardware can do. `deviceCapabilities` is false across the board in the simulator.
    nonisolated static func currentCapability() -> NearbyCapability {
        #if targetEnvironment(simulator)
        return .unsupported
        #else
        let capabilities = NISession.deviceCapabilities
        guard capabilities.supportsPreciseDistanceMeasurement else { return .unsupported }
        return capabilities.supportsDirectionMeasurement || capabilities.supportsCameraAssistance ? .uwbWithDirection : .uwbDistanceOnly
        #endif
    }

    override init() {
        super.init()
        session.delegate = self
    }

    func localToken() -> String? {
        guard let token = session.discoveryToken,
              let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) else { return nil }
        return data.base64EncodedString()
    }

    @discardableResult
    func run(peerToken: String) -> Bool {
        guard let data = Data(base64Encoded: peerToken),
              let token = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: data) else { return false }
        self.peerToken = token
        start()
        return true
    }

    /// Switches camera assistance on or off, re-running the session with the same friend.
    func setCameraAssistance(_ on: Bool) {
        guard on != cameraAssistance else { return }
        cameraAssistance = on && Self.supportsCameraAssistance
        if peerToken != nil { start() }
        if !cameraAssistance { onCoaching?(nil) }
    }

    private func start() {
        guard let peerToken else { return }
        let configuration = NINearbyPeerConfiguration(peerToken: peerToken)
        if cameraAssistance { configuration.isCameraAssistanceEnabled = true }
        peerConfiguration = configuration
        session.run(configuration)
    }

    func stop() {
        session.invalidate()
        peerConfiguration = nil
        peerToken = nil
    }

    // MARK: NISessionDelegate

    nonisolated func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        guard let object = nearbyObjects.first, let distance = object.distance else { return }
        let bearing = Self.arrowAngle(direction: object.direction.map { ($0.x, $0.y, $0.z) }, horizontalAngle: object.horizontalAngle)
        let meters = Double(distance)
        Task { @MainActor in self.onUpdate?(meters, bearing) }
    }

    /// The arrow's rotation, in degrees clockwise from the top of the screen, from what Nearby Interaction reports.
    /// `direction` is a unit vector in the phone's frame: x to the right, y towards the top edge, z out of the screen towards the
    /// user. Held upright (screen facing you, back camera at the friend), "ahead" is -z; held flat (screen up), "ahead" is +y.
    /// Whichever of the two the vector leans on most decides which plane the angle is measured in.
    nonisolated static func arrowAngle(direction: (x: Float, y: Float, z: Float)?, horizontalAngle: Float?) -> Double? {
        if let d = direction {
            let ahead = abs(d.z) > abs(d.y) ? -d.z : d.y
            guard abs(d.x) + abs(ahead) > 0.05 else { return nil }          // straight above or below: no useful bearing
            return Double(atan2(d.x, ahead)) * 180 / .pi
        }
        return horizontalAngle.map { Double($0) * 180 / .pi }
    }

    nonisolated func session(_ session: NISession, didUpdateAlgorithmConvergence convergence: NIAlgorithmConvergence, for object: NINearbyObject?) {
        let text: String?
        switch convergence.status {
        case .converged:
            text = nil
        case .notConverged(let reasons):
            let all = reasons.map { String(describing: $0).lowercased() }.joined(separator: " ")
            if all.contains("light") { text = "Too dark for the camera. Find some light." }
            else if all.contains("vertical") { text = "Tilt your phone up and down a little." }
            else if all.contains("horizontal") || all.contains("sweep") { text = "Move your phone slowly from side to side." }
            else { text = "Hold your phone up and move it slowly." }
        default:
            text = "Hold your phone up and move it slowly."
        }
        Task { @MainActor in self.onCoaching?(text) }
    }

    nonisolated func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        // A timeout can recover on its own once the friend is back in range; the friend leaving cannot.
        if reason == .peerEnded { Task { @MainActor in self.onEnded?() } }
    }

    nonisolated func sessionWasSuspended(_ session: NISession) {}

    nonisolated func sessionSuspensionEnded(_ session: NISession) {
        Task { @MainActor in self.start() }
    }

    nonisolated func session(_ session: NISession, didInvalidateWith error: Error) {
        Task { @MainActor in self.onEnded?() }
    }
}
