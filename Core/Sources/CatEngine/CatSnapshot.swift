import Foundation

/// 一次叫醒（从闹钟第一次响到关闭）的上下文。
public struct WakeContext: Hashable, Codable, Sendable {
    /// 本次叫醒第一次响铃的时间，准时判定从这里算
    public var firstRingAt: Date
    /// 最后一次闹钟活动（响 / 贪睡）的时间，用来判断记录是否丢失
    public var lastActivityAt: Date
    /// 本次叫醒按了几次贪睡（真实次数，不受乱子上限影响）
    public var snoozeCount: Int
    /// 是否是本逻辑日第一次叫醒（只有这次能拿奖励、记录 DayLog）
    public var rewardEligible: Bool
    /// 准时的话礼物是否有睡前幸运加成
    public var luckyBoost: Bool
    /// 最近一次贪睡的闹钟，用来区分 T5（稍后再响）和 X3（另一个闹钟响）
    public var snoozedAlarmID: String?
}

/// 正在进行的"陪你做事"。
public struct SessionContext: Hashable, Codable, Sendable {
    public var activity: Activity
    public var startedAt: Date
}

/// 引擎的完整状态，可以直接持久化（Codable）。
public struct CatSnapshot: Hashable, Codable, Sendable {
    public internal(set) var state: CatState
    /// 进入当前状态的时间
    public internal(set) var stateEnteredAt: Date
    /// 引擎已经处理到的时间
    public internal(set) var updatedAt: Date
    /// 房间里现在有几个乱子
    public internal(set) var messCount: Int = 0
    public internal(set) var wake: WakeContext?
    public internal(set) var giftShownAt: Date?
    public internal(set) var bedtimeTimerEndsAt: Date?
    public internal(set) var session: SessionContext?
    /// 处在幸运观察期（T9 之后、下一次叫醒之前）
    public internal(set) var luckyPending = false
    /// 今晚已经因为打开 App 失去了幸运加成（重开定时器也拿不回来）
    public internal(set) var luckyForfeited = false
    public internal(set) var lastWakeDay: LogicalDay?
    public internal(set) var lastBedtimeDay: LogicalDay?
    public internal(set) var lastStepGoalDay: LogicalDay?

    public init(state: CatState = .idleDaytime, at date: Date) {
        self.state = state
        self.stateEnteredAt = date
        self.updatedAt = date
    }

    /// 捣乱状态下该播哪个动画。
    public var mischief: MischiefKind? {
        guard state == .makingMischief, let wake else { return nil }
        return .forSnooze(wake.snoozeCount)
    }
}
