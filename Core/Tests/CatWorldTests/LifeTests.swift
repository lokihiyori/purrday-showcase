import CatEngine
import Economy
import Foundation
import Testing
@testable import CatWorld

/// 只给指定的家具标上猫的位置，其他家具没有（测试不依赖目录里的真实数据）。
private func catalog(spots: [String: [FurnitureSpot]]) throws -> Catalog {
    var catalog = try Catalog.bundled()
    for index in catalog.items.indices where catalog.items[index].placement != nil {
        let id = catalog.items[index].id
        catalog.items[index].placement?.spots = spots[id]
    }
    return catalog
}

private func lifeWorld(spots: [String: [FurnitureSpot]] = [:], furniture: [String] = [], seed: UInt64 = 7) throws -> CatWorld {
    var world = CatWorld.newPlayer(at: t(1, 20), seed: seed, catConfig: CatEngineConfig(calendar: calendar()),
                                   economy: EconomyEngine(catalog: try catalog(spots: spots)))
    world.state.economy = EconomyState(wallet: Wallet(fish: 5000), items: world.state.economy.items)
    for id in furniture { try world.buy(id, isPlus: false, at: t(1, 21)) }
    return world
}

/// 这些天里、这几个小时内每 15 分钟一次的样子。
private func samples(_ world: CatWorld, days: ClosedRange<Int> = 2...31, from: Int, to: Int) -> [(Date, CatPresence)] {
    var result: [(Date, CatPresence)] = []
    for d in days {
        var date = t(d, from, 1)
        while date < t(d, to) {
            result.append((date, world.presence(at: date)))
            date = date.addingTimeInterval(LifeSchedule.block)
        }
    }
    return result
}

private func share(_ list: [(Date, CatPresence)], _ activity: CatActivity) -> Double {
    Double(list.filter { $0.1.activity == activity }.count) / Double(max(list.count, 1))
}

private let bowl = ["furniture.food_bowl": [FurnitureSpot(uses: [.eat], dx: 0.13, dy: 0.01, layer: .floor)]]
private let box = ["furniture.cardboard_box": [FurnitureSpot(uses: [.hide, .nap], dx: 0, dy: -0.03, layer: .inside, weight: 2)]]

@Suite("生活：作息")
struct LifeScheduleTests {
    @Test("同一时刻问几次都一样；一拍（20 秒）之内不变，下一拍开始时再问")
    func deterministic() throws {
        let world = try lifeWorld()
        let a = world.presence(at: t(2, 10, 0, 1))
        #expect(world.presence(at: t(2, 10, 0, 1)) == a)
        #expect(world.presence(at: t(2, 10, 0, 19)) == a)
        #expect(a.nextChange == t(2, 10, 0, 20))
        // 存档读回来以后作息一样
        let reloaded = CatWorld(state: try JSONDecoder().decode(WorldState.self, from: JSONEncoder().encode(world.state)),
                                catConfig: world.catConfig, economy: world.economy)
        #expect(reloaded.presence(at: t(2, 10, 0, 1)) == a)
    }

    @Test("时段跟着起床时间走：没闹钟按 8 点起床")
    func slotsWithoutAlarm() throws {
        let world = try lifeWorld()
        #expect(world.lifeSlot(at: t(2, 7)) == .early)
        #expect(world.lifeSlot(at: t(2, 8, 30)) == .morning)
        #expect(world.lifeSlot(at: t(2, 10)) == .forenoon)
        #expect(world.lifeSlot(at: t(2, 13)) == .noon)
        #expect(world.lifeSlot(at: t(2, 16)) == .afternoon)
        #expect(world.lifeSlot(at: t(2, 19)) == .evening)
        #expect(world.lifeSlot(at: t(2, 22, 30)) == .late)
        #expect(world.lifeSlot(at: t(3, 1)) == .late) // 逻辑日到 04:00 才结束
    }

