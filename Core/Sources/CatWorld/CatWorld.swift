import CatEngine
import Economy
import Foundation

/// 写进事件日志的一条事件。`id` 由产生事件的一方生成（App Intent、App 自己），
/// 用来保证同一条事件只处理一次。
public struct LoggedEvent: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var event: CatEvent

    public init(id: String, event: CatEvent) {
        self.id = id
        self.event = event
    }
}

/// 付费墙的触发时机（计划书第 7 节）。第 3 个时机"点击付费内容"由 App 在遇到 `requiresPlus` 时直接处理。
public enum PaywallMoment: String, Codable, Sendable, CaseIterable {
    /// 新手引导结束后展示一次
    case onboardingFinished
    /// 第一次准时起床、猫送礼物的那一刻
    case firstOnTimeGift
}

/// 需要 App 弹出的东西。
public enum WorldPrompt: Hashable, Sendable {
    case paywall(PaywallMoment)
    /// 第 3 次准时起床后请求评分（计划书第 10 节）
    case requestReview
}

public struct Milestones: Codable, Hashable, Sendable {
    public internal(set) var onTimeWakes = 0
    public internal(set) var shownPaywalls: Set<PaywallMoment> = []
    public internal(set) var reviewRequested = false
    public internal(set) var onboardingCompletedAt: Date?
}

/// 整个世界的状态：猫、钱包和物品、随机数、闹钟、每日记录、里程碑、房间布局。
/// 是一个 Codable 值，App 整体保存、整体读取，所以"处理事件 + 发奖励 + 标记已处理"是原子的。
///
/// 新增字段时一定要给默认值，并在 `init(from:)` 里用 `decodeIfPresent`：
/// App 读不出旧存档时会当成新用户，猫和小鱼干就没了。
public struct WorldState: Codable, Hashable, Sendable {
    public internal(set) var cat: CatSnapshot
    public internal(set) var economy: EconomyState
    public internal(set) var rng: SeededRandom
    public internal(set) var alarms: [AlarmConfig] = []
    public internal(set) var dayLogs: [LogicalDay: DayLog] = [:]
    public internal(set) var milestones = Milestones()
    public internal(set) var room = RoomLayout()
    /// 已处理的事件 id → 事件时间。超过保留期的会被清掉
    var processedEventIDs: [String: Date] = [:]
    /// 台词用单独的随机数，不影响掉落
    var dialogueRng = SeededRandom(seed: 0x5055_4444_494E_47)
    var lastLines: [CatScene: String] = [:]
    var lastForegroundAt: Date?
    /// 布丁日常作息的种子（`Life.swift`）。和掉落用的随机数分开，作息不会因为开了礼物而改变
    var lifeSeed: UInt64 = 0x4C49_4645
    /// 隐藏好感度、性格、回忆册（`Bond.swift`）
    public internal(set) var bond = BondState.newCat(seed: 0x4C49_4645)
    /// 现在陪着你的是哪只猫（`bond` 是她的好感度）
    public internal(set) var activeCat = CatKind.pudding
    /// 领养过的猫，按领养的先后
    public internal(set) var adoptedCats: [CatKind] = [.pudding]
    /// 不在房间里的那些猫的好感度（换猫时和 `bond` 对调）
    var restingBonds: [CatKind: BondState] = [:]
    /// 窗外跟着用户那里：大概的位置、真实天气（`Sky.swift`）。没打开时是空的
    public internal(set) var sky = SkyState()
}

