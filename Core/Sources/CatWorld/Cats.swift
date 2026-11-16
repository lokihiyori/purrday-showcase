import Economy
import Foundation

// 不止一只猫（docs/cat-life.md 第 7 节第 3 步）：品种、体型不一样的猫可以领养、可以选哪只陪你。
// 房间里同一时间只有一只；每只猫有自己的好感度、回忆和性格，新来的猫和布丁当初一样从"刚到家"开始。

/// 猫的种类。美术资源按它分（布丁是 cat-pose-<姿势>，其他是 cat-<种类>-pose-<姿势>）。
public enum CatKind: String, Codable, CodingKeyRepresentable, Sendable, CaseIterable {
    /// 圆滚滚的奶油色短毛猫，焦糖色的帽子和尾巴（一开始就有）
    case pudding
    /// 细长优雅的暹罗，蓝眼睛
    case siamese
    /// 蓬松的烟灰色长毛猫，绿眼睛
    case fluffy

    /// 固定的性格（布丁的性格是领养时随机的）
    public var personality: Personality? {
        switch self {
        case .pudding: nil
        case .siamese: .clingy   // 暹罗：黏人、话多
        case .fluffy: .aloof     // 长毛猫：慢悠悠、有点高冷
        }
    }

    /// 怎么领养
    public var adoption: CatAdoption {
        switch self {
        case .pudding: .starter
        case .siamese: .bond(.familiar)
        case .fluffy: .fish(300)
        }
    }
}

/// 领养一只猫的条件。
public enum CatAdoption: Hashable, Sendable {
    /// 一开始就有
    case starter
    /// 和任意一只猫到了这个好感阶段，她就自己来了（不花钱）
    case bond(BondStage)
    /// 花小鱼干领养
    case fish(Int)
}

/// 一只猫现在的情况（"我的猫"页面用）。
public enum CatAvailability: Hashable, Sendable {
    /// 正陪着你
    case active
    /// 领养了，在休息，可以换她出来
    case resting
    /// 可以领养了
    case adoptable
    /// 还不行：好感不够 / 小鱼干不够
    case locked
}

extension CatWorld {
    public var activeCat: CatKind { state.activeCat }
    public var adoptedCats: [CatKind] { state.adoptedCats }

    /// 和所有猫里最熟的那只到了哪个阶段（解锁新猫看这个）
    public var bestBondStage: BondStage {
        ([state.bond] + Array(state.restingBonds.values)).map(\.stage).max() ?? .newcomer
    }

    public func availability(of kind: CatKind) -> CatAvailability {
        if kind == state.activeCat { return .active }
        if state.adoptedCats.contains(kind) { return .resting }
        switch kind.adoption {
        case .starter: return .adoptable
        case let .bond(stage): return bestBondStage >= stage ? .adoptable : .locked
        case let .fish(price): return state.economy.wallet.fish >= price ? .adoptable : .locked
        }
    }

    /// 某只猫的好感阶段（没领养的为 nil）。界面只用它决定说明文字，不显示分数。
    public func bondStage(of kind: CatKind) -> BondStage? {
        if kind == state.activeCat { return state.bond.stage }
        return state.restingBonds[kind]?.stage
    }

    /// 领养一只新猫，并且换她出来陪你。要花小鱼干的会扣；条件不够时抛错。
    public mutating func adopt(_ kind: CatKind, at date: Date) throws {
        guard availability(of: kind) == .adoptable else {
            if case let .fish(price) = kind.adoption, !state.adoptedCats.contains(kind) {
                throw EconomyError.insufficientFish(needed: price, balance: state.economy.wallet.fish)
            }
            throw WorldError.catNotAvailable(kind)
        }
        if case let .fish(price) = kind.adoption {
            var economyState = state.economy
            try economy.spend(price, state: &economyState)
            state.economy = economyState
        }
        state.adoptedCats.append(kind)
        var bond = BondState.newCat(seed: Self.mix(state.lifeSeed, UInt64(state.adoptedCats.count), 0x4B49_4E44))
        if let personality = kind.personality { bond.personality = personality }
        state.restingBonds[kind] = bond
        try switchCat(to: kind, at: date)
    }

    /// 换一只领养过的猫出来陪你。原来那只去休息，好感度、回忆都留着。
    public mutating func switchCat(to kind: CatKind, at date: Date) throws {
        guard kind != state.activeCat else { return }
        guard state.adoptedCats.contains(kind), let bond = state.restingBonds[kind] else {
            throw WorldError.catNotAvailable(kind)
        }
        state.restingBonds[state.activeCat] = state.bond
        state.restingBonds[kind] = nil
        state.bond = bond
        state.activeCat = kind
        addBond(.dailyVisit, at: date) // 今天第一次见她
    }
}