    @Test("起得晚，早饭和午睡都往后推")
    func lateRiser() throws {
        var world = try lifeWorld()
        try world.setAlarm(weekdayAlarm(at: 11), isPlus: false)
        #expect(world.lifeSlot(at: t(2, 10)) == .early)       // 周一，闹钟 11:00
        #expect(world.lifeSlot(at: t(2, 12)) == .morning)
        #expect(world.lifeSlot(at: t(2, 12, 40)) == .noon)
        #expect(world.lifeSlot(at: t(7, 10)) == .forenoon)    // 周六没有闹钟，按 8 点
    }

    @Test("要家具的事，没有家具就不会做")
    func needsFurniture() throws {
        let world = try lifeWorld()
        let all = samples(world, from: 6, to: 23)
        for activity in [CatActivity.eat, .drink, .scratch, .hide, .perch] {
            #expect(share(all, activity) == 0, "\(activity)")
        }
        #expect(all.allSatisfy { $0.1.depth.isFloor })
    }

    @Test("有食盆的话，早上经常去吃饭：站在食盆旁边、面朝它、低头吃")
    func breakfast() throws {
        var world = try lifeWorld(spots: bowl, furniture: ["furniture.food_bowl"])
        try world.setAlarm(weekdayAlarm(), isPlus: false)
        let mornings = samples(world, days: 2...30, from: 7, to: 8).filter { world.lifeSlot(at: $0.0) == .morning }
        #expect(share(mornings, .eat) > 0.15)
        let item = try #require(world.state.room.placed.first)
        for (_, p) in mornings where p.activity == .eat {
            #expect(p.pose == .eat)
            #expect(abs(p.spot.x - (item.position.x + 0.13)) < 1e-9)
            #expect(p.facing == -1) // 在食盆右边，朝左
        }
    }

    @Test("中午大多在睡觉")
    func noonNap() throws {
        let world = try lifeWorld()
        let noons = samples(world, from: 12, to: 15)
        #expect(share(noons, .nap) > 0.4)
        for (_, p) in noons where p.activity == .nap {
            #expect(p.pose == .curl)
        }
    }

    @Test("晒太阳只在有太阳的时候，躺在光斑上")
    func sunbathe() throws {
        let world = try lifeWorld()
        let all = samples(world, from: 6, to: 23)
        #expect(share(all, .sunbathe) > 0)
        for (date, p) in all where p.activity == .sunbathe {
            let beam = try #require(RoomGeometry.sunbeam(at: date, calendar: world.catConfig.calendar))
            #expect(p.spot == beam)
            #expect(p.pose == .sprawl)
        }
    }

    @Test("看窗外时背对你坐在窗下")
    func watch() throws {
        let world = try lifeWorld()
        let watching = samples(world, from: 8, to: 22).filter { $0.1.activity == .watch }
        #expect(!watching.isEmpty)
        #expect(watching.allSatisfy { $0.1.pose == .sitBack && $0.1.spot == RoomGeometry.windowSpot })
    }

    @Test("事情有连续性：睡觉通常不止 15 分钟")
    func streaks() throws {
        let world = try lifeWorld()
        let noons = samples(world, from: 12, to: 15)
        let pairs = zip(noons, noons.dropFirst()).filter { $0.0.1.activity == .nap }
        let continued = pairs.filter { $0.1.1.activity == .nap }.count
        #expect(Double(continued) / Double(max(pairs.count, 1)) > 0.6)
    }

    @Test("到处闻、自己玩的时候每一拍换个地方，地方都在地板上")
    func wandering() throws {
        let world = try lifeWorld(furniture: ["furniture.cat_tree"])
        let busy = try #require(samples(world, from: 8, to: 22).first { [.explore, .play].contains($0.1.activity) })
        let beats = (0..<6).map { world.presence(at: busy.0.addingTimeInterval(Double($0) * LifeSchedule.beat)) }
        #expect(Set(beats.map(\.spot)).count >= 3)
        for p in beats where p.activity == busy.1.activity {
            #expect(p.pose == .stand)
            #expect(p.facing != 0)
            #expect(RoomGeometry.catFloorX.contains(p.spot.x) && RoomGeometry.catFloorY.contains(p.spot.y))
        }
    }

