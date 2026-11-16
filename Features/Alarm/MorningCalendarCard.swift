import CatEngine
import CatWorld
import SwiftUI

/// 起床日历：这个月每天早上一个爪印（准时是焦糖色的爪印，赖床是灰色的 zzz，没有闹钟是一个小点），
/// 上面写着连续准时了几天。可以翻到之前的月份。数据来自 `CatWorld.calendarMonth`。
struct MorningCalendarCard: View {
    @Environment(WorldStore.self) private var store
    /// 往前翻了几个月（0 是这个月）
    @State private var monthsBack = 0

    var body: some View {
        let now = RoomClock.now()
        let calendar = store.world.catConfig.calendar
        let shown = calendar.date(byAdding: .month, value: -monthsBack, to: now) ?? now
        let parts = calendar.dateComponents([.year, .month], from: shown)
        let cells = store.world.calendarMonth(year: parts.year ?? 2026, month: parts.month ?? 1, today: now)
        let streak = store.world.wakeStreak(asOf: now)
        VStack(spacing: 12) {
            header(streak: streak)
            HStack {
                Button { monthsBack += 1 } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel(Text("calendar.previous"))
                    .accessibilityIdentifier("calendar.previous")
                Spacer()
                Text(shown, format: .dateTime.year().month(.wide))
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button { monthsBack = max(0, monthsBack - 1) } label: { Image(systemName: "chevron.right") }
                    .disabled(monthsBack == 0)
                    .opacity(monthsBack == 0 ? 0.25 : 1)
                    .accessibilityLabel(Text("calendar.next"))
            }
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(Theme.caramelDeep)
            .buttonStyle(.borderless)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
                ForEach(Array(Self.weekdaySymbols(calendar).enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.inkSoft)
                }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                    if let cell { dayCell(cell) } else { Color.clear.frame(height: 40) }
                }
            }
            legend
        }
        .gameCard(padding: 14)
        .animation(.snappy, value: monthsBack)
        .accessibilityIdentifier("calendar.card")
    }

    private func header(streak: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "pawprint.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(streak > 0 ? Theme.caramel : Theme.inkSoft.opacity(0.5), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("calendar.title")
                    .handwritten(20, relativeTo: .headline)
                    .foregroundStyle(Theme.ink)
                Text(streak > 0 ? localized("calendar.streak", streak) : String(localized: "calendar.streak.none"))
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(streak > 0 ? Theme.caramelDeep : Theme.inkSoft)
            }
            Spacer(minLength: 0)
            let best = store.world.bestWakeStreak
            if best > streak, best > 1 {
                Text(localized("calendar.best", best))
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.inkSoft)
            }
        }
    }

    private func dayCell(_ cell: CalendarDay) -> some View {
        VStack(spacing: 1) {
            ZStack {
                switch cell.mark {
                case .onTime:
                    Circle().fill(Theme.caramel.opacity(0.18))
                    Image(systemName: "pawprint.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.caramel)
                case .late:
                    Circle().fill(Theme.line)
                    Image(systemName: "zzz").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.inkSoft)
                case .none:
                    Circle().fill(Theme.inkSoft.opacity(cell.isFuture ? 0.12 : 0.3)).frame(width: 4, height: 4)
                }
                if cell.bedtime {
                    Image(systemName: "moon.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(Color(red: 0.55, green: 0.5, blue: 0.78))
                        .offset(x: 11, y: -10)
                }
            }
            .frame(width: 28, height: 28)
            .overlay { if cell.isToday { Circle().strokeBorder(Theme.caramelDeep, lineWidth: 1.5) } }
            Text(verbatim: "\(cell.day.day)")
                .font(.system(size: 10, weight: cell.isToday ? .heavy : .medium, design: .rounded))
                .foregroundStyle(cell.isFuture ? Theme.inkSoft.opacity(0.5) : Theme.inkSoft)
        }
        .frame(height: 40)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(cell.day.day), " + String(localized: String.LocalizationValue(Self.markKey(cell.mark)))))
    }

    private var legend: some View {
        HStack(spacing: 14) {
            Label { Text("calendar.onTime") } icon: { Image(systemName: "pawprint.fill").foregroundStyle(Theme.caramel) }
            Label { Text("calendar.late") } icon: { Image(systemName: "zzz").foregroundStyle(Theme.inkSoft) }
            Label { Text("calendar.bedtime") } icon: { Image(systemName: "moon.fill").foregroundStyle(Color(red: 0.55, green: 0.5, blue: 0.78)) }
        }
        .font(.system(size: 11, weight: .medium, design: .rounded))
        .foregroundStyle(Theme.inkSoft)
        .frame(maxWidth: .infinity)
    }

    static func markKey(_ mark: MorningMark) -> String {
        switch mark {
        case .onTime: "calendar.onTime"
        case .late: "calendar.late"
        case .none: "calendar.none"
        }
    }

    /// 星期的简写，从日历的第一天开始排
    static func weekdaySymbols(_ calendar: Calendar) -> [String] {
        var localized = calendar
        localized.locale = .current
        let symbols = localized.veryShortStandaloneWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
    }
}
