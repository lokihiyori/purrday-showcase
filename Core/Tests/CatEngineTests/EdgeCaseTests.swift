import Foundation
import Testing
@testable import CatEngine

// 规格第 4 节的边界情况。

@Suite("4.1 跨午夜")
struct CrossMidnightTests {
    let config = makeConfig()

    @Test("逻辑日从 04:00 开始：03:59 属于前一天，04:00 属于当天")
    func logicalDayBoundary() {
        #expect(config.logicalDay(of: t(2, 3, 59)) == LogicalDay(year: 2026, month: 11, day: 1))
        #expect(config.logicalDay(of: t(2, 4)) == LogicalDay(year: 2026, month: 11, day: 2))
        #expect(config.logicalDay(of: t(2, 0)) == LogicalDay(year: 2026, month: 11, day: 1))
    }

    @Test("跨月、跨年的逻辑日")
    func logicalDayAcrossMonthAndYear() {
        #expect(config.logicalDay(of: t(1, 1)) == LogicalDay(year: 2026, month: 10, day: 31))
        #expect(config.logicalDay(of: t(1, 1, month: 1, year: 2027)) == LogicalDay(year: 2026, month: 12, day: 31))
    }

    @Test("早于 04:00 的时刻属于下一个日历日")
    func timeInLogicalDay() {
        let day = LogicalDay(year: 2026, month: 11, day: 1)
        #expect(config.date(TimeOfDay(23), in: day) == t(1, 23))
        #expect(config.date(TimeOfDay(0, 30), in: day) == t(2, 0, 30))
        #expect(config.date(TimeOfDay(2), in: day) == t(2, 2))
    }

    @Test("00:20 入睡记在前一个逻辑日")
    func sleepAfterMidnight() {
        var machine = daytimeMachine(at: t(2, 22))
        machine.handle(.bedtimeTimerStarted(duration: 30 * 60, at: t(2, 23, 50)))
        let out = machine.handle(.bedtimeTimerEnded(at: t(3, 0, 20)))
        #expect(out.effects.contains(.sleepRecorded(at: t(3, 0, 20), day: LogicalDay(year: 2026, month: 11, day: 2))))
    }

    @Test("睡前时间设在午夜之后（00:30）：T8 在第二个日历日 00:30 触发，记在前一个逻辑日")
    func bedtimeAfterMidnight() {
        let config = makeConfig { $0.bedtime = TimeOfDay(0, 30) }
        var machine = daytimeMachine(at: t(2, 20), config: config)
        #expect(machine.handle(.tick(at: t(2, 23, 59), nextAlarmAt: nil)).isEmpty)
        let out = machine.handle(.tick(at: t(3, 0, 40), nextAlarmAt: nil))
        #expect(out.transitions == [.t8])
        #expect(out.transitionTimes == [t(3, 0, 30)])
        #expect(machine.snapshot.lastBedtimeDay == LogicalDay(year: 2026, month: 11, day: 2))
    }

    @Test("新的一天才能再拿准时礼物：凌晨 03:30 的闹钟属于前一个逻辑日，不再发奖励")
    func earlyMorningAlarmBelongsToPreviousDay() {
        var machine = asleepMachine()
        machine.handle(.alarmFired(alarmID: "A", at: t(2, 7)))
        machine.handle(.alarmStopped(alarmID: "A", via: .petCat, at: t(2, 7, 1)))
        // 当晚 T8 → X8 入睡，凌晨 03:30 有一个闹钟
        machine.handle(.tick(at: t(3, 2, 30), nextAlarmAt: t(3, 3, 30)))
        #expect(machine.state == .sleepingAtNight)
        machine.handle(.alarmFired(alarmID: "early", at: t(3, 3, 30)))
        #expect(machine.snapshot.wake?.rewardEligible == false)
    }

    @Test("夏令时结束（纽约 2026-11-01）：重复的 01:xx 都属于前一个逻辑日，X8 在当地 02:00 触发")
    func dstFallBack() {
        let config = makeConfig(newYork)
        let edt = t(1, 1, 30, tz: newYork) // 第一次 01:30（EDT）
        let est = edt.addingTimeInterval(3600) // 第二次 01:30（EST）
        #expect(config.logicalDay(of: edt) == LogicalDay(year: 2026, month: 10, day: 31))
        #expect(config.logicalDay(of: est) == LogicalDay(year: 2026, month: 10, day: 31))

        var machine = makeMachine(.idleDaytime, at: t(31, 20, month: 10, tz: newYork), config: config)
        let out = machine.handle(.tick(at: t(1, 3, tz: newYork), nextAlarmAt: nil))
        #expect(out.transitions == [.t8, .x8])
        #expect(out.transitionTimes[1] == t(1, 2, tz: newYork))
        // 23:00 到 02:00 这一晚有 4 个小时
        #expect(out.transitionTimes[1].timeIntervalSince(out.transitionTimes[0]) == 4 * 3600)
    }

