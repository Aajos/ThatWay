//
//  MapScreen.swift
//  ThatWay
//
//  A real MapKit map: real tiles for the area around the user, their real location, real
//  points of interest, and — once a destination is selected — the actual fetched route
//  traced live, trimmed back as the traveller moves and refreshed if they drift off it.
//

import SwiftUI
import MapKit

struct MapScreen: View {
    @EnvironmentObject var app: AppModel
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var hasCenteredOnce = false
    @State private var selection: MapSelection<MKMapItem>?
    @State private var is3D = false
    @State private var mapStyleIndex = 0

    /// The route line to actually draw: the full preview before guidance starts, but
    /// trimmed back to "what's left ahead" once guiding — so the line doesn't keep
    /// re-drawing ground the traveller has already covered.
    private var displayedPolyline: [CLLocationCoordinate2D] {
        if app.guiding, !app.routingManager.remainingPolyline.isEmpty {
            return app.routingManager.remainingPolyline
        }
        return app.routingManager.routePolyline
    }

    private var currentMapStyle: MapStyle {
        switch mapStyleIndex {
        case 1: return .hybrid
        case 2: return .imagery
        default: return .standard
        }
    }

    var body: some View {
        let theme = app.currentTheme

        VStack(spacing: 0) {
            Text("Map").font(.nunito(24, .black))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 2)
                .padding(.bottom, 0)

            Map(position: $cameraPosition, selection: $selection) {
                // The real destination and route line appear as soon as a place is
                // selected — a preview before guidance even starts, exactly like the
                // route line a real turn-by-turn app shows you before you hit "Go".
                if let destinationCoordinate = app.destinationCoordinate {
                    Marker(app.dest, coordinate: destinationCoordinate)
                        .tint(.red)
                }
                if displayedPolyline.count > 1 {
                    MapPolyline(coordinates: displayedPolyline)
                        .stroke(app.routeColor, lineWidth: 6)
                }

                // Fixed size (no zoom magnification), declared last so it's the topmost annotation and nearby business
                // markers and labels can never draw over the traveller's own position.
                Annotation("You", coordinate: app.currentPosition, anchor: .center) {
                    userLocationDot
                }
                .annotationTitles(.hidden)
            }
            .mapStyle(currentMapStyle)
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                    .mapControlVisibility(.visible)
            }
            .overlay(alignment: .topTrailing) {
                mapActionCluster(theme: theme)
                    // Clears MapKit's own native recenter + compass buttons stacked
                    // above (forced always-visible so this offset is never guessing at a
                    // gap), so the two 2D/3D and map-style buttons read as a continuation
                    // of that same corner group rather than a second, separate cluster.
                    .padding(.top, 116)
                    .padding(.trailing, 12)
            }
            .clipShape(RoundedRectangle(cornerRadius: 26))
            .overlay(RoundedRectangle(cornerRadius: 26).stroke(theme.ink.opacity(0.1)))
            // 5pt from the screen edges, the title above and the tab bar below (the tab icons
            // begin ~46pt above the bottom of the safe area).
            .padding(.horizontal, 5)
            .padding(.bottom, 46)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 8)
        .background(theme.screen)
        .onAppear {
            centerOnUserIfNeeded()
        }
        .onChange(of: app.hasRealLocation) { _, hasFix in
            if hasFix { centerOnUserIfNeeded() }
        }
        .onChange(of: selection) { _, newValue in
            handleSelection(newValue)
        }
    }

    /// Centres the camera on a real ~3km×3km block around the user the first time a
    /// position (real fix, or the mock fallback) is available — after that, panning is
    /// left entirely to the user; `MapUserLocationButton()` re-centres on request.
    private func centerOnUserIfNeeded() {
        guard !hasCenteredOnce else { return }
        hasCenteredOnce = true
        let region = MKCoordinateRegion(center: app.currentPosition, latitudinalMeters: 3000, longitudinalMeters: 3000)
        withAnimation { cameraPosition = .region(region) }
    }

    /// A tap on one of the map's own built-in Apple Maps points of interest — a real named
    /// place with a real coordinate, so it gets routed through the same "autofill + ask to
    /// route" flow.
    private func handleSelection(_ newValue: MapSelection<MKMapItem>?) {
        guard let newValue else { return }
        if let feature = newValue.feature, let name = feature.title {
            app.selectMapFeature(name: name, coordinate: feature.coordinate)
        }
        selection = nil
    }

    /// Tilts the camera between flat (2D) and a 60° perspective (3D) in place, keeping
    /// whatever centre/zoom/heading the user last set rather than resetting the view.
    private func toggle3D() {
        let camera = cameraPosition.camera
            ?? MapCamera(centerCoordinate: app.currentPosition, distance: 1200, heading: 0, pitch: 0)
        is3D.toggle()
        withAnimation(.easeInOut(duration: 0.4)) {
            cameraPosition = .camera(MapCamera(
                centerCoordinate: camera.centerCoordinate,
                distance: camera.distance,
                heading: camera.heading,
                pitch: is3D ? 60 : 0
            ))
        }
    }

    private func cycleMapStyle() {
        mapStyleIndex = (mapStyleIndex + 1) % 3
    }

    /// Temporary +/- zoom buttons for testing on a Mac, where pinch-to-zoom isn't available
    /// the way it is on a real device or the Simulator's own trackpad gestures.
    private func zoom(by factor: Double) {
        let camera = cameraPosition.camera
            ?? MapCamera(centerCoordinate: app.currentPosition, distance: 1200, heading: 0, pitch: is3D ? 60 : 0)
        withAnimation(.easeInOut(duration: 0.25)) {
            cameraPosition = .camera(MapCamera(
                centerCoordinate: camera.centerCoordinate,
                distance: max(200, min(20000, camera.distance * factor)),
                heading: camera.heading,
                pitch: camera.pitch
            ))
        }
    }

    private var userLocationDot: some View {
        ZStack {
            Circle().fill(Color.blue.opacity(0.18)).frame(width: 26, height: 26)
            Circle().fill(Color.blue)
                .frame(width: 12, height: 12)
                .overlay(Circle().stroke(.white, lineWidth: 2.5))
                .shadow(color: .black.opacity(0.35), radius: 2)
        }
    }

    private var mapStyleLabel: String {
        switch mapStyleIndex {
        case 1: return "HYBRID"
        case 2: return "SATELLITE"
        default: return "STANDARD"
        }
    }

    /// Our own map actions — 2D/3D perspective and map style — styled as the same
    /// translucent circles MapKit's native controls use, so stacked below the native
    /// recenter/compass pair they read as one continuous corner group instead of a second,
    /// visually distinct cluster.
    @ViewBuilder
    private func mapActionCluster(theme: AppTheme) -> some View {
        VStack(spacing: 10) {
            // Temporary Mac-testing convenience — pinch-to-zoom isn't available there.
            mapActionButton(icon: "plus.magnifyingglass", label: "IN", action: { zoom(by: 0.5) })
            mapActionButton(icon: "minus.magnifyingglass", label: "OUT", action: { zoom(by: 2) })
            mapActionButton(icon: "cube", label: is3D ? "2D" : "3D", action: toggle3D)
            mapActionButton(icon: "globe.americas.fill", label: mapStyleLabel, action: cycleMapStyle)
        }
    }

    @ViewBuilder
    private func mapActionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 15, weight: .semibold))
                Text(label).font(.nunito(8, .extraBold)).tracking(0.4)
            }
            .foregroundStyle(.primary)
            .frame(width: 44, height: 44)
            .background(Circle().fill(.ultraThinMaterial))
            .overlay(Circle().stroke(.white.opacity(0.15), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }

}
