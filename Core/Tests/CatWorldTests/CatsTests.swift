import CatEngine
@testable import Economy
import Foundation
import Testing
@testable import CatWorld

@Suite("不止一只猫：领养、换猫")
struct CatsTests {
    private func world(points: Int, fish: Int = 0) throws -> CatWorld {
        var world = try makeWorld()
        world.state.bond.points = points
        world.state.economy = EconomyState(wallet: Wallet(fish: fish), items: world.state.economy.items)
        return world
    }

    @Test("一开始只有布丁；暹罗要和一只猫到熟悉才来，长毛猫要 300 小鱼干")
    func availability() throws {
        let fresh = try world(points: 0)
        #expect(fresh.activeCat == .pudding)
        #expect(fresh.adoptedCats == [.pudding])
        #expect(fresh.availability(of: .pudding) == .active)
        #expect(fresh.availability(of: .siamese) == .locked)
        #expect(fresh.availability(of: .fluffy) == .locked)

        #expect(try world(points: 200).availability(of: .siamese) == .adoptable)
        #expect(try world(points: 0, fish: 300).availability(of: .fluffy) == .adoptable)
        #expect(try world(points: 0, fish: 299).availability(of: .fluffy) == .locked)
    }

    @Test("领养暹罗：不花钱，她换出来陪你，从刚到家开始，性格是黏人；布丁的好感度留着")
    func adoptByBond() throws {
        var world = try world(points: 250, fish: 10)
        world.state.bond.memories[.firstPet] = t(1, 20)
        try world.adopt(.siamese, at: t(2, 10))
        #expect(world.activeCat == .siamese)
        #expect(world.adoptedCats == [.pudding, .siamese])
        #expect(world.state.economy.wallet.fish == 10)
        #expect(world.bondStage == .newcomer)
        #expect(world.bond.personality == .clingy)
        #expect(world.bond.memories.isEmpty)
        #expect(world.bond.points > 0) // 今天第一次见她
        #expect(world.availability(of: .pudding) == .resting)
        #expect(world.bondStage(of: .pudding) == .familiar)

        try world.switchCat(to: .pudding, at: t(2, 11))
        #expect(world.activeCat == .pudding)
        #expect(world.bond.memories[.firstPet] == t(1, 20))
        #expect(world.bond.points >= 250)
        #expect(world.availability(of: .siamese) == .resting)
        #expect(world.bondStage(of: .siamese) == .newcomer)
    }

    @Test("领养长毛猫花 300 小鱼干；不够时报错，什么都不变")
    func adoptWithFish() throws {
        var poor = try world(points: 0, fish: 120)
        #expect(throws: EconomyError.insufficientFish(needed: 300, balance: 120)) { try poor.adopt(.fluffy, at: t(2, 10)) }
        #expect(poor.adoptedCats == [.pudding])
        #expect(poor.state.economy.wallet.fish == 120)

        var rich = try world(points: 0, fish: 320)
        try rich.adopt(.fluffy, at: t(2, 10))
        #expect(rich.state.economy.wallet.fish == 20)
        #expect(rich.activeCat == .fluffy)
        #expect(rich.bond.personality == .aloof)
    }

    @Test("条件不够不能领养；没领养的不能换；领养过的不能再领养")
    func guards() throws {
        var world = try world(points: 0)
        #expect(throws: WorldError.catNotAvailable(.siamese)) { try world.adopt(.siamese, at: t(2, 10)) }
        #expect(throws: WorldError.catNotAvailable(.siamese)) { try world.switchCat(to: .siamese, at: t(2, 10)) }
        world.state.bond.points = 300
        try world.adopt(.siamese, at: t(2, 10))
        #expect(throws: WorldError.catNotAvailable(.siamese)) { try world.adopt(.siamese, at: t(2, 11)) }
        #expect(throws: WorldError.catNotAvailable(.pudding)) { try world.adopt(.pudding, at: t(2, 11)) }
    }

    @Test("和任意一只猫熟了都算：带着暹罗到熟悉，布丁还不熟也能解锁")
    func bestStage() throws {
        var world = try world(points: 220)
        try world.adopt(.siamese, at: t(2, 10))
        #expect(world.bondStage == .newcomer)
        #expect(world.bestBondStage == .familiar)
    }

    @Test("每只猫自己的好感度：陪暹罗加的分不算到布丁头上；存档读回来都在")
    func separateBondsAndSave() throws {
        var world = try world(points: 250)
        try world.adopt(.siamese, at: t(2, 10))
        world.state.bond.points = 80
        let data = try JSONEncoder().encode(world.state)
        let loaded = try JSONDecoder().decode(WorldState.self, from: data)
        #expect(loaded == world.state)
        #expect(loaded.activeCat == .siamese)
        #expect(loaded.bond.points == 80)
        #expect(loaded.restingBonds[.pudding]?.points == 250)
    }

    @Test("旧存档没有这些字段：只有布丁")
    func oldSave() throws {
        let world = try world(points: 30)
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(world.state)) as? [String: Any])
        for key in ["activeCat", "adoptedCats", "restingBonds"] { json.removeValue(forKey: key) }
        let old = try JSONDecoder().decode(WorldState.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old.activeCat == .pudding && old.adoptedCats == [.pudding] && old.restingBonds.isEmpty)
    }
}
