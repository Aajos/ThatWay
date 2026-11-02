//
//  MapStore.swift
//  ThatWayCore · MapPrefetch
//
//  The other half of "how much": what to throw away. A phone's map store has a budget; when it is full the tiles least likely to be
//  wanted again go first, and the ones the person has just passed go before the ones still ahead. Plus the privacy trade-off for
//  asking a server for tiles at all.
//

import CoreLocation

public struct CachedTile: Equatable, Sendable {
    public var tile: TileID
    public var bytes: Int
    /// Seconds since it was last drawn or used.
    public var age: TimeInterval
    /// Saved trips and the person's home area: never evicted.
    public var pinned: Bool
    public init(tile: TileID, bytes: Int, age: TimeInterval, pinned: Bool = false) { self.tile = tile; self.bytes = bytes; self.age = age; self.pinned = pinned }
}

public enum EvictionPlanner {
    /// Tiles to delete so the store fits its budget, or nothing when it already does. Once over budget it frees down to
    /// `lowWater` of it, so it is not trimming on every download. Lowest keep-score goes first: the need model's retention
    /// (how likely it is wanted again, given where the person is going) plus a small bonus for recent use.
    public static func plan(cache: [CachedTile], budgetBytes: Int, lowWater: Double = 0.85, sources: [NeedSource], recencyHalfLife: TimeInterval = 6 * 3600) -> [TileID] {
        let total = cache.reduce(0) { $0 + $1.bytes }
        guard total > budgetBytes else { return [] }
        let target = Int(Double(budgetBytes) * lowWater)
        var scored: [(cached: CachedTile, keep: Double)] = []
        for c in cache where !c.pinned {
            let recency = 0.3 * pow(0.5, c.age / recencyHalfLife)
            scored.append((c, NeedModel.retention(of: c.tile, sources: sources) + recency))
        }
        scored.sort { a, b in
            if a.keep != b.keep { return a.keep < b.keep }
            if a.cached.tile.z != b.cached.tile.z { return a.cached.tile.z > b.cached.tile.z }     // ties: finer detail goes first
            return a.cached.tile < b.cached.tile
        }
        var remaining = total
        var out: [TileID] = []
        for entry in scored where remaining > target {
            out.append(entry.cached.tile); remaining -= entry.cached.bytes
        }
        return out
    }
}

/// Asking a server for tiles tells it roughly where someone is. Rounding every request up to a whole coarse block hides the exact
/// street, at the cost of downloading the rest of the block. This measures that trade so it can be chosen, not guessed.
public enum PrivacyBlocks {
    public struct Group: Equatable, Sendable {
        public var block: TileID
        public var wanted: [TileID]
        /// Tiles in the whole block at the finest zoom wanted: what "fetch the block" would download.
        public var wholeBlockTiles: Int
    }

    public static func group(_ requests: [TileRequest], blockZoom: Int) -> [Group] {
        var wanted: [TileID: [TileID]] = [:]
        var finest: [TileID: Int] = [:]
        for r in requests where r.tile.z >= blockZoom {
            let b = TileMath.parent(of: r.tile, atZoom: blockZoom)
            wanted[b, default: []].append(r.tile)
            finest[b] = max(finest[b] ?? 0, r.tile.z)
        }
        return wanted.map { b, tiles in
            // One block holds 4^(zoom − blockZoom) tiles at a zoom; counted over the zooms actually wanted.
            let zooms = Set(tiles.map(\.z))
            let whole = zooms.reduce(0) { $0 + Int(pow(4, Double($1 - blockZoom))) }
            return Group(block: b, wanted: tiles.sorted(), wholeBlockTiles: whole)
        }.sorted { $0.block < $1.block }
    }

    /// How many times more tiles "fetch whole blocks" downloads than the exact tiles (1 means no overhead).
    public static func overhead(_ requests: [TileRequest], blockZoom: Int) -> Double {
        let groups = group(requests, blockZoom: blockZoom)
        let exact = groups.reduce(0) { $0 + $1.wanted.count }
        guard exact > 0 else { return 1 }
        return Double(groups.reduce(0) { $0 + $1.wholeBlockTiles }) / Double(exact)
    }
}
