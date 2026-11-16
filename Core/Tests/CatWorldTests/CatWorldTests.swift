import CatEngine
import Economy
import Foundation
import Testing
@testable import CatWorld

let shanghai = TimeZone(identifier: "Asia/Shanghai")!
let newYork = TimeZone(identifier: "America/New_York")!

func calendar(_ tz: TimeZone = shanghai) -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = tz
    return c
}

/// 2026 年 11 月某日的当地时间。2026-11-02 是周一。
func t(_ day: Int, _ hour: Int, _ minute: Int = 0, _ second: Int = 0, month: Int = 11, year: Int = 2026, tz: TimeZone = shanghai) -> Date {
    calendar(tz).date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
}

func day(_ d: Int, month: Int = 11) -> LogicalDay {
    LogicalDay(year: 2026, month: month, day: d)
}

func makeWorld(at date: Date = t(1, 20), seed: UInt64 = 1) throws -> CatWorld {
    CatWorld.newPlayer(
        at: date, seed: seed,
        catConfig: CatEngineConfig(calendar: calendar()),
        economy: EconomyEngine(catalog: try Catalog.bundled())
    )
}

/// 工作日 07:00 的闹钟。
func weekdayAlarm(_ id: String = "A", at hour: Int = 7, armedAt: Date = t(1, 20)) -> AlarmConfig {
    AlarmConfig(id: id, time: TimeOfDay(hour), repeatDays: Weekday.weekdays, armedAt: armedAt)
}

/// 一次准时起床（闹钟响，1 分钟后关）。
func onTimeMorning(_ d: Int, id: String = "A") -> [LoggedEvent] {
    [
        LoggedEvent(id: "\(id)-fire-\(d)", event: .alarmFired(alarmID: id, at: t(d, 7))),
        LoggedEvent(id: "\(id)-stop-\(d)", event: .alarmStopped(alarmID: id, via: .petCat, at: t(d, 7, 1))),
    ]
}

@Suite("闹钟排程")
struct AlarmScheduleTests {
    let cal = calendar()

    @Test("工作日闹钟：周五晚上算出下周一")
    func weekdaysSkipWeekend() {
        let alarm = weekdayAlarm()
        #expect(AlarmSchedule.nextFire(of: alarm, after: t(6, 21), calendar: cal) == t(9, 7)) // 11-06 周五 → 11-09 周一
        #expect(AlarmSchedule.nextFire(of: alarm, after: t(2, 6, 59), calendar: cal) == t(2, 7))
        #expect(AlarmSchedule.nextFire(of: alarm, after: t(2, 7), calendar: cal) == t(3, 7)) // 不含当前时刻
    }

    @Test("每天响的闹钟")
    func everyday() {
        let alarm = AlarmConfig(id: "A", time: TimeOfDay(8, 30), repeatDays: Weekday.everyday, armedAt: t(1, 0))
        #expect(AlarmSchedule.nextFire(of: alarm, after: t(7, 9), calendar: cal) == t(8, 8, 30))
    }

    @Test("一次性闹钟：只在设置之后的第一个时刻响，过了就不再响")
    func oneShot() {
        let alarm = AlarmConfig(id: "nap", time: TimeOfDay(14), armedAt: t(2, 13))
        #expect(AlarmSchedule.nextFire(of: alarm, after: t(2, 13, 30), calendar: cal) == t(2, 14))
        #expect(AlarmSchedule.nextFire(of: alarm, after: t(2, 15), calendar: cal) == nil)
        let tomorrow = AlarmConfig(id: "nap", time: TimeOfDay(14), armedAt: t(2, 15))
        #expect(AlarmSchedule.nextFire(of: tomorrow, after: t(2, 15), calendar: cal) == t(3, 14))
    }

