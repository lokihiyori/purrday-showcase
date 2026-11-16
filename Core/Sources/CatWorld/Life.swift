import CatEngine
import Economy
import Foundation

// 布丁的日常生活（docs/cat-life.md 第 3 节）：白天待机时她按作息自己找事做，不用你互动。
//
// 结果只由"存档里的种子 + 房间里的家具 + 时间"算出来，不改存档：
// 同一时刻问几次都一样，关掉 App 再打开，她还在做原来那件事。
// 时间分两级：每 15 分钟一"段"决定她在做什么、在哪里；每 20 秒一"拍"决定小动作（打哈欠、甩尾巴……），
// 到处闻、自己玩的时候每一拍换一个地方。

/// 白天待机时布丁在做的事。和家具用途（`FurnitureUse`）同名的那些，可以在家具上做。
public enum CatActivity: String, Codable, Sendable, CaseIterable {
    /// 坐着发呆
    case sit
    /// 揣手趴着
    case loaf
    /// 舔毛洗脸
    case groom
    /// 睡觉
    case nap
    /// 晒太阳（只在有太阳的时候）
    case sunbathe
    /// 看窗外、看鱼
    case watch
    /// 吃饭（要有食盆）
    case eat
    /// 喝水（要有饮水机）
    case drink
    /// 磨爪（要有猫抓板 / 猫爬架）
    case scratch
    /// 躲起来（要有纸箱这类能钻进去的）
    case hide
    /// 待在高处（要有猫爬架、置物架这类）
    case perch
    /// 到处走走闻闻
    case explore
    /// 自己玩、跑来跑去
    case play
    /// 玩玩具：拨你送的小东西、抱着蹬（要有能当玩具的礼物，`LifeSchedule.toys`）
    case toy
    /// 在你面前仰躺露肚皮，等你来玩（亲近以后）
    case bellyUp
    /// 踩奶（在软的地方）
    case knead

    var use: FurnitureUse? { FurnitureUse(rawValue: rawValue) }
}

/// 布丁的姿势。界面按它选分层动画（`Features/Room/CatRig.swift`）。
public enum CatPose: String, Codable, Sendable, CaseIterable {
    /// 正面坐着
    case sit
    /// 背对你坐着（看窗外、看鱼）
    case sitBack
    /// 揣手趴着
    case loaf
    /// 坐着舔爪子洗脸
    case groom
    /// 蜷成一团睡
    case curl
    /// 侧躺摊开（晒太阳）
    case sprawl
    /// 伸懒腰（磨爪）
    case stretch
    /// 侧面站着（闻东西、走路、跑）
    case stand
    /// 侧面低头（吃饭、喝水）
    case eat
    /// 揣手闭眼打呼噜（睡前）
    case purr
    /// 用这个状态专门的画（叫醒、送礼物、捣乱、陪你做事），见 `CatArt`
    case stateArt
    // 下面这些是新活动和互动反应用的姿势（AI 画的整张图，原图在 design/incoming/poses）
    /// 仰躺露肚皮，爪子蜷在空中
    case bellyUp
    /// 侧面往前蹭，闭眼，尾巴竖起（朝右）
    case rub
    /// 正面坐着抬下巴，闭眼
    case chinUp
    /// 正面趴着踩奶
    case knead
    /// 侧躺着抬头看你
    case lieSide
    /// 正面坐着歪头
    case headTilt
    /// 压低身子准备扑（朝右）
    case crouch
    /// 扑在半空（朝右）
    case leap
    /// 坐着抬爪子拍（朝右）
    case bat
    /// 舔嘴巴，闭眼
    case lickLips
    /// 张嘴叫
    case meow
    /// 耳朵往后、尾巴炸开（朝右）
    case annoyed
    /// 弓背吓一跳（朝右）
    case startled
    /// 仰躺着睡
    case sleepBelly
    /// 跑，四脚腾空（朝右）
    case run
    /// 抱着玩具蹬
    case toyKick
    /// 后腿站起来，前爪往上够（朝右）
    case reach
}

/// 一拍里的小动作，只影响画面。
public enum CatFidget: String, Codable, Sendable, CaseIterable {
    case none
    case yawn
    case lookAround
    case tailFlick
    case earTwitch
    case slowBlink
    case sniff
}