    @Test("钻进纸箱：在纸箱里面，画在纸箱和它的前半部分之间")
    func insideBox() throws {
        let world = try lifeWorld(spots: box, furniture: ["furniture.cardboard_box"])
        let item = try #require(world.state.room.placed.first)
        let hiding = try #require(samples(world, from: 6, to: 23).first { $0.1.depth == .inside(itemID: item.itemID) })
        #expect([.hide, .nap].contains(hiding.1.activity))
        #expect(abs(hiding.1.spot.y - (item.position.y - 0.03)) < 1e-9)
        let layers = RoomGeometry.layers(world.state.room.placed, catalog: world.economy.catalog, cat: hiding.1.depth)
        #expect(layers == [.furniture(item), .cat, .furnitureFront(item)])
    }

    @Test("换一个种子，作息也不一样")
    func seeds() throws {
        let a = samples(try lifeWorld(seed: 1), days: 2...4, from: 8, to: 22).map(\.1.activity)
        let b = samples(try lifeWorld(seed: 2), days: 2...4, from: 8, to: 22).map(\.1.activity)
        #expect(a != b)
    }

    @Test("小动作：只出现在这个姿势会有的里面，大约一半的拍子有")
    func fidgets() throws {
        let world = try lifeWorld()
        var count = 0, total = 0
        var date = t(2, 9)
        while date < t(2, 12) {
            let p = world.presence(at: date)
            #expect(p.fidget == .none || LifeSchedule.fidgets(for: p.pose).contains(p.fidget))
            if !LifeSchedule.fidgets(for: p.pose).isEmpty {
                total += 1
                if p.fidget != .none { count += 1 }
            }
            date = date.addingTimeInterval(LifeSchedule.beat)
        }
        #expect(total > 100)
        #expect(Double(count) / Double(total) > 0.35 && Double(count) / Double(total) < 0.65)
    }
}

@Suite("生活：不是白天待机的时候")
struct LifeStateTests {
    private let beds = [
        "furniture.bed_cloud": [FurnitureSpot(uses: [.nap], dx: 0, dy: -0.03, layer: .inside, weight: 3)],
        "furniture.cushion": [FurnitureSpot(uses: [.nap, .loaf], dx: 0, dy: -0.04, layer: .on)],
    ]

    @Test("睡前在最舒服的床上揣手打呼噜，夜里蜷着睡")
    func bedtime() throws {
        var world = try lifeWorld(spots: beds, furniture: ["furniture.cushion", "furniture.bed_cloud"])
        let bed = try #require(world.state.room.placed.first { $0.catalogID == "furniture.bed_cloud" })
        world.tick(at: t(1, 23, 5), isPlus: false)
        #expect(world.state.cat.state == .purringAtBedtime)
        let purring = world.presence(at: t(1, 23, 6))
        #expect(purring.pose == .purr)
        #expect(purring.activity == nil)
        #expect(purring.depth == .inside(itemID: bed.itemID))

        world.tick(at: t(2, 3), isPlus: false)
        #expect(world.state.cat.state == .sleepingAtNight)
        let sleeping = world.presence(at: t(2, 3))
        #expect(sleeping.pose == .curl)
        #expect(sleeping.depth == .inside(itemID: bed.itemID))
        #expect([.none, .earTwitch, .tailFlick].contains(sleeping.fidget))
    }

    @Test("没有床就睡在地板上")
    func noBed() throws {
        var world = try lifeWorld()
        world.tick(at: t(2, 3), isPlus: false)
        let p = world.presence(at: t(2, 3))
        #expect(p.pose == .curl)
        #expect(p.depth.isFloor)
    }

    @Test("叫醒、送礼物的时候用专门的画，站在默认位置")
    func stateArt() throws {
        var world = try lifeWorld()
        try world.setAlarm(weekdayAlarm(), isPlus: false)
        world.ingest([LoggedEvent(id: "fire", event: .alarmFired(alarmID: "A", at: t(2, 7)))], isPlus: false)
        let p = world.presence(at: t(2, 7))
        #expect(p.pose == .stateArt)
        #expect(p.spot == RoomGeometry.catHome)
    }
}

