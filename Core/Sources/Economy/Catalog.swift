import Foundation

/// 物品稀有度。
public enum Rarity: String, Codable, CodingKeyRepresentable, Sendable, CaseIterable, Comparable {
    case common, uncommon, rare, legendary

    public static func < (lhs: Rarity, rhs: Rarity) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}

/// 物品种类。
public enum ItemKind: String, Codable, Sendable, CaseIterable {
    /// 早餐礼物：可以卖掉换小鱼干
    case gift
    /// 户外纪念品（步数达标）：收藏，不能卖
    case souvenir
    /// 家具：在商店用小鱼干买，每件只能有一个
    case furniture
    /// 猫咪毛色：Plus 解锁，每种只能有一个
    case coat
}

/// 目录里的一件物品（内置 JSON，不存数据库）。
public struct CatalogItem: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var kind: ItemKind
    public var rarity: Rarity
    /// Localizable.xcstrings 里的 key。Core 不放用户可见文字
    public var nameKey: String
    /// 中文名，仅供开发和策划参考
    public var name: String
    /// 商店价格（小鱼干），nil 表示不在商店卖
    public var price: Int?
    /// 卖出价格（小鱼干），nil 表示不能卖
    public var sellPrice: Int?
    /// 是否需要 Plus
    public var plusOnly: Bool
    /// 家具在房间里的尺寸和默认位置；其他物品为 nil
    public var placement: FurniturePlacement?

    /// 家具和毛色每件只能拥有一个；礼物和纪念品可以重复。
    public var isUnique: Bool { kind == .furniture || kind == .coat }
}

/// 家具放在房间的哪一层。
public enum RoomZone: String, Codable, Sendable, CaseIterable {
    /// 挂在墙上（置物架、灯串、窗边吊床）
    case wall
    /// 平铺在地上（地毯）：总是画在其他地面家具下面
    case rug
    /// 立在地上
    case floor
}

/// 家具的尺寸和默认位置（房间坐标见 `RoomGeometry`）。
///
/// 美术按这里的尺寸画：房间画布是 600×800，`width` × 600、`height` × 800 就是家具图的像素尺寸。
public struct FurniturePlacement: Codable, Hashable, Sendable {
    public var zone: RoomZone
    /// 默认位置：家具底边中点的横坐标，0 是房间最左，1 是最右
    public var x: Double
    /// 默认位置：家具底边的纵坐标，0 是房间顶部，1 是底部
    public var y: Double
    /// 占房间宽度的比例
    public var width: Double
    /// 占房间高度的比例
    public var height: Double
    /// 猫能在这件家具上 / 里面 / 旁边做什么（docs/cat-life.md 3.3）。纯装饰的家具没有
    public var spots: [FurnitureSpot]?

    public init(zone: RoomZone, x: Double, y: Double, width: Double, height: Double, spots: [FurnitureSpot]? = nil) {
        self.zone = zone
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.spots = spots
    }

    /// 有猫能钻进去的位置的家具，美术要多画一张前半部分（`<图名>-front`），盖在猫上面。
    public var hasFront: Bool {
        spots?.contains { $0.layer == .inside } ?? false
    }
}

/// 猫拿家具做的事。名字和 CatWorld 的 `CatActivity` 一一对应。
public enum FurnitureUse: String, Codable, Sendable, CaseIterable {
    case sit, loaf, groom, nap, sunbathe, watch, eat, drink, scratch, hide, perch
}

/// 猫在一件家具上（或旁边）待的位置。
public struct FurnitureSpot: Codable, Hashable, Sendable {
    public enum Layer: String, Codable, Sendable {
        /// 在家具里面：画在家具（后半部分）和它的前半部分之间，比如纸箱、云朵床、吊床
        case inside
        /// 在家具上面：画在家具之上，比如沙发坐垫、猫爬架顶
        case on
        /// 在家具旁边的地板上：和其他地上的东西一样按 y 排前后
        case floor
    }

