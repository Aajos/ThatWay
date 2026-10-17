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

    private let session = NISession()
    private var peerConfiguration: NINearbyPeerConfiguration?

    /// What this phone's hardware can do. `deviceCapabilities` is false across the board in the simulator.
    nonisolated static func currentCapability() -> NearbyCapability {
        #if targetEnvironment(simulator)
        return .unsupported
        #else
        let capabilities = NISession.deviceCapabilities
        guard capabilities.supportsPreciseDistanceMeasurement else { return .unsupported }
        return capabilities.supportsDirectionMeasurement ? .uwbWithDirection : .uwbDistanceOnly
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
        let configuration = NINearbyPeerConfiguration(peerToken: token)
        peerConfiguration = configuration
        session.run(configuration)
        return true
    }

    func stop() {
        session.invalidate()
        peerConfiguration = nil
    }

    // MARK: NISessionDelegate

    nonisolated func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        guard let object = nearbyObjects.first, let distance = object.distance else { return }
        // `horizontalAngle` is radians, positive to the right of the phone's top edge: the arrow's rotation.
        let bearing = object.horizontalAngle.map { Double($0) * 180 / .pi }
        let meters = Double(distance)
        Task { @MainActor in self.onUpdate?(meters, bearing) }
    }

    nonisolated func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        // A timeout can recover on its own once the friend is back in range; the friend leaving cannot.
        if reason == .peerEnded { Task { @MainActor in self.onEnded?() } }
    }

    nonisolated func sessionWasSuspended(_ session: NISession) {}

    nonisolated func sessionSuspensionEnded(_ session: NISession) {
        Task { @MainActor in
            if let configuration = self.peerConfiguration { self.session.run(configuration) }
        }
    }

    nonisolated func session(_ session: NISession, didInvalidateWith error: Error) {
        Task { @MainActor in self.onEnded?() }
    }
}
