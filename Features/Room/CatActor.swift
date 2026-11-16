import CatWorld
import Foundation

/// 布丁在画面上怎么动：Core 只说"她现在该在哪、在做什么"（`CatPresence`），
/// 这里负责从上一个地方走 / 跑 / 跳过去，睡醒先伸个懒腰，到了再换成那件事的姿势。
/// 纯计算（时间作为参数），方便测试。
struct CatActor: Equatable {
    /// 画面上此刻的样子。
    struct Frame: Equatable {
        var spot: RoomPoint
        var depth: CatDepth
        var pose: CatPose
        /// -1 朝左，1 朝右，0 正面
        var facing: Int
        var motion: Motion
        var fidget: CatFidget
        /// 小动作开始了多久（没有小动作时为 nil）
        var fidgetElapsed: TimeInterval?
        /// 是否在地上（显示影子；在家具里面时被前半部分挡住，不画影子）
        var onGround: Bool
    }

    enum Motion: Equatable {
        case rest
        case walk
        case run
        /// 跳起来：0…1
        case jump(Double)
    }

    struct Segment: Equatable {
        enum Kind: Equatable {
            case walk, run, jump
            /// 原地做一个姿势（睡醒伸懒腰）
            case pause(CatPose)
        }

        var kind: Kind
        var from: RoomPoint
        var to: RoomPoint
        var fromDepth: CatDepth
        var toDepth: CatDepth
        var start: Date
        var duration: TimeInterval
        var facing: Int

        var end: Date { start.addingTimeInterval(duration) }
    }

    /// 画布像素：600×800（算距离用，横竖比例和屏幕一致）
    static let canvas = (width: 600.0, height: 800.0)
    static let walkSpeed = 120.0   // 每秒多少画布像素
    static let runSpeed = 300.0
    static let jumpDuration = 0.5
    static let stretchDuration = 1.6

    private(set) var target: CatPresence?
    private(set) var segments: [Segment] = []
    private var fidgetStart: Date?

    /// 收到新的样子。`animated` 为 false 时直接出现在那里（刚打开房间、从后台回来）。
    /// `itemBottoms`：房间里家具底边的 y（用来算跳上 / 跳下家具前站在地板上的哪里）。
    /// `hurry`：跑过去（玩、吃零食、迎接你），不然只有她自己玩的时候才跑。
    /// `speed`：这只猫走路、跑的速度倍数（`CatStyle.speed`）。
    mutating func update(to presence: CatPresence, now: Date, animated: Bool, itemBottoms: [Int: Double], hurry: Bool = false,
                         speed: Double = 1) {
        defer {
            if presence.fidget != .none, presence.fidget != target?.fidget || fidgetStart == nil {
                fidgetStart = now
            } else if presence.fidget == .none {
                fidgetStart = nil
            }
            target = presence
        }
        guard animated, let previous = target, previous.pose != .stateArt, presence.pose != .stateArt else {
            segments = []
            return
        }
        guard presence.spot != previous.spot || presence.depth != previous.depth else {
            if isMoving(at: now) == false { segments = [] }
            return
        }
        let here = frame(at: now)
        segments = Self.plan(from: here, to: presence, now: now, itemBottoms: itemBottoms, hurry: hurry, speed: speed)
    }

    func isMoving(at date: Date) -> Bool {
        guard let last = segments.last else { return false }
        return date < last.end
    }

