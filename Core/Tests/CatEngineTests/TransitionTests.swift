import Foundation
import Testing
@testable import CatEngine

// 每条转换至少一个测试，编号对应 docs/cat-state-machine.md 第 3 节。

@Suite("计划书原图 T1–T9")
struct OriginalDiagramTests {
    @Test("T1 夜间熟睡 --闹钟响--> 叫醒中")
    func t1() {
        var machine = asleepMachine()
        let out = machine.handle(.alarmFired(alarmID: "A", at: t(2, 7)))
        #expect(out.transitions == [.t1])
        #expect(machine.state == .wakingUp)
        #expect(machine.snapshot.wake?.firstRingAt == t(2, 7))
        #expect(machine.snapshot.wake?.rewardEligible == true)
        #expect(machine.snapshot.wake?.snoozeCount == 0)
    }

    @Test("T2 叫醒中 --2 分钟内关闭--> 送早餐礼物，礼物 + 记录准时")
    func t2() {
        var machine = ringingMachine()
        let out = machine.handle(.alarmStopped(alarmID: "A", via: .petCat, at: t(2, 7, 1, 30)))
        #expect(out.transitions == [.t2])
        #expect(machine.state == .givingGift)
        #expect(out.rewards == [.wakeGift(luckyBoost: false)])
        #expect(out.effects == [.wakeRecorded(onTime: true, snoozeCount: 0, day: LogicalDay(year: 2026, month: 11, day: 2))])
    }

    @Test("T2 准时窗口边界：正好 2 分钟算准时，多 1 秒不算", arguments: [
        (120, TransitionID.t2), (121, TransitionID.x1),
    ])
    func t2Boundary(seconds: Int, expected: TransitionID) {
        var machine = ringingMachine()
        let out = machine.handle(.alarmStopped(alarmID: "A", via: .petCat, at: t(2, 7).addingTimeInterval(TimeInterval(seconds))))
        #expect(out.transitions == [expected])
    }

    @Test("T2 锁屏停止也算准时（规格 4.3 的默认方案）")
    func t2LockScreen() {
        var machine = ringingMachine()
        let out = machine.handle(.alarmStopped(alarmID: "A", via: .lockScreen, at: t(2, 7, 0, 30)))
        #expect(out.transitions == [.t2])
    }

    @Test("T3 送早餐礼物 --领取礼物 / 离开--> 白天待机", arguments: [true, false])
    func t3(collect: Bool) {
        var machine = ringingMachine()
        machine.handle(.alarmStopped(alarmID: "A", via: .petCat, at: t(2, 7, 1)))
        let at = t(2, 7, 2)
        let out = machine.handle(collect ? .giftCollected(at: at) : .dismissed(at: at))
        #expect(out.transitions == [.t3])
        #expect(machine.state == .idleDaytime)
        #expect(out.rewards.isEmpty) // 礼物在 T2 已经发了
    }

    @Test("T4 叫醒中 --按贪睡--> 捣乱：踩脸，加一个乱子，没有奖励")
    func t4() {
        var machine = ringingMachine()
        let out = machine.handle(.alarmSnoozed(alarmID: "A", at: t(2, 7, 1)))
        #expect(out.transitions == [.t4])
        #expect(machine.state == .makingMischief)
        #expect(machine.snapshot.mischief == .stepOnFace)
        #expect(out.effects == [.messAdded(.snooze(.stepOnFace))])
        #expect(out.rewards.isEmpty)
        #expect(machine.snapshot.messCount == 1)
    }

    @Test("T5 捣乱 --稍后再响--> 叫醒中，首次响铃时间不变")
    func t5() {
        var machine = ringingMachine()
        machine.handle(.alarmSnoozed(alarmID: "A", at: t(2, 7, 1)))
        let out = machine.handle(.alarmFired(alarmID: "A", at: t(2, 7, 10)))
        #expect(out.transitions == [.t5])
        #expect(machine.state == .wakingUp)
        #expect(machine.snapshot.wake?.firstRingAt == t(2, 7))
        #expect(machine.snapshot.wake?.snoozeCount == 1)
    }

    @Test("T6 白天待机 --开始任务--> 陪你做事", arguments: Activity.allCases)
    func t6(activity: Activity) {
        var machine = daytimeMachine()
        let out = machine.handle(.sessionStarted(activity, at: t(2, 14)))
        #expect(out.transitions == [.t6])
        #expect(machine.state == .accompanying(activity))
    }

