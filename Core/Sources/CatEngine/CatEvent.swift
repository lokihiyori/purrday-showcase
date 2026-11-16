import Foundation

/// 关闹钟的方式。
public enum AlarmStopMethod: String, Codable, Sendable {
    /// 在 App 里摸猫 / 喂猫关闹钟
    case petCat
    /// 锁屏上的停止按钮（App Intent）
    case lockScreen
    /// 没有关闭记录，由引擎推断（见规格 4.3）
    case unknown
}

/// 引擎的输入事件。每个事件都带时间戳，引擎不读系统时钟。
/// 事件可以持久化成日志（Codable），App 重启后按时间顺序回放。
public enum CatEvent: Hashable, Codable, Sendable {
    case alarmFired(alarmID: String, at: Date)
    case alarmSnoozed(alarmID: String, at: Date)
    case alarmStopped(alarmID: String, via: AlarmStopMethod, at: Date)
    case giftCollected(at: Date)
    case dismissed(at: Date)
    case messCleared(at: Date)
    case sessionStarted(Activity, at: Date)
    case sessionEnded(Activity, completed: Bool, at: Date)
    case bookFinished(at: Date)
    case stepGoalReached(at: Date)
    case bedtimeTimerStarted(duration: TimeInterval, at: Date)
    case bedtimeTimerEnded(at: Date)
    case bedtimeDismissed(at: Date)
    case appForegrounded(at: Date)
    /// App 启动 / 回到前台 / 后台刷新时调用。`nextAlarmAt` 是下一个会响的闹钟（没有则为 nil），
    /// X9（早晨且今天没有闹钟）只在 tick 里判断，因为只有 tick 带着闹钟排程信息。
    case tick(at: Date, nextAlarmAt: Date?)

    /// 事件发生的时间。
    public var at: Date {
        switch self {
        case let .alarmFired(_, at), let .alarmSnoozed(_, at), let .alarmStopped(_, _, at),
             let .giftCollected(at), let .dismissed(at), let .messCleared(at),
             let .sessionStarted(_, at), let .sessionEnded(_, _, at),
             let .bookFinished(at), let .stepGoalReached(at),
             let .bedtimeTimerStarted(_, at), let .bedtimeTimerEnded(at), let .bedtimeDismissed(at),
             let .appForegrounded(at), let .tick(at, _):
            at
        }
    }
}
