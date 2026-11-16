import CatEngine
import Economy
import Foundation
import Testing
@testable import CatWorld

/// 有足够小鱼干的世界，方便买家具。
private func richWorld(fish: Int = 2000) throws -> CatWorld {
    var world = try makeWorld()
    world.state.economy = EconomyState(wallet: Wallet(fish: fish), items: world.state.economy.items)
    return world
}

private func placement(_ zone: RoomZone, width: Double = 0.2, height: Double = 0.1) -> FurniturePlacement {
    FurniturePlacement(zone: zone, x: 0.5, y: 0.8, width: width, height: height)
}

private func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }

private func placed(_ id: Int, _ catalogID: String, x: Double, y: Double, at date: Date = t(2, 9)) -> PlacedFurniture {
    PlacedFurniture(itemID: id, catalogID: catalogID, position: RoomPoint(x: x, y: y), placedAt: date)
}

@Suite("房间：目录")
struct RoomCatalogTests {
    let catalog = try! Catalog.bundled()

    @Test("每件家具都有尺寸和默认位置，其他物品没有")
    func everyFurnitureHasPlacement() {
        for item in catalog.items {
            if item.kind == .furniture {
                #expect(item.placement != nil, "\(item.id) 缺少 placement")
            } else {
                #expect(item.placement == nil, "\(item.id) 不是家具，不该有 placement")
            }
        }
    }

    @Test("默认位置本身就在能放的范围里，尺寸合理")
    func defaultsAreValid() throws {
        for item in catalog.items {
            guard let p = item.placement else { continue }
            #expect(p.width > 0 && p.width <= 1 && p.height > 0 && p.height <= 1, "\(item.id) 尺寸不合理")
            let point = RoomPoint(x: p.x, y: p.y)
            #expect(RoomGeometry.clamp(point, for: p) == point, "\(item.id) 的默认位置超出了范围")
        }
    }

    @Test("挂在墙上的、平铺的、立在地上的")
    func zones() {
        func zone(_ id: String) -> RoomZone? { catalog.item("furniture.\(id)")?.placement?.zone }
        #expect(zone("wall_shelf") == .wall)
        #expect(zone("star_lights") == .wall)
        #expect(zone("window_hammock") == .wall)
        #expect(zone("rug_round") == .rug)
        #expect(zone("cat_tree") == .floor)
        #expect(zone("cardboard_box") == .floor)
    }
}

@Suite("房间：几何")
struct RoomGeometryTests {
    @Test("家具不会被拖出房间左右边界")
    func clampX() {
        let p = placement(.floor, width: 0.3)
        #expect(RoomGeometry.clamp(RoomPoint(x: -1, y: 0.8), for: p).x == 0.15)
        #expect(RoomGeometry.clamp(RoomPoint(x: 2, y: 0.8), for: p).x == 0.85)
        #expect(RoomGeometry.clamp(RoomPoint(x: 0.4, y: 0.8), for: p).x == 0.4)
    }

    @Test("墙上的东西不会掉到地上，也不会顶出天花板")
    func wall() {
        let p = placement(.wall, height: 0.1)
        #expect(RoomGeometry.clamp(RoomPoint(x: 0.5, y: 0.9), for: p).y == RoomGeometry.floorLine - 0.02)
        #expect(RoomGeometry.clamp(RoomPoint(x: 0.5, y: 0), for: p).y == 0.1 + 0.02)
    }

    @Test("地上的东西不会爬到墙上，也不会掉出房间")
    func floor() {
        let p = placement(.floor)
        #expect(RoomGeometry.clamp(RoomPoint(x: 0.5, y: 0.3), for: p).y == RoomGeometry.floorLine + 0.06)
        #expect(RoomGeometry.clamp(RoomPoint(x: 0.5, y: 1.4), for: p).y == 1)
    }

    @Test("地毯整块都在地板上")
    func rug() {
        let p = placement(.rug, height: 0.12)
        #expect(RoomGeometry.clamp(RoomPoint(x: 0.5, y: 0.5), for: p).y == RoomGeometry.floorLine + 0.12)
    }

