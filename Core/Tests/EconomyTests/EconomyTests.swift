import CatEngine
import Foundation
import Testing
@testable import Economy

let day1 = Date(timeIntervalSince1970: 1_793_000_000)

func bundledEngine() throws -> EconomyEngine {
    EconomyEngine(catalog: try Catalog.bundled())
}

/// 小目录，用来测 Plus 专属等内置目录里暂时没有的情况。
func testCatalog() -> Catalog {
    func item(_ id: String, _ kind: ItemKind, _ rarity: Rarity = .common, price: Int? = nil, sell: Int? = nil, plus: Bool = false) -> CatalogItem {
        CatalogItem(id: id, kind: kind, rarity: rarity, nameKey: "item.\(id)", name: id, price: price, sellPrice: sell, plusOnly: plus)
    }
    return Catalog(
        version: 1,
        defaultCoat: "coat.default",
        items: [
            item("coat.default", .coat),
            item("coat.plus", .coat, .rare, plus: true),
            item("gift.a", .gift, sell: 2),
            item("gift.b", .gift, .rare, sell: 10),
            item("souvenir.a", .souvenir),
            item("furniture.chair", .furniture, price: 20),
            item("furniture.xmas", .furniture, price: 30, plus: true),
        ],
        lootTables: [
            "breakfast": LootTable(items: ["gift.a", "gift.b"], rarityWeights: [.common: 3, .rare: 1], luckyMultipliers: [.rare: 3]),
            "souvenir": LootTable(items: ["souvenir.a"], rarityWeights: [.common: 1]),
        ]
    )
}

@Suite("内置目录 catalog.json")
struct BundledCatalogTests {
    @Test("能加载，并且自洽")
    func loadsAndValidates() throws {
        let catalog = try Catalog.bundled()
        #expect(catalog.validate() == [])
    }

    @Test("首批 20 件家具（计划书阶段 1）")
    func twentyFurniture() throws {
        let catalog = try Catalog.bundled()
        #expect(catalog.items.filter { $0.kind == .furniture }.count == 20)
    }

    @Test("早餐礼物四个稀有度都有，偶尔稀有")
    func breakfastHasAllRarities() throws {
        let engine = try bundledEngine()
        let odds = try engine.rarityOdds("breakfast", lucky: false)
        #expect(Set(odds.keys) == Set(Rarity.allCases))
        #expect(odds[.common]! > 0.5)
        #expect(odds[.rare]! + odds[.legendary]! < 0.1)
    }

    @Test("默认毛色是布丁，新用户默认拥有")
    func defaultCoat() throws {
        let catalog = try Catalog.bundled()
        let state = EconomyState.newPlayer(catalog: catalog, at: day1)
        #expect(catalog.defaultCoat == "coat.pudding")
        #expect(state.owns("coat.pudding"))
        #expect(state.wallet.fish == 0)
    }

    @Test("用户可见文字都走本地化 key")
    func nameKeys() throws {
        let catalog = try Catalog.bundled()
        for item in catalog.items {
            #expect(item.nameKey == "item.\(item.id)")
        }
    }
}

@Suite("目录校验")
struct CatalogValidationTests {
    @Test("能发现常见错误")
    func findsProblems() {
        var catalog = testCatalog()
        catalog.items.append(catalog.items[2]) // 重复 id
        catalog.items.append(CatalogItem(id: "gift.nosell", kind: .gift, rarity: .common, nameKey: "", name: "", price: nil, sellPrice: nil, plusOnly: false))
        catalog.lootTables["broken"] = LootTable(items: ["missing"], rarityWeights: [:])
        let problems = catalog.validate()
        #expect(problems.contains("重复的 id：gift.a"))
        #expect(problems.contains("礼物 gift.nosell 没有卖价"))
        #expect(problems.contains("掉落表 broken 引用了不存在的 missing"))
    }
}

