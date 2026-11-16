import CatEngine
import Foundation

// 起床日历（docs/cat-on-chair.md 第 7 条）：每天一个爪印——准时、赖床、没有闹钟——加上连续准时的天数。
// 数据就是每日记录（`DayLog`），这里只是整理成一个月的格子。

/// 一天早上的结果。
public enum MorningMark: Hashable, Sendable {
    /// 准时起床
    case onTime
    /// 赖床了（贪睡了几次）
    case late(snoozes: Int)
    /// 这天没有闹钟（或者还没到）
    case none
}

/// 日历上的一格。
public struct CalendarDay: Hashable, Sendable, Identifiable {
    public var day: LogicalDay
    public var mark: MorningMark
    /// 这天晚上用了睡前模式
    public var bedtime: Bool
    public var isToday: Bool
    public var isFuture: Bool

    public var id: LogicalDay { day }
}

extension CatWorld {
    public func morningMark(_ day: LogicalDay) -> MorningMark {
        guard let log = state.dayLogs[day], let onTime = log.wokeOnTime else { return .none }
        return onTime ? .onTime : .late(snoozes: log.snoozeCount)
    }

    /// 某个月的格子：前面按星期几补空（nil），一行七天。`today` 用来标出今天和还没到的日子。
    public func calendarMonth(year: Int, month: Int, today: Date) -> [CalendarDay?] {
        let calendar = catConfig.calendar
        guard let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let count = calendar.range(of: .day, in: .month, for: first)?.count else { return [] }
        let now = catConfig.logicalDay(of: today)
        let leading = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        var cells: [CalendarDay?] = Array(repeating: nil, count: leading)
        for d in 1...count {
            let day = LogicalDay(year: year, month: month, day: d)
            cells.append(CalendarDay(day: day, mark: morningMark(day), bedtime: state.dayLogs[day]?.sleptAt != nil,
                                     isToday: day == now, isFuture: day > now))
        }
        return cells
    }

    /// 连续准时起床的天数（到今天为止）。没有闹钟的日子不算断（周末不设闹钟不会清零）；赖床才断。
    public func wakeStreak(asOf date: Date) -> Int {
        Self.streak(endingAt: catConfig.logicalDay(of: date), marks: marks())
    }

    /// 历史上最长的连续准时天数
    public var bestWakeStreak: Int {
        var best = 0, run = 0
        for (_, mark) in marks().sorted(by: { $0.key < $1.key }) {
            switch mark {
            case .onTime: run += 1; best = max(best, run)
            case .late: run = 0
            case .none: break
            }
        }
        return best
    }

    /// 一共准时起床了多少天
    public var onTimeMornings: Int {
        state.dayLogs.values.filter { $0.wokeOnTime == true }.count
    }

    private func marks() -> [LogicalDay: MorningMark] {
        state.dayLogs.mapValues { log in
            log.wokeOnTime.map { $0 ? MorningMark.onTime : .late(snoozes: log.snoozeCount) } ?? MorningMark.none
        }
    }

    static func streak(endingAt today: LogicalDay, marks: [LogicalDay: MorningMark]) -> Int {
        var count = 0
        for (_, mark) in marks.filter({ $0.key <= today }).sorted(by: { $0.key > $1.key }) {
            switch mark {
            case .onTime: count += 1
            case .late: return count
            case .none: continue
            }
        }
        return count
    }
}

#if DEBUG
extension CatWorld {
    /// 只在 Debug 版本里有：把过去三周填上示例记录（`-debugMornings 1`，看日历的样子）。
    public mutating func debugFillMornings(until date: Date) {
        let calendar = catConfig.calendar
        for back in 1...21 {
            guard let past = calendar.date(byAdding: .day, value: -back, to: date) else { continue }
            let day = catConfig.logicalDay(of: past)
            var log = state.dayLogs[day] ?? DayLog(day: day)
            let weekday = calendar.component(.weekday, from: past)
            if weekday == 1 || weekday == 7 { state.dayLogs[day] = log; continue } // 周末没闹钟
            log.wokeOnTime = back % 6 != 0
            log.snoozeCount = back % 6 == 0 ? 2 : 0
            if back % 3 == 0 { log.sleptAt = past }
            state.dayLogs[day] = log
        }
    }
}
#endif