/// 布丁在前后顺序里的位置。
public enum CatDepth: Hashable, Sendable {
    /// 在地板上：和地上的家具按 `y` 比前后
    case floor(Double)
    /// 在这件家具上面：紧跟着它画
    case on(itemID: Int)
    /// 在这件家具里面：画在它和它的前半部分之间
    case inside(itemID: Int)
}

/// 此刻布丁在房间里的样子：在做什么、什么姿势、在哪里。
public struct CatPresence: Hashable, Sendable {
    /// 白天待机时在做的事；其他状态（夜里睡觉、叫醒……）为 nil
    public var activity: CatActivity?
    public var pose: CatPose
    /// 脚底中点（房间坐标）
    public var spot: RoomPoint
    public var depth: CatDepth
    /// 朝向：-1 朝左，0 正面，1 朝右。只对侧面的姿势（站、吃、伸懒腰）有意义
    public var facing: Int
    public var fidget: CatFidget
    /// 下一拍开始的时间：界面在这时候再问一次
    public var nextChange: Date
    /// 她在玩的东西（玩玩具时是那件礼物的目录 id），界面画在她爪子前面
    public var prop: String?

    public init(activity: CatActivity?, pose: CatPose, spot: RoomPoint, depth: CatDepth, facing: Int = 0,
                fidget: CatFidget = .none, nextChange: Date, prop: String? = nil) {
        self.activity = activity
        self.pose = pose
        self.spot = spot
        self.depth = depth
        self.facing = facing
        self.fidget = fidget
        self.nextChange = nextChange
        self.prop = prop
    }
}

/// 一天里的时段，以起床时间和睡前时间为基准（docs/cat-life.md 3.1）。
public enum LifeSlot: String, Sendable, CaseIterable {
    /// 起床之前（没设闹钟的早上，或者你比闹钟起得早）
    case early
    /// 起床后一个半小时：吃早餐、洗脸
    case morning
    /// 上午：晒太阳、看窗外
    case forenoon
    /// 中午到 15:00：午睡
    case noon
    /// 15:00–18:00：玩、磨爪、到处闻
    case afternoon
    /// 18:00 到睡前一小时：看鸟、吃晚饭
    case evening
    /// 睡前一小时：揣手、打盹
    case late
}

public enum LifeSchedule {
    /// 一段多长：每段决定一次在做什么
    public static let block: TimeInterval = 15 * 60
    /// 一拍多长：每拍决定一次小动作
    public static let beat: TimeInterval = 20
    /// 当天没有闹钟时假设的起床时间
    public static let defaultWake = TimeOfDay(8)
    /// 有太阳的时间（画面钟点：日出后一小时到日落前半小时，见 `SceneClock`）
    static let sunHours = 7.5..<17.5

    /// 每个时段里各件事的权重（docs/cat-life.md 3.1 的表）。没写的是 0。
    static let weights: [LifeSlot: [CatActivity: Double]] = [
        .early: [.sit: 1, .loaf: 3, .groom: 2, .nap: 4, .watch: 1, .hide: 1, .perch: 1],
        .morning: [.sit: 2, .loaf: 1, .groom: 4, .nap: 1, .watch: 2, .eat: 5, .drink: 2, .scratch: 2, .perch: 1,
                   .explore: 2, .play: 1],
        .forenoon: [.sit: 2, .loaf: 2, .groom: 2, .nap: 2, .sunbathe: 5, .watch: 4, .drink: 1, .scratch: 1, .hide: 1,
                    .perch: 3, .explore: 2, .play: 2],
        .noon: [.sit: 1, .loaf: 2, .groom: 1, .nap: 8, .sunbathe: 3, .watch: 1, .drink: 1, .hide: 2, .perch: 1,
                .explore: 1],
        .afternoon: [.sit: 2, .loaf: 2, .groom: 2, .nap: 2, .sunbathe: 2, .watch: 3, .eat: 1, .drink: 2, .scratch: 3,
                     .hide: 2, .perch: 3, .explore: 4, .play: 5],
        .evening: [.sit: 2, .loaf: 3, .groom: 3, .nap: 2, .watch: 4, .eat: 3, .drink: 1, .scratch: 1, .hide: 1,
                   .perch: 2, .explore: 2, .play: 2],
        .late: [.sit: 1, .loaf: 4, .groom: 3, .nap: 4, .watch: 1, .drink: 1, .hide: 1, .perch: 1],
    ]

