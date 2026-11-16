import CatEngine
import CatWorld
import Economy
import SwiftUI
import WidgetKit

/// 锁屏 / 主屏小组件：猫现在在做什么，下一个闹钟几点（计划书阶段 1）。
@main
struct PurrdayWidgets: WidgetBundle {
    var body: some Widget {
        CatWidget()
        AlarmLiveActivity()
    }
}

struct CatWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CatWidget", provider: CatTimelineProvider()) { entry in
            CatWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color("RoomBackground") }
        }
        .configurationDisplayName("widget.name")
        .description("widget.description")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .systemSmall])
    }
}

struct CatTimelineEntry: TimelineEntry {
    let date: Date
    let cat: WidgetEntry?
}

struct CatTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> CatTimelineEntry {
        CatTimelineEntry(date: .now, cat: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (CatTimelineEntry) -> Void) {
        completion(entries(now: .now).first ?? placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CatTimelineEntry>) -> Void) {
        let now = Date.now
        // App 每次保存都会让小组件刷新；这里再兜底每 6 小时重新算一次
        completion(Timeline(entries: entries(now: now), policy: .after(now.addingTimeInterval(6 * 3600))))
    }

    private func entries(now: Date) -> [CatTimelineEntry] {
        guard let state = try? WorldStorage(fileURL: AppGroup.file("world.json")).load(),
              let catalog = try? Catalog.bundled()
        else {
            return [CatTimelineEntry(date: now, cat: nil)]
        }
        let world = CatWorld(state: state, catConfig: CatEngineConfig(calendar: .autoupdatingCurrent),
                             economy: EconomyEngine(catalog: catalog))
        return world.widgetTimeline(now: now).map { CatTimelineEntry(date: $0.date, cat: $0) }
    }
}

struct CatWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CatTimelineEntry

    /// 现在陪着你的那只猫此刻的样子：白天待机时是她在做的那件事的姿势，其他状态是那个时刻的画
    private var art: String {
        guard let cat = entry.cat else { return "cat-idle" }
        if cat.state == .idleDaytime, cat.activity != nil, let pose = CatArtNames.pose(cat.pose, kind: cat.kind) {
            return pose
        }
        return CatArtNames.still(CatArt.assetName(state: cat.state, mischief: cat.mischief), kind: cat.kind)
    }

    /// 她在做什么：白天待机时说具体的事（在晒太阳、在玩玩具……），其他时候说状态
    private var stateKey: LocalizedStringKey {
        if let cat = entry.cat, cat.state == .idleDaytime, let activity = cat.activity {
            return LocalizedStringKey(Self.activityKey(activity))
        }
        return LocalizedStringKey(entry.cat?.state.nameKey ?? "state.idleDaytime")
    }

    static func activityKey(_ activity: CatActivity) -> String { "activity.\(activity.rawValue)" }

    /// 姿势图的画布比猫宽很多（两边是空的），按高度铺满、裁掉两边，猫才够大
    private var picture: some View {
        Image(art).resizable().scaledToFill()
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            picture.frame(width: 44, height: 44).clipped().padding(2)
        case .accessoryRectangular:
            HStack(spacing: 6) {
                picture.frame(width: 46, height: 46).clipped()
                VStack(alignment: .leading, spacing: 2) {
                    Text(stateKey).font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                    alarmLine.font(.caption)
                }
            }
        default:
            VStack(alignment: .leading, spacing: 4) {
                picture.frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
                Text(stateKey).font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                alarmLine.font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var alarmLine: some View {
        if let next = entry.cat?.nextAlarmAt {
            Label { Text(next, style: .time) } icon: { Image(systemName: "alarm.fill") }
        } else {
            Text("widget.noAlarm")
        }
    }
}