    @Test("T7 陪你做事 --完成--> 白天待机：专注给 5 小鱼干，并记录 session")
    func t7Focus() {
        var machine = daytimeMachine()
        machine.handle(.sessionStarted(.focus, at: t(2, 14)))
        let out = machine.handle(.sessionEnded(.focus, completed: true, at: t(2, 14, 25)))
        #expect(out.transitions == [.t7])
        #expect(machine.state == .idleDaytime)
        #expect(out.rewards == [.focusCompleted])
        #expect(out.effects == [.sessionRecorded(.focus, start: t(2, 14), end: t(2, 14, 25), completed: true)])
    }

    @Test("T7 读书 / 散步完成本身不给小鱼干（读完一本书才给，见 X12）", arguments: [Activity.read, .move])
    func t7Other(activity: Activity) {
        var machine = daytimeMachine()
        machine.handle(.sessionStarted(activity, at: t(2, 14)))
        let out = machine.handle(.sessionEnded(activity, completed: true, at: t(2, 15)))
        #expect(out.transitions == [.t7])
        #expect(out.rewards.isEmpty)
    }

    @Test("T8 白天待机 --到了睡前时间--> 睡前呼噜，提示开启睡前模式")
    func t8() {
        var machine = daytimeMachine(at: t(2, 20))
        #expect(machine.handle(.tick(at: t(2, 22, 59), nextAlarmAt: t(3, 7))).isEmpty)
        let out = machine.handle(.tick(at: t(2, 23, 5), nextAlarmAt: t(3, 7)))
        #expect(out.transitions == [.t8])
        #expect(out.transitionTimes == [t(2, 23)]) // 按预定时间发生，不是 tick 的时间
        #expect(out.effects == [.promptBedtime])
        #expect(machine.state == .purringAtBedtime)
    }

    @Test("T9 睡前呼噜 --定时结束--> 夜间熟睡：停声音、记录入睡、进入幸运观察期")
    func t9() {
        var machine = daytimeMachine(at: t(2, 22))
        machine.handle(.bedtimeTimerStarted(duration: 30 * 60, at: t(2, 22, 30)))
        let out = machine.handle(.bedtimeTimerEnded(at: t(2, 23)))
        #expect(out.transitions == [.t9])
        #expect(machine.state == .sleepingAtNight)
        #expect(out.effects == [.stopBedtimeAudio, .sleepRecorded(at: t(2, 23), day: LogicalDay(year: 2026, month: 11, day: 2))])
        #expect(machine.snapshot.luckyPending)
    }

    @Test("T9 兜底：App 没收到定时结束事件，tick 时按定时器结束时间补上")
    func t9Fallback() {
        var machine = daytimeMachine(at: t(2, 22))
        machine.handle(.bedtimeTimerStarted(duration: 30 * 60, at: t(2, 22, 30)))
        let out = machine.handle(.tick(at: t(3, 1), nextAlarmAt: t(3, 7)))
        #expect(out.transitions == [.t9])
        #expect(out.transitionTimes == [t(2, 23)])
        // 之后迟到的定时结束事件被忽略
        #expect(machine.handle(.bedtimeTimerEnded(at: t(3, 1, 1))).isEmpty)
    }

    @Test("T9 → T1 → T2：睡前定时结束后没再打开 App，第二天礼物有幸运加成")
    func luckyBoost() {
        var machine = daytimeMachine(at: t(2, 22))
        machine.handle(.bedtimeTimerStarted(duration: 30 * 60, at: t(2, 22, 30)))
        machine.handle(.bedtimeTimerEnded(at: t(2, 23)))
        machine.handle(.alarmFired(alarmID: "A", at: t(3, 7)))
        #expect(machine.snapshot.wake?.luckyBoost == true)
        let out = machine.handle(.alarmStopped(alarmID: "A", via: .petCat, at: t(3, 7, 1)))
        #expect(out.rewards == [.wakeGift(luckyBoost: true)])
    }
}

@Suite("补充转换 X1–X13")
struct SupplementaryTests {
    @Test("X1 叫醒中 --超过 2 分钟才关（没贪睡）--> 白天待机：无奖励、不加乱子")
    func x1Late() {
        var machine = ringingMachine()
        let out = machine.handle(.alarmStopped(alarmID: "A", via: .petCat, at: t(2, 7, 5)))
        #expect(out.transitions == [.x1])
        #expect(machine.state == .idleDaytime)
        #expect(out.rewards.isEmpty)
        #expect(out.effects == [.wakeRecorded(onTime: false, snoozeCount: 0, day: LogicalDay(year: 2026, month: 11, day: 2))])
        #expect(machine.snapshot.messCount == 0)
    }