    /// 好感度、玩具带来的事（按时段的权重；要满足条件才会做，见 `CatWorld.availableWeights`）
    static let extraWeights: [LifeSlot: [CatActivity: Double]] = [
        .early: [.knead: 1],
        .morning: [.toy: 1],
        .forenoon: [.toy: 2, .bellyUp: 1],
        .noon: [.bellyUp: 1, .knead: 1],
        .afternoon: [.toy: 4, .bellyUp: 2],
        .evening: [.toy: 2, .bellyUp: 2, .knead: 1],
        .late: [.knead: 3, .bellyUp: 1],
    ]

    /// 能当玩具的礼物和纪念品（你得先拥有它，她才会拿来玩）
    public static let toys = [
        "gift.yarn_ball", "gift.tiny_bell", "gift.ribbon", "gift.milk_cap", "souvenir.feather",
        "souvenir.acorn", "souvenir.pinecone",
    ]

    /// 上一段在做的事这一段接着做的概率：睡觉一睡就很久，玩一会儿就换
    static func stay(_ activity: CatActivity) -> Double {
        switch activity {
        case .nap: 0.75
        case .sunbathe, .perch, .hide: 0.6
        case .explore, .play, .eat, .drink, .scratch, .toy, .knead: 0.3
        case .bellyUp: 0.2
        default: 0.5
        }
    }

    /// 每种姿势会有的小动作（每拍有一半机会做一个）
    static func fidgets(for pose: CatPose) -> [CatFidget] {
        switch pose {
        case .sit: [.yawn, .lookAround, .tailFlick, .slowBlink]
        case .loaf: [.yawn, .tailFlick, .earTwitch, .slowBlink]
        case .curl, .sprawl, .purr, .sleepBelly: [.earTwitch, .tailFlick]
        case .sitBack: [.lookAround, .tailFlick]
        case .stand: [.sniff, .tailFlick]
        case .bellyUp, .lieSide: [.tailFlick, .earTwitch, .slowBlink]
        case .groom, .stretch, .eat, .stateArt, .rub, .chinUp, .knead, .headTilt, .crouch, .leap, .bat, .lickLips,
             .meow, .annoyed, .startled, .run, .toyKick, .reach: []
        }
    }
}

extension RoomGeometry {
    /// 没有家具时也能坐、趴、睡的地板位置
    static let restPoints = [
        RoomPoint(x: 0.5, y: 0.9), RoomPoint(x: 0.32, y: 0.86), RoomPoint(x: 0.68, y: 0.88),
        RoomPoint(x: 0.42, y: 0.78), RoomPoint(x: 0.6, y: 0.8),
    ]
    /// 窗户正下方：背对你坐着看窗外
    public static let windowSpot = RoomPoint(x: 0.5, y: 0.7)
    /// 猫在地板上能到的范围（脚底中点）
    static let catFloorX = 0.12...0.88
    static let catFloorY = 0.7...0.97

    /// 窗户照进来的阳光落在地板上的位置，随时间从右往左移；没有太阳时为 nil。界面在这里画光斑。
    public static func sunbeam(at date: Date, calendar: Calendar) -> RoomPoint? {
        sunbeam(sceneHour: CatWorld.clockHour(date, calendar: calendar))
    }

    /// 同上，按画面钟点（`CatWorld.sceneHour`）。
    public static func sunbeam(sceneHour hours: Double) -> RoomPoint? {
        let sun = LifeSchedule.sunHours
        guard sun.contains(hours) else { return nil }
        let t = (hours - sun.lowerBound) / (sun.upperBound - sun.lowerBound)
        return RoomPoint(x: 0.7 - 0.4 * t, y: 0.84)
    }

    /// 猫在房间里画的前后顺序：家具从后往前，有前半部分的家具紧跟着画前半部分，猫插在它该在的位置。
    public static func layers(_ placed: [PlacedFurniture], catalog: Catalog, cat: CatDepth?) -> [RoomLayer] {
        var result: [RoomLayer] = []
        var catDrawn = cat == nil
        for item in drawOrder(placed, catalog: catalog) {
            let placement = catalog.item(item.catalogID)?.placement
            if !catDrawn, case let .floor(y) = cat, placement?.zone == .floor, item.position.y > y {
                result.append(.cat)
                catDrawn = true
            }
            result.append(.furniture(item))
            let hasFront = placement?.hasFront ?? false
            switch cat {
            case let .inside(id)? where id == item.itemID:
                result.append(.cat)
                catDrawn = true
                if hasFront { result.append(.furnitureFront(item)) }
            case let .on(id)? where id == item.itemID:
                if hasFront { result.append(.furnitureFront(item)) }
                result.append(.cat)
                catDrawn = true
            default:
                if hasFront { result.append(.furnitureFront(item)) }
            }
        }
        if !catDrawn { result.append(.cat) }
        return result
    }
}

