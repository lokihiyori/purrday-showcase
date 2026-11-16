import CatEngine
import Economy
import Foundation

// 你不在的时候（docs/cat-life.md 3.4）：再打开 App 时，按她的作息推算这段时间她做了什么，
// 挑几件说给你听，再在房间里留下一点痕迹（玩过的玩具还在地上）。
// 全部由种子 + 时间算出来，不存档，不影响别的。

/// 离开期间她做的一件事。
public struct AwayHighlight: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case activity(CatActivity)
        /// 夜里睡了一整晚
        case night
    }

    public var kind: Kind
    /// 一共做了多少分钟
    public var minutes: Int

    public init(kind: Kind, minutes: Int) {
        self.kind = kind
        self.minutes = minutes
    }
}

/// 她在房间里留下的痕迹。
public struct RoomTrace: Hashable, Sendable {
    /// 玩过的玩具（礼物 / 纪念品的目录 id），还丢在地板上
    public var toy: String
    public var spot: RoomPoint
}

/// 你不在的这段时间。
public struct AwayReport: Hashable, Sendable {
    public var from: Date
    public var to: Date
    /// 最值得说的几件事（最多三件，按有意思的程度排）
    public var highlights: [AwayHighlight]
    public var trace: RoomTrace?

    public var minutes: Int { Int(to.timeIntervalSince(from) / 60) }
}

extension CatWorld {
    /// 离开多久才算"你不在"
    public static let awayAfter: TimeInterval = 60 * 60
    /// 最多往回看多久
    static let awayLookback: TimeInterval = 24 * 3600

    /// 从 `from` 到 `to` 她做了什么。离开不到一小时返回 nil。
    /// 白天（起床时间到睡前时间）按作息一段一段看；夜里算睡觉。
    public func awayReport(from: Date, to: Date) -> AwayReport? {
        guard to.timeIntervalSince(from) >= Self.awayAfter else { return nil }
        let start = max(from, to.addingTimeInterval(-Self.awayLookback))
        let candidates = spotCandidates()
        var minutes: [AwayHighlight.Kind: Int] = [:]
        var lastToy: (block: Int, date: Date)?
        let step = LifeSchedule.block
        var block = Self.index(of: start, step: step) + 1
        let last = Self.index(of: to, step: step)
        while block < last {
            let date = Date(timeIntervalSinceReferenceDate: Double(block) * step)
            let day = catConfig.logicalDay(of: date)
            let awake = date >= wakeTime(day: day) && date < catConfig.date(catConfig.bedtime, in: day)
            if awake {
                let activity = activity(atBlock: block, date: date, candidates: candidates)
                minutes[.activity(activity), default: 0] += Int(step / 60)
                if activity == .toy { lastToy = (block, date) }
            } else {
                minutes[.night, default: 0] += Int(step / 60)
            }
            block += 1
        }
        // 夜里不到两小时不值得说
        if (minutes[.night] ?? 0) < 120 { minutes[.night] = nil }
        let ranked = minutes.sorted { a, b in
            let (ia, ib) = (Self.interest(a.key), Self.interest(b.key))
            return ia != ib ? ia > ib : (a.value != b.value ? a.value > b.value : Self.order(a.key) < Self.order(b.key))
        }
        let highlights = ranked.prefix(3).map { AwayHighlight(kind: $0.key, minutes: $0.value) }
        guard !highlights.isEmpty else { return nil }

        var trace: RoomTrace?
        if let lastToy, state.cat.state == .idleDaytime {
            // 玩过的玩具丢在她最后玩的地方（现在没在玩的话）
            let then = lifePresenceForAway(at: lastToy.date)
            if let toy = then.prop, presence(at: to).activity != .toy {
                trace = RoomTrace(toy: toy, spot: RoomPoint(x: (then.spot.x + 0.08).clamped(to: 0.12...0.88), y: then.spot.y))
            }
        }
        return AwayReport(from: start, to: to, highlights: highlights, trace: trace)
    }

    /// 越有意思的事越先说（发呆、趴着排最后）
    static func interest(_ kind: AwayHighlight.Kind) -> Int {
        switch kind {
        case .night: 3
        case let .activity(activity):
            switch activity {
            case .toy, .play, .bellyUp, .knead, .hide, .sunbathe: 4
            case .watch, .perch, .scratch, .explore: 3
            case .nap, .groom, .eat, .drink: 2
            case .sit, .loaf: 1
            }
        }
    }

    private static func order(_ kind: AwayHighlight.Kind) -> Int {
        switch kind {
        case .night: -1
        case let .activity(activity): CatActivity.allCases.firstIndex(of: activity) ?? 0
        }
    }
}
