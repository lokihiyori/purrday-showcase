import CatEngine
import CatWorld
import Economy
import Foundation
import Testing
@testable import Purrday

@MainActor
@Suite("WorldStore")
struct WorldStoreTests {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    func makeStore(now: Date) throws -> WorldStore {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return WorldStore(
            storage: WorldStorage(fileURL: dir.appendingPathComponent("world.json")),
            log: EventLog(fileURL: dir.appendingPathComponent("events.jsonl")),
            plus: PlusStatus(),
            scheduler: PreviewAlarmScheduler(),
            catConfig: CatEngineConfig(calendar: calendar),
            economy: EconomyEngine(catalog: try Catalog.bundled()),
            now: now
        )
    }

    func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    @Test("一个早晨：锁屏事件写进日志 → 打开 App → 发奖励 → 保存 → 重新打开不重复发")
    func morning() throws {
        let store = try makeStore(now: date(1, 20))
        try store.setAlarm(AlarmConfig(id: UUID().uuidString, time: TimeOfDay(7), repeatDays: Weekday.weekdays, armedAt: date(1, 20)))
        // 模拟 App Intent 在锁屏上写的事件
        let log = EventLog(fileURL: dir.appendingPathComponent("events.jsonl"))
        try log.append(LoggedEvent(id: "fire", event: .alarmFired(alarmID: "A", at: date(2, 7))))
        try log.append(LoggedEvent(id: "stop", event: .alarmStopped(alarmID: "A", via: .lockScreen, at: date(2, 7, 1))))

        store.foreground(now: date(2, 7, 5))
        #expect(store.world.state.economy.wallet.fish == 10)
        #expect(store.pendingGrants.count == 1)
        #expect(store.pendingPrompts == [.paywall(.firstOnTimeGift)])
        #expect(store.bubble != nil)

        // 重新打开 App：从磁盘读回来，日志里还是那两条事件
        let reopened = try makeStore(now: date(2, 8))
        reopened.foreground(now: date(2, 8))
        #expect(reopened.world.state.economy.wallet.fish == 10)
        #expect(reopened.pendingGrants.isEmpty)
    }

    @Test("App 内操作：贪睡 → 摸猫关闹钟 → 收拾乱子")
    func inAppEvents() throws {
        let store = try makeStore(now: date(1, 20))
        store.send(.alarmFired(alarmID: "A", at: date(2, 7)))
        #expect(store.cat.state == .wakingUp)
        store.send(.alarmSnoozed(alarmID: "A", at: date(2, 7, 1)))
        #expect(store.cat.state == .makingMischief)
        #expect(store.cat.messCount == 1)
        store.send(.alarmStopped(alarmID: "A", via: .petCat, at: date(2, 7, 3)))
        #expect(store.cat.state == .idleDaytime)
        store.clearMess(now: date(2, 7, 4))
        #expect(store.cat.messCount == 0)
        #expect(store.bubble?.hasPrefix("line.messCleared") == true)
    }

    @Test("免费用户第二个闹钟被拦下")
    func alarmLimit() throws {
        let store = try makeStore(now: date(1, 20))
        try store.setAlarm(AlarmConfig(id: "a", time: TimeOfDay(7), armedAt: date(1, 20)))
        #expect(throws: WorldError.alarmLimitReached(limit: 1)) {
            try store.setAlarm(AlarmConfig(id: "b", time: TimeOfDay(8), armedAt: date(1, 20)))
        }
    }

    @Test("日志清理只删掉保留期以前的事件")
    func logPrune() throws {
        let log = EventLog(fileURL: dir.appendingPathComponent("prune.jsonl"))
        try log.append(LoggedEvent(id: "old", event: .appForegrounded(at: date(1, 8))))
        try log.append(LoggedEvent(id: "new", event: .appForegrounded(at: date(20, 8))))
        try log.prune(olderThan: date(10, 0))
        #expect(log.readAll().map(\.id) == ["new"])
    }

    @Test("CatArt 覆盖所有状态")
    func art() {
        #expect(CatArt.assetName(for: CatSnapshot(state: .idleDaytime, at: date(1, 8))) == "cat-idle")
        #expect(CatArt.assetName(for: CatSnapshot(state: .accompanying(.read), at: date(1, 8))) == "cat-read")
        #expect(CatArt.assetName(for: CatSnapshot(state: .idleDaytime, at: date(1, 8)), petted: true) == "cat-petted")
    }
}

