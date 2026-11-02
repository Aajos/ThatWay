//
//  TileMath.swift
//  ThatWayCore · MapPrefetch
//
//  Web-Mercator "slippy map" tiles (z/x/y), which is what vector and raster map archives (PMTiles, MBTiles, XYZ servers) are
//  cut into. Pure maths: no network, no map SDK. The prefetch planner thinks in tiles, bytes and seconds, and whatever map
//  source is chosen later only has to turn a TileID into bytes.
//

import CoreLocation

public struct TileID: Hashable, Comparable, Codable, Sendable {
    public let z: Int, x: Int, y: Int
    public init(z: Int, x: Int, y: Int) { self.z = z; self.x = x; self.y = y }
    public static func < (a: TileID, b: TileID) -> Bool { (a.z, a.x, a.y) < (b.z, b.x, b.y) }
}

public enum TileMath {
    public static let earthCircumference = 40_075_016.686
    public static let maxLatitude = 85.0511287798
    static let metresPerDegreeLatitude = 110_574.0
    static let metresPerDegreeLongitudeAtEquator = 111_320.0

    public static func tile(containing c: CLLocationCoordinate2D, zoom: Int) -> TileID {
        let n = Double(1 << zoom)
        let lat = max(-maxLatitude, min(maxLatitude, c.latitude)) * .pi / 180
        let fx = (c.longitude + 180) / 360 * n
        let fy = (1 - log(tan(lat) + 1 / cos(lat)) / .pi) / 2 * n
        let top = Int(n) - 1
        return TileID(z: zoom, x: min(top, max(0, Int(floor(fx)))), y: min(top, max(0, Int(floor(fy)))))
    }

    /// The edges of a tile, in degrees.
    public static func bounds(of t: TileID) -> (north: Double, south: Double, west: Double, east: Double) {
        let n = Double(1 << t.z)
        func lat(_ y: Double) -> Double { atan(sinh(.pi * (1 - 2 * y / n))) * 180 / .pi }
        return (lat(Double(t.y)), lat(Double(t.y + 1)), Double(t.x) / n * 360 - 180, Double(t.x + 1) / n * 360 - 180)
    }

    public static func center(of t: TileID) -> CLLocationCoordinate2D {
        let b = bounds(of: t)
        return CLLocationCoordinate2D(latitude: (b.north + b.south) / 2, longitude: (b.west + b.east) / 2)
    }

    /// How wide a tile is on the ground at this latitude.
    public static func sizeMeters(zoom: Int, latitude: Double) -> Double {
        earthCircumference * cos(latitude * .pi / 180) / Double(1 << zoom)
    }

    /// The tile at a coarser zoom that contains this one.
    public static func parent(of t: TileID, atZoom z: Int) -> TileID {
        precondition(z <= t.z, "a parent is at a coarser zoom")
        let shift = t.z - z
        return TileID(z: z, x: t.x >> shift, y: t.y >> shift)
    }

    public static func parent(of t: TileID) -> TileID? { t.z > 0 ? parent(of: t, atZoom: t.z - 1) : nil }

    // MARK: Distances on the ground (flat-earth, accurate to a few metres over the distances a trip's map needs)

    /// Metres from a point to the nearest edge of a tile (0 inside it).
    public static func distance(from p: CLLocationCoordinate2D, toTile t: TileID) -> Double {
        let b = bounds(of: t)
        let dLat = max(0, b.south - p.latitude, p.latitude - b.north)
        let dLon = max(0, b.west - p.longitude, p.longitude - b.east)
        return hypot(dLat * metresPerDegreeLatitude, dLon * metresPerDegreeLongitudeAtEquator * cos(p.latitude * .pi / 180))
    }

    public static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let midLat = (a.latitude + b.latitude) / 2 * .pi / 180
        return hypot((a.latitude - b.latitude) * metresPerDegreeLatitude, (a.longitude - b.longitude) * metresPerDegreeLongitudeAtEquator * cos(midLat))
    }

    /// Every tile at `zoom` that comes within `radius` metres of `p`, with how far it is.
    public static func tiles(near p: CLLocationCoordinate2D, radius: Double, zoom: Int) -> [(tile: TileID, distance: Double)] {
        let dLat = radius / metresPerDegreeLatitude
        let dLon = radius / (metresPerDegreeLongitudeAtEquator * max(0.05, cos(p.latitude * .pi / 180)))
        let a = tile(containing: CLLocationCoordinate2D(latitude: p.latitude + dLat, longitude: p.longitude - dLon), zoom: zoom)
        let b = tile(containing: CLLocationCoordinate2D(latitude: p.latitude - dLat, longitude: p.longitude + dLon), zoom: zoom)
        var out: [(TileID, Double)] = []
        for x in min(a.x, b.x)...max(a.x, b.x) {
            for y in min(a.y, b.y)...max(a.y, b.y) {
                let t = TileID(z: zoom, x: x, y: y)
                let d = distance(from: p, toTile: t)
                if d <= radius { out.append((t, d)) }
            }
        }
        return out
    }
}
