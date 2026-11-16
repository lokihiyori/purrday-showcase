import CatEngine
import Foundation

/// 每个逻辑日一条记录（对应 SwiftData 的 `DayLog`），统计和周日记都从这里取。
public struct DayLog: Codable, Hashable, Sendable {
    public var day: LogicalDay
    /// nil 表示这天没有可记录的叫醒
    public var wokeOnTime: Bool?
    public var snoozeCount: Int = 0
    /// 完成的番茄钟分钟数（中途放弃的不算）
    public var focusMinutes: Int = 0
    public var completedFocusSessions: Int = 0
    /// 读书分钟数（没读完也算）
    public var readingMinutes: Int = 0
    /// HealthKit 步数（V1.2），由 App 写入
    public var steps: Int?
    public var sleptAt: Date?

    public init(day: LogicalDay) {
        self.day = day
    }
}
