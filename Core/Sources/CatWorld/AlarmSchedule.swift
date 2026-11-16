import CatEngine
import Foundation

/// 星期，raw value 与 `Calendar.component(.weekday)` 一致（1 = 周日）。
public enum Weekday: Int, Codable, Sendable, CaseIterable, Comparable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    public static let weekdays: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]
    public static let everyday = Set(Weekday.allCases)

    public static func < (lhs: Weekday, rhs: Weekday) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// 一个闹钟的设置（对应 SwiftData 的 `AlarmConfig`，只保留和逻辑有关的字段）。
/// 声音、关闹钟方式、AlarmKit 的 id 由 App 层保存。
public struct AlarmConfig: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var time: TimeOfDay
    /// 空集合表示只响一次
    public var repeatDays: Set<Weekday>
    public var isEnabled: Bool
    /// 设置（或重新打开）闹钟的时间。一次性闹钟在这之后的第一个 `time` 响
    public var armedAt: Date

    public init(id: String, time: TimeOfDay, repeatDays: Set<Weekday> = [], isEnabled: Bool = true, armedAt: Date) {
        self.id = id
        self.time = time
        self.repeatDays = repeatDays
        self.isEnabled = isEnabled
        self.armedAt = armedAt
    }

    public var isOneShot: Bool { repeatDays.isEmpty }
}

/// 计算闹钟下一次响的时间。AlarmKit 负责真正的排程，这里只是给 CatEngine 的 `tick(nextAlarmAt:)`
/// 和锁屏小组件"下一个闹钟"用。
public enum AlarmSchedule {
    /// `alarm` 在 `date` 之后（不含）下一次响铃的时间；不会再响则为 nil。
    public static func nextFire(of alarm: AlarmConfig, after date: Date, calendar: Calendar) -> Date? {
        guard alarm.isEnabled else { return nil }
        if alarm.isOneShot {
            guard let first = firstOccurrence(of: alarm.time, after: alarm.armedAt, calendar: calendar, matching: nil) else {
                return nil
            }
            return first > date ? first : nil
        }
        return firstOccurrence(of: alarm.time, after: date, calendar: calendar, matching: alarm.repeatDays)
    }

    /// `alarm` 在 `date` 及之前最近一次响铃的时间（不看开关：一次性闹钟响过之后会被关掉）。
    /// 锁屏上停止 / 贪睡时，用它推算这次叫醒是几点开始的。
    public static func previousFire(of alarm: AlarmConfig, atOrBefore date: Date, calendar: Calendar) -> Date? {
        if alarm.isOneShot {
            guard let first = firstOccurrence(of: alarm.time, after: alarm.armedAt, calendar: calendar, matching: nil) else {
                return nil
            }
            return first <= date ? first : nil
        }
        let start = calendar.startOfDay(for: date)
        for offset in 0...8 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: start) else { continue }
            let c = calendar.dateComponents([.year, .month, .day], from: day)
            guard let candidate = calendar.date(from: DateComponents(year: c.year, month: c.month, day: c.day, hour: alarm.time.hour, minute: alarm.time.minute)),
                  candidate <= date,
                  let weekday = Weekday(rawValue: calendar.component(.weekday, from: candidate)),
                  alarm.repeatDays.contains(weekday)
            else { continue }
            return candidate
        }
        return nil
    }

    /// 一组闹钟里最早的下一次响铃。
    public static func nextFire(of alarms: [AlarmConfig], after date: Date, calendar: Calendar) -> Date? {
        alarms.compactMap { nextFire(of: $0, after: date, calendar: calendar) }.min()
    }

    private static func firstOccurrence(of time: TimeOfDay, after date: Date, calendar: Calendar, matching days: Set<Weekday>?) -> Date? {
        let start = calendar.startOfDay(for: date)
        for offset in 0...8 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            let c = calendar.dateComponents([.year, .month, .day], from: day)
            // 夏令时切换当天不存在的时刻会顺延
            guard let candidate = calendar.date(from: DateComponents(year: c.year, month: c.month, day: c.day, hour: time.hour, minute: time.minute)),
                  candidate > date
            else { continue }
            if let days, let weekday = Weekday(rawValue: calendar.component(.weekday, from: candidate)), !days.contains(weekday) {
                continue
            }
            return candidate
        }
        return nil
    }
}

/// 免费用户 1 个闹钟，Plus 不限（计划书第 4.1 节）。
public enum AlarmPolicy {
    public static let freeEnabledLimit = 1

    public static func limit(isPlus: Bool) -> Int? {
        isPlus ? nil : freeEnabledLimit
    }
}
