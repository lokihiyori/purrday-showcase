import ActivityKit
import AlarmKit
import CatWorld
import SwiftUI
import WidgetKit

/// 现在陪着你的是哪只猫（从 App Group 里的存档读；读不到就是布丁）。
enum ActiveCat {
    static func kind() -> CatKind {
        (try? WorldStorage(fileURL: AppGroup.file("world.json")).load())?.activeCat ?? .pudding
    }

    /// 赖床时踩你的那张画
    static var kneadArt: String { CatArtNames.still("cat-knead", kind: kind()) }
}

/// 贪睡倒计时的实时活动（锁屏 + 灵动岛）：现在陪着你的那只猫在旁边等着下一次叫你。
struct AlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<PurrdayAlarmMetadata>.self) { context in
            HStack(spacing: 16) {
                Image(ActiveCat.kneadArt).resizable().scaledToFit().frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title(for: context.state.mode)).font(.headline)
                    countdown(context.state.mode).font(.title2.monospacedDigit().weight(.semibold))
                }
                Spacer(minLength: 0)
            }
            .padding()
            .activityBackgroundTint(Color("RoomBackground"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(ActiveCat.kneadArt).resizable().scaledToFit().frame(width: 44, height: 44)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdown(context.state.mode).font(.title3.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(title(for: context.state.mode)).font(.caption)
                }
            } compactLeading: {
                Image(ActiveCat.kneadArt).resizable().scaledToFit()
            } compactTrailing: {
                countdown(context.state.mode).monospacedDigit().frame(maxWidth: 44)
            } minimal: {
                Image(ActiveCat.kneadArt).resizable().scaledToFit()
            }
        }
    }

    private func title(for mode: AlarmPresentationState.Mode) -> LocalizedStringKey {
        switch mode {
        case .alert: "alarm.alert.title"
        case .countdown, .paused: "alarm.countdown.title"
        @unknown default: "alarm.countdown.title"
        }
    }

    @ViewBuilder
    private func countdown(_ mode: AlarmPresentationState.Mode) -> some View {
        switch mode {
        case let .countdown(countdown):
            Text(timerInterval: countdown.startDate...max(countdown.startDate, countdown.fireDate), countsDown: true)
        default:
            Text(verbatim: "")
        }
    }
}