    @Test("夏令时开始（纽约 2027-03-14）：不存在的 02:00 顺延，X8 照样触发")
    func dstSpringForward() {
        let config = makeConfig(newYork)
        var machine = makeMachine(.idleDaytime, at: t(13, 20, month: 3, year: 2027, tz: newYork), config: config)
        let out = machine.handle(.tick(at: t(14, 5, month: 3, year: 2027, tz: newYork), nextAlarmAt: nil))
        #expect(out.transitions == [.t8, .x8])
        #expect(out.transitionTimes[1] == t(14, 3, month: 3, year: 2027, tz: newYork))
        #expect(machine.state == .sleepingAtNight)
    }
}

@Suite("4.2 连续贪睡 3 次以上")
struct RepeatedSnoozeTests {
    @Test("动画升级到第 3 次后保持躺在手机上；乱子最多 3 个；DayLog 记真实次数")
    func fiveSnoozes() {
        var machine = ringingMachine()
        var kinds: [MischiefKind] = []
        var messes = 0
        for i in 0..<5 {
            let base = t(2, 7).addingTimeInterval(TimeInterval(i * 600))
            if i > 0 { machine.handle(.alarmFired(alarmID: "A", at: base)) }
            let out = machine.handle(.alarmSnoozed(alarmID: "A", at: base.addingTimeInterval(30)))
            #expect(out.transitions == [.t4])
            kinds.append(machine.snapshot.mischief!)
            messes += out.effects.filter { if case .messAdded = $0 { true } else { false } }.count
        }
        #expect(kinds == [.stepOnFace, .pushCup, .lieOnPhone, .lieOnPhone, .lieOnPhone])
        #expect(messes == 3)
        #expect(machine.snapshot.messCount == 3)

        let out = machine.handle(.alarmStopped(alarmID: "A", via: .petCat, at: t(2, 7, 41)))
        #expect(out.transitions == [.x2])
        #expect(out.rewards.isEmpty)
        #expect(out.effects == [.wakeRecorded(onTime: false, snoozeCount: 5, day: LogicalDay(year: 2026, month: 11, day: 2))])
    }

    @Test("收拾掉乱子后，下次贪睡可以再加")
    func messCapAfterCleaning() {
        var machine = ringingMachine()
        machine.snapshotForTesting { $0.messCount = 3 }
        #expect(machine.handle(.alarmSnoozed(alarmID: "A", at: t(2, 7, 1))).effects.isEmpty)
        machine.handle(.messCleared(at: t(2, 7, 2)))
        #expect(machine.snapshot.messCount == 2)
        machine.handle(.alarmFired(alarmID: "A", at: t(2, 7, 10)))
        let out = machine.handle(.alarmSnoozed(alarmID: "A", at: t(2, 7, 11)))
        #expect(out.effects == [.messAdded(.snooze(.pushCup))])
    }

    @Test("收拾乱子不会变成负数")
    func messNeverNegative() {
        var machine = daytimeMachine()
        machine.handle(.messCleared(at: t(2, 13)))
        #expect(machine.snapshot.messCount == 0)
    }
}

@Suite("4.3 闹钟响时 App 没打开")
struct AppNotOpenTests {
    @Test("前一晚 21:00 之后没打开 App，锁屏上准时停止：回放得到 T8 → X8 → T1 → T2 → T3")
    func replayLockScreenStop() {
        var machine = daytimeMachine(at: t(1, 21))
        machine.snapshotForTesting {
            $0.lastWakeDay = LogicalDay(year: 2026, month: 11, day: 1)
            $0.lastBedtimeDay = LogicalDay(year: 2026, month: 10, day: 31)
        }
        // App Intent 写进日志的事件，顺序可能是乱的
        let log: [CatEvent] = [
            .alarmStopped(alarmID: "A", via: .lockScreen, at: t(2, 7, 1)),
            .alarmFired(alarmID: "A", at: t(2, 7)),
        ]
        var out = machine.replay(log)
        out += machine.handle(.appForegrounded(at: t(2, 12)))
        #expect(out.transitions == [.t8, .x8, .t1, .t2, .t3])
        #expect(out.rewards == [.wakeGift(luckyBoost: false)])
        #expect(machine.state == .idleDaytime)
    }

