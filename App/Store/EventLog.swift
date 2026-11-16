import CatWorld
import Foundation

/// 事件日志：一行一条 JSON（JSON Lines），放在 App Group 里。
/// App Intent（锁屏上停止 / 贪睡）和 App 自己都往里追加；`CatWorld.ingest` 按 id 去重，所以整份重复提交是安全的。
///
/// TODO(Mac)：App Intent 如果跑在单独的进程里，读写这个文件要用 NSFileCoordinator 协调。
struct EventLog: Sendable {
    let fileURL: URL

    func append(_ event: LoggedEvent) throws {
        var line = try JSONEncoder().encode(event)
        line.append(0x0A)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try line.write(to: fileURL, options: .atomic)
        }
    }

    /// 读出全部事件；坏掉的行跳过。
    func readAll() -> [LoggedEvent] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        return data.split(separator: 0x0A).compactMap { try? decoder.decode(LoggedEvent.self, from: Data($0)) }
    }

    /// 删掉比 `cutoff` 更早的事件（CatWorld 只记 14 天内处理过的 id，更早的提交了也会被丢弃）。
    func prune(olderThan cutoff: Date) throws {
        let kept = readAll().filter { $0.event.at >= cutoff }
        let encoder = JSONEncoder()
        var data = Data()
        for event in kept {
            data.append(try encoder.encode(event))
            data.append(0x0A)
        }
        try data.write(to: fileURL, options: .atomic)
    }
}