@Suite("奖励")
struct GrantTests {
    @Test("准时起床：10 小鱼干 + 1 件早餐礼物")
    func wakeGift() throws {
        let engine = try bundledEngine()
        var state = EconomyState.newPlayer(catalog: engine.catalog, at: day1)
        var rng = SeededRandom(seed: 1)
        let grant = try engine.grant(.wakeGift(luckyBoost: false), isPlus: false, at: day1, state: &state, rng: &rng)
        #expect(grant.fish == 10)
        #expect(grant.items.count == 1)
        #expect(engine.catalog.item(grant.items[0].catalogID)?.kind == .gift)
        #expect(grant.items[0].source == .gift)
        #expect(state.wallet == Wallet(fish: 10, lifetimeFish: 10))
        #expect(state.items.count == 2) // 默认毛色 + 礼物
    }

    @Test("各种奖励的小鱼干数量；Plus ×2", arguments: [
        (CatReward.wakeGift(luckyBoost: false), 10),
        (.focusCompleted, 5),
        (.bookFinished, 30),
        (.stepGoalSouvenir, 0),
    ])
    func fishAmounts(reward: CatReward, fish: Int) throws {
        let engine = try bundledEngine()
        for isPlus in [false, true] {
            var state = EconomyState()
            var rng = SeededRandom(seed: 7)
            let grant = try engine.grant(reward, isPlus: isPlus, at: day1, state: &state, rng: &rng)
            #expect(grant.fish == fish * (isPlus ? 2 : 1))
        }
    }

    @Test("步数达标：1 件纪念品，不给小鱼干")
    func souvenir() throws {
        let engine = try bundledEngine()
        var state = EconomyState()
        var rng = SeededRandom(seed: 3)
        let grant = try engine.grant(.stepGoalSouvenir, isPlus: false, at: day1, state: &state, rng: &rng)
        #expect(grant.items.count == 1)
        #expect(engine.catalog.item(grant.items[0].catalogID)?.kind == .souvenir)
    }

    @Test("同一个种子掉落结果相同（可复现）")
    func deterministic() throws {
        let engine = try bundledEngine()
        func run() throws -> [String] {
            var rng = SeededRandom(seed: 42)
            return try (0..<50).map { _ in try engine.roll("breakfast", lucky: false, rng: &rng).id }
        }
        #expect(try run() == run())
    }

    @Test("SeededRandom 的输出固定，不随标准库版本变化")
    func seededRandomIsStable() {
        var rng = SeededRandom(seed: 0)
        #expect(rng.next() == 0xE220_A839_7B1D_CDAF)
        #expect(rng.next() == 0x6E78_9E6A_A1B9_65F4)
    }
}

@Suite("掉落概率")
struct LootOddsTests {
    @Test("抽样分布接近配置的概率")
    func distributionMatchesOdds() throws {
        let engine = try bundledEngine()
        let odds = try engine.rarityOdds("breakfast", lucky: false)
        var rng = SeededRandom(seed: 2026)
        var counts: [Rarity: Int] = [:]
        let n = 100_000
        for _ in 0..<n {
            counts[try engine.roll("breakfast", lucky: false, rng: &rng).rarity, default: 0] += 1
        }
        for (rarity, p) in odds {
            let observed = Double(counts[rarity, default: 0]) / Double(n)
            #expect(abs(observed - p) < 0.01, "\(rarity): 期望 \(p)，实际 \(observed)")
        }
    }

    @Test("幸运加成提高稀有和传说的概率")
    func luckyBoostRaisesRareOdds() throws {
        let engine = try bundledEngine()
        let normal = try engine.rarityOdds("breakfast", lucky: false)
        let lucky = try engine.rarityOdds("breakfast", lucky: true)
        #expect(lucky[.rare]! > normal[.rare]! * 2)
        #expect(lucky[.legendary]! > normal[.legendary]! * 2)
        #expect(lucky[.common]! < normal[.common]!)
        #expect(abs(lucky.values.reduce(0, +) - 1) < 1e-9)
    }

    @Test("每个稀有度里的物品都能被抽到")
    func everyItemReachable() throws {
        let engine = EconomyEngine(catalog: testCatalog())
        var rng = SeededRandom(seed: 9)
        var seen = Set<String>()
        for _ in 0..<500 { seen.insert(try engine.roll("breakfast", lucky: false, rng: &rng).id) }
        #expect(seen == ["gift.a", "gift.b"])
    }