    @Test("关掉的闹钟不响；多个闹钟取最早")
    func disabledAndEarliest() {
        var a = weekdayAlarm("A", at: 7)
        let b = weekdayAlarm("B", at: 6)
        #expect(AlarmSchedule.nextFire(of: [a, b], after: t(2, 0), calendar: cal) == t(2, 6))
        a.isEnabled = false
        #expect(AlarmSchedule.nextFire(of: a, after: t(2, 0), calendar: cal) == nil)
    }

    @Test("夏令时开始当天不存在的 02:30 顺延，闹钟照样会响")
    func dstGap() {
        let ny = calendar(newYork)
        let alarm = AlarmConfig(id: "A", time: TimeOfDay(2, 30), repeatDays: Weekday.everyday, armedAt: t(1, 0, tz: newYork))
        let fire = AlarmSchedule.nextFire(of: alarm, after: t(14, 0, month: 3, year: 2027, tz: newYork), calendar: ny)!
        #expect(ny.component(.day, from: fire) == 14)
        #expect(fire > t(14, 0, month: 3, year: 2027, tz: newYork))
    }
}

@Suite("闹钟数量限制")
struct AlarmLimitTests {
    @Test("免费用户只能开 1 个闹钟；关着的闹钟不占名额")
    func freeLimit() throws {
        var world = try makeWorld()
        try world.setAlarm(weekdayAlarm("A"), isPlus: false)
        #expect(throws: WorldError.alarmLimitReached(limit: 1)) {
            try world.setAlarm(weekdayAlarm("B", at: 8), isPlus: false)
        }
        var off = weekdayAlarm("B", at: 8)
        off.isEnabled = false
        try world.setAlarm(off, isPlus: false)
        // 修改已经开着的那个不受影响
        try world.setAlarm(weekdayAlarm("A", at: 6), isPlus: false)
        #expect(world.state.alarms.count == 2)
    }

    @Test("Plus 不限；到期后只保留最快会响的那个")
    func plusAndLapse() throws {
        var world = try makeWorld()
        try world.setAlarm(weekdayAlarm("late", at: 9), isPlus: true)
        try world.setAlarm(weekdayAlarm("early", at: 6), isPlus: true)
        try world.setAlarm(weekdayAlarm("mid", at: 7), isPlus: true)
        let disabled = world.enforceAlarmLimit(isPlus: false, now: t(1, 21))
        #expect(Set(disabled) == ["late", "mid"])
        #expect(world.state.alarms.filter(\.isEnabled).map(\.id) == ["early"])
        #expect(world.enforceAlarmLimit(isPlus: true, now: t(1, 21)).isEmpty)
    }

    @Test("删除闹钟")
    func remove() throws {
        var world = try makeWorld()
        try world.setAlarm(weekdayAlarm("A"), isPlus: false)
        try world.removeAlarm(id: "A")
        #expect(world.state.alarms.isEmpty)
        #expect(throws: WorldError.unknownAlarm("A")) { try world.removeAlarm(id: "A") }
    }
}

@Suite("事件只处理一次")
struct IdempotencyTests {
    @Test("同一批事件提交两次，奖励只发一次")
    func resubmit() throws {
        var world = try makeWorld()
        let first = world.ingest(onTimeMorning(2), isPlus: false)
        #expect(first.grants.map(\.fish) == [10])
        let second = world.ingest(onTimeMorning(2), isPlus: false)
        #expect(second.outputs.isEmpty)
        #expect(second.skippedEvents == 2)
        #expect(world.state.economy.wallet.fish == 10)
    }

    @Test("同一批里重复的 id 只处理第一条")
    func duplicatesInBatch() throws {
        var world = try makeWorld()
        let events = onTimeMorning(2)
        let update = world.ingest(events + events, isPlus: false)
        #expect(update.skippedEvents == 2)
        #expect(update.grants.count == 1)
    }

