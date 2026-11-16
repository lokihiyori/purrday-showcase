import CatEngine
@testable import Economy
import Foundation
import Testing
@testable import CatWorld

/// 一只好感分数是 points 的某种猫（直接换过去，不走领养）
private func world(_ kind: CatKind, points: Int) throws -> CatWorld {
    var world = try makeWorld()
    world.state.activeCat = kind
    world.state.adoptedCats = [.pudding, kind]
    world.state.bond.points = points
    if let personality = kind.personality { world.state.bond.personality = personality }
    return world
}

private func weight(_ trigger: ReactionTrigger, _ kind: CatKind, _ reaction: CatReaction, stage: BondStage = .close) -> Double {
    let personality = kind.personality ?? .playful
    return CatWorld.reactionWeights(trigger, stage: stage, personality: personality, activity: .sit, kind: kind)
        .first { $0.0 == reaction }?.1 ?? 0
}

/// 某种反应在所有可能的反应里占多少
private func share(_ trigger: ReactionTrigger, _ kind: CatKind, _ reaction: CatReaction, stage: BondStage = .close) -> Double {
    let all = CatWorld.reactionWeights(trigger, stage: stage, personality: kind.personality ?? .playful, activity: .sit, kind: kind)
    return (all.first { $0.0 == reaction }?.1 ?? 0) / all.reduce(0) { $0 + $1.1 }
}

@Suite("每种猫的脾气不一样")
struct TemperamentTests {
    @Test("点她：暹罗多半叫一声或者走过来；长毛猫多半甩甩尾巴不理你")
    func tap() {
        #expect(share(.tap, .siamese, .meow) + share(.tap, .siamese, .comeCloser) > 0.6)
        #expect(share(.tap, .fluffy, .tailFlick) > share(.tap, .fluffy, .meow) * 3)
        #expect(share(.tap, .siamese, .tailFlick) < 0.05)
        #expect(share(.tap, .fluffy, .comeCloser) < share(.tap, .pudding, .comeCloser))
    }

    @Test("摸到喜欢的地方：暹罗站起来蹭你；长毛猫揣手打呼噜、慢慢倒下，很少翻肚皮；布丁最爱翻肚皮")
    func petting() {
        let pet = ReactionTrigger.pet(.head, .loves)
        #expect(share(pet, .siamese, .headbutt) > share(pet, .fluffy, .headbutt) * 2)
        #expect(share(pet, .fluffy, .purrLoaf) + share(pet, .fluffy, .flop) > 0.5)
        #expect(share(pet, .fluffy, .rollOver) < 0.05)
        #expect(share(pet, .pudding, .rollOver) > share(pet, .siamese, .rollOver))
    }

    @Test("零食：布丁最爱讨要；长毛猫先闻一闻，不讨要；逗猫：暹罗爱满屋子跑，长毛猫坐着拍，布丁常扑空")
    func treatsAndPlay() {
        #expect(weight(.treat, .pudding, .beg) > weight(.treat, .fluffy, .beg) * 3)
        #expect(share(.treat, .fluffy, .sniffFirst) > share(.treat, .siamese, .sniffFirst) * 2)
        #expect(share(.pounce(1), .siamese, .zoomies) > share(.pounce(1), .fluffy, .zoomies) * 4)
        #expect(share(.pounce(1), .fluffy, .batAtIt) > share(.pounce(1), .siamese, .batAtIt))
        #expect(share(.pounce(1), .pudding, .miss) > share(.pounce(1), .siamese, .miss))
    }

    @Test("慢眨眼：长毛猫常常只是把眼睛移开、打个哈欠（猫的另一种放松）")
    func blink() {
        #expect(share(.blink(returned: true), .fluffy, .lookAway) > share(.blink(returned: true), .siamese, .lookAway) * 3)
        #expect(share(.blink(returned: true), .siamese, .blinkBack) > 0.7)
    }

