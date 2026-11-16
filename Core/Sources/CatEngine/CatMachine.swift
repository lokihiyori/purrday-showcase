import Foundation

/// 猫的行为状态机。纯值类型，没有 I/O：输入事件，输出转换、奖励和副作用。
///
/// 每个事件处理前，引擎会先把"和时间相关的转换"（T8、X8、T9 兜底、X9、超时）
/// 按它们各自发生的时间补跑到事件时间为止，所以 App 很久没打开、按时间顺序回放事件日志，
/// 得到的结果和实时处理一样。规格见 docs/cat-state-machine.md。
public struct CatMachine: Sendable {
    public let config: CatEngineConfig
    public private(set) var snapshot: CatSnapshot

    public init(config: CatEngineConfig, snapshot: CatSnapshot) {
        self.config = config
        self.snapshot = snapshot
    }

    public var state: CatState { snapshot.state }

    /// 处理一个事件。
    @discardableResult
    public mutating func handle(_ event: CatEvent) -> [CatOutput] {
        var out: [CatOutput] = []
        if case let .tick(at, nextAlarmAt) = event {
            advance(to: at, alarms: .known(nextAlarmAt), &out)
            return out
        }
        advance(to: event.at, alarms: .unknown, &out)
        apply(event, &out)
        snapshot.updatedAt = max(snapshot.updatedAt, event.at)
        return out
    }

    /// 按时间顺序回放一批事件（时间相同的保持原顺序）。
    @discardableResult
    public mutating func replay(_ events: [CatEvent]) -> [CatOutput] {
        let ordered = events.enumerated()
            .sorted { ($0.element.at, $0.offset) < ($1.element.at, $1.offset) }
            .map(\.element)
        return ordered.flatMap { handle($0) }
    }
}

// MARK: - 和时间相关的转换

extension CatMachine {
    enum AlarmInfo {
        /// 不知道闹钟排程（非 tick 事件），不判断 X9
        case unknown
        case known(Date?)
    }

    enum TimedTransition {
        case bedtimeArrived       // T8
        case sleepCutoff          // X8
        case bedtimeTimerEnded    // T9（App 没收到定时结束事件时的兜底）
        case morningWithoutAlarm  // X9
        case staleWake            // X1 / X2，via .unknown
        case giftTimeout          // T3
    }

    private mutating func advance(to target: Date, alarms: AlarmInfo, _ out: inout [CatOutput]) {
        // 正常一天最多十来次时间转换；上限只是防止配置错误导致死循环。
        for _ in 0..<64 {
            guard let (time, transition) = nextTimedTransition(alarms: alarms), time <= target else { break }
            fire(transition, scheduledAt: time, &out)
        }
        snapshot.updatedAt = max(snapshot.updatedAt, target)
    }

    private func nextTimedTransition(alarms: AlarmInfo) -> (Date, TimedTransition)? {
        let entered = snapshot.stateEnteredAt
        let day = config.logicalDay(of: entered)
        switch snapshot.state {
        case .idleDaytime:
            let bedtimeDay = snapshot.lastBedtimeDay == day ? config.day(after: day) : day
            let bedtime = config.date(config.bedtime, in: bedtimeDay)
            let cutoff = config.date(config.sleepCutoff, in: day)
            return bedtime <= cutoff ? (bedtime, .bedtimeArrived) : (cutoff, .sleepCutoff)
        case .purringAtBedtime:
            if let end = snapshot.bedtimeTimerEndsAt {
                return (end, .bedtimeTimerEnded)
            }
            return (config.date(config.sleepCutoff, in: day), .sleepCutoff)
        case .sleepingAtNight:
            guard case let .known(nextAlarm) = alarms else { return nil }
            var morning = config.date(config.morning, in: day)
            if morning <= entered {
                morning = config.date(config.morning, in: config.day(after: day))
            }
            if let nextAlarm, config.logicalDay(of: nextAlarm) == config.logicalDay(of: morning) {
                return nil // 今天还有闹钟会响，等闹钟
            }
            return (morning, .morningWithoutAlarm)
        case .wakingUp, .makingMischief:
            guard let wake = snapshot.wake else { return nil }
            return (wake.lastActivityAt.addingTimeInterval(config.staleWakeTimeout), .staleWake)
        case .givingGift:
            guard let shown = snapshot.giftShownAt else { return nil }
            return (shown.addingTimeInterval(config.giftDisplayTimeout), .giftTimeout)
        case .accompanying:
            return nil
        }
    }