    @Test("日志顺序乱了也按时间处理")
    func outOfOrder() throws {
        var world = try makeWorld()
        let update = world.ingest(onTimeMorning(2).reversed(), isPlus: false)
        #expect(update.transitions == [.t8, .x8, .t1, .t2])
        #expect(update.grants.count == 1)
    }

    @Test("保存再读取之后重新提交，也不会重复发奖励")
    func survivesPersistence() throws {
        var world = try makeWorld()
        world.ingest(onTimeMorning(2), isPlus: false)
        let data = try JSONEncoder().encode(world.state)
        let restoredState = try JSONDecoder().decode(WorldState.self, from: data)
        #expect(restoredState == world.state)
        var restored = CatWorld(state: restoredState, catConfig: world.catConfig, economy: world.economy)
        #expect(restored.ingest(onTimeMorning(2), isPlus: false).grants.isEmpty)
        #expect(restored.state.economy.wallet.fish == 10)
    }

    @Test("比保留期更旧的事件当作过期丢弃，已处理 id 也会被清理")
    func staleEventsAndPruning() throws {
        var world = try makeWorld()
        world.ingest(onTimeMorning(2), isPlus: false)
        #expect(world.state.processedEventIDs.count == 2)
        world.foreground(at: t(20, 12), isPlus: false) // 18 天后
        world.ingest([], isPlus: false)
        #expect(world.state.processedEventIDs.isEmpty)
        let stale = world.ingest([LoggedEvent(id: "old", event: .alarmFired(alarmID: "A", at: t(3, 7)))], isPlus: false)
        #expect(stale.skippedEvents == 1)
        #expect(stale.outputs.isEmpty)
    }
}

@Suite("一个早晨")
struct MorningTests {
    @Test("免费用户第一次准时起床：10 小鱼干 + 礼物 + DayLog + 付费墙")
    func firstOnTimeWakeFree() throws {
        var world = try makeWorld()
        try world.setAlarm(weekdayAlarm(), isPlus: false)
        let update = world.ingest(onTimeMorning(2), isPlus: false)
        #expect(update.grants.count == 1)
        #expect(update.grants[0].fish == 10)
        #expect(update.grants[0].items.count == 1)
        #expect(update.prompts == [.paywall(.firstOnTimeGift)])
        #expect(world.state.dayLogs[day(2)]?.wokeOnTime == true)
        #expect(world.state.dayLogs[day(2)]?.snoozeCount == 0)
        #expect(world.state.cat.state == .givingGift)
    }

    @Test("Plus 用户：小鱼干翻倍，不弹付费墙")
    func firstOnTimeWakePlus() throws {
        var world = try makeWorld()
        let update = world.ingest(onTimeMorning(2), isPlus: true)
        #expect(update.grants[0].fish == 20)
        #expect(update.prompts.isEmpty)
    }

    @Test("贪睡的早晨：没有奖励，DayLog 记贪睡次数")
    func snoozedMorning() throws {
        var world = try makeWorld()
        let update = world.ingest([
            LoggedEvent(id: "1", event: .alarmFired(alarmID: "A", at: t(2, 7))),
            LoggedEvent(id: "2", event: .alarmSnoozed(alarmID: "A", at: t(2, 7, 1))),
            LoggedEvent(id: "3", event: .alarmFired(alarmID: "A", at: t(2, 7, 10))),
            LoggedEvent(id: "4", event: .alarmStopped(alarmID: "A", via: .lockScreen, at: t(2, 7, 11))),
        ], isPlus: false)
        #expect(update.grants.isEmpty)
        #expect(update.effects.contains(.messAdded(.snooze(.stepOnFace))))
        #expect(world.state.dayLogs[day(2)]?.wokeOnTime == false)
        #expect(world.state.dayLogs[day(2)]?.snoozeCount == 1)
    }