extension WorldState {
    /// 只有猫、钱包、随机数是必需的；其他字段在旧存档里没有时用默认值。
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cat = try c.decode(CatSnapshot.self, forKey: .cat)
        economy = try c.decode(EconomyState.self, forKey: .economy)
        rng = try c.decode(SeededRandom.self, forKey: .rng)
        alarms = try c.decodeIfPresent([AlarmConfig].self, forKey: .alarms) ?? []
        dayLogs = try c.decodeIfPresent([LogicalDay: DayLog].self, forKey: .dayLogs) ?? [:]
        milestones = try c.decodeIfPresent(Milestones.self, forKey: .milestones) ?? Milestones()
        room = try c.decodeIfPresent(RoomLayout.self, forKey: .room) ?? RoomLayout()
        processedEventIDs = try c.decodeIfPresent([String: Date].self, forKey: .processedEventIDs) ?? [:]
        dialogueRng = try c.decodeIfPresent(SeededRandom.self, forKey: .dialogueRng) ?? SeededRandom(seed: 0x5055_4444_494E_47)
        // 旧存档里可能记着已经删掉的场景（以前她会说话）：不认识的就丢掉，不能让整个存档读不出来
        let savedLines = (try? c.decodeIfPresent([String: String].self, forKey: .lastLines)) ?? [:]
        lastLines = Dictionary(uniqueKeysWithValues: savedLines.compactMap { key, value in
            CatScene(rawValue: key).map { ($0, value) }
        })
        lastForegroundAt = try c.decodeIfPresent(Date.self, forKey: .lastForegroundAt)
        // 旧存档没有作息种子：从掉落随机数推一个，下次保存后就固定了
        lifeSeed = try c.decodeIfPresent(UInt64.self, forKey: .lifeSeed) ?? (rng.state ^ 0x4C49_4645_5345_4544)
        bond = try c.decodeIfPresent(BondState.self, forKey: .bond) ?? BondState.newCat(seed: lifeSeed)
        activeCat = try c.decodeIfPresent(CatKind.self, forKey: .activeCat) ?? .pudding
        adoptedCats = try c.decodeIfPresent([CatKind].self, forKey: .adoptedCats) ?? [.pudding]
        restingBonds = try c.decodeIfPresent([CatKind: BondState].self, forKey: .restingBonds) ?? [:]
        sky = try c.decodeIfPresent(SkyState.self, forKey: .sky) ?? SkyState()
    }
}

/// 一次调用的结果。
public struct WorldUpdate: Hashable, Sendable {
    /// CatEngine 的原始输出（转换、奖励、副作用）
    public var outputs: [CatOutput] = []
    /// 实际发放的小鱼干和物品
    public var grants: [Grant] = []
    public var prompts: [WorldPrompt] = []
    /// 因为已经处理过或太旧而跳过的事件数
    public var skippedEvents = 0
    /// 不该发生的问题（例如目录里缺了掉落表），App 可以上报到崩溃 / 分析工具
    public var issues: [String] = []
    /// 这次更新里布丁的反应
    public var scene: CatScene?
    /// 要显示的台词（Localizable.xcstrings 的 key）
    public var line: String?
    /// 这次更新里好感度的变化（每天第一次打开、准时起床、睡前模式……）
    public var bond = BondUpdate()
    /// 你不在的时候她做了什么（离开一小时以上再打开 App 时才有）
    public var away: AwayReport?

    /// App 需要执行的副作用（播放 / 停止呼噜声、加乱子、提示睡前模式……）。
    public var effects: [CatEffect] {
        outputs.compactMap { if case let .effect(effect) = $0 { effect } else { nil } }
    }

    /// 发生的状态转换。
    public var transitions: [TransitionID] {
        outputs.compactMap { if case let .transition(id, _, _, _) = $0 { id } else { nil } }
    }
}

public enum WorldError: Error, Hashable, Sendable {
    /// 免费用户只能开 1 个闹钟
    case alarmLimitReached(limit: Int)
    case unknownAlarm(String)
    /// 没有这件物品，或者它不是能摆进房间的家具
    case notPlaceable(itemID: Int)
    /// 这件家具现在不在房间里（收起来了）
    case notInRoom(itemID: Int)
    /// 这只猫还没领养 / 还不能领养（好感不够）
    case catNotAvailable(CatKind)
}