    @Test("X1 贪睡后稍后再响，再快速关闭也不算准时")
    func x1AfterSnooze() {
        var machine = ringingMachine()
        machine.handle(.alarmSnoozed(alarmID: "A", at: t(2, 7, 0, 30)))
        machine.handle(.alarmFired(alarmID: "A", at: t(2, 7, 1)))
        let out = machine.handle(.alarmStopped(alarmID: "A", via: .petCat, at: t(2, 7, 1, 10)))
        #expect(out.transitions == [.x1])
        #expect(out.rewards.isEmpty)
        #expect(out.effects == [.wakeRecorded(onTime: false, snoozeCount: 1, day: LogicalDay(year: 2026, month: 11, day: 2))])
        #expect(machine.snapshot.messCount == 1) // 贪睡留下的乱子还在
    }

    @Test("X2 捣乱 --贪睡倒计时中直接停掉--> 白天待机")
    func x2() {
        var machine = ringingMachine()
        machine.handle(.alarmSnoozed(alarmID: "A", at: t(2, 7, 1)))
        let out = machine.handle(.alarmStopped(alarmID: "A", via: .lockScreen, at: t(2, 7, 3)))
        #expect(out.transitions == [.x2])
        #expect(machine.state == .idleDaytime)
        #expect(out.rewards.isEmpty)
    }

    @Test("X3 叫醒中又有另一个闹钟响：合并，首次响铃时间保持最早")
    func x3WhileRinging() {
        var machine = ringingMachine()
        let out = machine.handle(.alarmFired(alarmID: "B", at: t(2, 7, 1)))
        #expect(out.transitions == [.x3])
        #expect(machine.state == .wakingUp)
        #expect(machine.snapshot.wake?.firstRingAt == t(2, 7))
        // 在首次响铃 2 分钟内关闭任意一个都算准时
        let stop = machine.handle(.alarmStopped(alarmID: "B", via: .petCat, at: t(2, 7, 1, 30)))
        #expect(stop.transitions == [.t2])
        // 另一个闹钟后面的关闭记录被忽略
        #expect(machine.handle(.alarmStopped(alarmID: "A", via: .lockScreen, at: t(2, 7, 1, 40))).isEmpty)
    }

    @Test("X3 捣乱中另一个闹钟响（不是被贪睡的那个）→ 叫醒中")
    func x3WhileSnoozed() {
        var machine = ringingMachine()
        machine.handle(.alarmSnoozed(alarmID: "A", at: t(2, 7, 1)))
        let out = machine.handle(.alarmFired(alarmID: "B", at: t(2, 7, 5)))
        #expect(out.transitions == [.x3])
        #expect(machine.state == .wakingUp)
    }

    @Test("X4 白天待机时闹钟响（今天已经叫醒过）：照样叫你，但没有奖励也不加乱子")
    func x4() {
        var machine = daytimeMachine()
        let fire = machine.handle(.alarmFired(alarmID: "nap", at: t(2, 14)))
        #expect(fire.transitions == [.x4])
        #expect(machine.snapshot.wake?.rewardEligible == false)
        let snooze = machine.handle(.alarmSnoozed(alarmID: "nap", at: t(2, 14, 1)))
        #expect(snooze.transitions == [.t4])
        #expect(snooze.effects.isEmpty) // 不加乱子
        machine.handle(.alarmFired(alarmID: "nap", at: t(2, 14, 10)))
        let stop = machine.handle(.alarmStopped(alarmID: "nap", via: .petCat, at: t(2, 14, 10, 30)))
        #expect(stop.transitions == [.x1])
        #expect(stop.rewards.isEmpty)
        #expect(stop.effects.isEmpty) // 不写 DayLog
    }

    @Test("X4 送早餐礼物时第二个闹钟响 → 叫醒中，不再发奖励")
    func x4FromGift() {
        var machine = ringingMachine()
        machine.handle(.alarmStopped(alarmID: "A", via: .petCat, at: t(2, 7, 1)))
        let out = machine.handle(.alarmFired(alarmID: "B", at: t(2, 7, 30)))
        #expect(out.transitions == [.x4])
        let stop = machine.handle(.alarmStopped(alarmID: "B", via: .petCat, at: t(2, 7, 30, 30)))
        #expect(stop.transitions == [.x1])
        #expect(stop.rewards.isEmpty)
    }

