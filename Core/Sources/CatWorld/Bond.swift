import CatEngine
import Economy
import Foundation

// 隐藏好感度（docs/cat-life.md 第 2 节）：像刚领回家的小猫，从躲着你到黏着你。
// 界面上从不显示分数，只通过她的行为、台词和回忆册体现出来。分数只升不降；每天各种来源都有上限，刷不了。

/// 好感阶段。
public enum BondStage: Int, Codable, Sendable, CaseIterable, Comparable {
    /// 刚到家：躲着你，摸不得
    case newcomer = 1
    /// 好奇：自己出来走动，会凑过来闻
    case curious
    /// 熟悉：让摸头和背，打开 App 会过来迎接
    case familiar
    /// 亲近：摸的时候打呼噜，会露肚子（有时是陷阱），慢眨眼会眨回来
    case close
    /// 信赖：黏着你
    case devoted

    /// 进入每个阶段需要的分数
    public static let thresholds = [0, 50, 200, 500, 1000]

    public static func of(points: Int) -> BondStage {
        var stage = BondStage.newcomer
        for (index, threshold) in thresholds.enumerated() where points >= threshold {
            stage = BondStage(rawValue: index + 1) ?? .devoted
        }
        return stage
    }

    public static func < (lhs: BondStage, rhs: BondStage) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// 性格（领养时随机，隐藏）：影响各种互动加多少分。
public enum Personality: String, Codable, Sendable, CaseIterable {
    case clingy, aloof, playful, foodie, shy
}

/// 摸的部位。
public enum PetRegion: String, Codable, Sendable, CaseIterable {
    case head, chin, cheek, back, belly, tail
}

/// 被摸的反应。
public enum PetReaction: String, Codable, Sendable {
    /// 最喜欢的地方：闭眼、打呼噜
    case loves
    case likes
    /// 还不熟，忍着
    case tolerates
    /// 尾巴、还不让摸的肚子
    case dislikes
}

/// 好感度从哪来（每样每天有上限）。
public enum BondSource: String, Codable, CodingKeyRepresentable, Sendable, CaseIterable {
    case dailyVisit, onTimeWake, bedtime, pet, play, treat, slowBlink, request
}

/// 回忆册里的一条"第一次"。
public enum CatMemory: String, Codable, CodingKeyRepresentable, Sendable, CaseIterable {
    /// 第一次自己出来（进入好奇阶段）
    case cameOut
    /// 第一次让你摸
    case firstPet
    /// 第一次被摸得打呼噜
    case firstPurr
    /// 第一次陪她玩逗猫棒
    case firstPlay
    /// 第一次喂零食
    case firstTreat
    /// 第一次对你慢眨眼
    case firstBlinkBack
    /// 第一次满足她的小请求
    case firstRequest
    /// 第一次送你早餐礼物
    case firstGift
    /// 熟悉了：打开 App 会来迎接你
    case familiar
    /// 亲近了
    case close
    /// 信赖你了
    case devoted
}

/// 她偶尔提的小请求（每天最多一个，在固定的时段出现）。
public enum CatRequest: String, Codable, Sendable, CaseIterable {
    /// 下午想玩逗猫棒
    case play
    /// 傍晚想吃零食
    case treat
    /// 睡前想让你早点睡（开始睡前模式）
    case earlySleep
}

public struct BondState: Codable, Hashable, Sendable {
    public internal(set) var points = 0
    public internal(set) var personality: Personality
    /// 最喜欢被摸的地方（玩家要自己发现）
    public internal(set) var favoriteRegion: PetRegion
    public internal(set) var memories: [CatMemory: Date] = [:]
    /// 生气到什么时候（这段时间不加分，她背对着你）
    public internal(set) var annoyedUntil: Date?
    /// 今天（逻辑日）各来源已经加了几次
    var today: LogicalDay?
    var counts: [BondSource: Int] = [:]
    /// 最近点她 / 摸到讨厌的地方的时间，用来判断是不是烦了
    var recentPokes: [Date] = []
    var fulfilledRequestDay: LogicalDay?
    /// 上一次的反应（下一次尽量不重样）
    var lastReaction: CatReaction?
    var rng: SeededRandom

    /// 新领养的猫：性格和最喜欢的部位由种子决定。
    public static func newCat(seed: UInt64) -> BondState {
        var rng = SeededRandom(seed: seed ^ 0x424F_4E44)
        let personality = Personality.allCases[Int(rng.next() % UInt64(Personality.allCases.count))]
        let favorites: [PetRegion] = [.head, .chin, .cheek, .back]
        let favorite = favorites[Int(rng.next() % UInt64(favorites.count))]
        return BondState(personality: personality, favoriteRegion: favorite, rng: rng)
    }

    public var stage: BondStage { .of(points: points) }
}

/// 一次互动带来的变化。
public struct BondUpdate: Hashable, Sendable {
    public var gained = 0
    /// 刚进入的阶段
    public var newStage: BondStage?
    /// 刚记下的回忆
    public var memories: [CatMemory] = []
    /// 满足了的小请求
    public var fulfilled: CatRequest?