    @Test("尺寸比墙还高、比房间还宽也不会崩")
    func impossibleSizes() {
        let p = FurniturePlacement(zone: .wall, x: 0.5, y: 0.3, width: 1.5, height: 0.9)
        let point = RoomGeometry.clamp(RoomPoint(x: 0.1, y: 0.1), for: p)
        #expect(point == RoomPoint(x: 0.5, y: 0.92))
    }

    @Test("绘制顺序：墙上 → 地毯 → 地上按前后；一样靠前时后放的在上面")
    func drawOrder() throws {
        let catalog = try Catalog.bundled()
        let items = [
            placed(1, "furniture.cat_tree", x: 0.2, y: 0.9),
            placed(2, "furniture.rug_round", x: 0.5, y: 0.95),
            placed(3, "furniture.cushion", x: 0.5, y: 0.7),
            placed(4, "furniture.wall_shelf", x: 0.5, y: 0.3),
            placed(5, "furniture.food_bowl", x: 0.6, y: 0.9, at: t(2, 8)),
        ]
        let order = RoomGeometry.drawOrder(items, catalog: catalog).map(\.itemID)
        #expect(order == [4, 2, 3, 5, 1])
    }

    @Test("猫站到地上家具的旁边，右边放不下就站左边")
    func catBesideFloorItem() {
        let p = placement(.floor, width: 0.2)
        let left = RoomGeometry.catSpot(beside: placed(1, "x", x: 0.3, y: 0.8), placement: p)
        #expect(left.x > 0.3)
        #expect(left.y == 0.86) // 家具靠后：猫站在前排，不被其他家具挡住
        let front = RoomGeometry.catSpot(beside: placed(1, "x", x: 0.3, y: 0.9), placement: p)
        #expect(close(front.y, 0.92)) // 家具靠前：比它再靠前一点
        let right = RoomGeometry.catSpot(beside: placed(1, "x", x: 0.85, y: 0.8), placement: p)
        #expect(right.x < 0.85)
        for spot in [left, right] {
            #expect(spot.x >= RoomGeometry.catWidth / 2 && spot.x <= 1 - RoomGeometry.catWidth / 2)
        }
    }

    @Test("墙上的东西：猫坐在它下面的地板上；地毯：坐在地毯上")
    func catBesideWallAndRug() {
        let wall = RoomGeometry.catSpot(beside: placed(1, "x", x: 0.9, y: 0.3), placement: placement(.wall))
        #expect(wall == RoomPoint(x: 1 - RoomGeometry.catWidth / 2, y: 0.88))
        let rug = RoomGeometry.catSpot(beside: placed(1, "x", x: 0.5, y: 0.95), placement: placement(.rug))
        #expect(rug.x == 0.5 && close(rug.y, 0.93))
    }
}

@Suite("房间：布置")
struct RoomLayoutTests {
    @Test("买到的家具直接摆在默认位置")
    func buyPlaces() throws {
        var world = try richWorld()
        let box = try world.buy("furniture.cardboard_box", isPlus: false, at: t(2, 9))
        let spot = try #require(world.economy.catalog.item("furniture.cardboard_box")?.placement)
        #expect(world.state.room.furniture(itemID: box.id)?.position == RoomPoint(x: spot.x, y: spot.y))
        #expect(world.roomDrawOrder.map(\.itemID) == [box.id])
        #expect(world.storedFurniture.isEmpty)
    }

    @Test("第一次准时起床拿到 10 小鱼干，买纸箱，房间里就有了纸箱")
    func firstMorningToBox() throws {
        var world = try makeWorld()
        try world.setAlarm(weekdayAlarm(), isPlus: false)
        world.ingest(onTimeMorning(2), isPlus: false)
        let box = try world.buy("furniture.cardboard_box", isPlus: false, at: t(2, 8))
        #expect(world.roomDrawOrder.map(\.itemID) == [box.id])
    }

    @Test("收起来再摆出来；收起来的家具不在房间里")
    func putAwayAndPlace() throws {
        var world = try richWorld()
        let sofa = try world.buy("furniture.pudding_sofa", isPlus: false, at: t(2, 9))
        try world.putAway(itemID: sofa.id)
        #expect(world.state.room.placed.isEmpty)
        #expect(world.storedFurniture.map(\.id) == [sofa.id])
        #expect(throws: WorldError.notInRoom(itemID: sofa.id)) { try world.putAway(itemID: sofa.id) }

        let position = try world.placeFurniture(itemID: sofa.id, at: RoomPoint(x: 0.6, y: 0.9), date: t(2, 10))
        #expect(position == RoomPoint(x: 0.6, y: 0.9))
        #expect(world.storedFurniture.isEmpty)
        #expect(world.state.room.furniture(itemID: sofa.id)?.placedAt == t(2, 10))
    }

