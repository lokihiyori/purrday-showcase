import CatEngine
@testable import Economy
import Foundation
import Testing
@testable import CatWorld

@Suite("商店：今日推荐和房间预览")
struct ShopPicksTests {
    @Test("今日推荐：三件没买过的家具，同一天不变，隔天会换；买了的不再推荐")
    func picks() throws {
        var world = try makeWorld()
        let today = world.dailyPicks(at: t(2, 10), isPlus: false)
        #expect(today.count == 3)
        #expect(Set(today.map(\.id)).count == 3)
        #expect(today.allSatisfy { $0.kind == .furniture && !$0.plusOnly })
        #expect(today.map(\.id) == world.dailyPicks(at: t(2, 20), isPlus: false).map(\.id))
        let week = Set((2...8).map { world.dailyPicks(at: t($0, 10), isPlus: false).map(\.id) })
        #expect(week.count > 1)

        world.debugGrantFish(2000)
        try world.buy(today[0].id, isPlus: false, at: t(2, 11))
        #expect(!world.dailyPicks(at: t(2, 12), isPlus: false).contains { $0.id == today[0].id })
    }

    @Test("快买齐了：剩几件推荐几件，全买了就没有")
    func almostEverything() throws {
        var world = try makeWorld()
        world.debugGrantFish(5000)
        let all = world.economy.shopItems().filter { !$0.plusOnly }
        for item in all.dropLast(2) { try world.buy(item.id, isPlus: false, at: t(2, 11)) }
        #expect(world.dailyPicks(at: t(2, 12), isPlus: false).count == 2)
        for item in all.suffix(2) { try world.buy(item.id, isPlus: false, at: t(2, 11)) }
        #expect(world.dailyPicks(at: t(2, 12), isPlus: false).isEmpty)
    }

    @Test("房间预览：新家具放在默认位置，和已有的一起排好前后；不改存档；她坐在新家具旁边")
    func preview() throws {
        var world = try makeWorld()
        world.debugGrantFish(500)
        try world.buy("furniture.cardboard_box", isPlus: false, at: t(2, 11))
        let before = world.state
        let preview = try #require(world.roomPreview(adding: "furniture.cat_tree", at: t(2, 12)))
        #expect(world.state == before)
        #expect(preview.furniture.count == 2)
        #expect(preview.added.catalogID == "furniture.cat_tree")
        #expect(preview.furniture.contains(preview.added))
        let placement = try #require(world.economy.catalog.item("furniture.cat_tree")?.placement)
        #expect(preview.added.position == RoomPoint(x: placement.x, y: placement.y))
        #expect((0.1...0.9).contains(preview.cat.x) && preview.cat.y >= RoomGeometry.floorLine)
        #expect(world.roomPreview(adding: "gift.yarn_ball", at: t(2, 12)) == nil)
    }
}
