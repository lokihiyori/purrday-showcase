import CatEngine
import CatWorld
import SwiftUI

struct AlarmListView: View {
    @Environment(WorldStore.self) private var store
    @State private var editing: AlarmConfig?
    @State private var showLimit = false

    var body: some View {
        NavigationStack {
            List {
                BannerHeader(image: "banner-alarms", title: "alarms.title", subtitle: "alarms.subtitle")
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                if store.world.state.alarms.isEmpty {
                    Text("alarms.empty")
                        .font(.system(.callout, design: .rounded))
                        .foregroundStyle(Theme.inkSoft)
                        .frame(maxWidth: .infinity)
                        .gameCard()
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                ForEach(store.world.state.alarms) { alarm in
                    Button { editing = alarm } label: { AlarmRow(alarm: alarm) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("alarms.row")
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                }
                .onDelete { offsets in
                    let ids = offsets.map { store.world.state.alarms[$0].id }
                    ids.forEach(store.removeAlarm)
                }
                // 起床日历：每天早上一个爪印
                MorningCalendarCard()
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 24, trailing: 16))
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .ignoresSafeArea(edges: .top)
            .background(PaperBackground())
            .toolbar {
                Button {
                    editing = AlarmConfig(id: UUID().uuidString, time: TimeOfDay(7), repeatDays: Weekday.weekdays, armedAt: .now)
                } label: {
                    Label("alarms.add", systemImage: "plus")
                }
                .accessibilityIdentifier("alarms.add")
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .sheet(item: $editing) { alarm in
                AlarmEditView(alarm: alarm) { showLimit = true }
            }
            .alert("alarms.limit.title", isPresented: $showLimit) {
                Button("common.close", role: .cancel) {}
                Button("paywall.title") { store.paywallRequested = true }
            } message: {
                Text("alarms.limit.body")
            }
        }
    }
}

/// 一个闹钟：大大的时间、重复方式、小铃铛。
struct AlarmRow: View {
    let alarm: AlarmConfig

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(alarm.isEnabled ? Theme.caramel.opacity(0.16) : Theme.line)
                Image(systemName: alarm.isEnabled ? "bell.fill" : "bell.slash")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(alarm.isEnabled ? Theme.caramel : Theme.inkSoft)
            }
            .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(alarm.time.displayDate.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                Text(LocalizedStringKey(RepeatChoice(alarm.repeatDays).titleKey))
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.inkSoft)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(Theme.inkSoft)
        }
        .gameCard()
        .opacity(alarm.isEnabled ? 1 : 0.55)
    }
}

/// 闹钟重复方式（MVP 只提供三种）。
enum RepeatChoice: Hashable, CaseIterable {
    case once, weekdays, everyday

    init(_ days: Set<Weekday>) {
        switch days {
        case []: self = .once
        case Weekday.everyday: self = .everyday
        default: self = .weekdays
        }
    }

    var days: Set<Weekday> {
        switch self {
        case .once: []
        case .weekdays: Weekday.weekdays
        case .everyday: Weekday.everyday
        }
    }

    var titleKey: String {
        switch self {
        case .once: "alarms.repeat.once"
        case .weekdays: "alarms.repeat.weekdays"
        case .everyday: "alarms.repeat.everyday"
        }
    }
}

extension TimeOfDay {
    /// 今天这个时刻，只用来显示和 DatePicker。
    var displayDate: Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
    }

    init(_ date: Date) {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        self.init(c.hour ?? 7, c.minute ?? 0)
    }
}
