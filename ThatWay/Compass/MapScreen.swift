//
//  MapScreen.swift
//  ThatWay
//
//  A real MapKit map: real tiles for the area around the user, their real location (via
//  MapKit's own location handling), friends placed as real nearby coordinates, real
//  points of interest, and — once a destination is selected — the actual fetched route
//  traced live, trimmed back as the traveller moves and refreshed if they drift off it.
//

import SwiftUI
import MapKit

struct MapScreen: View {
    @EnvironmentObject var app: AppModel
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var nearbyPlaces: [MKMapItem] = []
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
                .padding(.bottom, 6)

            Map(position: $cameraPosition, selection: $selection) {
                UserAnnotation()

                ForEach(Friend.all) { f in
                    Annotation(f.name, coordinate: app.coordinate(for: f)) {
                        friendMarker(f, theme: theme)
                    }
                }

                // The real destination and route line appear as soon as a place or friend
                // is selected — a preview before guidance even starts, exactly like the
                // route line a real turn-by-turn app shows you before you hit "Go".
                if let destinationCoordinate = app.destinationCoordinate {
                    Marker(app.dest, coordinate: destinationCoordinate)
                        .tint(.red)
                }
                if displayedPolyline.count > 1 {
                    MapPolyline(coordinates: displayedPolyline)
                        .stroke(app.routeColor, lineWidth: 6)
                }

                // Tagged so tapping one of our own real nearby-place markers reports back
                // through `selection` exactly like tapping a built-in Apple Maps POI does.
                ForEach(nearbyPlaces, id: \.self) { item in
                    Marker(item: item).tint(.orange).tag(item)
                }
            }
            .mapStyle(currentMapStyle)
            .mapControls {
                MapUserLocationButton()
                MapPitchToggle()
                MapCompass()
            }
            .overlay(alignment: .bottomTrailing) {
                mapActionCluster(theme: theme)
                    .padding(12)
            }
            .clipShape(RoundedRectangle(cornerRadius: 26))
            .overlay(RoundedRectangle(cornerRadius: 26).stroke(theme.ink.opacity(0.1)))
            .padding(.horizontal, 16)
            .padding(.bottom, 90)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 8)
        .background(theme.screen)
        .onAppear {
            centerOnUserIfNeeded()
            Task {
                nearbyPlaces = await PlaceSearch.nearbyPlaces(around: app.currentPosition, radius: 1500)
            }
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

    /// A tap on either one of our own real nearby-place markers or a built-in Apple Maps
    /// point of interest — either way, a real named place with a real coordinate, so it
    /// gets routed through the same "autofill + ask to route" flow.
    private func handleSelection(_ newValue: MapSelection<MKMapItem>?) {
        guard let newValue else { return }
        if let feature = newValue.feature, let name = feature.title {
            app.selectMapFeature(name: name, coordinate: feature.coordinate)
        } else if let item = newValue.value {
            app.selectMapFeature(name: item.name ?? "Selected place", coordinate: item.placemark.coordinate)
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

    private var mapStyleLabel: String {
        switch mapStyleIndex {
        case 1: return "HYBRID"
        case 2: return "SATELLITE"
        default: return "STANDARD"
        }
    }

    /// A small custom cluster of map actions — 2D/3D perspective and map style — alongside
    /// MapKit's own built-in controls (recenter, native pitch toggle, compass).
    @ViewBuilder
    private func mapActionCluster(theme: AppTheme) -> some View {
        VStack(spacing: 10) {
            mapActionButton(icon: "cube", label: is3D ? "2D" : "3D", theme: theme, action: toggle3D)
            mapActionButton(icon: "globe.americas.fill", label: mapStyleLabel, theme: theme, action: cycleMapStyle)
        }
    }

    @ViewBuilder
    private func mapActionButton(icon: String, label: String, theme: AppTheme, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 15, weight: .semibold))
                Text(label).font(.nunito(8, .extraBold)).tracking(0.4)
            }
            .foregroundStyle(theme.ink)
            .frame(width: 50, height: 46)
            .background(RoundedRectangle(cornerRadius: 14).fill(theme.screen.opacity(0.92)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.borderColor))
            .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func friendMarker(_ f: Friend, theme: AppTheme) -> some View {
        VStack(spacing: 4) {
            Circle().fill(f.color).frame(width: 34, height: 34)
                .overlay(Circle().stroke(.white, lineWidth: 2))
                .overlay(Text(f.initials).font(.nunito(12, .extraBold)).foregroundStyle(Color(hex: "241A14")))
                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
            Text(f.name)
                .font(.nunito(10, .semibold))
                .foregroundStyle(theme.ink)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(theme.screen.opacity(0.85), in: Capsule())
        }
    }
}