/// App 调用 Core 的唯一入口：把 CatEngine、Economy、闹钟排程和每日记录串起来。
///
/// 用法：
/// 1. App Intent（锁屏上停止 / 贪睡）和 App 自己把事件追加到日志
/// 2. App 回到前台时调用 `ingest(日志)`，再调用 `foreground(at:)`
/// 3. 保存 `state`；执行 `update.effects`、展示 `update.grants` 和 `update.prompts`
///
/// 同一条事件提交多次只会处理一次，所以日志可以整份重复提交。
public struct CatWorld: Sendable {
    public let catConfig: CatEngineConfig
    public let economy: EconomyEngine
    public internal(set) var state: WorldState
    /// 已处理事件 id 的保留时长；比这更旧的未知事件被当作过期丢弃
    public var eventRetention: TimeInterval = 14 * 24 * 3600

    public init(state: WorldState, catConfig: CatEngineConfig, economy: EconomyEngine) {
        self.state = state
        self.catConfig = catConfig
        self.economy = economy
    }

    /// 新用户：猫在白天待机，默认毛色，0 小鱼干。
    public static func newPlayer(at date: Date, seed: UInt64, catConfig: CatEngineConfig, economy: EconomyEngine) -> CatWorld {
        let state = WorldState(
            cat: CatSnapshot(state: .idleDaytime, at: date),
            economy: .newPlayer(catalog: economy.catalog, at: date),
            rng: SeededRandom(seed: seed),
            dialogueRng: SeededRandom(seed: ~seed),
            lifeSeed: seed ^ 0x4C49_4645_5345_4544,
            bond: BondState.newCat(seed: seed)
        )
        return CatWorld(state: state, catConfig: catConfig, economy: economy)
    }

    // MARK: 事件

    /// 处理一批事件。已经处理过的 id、同一批里重复的 id、比保留期更旧的事件都会被跳过。
    @discardableResult
    public mutating func ingest(_ events: [LoggedEvent], isPlus: Bool) -> WorldUpdate {
        var update = WorldUpdate()
        let horizon = state.cat.updatedAt.addingTimeInterval(-eventRetention)
        var seen = Set<String>()
        let fresh = events.enumerated().filter { _, logged in
            guard state.processedEventIDs[logged.id] == nil, logged.event.at >= horizon, seen.insert(logged.id).inserted else {
                update.skippedEvents += 1
                return false
            }
            return true
        }
        let ordered = fresh.sorted { ($0.element.event.at, $0.offset) < ($1.element.event.at, $1.offset) }.map(\.element)
        for logged in ordered {
            process(logged.event, isPlus: isPlus, into: &update)
            state.processedEventIDs[logged.id] = logged.event.at
        }
        pruneProcessedIDs()
        if let latest = ordered.last?.event.at {
            attachLine(to: &update, now: latest)
        }
        return update
    }

    /// App 回到前台：先处理"打开了 App"，再按闹钟排程跑一次 tick。
    @discardableResult
    public mutating func foreground(at date: Date, isPlus: Bool) -> WorldUpdate {
        var update = WorldUpdate()
        let wasAway = state.lastForegroundAt.map { date.timeIntervalSince($0) >= Self.returnedAfter } ?? false
        let previous = state.lastForegroundAt
        state.lastForegroundAt = date
        process(.appForegrounded(at: date), isPlus: isPlus, into: &update)
        update.bond.merge(addBond(.dailyVisit, at: date))
        process(.tick(at: date, nextAlarmAt: nextAlarmAt(after: date)), isPlus: isPlus, into: &update)
        attachLine(to: &update, now: date, fallback: wasAway ? .returned : nil)
        if let previous { update.away = awayReport(from: previous, to: date) }
        return update
    }

    /// 后台刷新、小组件时间线等只需要推进时间的场合。
    @discardableResult
    public mutating func tick(at date: Date, isPlus: Bool) -> WorldUpdate {
        var update = WorldUpdate()
        process(.tick(at: date, nextAlarmAt: nextAlarmAt(after: date)), isPlus: isPlus, into: &update)
        return update
    }

