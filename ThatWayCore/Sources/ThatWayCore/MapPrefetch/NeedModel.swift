//
//  NeedModel.swift
//  ThatWayCore · MapPrefetch
//
//  "Which map will this person want, where, at what detail, and by when?" answered as a field over tiles.
//
//  The idea is one rule that does the work of many thresholds: detail falls off with distance from where the person is going.
//  A source (the route, a stop, an attraction, the person themself) has a base radius at its finest zoom, and each coarser zoom
//  reaches twice as far:
//
//        radius(z) = baseRadius × 2^(maxZoom − z)
//
//  Tiles double in width each zoom out, so every level costs about half the tiles of the one below it, and the whole pyramid
//  costs about twice its finest level. Street detail stays near the path, and the wider region is there as context, cheaply.
//
//  Everything is a probability and a deadline: p (0...1) is how likely the tile is wanted, `eta` is how many seconds until the
//  person could need it. The planner spends bytes on high p and early eta first.
//

import CoreLocation

public struct NeedSource {
    public enum Kind: String, Codable, Sendable {
        case route          // the planned route
        case alternative    // another route the person might take (multi-routing)
        case ahead          // no route: where they are heading, dead-reckoned from heading and speed
        case position       // around where they are right now
        case stop           // the destination or a waypoint, where they will walk around
        case poi            // an attraction they might detour to
    }

    public enum Geometry {
        /// A point and when the person could be there (seconds from now).
        case point(CLLocationCoordinate2D, eta: TimeInterval)
        /// A path with the seconds-from-now at each vertex (same count as the vertices).
        case path([CLLocationCoordinate2D], etas: [TimeInterval])
    }

    public var kind: Kind
    /// How likely this source is to be real or taken, 0...1 (an alternative route might be 0.3).
    public var weight: Double
    public var geometry: Geometry
    /// Radius in metres at `maxZoom`; coarser zooms reach 2× further per level.
    public var baseRadius: Double
    public var maxZoom: Int

    public init(kind: Kind, weight: Double, geometry: Geometry, baseRadius: Double, maxZoom: Int) {
        self.kind = kind; self.weight = max(0, min(1, weight)); self.geometry = geometry; self.baseRadius = baseRadius; self.maxZoom = maxZoom
    }

    public func radius(atZoom z: Int) -> Double { baseRadius * pow(2, Double(maxZoom - z)) }
}

/// What the model says about one tile.
public struct NeedHit {
    public var distance: Double
    public var eta: TimeInterval
    /// Probability the tile is wanted: the source's weight times a falloff from 1 (close) to 0.25 (at the edge of its reach).
    public var p: Double
    public var kind: NeedSource.Kind
}

public enum NeedModel {
    /// 1 inside half the radius, easing to 0.25 at the radius.
    static func falloff(_ u: Double) -> Double {
        if u <= 0.5 { return 1 }
        if u <= 1 { return 1 - (u - 0.5) / 0.5 * 0.75 }
        if u <= 2 { return 0.25 * (1 - (u - 1)) }
        return 0
    }

    /// Every tile at `zoom` that `source` reaches, with the soonest it could be needed and how likely it is wanted.
    public static func candidates(of source: NeedSource, zoom: Int, horizon: TimeInterval?) -> [TileID: NeedHit] {
        guard zoom <= source.maxZoom else { return [:] }
        let radius = source.radius(atZoom: zoom)
        var hits: [TileID: NeedHit] = [:]

        func add(point: CLLocationCoordinate2D, eta: TimeInterval) {
            if let horizon, eta > horizon { return }
            for (tile, d) in TileMath.tiles(near: point, radius: radius, zoom: zoom) {
                let p = source.weight * falloff(d / radius)
                if var existing = hits[tile] {
                    if d < existing.distance { existing.distance = d }
                    if eta < existing.eta { existing.eta = eta }
                    existing.p = max(existing.p, p)
                    hits[tile] = existing
                } else {
                    hits[tile] = NeedHit(distance: d, eta: eta, p: p, kind: source.kind)
                }
            }
        }

        switch source.geometry {
        case .point(let c, let eta):
            add(point: c, eta: eta)
        case .path(let vertices, let etas):
            guard !vertices.isEmpty else { break }
            let step = max(15, min(TileMath.sizeMeters(zoom: zoom, latitude: vertices[0].latitude) / 2, radius / 2))
            add(point: vertices[0], eta: etas.first ?? 0)
            var sinceLast = 0.0                       // ground covered since the last sample
            for i in 1..<max(1, vertices.count) {
                let a = vertices[i - 1], b = vertices[i]
                let length = TileMath.distance(a, b)
                let ea = etas.indices.contains(i - 1) ? etas[i - 1] : 0
                let eb = etas.indices.contains(i) ? etas[i] : ea
                guard length > 0 else { continue }
                var pos = 0.0
                while sinceLast + (length - pos) >= step {
                    pos += step - sinceLast
                    sinceLast = 0
                    let f = pos / length
                    add(point: CLLocationCoordinate2D(latitude: a.latitude + (b.latitude - a.latitude) * f, longitude: a.longitude + (b.longitude - a.longitude) * f),
                        eta: ea + (eb - ea) * f)
                }
                sinceLast += length - pos
                add(point: b, eta: eb)                // corners always count
            }
        }
        return hits
    }

    /// How much a tile that is already on the device is still worth keeping: the best any source says about it (0 when none reach it),
    /// a little lower for detail finer than a source ever asks for.
    public static func retention(of tile: TileID, sources: [NeedSource]) -> Double {
        let centre = TileMath.center(of: tile)
        let half = TileMath.sizeMeters(zoom: tile.z, latitude: centre.latitude) / 2
        var best = 0.0
        for s in sources {
            let zoomForRadius = min(tile.z, s.maxZoom)
            let radius = s.radius(atZoom: zoomForRadius)
            let d = max(0, distanceToSource(centre, s) - half)
            var p = s.weight * falloff(d / radius)
            if tile.z > s.maxZoom { p *= 0.3 }
            best = max(best, p)
        }
        return best
    }

    static func distanceToSource(_ p: CLLocationCoordinate2D, _ s: NeedSource) -> Double {
        switch s.geometry {
        case .point(let c, _): return TileMath.distance(p, c)
        case .path(let v, _):
            guard let first = v.first else { return .infinity }
            if v.count == 1 { return TileMath.distance(p, first) }
            var best = Double.infinity
            for i in 1..<v.count { best = min(best, distance(from: p, toSegment: v[i - 1], v[i])) }
            return best
        }
    }

    static func distance(from p: CLLocationCoordinate2D, toSegment a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let k = cos(p.latitude * .pi / 180)
        let ax = (a.longitude - p.longitude) * TileMath.metresPerDegreeLongitudeAtEquator * k, ay = (a.latitude - p.latitude) * TileMath.metresPerDegreeLatitude
        let bx = (b.longitude - p.longitude) * TileMath.metresPerDegreeLongitudeAtEquator * k, by = (b.latitude - p.latitude) * TileMath.metresPerDegreeLatitude
        let dx = bx - ax, dy = by - ay
        let len2 = dx * dx + dy * dy
        let t = len2 == 0 ? 0 : max(0, min(1, -(ax * dx + ay * dy) / len2))
        return hypot(ax + t * dx, ay + t * dy)
    }
}
