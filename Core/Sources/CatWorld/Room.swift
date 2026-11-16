import Economy
import Foundation

/// 房间里的一个位置：家具（或猫）底边中点的坐标。
///
/// 房间画布宽:高 = 3:4。`x` 从左 0 到右 1，`y` 从上 0 到下 1；墙面在 `RoomGeometry.floorLine` 以上，地板在以下。
/// 地上的东西 `y` 越大越靠前（画在越上层）。
public struct RoomPoint: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// 摆在房间里的一件家具（对应计划书第 6 节 `RoomLayout.placements`）。
public struct PlacedFurniture: Codable, Hashable, Sendable, Identifiable {
    /// `OwnedItem.id`
    public var itemID: Int
    public var catalogID: String
    public var position: RoomPoint
    /// 放进房间（或最后一次移动）的时间；同一层里后放的画在上面
    public var placedAt: Date

    public var id: Int { itemID }
}

/// 房间布局。只有摆出来的家具在这里；买了但收起来的家具只在 `EconomyState.items` 里。
public struct RoomLayout: Codable, Hashable, Sendable {
    public internal(set) var placed: [PlacedFurniture] = []

    public init(placed: [PlacedFurniture] = []) {
        self.placed = placed
    }

    public func furniture(itemID: Int) -> PlacedFurniture? {
        placed.first { $0.itemID == itemID }
    }
}

/// 房间的几何规则：家具能放在哪里、谁挡住谁、猫站在哪里。纯计算，方便测试。
public enum RoomGeometry {
    /// 墙和地板的分界线
    public static let floorLine = 0.6
    /// 墙上的东西离天花板、地板至少留这么多
    static let wallMargin = 0.02
    /// 地上的东西底边至少比分界线低这么多（看起来是站在地板上，而不是贴着墙根）
    static let floorDepth = 0.06
    /// 房间里猫的图的尺寸（猫的图是正方形，600×800 画布里 192×192）
    public static let catWidth = 0.32
    public static let catHeight = 0.24
    /// 猫的图里脚底那条线的高度（从图的顶部算，占图高的比例）：这一点对准猫的位置
    public static let catGround = 0.9
    /// 没有特别要去的地方时，猫坐在这里
    public static let catHome = RoomPoint(x: 0.5, y: 0.9)
    /// 猫去看地上的家具时最靠后站到这里
    static let catFrontRow = 0.86

    /// 把位置限制在这件家具能放的范围里：不出房间左右边界，墙上的东西不掉到地上，地上的东西不爬到墙上。
    public static func clamp(_ point: RoomPoint, for placement: FurniturePlacement) -> RoomPoint {
        let halfWidth = min(placement.width, 1) / 2
        let x = point.x.clamped(to: range(halfWidth, 1 - halfWidth))
        let yRange: ClosedRange<Double>
        switch placement.zone {
        case .wall:
            yRange = range(placement.height + wallMargin, floorLine - wallMargin)
        case .rug:
            yRange = range(floorLine + max(placement.height, floorDepth), 1)
        case .floor:
            yRange = range(floorLine + floorDepth, 1)
        }
        return RoomPoint(x: x, y: point.y.clamped(to: yRange))
    }

    /// 目录数据不合理（比如墙上的东西比墙还高）时也不会崩：下限优先。
    private static func range(_ lower: Double, _ upper: Double) -> ClosedRange<Double> {
        lower...max(lower, upper)
    }

    /// 从后往前的绘制顺序：墙上的 → 地毯 → 地上的（按 `y` 从小到大）。同一层、同一个 `y` 时后放的在上面。
    public static func drawOrder(_ placed: [PlacedFurniture], catalog: Catalog) -> [PlacedFurniture] {
        func rank(_ item: PlacedFurniture) -> (Int, Double, Date, Int) {
            let zone = catalog.item(item.catalogID)?.placement?.zone ?? .floor
            let layer = RoomZone.allCases.firstIndex(of: zone)!
            return (layer, zone == .floor ? item.position.y : 0, item.placedAt, item.itemID)
        }
        return placed.sorted { rank($0) < rank($1) }
    }