    @Test("拖动：位置被限制在能放的范围里，拖过的画在同一排的上面")
    func move() throws {
        var world = try richWorld()
        let bowl = try world.buy("furniture.food_bowl", isPlus: false, at: t(2, 9))
        let fountain = try world.buy("furniture.water_fountain", isPlus: false, at: t(2, 9, 1))
        let up = try world.moveFurniture(itemID: bowl.id, to: RoomPoint(x: 0.5, y: 0.1), date: t(2, 9, 2))
        #expect(up.y == RoomGeometry.floorLine + 0.06) // 地上的东西拖不到墙上

        try world.moveFurniture(itemID: bowl.id, to: RoomPoint(x: 0.3, y: 0.85), date: t(2, 9, 3))
        try world.moveFurniture(itemID: fountain.id, to: RoomPoint(x: 0.7, y: 0.85), date: t(2, 9, 4))
        try world.moveFurniture(itemID: bowl.id, to: RoomPoint(x: 0.4, y: 0.85), date: t(2, 9, 5))
        #expect(world.roomDrawOrder.map(\.itemID) == [fountain.id, bowl.id])
    }

    @Test("拖动收起来的家具、摆礼物、摆不存在的东西都会报错")
    func errors() throws {
        var world = try richWorld()
        let lamp = try world.buy("furniture.floor_lamp", isPlus: false, at: t(2, 9))
        try world.putAway(itemID: lamp.id)
        #expect(throws: WorldError.notInRoom(itemID: lamp.id)) {
            try world.moveFurniture(itemID: lamp.id, to: RoomPoint(x: 0.5, y: 0.8), date: t(2, 10))
        }
        let coat = try #require(world.state.economy.items.first) // 默认毛色
        #expect(throws: WorldError.notPlaceable(itemID: coat.id)) {
            try world.placeFurniture(itemID: coat.id, at: nil, date: t(2, 10))
        }
        #expect(throws: WorldError.notPlaceable(itemID: 999)) {
            try world.placeFurniture(itemID: 999, at: nil, date: t(2, 10))
        }
    }

    @Test("猫去看刚放好的家具；家具收起来了就回到默认位置")
    func catSpot() throws {
        var world = try richWorld()
        #expect(world.catSpot(beside: nil) == RoomGeometry.catHome)
        let box = try world.buy("furniture.cardboard_box", isPlus: false, at: t(2, 9))
        #expect(world.catSpot(beside: box.id) != RoomGeometry.catHome)
        try world.putAway(itemID: box.id)
        #expect(world.catSpot(beside: box.id) == RoomGeometry.catHome)
    }

    @Test("房间布局随存档保存和读取")
    func roundTrip() throws {
        var world = try richWorld()
        try world.buy("furniture.cat_tree", isPlus: false, at: t(2, 9))
        let data = try JSONEncoder().encode(world.state)
        #expect(try JSONDecoder().decode(WorldState.self, from: data) == world.state)
    }

    @Test("旧存档没有房间字段：照样读出来，猫和小鱼干都在，房间是空的")
    func oldSaveWithoutRoom() throws {
        var world = try richWorld(fish: 42)
        try world.setAlarm(weekdayAlarm(), isPlus: false)
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(world.state)) as? [String: Any])
        json.removeValue(forKey: "room")
        let old = try JSONDecoder().decode(WorldState.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old.room == RoomLayout())
        #expect(old.economy.wallet.fish == 42)
        #expect(old.alarms == world.state.alarms)
        #expect(old.cat == world.state.cat)
    }

    #if DEBUG
    @Test("Debug 版本可以加小鱼干（UI 走查用）")
    func debugFish() throws {
        var world = try makeWorld()
        world.debugGrantFish(200)
        #expect(world.state.economy.wallet.fish == 200)
    }
    #endif
}