    @Test("第 3 次准时起床后请求评分，只请求一次；付费墙只在第 1 次")
    func reviewAfterThirdWake() throws {
        var world = try makeWorld()
        var prompts: [[WorldPrompt]] = []
        for d in 2...5 {
            prompts.append(world.ingest(onTimeMorning(d), isPlus: false).prompts)
        }
        #expect(prompts == [[.paywall(.firstOnTimeGift)], [], [.requestReview], []])
        #expect(world.state.milestones.onTimeWakes == 4)
    }

    @Test("新手引导结束弹一次付费墙；Plus 不弹")
    func onboardingPaywall() throws {
        var free = try makeWorld()
        #expect(free.completeOnboarding(at: t(1, 20, 5), isPlus: false) == [.paywall(.onboardingFinished)])
        #expect(free.completeOnboarding(at: t(1, 20, 6), isPlus: false).isEmpty)
        var plus = try makeWorld()
        #expect(plus.completeOnboarding(at: t(1, 20, 5), isPlus: true).isEmpty)
    }
}

@Suite("闹钟和猫联动")
struct AlarmIntegrationTests {
    @Test("一次性闹钟响过之后自动关掉")
    func oneShotDisablesAfterFiring() throws {
        var world = try makeWorld()
        try world.setAlarm(AlarmConfig(id: "once", time: TimeOfDay(7), armedAt: t(1, 20)), isPlus: false)
        #expect(world.nextAlarmAt(after: t(1, 21)) == t(2, 7))
        world.ingest([LoggedEvent(id: "f", event: .alarmFired(alarmID: "once", at: t(2, 7)))], isPlus: false)
        #expect(world.state.alarms[0].isEnabled == false)
        #expect(world.nextAlarmAt(after: t(2, 8)) == nil)
    }

    @Test("没有闹钟的早晨：回到前台时猫在早晨自己醒来（X9）")
    func noAlarmMorning() throws {
        var world = try makeWorld()
        let update = world.foreground(at: t(2, 11), isPlus: false)
        #expect(update.transitions == [.t8, .x8, .x9])
        #expect(world.state.cat.state == .idleDaytime)
    }

    @Test("今天 11:00 还有闹钟：10:30 打开 App 时猫继续睡")
    func lateAlarmKeepsSleeping() throws {
        var world = try makeWorld()
        try world.setAlarm(AlarmConfig(id: "late", time: TimeOfDay(11), repeatDays: Weekday.everyday, armedAt: t(1, 20)), isPlus: false)
        world.foreground(at: t(2, 10, 30), isPlus: false)
        #expect(world.state.cat.state == .sleepingAtNight)
    }

    @Test("tick 也会带上闹钟排程")
    func tickUsesSchedule() throws {
        var world = try makeWorld()
        try world.setAlarm(weekdayAlarm(), isPlus: false)
        world.tick(at: t(2, 3), isPlus: false)
        #expect(world.state.cat.state == .sleepingAtNight)
    }
}

@Suite("每日记录")
struct DayLogTests {
    @Test("番茄钟完成才计分钟；读书没读完也计")
    func sessions() throws {
        var world = try makeWorld(at: t(2, 9))
        world.ingest([
            LoggedEvent(id: "1", event: .sessionStarted(.focus, at: t(2, 10))),
            LoggedEvent(id: "2", event: .sessionEnded(.focus, completed: true, at: t(2, 10, 25))),
            LoggedEvent(id: "3", event: .sessionStarted(.focus, at: t(2, 11))),
            LoggedEvent(id: "4", event: .sessionEnded(.focus, completed: false, at: t(2, 11, 10))),
            LoggedEvent(id: "5", event: .sessionStarted(.read, at: t(2, 14))),
            LoggedEvent(id: "6", event: .sessionEnded(.read, completed: false, at: t(2, 14, 40))),
        ], isPlus: false)
        let log = try #require(world.state.dayLogs[day(2)])
        #expect(log.focusMinutes == 25)
        #expect(log.completedFocusSessions == 1)
        #expect(log.readingMinutes == 40)
        #expect(world.state.economy.wallet.fish == 5)
    }

