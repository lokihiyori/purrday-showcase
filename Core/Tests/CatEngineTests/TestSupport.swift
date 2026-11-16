import Foundation
@testable import CatEngine

/// 测试统一用没有夏令时的上海时区，夏令时测试单独指定。
let shanghai = TimeZone(identifier: "Asia/Shanghai")!
let newYork = TimeZone(identifier: "America/New_York")!

func makeCalendar(_ tz: TimeZone = shanghai) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = tz
    return calendar
}

func makeConfig(_ tz: TimeZone = shanghai, _ adjust: (inout CatEngineConfig) -> Void = { _ in }) -> CatEngineConfig {
    var config = CatEngineConfig(calendar: makeCalendar(tz))
    adjust(&config)
    return config
}

/// 2026 年某月某日的当地时间（默认 11 月、上海时区）。
func t(_ day: Int, _ hour: Int, _ minute: Int = 0, _ second: Int = 0, month: Int = 11, year: Int = 2026, tz: TimeZone = shanghai) -> Date {
    makeCalendar(tz).date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
}

func makeMachine(
    _ state: CatState,
    at date: Date,
    config: CatEngineConfig = makeConfig(),
    _ adjust: (inout CatSnapshot) -> Void = { _ in }
) -> CatMachine {
    var snapshot = CatSnapshot(state: state, at: date)
    adjust(&snapshot)
    return CatMachine(config: config, snapshot: snapshot)
}

/// 11 月 1 日 23:30 入睡（已经过了当天的睡前时间），等 11 月 2 日的闹钟。
func asleepMachine(config: CatEngineConfig = makeConfig()) -> CatMachine {
    makeMachine(.sleepingAtNight, at: t(1, 23, 30), config: config) {
        $0.lastBedtimeDay = LogicalDay(year: 2026, month: 11, day: 1)
        $0.lastWakeDay = LogicalDay(year: 2026, month: 11, day: 1)
    }
}

/// 11 月 2 日 07:00 闹钟 A 刚响，处在叫醒中。
func ringingMachine(config: CatEngineConfig = makeConfig()) -> CatMachine {
    var machine = asleepMachine(config: config)
    machine.handle(.alarmFired(alarmID: "A", at: t(2, 7)))
    return machine
}

/// 11 月 2 日白天，今天已经叫醒过，处在白天待机。
func daytimeMachine(at date: Date = t(2, 12), config: CatEngineConfig = makeConfig()) -> CatMachine {
    makeMachine(.idleDaytime, at: date, config: config) {
        $0.lastWakeDay = LogicalDay(year: 2026, month: 11, day: 2)
        $0.lastBedtimeDay = LogicalDay(year: 2026, month: 11, day: 1)
    }
}

extension Array where Element == CatOutput {
    var transitions: [TransitionID] {
        compactMap { if case let .transition(id, _, _, _) = $0 { id } else { nil } }
    }

    var rewards: [CatReward] {
        compactMap { if case let .reward(reward) = $0 { reward } else { nil } }
    }

    var effects: [CatEffect] {
        compactMap { if case let .effect(effect) = $0 { effect } else { nil } }
    }

    var transitionTimes: [Date] {
        compactMap { if case let .transition(_, _, _, at) = $0 { at } else { nil } }
    }
}