    @Test("不存在的掉落表报错")
    func unknownTable() {
        let engine = EconomyEngine(catalog: testCatalog())
        var rng = SeededRandom(seed: 1)
        #expect(throws: EconomyError.unknownLootTable("nope")) {
            try engine.roll("nope", lucky: false, rng: &rng)
        }
    }
}

@Suite("商店")
struct ShopTests {
    @Test("买家具：扣小鱼干、加物品，累计获得不变")
    func buy() throws {
        let engine = EconomyEngine(catalog: testCatalog())
        var state = EconomyState(wallet: Wallet(fish: 25))
        let item = try engine.buy("furniture.chair", isPlus: false, at: day1, state: &state)
        #expect(item.source == .shop)
        #expect(state.wallet.fish == 5)
        #expect(state.wallet.lifetimeFish == 25)
        #expect(state.owns("furniture.chair"))
    }

    @Test("小鱼干不够")
    func insufficient() {
        let engine = EconomyEngine(catalog: testCatalog())
        var state = EconomyState(wallet: Wallet(fish: 19))
        #expect(throws: EconomyError.insufficientFish(needed: 20, balance: 19)) {
            try engine.buy("furniture.chair", isPlus: false, at: day1, state: &state)
        }
        #expect(state.wallet.fish == 19)
    }

    @Test("家具每件只能买一次")
    func alreadyOwned() throws {
        let engine = EconomyEngine(catalog: testCatalog())
        var state = EconomyState(wallet: Wallet(fish: 100))
        try engine.buy("furniture.chair", isPlus: false, at: day1, state: &state)
        #expect(throws: EconomyError.alreadyOwned("furniture.chair")) {
            try engine.buy("furniture.chair", isPlus: false, at: day1, state: &state)
        }
    }

    @Test("Plus 专属家具：免费用户买不了，Plus 用户可以")
    func plusOnly() throws {
        let engine = EconomyEngine(catalog: testCatalog())
        var state = EconomyState(wallet: Wallet(fish: 100))
        #expect(throws: EconomyError.requiresPlus("furniture.xmas")) {
            try engine.buy("furniture.xmas", isPlus: false, at: day1, state: &state)
        }
        try engine.buy("furniture.xmas", isPlus: true, at: day1, state: &state)
        #expect(state.owns("furniture.xmas"))
    }

    @Test("不在商店卖的东西买不了")
    func notForSale() {
        let engine = EconomyEngine(catalog: testCatalog())
        var state = EconomyState(wallet: Wallet(fish: 100))
        #expect(throws: EconomyError.notForSale("gift.a")) {
            try engine.buy("gift.a", isPlus: false, at: day1, state: &state)
        }
        #expect(throws: EconomyError.unknownItem("nope")) {
            try engine.buy("nope", isPlus: false, at: day1, state: &state)
        }
    }

    @Test("商店按价格排序，只有家具")
    func shopListing() throws {
        let items = try bundledEngine().shopItems()
        #expect(items.count == 20)
        #expect(items.allSatisfy { $0.kind == .furniture })
        #expect(items.map { $0.price! } == items.map { $0.price! }.sorted())
        #expect(items.first?.id == "furniture.cardboard_box") // 最便宜的是纸箱
    }
}

@Suite("卖礼物")
struct SellTests {
    @Test("卖掉礼物换小鱼干，计入累计获得")
    func sellGift() throws {
        let engine = EconomyEngine(catalog: testCatalog())
        var state = EconomyState()
        let gift = state.add("gift.b", at: day1, source: .gift)
        let fish = try engine.sell(itemID: gift.id, state: &state)
        #expect(fish == 10)
        #expect(state.wallet == Wallet(fish: 10, lifetimeFish: 10))
        #expect(!state.owns("gift.b"))
    }

    @Test("重复的礼物可以只卖一个")
    func sellOneOfDuplicates() throws {
        let engine = EconomyEngine(catalog: testCatalog())
        var state = EconomyState()
        let first = state.add("gift.a", at: day1, source: .gift)
        state.add("gift.a", at: day1, source: .gift)
        try engine.sell(itemID: first.id, state: &state)
        #expect(state.count(of: "gift.a") == 1)
    }

