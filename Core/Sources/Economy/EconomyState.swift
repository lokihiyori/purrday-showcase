import Foundation

/// 小鱼干钱包（对应 SwiftData 的 `Wallet`）。
public struct Wallet: Codable, Hashable, Sendable {
    public internal(set) var fish: Int = 0
    /// 累计获得过的小鱼干（包括卖礼物），只增不减
    public internal(set) var lifetimeFish: Int = 0

    public init(fish: Int = 0, lifetimeFish: Int? = nil) {
        self.fish = fish
        self.lifetimeFish = lifetimeFish ?? fish
    }
}

/// 物品来源（对应 SwiftData `Item.source`）。
public enum ItemSource: String, Codable, Sendable {
    /// 猫带回来的（早餐礼物、户外纪念品）
    case gift
    case shop
    /// 活动 / 默认赠送 / Plus 解锁
    case event
}

/// 用户拥有的一件物品（对应 SwiftData 的 `Item`）。
public struct OwnedItem: Codable, Hashable, Sendable, Identifiable {
    /// 本地递增编号；同步到 SwiftData 时可以映射成 UUID
    public var id: Int
    public var catalogID: String
    public var obtainedAt: Date
    public var source: ItemSource
}

/// 经济系统的完整状态，可以直接持久化。
public struct EconomyState: Codable, Hashable, Sendable {
    public internal(set) var wallet: Wallet
    public internal(set) var items: [OwnedItem]
    var nextItemID: Int

    /// 新用户：默认毛色 + 0 小鱼干。
    public static func newPlayer(catalog: Catalog, at date: Date) -> EconomyState {
        EconomyState(
            wallet: Wallet(),
            items: [OwnedItem(id: 1, catalogID: catalog.defaultCoat, obtainedAt: date, source: .event)],
            nextItemID: 2
        )
    }

    public init(wallet: Wallet = Wallet(), items: [OwnedItem] = [], nextItemID: Int? = nil) {
        self.wallet = wallet
        self.items = items
        self.nextItemID = nextItemID ?? ((items.map(\.id).max() ?? 0) + 1)
    }

    public func owns(_ catalogID: String) -> Bool {
        items.contains { $0.catalogID == catalogID }
    }

    public func count(of catalogID: String) -> Int {
        items.filter { $0.catalogID == catalogID }.count
    }

    @discardableResult
    mutating func add(_ catalogID: String, at date: Date, source: ItemSource) -> OwnedItem {
        let item = OwnedItem(id: nextItemID, catalogID: catalogID, obtainedAt: date, source: source)
        nextItemID += 1
        items.append(item)
        return item
    }

    mutating func credit(_ amount: Int) {
        precondition(amount >= 0)
        wallet.fish += amount
        wallet.lifetimeFish += amount
    }

    #if DEBUG
    /// 只在 Debug 版本里有：给测试和 UI 走查加小鱼干。
    public mutating func debugCredit(_ amount: Int) {
        credit(amount)
    }
    #endif
}