    /// 此刻画面上的样子。
    func frame(at date: Date) -> Frame {
        guard let target else {
            return Frame(spot: RoomGeometry.catHome, depth: .floor(RoomGeometry.catHome.y), pose: .sit, facing: 0,
                         motion: .rest, fidget: .none, fidgetElapsed: nil, onGround: true)
        }
        if let segment = segments.first(where: { date >= $0.start && date < $0.end }) {
            let t = (date.timeIntervalSince(segment.start) / segment.duration).clamped(to: 0...1)
            switch segment.kind {
            case let .pause(pose):
                return Frame(spot: segment.from, depth: segment.fromDepth, pose: pose, facing: segment.facing,
                             motion: .rest, fidget: .none, fidgetElapsed: nil, onGround: segment.fromDepth.isOnFloor)
            case .walk, .run:
                let spot = Self.lerp(segment.from, segment.to, t)
                return Frame(spot: spot, depth: .floor(spot.y), pose: .stand, facing: segment.facing,
                             motion: segment.kind == .run ? .run : .walk, fidget: .none, fidgetElapsed: nil, onGround: true)
            case .jump:
                var spot = Self.lerp(segment.from, segment.to, t)
                let height = 0.05 + abs(segment.to.y - segment.from.y) * 0.25
                spot.y -= 4 * height * t * (1 - t)
                return Frame(spot: spot, depth: t < 0.5 ? segment.fromDepth : segment.toDepth, pose: .stand,
                             facing: segment.facing, motion: .jump(t), fidget: .none, fidgetElapsed: nil, onGround: false)
            }
        }
        if let first = segments.first, date < first.start {
            return Frame(spot: first.from, depth: first.fromDepth, pose: .stand, facing: first.facing, motion: .rest,
                         fidget: .none, fidgetElapsed: nil, onGround: first.fromDepth.isOnFloor)
        }
        let settledAt = segments.last?.end
        let elapsed = fidgetStart.map { date.timeIntervalSince(max($0, settledAt ?? $0)) }
        return Frame(spot: target.spot, depth: target.depth, pose: target.pose, facing: target.facing, motion: .rest,
                     fidget: target.fidget, fidgetElapsed: target.fidget == .none ? nil : elapsed,
                     onGround: target.depth.isOnFloor)
    }

    /// 从此刻的样子到新地方：（睡醒先伸懒腰）→（在家具上就先跳下来）→ 走 / 跑过去 →（要上家具就跳上去）。
    static func plan(from here: Frame, to presence: CatPresence, now: Date, itemBottoms: [Int: Double], hurry: Bool = false,
                     speed pace: Double = 1) -> [Segment] {
        var segments: [Segment] = []
        var clock = now
        var position = here.spot
        var depth = here.depth
        var facing = here.facing == 0 ? (presence.spot.x >= position.x ? 1 : -1) : here.facing

        func add(_ kind: Segment.Kind, to point: RoomPoint, depth newDepth: CatDepth, duration: TimeInterval) {
            if point.x != position.x { facing = point.x > position.x ? 1 : -1 }
            segments.append(Segment(kind: kind, from: position, to: point, fromDepth: depth, toDepth: newDepth,
                                    start: clock, duration: duration, facing: facing))
            clock = clock.addingTimeInterval(duration)
            position = point
            depth = newDepth
        }

        if here.motion == .rest, [.curl, .sprawl, .purr].contains(here.pose) {
            add(.pause(.stretch), to: position, depth: depth, duration: stretchDuration)
        }
        if case .jump = here.motion {} else if !depth.isOnFloor {
            let base = floorBase(for: depth, spot: position, itemBottoms: itemBottoms)
            add(.jump, to: base, depth: .floor(base.y), duration: jumpDuration)
        }
        let destinationBase = presence.depth.isOnFloor
            ? presence.spot
            : floorBase(for: presence.depth, spot: presence.spot, itemBottoms: itemBottoms)
        let running = hurry || presence.activity == .play
        let distance = pixelDistance(position, destinationBase)
        if distance > 2 {
            let speed = (running ? runSpeed : walkSpeed) * pace
            add(running ? .run : .walk, to: destinationBase, depth: .floor(destinationBase.y), duration: max(0.3, distance / speed))
        }
        if !presence.depth.isOnFloor {
            add(.jump, to: presence.spot, depth: presence.depth, duration: jumpDuration)
        }
        return segments
    }

    /// 跳上 / 跳下一件家具时站在地板上的位置：家具前面一点。
    static func floorBase(for depth: CatDepth, spot: RoomPoint, itemBottoms: [Int: Double]) -> RoomPoint {
        let bottom: Double
        switch depth {
        case let .on(id), let .inside(id): bottom = itemBottoms[id] ?? spot.y
        case let .floor(y): bottom = y
        }
        return RoomPoint(x: spot.x.clamped(to: 0.12...0.88), y: (bottom + 0.02).clamped(to: 0.7...0.97))
    }

    static func pixelDistance(_ a: RoomPoint, _ b: RoomPoint) -> Double {
        let dx = (a.x - b.x) * canvas.width, dy = (a.y - b.y) * canvas.height
        return (dx * dx + dy * dy).squareRoot()
    }

    static func lerp(_ a: RoomPoint, _ b: RoomPoint, _ t: Double) -> RoomPoint {
        RoomPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }
}

extension CatDepth {
    var isOnFloor: Bool {
        if case .floor = self { true } else { false }
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
