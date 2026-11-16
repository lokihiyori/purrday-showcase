import CatEngine
import Foundation

/// 奖励数值（计划书第 3 节初稿，内测时调）。
public struct EconomyConfig: Hashable, Sendable {
    public var wakeGiftFish = 10
    public var focusFish = 5
    public var bookFish = 30
    /// Plus 会员获得的奖励小鱼干倍数（卖礼物不翻倍）
    public var plusFishMultiplier = 2
    public var breakfastTable = "breakfast"
    public var souvenirTable = "souvenir"

    public init() {}
}

public enum EconomyError: Error, Hashable, Sendable {
    case unknownItem(String)
    case unknownLootTable(String)
    case notForSale(String)
    case notSellable(String)
    case alreadyOwned(String)
    case requiresPlus(String)
    case insufficientFish(needed: Int, balance: Int)
    case itemNotOwned(Int)
}

/// 一次奖励实际发了什么。
public struct Grant: Hashable, Sendable {
    public var fish: Int
    public var items: [OwnedItem]
}

/// 经济规则：把 CatEngine 的奖励变成小鱼干和物品，以及商店买卖。纯函数，状态由调用方保存。
public struct EconomyEngine: Sendable {
    public let catalog: Catalog
    public let config: EconomyConfig

    public init(catalog: Catalog, config: EconomyConfig = EconomyConfig()) {
        self.catalog = catalog
        self.config = config
    }

    // MARK: 奖励

    /// 发放 CatEngine 输出的奖励。
    @discardableResult
    public func grant<R: RandomNumberGenerator>(
        _ reward: CatReward,
        isPlus: Bool,
        at date: Date,
        state: inout EconomyState,
        rng: inout R
    ) throws -> Grant {
        let multiplier = isPlus ? config.plusFishMultiplier : 1
        var fish = 0
        var items: [OwnedItem] = []
        switch reward {
        case let .wakeGift(luckyBoost):
            fish = config.wakeGiftFish * multiplier
            let gift = try roll(config.breakfastTable, lucky: luckyBoost, rng: &rng)
            items.append(state.add(gift.id, at: date, source: .gift))
        case .focusCompleted:
            fish = config.focusFish * multiplier
        case .bookFinished:
            fish = config.bookFish * multiplier
        case .stepGoalSouvenir:
            let souvenir = try roll(config.souvenirTable, lucky: false, rng: &rng)
            items.append(state.add(souvenir.id, at: date, source: .gift))
        }
        state.credit(fish)
        return Grant(fish: fish, items: items)
    }

    // MARK: 掉落

    /// 各稀有度的实际抽中概率（考虑幸运加成）。
    public func rarityOdds(_ tableName: String, lucky: Bool) throws -> [Rarity: Double] {
        guard let table = catalog.lootTables[tableName] else { throw EconomyError.unknownLootTable(tableName) }
        let present = Set(table.items.compactMap { catalog.item($0)?.rarity })
        var weights: [Rarity: Double] = [:]
        for rarity in present {
            let base = table.rarityWeights[rarity] ?? 0
            weights[rarity] = lucky ? base * (table.luckyMultipliers[rarity] ?? 1) : base
        }
        let total = weights.values.reduce(0, +)
        guard total > 0 else { throw EconomyError.unknownLootTable(tableName) }
        return weights.mapValues { $0 / total }
    }

    /// 从掉落表里抽一件物品。
    public func roll<R: RandomNumberGenerator>(_ tableName: String, lucky: Bool, rng: inout R) throws -> CatalogItem {
        let odds = try rarityOdds(tableName, lucky: lucky)
        let table = catalog.lootTables[tableName]!
        var pick = rng.unitDouble()
        var chosen = odds.keys.max()!
        for rarity in Rarity.allCases {
            guard let p = odds[rarity] else { continue }
            if pick < p { chosen = rarity; break }
            pick -= p
        }
        let candidates = table.items.compactMap(catalog.item).filter { $0.rarity == chosen }
        let index = min(Int(rng.unitDouble() * Double(candidates.count)), candidates.count - 1)
        return candidates[index]
    }

    // MARK: 商店

    /// 商店里能看到的家具，按价格排序。Plus 专属的也列出来（带预览，点击时触发付费墙）。
    public func shopItems() -> [CatalogItem] {
        catalog.items
            .filter { $0.kind == .furniture && $0.price != nil }
            .sorted { ($0.price!, $0.id) < ($1.price!, $1.id) }
    }

    /// 用小鱼干买一件家具。
    @discardableResult
    public func buy(_ catalogID: String, isPlus: Bool, at date: Date, state: inout EconomyState) throws -> OwnedItem {
        guard let item = catalog.item(catalogID) else { throw EconomyError.unknownItem(catalogID) }
        guard let price = item.price else { throw EconomyError.notForSale(catalogID) }
        if item.plusOnly && !isPlus { throw EconomyError.requiresPlus(catalogID) }
        if item.isUnique && state.owns(catalogID) { throw EconomyError.alreadyOwned(catalogID) }
        guard state.wallet.fish >= price else {
            throw EconomyError.insufficientFish(needed: price, balance: state.wallet.fish)
        }
        state.wallet.fish -= price
        return state.add(catalogID, at: date, source: .shop)
    }

    /// 一份零食多少小鱼干（docs/cat-life.md：零食花小鱼干买，是小鱼干的日常消耗）
    public static let treatPrice = 3

    /// 花小鱼干（零食这类不进背包的消耗）。
    public func spend(_ amount: Int, state: inout EconomyState) throws {
        precondition(amount >= 0)
        guard state.wallet.fish >= amount else {
            throw EconomyError.insufficientFish(needed: amount, balance: state.wallet.fish)
        }
        state.wallet.fish -= amount
    }

    /// 卖掉一件礼物，返回得到的小鱼干。
    @discardableResult
    public func sell(itemID: Int, state: inout EconomyState) throws -> Int {
        guard let index = state.items.firstIndex(where: { $0.id == itemID }) else {
            throw EconomyError.itemNotOwned(itemID)
        }
        let catalogID = state.items[index].catalogID
        guard let item = catalog.item(catalogID) else { throw EconomyError.unknownItem(catalogID) }
        guard let price = item.sellPrice else { throw EconomyError.notSellable(catalogID) }
        state.items.remove(at: index)
        state.credit(price)
        return price
    }

    // MARK: 毛色

    /// 这个毛色现在能不能用：拥有的（默认毛色）都能用，其余 Plus 专属毛色在 Plus 期间能用。
    public func canUseCoat(_ catalogID: String, isPlus: Bool, state: EconomyState) -> Bool {
        guard let item = catalog.item(catalogID), item.kind == .coat else { return false }
        return state.owns(catalogID) || (item.plusOnly && isPlus)
    }
}
