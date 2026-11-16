import CatWorld
import Foundation

/// 把整个 `WorldState` 存成一个 JSON 文件（App Group 里，App Intent 和小组件也能读）。
/// 整体写入是原子的，所以"处理事件 + 发奖励 + 标记已处理"不会只存一半。
///
/// TODO(Mac)：另存一份到 SwiftData + CloudKit，用于换手机恢复（见 docs/app-integration.md 第 6 节）。
struct WorldStorage: Sendable {
    let fileURL: URL

    func load() throws -> WorldState? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try JSONDecoder().decode(WorldState.self, from: Data(contentsOf: fileURL))
    }

    func save(_ state: WorldState) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(state).write(to: fileURL, options: .atomic)
    }
}