    public init() {}

    mutating func merge(_ other: BondUpdate) {
        gained += other.gained
        newStage = other.newStage ?? newStage
        memories += other.memories
        fulfilled = other.fulfilled ?? fulfilled
    }
}

/// 摸一下的结果。
public struct PetOutcome: Hashable, Sendable {
    public var reaction: PetReaction
    public var update: BondUpdate
    /// 这一下把她惹烦了
    public var becameAnnoyed: Bool
}

extension BondStage {
    /// 回忆册里这个阶段对应的回忆
    var memory: CatMemory? {
        switch self {
        case .newcomer: nil
        case .curious: .cameOut
        case .familiar: .familiar
        case .close: .close
        case .devoted: .devoted
        }
    }
}

enum BondRules {
    /// 每种来源：一次加几分、每天最多几次
    static let gains: [BondSource: (points: Int, cap: Int)] = [
        .dailyVisit: (5, 1), .onTimeWake: (8, 1), .bedtime: (5, 1), .pet: (1, 10),
        .play: (3, 2), .treat: (2, 3), .slowBlink: (1, 3), .request: (4, 1),
    ]
    /// 生气多久
    static let annoyedFor: TimeInterval = 180
    /// 10 秒里点 / 摸讨厌的地方这么多次就烦了
    static let pokesToAnnoy = 7
    static let pokeWindow: TimeInterval = 10
    /// 慢眨眼她眨回来的概率（按阶段）
    static let blinkBack: [BondStage: Double] = [.newcomer: 0.1, .curious: 0.25, .familiar: 0.5, .close: 0.75, .devoted: 0.9]

    static func multiplier(_ source: BondSource, personality: Personality, stage: BondStage) -> Double {
        switch (personality, source) {
        case (.clingy, .pet): 1.5
        case (.aloof, .pet): 0.7
        case (.aloof, .slowBlink): 2
        case (.playful, .play): 1.5
        case (.foodie, .treat): 1.5
        case (.shy, _): stage < .familiar ? 0.8 : 1.2
        default: 1
        }
    }
}

// MARK: - 互动

extension CatWorld {
    public var bond: BondState { state.bond }
    public var bondStage: BondStage { state.bond.stage }

    public func isAnnoyed(at date: Date) -> Bool {
        (state.bond.annoyedUntil ?? .distantPast) > date
    }

    /// 加好感度：每天每种来源有上限；生气的时候不加；跨过阶段时记下回忆。
    @discardableResult
    mutating func addBond(_ source: BondSource, at date: Date) -> BondUpdate {
        var update = BondUpdate()
        let day = catConfig.logicalDay(of: date)
        if state.bond.today != day {
            state.bond.today = day
            state.bond.counts = [:]
        }
        guard let rule = BondRules.gains[source], !isAnnoyed(at: date),
              state.bond.counts[source, default: 0] < rule.cap else { return update }
        state.bond.counts[source, default: 0] += 1
        let before = state.bond.stage
        let gain = max(1, Int((Double(rule.points) * BondRules.multiplier(source, personality: state.bond.personality, stage: before)).rounded()))
        state.bond.points += gain
        update.gained = gain
        let after = state.bond.stage
        if after > before {
            update.newStage = after
            for raw in (before.rawValue + 1)...after.rawValue {
                if let memory = BondStage(rawValue: raw)?.memory { remember(memory, at: date, into: &update) }
            }
        }
        return update
    }

    mutating func remember(_ memory: CatMemory, at date: Date, into update: inout BondUpdate) {
        guard state.bond.memories[memory] == nil else { return }
        state.bond.memories[memory] = date
        update.memories.append(memory)
    }

    /// 摸她的某个部位。还不熟的时候她只是忍着；尾巴永远不喜欢；肚子到亲近以后一半是陷阱。
    public mutating func pet(_ region: PetRegion, at date: Date) -> PetOutcome {
        let stage = state.bond.stage
        var rng = state.bond.rng
        let reaction: PetReaction
        switch region {
        case .tail:
            reaction = .dislikes
        case .belly:
            // 亲近以后一半是陷阱；她自己躺下露肚皮等你的时候，大多是真的让你摸
            let inviting = state.cat.state == .idleDaytime && presence(at: date).activity == .bellyUp
            reaction = stage >= temperament.bellyStage && Self.unit(&rng) < (inviting ? 0.85 : 0.5) ? .loves : .dislikes
        case state.bond.favoriteRegion:
            reaction = stage >= .curious ? .loves : .tolerates
        default:
            reaction = stage >= .familiar ? .likes : .tolerates
        }
        state.bond.rng = rng

        var update = BondUpdate()
        var annoyed = false
        switch reaction {
        case .loves, .likes:
            update = addBond(.pet, at: date)
            if !isAnnoyed(at: date) {
                remember(.firstPet, at: date, into: &update)
                if reaction == .loves { remember(.firstPurr, at: date, into: &update) }
            }
        case .tolerates:
            break
        case .dislikes:
            annoyed = poke(at: date, weight: 3)
        }
        return PetOutcome(reaction: reaction, update: update, becameAnnoyed: annoyed)
    }