    private mutating func process(_ event: CatEvent, isPlus: Bool, into update: inout WorldUpdate) {
        // 她想让你早点睡：要在进入睡前状态之前判断
        if case .bedtimeTimerStarted = event { update.bond.merge(bedtimeStarted(at: event.at)) }
        var machine = CatMachine(config: catConfig, snapshot: state.cat)
        let outputs = machine.handle(event)
        state.cat = machine.snapshot
        update.outputs += outputs

        if case let .alarmFired(alarmID, _) = event,
           let index = state.alarms.firstIndex(where: { $0.id == alarmID }), state.alarms[index].isOneShot {
            state.alarms[index].isEnabled = false // 一次性闹钟响过就关掉
        }

        for output in outputs {
            switch output {
            case let .reward(reward):
                grant(reward, at: event.at, isPlus: isPlus, into: &update)
            case let .effect(effect):
                record(effect)
                if case .sleepRecorded = effect { update.bond.merge(addBond(.bedtime, at: event.at)) }
            case .transition:
                break
            }
        }
    }

    private mutating func grant(_ reward: CatReward, at date: Date, isPlus: Bool, into update: inout WorldUpdate) {
        var economyState = state.economy
        var rng = state.rng
        do {
            update.grants.append(try economy.grant(reward, isPlus: isPlus, at: date, state: &economyState, rng: &rng))
            state.economy = economyState
            state.rng = rng
        } catch {
            update.issues.append("发放 \(reward) 失败：\(error)")
        }

        guard case .wakeGift = reward else { return }
        update.bond.merge(addBond(.onTimeWake, at: date))
        remember(.firstGift, at: date, into: &update.bond)
        state.milestones.onTimeWakes += 1
        if state.milestones.onTimeWakes == 1, !isPlus, state.milestones.shownPaywalls.insert(.firstOnTimeGift).inserted {
            update.prompts.append(.paywall(.firstOnTimeGift))
        }
        if state.milestones.onTimeWakes >= 3, !state.milestones.reviewRequested {
            state.milestones.reviewRequested = true
            update.prompts.append(.requestReview)
        }
    }

    private mutating func record(_ effect: CatEffect) {
        switch effect {
        case let .wakeRecorded(onTime, snoozeCount, day):
            modifyLog(day) {
                $0.wokeOnTime = onTime
                $0.snoozeCount = snoozeCount
            }
        case let .sleepRecorded(at, day):
            modifyLog(day) { $0.sleptAt = at }
        case let .sessionRecorded(activity, start, end, completed):
            let minutes = max(0, Int(end.timeIntervalSince(start) / 60))
            modifyLog(catConfig.logicalDay(of: start)) {
                switch activity {
                case .focus where completed:
                    $0.focusMinutes += minutes
                    $0.completedFocusSessions += 1
                case .read:
                    $0.readingMinutes += minutes
                case .focus, .move:
                    break
                }
            }
        case .messAdded, .startBedtimeAudio, .stopBedtimeAudio, .promptBedtime:
            break // 由 App 执行
        }
    }

    private mutating func modifyLog(_ day: LogicalDay, _ change: (inout DayLog) -> Void) {
        var log = state.dayLogs[day] ?? DayLog(day: day)
        change(&log)
        state.dayLogs[day] = log
    }

    private mutating func pruneProcessedIDs() {
        let horizon = state.cat.updatedAt.addingTimeInterval(-eventRetention)
        state.processedEventIDs = state.processedEventIDs.filter { $0.value >= horizon }
    }

    // MARK: 闹钟

    /// 下一个会响的闹钟。
    public func nextAlarmAt(after date: Date) -> Date? {
        AlarmSchedule.nextFire(of: state.alarms, after: date, calendar: catConfig.calendar)
    }

