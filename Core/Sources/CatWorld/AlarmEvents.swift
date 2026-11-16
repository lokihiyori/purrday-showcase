import CatEngine
import Foundation

/// 系统闹钟（AlarmKit）发生的事。
public enum AlarmAction: Sendable {
    /// 闹钟正在响（App 通过 alarmUpdates 看到）
    case alerting
    /// 锁屏 / 灵动岛上点了停止
    case stopped
    /// 锁屏 / 灵动岛上点了贪睡
    case snoozed
}

extension CatWorld {
    /// 推算首次响铃时间时，最多往前推这么久；更久的当作数据有问题，用当前时间
    static let maxRingInference: TimeInterval = 2 * 3600

    /// 系统闹钟事件 → 要写进日志的事件。
    ///
    /// 锁屏上的停止 / 贪睡按钮在 App 没打开时运行，只知道"现在"。这里按闹钟排程推算这次叫醒是几点开始的，
    /// 先补一条 `alarmFired`，再记操作本身，这样"2 分钟内关闭才算准时"按真实响铃时间判断。
    /// `alarmFired` 的 id 由闹钟 id 和推算出的响铃时间决定，App 内和锁屏两条路径记的是同一条，`ingest` 会去重。
    public func alarmEvents(_ action: AlarmAction, alarmID: String, at now: Date) -> [LoggedEvent] {
        var firedAt = now
        if let config = state.alarms.first(where: { $0.id == alarmID }),
           let previous = AlarmSchedule.previousFire(of: config, atOrBefore: now, calendar: catConfig.calendar),
           now.timeIntervalSince(previous) <= Self.maxRingInference {
            firedAt = previous
        }
        let stamp = { (date: Date) in Int(date.timeIntervalSince1970) }
        var events = [LoggedEvent(id: "alarm-fired-\(alarmID)-\(stamp(firedAt))", event: .alarmFired(alarmID: alarmID, at: firedAt))]
        switch action {
        case .alerting:
            // 贪睡倒计时结束后再次响铃（T5）
            if state.cat.state == .makingMischief, firedAt < now {
                events.append(LoggedEvent(id: "alarm-refired-\(alarmID)-\(stamp(now) / 60)", event: .alarmFired(alarmID: alarmID, at: now)))
            }
        case .stopped:
            events.append(LoggedEvent(id: "alarm-stopped-\(alarmID)-\(stamp(now))", event: .alarmStopped(alarmID: alarmID, via: .lockScreen, at: now)))
        case .snoozed:
            events.append(LoggedEvent(id: "alarm-snoozed-\(alarmID)-\(stamp(now))", event: .alarmSnoozed(alarmID: alarmID, at: now)))
        }
        return events
    }
}