@MainActor
@Suite("WorldStore · 系统闹钟")
struct WorldStoreAlarmTests {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let alarmID = "6F1C1D8E-1A2B-4C3D-9E8F-000000000001"

    func makeStore() throws -> WorldStore {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return WorldStore(
            storage: WorldStorage(fileURL: dir.appendingPathComponent("world.json")),
            log: EventLog(fileURL: dir.appendingPathComponent("events.jsonl")),
            plus: PlusStatus(),
            scheduler: PreviewAlarmScheduler(),
            catConfig: CatEngineConfig(calendar: calendar),
            economy: EconomyEngine(catalog: try Catalog.bundled()),
            now: date(1, 20)
        )
    }

    func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    @Test("AlarmKit 报告闹钟在响 → 叫醒中；在 App 里摸猫关掉 → 准时礼物")
    func ringThenPet() throws {
        let store = try makeStore()
        try store.setAlarm(AlarmConfig(id: alarmID, time: TimeOfDay(7), repeatDays: Weekday.weekdays, armedAt: date(1, 20)))
        store.alarmsUpdated(alertingIDs: [alarmID], now: date(2, 7))
        #expect(store.cat.state == .wakingUp)
        #expect(store.ringingAlarmID == alarmID)
        store.stopRingingAlarm(now: date(2, 7, 1))
        #expect(store.cat.state == .givingGift)
        #expect(store.ringingAlarmID == nil)
        #expect(store.world.state.economy.wallet.fish == 10)
    }

    @Test("App 内贪睡 → 倒计时结束再次响铃 → 摸猫关掉：没有礼物")
    func snoozeInApp() throws {
        let store = try makeStore()
        try store.setAlarm(AlarmConfig(id: alarmID, time: TimeOfDay(7), repeatDays: Weekday.weekdays, armedAt: date(1, 20)))
        store.alarmsUpdated(alertingIDs: [alarmID], now: date(2, 7))
        store.snoozeRingingAlarm(now: date(2, 7, 1))
        #expect(store.cat.state == .makingMischief)
        store.alarmsUpdated(alertingIDs: [], now: date(2, 7, 2))
        store.alarmsUpdated(alertingIDs: [alarmID], now: date(2, 7, 10))
        #expect(store.cat.state == .wakingUp)
        store.stopRingingAlarm(now: date(2, 7, 11))
        #expect(store.cat.state == .idleDaytime)
        #expect(store.world.state.economy.wallet.fish == 0)
    }

    @Test("锁屏上停止（App Intent 写日志）→ 打开 App 时按真实响铃时间判断")
    func lockScreenStop() throws {
        let store = try makeStore()
        try store.setAlarm(AlarmConfig(id: alarmID, time: TimeOfDay(7), repeatDays: Weekday.weekdays, armedAt: date(1, 20)))
        let log = EventLog(fileURL: dir.appendingPathComponent("events.jsonl"))
        for event in store.world.alarmEvents(.stopped, alarmID: alarmID, at: date(2, 7, 1)) {
            try log.append(event)
        }
        store.foreground(now: date(2, 7, 30))
        #expect(store.world.state.economy.wallet.fish == 10)
    }
}

@MainActor
@Suite("WorldStore · 房间")
struct WorldStoreRoomTests {
    /// 用 WorldStoreTests 的临时目录和日期工具；同一个 base 里的 store 共用一个存档
    let base = WorldStoreTests()

