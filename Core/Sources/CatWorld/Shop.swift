import CatEngine
import Economy
import Foundation

// 商店里的两件小事（docs/cat-life.md 第 5 节）：今日推荐，和"买之前先看看摆在房间里的样子"。

extension CatWorld {
    /// 今日推荐：每天挑几件你还没有、现在买得了的家具（Plus 专属的只推荐给 Plus 用户）。
    /// 由种子和日期决定，同一天不变；快买齐时有几件算几件。
    public func dailyPicks(at date: Date, isPlus: Bool, count: Int = 3) -> [CatalogItem] {
        let day = catConfig.logicalDay(of: date)
        var rng = SeededRandom(seed: Self.mix(state.lifeSeed, UInt64(day.year * 10000 + day.month * 100 + day.day), 0x5049_434B))
        var pool = economy.shopItems().filter { !state.economy.owns($0.id) && (isPlus || !$0.plusOnly) }
        var picks: [CatalogItem] = []
        while picks.count < count, !pool.isEmpty {
            picks.append(pool.remove(at: Int(rng.next() % UInt64(pool.count))))
        }
        return picks
    }

    /// 把一件还没买的家具放在默认位置，和房间里已有的家具一起按前后顺序排好（预览用，不改存档）。
    /// 返回排好的家具和新家具那一件；目录里没有这件家具、或者它不能摆进房间时返回 nil。
    public func roomPreview(adding catalogID: String, at date: Date) -> (furniture: [PlacedFurniture], added: PlacedFurniture, cat: RoomPoint)? {
        guard let placement = economy.catalog.item(catalogID)?.placement else { return nil }
        let position = RoomGeometry.clamp(RoomPoint(x: placement.x, y: placement.y), for: placement)
        let added = PlacedFurniture(itemID: -1, catalogID: catalogID, position: position, placedAt: date)
        let all = RoomGeometry.drawOrder(state.room.placed.filter { $0.catalogID != catalogID } + [added], catalog: economy.catalog)
        return (all, added, RoomGeometry.catSpot(beside: added, placement: placement))
    }
}