    /// 点了她一下（说话）。短时间点太多次她会烦。返回这一下有没有把她惹烦。
    @discardableResult
    public mutating func noteTap(at date: Date) -> Bool {
        poke(at: date, weight: 1)
    }

    private mutating func poke(at date: Date, weight: Int) -> Bool {
        guard !isAnnoyed(at: date) else { return false }
        let recent = state.bond.recentPokes.filter { date.timeIntervalSince($0) < BondRules.pokeWindow }
        state.bond.recentPokes = recent + Array(repeating: date, count: weight)
        guard state.bond.recentPokes.count >= temperament.pokesToAnnoy else { return false }
        state.bond.annoyedUntil = date.addingTimeInterval(temperament.annoyedFor)
        state.bond.recentPokes = []
        return true
    }

    /// 陪她玩了一局逗猫棒。
    @discardableResult
    public mutating func playedWithWand(at date: Date) -> BondUpdate {
        var update = addBond(.play, at: date)
        remember(.firstPlay, at: date, into: &update)
        fulfill(.play, at: date, into: &update)
        return update
    }

    /// 喂一份零食（花 `EconomyEngine.treatPrice` 小鱼干）。小鱼干不够时抛 `EconomyError.insufficientFish`。
    @discardableResult
    public mutating func giveTreat(at date: Date) throws -> BondUpdate {
        var economyState = state.economy
        try economy.spend(EconomyEngine.treatPrice, state: &economyState)
        state.economy = economyState
        var update = addBond(.treat, at: date)
        remember(.firstTreat, at: date, into: &update)
        fulfill(.treat, at: date, into: &update)
        return update
    }

    /// 对她慢慢眨眼（猫的"我信任你"）。她按阶段的概率眨回来。
    public mutating func slowBlink(at date: Date) -> (returned: Bool, update: BondUpdate) {
        var rng = state.bond.rng
        var chance = BondRules.blinkBack[state.bond.stage] ?? 0.5
        if state.bond.personality == .aloof { chance += 0.1 }
        let returned = !isAnnoyed(at: date) && Self.unit(&rng) < chance
        state.bond.rng = rng
        guard returned else { return (false, BondUpdate()) }
        var update = addBond(.slowBlink, at: date)
        remember(.firstBlinkBack, at: date, into: &update)
        return (true, update)
    }

    // MARK: 小请求

    /// 此刻她有没有在提小请求：每天由种子决定要不要提、提什么（性格会偏向某一种），只在对应的时段里出现；
    /// 满足过了、还没到好奇阶段、在生气、不是白天待机时都没有。
    public func request(at date: Date) -> CatRequest? {
        guard state.bond.stage >= .curious, state.cat.state == .idleDaytime, !isAnnoyed(at: date) else { return nil }
        let day = catConfig.logicalDay(of: date)
        guard state.bond.fulfilledRequestDay != day else { return nil }
        var rng = SeededRandom(seed: Self.mix(state.lifeSeed, UInt64(day.year * 10000 + day.month * 100 + day.day), 0x5245_51))
        guard Self.unit(&rng) < 0.7 else { return nil }
        let kinds: [CatRequest] = switch state.bond.personality {
        case .playful: [.play, .play, .treat, .earlySleep]
        case .foodie: [.treat, .treat, .play, .earlySleep]
        case .clingy: [.earlySleep, .play, .treat]
        default: CatRequest.allCases
        }
        let kind = kinds[Int(rng.next() % UInt64(kinds.count))]
        let slot = lifeSlot(at: date)
        let active = switch kind {
        case .play: slot == .afternoon
        case .treat: slot == .evening
        case .earlySleep: slot == .late
        }
        return active ? kind : nil
    }

    private mutating func fulfill(_ kind: CatRequest, at date: Date, into update: inout BondUpdate) {
        guard request(at: date) == kind else { return }
        state.bond.fulfilledRequestDay = catConfig.logicalDay(of: date)
        let gained = addBond(.request, at: date)
        update.gained += gained.gained
        update.newStage = gained.newStage ?? update.newStage
        update.memories += gained.memories
        remember(.firstRequest, at: date, into: &update)
        update.fulfilled = kind
    }

    /// 开始睡前模式：如果她正想让你早点睡，就算满足了。
    mutating func bedtimeStarted(at date: Date) -> BondUpdate {
        var update = BondUpdate()
        fulfill(.earlySleep, at: date, into: &update)
        return update
    }

    #if DEBUG
    /// 只在 Debug 版本里有：直接设好感分数（`-debugBond 600` 启动参数，看不同阶段的样子）。
    public mutating func debugSetBond(_ points: Int) {
        state.bond.points = max(0, points)
    }
    #endif
}