    #if DEBUG
    @Test("买家具 → 摆在房间里，布丁走过去看一会儿再接着过日子；收起来她就不看了；摆回来她又过去")
    func furniture() throws {
        let store = try base.makeStore(now: base.date(2, 9))
        store.debugGrantFish(200)
        let start = base.date(2, 9)
        #expect(store.presence(at: start) == store.world.presence(at: start))

        try store.buy("furniture.cat_tree", now: start)
        let tree = try #require(store.world.state.room.placed.first)
        #expect(tree.catalogID == "furniture.cat_tree")
        #expect(store.catFocusItemID == tree.itemID)
        let looking = store.presence(at: start.addingTimeInterval(10))
        #expect(looking.spot == store.world.catSpot(beside: tree.itemID))
        #expect(looking.pose == .sit)
        let later = start.addingTimeInterval(WorldStore.focusDuration + 1)
        #expect(store.presence(at: later) == store.world.presence(at: later))

        let bought = try #require(store.bubble)
        #expect(bought.hasPrefix("line.shopBought"))
        store.sayAmbientLine(now: base.date(2, 9, 1)) // 切回房间：保留"新家具"那句
        #expect(store.bubble == bought)
        store.sayAmbientLine(now: base.date(2, 9, 2)) // 之后再进房间：她不说话了（用动作表达）
        #expect(store.bubble == nil)

        try store.putAway(itemID: tree.itemID)
        #expect(store.catFocusItemID == nil)
        #expect(store.presence(at: start.addingTimeInterval(10)) == store.world.presence(at: start.addingTimeInterval(10)))
        #expect(store.world.storedFurniture.map(\.id) == [tree.itemID])

        try store.placeFurniture(itemID: tree.itemID, now: base.date(2, 10))
        #expect(store.catFocusItemID == tree.itemID)
        #expect(store.world.storedFurniture.isEmpty)
    }

    @Test("拖动后的位置保存下来，重新打开 App 还在；新打开时布丁按自己的作息")
    func movePersists() throws {
        let store = try base.makeStore(now: base.date(2, 9))
        store.debugGrantFish(200)
        try store.buy("furniture.pudding_sofa", now: base.date(2, 9))
        let sofa = try #require(store.world.state.room.placed.first)
        try store.moveFurniture(itemID: sofa.itemID, to: RoomPoint(x: 0.7, y: 0.9), now: base.date(2, 9, 5))

        let reopened = try base.makeStore(now: base.date(2, 10))
        #expect(reopened.world.state.room.furniture(itemID: sofa.itemID)?.position == RoomPoint(x: 0.7, y: 0.9))
        #expect(reopened.world.state.economy.wallet.fish == 50)
        #expect(reopened.catFocusItemID == nil)
        #expect(reopened.presence(at: base.date(2, 10)) == store.world.presence(at: base.date(2, 10)))
    }
    #endif

    @Test("刚领养完，布丁先坐在前面看着你，一分钟后去过自己的日子")
    func greeting() throws {
        let store = try base.makeStore(now: base.date(2, 13))
        let now = base.date(2, 13)
        store.completeOnboarding(now: now)
        let greeting = store.presence(at: now.addingTimeInterval(10))
        #expect(greeting.pose == .sit)
        #expect(greeting.spot == RoomGeometry.catHome)
        let later = now.addingTimeInterval(WorldStore.greetingDuration + 1)
        #expect(store.presence(at: later) == store.world.presence(at: later))

        // 打招呼时她是醒着的：点她不会是"午睡被吵醒"；刚到家还怕你，会吓一跳（不说话）
        store.tapCat(now: now.addingTimeInterval(10))
        #expect(store.bubble == nil)
        #expect(store.flinchAt == now.addingTimeInterval(10))
        #expect([.freeze, .scoot].contains(try #require(store.performance?.reaction)))
    }

    @Test("每件家具都有美术资源名")
    func furnitureArtNames() throws {
        let catalog = try Catalog.bundled()
        for item in catalog.items where item.kind == .furniture {
            #expect(RoomArt.furniture(item.id) == "furniture-" + item.id.dropFirst("furniture.".count))
        }
    }
}