    public var uses: [FurnitureUse]
    /// 猫脚底中点相对家具底边中点的偏移（房间坐标：`dx` 按房间宽算，`dy` 按房间高算，往上是负数）
    public var dx: Double
    public var dy: Double
    public var layer: Layer
    /// 被挑中的相对权重（默认 1）。比如睡觉时云朵床比地毯更受欢迎
    public var weight: Double?

    public init(uses: [FurnitureUse], dx: Double, dy: Double, layer: Layer, weight: Double? = nil) {
        self.uses = uses
        self.dx = dx
        self.dy = dy
        self.layer = layer
        self.weight = weight
    }
}

/// 掉落表：先按稀有度权重抽稀有度，再在该稀有度的物品里等概率抽一件。
public struct LootTable: Codable, Hashable, Sendable {
    public var items: [String]
    public var rarityWeights: [Rarity: Double]
    /// 幸运加成时各稀有度权重的倍数（没写的是 1）
    public var luckyMultipliers: [Rarity: Double]

    public init(items: [String], rarityWeights: [Rarity: Double], luckyMultipliers: [Rarity: Double] = [:]) {
        self.items = items
        self.rarityWeights = rarityWeights
        self.luckyMultipliers = luckyMultipliers
    }
}

/// 物品目录和掉落表。
public struct Catalog: Codable, Hashable, Sendable {
    public var version: Int
    /// 新用户默认拥有的毛色
    public var defaultCoat: String
    public var items: [CatalogItem]
    public var lootTables: [String: LootTable]

    public init(version: Int, defaultCoat: String, items: [CatalogItem], lootTables: [String: LootTable]) {
        self.version = version
        self.defaultCoat = defaultCoat
        self.items = items
        self.lootTables = lootTables
    }

    /// 内置目录（`Resources/catalog.json`）。
    public static func bundled() throws -> Catalog {
        guard let url = Bundle.module.url(forResource: "catalog", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
    }

    public func item(_ id: String) -> CatalogItem? {
        items.first { $0.id == id }
    }

    /// 检查目录本身是否自洽，返回发现的问题（空数组表示没问题）。
    public func validate() -> [String] {
        var problems: [String] = []
        var seen = Set<String>()
        for item in items {
            if !seen.insert(item.id).inserted { problems.append("重复的 id：\(item.id)") }
            if let price = item.price, price <= 0 { problems.append("\(item.id) 价格必须为正") }
            if let sell = item.sellPrice, sell <= 0 { problems.append("\(item.id) 卖价必须为正") }
            if item.kind == .gift, item.sellPrice == nil { problems.append("礼物 \(item.id) 没有卖价") }
            if item.kind == .furniture, item.price == nil { problems.append("家具 \(item.id) 没有价格") }
            if item.kind != .gift, item.sellPrice != nil { problems.append("\(item.id) 不是礼物，不能卖") }
            for spot in item.placement?.spots ?? [] {
                if spot.uses.isEmpty { problems.append("\(item.id) 有一个猫的位置没有写用途") }
                if let weight = spot.weight, weight <= 0 { problems.append("\(item.id) 猫的位置权重必须为正") }
            }
        }
        if item(defaultCoat)?.kind != .coat { problems.append("默认毛色 \(defaultCoat) 不存在") }
        for (name, table) in lootTables {
            if table.items.isEmpty { problems.append("掉落表 \(name) 是空的") }
            for id in table.items where item(id) == nil { problems.append("掉落表 \(name) 引用了不存在的 \(id)") }
            let rarities = Set(table.items.compactMap { item($0)?.rarity })
            for rarity in rarities where (table.rarityWeights[rarity] ?? 0) <= 0 {
                problems.append("掉落表 \(name) 里 \(rarity) 的权重必须为正")
            }
            for (rarity, weight) in table.rarityWeights where weight > 0 && !rarities.contains(rarity) {
                problems.append("掉落表 \(name) 给 \(rarity) 设了权重，但没有这个稀有度的物品")
            }
        }
        return problems
    }
}