    @Test("X5 睡前呼噜（没开定时器）中开启定时器 → 开始播放")
    func x5FromPurring() {
        var machine = daytimeMachine(at: t(2, 22))
        machine.handle(.tick(at: t(2, 23), nextAlarmAt: nil)) // T8
        let out = machine.handle(.bedtimeTimerStarted(duration: 20 * 60, at: t(2, 23, 10)))
        #expect(out.transitions == [.x5])
        #expect(out.effects == [.startBedtimeAudio(endsAt: t(2, 23, 30))])
        #expect(machine.state == .purringAtBedtime)
    }

    @Test("X5 夜间熟睡时（半夜醒来）重新开启定时器 → 睡前呼噜")
    func x5FromSleeping() {
        var machine = asleepMachine()
        let out = machine.handle(.bedtimeTimerStarted(duration: 20 * 60, at: t(2, 3)))
        #expect(out.transitions == [.x5])
        #expect(machine.state == .purringAtBedtime)
        let end = machine.handle(.bedtimeTimerEnded(at: t(2, 3, 20)))
        #expect(end.transitions == [.t9])
    }

    @Test("X6 睡前时间之前手动开启睡前模式 → 睡前呼噜，当天不再触发 T8")
    func x6() {
        var machine = daytimeMachine(at: t(2, 21))
        let out = machine.handle(.bedtimeTimerStarted(duration: 30 * 60, at: t(2, 21, 30)))
        #expect(out.transitions == [.x6])
        #expect(out.effects == [.startBedtimeAudio(endsAt: t(2, 22))])
        machine.handle(.bedtimeDismissed(at: t(2, 21, 40)))
        let later = machine.handle(.tick(at: t(2, 23, 30), nextAlarmAt: t(3, 7)))
        #expect(!later.transitions.contains(.t8))
    }

    @Test("X7 睡前呼噜 --还不睡--> 白天待机，T8 当天不会再触发")
    func x7() {
        var machine = daytimeMachine(at: t(2, 22))
        machine.handle(.tick(at: t(2, 23), nextAlarmAt: t(3, 7)))
        let out = machine.handle(.bedtimeDismissed(at: t(2, 23, 1)))
        #expect(out.transitions == [.x7])
        #expect(out.effects.isEmpty) // 没开定时器就没有声音要停
        #expect(machine.state == .idleDaytime)
        #expect(machine.handle(.tick(at: t(2, 23, 30), nextAlarmAt: t(3, 7))).isEmpty)
    }

    @Test("X7 定时器在跑时选择还不睡：停掉声音")
    func x7WithTimer() {
        var machine = daytimeMachine(at: t(2, 22))
        machine.handle(.bedtimeTimerStarted(duration: 30 * 60, at: t(2, 22, 30)))
        let out = machine.handle(.bedtimeDismissed(at: t(2, 22, 40)))
        #expect(out.transitions == [.x7])
        #expect(out.effects == [.stopBedtimeAudio])
    }

    @Test("X8 睡前呼噜（没开定时器）过了入睡截止时间 → 夜间熟睡，没有幸运加成")
    func x8FromPurring() {
        var machine = daytimeMachine(at: t(2, 22))
        let out = machine.handle(.tick(at: t(3, 2, 30), nextAlarmAt: t(3, 7)))
        #expect(out.transitions == [.t8, .x8])
        #expect(out.transitionTimes == [t(2, 23), t(3, 2)])
        #expect(machine.state == .sleepingAtNight)
        #expect(!machine.snapshot.luckyPending)
    }

    @Test("X8 白天待机（选了还不睡）过了入睡截止时间 → 夜间熟睡")
    func x8FromIdle() {
        var machine = daytimeMachine(at: t(2, 22))
        machine.handle(.tick(at: t(2, 23), nextAlarmAt: t(3, 7)))
        machine.handle(.bedtimeDismissed(at: t(2, 23, 1)))
        let out = machine.handle(.tick(at: t(3, 2), nextAlarmAt: t(3, 7)))
        #expect(out.transitions == [.x8])
        #expect(machine.state == .sleepingAtNight)
    }

    @Test("X9 夜间熟睡，过了早晨且今天没有闹钟 → 白天待机")
    func x9() {
        var machine = asleepMachine()
        let out = machine.handle(.tick(at: t(2, 11), nextAlarmAt: nil))
        #expect(out.transitions == [.x9])
        #expect(out.transitionTimes == [t(2, 10)])
        #expect(machine.state == .idleDaytime)
    }

