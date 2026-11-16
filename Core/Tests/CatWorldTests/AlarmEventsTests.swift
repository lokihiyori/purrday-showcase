import CatEngine
import Economy
import Foundation
import Testing
@testable import CatWorld

@Suite("系统闹钟事件")
struct AlarmEventsTests {
    let cal = calendar()

    @Test("最近一次响铃：工作日闹钟、跨周末、一次性")
    func previousFire() {
        let alarm = weekdayAlarm()
        #expect(AlarmSchedule.previousFire(of: alarm, atOrBefore: t(2, 7, 1), calendar: cal) == t(2, 7))
        #expect(AlarmSchedule.previousFire(of: alarm, atOrBefore: t(2, 7), calendar: cal) == t(2, 7)) // 含当前时刻
        #expect(AlarmSchedule.previousFire(of: alarm, atOrBefore: t(9, 6), calendar: cal) == t(6, 7)) // 周一早上 6 点 → 上周五
        let once = AlarmConfig(id: "once", time: TimeOfDay(7), isEnabled: false, armedAt: t(1, 20))
        #expect(AlarmSchedule.previousFire(of: once, atOrBefore: t(2, 7, 5), calendar: cal) == t(2, 7))
        #expect(AlarmSchedule.previousFire(of: once, atOrBefore: t(2, 6), calendar: cal) == nil)
    }

    @Test("锁屏上 1 分钟内停止：按排程补记 7:00 响铃，算准时")
    func lockScreenStopOnTime() throws {
        var world = try makeWorld()
        try world.setAlarm(weekdayAlarm(), isPlus: false)
        let events = world.alarmEvents(.stopped, alarmID: "A", at: t(2, 7, 1))
        #expect(events.map(\.event) == [.alarmFired(alarmID: "A", at: t(2, 7)), .alarmStopped(alarmID: "A", via: .lockScreen, at: t(2, 7, 1))])
        let update = world.ingest(events, isPlus: false)
        #expect(update.transitions.last == .t2)
    }

    @Test("响了 10 分钟才在锁屏上停止：不算准时（不是按停止时间补记响铃）")
    func lockScreenStopLate() throws {
        var world = try makeWorld()
        try world.setAlarm(weekdayAlarm(), isPlus: false)
        let update = world.ingest(world.alarmEvents(.stopped, alarmID: "A", at: t(2, 7, 10)), isPlus: false)
        #expect(update.transitions.last == .x1)
        #expect(update.grants.isEmpty)
    }

    @Test("App 内看到响铃 + 锁屏停止：同一次响铃只记一次")
    func dedupeAcrossPaths() throws {
        var world = try makeWorld()
        try world.setAlarm(weekdayAlarm(), isPlus: false)
        world.ingest(world.alarmEvents(.alerting, alarmID: "A", at: t(2, 7, 0, 3)), isPlus: false)
        let stop = world.ingest(world.alarmEvents(.stopped, alarmID: "A", at: t(2, 7, 1)), isPlus: false)
        #expect(stop.skippedEvents == 1)
        #expect(stop.transitions == [.t2])
    }

    @Test("锁屏贪睡 → 倒计时结束再次响铃 → 停止：走捣乱循环")
    func snoozeThenRefire() throws {
        var world = try makeWorld()
        try world.setAlarm(weekdayAlarm(), isPlus: false)
        let snooze = world.ingest(world.alarmEvents(.snoozed, alarmID: "A", at: t(2, 7, 1)), isPlus: false)
        #expect(snooze.transitions == [.t8, .x8, .t1, .t4])
        let refire = world.ingest(world.alarmEvents(.alerting, alarmID: "A", at: t(2, 7, 10)), isPlus: false)
        #expect(refire.transitions == [.t5])
        let stop = world.ingest(world.alarmEvents(.stopped, alarmID: "A", at: t(2, 7, 11)), isPlus: false)
        #expect(stop.transitions == [.x1])
    }

    @Test("找不到闹钟设置时按当前时间记（宁可给奖励，也不因为数据缺失扣掉）")
    func unknownAlarm() throws {
        var world = try makeWorld()
        let events = world.alarmEvents(.stopped, alarmID: "ghost", at: t(2, 7, 30))
        #expect(events.first?.event == .alarmFired(alarmID: "ghost", at: t(2, 7, 30)))
        #expect(world.ingest(events, isPlus: false).transitions.last == .t2)
    }
}