@Suite("生活：房间里的前后顺序和阳光")
struct LifeGeometryTests {
    let catalog = try! Catalog.bundled()

    private func placed(_ id: Int, _ catalogID: String, x: Double, y: Double) -> PlacedFurniture {
        PlacedFurniture(itemID: id, catalogID: catalogID, position: RoomPoint(x: x, y: y), placedAt: t(2, 9))
    }

    @Test("猫在地板上：比她靠后的家具在她后面，靠前的在前面；墙上的和地毯总在后面")
    func floorCat() {
        let shelf = placed(1, "furniture.wall_shelf", x: 0.5, y: 0.3)
        let rug = placed(2, "furniture.rug_round", x: 0.5, y: 0.95)
        let back = placed(3, "furniture.scratching_post", x: 0.4, y: 0.72)
        let front = placed(4, "furniture.cat_tunnel", x: 0.4, y: 0.99)
        let layers = RoomGeometry.layers([front, back, rug, shelf], catalog: catalog, cat: .floor(0.9))
        #expect(layers == [.furniture(shelf), .furniture(rug), .furniture(back), .cat, .furniture(front)])
    }

    @Test("猫在家具上面：紧跟着那件家具；在墙上的置物架上时，地上的家具都在她前面")
    func onFurniture() {
        let shelf = placed(1, "furniture.wall_shelf", x: 0.5, y: 0.3)
        let post = placed(3, "furniture.scratching_post", x: 0.4, y: 0.72)
        let layers = RoomGeometry.layers([post, shelf], catalog: catalog, cat: .on(itemID: 1))
        #expect(layers == [.furniture(shelf), .cat, .furniture(post)])
    }

    @Test("有前半部分的家具：猫不在里面时，前半部分紧跟着画")
    func frontWithoutCat() throws {
        var catalog = self.catalog
        let index = try #require(catalog.items.firstIndex { $0.id == "furniture.cardboard_box" })
        catalog.items[index].placement?.spots = [FurnitureSpot(uses: [.hide], dx: 0, dy: 0, layer: .inside)]
        let box = placed(1, "furniture.cardboard_box", x: 0.7, y: 0.95)
        #expect(RoomGeometry.layers([box], catalog: catalog, cat: .floor(0.8)) == [.cat, .furniture(box), .furnitureFront(box)])
        #expect(RoomGeometry.layers([box], catalog: catalog, cat: nil) == [.furniture(box), .furnitureFront(box)])
    }

    @Test("猫在一件已经收起来的家具上：画在最后，不会消失")
    func missingItem() {
        let post = placed(3, "furniture.scratching_post", x: 0.4, y: 0.72)
        #expect(RoomGeometry.layers([post], catalog: catalog, cat: .inside(itemID: 99)) == [.furniture(post), .cat])
    }

    @Test("阳光：早上在右边，下午移到左边，太阳下山就没了")
    func sunbeam() throws {
        let cal = calendar()
        #expect(RoomGeometry.sunbeam(at: t(2, 6), calendar: cal) == nil)
        #expect(RoomGeometry.sunbeam(at: t(2, 18), calendar: cal) == nil)
        let morning = try #require(RoomGeometry.sunbeam(at: t(2, 9), calendar: cal))
        let afternoon = try #require(RoomGeometry.sunbeam(at: t(2, 15), calendar: cal))
        #expect(morning.x > afternoon.x)
        #expect(RoomGeometry.catFloorY.contains(morning.y))
    }
}

@Suite("生活：存档")
struct LifeSaveTests {
    @Test("旧存档没有作息种子：照样能读，保存一次后作息固定")
    func oldSave() throws {
        let world = try lifeWorld()
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(world.state)) as? [String: Any])
        json.removeValue(forKey: "lifeSeed")
        let old = try JSONDecoder().decode(WorldState.self, from: JSONSerialization.data(withJSONObject: json))
        let again = try JSONDecoder().decode(WorldState.self, from: JSONEncoder().encode(old))
        #expect(again.lifeSeed == old.lifeSeed)
        #expect(old.economy == world.state.economy)
    }
}
