import CatWorld
import Foundation

/// 真正让闹钟响的部分（AlarmKit）。WorldStore 只依赖这个协议，方便预览和测试。
protocol AlarmScheduling: Sendable {
    /// 请求闹钟权限，返回是否已授权
    func requestAuthorization() async -> Bool
    /// 新增或更新一个闹钟。`alarm.id` 是 UUID 字符串，AlarmKit 用 UUID 作为闹钟 id
    func schedule(_ alarm: AlarmConfig) async throws
    func cancel(alarmID: String) async throws
    /// 停止正在响的闹钟（在 App 里摸猫关掉时）
    func stop(alarmID: String) async throws
    /// 让正在响的闹钟进入贪睡倒计时
    func snooze(alarmID: String) async throws
}

/// 预览和测试用：什么都不做。
struct PreviewAlarmScheduler: AlarmScheduling {
    func requestAuthorization() async -> Bool { true }
    func schedule(_ alarm: AlarmConfig) async throws {}
    func cancel(alarmID: String) async throws {}
    func stop(alarmID: String) async throws {}
    func snooze(alarmID: String) async throws {}
}
