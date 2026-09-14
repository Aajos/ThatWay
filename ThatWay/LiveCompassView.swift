//
//  LiveCompassView.swift
//  ThatWay
//
//  A real-GPS compass screen driven by LocationManager/CompassManager/RouteManager.
//  Not currently wired into the app's entry point (see ContentView) while the
//  design-mockup CompassScreen is the primary screen, but kept ready to swap in
//  or merge with once the real-data integration work resumes.
//

import SwiftUI
import CoreLocation
import MapKit

struct LiveCompassView: View {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var routeManager = RouteManager()

    @State private var destinationCoordinate: CLLocationCoordinate2D?
    @State private var destinationName: String = ""
    @State private var addressText: String = ""
    @State private var isGeocoding = false
    @State private var searchError: String?
    @State private var isGuiding = false

    private let accent = Color(red: 1, green: 0.353, blue: 0.212) // #FF5A36

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 22) {
                    header

                    CompassDialView(
                        heading: locationManager.heading,
                        relativeBearing: relativeBearing,
                        hasDestination: destinationCoordinate != nil,
                        accent: accent
                    )
                    .frame(width: 260, height: 260)
                    .padding(.top, 8)

                    readout

                    if isGuiding {
                        guidancePanel
                    } else {
                        destinationSearch
                    }

                    if let message = locationManager.errorMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding()
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { locationManager.requestPermission() }
        .onChange(of: locationManager.location?.timestamp) { _, _ in
            guard let location = locationManager.location, isGuiding else { return }
            routeManager.updateProgress(userLocation: location)
        }
    }

    // MARK: - Derived values

    private var bearingToDestination: CLLocationDirection? {
        guard let origin = locationManager.coordinate, let destination = destinationCoordinate else { return nil }
        return CompassManager.bearing(from: origin, to: destination)
    }

    private var relativeBearing: Double {
        guard let bearing = bearingToDestination else { return 0 }
        return CompassManager.relativeBearing(heading: locationManager.heading, bearing: bearing)
    }

    private var distanceToDestination: CLLocationDistance? {
        guard let origin = locationManager.coordinate, let destination = destinationCoordinate else { return nil }
        return CompassManager.distance(from: origin, to: destination)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 4) {
            Text("ThatWay").font(.system(size: 28, weight: .heavy))
            Text(statusText)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private var statusText: String {
        switch locationManager.authorizationStatus {
        case .notDetermined: return "Waiting for location permission…"
        case .denied, .restricted: return "Location access denied — enable it in Settings"
        default:
            guard locationManager.coordinate != nil else { return "Finding your location…" }
            return locationManager.hasReliableHeading ? "Heading \(Int(locationManager.heading))° \(CompassManager.compassPoint(for: locationManager.heading))" : "Move your phone to calibrate the compass"
        }
    }

    private var readout: some View {
        HStack(spacing: 28) {
            VStack(spacing: 2) {
                Text(distanceToDestination.map { CompassManager.formattedDistance($0) } ?? "—")
                    .font(.system(size: 30, weight: .black))
                Text("DISTANCE").font(.caption2.weight(.bold)).foregroundStyle(.white.opacity(0.5))
            }
            if let bearing = bearingToDestination {
                VStack(spacing: 2) {
                    Text("\(Int(bearing))° \(CompassManager.compassPoint(for: bearing))")
                        .font(.system(size: 30, weight: .black))
                    Text("BEARING").font(.caption2.weight(.bold)).foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .foregroundStyle(.white)
    }

    private var destinationSearch: some View {
        VStack(spacing: 12) {
            HStack {
                TextField("Search for a destination", text: $addressText)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(Capsule().fill(.white.opacity(0.08)))
                    .foregroundStyle(.white)
                    .submitLabel(.search)
                    .onSubmit { geocode() }

                Button(action: geocode) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(accent))
                }
                .disabled(addressText.trimmingCharacters(in: .whitespaces).isEmpty || isGeocoding)
            }

            if let searchError {
                Text(searchError).font(.footnote).foregroundStyle(.red)
            }

            if destinationCoordinate != nil {
                VStack(spacing: 10) {
                    Text(destinationName)
                        .font(.headline)
                        .foregroundStyle(.white)

                    Button {
                        startGuidance()
                    } label: {
                        Text(routeManager.isCalculating ? "Calculating route…" : "Start Guidance")
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(RoundedRectangle(cornerRadius: 16).fill(accent))
                    }
                    .disabled(locationManager.coordinate == nil || routeManager.isCalculating)
                }
                .padding(.top, 4)
            }
        }
    }

    private var guidancePanel: some View {
        VStack(spacing: 14) {
            if let route = routeManager.route {
                Text("\(CompassManager.formattedDistance(route.distance)) · \(formattedDuration(route.expectedTravelTime))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }

            if let step = routeManager.currentStep {
                VStack(alignment: .leading, spacing: 6) {
                    Text(step.instructions)
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(.white)
                    Text(CompassManager.formattedDistance(step.distance))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(accent)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 18).fill(.white.opacity(0.08)))

                if let next = routeManager.nextStep {
                    HStack(spacing: 8) {
                        Text("THEN").font(.caption2.weight(.heavy)).foregroundStyle(.white.opacity(0.5))
                        Text(next.instructions)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if routeManager.isFinished {
                Text("You've arrived.").font(.headline).foregroundStyle(.white)
            }

            if let error = routeManager.errorMessage {
                Text(error).font(.footnote).foregroundStyle(.red)
            }

            Button {
                endGuidance()
            } label: {
                Text("END")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.25)))
            }
        }
    }

    // MARK: - Actions

    private func geocode() {
        let query = addressText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        isGeocoding = true
        searchError = nil
        Task {
            defer { isGeocoding = false }
            do {
                let placemarks = try await CLGeocoder().geocodeAddressString(query)
                guard let coordinate = placemarks.first?.location?.coordinate else {
                    searchError = "Couldn't find that place."
                    return
                }
                destinationCoordinate = coordinate
                destinationName = placemarks.first?.name ?? query
            } catch {
                searchError = error.localizedDescription
            }
        }
    }

    private func startGuidance() {
        guard let origin = locationManager.coordinate, let destination = destinationCoordinate else { return }
        Task {
            await routeManager.calculateRoute(from: origin, to: destination)
            if routeManager.route != nil { isGuiding = true }
        }
    }

    private func endGuidance() {
        isGuiding = false
        routeManager.clear()
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes >= 60 { return "\(minutes / 60) h \(minutes % 60) min" }
        return "\(minutes) min"
    }
}

/// A real compass rose that stays north-aligned as the device turns, with a
/// needle that points at `relativeBearing` — the on-screen direction of the
/// destination relative to wherever the phone is currently facing.
private struct CompassDialView: View {
    let heading: CLLocationDirection
    let relativeBearing: Double
    let hasDestination: Bool
    let accent: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color(white: 0.18), Color(white: 0.06)], center: .init(x: 0.5, y: 0.3), startRadius: 0, endRadius: 160))
                .overlay(Circle().stroke(.white.opacity(0.18)))

            CompassTicks()
                .stroke(.white.opacity(0.7), lineWidth: 1.4)
                .padding(18)
                .rotationEffect(.degrees(-heading))

            CardinalLabels()
                .rotationEffect(.degrees(-heading))

            if hasDestination {
                NeedleShape()
                    .fill(accent)
                    .frame(width: 14, height: 100)
                    .shadow(color: accent.opacity(0.7), radius: 8)
                    .rotationEffect(.degrees(relativeBearing))
            }

            Circle().fill(.white).frame(width: 8, height: 8)

            // Fixed marker at the top of the screen — always "the way the phone is pointing."
            Triangle()
                .fill(.white.opacity(0.85))
                .frame(width: 12, height: 10)
                .offset(y: -128)
        }
        .animation(.easeOut(duration: 0.2), value: heading)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: relativeBearing)
    }
}

private struct CompassTicks: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        for i in 0..<72 {
            let major = i % 18 == 0
            let minor = i % 9 == 0
            let angle = Double(i) / 72 * 2 * .pi - .pi / 2
            let length: CGFloat = major ? 16 : minor ? 10 : 5
            let outer = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            let inner = CGPoint(x: center.x + cos(angle) * (radius - length), y: center.y + sin(angle) * (radius - length))
            path.move(to: outer)
            path.addLine(to: inner)
        }
        return path
    }
}

private struct CardinalLabels: View {
    var body: some View {
        GeometryReader { geo in
            let radius = min(geo.size.width, geo.size.height) / 2 - 30
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            ForEach(Array(["N", "E", "S", "W"].enumerated()), id: \.offset) { index, label in
                let angle = Double(index) / 4 * 2 * .pi - .pi / 2
                Text(label)
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(label == "N" ? Color(red: 1, green: 0.353, blue: 0.212) : .white.opacity(0.7))
                    .position(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            }
        }
    }
}

private struct NeedleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.midY + 14))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

#Preview {
    LiveCompassView()
}