    @Test("多久会烦：长毛猫 5 下就烦、烦四分半；暹罗 9 下才烦、一分半就好")
    func annoyance() throws {
        var fluffy = try world(.fluffy, points: 300)
        let fluffyTaps = (0..<5).map { fluffy.noteTap(at: t(2, 10, 0, $0)) }
        #expect(fluffyTaps == [false, false, false, false, true])
        #expect(fluffy.isAnnoyed(at: t(2, 10, 4)))
        #expect(!fluffy.isAnnoyed(at: t(2, 10, 5)))

        var siamese = try world(.siamese, points: 300)
        let siameseTaps = (0..<9).map { siamese.noteTap(at: t(2, 10, 0, $0)) }
        #expect(siameseTaps == Array(repeating: false, count: 8) + [true])
        #expect(siamese.isAnnoyed(at: t(2, 10, 1)))
        #expect(!siamese.isAnnoyed(at: t(2, 10, 2)))
    }

    @Test("肚子：长毛猫到亲近也不让摸，要到信赖")
    func belly() throws {
        var close = try world(.fluffy, points: 600)
        let early = (0..<20).map { close.pet(.belly, at: t(3 + $0, 10)).reaction }
        #expect(early.allSatisfy { $0 == .dislikes })
        var devoted = try world(.fluffy, points: 1200)
        let later = (0..<40).map { devoted.pet(.belly, at: t(3 + $0, 10)).reaction }
        #expect(later.contains(.loves))
    }

    /// 一周里（每 15 分钟看一次，8 点到 22 点）各种事做了多少次
    private func week(_ world: CatWorld) -> [CatActivity: Int] {
        var counts: [CatActivity: Int] = [:]
        for day in 2...8 {
            var date = t(day, 8)
            while date < t(day, 22) {
                if let activity = world.presence(at: date).activity { counts[activity, default: 0] += 1 }
                date = date.addingTimeInterval(LifeSchedule.block)
            }
        }
        return counts
    }

    @Test("自己过日子：暹罗到处跑、玩得多；长毛猫趴着、睡觉、舔毛得多")
    func life() throws {
        let siamese = week(try world(.siamese, points: 300))
        let fluffy = week(try world(.fluffy, points: 300))
        func active(_ c: [CatActivity: Int]) -> Int { c[.explore, default: 0] + c[.play, default: 0] }
        func lazy(_ c: [CatActivity: Int]) -> Int { c[.loaf, default: 0] + c[.nap, default: 0] + c[.groom, default: 0] }
        #expect(active(siamese) > active(fluffy) * 2)
        #expect(lazy(fluffy) > lazy(siamese))
    }

    @Test("每只猫的作息不是同一份：同一时刻，三只猫不总在做同一件事")
    func differentSchedules() throws {
        let cats = try CatKind.allCases.map { try world($0, points: 300) }
        var same = 0, total = 0
        var date = t(2, 8)
        while date < t(4, 22) {
            let activities = cats.map { $0.presence(at: date).activity }
            total += 1
            if Set(activities).count == 1 { same += 1 }
            date = date.addingTimeInterval(LifeSchedule.block)
        }
        #expect(Double(same) / Double(total) < 0.5)
    }

    @Test("话多的暹罗常常自己叫一声；长毛猫几乎不叫；刚到家、睡着时都不叫")
    func calls() throws {
        func calls(_ world: CatWorld) -> Int {
            var count = 0
            var date = t(2, 8)
            while date < t(2, 22) {
                if world.callsOut(at: date) { count += 1 }
                date = date.addingTimeInterval(LifeSchedule.beat)
            }
            return count
        }
        let siamese = calls(try world(.siamese, points: 300))
        let fluffy = calls(try world(.fluffy, points: 300))
        #expect(siamese > 200)
        #expect(fluffy < siamese / 8)
        #expect(calls(try world(.siamese, points: 0)) == 0)
        let chatty = try world(.siamese, points: 300)
        #expect(chatty.callsOut(at: t(2, 16)) == chatty.callsOut(at: t(2, 16)))
    }

    @Test("迎接：暹罗好奇阶段就来，布丁要熟悉，长毛猫要到信赖")
    func greeting() {
        #expect(CatKind.siamese.temperament.greetStage == .curious)
        #expect(CatKind.pudding.temperament.greetStage == .familiar)
        #expect(CatKind.fluffy.temperament.greetStage == .devoted)
    }
}