/// 房间里从后往前画的一层。
public enum RoomLayer: Hashable, Sendable {
    /// 一件家具（有前半部分的家具，这里只画后半部分）
    case furniture(PlacedFurniture)
    /// 家具的前半部分（`<图名>-front`）
    case furnitureFront(PlacedFurniture)
    case cat
}

// MARK: - 算出此刻的样子

extension CatWorld {
    /// 此刻布丁在房间里的样子。白天待机时按作息算；夜里睡觉 / 睡前在床上；其他状态用专门的画站在默认位置。
    public func presence(at date: Date) -> CatPresence {
        let beat = Self.index(of: date, step: LifeSchedule.beat)
        let nextChange = Date(timeIntervalSinceReferenceDate: Double(beat + 1) * LifeSchedule.beat)
        switch state.cat.state {
        case .idleDaytime:
            return lifePresence(at: date, beat: beat, nextChange: nextChange)
        case .sleepingAtNight, .purringAtBedtime:
            let pose: CatPose = state.cat.state == .purringAtBedtime ? .purr : .curl
            let bed = bedSpot(day: catConfig.logicalDay(of: date))
            return CatPresence(activity: nil, pose: pose, spot: bed.point, depth: bed.depth,
                               fidget: fidget(for: pose, beat: beat), nextChange: nextChange)
        case .wakingUp, .givingGift, .makingMischief, .accompanying:
            let home = RoomGeometry.catHome
            return CatPresence(activity: nil, pose: .stateArt, spot: home, depth: .floor(home.y), nextChange: nextChange)
        }
    }

    /// 这个时刻属于哪个时段。
    public func lifeSlot(at date: Date) -> LifeSlot {
        let day = catConfig.logicalDay(of: date)
        let wake = wakeTime(day: day)
        let hour = { (h: Int) in self.catConfig.date(TimeOfDay(h), in: day) }
        let bed = catConfig.date(catConfig.bedtime, in: day)
        // 每个分界点都不早于前一个：起得晚的话，上午、午睡往后推
        let morningEnd = wake.addingTimeInterval(90 * 60)
        let noon = max(hour(12), morningEnd)
        let afternoon = max(hour(15), noon)
        let evening = max(hour(18), afternoon)
        let late = max(bed.addingTimeInterval(-3600), evening)
        switch date {
        case ..<wake: return .early
        case ..<morningEnd: return .morning
        case ..<noon: return .forenoon
        case ..<afternoon: return .noon
        case ..<evening: return .afternoon
        case ..<late: return .evening
        default: return .late
        }
    }

    /// 当天第一个闹钟的时间（中午以前的才算起床闹钟），没有就是 `LifeSchedule.defaultWake`。
    func wakeTime(day: LogicalDay) -> Date {
        let dayStart = catConfig.date(catConfig.dayStart, in: day)
        let noon = catConfig.date(TimeOfDay(12), in: day)
        if let alarm = AlarmSchedule.nextFire(of: state.alarms, after: dayStart, calendar: catConfig.calendar), alarm < noon {
            return alarm
        }
        return catConfig.date(LifeSchedule.defaultWake, in: day)
    }

    /// 白天待机：先算这一段在做什么，再算位置、姿势和这一拍的小动作。
    /// 某个过去的时刻她在哪、在做什么（"你不在的时候"用，不看现在的状态机）
    func lifePresenceForAway(at date: Date) -> CatPresence {
        let beat = Self.index(of: date, step: LifeSchedule.beat)
        return lifePresence(at: date, beat: beat, nextChange: date.addingTimeInterval(LifeSchedule.beat))
    }