    @Test("X9 今天还有闹钟（晚于早晨时间）就继续睡，等闹钟")
    func x9WaitsForAlarm() {
        var machine = asleepMachine()
        #expect(machine.handle(.tick(at: t(2, 10, 30), nextAlarmAt: t(2, 11))).isEmpty)
        #expect(machine.state == .sleepingAtNight)
    }

    @Test("X9 下一个闹钟在明天：今天照样醒来")
    func x9AlarmTomorrow() {
        var machine = asleepMachine()
        let out = machine.handle(.tick(at: t(2, 10, 30), nextAlarmAt: t(3, 7)))
        #expect(out.transitions == [.x9])
    }

    @Test("X9 只在 tick 里判断；先收到别的事件也不会错过")
    func x9AfterOtherEvent() {
        var machine = asleepMachine()
        #expect(machine.handle(.appForegrounded(at: t(2, 12))).isEmpty)
        let out = machine.handle(.tick(at: t(2, 12), nextAlarmAt: nil))
        #expect(out.transitions == [.x9])
    }

    @Test("X10 幸运观察期内打开 App → 幸运加成作废，重开定时器也拿不回来")
    func x10() {
        var machine = daytimeMachine(at: t(2, 22))
        machine.handle(.bedtimeTimerStarted(duration: 30 * 60, at: t(2, 22, 30)))
        machine.handle(.bedtimeTimerEnded(at: t(2, 23)))
        let out = machine.handle(.appForegrounded(at: t(3, 1)))
        #expect(out.transitions == [.x10])
        #expect(machine.state == .sleepingAtNight)
        #expect(!machine.snapshot.luckyPending)
        machine.handle(.bedtimeTimerStarted(duration: 10 * 60, at: t(3, 1, 1)))
        machine.handle(.bedtimeTimerEnded(at: t(3, 1, 11)))
        machine.handle(.alarmFired(alarmID: "A", at: t(3, 7)))
        let stop = machine.handle(.alarmStopped(alarmID: "A", via: .petCat, at: t(3, 7, 1)))
        #expect(stop.rewards == [.wakeGift(luckyBoost: false)])
    }

    @Test("X10 不在观察期时打开 App 不产生转换")
    func x10OutsideWatch() {
        var machine = asleepMachine()
        #expect(machine.handle(.appForegrounded(at: t(2, 1))).isEmpty)
    }

    @Test("X11 陪你做事 --中途放弃--> 白天待机：猫去抓沙发，没有奖励")
    func x11() {
        var machine = daytimeMachine()
        machine.handle(.sessionStarted(.focus, at: t(2, 14)))
        let out = machine.handle(.sessionEnded(.focus, completed: false, at: t(2, 14, 10)))
        #expect(out.transitions == [.x11])
        #expect(out.rewards.isEmpty)
        #expect(out.effects == [
            .messAdded(.sofaScratched),
            .sessionRecorded(.focus, start: t(2, 14), end: t(2, 14, 10), completed: false),
        ])
    }

    @Test("X12 读完一本书：30 小鱼干（白天待机或读书中都可以）")
    func x12Book() {
        var idle = daytimeMachine()
        #expect(idle.handle(.bookFinished(at: t(2, 15))).rewards == [.bookFinished])
        var reading = daytimeMachine()
        reading.handle(.sessionStarted(.read, at: t(2, 15)))
        let out = reading.handle(.bookFinished(at: t(2, 15, 30)))
        #expect(out.transitions == [.x12])
        #expect(out.rewards == [.bookFinished])
        #expect(reading.state == .accompanying(.read))
    }

    @Test("X12 步数达标每个逻辑日最多一个纪念品")
    func x12Steps() {
        var machine = daytimeMachine()
        #expect(machine.handle(.stepGoalReached(at: t(2, 15))).rewards == [.stepGoalSouvenir])
        #expect(machine.handle(.stepGoalReached(at: t(2, 18))).isEmpty)
        // 第二天（逻辑日 11-03）重新计算
        var nextDay = machine
        nextDay.handle(.alarmFired(alarmID: "A", at: t(3, 9))) // 走完一遍叫醒，回到白天
        nextDay.handle(.alarmStopped(alarmID: "A", via: .petCat, at: t(3, 9, 1)))
        nextDay.handle(.giftCollected(at: t(3, 9, 2)))
        #expect(nextDay.handle(.stepGoalReached(at: t(3, 15))).rewards == [.stepGoalSouvenir])
    }

    @Test("X13 睡前呼噜时闹钟响：停呼噜声，进入叫醒中")
    func x13FromPurring() {
        var machine = daytimeMachine(at: t(2, 22))
        machine.handle(.bedtimeTimerStarted(duration: 60 * 60, at: t(2, 22, 30)))
        let out = machine.handle(.alarmFired(alarmID: "A", at: t(2, 23)))
        #expect(out.transitions == [.x13])
        #expect(out.effects == [.stopBedtimeAudio])
        #expect(machine.state == .wakingUp)
        #expect(machine.snapshot.wake?.luckyBoost == false)
    }

    @Test("X13 陪你做事时闹钟响：session 按未完成记录，但不抓沙发")
    func x13FromAccompanying() {
        var machine = daytimeMachine()
        machine.handle(.sessionStarted(.focus, at: t(2, 14)))
        let out = machine.handle(.alarmFired(alarmID: "A", at: t(2, 14, 10)))
        #expect(out.transitions == [.x13])
        #expect(out.effects == [.sessionRecorded(.focus, start: t(2, 14), end: t(2, 14, 10), completed: false)])
        #expect(machine.snapshot.messCount == 0)
        #expect(machine.state == .wakingUp)
    }
}

