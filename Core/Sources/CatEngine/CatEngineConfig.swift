import Foundation

/// 一天中的时刻（当地时间）。
public struct TimeOfDay: Hashable, Codable, Sendable, Comparable {
    public var hour: Int
    public var minute: Int

    public init(_ hour: Int, _ minute: Int = 0) {
        precondition((0..<24).contains(hour) && (0..<60).contains(minute), "invalid time of day")
        self.hour = hour
        self.minute = minute
    }

    var minutesSinceMidnight: Int { hour * 60 + minute }

    public static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        lhs.minutesSinceMidnight < rhs.minutesSinceMidnight
    }
}

/// "猫的一天"（逻辑日）。从 `CatEngineConfig.dayStart`（默认 04:00）开始，而不是 00:00。
/// 对应 `DayLog.date`。
public struct LogicalDay: Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public static func < (lhs: LogicalDay, rhs: LogicalDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }
}

/// 引擎参数。带 🟡 的默认值在规格第 5 节等待产品确认。
public struct CatEngineConfig: Sendable {
    /// 日历和时区。测试里注入固定时区。
    public var calendar: Calendar
    /// 逻辑日的开始时刻 🟡
    public var dayStart = TimeOfDay(4)
    /// 睡前时间（T8）🟡
    public var bedtime = TimeOfDay(23)
    /// 入睡截止时间（X8），必须早于 `dayStart` 🟡
    public var sleepCutoff = TimeOfDay(2)
    /// 早晨时间（X9），必须不早于 `dayStart` 🟡
    public var morning = TimeOfDay(10)
    /// 准时窗口（T2）：首次响铃后多久内关闭算准时
    public var onTimeWindow: TimeInterval = 2 * 60
    /// 房间里同时最多几个乱子
    public var maxMessCount = 3
    /// 送早餐礼物在没人看时最多挂多久，之后自动进入白天待机 🟡
    public var giftDisplayTimeout: TimeInterval = 30 * 60
    /// 叫醒中 / 捣乱距最后一次闹钟活动多久没有关闭记录，就按 `.unknown` 关闭处理（规格 4.3）
    public var staleWakeTimeout: TimeInterval = 30 * 60

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    /// `date` 所属的逻辑日。
    public func logicalDay(of date: Date) -> LogicalDay {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let minutes = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        if minutes >= dayStart.minutesSinceMidnight {
            return LogicalDay(year: c.year ?? 0, month: c.month ?? 0, day: c.day ?? 0)
        }
        let previous = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: date)) ?? date
        let p = calendar.dateComponents([.year, .month, .day], from: previous)
        return LogicalDay(year: p.year ?? 0, month: p.month ?? 0, day: p.day ?? 0)
    }

    /// 逻辑日 `day` 里的时刻 `time` 对应的绝对时间。
    /// 早于 `dayStart` 的时刻属于下一个日历日（例如逻辑日 11-01 的 00:30 是 11-02 00:30）。
    /// 夏令时切换当天不存在的时刻会顺延到切换之后，重复的时刻取第一次。
    public func date(_ time: TimeOfDay, in day: LogicalDay) -> Date {
        let calendarDay = time < dayStart ? self.day(after: day) : day
        let components = DateComponents(
            year: calendarDay.year, month: calendarDay.month, day: calendarDay.day,
            hour: time.hour, minute: time.minute
        )
        return calendar.date(from: components) ?? .distantPast
    }

    /// 下一个逻辑日。
    public func day(after day: LogicalDay) -> LogicalDay {
        let noon = calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12)) ?? Date(timeIntervalSince1970: 0)
        let next = calendar.date(byAdding: .day, value: 1, to: noon) ?? noon
        let c = calendar.dateComponents([.year, .month, .day], from: next)
        return LogicalDay(year: c.year ?? 0, month: c.month ?? 0, day: c.day ?? 0)
    }
}
