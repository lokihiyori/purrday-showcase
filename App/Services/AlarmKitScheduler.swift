import AlarmKit
import CatWorld
import Foundation
import SwiftUI

/// 用 AlarmKit 让闹钟真正响起来。API 按 iOS 26.5 SDK 里 AlarmKit 的 .swiftinterface 实现。
///
/// - 闹钟响时系统显示全屏提醒（静音、专注模式也会响），按钮：停止（系统提供）+ 贪睡（倒计时 9 分钟）
/// - 锁屏上点停止 / 贪睡会运行 `StopAlarmIntent` / `SnoozeAlarmIntent`，把事件写进 EventLog
/// - 点提醒本身会打开 App，进入叫醒界面摸猫关闹钟
struct AlarmKitScheduler: AlarmScheduling {
    static let snoozeDuration: TimeInterval = 9 * 60

    func requestAuthorization() async -> Bool {
        let manager = AlarmManager.shared
        switch manager.authorizationState {
        case .authorized:
            return true
        case .denied:
            return false
        case .notDetermined:
            return (try? await manager.requestAuthorization()) == .authorized
        @unknown default:
            return false
        }
    }

    func schedule(_ alarm: AlarmConfig) async throws {
        guard let id = UUID(uuidString: alarm.id) else { return }
        let schedule: Alarm.Schedule
        if alarm.isOneShot {
            guard let date = AlarmSchedule.nextFire(of: alarm, after: .now, calendar: .autoupdatingCurrent) else { return }
            schedule = .fixed(date)
        } else {
            let days = alarm.repeatDays.sorted().map(\.localeWeekday)
            schedule = .relative(Alarm.Schedule.Relative(
                time: Alarm.Schedule.Relative.Time(hour: alarm.time.hour, minute: alarm.time.minute),
                repeats: .weekly(days)
            ))
        }
        let configuration = AlarmManager.AlarmConfiguration(
            countdownDuration: Alarm.CountdownDuration(preAlert: nil, postAlert: Self.snoozeDuration),
            schedule: schedule,
            attributes: Self.attributes(),
            stopIntent: StopAlarmIntent(alarmID: alarm.id),
            secondaryIntent: SnoozeAlarmIntent(alarmID: alarm.id)
        )
        _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
    }

    func cancel(alarmID: String) async throws {
        guard let id = UUID(uuidString: alarmID) else { return }
        try AlarmManager.shared.cancel(id: id)
    }

    func stop(alarmID: String) async throws {
        guard let id = UUID(uuidString: alarmID) else { return }
        try AlarmManager.shared.stop(id: id)
    }

    func snooze(alarmID: String) async throws {
        guard let id = UUID(uuidString: alarmID) else { return }
        try AlarmManager.shared.countdown(id: id)
    }

    private static func attributes() -> AlarmAttributes<PurrdayAlarmMetadata> {
        let snooze = AlarmButton(text: "wake.snooze", textColor: .white, systemImageName: "zzz")
        let alert: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            alert = AlarmPresentation.Alert(title: "alarm.alert.title", secondaryButton: snooze, secondaryButtonBehavior: .countdown)
        } else {
            let stop = AlarmButton(text: "alarm.stop", textColor: .white, systemImageName: "pawprint.fill")
            alert = AlarmPresentation.Alert(title: "alarm.alert.title", stopButton: stop, secondaryButton: snooze, secondaryButtonBehavior: .countdown)
        }
        let presentation = AlarmPresentation(alert: alert, countdown: AlarmPresentation.Countdown(title: "alarm.countdown.title"))
        return AlarmAttributes(presentation: presentation, metadata: PurrdayAlarmMetadata(), tintColor: Color("AccentColor"))
    }
}

extension Weekday {
    var localeWeekday: Locale.Weekday {
        switch self {
        case .sunday: .sunday
        case .monday: .monday
        case .tuesday: .tuesday
        case .wednesday: .wednesday
        case .thursday: .thursday
        case .friday: .friday
        case .saturday: .saturday
        }
    }
}
