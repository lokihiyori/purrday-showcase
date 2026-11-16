import Foundation

/// App、小组件、App Intent 共用的 App Group。和 project.yml 里的 entitlements 保持一致。
enum AppGroup {
    static let identifier = "group.com.purrday.app"

    /// App Group 容器里的文件（拿不到容器时退回到本地文档目录，例如单元测试）。
    static func file(_ name: String) -> URL {
        let fallback = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        #if canImport(Darwin)
        let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) ?? fallback
        #else
        let directory = fallback // Linux 上检查编译时没有 App Group
        #endif
        return directory.appendingPathComponent(name)
    }
}
