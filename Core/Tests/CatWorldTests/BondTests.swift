import CatEngine
import Economy
import Foundation
import Testing
@testable import CatWorld

private func bondWorld(points: Int = 0, personality: Personality = .clingy, favorite: PetRegion = .chin,
                       fish: Int = 100) throws -> CatWorld {
    var world = try makeWorld()
    world.state.bond.points = points
    world.state.bond.personality = personality
    world.state.bond.favoriteRegion = favorite
    world.state.economy = EconomyState(wallet: Wallet(fish: fish), items: world.state.economy.items)
    return world
}

@Suite("好感度：阶段和加分")
struct BondGainTests {
    @Test("五个阶段的门槛")
    func stages() {
        #expect(BondStage.of(points: 0) == .newcomer)
        #expect(BondStage.of(points: 49) == .newcomer)
        #expect(BondStage.of(points: 50) == .curious)
        #expect(BondStage.of(points: 200) == .familiar)
        #expect(BondStage.of(points: 500) == .close)
        #expect(BondStage.of(points: 5000) == .devoted)
    }

    @Test("新领养的猫：性格和最喜欢的部位由种子决定，同一个种子一样")
    func newCat() {
        #expect(BondState.newCat(seed: 7) == BondState.newCat(seed: 7))
        let regions = Set((1...40).map { BondState.newCat(seed: UInt64($0)).favoriteRegion })
        #expect(regions.count > 1)
        #expect(!regions.contains(.tail) && !regions.contains(.belly))
    }

    @Test("每天第一次打开 App +5，同一天再打开不加；第二天又加")
    func dailyVisit() throws {
        var world = try bondWorld(personality: .clingy)
        #expect(world.foreground(at: t(2, 9), isPlus: false).bond.gained == 5)
        #expect(world.foreground(at: t(2, 12), isPlus: false).bond.gained == 0)
        #expect(world.foreground(at: t(3, 9), isPlus: false).bond.gained == 5)
        #expect(world.bond.points == 10)
    }

    @Test("准时起床 +8，并记下第一次送礼物")
    func onTimeWake() throws {
        var world = try bondWorld()
        try world.setAlarm(weekdayAlarm(), isPlus: false)
        let update = world.ingest(onTimeMorning(2), isPlus: false)
        #expect(update.bond.gained == 8)
        #expect(update.bond.memories.contains(.firstGift))
        #expect(world.bond.memories[.firstGift] == t(2, 7, 1))
    }

    @Test("摸喜欢的地方每天最多加 10 次")
    func petCap() throws {
        var world = try bondWorld(points: 200, personality: .playful)
        for i in 0..<14 {
            _ = world.pet(.head, at: t(2, 10, 0, i * 3))
        }
        #expect(world.bond.points == 210)
        #expect(world.pet(.head, at: t(3, 10)).update.gained == 1)
    }

    @Test("性格：黏人的猫被摸加得更多")
    func personality() throws {
        var clingy = try bondWorld(points: 200, personality: .clingy)
        var aloof = try bondWorld(points: 200, personality: .aloof)
        #expect(clingy.pet(.head, at: t(2, 10)).update.gained == 2)
        #expect(aloof.pet(.head, at: t(2, 10)).update.gained == 1)
    }

    @Test("跨过阶段：记下回忆（好奇了、熟悉了……）")
    func stageMemories() throws {
        var world = try bondWorld(points: 47)
        let update = world.foreground(at: t(2, 9), isPlus: false)
        #expect(update.bond.newStage == .curious)
        #expect(update.bond.memories == [.cameOut])
        #expect(world.bond.memories[.cameOut] == t(2, 9))
    }
}

@Suite("好感度：摸、生气")
struct BondPetTests {
    @Test("刚到家：哪里都只是忍着，不加分")
    func newcomer() throws {
        var world = try bondWorld(points: 0, favorite: .chin)
        for region in [PetRegion.head, .chin, .back] {
            let outcome = world.pet(region, at: t(2, 10))
            #expect(outcome.reaction == .tolerates)
            #expect(outcome.update.gained == 0)
        }
    }

    @Test("好奇阶段：最喜欢的地方会打呼噜，记下第一次")
    func favorite() throws {
        var world = try bondWorld(points: 60, favorite: .cheek)
        let outcome = world.pet(.cheek, at: t(2, 10))
        #expect(outcome.reaction == .loves)
        #expect(outcome.update.memories == [.firstPet, .firstPurr])
        #expect(world.pet(.head, at: t(2, 10, 1)).reaction == .tolerates) // 别的地方要到熟悉才行
    }

    @Test("熟悉以后头和背都喜欢；尾巴永远不喜欢；肚子到亲近以后时好时坏")
    func regions() throws {
        var world = try bondWorld(points: 300, favorite: .chin)
        #expect(world.pet(.head, at: t(2, 10)).reaction == .likes)
        #expect(world.pet(.back, at: t(2, 10, 1)).reaction == .likes)
        #expect(world.pet(.tail, at: t(2, 10, 2)).reaction == .dislikes)
        #expect(world.pet(.belly, at: t(2, 11)).reaction == .dislikes)

        var close = try bondWorld(points: 600)
        let bellies = (0..<20).map { close.pet(.belly, at: t(3, 10, $0)).reaction }
        #expect(bellies.contains(.loves) && bellies.contains(.dislikes))
    }