    private func lifePresence(at date: Date, beat: Int, nextChange: Date) -> CatPresence {
        let block = Self.index(of: date, step: LifeSchedule.block)
        let candidates = spotCandidates()
        let activity = activity(atBlock: block, date: date, candidates: candidates)

        var rng = SeededRandom(seed: Self.mix(catSeed, UInt64(bitPattern: Int64(block)), 0x5350_4F54))
        var spot: SpotCandidate
        switch activity {
        case .explore, .play:
            // 每一拍换一个地方
            var beatRng = SeededRandom(seed: Self.mix(catSeed, UInt64(bitPattern: Int64(beat)), 0x5741_4E44))
            let furnitureSpots = candidates.values.joined().filter { $0.depth.isFloor && $0.itemID != nil }
            if activity == .explore, !furnitureSpots.isEmpty, Self.unit(&beatRng) < 0.5 {
                spot = Self.pick(Array(furnitureSpots), rng: &beatRng)
            } else {
                spot = SpotCandidate.floor(RoomPoint(
                    x: Self.lerp(RoomGeometry.catFloorX, Self.unit(&beatRng)),
                    y: Self.lerp(RoomGeometry.catFloorY, Self.unit(&beatRng))
                ))
            }
        case .sunbathe:
            spot = Self.pick(sunbathePlaces(at: date, candidates: candidates), rng: &rng)
        default:
            spot = Self.pick(candidates[activity] ?? [SpotCandidate.floor(RoomGeometry.catHome)], rng: &rng)
        }

        var pose = Self.pose(for: activity, perchVariant: rng.next() & 1 == 0)
        var prop: String?
        switch activity {
        case .toy:
            // 玩玩具：每一拍换一种玩法（拨一拨 / 抱着蹬 / 蹲着盯），玩的是你有的某件小东西
            var beatRng = SeededRandom(seed: Self.mix(catSeed, UInt64(bitPattern: Int64(beat)), 0x544F_59))
            pose = [CatPose.bat, .toyKick, .crouch][Int(beatRng.next() % 3)]
            let owned = ownedToys
            prop = owned.isEmpty ? nil : owned[Int(rng.next() % UInt64(owned.count))]
        case .nap where state.bond.stage >= .close && spot.depth.isFloor && rng.next() % 3 == 0:
            pose = .sleepBelly // 很信任你了：肚皮朝天睡
        default:
            break
        }
        if [.stand, .bat, .crouch].contains(pose), case .floor = spot.depth, spot.facing == 0 {
            spot.facing = rng.next() & 1 == 0 ? -1 : 1 // 在地板中间闻东西 / 跑 / 玩：随便朝一边
        }
        return CatPresence(activity: activity, pose: pose, spot: spot.point, depth: spot.depth, facing: spot.facing,
                           fidget: fidget(for: pose, beat: beat), nextChange: nextChange, prop: prop)
    }

    /// 你有的、能当玩具的东西
    var ownedToys: [String] {
        let owned = Set(state.economy.items.map(\.catalogID))
        return LifeSchedule.toys.filter { owned.contains($0) }
    }

    /// 这一段在做什么：从当天开头一段一段往后推，上一段的事有一定概率接着做。
    func activity(atBlock block: Int, date: Date, candidates: [CatActivity: [SpotCandidate]]) -> CatActivity {
        let day = catConfig.logicalDay(of: date)
        let dayStart = catConfig.date(catConfig.dayStart, in: day)
        let first = Self.index(of: dayStart, step: LifeSchedule.block)
        var previous: CatActivity?
        for b in max(first, block - 120)...block {
            let start = max(Date(timeIntervalSinceReferenceDate: Double(b) * LifeSchedule.block), dayStart)
            let weights = availableWeights(at: start, candidates: candidates)
            var rng = SeededRandom(seed: Self.mix(catSeed, UInt64(bitPattern: Int64(b)), 0x4143_5459))
            if let previous, (weights[previous] ?? 0) > 0, Self.unit(&rng) < LifeSchedule.stay(previous) {
                continue
            }
            previous = Self.pickWeighted(weights, rng: &rng) ?? .sit
        }
        return previous ?? .sit
    }