    /// 新增或修改闹钟。免费用户最多同时开 1 个。
    public mutating func setAlarm(_ alarm: AlarmConfig, isPlus: Bool) throws {
        if alarm.isEnabled, let limit = AlarmPolicy.limit(isPlus: isPlus) {
            let others = state.alarms.filter { $0.id != alarm.id && $0.isEnabled }.count
            if others >= limit { throw WorldError.alarmLimitReached(limit: limit) }
        }
        if let index = state.alarms.firstIndex(where: { $0.id == alarm.id }) {
            state.alarms[index] = alarm
        } else {
            state.alarms.append(alarm)
        }
    }

    public mutating func removeAlarm(id: String) throws {
        guard let index = state.alarms.firstIndex(where: { $0.id == id }) else { throw WorldError.unknownAlarm(id) }
        state.alarms.remove(at: index)
    }

    /// Plus 到期后调用：只保留最快会响的那个闹钟，其余关掉（不删除，重新订阅后可以再打开）。
    /// 返回被关掉的闹钟 id，App 据此取消对应的 AlarmKit 闹钟。
    @discardableResult
    public mutating func enforceAlarmLimit(isPlus: Bool, now: Date) -> [String] {
        guard let limit = AlarmPolicy.limit(isPlus: isPlus) else { return [] }
        let calendar = catConfig.calendar
        let enabled = state.alarms.filter(\.isEnabled).sorted {
            let a = AlarmSchedule.nextFire(of: $0, after: now, calendar: calendar) ?? .distantFuture
            let b = AlarmSchedule.nextFire(of: $1, after: now, calendar: calendar) ?? .distantFuture
            return (a, $0.id) < (b, $1.id)
        }
        let toDisable = Set(enabled.dropFirst(limit).map(\.id))
        for index in state.alarms.indices where toDisable.contains(state.alarms[index].id) {
            state.alarms[index].isEnabled = false
        }
        return enabled.dropFirst(limit).map(\.id)
    }

    // MARK: 其他

    /// 新手引导结束。免费用户展示一次付费墙（可关闭）。
    public mutating func completeOnboarding(at date: Date, isPlus: Bool) -> [WorldPrompt] {
        guard state.milestones.onboardingCompletedAt == nil else { return [] }
        state.milestones.onboardingCompletedAt = date
        guard !isPlus, state.milestones.shownPaywalls.insert(.onboardingFinished).inserted else { return [] }
        return [.paywall(.onboardingFinished)]
    }

    /// 写入 HealthKit 步数（V1.2）。步数达标的奖励仍然走 `stepGoalReached` 事件。
    public mutating func recordSteps(_ steps: Int, on day: LogicalDay) {
        modifyLog(day) { $0.steps = steps }
    }

    /// 在商店买家具。买到的家具直接摆在它的默认位置（`FurniturePlacement`）。
    @discardableResult
    public mutating func buy(_ catalogID: String, isPlus: Bool, at date: Date) throws -> OwnedItem {
        var economyState = state.economy
        let item = try economy.buy(catalogID, isPlus: isPlus, at: date, state: &economyState)
        state.economy = economyState
        if economy.catalog.item(catalogID)?.placement != nil {
            _ = try? placeFurniture(itemID: item.id, at: nil, date: date) // 刚买到、目录里有位置，不会失败
        }
        return item
    }

    /// 卖掉一件礼物。
    @discardableResult
    public mutating func sell(itemID: Int) throws -> Int {
        var economyState = state.economy
        let fish = try economy.sell(itemID: itemID, state: &economyState)
        state.economy = economyState
        return fish
    }

    /// 收拾掉房间里的一个乱子。
    @discardableResult
    public mutating func clearMess(at date: Date, isPlus: Bool) -> WorldUpdate {
        var update = WorldUpdate()
        process(.messCleared(at: date), isPlus: isPlus, into: &update)
        update.scene = .messCleared
        update.line = line(for: .messCleared)
        return update
    }
}