    private mutating func fire(_ transition: TimedTransition, scheduledAt time: Date, _ out: inout [CatOutput]) {
        // 预定时间早于引擎当前时间时（比如刚安装就已经过了睡前时间），在当前时间立即发生。
        let at = max(time, snapshot.updatedAt)
        switch transition {
        case .bedtimeArrived:
            snapshot.lastBedtimeDay = config.logicalDay(of: time)
            move(to: .purringAtBedtime, .t8, at: at, &out)
            out.append(.effect(.promptBedtime))
        case .sleepCutoff:
            snapshot.luckyPending = false
            move(to: .sleepingAtNight, .x8, at: at, &out)
        case .bedtimeTimerEnded:
            endBedtime(at: at, &out)
        case .morningWithoutAlarm:
            snapshot.luckyPending = false
            snapshot.luckyForfeited = false
            move(to: .idleDaytime, .x9, at: at, &out)
        case .staleWake:
            resolveWake(at: at, &out)
        case .giftTimeout:
            snapshot.giftShownAt = nil
            move(to: .idleDaytime, .t3, at: at, &out)
        }
        snapshot.updatedAt = max(snapshot.updatedAt, at)
    }
}

// MARK: - 事件

extension CatMachine {
    private mutating func apply(_ event: CatEvent, _ out: inout [CatOutput]) {
        let state = snapshot.state
        switch event {
        case let .alarmFired(alarmID, at):
            alarmFired(alarmID, at: at, &out)

        case let .alarmSnoozed(alarmID, at):
            guard state == .wakingUp, var wake = snapshot.wake else { return }
            wake.snoozeCount += 1
            wake.lastActivityAt = at
            wake.snoozedAlarmID = alarmID
            snapshot.wake = wake
            move(to: .makingMischief, .t4, at: at, &out)
            if wake.rewardEligible {
                addMess(.snooze(.forSnooze(wake.snoozeCount)), &out)
            }

        case let .alarmStopped(_, _, at):
            guard state == .wakingUp || state == .makingMischief else { return }
            resolveWake(at: at, &out)

        case let .giftCollected(at), let .dismissed(at):
            guard state == .givingGift else { return }
            snapshot.giftShownAt = nil
            move(to: .idleDaytime, .t3, at: at, &out)

        case .messCleared:
            snapshot.messCount = max(0, snapshot.messCount - 1)

        case let .sessionStarted(activity, at):
            guard state == .idleDaytime else { return }
            snapshot.session = SessionContext(activity: activity, startedAt: at)
            move(to: .accompanying(activity), .t6, at: at, &out)

        case let .sessionEnded(activity, completed, at):
            guard state == .accompanying(activity), let session = snapshot.session else { return }
            snapshot.session = nil
            if completed {
                move(to: .idleDaytime, .t7, at: at, &out)
                if activity == .focus {
                    out.append(.reward(.focusCompleted))
                }
            } else {
                move(to: .idleDaytime, .x11, at: at, &out)
                addMess(.sofaScratched, &out)
            }
            out.append(.effect(.sessionRecorded(activity, start: session.startedAt, end: at, completed: completed)))

        case let .bookFinished(at):
            guard isDaytime(state) else { return }
            move(to: state, .x12, at: at, &out)
            out.append(.reward(.bookFinished))

        case let .stepGoalReached(at):
            let day = config.logicalDay(of: at)
            guard isDaytime(state), snapshot.lastStepGoalDay != day else { return }
            snapshot.lastStepGoalDay = day
            move(to: state, .x12, at: at, &out)
            out.append(.reward(.stepGoalSouvenir))

        case let .bedtimeTimerStarted(duration, at):
            let id: TransitionID
            switch state {
            case .idleDaytime:
                id = .x6
                snapshot.lastBedtimeDay = config.logicalDay(of: at)
            case .purringAtBedtime, .sleepingAtNight:
                id = .x5
            default:
                return
            }
            let endsAt = at.addingTimeInterval(duration)
            snapshot.bedtimeTimerEndsAt = endsAt
            move(to: .purringAtBedtime, id, at: at, &out)
            out.append(.effect(.startBedtimeAudio(endsAt: endsAt)))

        case let .bedtimeTimerEnded(at):
            guard state == .purringAtBedtime else { return }
            endBedtime(at: at, &out)

        case let .bedtimeDismissed(at):
            guard state == .purringAtBedtime else { return }
            stopBedtimeAudioIfNeeded(&out)
            move(to: .idleDaytime, .x7, at: at, &out)

        case let .appForegrounded(at):
            guard state == .sleepingAtNight, snapshot.luckyPending else { return }
            snapshot.luckyPending = false
            snapshot.luckyForfeited = true
            move(to: state, .x10, at: at, &out)

        case .tick:
            break // 在 handle 里处理
        }
    }