@Suite("覆盖率")
struct CoverageTests {
    @Test("规格里的每条转换都在测试里出现过")
    func allTransitionsCovered() {
        // 用一组场景触发全部转换，防止以后新增转换却忘了写测试。
        var seen = Set<TransitionID>()
        func record(_ outputs: [CatOutput]) { seen.formUnion(outputs.transitions) }

        // T8 → X5 → T9 → X10 → T1 → T4 → X3 → T5 → T2 → T3 → T6 → T7 → X12 → X11
        var m = daytimeMachine(at: t(2, 20))
        record(m.handle(.tick(at: t(2, 23), nextAlarmAt: t(3, 7))))
        record(m.handle(.bedtimeTimerStarted(duration: 600, at: t(2, 23, 1))))
        record(m.handle(.bedtimeTimerEnded(at: t(2, 23, 11))))
        record(m.handle(.appForegrounded(at: t(3, 1))))
        record(m.handle(.alarmFired(alarmID: "A", at: t(3, 7))))
        record(m.handle(.alarmSnoozed(alarmID: "A", at: t(3, 7, 0, 10))))
        record(m.handle(.alarmFired(alarmID: "B", at: t(3, 7, 0, 20))))
        record(m.handle(.alarmSnoozed(alarmID: "A", at: t(3, 7, 0, 30))))
        record(m.handle(.alarmFired(alarmID: "A", at: t(3, 7, 9))))
        record(m.handle(.alarmStopped(alarmID: "A", via: .petCat, at: t(3, 7, 9, 10))))

        var n = ringingMachine()
        record(n.handle(.alarmStopped(alarmID: "A", via: .petCat, at: t(2, 7, 1))))
        record(n.handle(.giftCollected(at: t(2, 7, 2))))
        record(n.handle(.sessionStarted(.focus, at: t(2, 9))))
        record(n.handle(.sessionEnded(.focus, completed: true, at: t(2, 9, 25))))
        record(n.handle(.bookFinished(at: t(2, 10))))
        record(n.handle(.sessionStarted(.focus, at: t(2, 11))))
        record(n.handle(.sessionEnded(.focus, completed: false, at: t(2, 11, 5))))
        // X4 → X2
        record(n.handle(.alarmFired(alarmID: "nap", at: t(2, 14))))
        record(n.handle(.alarmSnoozed(alarmID: "nap", at: t(2, 14, 1))))
        record(n.handle(.alarmStopped(alarmID: "nap", via: .petCat, at: t(2, 14, 2))))
        // X6 → X7 → X8 → X9
        record(n.handle(.bedtimeTimerStarted(duration: 600, at: t(2, 21))))
        record(n.handle(.bedtimeDismissed(at: t(2, 21, 5))))
        record(n.handle(.tick(at: t(3, 2), nextAlarmAt: nil)))
        record(n.handle(.tick(at: t(3, 10), nextAlarmAt: nil)))
        // X13
        record(n.handle(.sessionStarted(.read, at: t(3, 11))))
        record(n.handle(.alarmFired(alarmID: "C", at: t(3, 11, 30))))

        let missing = Set(TransitionID.allCases).subtracting(seen)
        #expect(missing.isEmpty, "没有被触发的转换：\(missing.map(\.rawValue).sorted())")
    }
}