    @Test("打开 App 时还在 30 分钟内：停在送早餐礼物，等用户领取")
    func giftStillShowing() {
        var machine = ringingMachine()
        machine.handle(.alarmStopped(alarmID: "A", via: .lockScreen, at: t(2, 7, 1)))
        machine.handle(.appForegrounded(at: t(2, 7, 20)))
        #expect(machine.state == .givingGift)
        let out = machine.handle(.appForegrounded(at: t(2, 7, 40)))
        #expect(out.transitions == [.t3])
        #expect(out.transitionTimes == [t(2, 7, 31)])
    }

    @Test("锁屏上贪睡了几次、App 一直没打开：回放捣乱循环，乱子照常留下")
    func replaySnoozes() {
        var machine = asleepMachine()
        let out = machine.replay([
            .alarmFired(alarmID: "A", at: t(2, 7)),
            .alarmSnoozed(alarmID: "A", at: t(2, 7, 1)),
            .alarmFired(alarmID: "A", at: t(2, 7, 10)),
            .alarmSnoozed(alarmID: "A", at: t(2, 7, 11)),
            .alarmFired(alarmID: "A", at: t(2, 7, 20)),
            .alarmStopped(alarmID: "A", via: .lockScreen, at: t(2, 7, 21)),
        ])
        #expect(out.transitions == [.t1, .t4, .t5, .t4, .t5, .x1])
        #expect(machine.snapshot.messCount == 2)
    }

    @Test("有响铃记录、没有关闭记录：30 分钟后按未知方式关闭，无奖励、不加乱子")
    func missingStopRecord() {
        var machine = ringingMachine()
        let out = machine.handle(.tick(at: t(2, 9), nextAlarmAt: t(3, 7)))
        #expect(out.transitions == [.x1])
        #expect(out.transitionTimes == [t(2, 7, 30)])
        #expect(out.rewards.isEmpty)
        #expect(machine.snapshot.messCount == 0)
        #expect(machine.state == .idleDaytime)
    }

    @Test("捣乱中丢了后续记录：距最后一次贪睡 30 分钟后走 X2")
    func missingRecordWhileSnoozed() {
        var machine = ringingMachine()
        machine.handle(.alarmSnoozed(alarmID: "A", at: t(2, 7, 1)))
        let out = machine.handle(.tick(at: t(2, 9), nextAlarmAt: t(3, 7)))
        #expect(out.transitions == [.x2])
        #expect(out.transitionTimes == [t(2, 7, 31)])
    }

    @Test("连响铃记录都没有：tick 时在早晨进入白天待机")
    func noRecordsAtAll() {
        var machine = asleepMachine()
        let out = machine.handle(.tick(at: t(2, 12), nextAlarmAt: t(3, 7)))
        #expect(out.transitions == [.x9])
    }

    @Test("快照可以编码再解码，继续处理事件")
    func snapshotRoundTrip() throws {
        var machine = ringingMachine()
        machine.handle(.alarmSnoozed(alarmID: "A", at: t(2, 7, 1)))
        let data = try JSONEncoder().encode(machine.snapshot)
        let decoded = try JSONDecoder().decode(CatSnapshot.self, from: data)
        #expect(decoded == machine.snapshot)
        var restored = CatMachine(config: machine.config, snapshot: decoded)
        #expect(restored.handle(.alarmFired(alarmID: "A", at: t(2, 7, 10))).transitions == [.t5])
    }

    @Test("事件可以编码成日志再解码")
    func eventRoundTrip() throws {
        let events: [CatEvent] = [
            .alarmStopped(alarmID: "A", via: .lockScreen, at: t(2, 7, 1)),
            .tick(at: t(2, 8), nextAlarmAt: nil),
            .sessionEnded(.focus, completed: true, at: t(2, 9)),
        ]
        let data = try JSONEncoder().encode(events)
        #expect(try JSONDecoder().decode([CatEvent].self, from: data) == events)
    }
}

