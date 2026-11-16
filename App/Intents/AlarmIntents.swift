import AlarmKit
import AppIntents
import CatEngine
import CatWorld
import Economy
import Foundation

/// 锁屏 / 灵动岛上点"停止"。App 没打开也会运行：把事件写进 EventLog，下次打开 App 时由 CatWorld 处理。
struct StopAlarmIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "alarm.stop"

    @Parameter(title: "Alarm ID")
    var alarmID: String

    init(alarmID: String) {
        self.alarmID = alarmID
    }

    init() {
        alarmID = ""
    }

    func perform() async throws -> some IntentResult {
        AlarmIntentRecorder.record(.stopped, alarmID: alarmID)
        if let id = UUID(uuidString: alarmID) {
            try? AlarmManager.shared.stop(id: id)
        }
        return .result()
    }
}

/// 锁屏 / 灵动岛上点"贪睡"。
struct SnoozeAlarmIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "wake.snooze"

    @Parameter(title: "Alarm ID")
    var alarmID: String

    init(alarmID: String) {
        self.alarmID = alarmID
    }

    init() {
        alarmID = ""
    }

    func perform() async throws -> some IntentResult {
        AlarmIntentRecorder.record(.snoozed, alarmID: alarmID)
        if let id = UUID(uuidString: alarmID) {
            try? AlarmManager.shared.countdown(id: id)
        }
        return .result()
    }
}

/// 把锁屏上的操作写进事件日志。响铃时间按 world.json 里的闹钟排程推算（见 CatWorld.alarmEvents）。
enum AlarmIntentRecorder {
    static func record(_ action: AlarmAction, alarmID: String) {
        let log = EventLog(fileURL: AppGroup.file("events.jsonl"))
        let now = Date.now
        let events: [LoggedEvent]
        if let state = try? WorldStorage(fileURL: AppGroup.file("world.json")).load(),
           let catalog = try? Catalog.bundled() {
            let world = CatWorld(state: state, catConfig: CatEngineConfig(calendar: .autoupdatingCurrent),
                                 economy: EconomyEngine(catalog: catalog))
            events = world.alarmEvents(action, alarmID: alarmID, at: now)
        } else {
            let fired = LoggedEvent(id: "alarm-fired-\(alarmID)-\(Int(now.timeIntervalSince1970))",
                                    event: .alarmFired(alarmID: alarmID, at: now))
            let action: CatEvent = action == .snoozed
                ? .alarmSnoozed(alarmID: alarmID, at: now)
                : .alarmStopped(alarmID: alarmID, via: .lockScreen, at: now)
            events = [fired, LoggedEvent(id: UUID().uuidString, event: action)]
        }
        for event in events {
            try? log.append(event)
        }
    }
}