    @Test("00:20 入睡记在前一个逻辑日")
    func sleepAfterMidnight() throws {
        var world = try makeWorld(at: t(2, 22))
        world.ingest([
            LoggedEvent(id: "1", event: .bedtimeTimerStarted(duration: 30 * 60, at: t(2, 23, 50))),
            LoggedEvent(id: "2", event: .bedtimeTimerEnded(at: t(3, 0, 20))),
        ], isPlus: false)
        #expect(world.state.dayLogs[day(2)]?.sleptAt == t(3, 0, 20))
    }

    @Test("写入步数")
    func steps() throws {
        var world = try makeWorld()
        world.recordSteps(8421, on: day(2))
        #expect(world.state.dayLogs[day(2)]?.steps == 8421)
    }
}

@Suite("商店和房间")
struct ShopTests {
    @Test("卖掉早餐礼物、买纸箱、收拾乱子")
    func buySellClean() throws {
        var world = try makeWorld()
        world.ingest(onTimeMorning(2), isPlus: false)
        let gift = try #require(world.state.economy.items.first { world.economy.catalog.item($0.catalogID)?.kind == .gift })
        let fish = try world.sell(itemID: gift.id)
        #expect(world.state.economy.wallet.fish == 10 + fish)
        try world.buy("furniture.cardboard_box", isPlus: false, at: t(2, 8))
        #expect(world.state.economy.owns("furniture.cardboard_box"))

        world.ingest([
            LoggedEvent(id: "f", event: .alarmFired(alarmID: "nap", at: t(2, 14))),
        ], isPlus: false)
        #expect(world.state.cat.messCount == 0)
        world.ingest([LoggedEvent(id: "f3", event: .alarmFired(alarmID: "A", at: t(3, 7))),
                      LoggedEvent(id: "s3", event: .alarmSnoozed(alarmID: "A", at: t(3, 7, 1)))], isPlus: false)
        #expect(world.state.cat.messCount == 1)
        world.clearMess(at: t(3, 8), isPlus: false)
        #expect(world.state.cat.messCount == 0)
    }
}

@Suite("一周模拟")
struct WeekSimulationTests {
    @Test("工作日闹钟，一周里 3 天准时、2 天贪睡，周末自然醒")
    func week() throws {
        var world = try makeWorld()
        try world.setAlarm(weekdayAlarm(), isPlus: false)
        for d in 2...8 { // 11-02 周一 … 11-08 周日
            let weekday = calendar().component(.weekday, from: t(d, 12))
            if weekday == 1 || weekday == 7 {
                world.foreground(at: t(d, 11), isPlus: false)
            } else if d % 2 == 0 {
                world.ingest(onTimeMorning(d), isPlus: false)
                world.ingest([LoggedEvent(id: "gift-\(d)", event: .giftCollected(at: t(d, 7, 2)))], isPlus: false)
            } else {
                world.ingest([
                    LoggedEvent(id: "f-\(d)", event: .alarmFired(alarmID: "A", at: t(d, 7))),
                    LoggedEvent(id: "z-\(d)", event: .alarmSnoozed(alarmID: "A", at: t(d, 7, 1))),
                    LoggedEvent(id: "s-\(d)", event: .alarmStopped(alarmID: "A", via: .petCat, at: t(d, 7, 5))),
                ], isPlus: false)
            }
        }
        let logs = (2...6).map { world.state.dayLogs[day($0)]?.wokeOnTime }
        #expect(logs == [true, false, true, false, true])
        #expect(world.state.dayLogs[day(7)]?.wokeOnTime == nil)
        #expect(world.state.economy.wallet.fish == 30)
        #expect(world.state.milestones.onTimeWakes == 3)
        #expect(world.state.milestones.reviewRequested)
        #expect(world.state.cat.messCount == 2)
        #expect(world.state.cat.state == .idleDaytime)
    }
}