@Suite("4.4 一天多个闹钟")
struct MultipleAlarmsTests {
    @Test("只有本逻辑日第一次叫醒能拿奖励：两个早晨闹钟，第二个没有奖励")
    func onlyFirstWakeRewarded() {
        var machine = ringingMachine()
        let first = machine.handle(.alarmStopped(alarmID: "A", via: .petCat, at: t(2, 7, 1)))
        #expect(first.rewards.count == 1)
        machine.handle(.giftCollected(at: t(2, 7, 2)))
        machine.handle(.alarmFired(alarmID: "B", at: t(2, 7, 30)))
        let second = machine.handle(.alarmStopped(alarmID: "B", via: .petCat, at: t(2, 7, 30, 30)))
        #expect(second.rewards.isEmpty)
        #expect(second.effects.isEmpty)
    }

    @Test("Plus 用户设 10 个闹钟也刷不了小鱼干")
    func cannotFarmWithManyAlarms() {
        var machine = asleepMachine()
        var rewards: [CatReward] = []
        for i in 0..<10 {
            let at = t(2, 7).addingTimeInterval(TimeInterval(i * 15 * 60))
            rewards += machine.handle(.alarmFired(alarmID: "alarm\(i)", at: at)).rewards
            rewards += machine.handle(.alarmStopped(alarmID: "alarm\(i)", via: .petCat, at: at.addingTimeInterval(10))).rewards
            rewards += machine.handle(.giftCollected(at: at.addingTimeInterval(20))).rewards
        }
        #expect(rewards == [.wakeGift(luckyBoost: false)])
    }

    @Test("第二天的第一个闹钟又可以拿奖励")
    func nextDayRewardedAgain() {
        var machine = ringingMachine()
        machine.handle(.alarmStopped(alarmID: "A", via: .petCat, at: t(2, 7, 1)))
        machine.handle(.giftCollected(at: t(2, 7, 2)))
        machine.handle(.alarmFired(alarmID: "A", at: t(3, 7))) // 中间经过 T8、X8
        let out = machine.handle(.alarmStopped(alarmID: "A", via: .petCat, at: t(3, 7, 1)))
        #expect(out.rewards == [.wakeGift(luckyBoost: false)])
    }
}

@Suite("其他")
struct MiscTests {
    @Test("和当前状态无关的事件被忽略，不产生输出", arguments: [
        CatEvent.alarmSnoozed(alarmID: "A", at: t(2, 13)),
        .alarmStopped(alarmID: "A", via: .petCat, at: t(2, 13)),
        .giftCollected(at: t(2, 13)),
        .sessionEnded(.focus, completed: true, at: t(2, 13)),
        .bedtimeTimerEnded(at: t(2, 13)),
        .bedtimeDismissed(at: t(2, 13)),
        .appForegrounded(at: t(2, 13)),
    ])
    func ignoredInDaytime(event: CatEvent) {
        var machine = daytimeMachine()
        #expect(machine.handle(event).isEmpty)
        #expect(machine.state == .idleDaytime)
    }

    @Test("结束的 session 和正在进行的不是同一种，忽略")
    func mismatchedSessionEnd() {
        var machine = daytimeMachine()
        machine.handle(.sessionStarted(.focus, at: t(2, 14)))
        #expect(machine.handle(.sessionEnded(.read, completed: true, at: t(2, 14, 25))).isEmpty)
        #expect(machine.state == .accompanying(.focus))
    }

    @Test("刚安装就已经过了睡前时间：立即进入睡前呼噜")
    func freshInstallAfterBedtime() {
        var machine = makeMachine(.idleDaytime, at: t(2, 23, 30))
        let out = machine.handle(.tick(at: t(2, 23, 30), nextAlarmAt: t(3, 7)))
        #expect(out.transitions == [.t8])
        #expect(out.transitionTimes == [t(2, 23, 30)])
    }

    @Test("贪睡动画映射", arguments: [(0, MischiefKind.stepOnFace), (1, .stepOnFace), (2, .pushCup), (3, .lieOnPhone), (9, .lieOnPhone)])
    func mischiefMapping(count: Int, kind: MischiefKind) {
        #expect(MischiefKind.forSnooze(count) == kind)
    }
}

extension CatMachine {
    /// 仅测试用：直接修改快照。
    mutating func snapshotForTesting(_ adjust: (inout CatSnapshot) -> Void) {
        var snapshot = self.snapshot
        adjust(&snapshot)
        self = CatMachine(config: config, snapshot: snapshot)
    }
}