    /// 这个时刻能做的事和权重：要家具的事得有家具，晒太阳得有太阳。
    private func availableWeights(at date: Date, candidates: [CatActivity: [SpotCandidate]]) -> [CatActivity: Double] {
        let slot = lifeSlot(at: date)
        var base = LifeSchedule.weights[slot] ?? [:]
        for (activity, weight) in LifeSchedule.extraWeights[slot] ?? [:] {
            let allowed = switch activity {
            case .toy: !ownedToys.isEmpty && state.bond.stage >= .curious
            case .bellyUp: state.bond.stage >= .close
            case .knead: state.bond.stage >= .familiar
            default: true
            }
            if allowed { base[activity] = weight }
        }
        if state.bond.stage == .newcomer {
            // 刚到家：更爱躲起来、远远地看，不太自己玩
            for (activity, factor) in [(CatActivity.hide, 3.0), (.watch, 1.5), (.play, 0.5), (.explore, 0.5)] {
                base[activity] = (base[activity] ?? 0) * factor + (activity == .hide ? 1 : 0)
            }
        }
        // 每种猫爱做的事不一样（暹罗爱到处跑，长毛猫爱趴着、舔毛）
        for (activity, factor) in temperament.activities {
            if let weight = base[activity] { base[activity] = weight * factor }
        }
        // 下雨下雪：没有太阳可晒，更爱看窗外、睡觉
        if weather(at: date).isFalling {
            for (activity, factor) in WeatherRules.fallingActivities {
                if let weight = base[activity] { base[activity] = weight * factor }
            }
        }
        let sunny = sunbeam(at: date) != nil
        return base.filter { activity, weight in
            guard weight > 0 else { return false }
            switch activity {
            case .sunbathe: return sunny
            case .explore, .play, .toy: return true
            default: return !(candidates[activity] ?? []).isEmpty
            }
        }
    }

    /// 每件事能去的地方：家具上标出的位置，加上不用家具也能去的地板位置。
    func spotCandidates() -> [CatActivity: [SpotCandidate]] {
        var result: [CatActivity: [SpotCandidate]] = [:]
        for item in state.room.placed {
            guard let placement = economy.catalog.item(item.catalogID)?.placement else { continue }
            for spot in placement.spots ?? [] {
                let candidate = SpotCandidate(item: item, spot: spot, zone: placement.zone)
                for use in spot.uses {
                    guard let activity = CatActivity(rawValue: use.rawValue) else { continue }
                    result[activity, default: []].append(candidate)
                }
            }
        }
        // 刚到家时只待在房间后面（离你远一点）
        let rest = state.bond.stage == .newcomer ? RoomGeometry.restPoints.filter { $0.y <= 0.82 } : RoomGeometry.restPoints
        for activity in [CatActivity.sit, .loaf, .groom] {
            result[activity, default: []] += rest.map { SpotCandidate.floor($0, weight: 0.6) }
        }
        result[.nap, default: []] += RoomGeometry.restPoints.prefix(3).map { SpotCandidate.floor($0, weight: 0.3) }
        result[.watch, default: []].append(SpotCandidate.floor(RoomGeometry.windowSpot))
        // 露肚皮：就在你面前；踩奶：在软的地方（能睡觉的家具上、地毯上），没有就在地板上
        result[.bellyUp] = RoomGeometry.restPoints.filter { $0.y >= 0.85 }.map { SpotCandidate.floor($0) }
        result[.knead] = (result[.nap] ?? []).filter { $0.itemID != nil } + [SpotCandidate.floor(RoomGeometry.catHome, weight: 0.4)]
        return result
    }

    /// 晒太阳的地方：地板上的光斑，或者家具上标了能晒太阳的位置（比如窗边吊床）。
    private func sunbathePlaces(at date: Date, candidates: [CatActivity: [SpotCandidate]]) -> [SpotCandidate] {
        var places = candidates[.sunbathe] ?? []
        if let beam = sunbeam(at: date) {
            places.append(SpotCandidate.floor(beam, weight: 2))
        }
        return places.isEmpty ? [SpotCandidate.floor(RoomGeometry.catHome)] : places
    }

    /// 夜里睡觉、睡前打呼噜的地方：最舒服的床；一样舒服的按日期轮流。
    func bedSpot(day: LogicalDay) -> SpotCandidate {
        let beds = spotCandidates()[.nap] ?? []
        guard let best = beds.map(\.weight).max() else { return SpotCandidate.floor(RoomGeometry.catHome) }
        let top = beds.filter { $0.weight == best }
        let seed = Self.mix(catSeed, UInt64(day.year * 10000 + day.month * 100 + day.day), 0x4245_44)
        return top[Int(seed % UInt64(top.count))]
    }