    @Test("家具、毛色、纪念品不能卖")
    func cannotSellNonGifts() {
        let engine = EconomyEngine(catalog: testCatalog())
        var state = EconomyState()
        for id in ["furniture.chair", "coat.default", "souvenir.a"] {
            let item = state.add(id, at: day1, source: .event)
            #expect(throws: EconomyError.notSellable(id)) {
                try engine.sell(itemID: item.id, state: &state)
            }
        }
    }

    @Test("卖不存在的物品报错")
    func sellMissing() {
        let engine = EconomyEngine(catalog: testCatalog())
        var state = EconomyState()
        #expect(throws: EconomyError.itemNotOwned(99)) {
            try engine.sell(itemID: 99, state: &state)
        }
    }

    @Test("物品编号不会重复，即使卖掉后再获得")
    func idsNeverReused() throws {
        let engine = EconomyEngine(catalog: testCatalog())
        var state = EconomyState()
        let a = state.add("gift.a", at: day1, source: .gift)
        try engine.sell(itemID: a.id, state: &state)
        let b = state.add("gift.a", at: day1, source: .gift)
        #expect(b.id != a.id)
    }
}

@Suite("毛色")
struct CoatTests {
    @Test("默认毛色永远能用；Plus 毛色只在 Plus 期间能用")
    func coatAvailability() {
        let engine = EconomyEngine(catalog: testCatalog())
        let state = EconomyState.newPlayer(catalog: engine.catalog, at: day1)
        #expect(engine.canUseCoat("coat.default", isPlus: false, state: state))
        #expect(!engine.canUseCoat("coat.plus", isPlus: false, state: state))
        #expect(engine.canUseCoat("coat.plus", isPlus: true, state: state))
        #expect(!engine.canUseCoat("furniture.chair", isPlus: true, state: state))
    }
}

@Suite("持久化")
struct PersistenceTests {
    @Test("状态和随机数生成器都可以编码再解码")
    func roundTrip() throws {
        let engine = try bundledEngine()
        var state = EconomyState.newPlayer(catalog: engine.catalog, at: day1)
        var rng = SeededRandom(seed: 5)
        try engine.grant(.wakeGift(luckyBoost: true), isPlus: false, at: day1, state: &state, rng: &rng)
        let decodedState = try JSONDecoder().decode(EconomyState.self, from: JSONEncoder().encode(state))
        var decodedRng = try JSONDecoder().decode(SeededRandom.self, from: JSONEncoder().encode(rng))
        #expect(decodedState == state)
        #expect(decodedRng.next() == rng.next())
    }
}

@Suite("和 CatEngine 联动")
struct IntegrationTests {
    @Test("一个早晨：准时关闹钟 → 礼物和小鱼干 → 卖掉礼物 → 买纸箱")
    func morningFlow() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let at = { (h: Int, m: Int) in calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: h, minute: m))! }

        var cat = CatMachine(config: CatEngineConfig(calendar: calendar), snapshot: CatSnapshot(state: .sleepingAtNight, at: at(1, 0)))
        let engine = try bundledEngine()
        var economy = EconomyState.newPlayer(catalog: engine.catalog, at: at(1, 0))
        var rng = SeededRandom(seed: 11)

        cat.handle(.alarmFired(alarmID: "A", at: at(7, 0)))
        let outputs = cat.handle(.alarmStopped(alarmID: "A", via: .petCat, at: at(7, 1)))
        for case let .reward(reward) in outputs {
            try engine.grant(reward, isPlus: false, at: at(7, 1), state: &economy, rng: &rng)
        }
        #expect(economy.wallet.fish == 10)
        let gift = economy.items.first { engine.catalog.item($0.catalogID)?.kind == .gift }!
        try engine.sell(itemID: gift.id, state: &economy)
        #expect(economy.wallet.fish >= 12)
        try engine.buy("furniture.cardboard_box", isPlus: false, at: at(7, 5), state: &economy)
        #expect(economy.owns("furniture.cardboard_box"))
    }
}