    @Test("10 秒里连着点很多下，或者摸讨厌的地方：她烦了，3 分钟内不加分")
    func annoyed() throws {
        var world = try bondWorld(points: 300)
        var annoyed = false
        for i in 0..<7 { annoyed = world.noteTap(at: t(2, 10, 0, i)) || annoyed }
        #expect(annoyed)
        #expect(world.isAnnoyed(at: t(2, 10, 2)))
        #expect(world.pet(.head, at: t(2, 10, 2)).update.gained == 0)
        #expect(!world.isAnnoyed(at: t(2, 10, 4)))
        #expect(world.pet(.head, at: t(2, 10, 4)).update.gained > 0)

        var other = try bondWorld(points: 300)
        _ = other.pet(.tail, at: t(2, 10))
        _ = other.pet(.tail, at: t(2, 10, 0, 3))
        #expect(other.pet(.tail, at: t(2, 10, 0, 6)).becameAnnoyed)
    }
}

@Suite("好感度：零食、逗猫棒、慢眨眼、小请求")
struct BondInteractionTests {
    @Test("零食花 3 条小鱼干；不够时报错，不加分")
    func treat() throws {
        var world = try bondWorld(fish: 4)
        let update = try world.giveTreat(at: t(2, 18))
        #expect(world.state.economy.wallet.fish == 1)
        #expect(update.gained == 2)
        #expect(update.memories.contains(.firstTreat))
        #expect(throws: EconomyError.insufficientFish(needed: 3, balance: 1)) { try world.giveTreat(at: t(2, 18, 1)) }
    }

    @Test("慢眨眼：越熟越会眨回来")
    func slowBlink() throws {
        var stranger = try bondWorld(points: 0, personality: .clingy)
        var friend = try bondWorld(points: 1200, personality: .clingy)
        let strangerBack = (0..<100).filter { stranger.slowBlink(at: t(2, 10, 0, $0)).returned }.count
        let friendBack = (0..<100).filter { friend.slowBlink(at: t(2, 10, 0, $0)).returned }.count
        #expect(strangerBack < 25)
        #expect(friendBack > 75)
    }

    @Test("小请求：每天由种子决定，只在对应时段出现；满足后加分、记下回忆，当天不再提")
    func requests() throws {
        // 找一天她下午想玩
        var world = try bondWorld(points: 100, personality: .playful)
        let day = try #require((2...30).first { world.request(at: t($0, 16)) == .play })
        #expect(world.request(at: t(day, 10)) == nil) // 上午不提
        #expect(world.request(at: t(day, 16)) == world.request(at: t(day, 16)))
        let update = world.playedWithWand(at: t(day, 16))
        #expect(update.fulfilled == .play)
        #expect(update.gained == 5 + 4) // 逗猫棒（好动 ×1.5 → 5）+ 请求
        #expect(update.memories.contains(.firstRequest))
        #expect(world.request(at: t(day, 16, 30)) == nil)
    }

    @Test("想让你早点睡：睡前时段开始睡前模式就算满足")
    func earlySleep() throws {
        var world = try bondWorld(points: 100, personality: .clingy)
        let day = try #require((2...40).first { world.request(at: t($0, 22, 30)) == .earlySleep })
        world.ingest([LoggedEvent(id: "bed", event: .bedtimeTimerStarted(duration: 1800, at: t(day, 22, 30)))], isPlus: false)
        #expect(world.bond.memories[.firstRequest] == t(day, 22, 30))
    }

    @Test("还没到好奇阶段、生气的时候都不提请求")
    func noRequest() throws {
        let world = try bondWorld(points: 0)
        #expect((2...30).allSatisfy { world.request(at: t($0, 16)) == nil && world.request(at: t($0, 19)) == nil })
    }
}

@Suite("好感度：作息和存档")
struct BondLifeTests {
    @Test("刚到家时待在房间后面（离你远）")
    func newcomerStaysBack() throws {
        let world = try bondWorld(points: 0)
        var date = t(2, 8)
        while date < t(2, 22) {
            let p = world.presence(at: date)
            if [.sit, .loaf, .groom].contains(p.activity), case let .floor(y) = p.depth {
                #expect(y <= 0.82)
            }
            date = date.addingTimeInterval(LifeSchedule.block)
        }
    }

    @Test("旧存档没有好感度：照样能读，性格由作息种子决定")
    func oldSave() throws {
        let world = try bondWorld(points: 30)
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(world.state)) as? [String: Any])
        json.removeValue(forKey: "bond")
        let old = try JSONDecoder().decode(WorldState.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old.bond.points == 0)
        #expect(old.bond == BondState.newCat(seed: old.lifeSeed))
    }
}
