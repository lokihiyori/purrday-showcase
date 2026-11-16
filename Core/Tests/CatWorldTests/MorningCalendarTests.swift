import CatEngine
import Economy
import Foundation
import Testing
@testable import CatWorld

@Suite("起床日历")
struct MorningCalendarTests {
    /// 2 号、3 号准时，4 号赖床，5 号没闹钟，6 号准时
    private func world() throws -> CatWorld {
        var world = try makeWorld()
        for (d, onTime, snoozes) in [(2, true, 0), (3, true, 0), (4, false, 2), (6, true, 0)] {
            var log = DayLog(day: day(d))
            log.wokeOnTime = onTime
            log.snoozeCount = snoozes
            world.state.dayLogs[day(d)] = log
        }
        world.state.dayLogs[day(5)] = DayLog(day: day(5))
        world.state.dayLogs[day(3)]?.sleptAt = t(3, 23)
        return world
    }

    @Test("每天的爪印：准时、赖床（带贪睡次数）、没有闹钟")
    func marks() throws {
        let world = try world()
        #expect(world.morningMark(day(2)) == .onTime)
        #expect(world.morningMark(day(4)) == .late(snoozes: 2))
        #expect(world.morningMark(day(5)) == .none)
        #expect(world.morningMark(day(20)) == .none)
        #expect(world.onTimeMornings == 3)
    }

    @Test("一个月的格子：按星期补空，一共那么多天；标出今天、还没到的日子、用了睡前模式的晚上")
    func month() throws {
        let world = try world()
        let cells = world.calendarMonth(year: 2026, month: 11, today: t(6, 12))
        let days = cells.compactMap { $0 }
        #expect(days.count == 30)
        // 2026-11-01 是周日；补几个空看日历从周几开始
        let leading = cells.prefix { $0 == nil }.count
        #expect(leading == (1 - world.catConfig.calendar.firstWeekday + 7) % 7)
        #expect(days[5].isToday && !days[5].isFuture)
        #expect(days[6].isFuture && !days[4].isFuture)
        #expect(days[2].bedtime && !days[1].bedtime)
        #expect(days[3].mark == .late(snoozes: 2))
        #expect(world.calendarMonth(year: 2026, month: 2, today: t(6, 12)).compactMap { $0 }.count == 28)
    }

    @Test("连续准时：赖床才断，没闹钟的日子不算断；今天还没起也不清零")
    func streak() throws {
        let world = try world()
        #expect(world.wakeStreak(asOf: t(3, 12)) == 2)
        #expect(world.wakeStreak(asOf: t(4, 12)) == 0)
        #expect(world.wakeStreak(asOf: t(6, 12)) == 1) // 5 号没闹钟，不断；4 号赖床，断在那里
        #expect(world.wakeStreak(asOf: t(9, 12)) == 1) // 之后几天没记录
        #expect(world.bestWakeStreak == 2)
        #expect(try makeWorld().wakeStreak(asOf: t(6, 12)) == 0)
    }

    @Test("真的准时起床以后，日历上就有爪印")
    func fromRealMorning() throws {
        var world = try makeWorld()
        try world.setAlarm(weekdayAlarm(), isPlus: false)
        world.ingest(onTimeMorning(2), isPlus: false)
        #expect(world.morningMark(day(2)) == .onTime)
        #expect(world.wakeStreak(asOf: t(2, 12)) == 1)
    }
}