    /// 猫要去看一件刚放好的家具时站的位置：地上的家具站在旁边（右边放不下就站左边），
    /// 地毯就坐在地毯上，墙上的东西就坐在它正下方的地板上抬头看。
    /// 站在地上家具旁边时至少站到 `catFrontRow` 那么靠前，免得被别的家具挡住。
    public static func catSpot(beside item: PlacedFurniture, placement: FurniturePlacement) -> RoomPoint {
        let catHalf = catWidth / 2
        let catRange = catHalf...(1 - catHalf)
        let floorRange = (floorLine + floorDepth)...1
        switch placement.zone {
        case .wall:
            return RoomPoint(x: item.position.x.clamped(to: catRange), y: 0.88)
        case .rug:
            return RoomPoint(x: item.position.x.clamped(to: catRange), y: (item.position.y - 0.02).clamped(to: floorRange))
        case .floor:
            // 猫的图左右有留白，贴近一点看起来才像挨着
            let offset = placement.width / 2 + catHalf * 0.7
            let right = item.position.x + offset
            let x = right <= catRange.upperBound ? right : item.position.x - offset
            return RoomPoint(x: x.clamped(to: catRange), y: max(item.position.y + 0.02, catFrontRow).clamped(to: floorRange))
        }
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - 布置房间

extension CatWorld {
    /// 拥有、但收起来没摆在房间里的家具。
    public var storedFurniture: [OwnedItem] {
        state.economy.items.filter { item in
            economy.catalog.item(item.catalogID)?.placement != nil && state.room.furniture(itemID: item.id) == nil
        }
    }

    /// 房间里的家具，按从后往前的绘制顺序。
    public var roomDrawOrder: [PlacedFurniture] {
        RoomGeometry.drawOrder(state.room.placed, catalog: economy.catalog)
    }

    /// 把一件家具摆进房间。`point` 为 nil 时放在默认位置；已经在房间里的就移过去。返回实际位置（限制在能放的范围里）。
    @discardableResult
    public mutating func placeFurniture(itemID: Int, at point: RoomPoint?, date: Date) throws -> RoomPoint {
        guard let owned = state.economy.items.first(where: { $0.id == itemID }),
              let placement = economy.catalog.item(owned.catalogID)?.placement
        else { throw WorldError.notPlaceable(itemID: itemID) }
        let position = RoomGeometry.clamp(point ?? RoomPoint(x: placement.x, y: placement.y), for: placement)
        state.room.placed.removeAll { $0.itemID == itemID }
        state.room.placed.append(PlacedFurniture(itemID: itemID, catalogID: owned.catalogID, position: position, placedAt: date))
        return position
    }

    /// 拖动房间里的一件家具。返回实际位置（限制在能放的范围里）。
    @discardableResult
    public mutating func moveFurniture(itemID: Int, to point: RoomPoint, date: Date) throws -> RoomPoint {
        guard state.room.furniture(itemID: itemID) != nil else { throw WorldError.notInRoom(itemID: itemID) }
        return try placeFurniture(itemID: itemID, at: point, date: date)
    }

    /// 把一件家具收起来（还在背包里，可以再摆出来）。
    public mutating func putAway(itemID: Int) throws {
        guard state.room.furniture(itemID: itemID) != nil else { throw WorldError.notInRoom(itemID: itemID) }
        state.room.placed.removeAll { $0.itemID == itemID }
    }

    /// 猫要去看这件家具时站的位置；家具不在房间里时回到默认位置。
    public func catSpot(beside itemID: Int?) -> RoomPoint {
        guard let itemID, let item = state.room.furniture(itemID: itemID),
              let placement = economy.catalog.item(item.catalogID)?.placement
        else { return RoomGeometry.catHome }
        return RoomGeometry.catSpot(beside: item, placement: placement)
    }

    #if DEBUG
    /// 只在 Debug 版本里有：给测试和 UI 走查加小鱼干（`-debugFish 200` 启动参数）。
    public mutating func debugGrantFish(_ amount: Int) {
        state.economy.debugCredit(amount)
    }
    #endif
}
