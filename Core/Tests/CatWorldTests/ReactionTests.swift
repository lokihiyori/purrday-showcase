import CatEngine
@testable import Economy
import Foundation
import Testing
@testable import CatWorld

private func world(points: Int, personality: Personality = .clingy, favorite: PetRegion = .chin) throws -> CatWorld {
    var world = try makeWorld()
    world.state.bond.points = points
    world.state.bond.personality = personality
    world.state.bond.favoriteRegion = favorite
    return world
}

@Suite("她的反应：同一种互动有好几种动作")
struct ReactionTests {
    @Test("每种互动都至少有两种可能的反应，连着两次不重样")
    func variety() throws {
        let triggers: [ReactionTrigger] = [
            .pet(.head, .loves), .pet(.chin, .likes), .pet(.back, .tolerates), .pet(.tail, .dislikes),
            .treat, .pounce(0), .pounce(2), .tap, .blink(returned: true), .blink(returned: false),
        ]
        for trigger in triggers {
            var world = try world(points: 600)
            var seen = Set<CatReaction>()
            var last: CatReaction?
            for i in 0..<40 {
                let reaction = world.react(to: trigger, at: t(2, 16, 0, i))
                #expect(reaction != last, "\(trigger) 连着两次一样")
                seen.insert(reaction)
                last = reaction
            }
            #expect(seen.count >= 2, "\(trigger) 只有一种反应")
        }
    }

    @Test("摸下巴会抬下巴；亲近以后才会踩奶、翻肚皮；不熟时只会僵住、闻手、往后缩")
    func petReactions() {
        let chin = Set(CatWorld.reactionWeights(.pet(.chin, .loves), stage: .familiar, personality: .clingy, activity: .sit).map(\.0))
        #expect(chin.contains(.chinUp))
        #expect(!chin.contains(.knead) && !chin.contains(.rollOver))
        let close = Set(CatWorld.reactionWeights(.pet(.head, .loves), stage: .close, personality: .clingy, activity: .sit).map(\.0))
        #expect(close.isSuperset(of: [.leanIn, .headbutt, .knead, .rollOver, .flop]))
        let stranger = Set(CatWorld.reactionWeights(.pet(.head, .tolerates), stage: .newcomer, personality: .shy, activity: .sit).map(\.0))
        #expect(stranger == [.freeze, .scoot])
        let curious = Set(CatWorld.reactionWeights(.pet(.head, .tolerates), stage: .curious, personality: .shy, activity: .sit).map(\.0))
        #expect(curious.contains(.sniffHand))
    }

    @Test("不喜欢：摸尾巴是嘟囔或拍你；亲近以后摸肚子的陷阱是抱住咬一口")
    func dislikes() {
        let tail = Set(CatWorld.reactionWeights(.pet(.tail, .dislikes), stage: .close, personality: .aloof, activity: .sit).map(\.0))
        #expect(tail == [.grumble, .swat])
        let belly = CatWorld.reactionWeights(.pet(.belly, .dislikes), stage: .close, personality: .clingy, activity: .sit)
        #expect(belly.max { $0.1 < $1.1 }?.0 == .loveBite)
    }

    @Test("性格影响吃相和玩法：贪吃的爱讨要，胆小的先闻、叼走，好动的拨着玩、满屋子跑")
    func personalities() {
        func weight(_ trigger: ReactionTrigger, _ personality: Personality, _ reaction: CatReaction) -> Double {
            CatWorld.reactionWeights(trigger, stage: .familiar, personality: personality, activity: .sit).first { $0.0 == reaction }?.1 ?? 0
        }
        #expect(weight(.treat, .foodie, .beg) > weight(.treat, .aloof, .beg))
        #expect(weight(.treat, .shy, .carryAway) > weight(.treat, .clingy, .carryAway))
        #expect(weight(.treat, .playful, .batTreat) > weight(.treat, .foodie, .batTreat))
        #expect(weight(.pounce(1), .playful, .zoomies) > weight(.pounce(1), .shy, .zoomies))
        #expect(weight(.tap, .clingy, .comeCloser) > weight(.tap, .aloof, .comeCloser))
    }

    @Test("刚到家点她：只会吓一跳或僵住")
    func newcomerTap() {
        let reactions = Set(CatWorld.reactionWeights(.tap, stage: .newcomer, personality: .playful, activity: .sit).map(\.0))
        #expect(reactions == [.freeze, .scoot])
    }
}

@Suite("她自己会做的新事情：玩玩具、露肚皮、踩奶")
struct NewActivityTests {
    /// 一整天里（每 15 分钟看一次）她做过哪些事
    private func activities(_ world: CatWorld, day: Int) -> [CatPresence] {
        var result: [CatPresence] = []
        var date = t(day, 8)
        while date < t(day, 22) {
            result.append(world.presence(at: date))
            date = date.addingTimeInterval(LifeSchedule.block)
        }
        return result
    }

    @Test("有能当玩具的礼物、过了刚到家的阶段，她才会自己玩玩具；玩的是你有的东西")
    func toys() throws {
        var world = try world(points: 300)
        let without = (2...8).flatMap { activities(world, day: $0) }
        #expect(!without.contains { $0.activity == .toy })

        world.state.economy.items.append(OwnedItem(id: 9001, catalogID: "gift.yarn_ball", obtainedAt: t(1, 20), source: .gift))
        let with = (2...8).flatMap { activities(world, day: $0) }
        let playing = with.filter { $0.activity == .toy }
        #expect(!playing.isEmpty)
        #expect(playing.allSatisfy { $0.prop == "gift.yarn_ball" })
        #expect(playing.allSatisfy { [.bat, .toyKick, .crouch].contains($0.pose) })

        world.state.bond.points = 0
        #expect(!(2...8).flatMap { activities(world, day: $0) }.contains { $0.activity == .toy })
    }

    @Test("露肚皮等你要到亲近以后，而且就在你面前；踩奶要到熟悉以后")
    func bellyAndKnead() throws {
        let familiar = try world(points: 300)
        let early = (2...12).flatMap { activities(familiar, day: $0) }
        #expect(!early.contains { $0.activity == .bellyUp })
        #expect(early.contains { $0.activity == .knead && $0.pose == .knead })

        let close = try world(points: 600)
        let later = (2...12).flatMap { activities(close, day: $0) }
        let belly = later.filter { $0.activity == .bellyUp }
        #expect(!belly.isEmpty)
        #expect(belly.allSatisfy { $0.pose == .bellyUp && $0.spot.y >= 0.85 })

        let stranger = try world(points: 0)
        #expect(!(2...12).flatMap { activities(stranger, day: $0) }.contains { $0.activity == .knead })
    }

    @Test("她躺着露肚皮等你的时候，摸肚子大多是真的让摸")
    func invitingBelly() throws {
        var world = try world(points: 600)
        let moment = try #require((2...30).lazy.flatMap { day in
            stride(from: 8, to: 22, by: 1).map { t(day, $0) }
        }.first { world.presence(at: $0).activity == .bellyUp })
        let loved = (0..<200).filter { _ in world.pet(.belly, at: moment).reaction == .loves }.count
        #expect(loved > 140)
    }
}
