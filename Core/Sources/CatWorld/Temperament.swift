import Economy
import Foundation

// 每种猫的脾气（docs/cat-life.md 4.3）：不只是换一套图。同样的互动，她们挑的反应不一样；
// 自己过日子时爱做的事不一样；多久会烦、怎么迎接你、爱不爱叫也不一样。
// 动作的快慢、幅度这些"怎么演"的差别在 App 里（Features/Room/CatStyle.swift）。

/// 一种猫的脾气。数字都是"相对布丁"的倍数，没写的是 1。
public struct Temperament: Sendable {
    /// 各种反应更常 / 更少出现
    var reactions: [CatReaction: Double] = [:]
    /// 自己过日子时各种事更爱 / 更不爱做
    var activities: [CatActivity: Double] = [:]
    /// 每一拍做小动作（打哈欠、甩尾巴、左右看）的机会
    var fidgetChance = 0.5
    /// 醒着没事时，每一拍自己叫一声的机会
    var callChance = 0.05
    /// 10 秒里被戳多少下会烦
    var pokesToAnnoy = 7
    /// 烦多久
    var annoyedFor: TimeInterval = 180
    /// 到哪个阶段肚子才（有时）让摸
    var bellyStage = BondStage.close
    /// 到哪个阶段你回来时她会跑过来迎接
    public var greetStage = BondStage.familiar

    /// 布丁：憨憨的、贪吃、爱翻肚皮，扑东西经常扑空
    static let pudding = Temperament(
        reactions: [.eatHappily: 1.5, .beg: 2, .rollOver: 1.5, .purrLoaf: 1.3, .miss: 1.8, .bunnyKick: 1.3, .carryAway: 0.5],
        activities: [.eat: 1.5, .nap: 1.2, .sunbathe: 1.2, .bellyUp: 1.5, .knead: 1.3]
    )

    /// 暹罗：黏人、话多、轻快。爱叫、爱跟着你蹭，到处跑；不容易烦，烦了也好得快
    static let siamese = Temperament(
        reactions: [.meow: 3, .chirp: 2, .comeCloser: 2.5, .headbutt: 2.2, .leanIn: 1.2, .zoomies: 1.6, .catchIt: 1.3,
                    .tailFlick: 0.3, .freeze: 0.6, .purrLoaf: 0.6, .flop: 0.7, .beg: 1.5, .blinkBack: 1.3, .lookAway: 0.4,
                    .sniffFirst: 0.6, .carryAway: 0.4],
        activities: [.explore: 1.7, .play: 1.7, .toy: 1.5, .watch: 1.3, .perch: 1.4, .scratch: 1.3, .sit: 1.2,
                     .nap: 0.7, .loaf: 0.5, .hide: 0.5, .sunbathe: 0.8],
        fidgetChance: 0.7,
        callChance: 0.3,
        pokesToAnnoy: 9,
        annoyedFor: 90,
        greetStage: .curious
    )

    /// 长毛猫：高冷、慢悠悠。多半是揣手打呼噜、慢慢倒下，很少翻肚皮、很少叫；
    /// 爱趴着、晒太阳、舔毛；容易烦，烦得久；你回来她不跑过来，只在原地对你眨眨眼
    static let fluffy = Temperament(
        reactions: [.purrLoaf: 2.5, .flop: 2, .knead: 1.4, .tailFlick: 3, .headTilt: 1.5, .lookAway: 3, .yawn: 2,
                    .batAtIt: 2.2, .sniffFirst: 2, .grumble: 1.5,
                    .meow: 0.4, .chirp: 0.6, .comeCloser: 0.3, .rollOver: 0.25, .headbutt: 0.6, .zoomies: 0.2,
                    .bunnyKick: 0.5, .catchIt: 0.7, .beg: 0.3, .swat: 0.7],
        activities: [.loaf: 2, .nap: 1.4, .sunbathe: 1.7, .groom: 1.9, .perch: 1.2, .watch: 1.2,
                     .play: 0.35, .explore: 0.6, .toy: 0.5, .bellyUp: 0.3, .scratch: 0.7],
        fidgetChance: 0.35,
        callChance: 0.02,
        pokesToAnnoy: 5,
        annoyedFor: 270,
        bellyStage: .devoted,
        greetStage: .devoted
    )
}

extension CatKind {
    public var temperament: Temperament {
        switch self {
        case .pudding: .pudding
        case .siamese: .siamese
        case .fluffy: .fluffy
        }
    }
}

extension CatWorld {
    /// 现在陪着你的那只猫的脾气
    public var temperament: Temperament { state.activeCat.temperament }

    /// 这一拍她会不会自己叫一声（醒着、白天待机、过了刚到家的阶段、没在生气时）。
    /// 由种子和时间算出来，同一拍问几次都一样。话多的暹罗常叫，长毛猫几乎不叫。
    public func callsOut(at date: Date) -> Bool {
        guard state.cat.state == .idleDaytime, state.bond.stage >= .curious, !isAnnoyed(at: date) else { return false }
        let now = presence(at: date)
        guard ![.nap, .sunbathe, .hide].contains(now.activity ?? .sit) else { return false }
        let beat = Self.index(of: date, step: LifeSchedule.beat)
        var rng = SeededRandom(seed: Self.mix(catSeed, UInt64(bitPattern: Int64(beat)), 0x4341_4C4C))
        return Self.unit(&rng) < temperament.callChance
    }

    /// 作息用的种子：每只猫不一样（布丁沿用存档里的，保证老存档的布丁还在做原来那件事）
    var catSeed: UInt64 {
        switch state.activeCat {
        case .pudding: state.lifeSeed
        case .siamese: Self.mix(state.lifeSeed, 1, 0x4B49_4E44)
        case .fluffy: Self.mix(state.lifeSeed, 2, 0x4B49_4E44)
        }
    }
}