    private func fidget(for pose: CatPose, beat: Int) -> CatFidget {
        let options = LifeSchedule.fidgets(for: pose)
        guard !options.isEmpty else { return .none }
        var rng = SeededRandom(seed: Self.mix(catSeed, UInt64(bitPattern: Int64(beat)), 0x4649_4447))
        guard Self.unit(&rng) < temperament.fidgetChance else { return .none }
        return options[Int(rng.next() % UInt64(options.count))]
    }

    static func pose(for activity: CatActivity, perchVariant: Bool) -> CatPose {
        switch activity {
        case .sit: .sit
        case .loaf, .hide: .loaf
        case .groom: .groom
        case .nap: .curl
        case .sunbathe: .sprawl
        case .watch: .sitBack
        case .eat, .drink: .eat
        case .scratch: .stretch
        case .perch: perchVariant ? .loaf : .sit
        case .explore, .play: .stand
        case .toy: .bat
        case .bellyUp: .bellyUp
        case .knead: .knead
        }
    }

    // MARK: 随机数（全部由种子算出，可复现）

    static func index(of date: Date, step: TimeInterval) -> Int {
        Int((date.timeIntervalSinceReferenceDate / step).rounded(.down))
    }

    static func mix(_ a: UInt64, _ b: UInt64, _ c: UInt64) -> UInt64 {
        var z = a ^ (b &* 0x9E37_79B9_7F4A_7C15) ^ (c &* 0xD6E8_FEB8_6659_FD93)
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    static func unit(_ rng: inout SeededRandom) -> Double {
        Double(rng.next() >> 11) * 0x1p-53
    }

    static func lerp(_ range: ClosedRange<Double>, _ t: Double) -> Double {
        range.lowerBound + (range.upperBound - range.lowerBound) * t
    }

    static func pickWeighted(_ weights: [CatActivity: Double], rng: inout SeededRandom) -> CatActivity? {
        // 按固定顺序遍历，保证同一个种子在不同平台上结果一样
        let entries = CatActivity.allCases.compactMap { a in weights[a].map { (a, $0) } }
        let total = entries.reduce(0) { $0 + $1.1 }
        guard total > 0 else { return nil }
        var roll = unit(&rng) * total
        for (activity, weight) in entries {
            roll -= weight
            if roll < 0 { return activity }
        }
        return entries.last?.0
    }

    static func pick(_ candidates: [SpotCandidate], rng: inout SeededRandom) -> SpotCandidate {
        let total = candidates.reduce(0) { $0 + $1.weight }
        var roll = unit(&rng) * total
        for candidate in candidates {
            roll -= candidate.weight
            if roll < 0 { return candidate }
        }
        return candidates.last ?? SpotCandidate.floor(RoomGeometry.catHome)
    }
}

/// 布丁能去的一个地方。
struct SpotCandidate: Hashable, Sendable {
    var point: RoomPoint
    var depth: CatDepth
    var itemID: Int?
    var facing: Int
    var weight: Double

    static func floor(_ point: RoomPoint, weight: Double = 1) -> SpotCandidate {
        SpotCandidate(point: point, depth: .floor(point.y), itemID: nil, facing: 0, weight: weight)
    }

    init(point: RoomPoint, depth: CatDepth, itemID: Int?, facing: Int, weight: Double) {
        self.point = point
        self.depth = depth
        self.itemID = itemID
        self.facing = facing
        self.weight = weight
    }

    /// 家具上标出的位置 → 房间里的绝对位置。旁边地板上的位置限制在猫能到的范围里，并且面朝家具。
    init(item: PlacedFurniture, spot: FurnitureSpot, zone: RoomZone) {
        var point = RoomPoint(x: item.position.x + spot.dx, y: item.position.y + spot.dy)
        itemID = item.itemID
        weight = spot.weight ?? 1
        switch spot.layer {
        case .floor:
            point = RoomPoint(x: point.x.clamped(to: RoomGeometry.catFloorX), y: point.y.clamped(to: RoomGeometry.catFloorY))
            depth = .floor(point.y)
            facing = spot.dx > 0.001 ? -1 : (spot.dx < -0.001 ? 1 : 0)
        case .on:
            depth = .on(itemID: item.itemID)
            facing = 0
        case .inside:
            depth = .inside(itemID: item.itemID)
            facing = 0
        }
        self.point = point
    }
}

extension CatDepth {
    var isFloor: Bool {
        if case .floor = self { true } else { false }
    }
}