    private mutating func alarmFired(_ alarmID: String, at: Date, _ out: inout [CatOutput]) {
        switch snapshot.state {
        case .sleepingAtNight:
            startWake(.t1, at: at, allowLucky: true, &out)
        case .wakingUp:
            snapshot.wake?.lastActivityAt = at
            move(to: .wakingUp, .x3, at: at, &out)
        case .makingMischief:
            let id: TransitionID = snapshot.wake?.snoozedAlarmID == alarmID ? .t5 : .x3
            snapshot.wake?.lastActivityAt = at
            move(to: .wakingUp, id, at: at, &out)
        case .idleDaytime, .givingGift:
            snapshot.giftShownAt = nil
            startWake(.x4, at: at, allowLucky: false, &out)
        case .purringAtBedtime:
            stopBedtimeAudioIfNeeded(&out)
            startWake(.x13, at: at, allowLucky: false, &out)
        case let .accompanying(activity):
            if let session = snapshot.session {
                out.append(.effect(.sessionRecorded(activity, start: session.startedAt, end: at, completed: false)))
            }
            snapshot.session = nil
            startWake(.x13, at: at, allowLucky: false, &out)
        }
    }

    /// 开始一次叫醒。只有本逻辑日第一次叫醒能拿奖励（规格 4.4）。
    private mutating func startWake(_ id: TransitionID, at: Date, allowLucky: Bool, _ out: inout [CatOutput]) {
        let day = config.logicalDay(of: at)
        let eligible = snapshot.lastWakeDay != day
        if eligible {
            snapshot.lastWakeDay = day
        }
        snapshot.wake = WakeContext(
            firstRingAt: at,
            lastActivityAt: at,
            snoozeCount: 0,
            rewardEligible: eligible,
            luckyBoost: allowLucky && eligible && snapshot.luckyPending,
            snoozedAlarmID: nil
        )
        snapshot.luckyPending = false
        move(to: .wakingUp, id, at: at, &out)
    }

    /// 关闭闹钟：T2（准时）、X1（叫醒中非准时）、X2（捣乱中关闭）。
    private mutating func resolveWake(at: Date, _ out: inout [CatOutput]) {
        guard let wake = snapshot.wake else { return }
        let from = snapshot.state
        snapshot.wake = nil
        snapshot.luckyPending = false
        snapshot.luckyForfeited = false

        let onTime = from == .wakingUp
            && wake.rewardEligible
            && wake.snoozeCount == 0
            && at.timeIntervalSince(wake.firstRingAt) <= config.onTimeWindow
        let day = config.logicalDay(of: wake.firstRingAt)

        if onTime {
            snapshot.giftShownAt = at
            move(to: .givingGift, .t2, at: at, &out)
            out.append(.reward(.wakeGift(luckyBoost: wake.luckyBoost)))
            out.append(.effect(.wakeRecorded(onTime: true, snoozeCount: 0, day: day)))
        } else {
            move(to: .idleDaytime, from == .wakingUp ? .x1 : .x2, at: at, &out)
            if wake.rewardEligible {
                out.append(.effect(.wakeRecorded(onTime: false, snoozeCount: wake.snoozeCount, day: day)))
            }
        }
    }

    /// T9：睡前定时结束，进入夜间熟睡和幸运观察期。
    private mutating func endBedtime(at: Date, _ out: inout [CatOutput]) {
        stopBedtimeAudioIfNeeded(&out)
        snapshot.luckyPending = !snapshot.luckyForfeited
        move(to: .sleepingAtNight, .t9, at: at, &out)
        out.append(.effect(.sleepRecorded(at: at, day: config.logicalDay(of: at))))
    }

    private mutating func stopBedtimeAudioIfNeeded(_ out: inout [CatOutput]) {
        if snapshot.bedtimeTimerEndsAt != nil {
            snapshot.bedtimeTimerEndsAt = nil
            out.append(.effect(.stopBedtimeAudio))
        }
    }

    private mutating func addMess(_ kind: MessKind, _ out: inout [CatOutput]) {
        guard snapshot.messCount < config.maxMessCount else { return }
        snapshot.messCount += 1
        out.append(.effect(.messAdded(kind)))
    }

    private func isDaytime(_ state: CatState) -> Bool {
        if case .accompanying = state { return true }
        return state == .idleDaytime
    }

    private mutating func move(to newState: CatState, _ id: TransitionID, at: Date, _ out: inout [CatOutput]) {
        out.append(.transition(id, from: snapshot.state, to: newState, at: at))
        if newState != snapshot.state {
            snapshot.state = newState
            snapshot.stateEnteredAt = at
        }
    }
}
