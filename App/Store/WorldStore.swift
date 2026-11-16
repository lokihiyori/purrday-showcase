import CatEngine
import CatWorld
import Economy
import Foundation
import Observation

/// App 里唯一持有 `CatWorld` 的对象。界面只通过它读写状态，用法见 docs/app-integration.md。
@MainActor
@Observable
final class WorldStore {
    private(set) var world: CatWorld
    /// 布丁现在说的话（Localizable.xcstrings 的 key）
    var bubble: String?
    /// 待展示的奖励（早餐礼物弹窗）
    var pendingGrants: [Grant] = []
    /// 待处理的付费墙 / 评分请求
    var pendingPrompts: [WorldPrompt] = []
    /// 界面上点到了 Plus 专属内容，需要弹付费墙
    var paywallRequested = false
    /// 点猫后短暂显示"被摸"姿势
    private(set) var isBeingPetted = false
    /// 最近一次点猫的时间（画面上的小爱心从这时候开始飘）
    private(set) var pettedAt: Date?
    /// 最近一次更新产生的副作用；`effectsVersion` 每次加一，界面据此执行（音频等）
    private(set) var lastEffects: [CatEffect] = []
    private(set) var effectsVersion = 0
    private(set) var lastError: String?
    /// 正在响的系统闹钟（AlarmKit 的 id，UUID 字符串）
    private(set) var ringingAlarmID: String?
    /// 布丁正走过去看的家具（刚买 / 刚摆出来的）。只在这次打开 App 期间有效，不保存
    private(set) var catFocusItemID: Int?
    /// 看新家具看到什么时候，之后接着过她自己的日子
    private(set) var catFocusUntil: Date?
    /// 看新家具看多久
    static let focusDuration: TimeInterval = 40
    /// 刚领养完：先坐在前面看着你，过一会儿再去过自己的日子
    private(set) var greetingUntil: Date?
    static let greetingDuration: TimeInterval = 60
    /// 刚在商店买了家具：回到房间时保留"新家具"那句台词，不被随口一句盖掉
    private var keepBubbleOnRoomAppear = false

    // MARK: 互动（好感度，docs/cat-life.md 第 2 节）。都只在这次打开 App 期间有效，不保存

    /// 最近一次摸她的反应（画面上的爱心、"……"、生气符号从这时候开始）
    private(set) var lastPet: PetMoment?
    /// 呼噜震动：每加一就轻轻震一下
    private(set) var purrTicks = 0
    /// 她正在演的反应（蹭你、翻肚皮、踩奶、扑……），房间按它换姿势和动作
    private(set) var performance: CatPerformance?
    /// 呼噜声放到什么时候（房间据此放 / 停呼噜声）
    private(set) var purrUntil: Date?
    /// 她刚发出的声音；`soundSerial` 每次加一，房间据此放声音
    private(set) var soundCue: CatSound?
    private(set) var soundSerial = 0
    /// 吓一跳 / 被摸到不喜欢的地方：缩一下
    private(set) var flinchAt: Date?
    /// 正在吃零食
    private(set) var treat: TreatMoment?
    /// 正在玩逗猫棒
    private(set) var play: PlaySession?
    /// 你对她慢眨眼
    private(set) var blink: BlinkMoment?
    /// 生气时去哪个角落背对你；嘟囔完（`sulkFrom`）再走过去
    private(set) var sulkSpot: RoomPoint?
    private var sulkFrom: Date?
    /// 她此刻提的小请求（房间里显示成一个想法气泡）
    private(set) var request: CatRequest?
    /// 刚记下的回忆，房间顶上依次弹出小卡片
    private(set) var memoryToasts: [CatMemory] = []
    /// 你不在的时候她做了什么（回来时房间顶上一张小卡片）
    private(set) var awayReport: AwayReport?
    /// 她留在地板上的东西（玩过的玩具）。点一下收起来
    private(set) var trace: RoomTrace?
    /// 开始 / 结束一个互动、逗猫棒换了目标时加一：房间据此马上重新问布丁该在哪
    private(set) var interactionVersion = 0
    /// 上次回到前台的时间（隔了一阵子再打开，熟了的布丁会跑过来迎接）
    private var lastForegroundAt: Date?
    /// 这次迎接已经蹭过你了（跑到面前以后蹭一下 / 叫一声，只做一次）
    private var greeted = true
    /// 你回来了，她不过来，只在原地打个招呼（等房间显示出来再做）
    private var pendingHello = false
    /// 上一次自己叫是哪一拍（一拍只叫一次）
    private var lastCallBeat: Int?
    /// 小鱼干不够买零食的次数（零食按钮据此抖一下）
    private(set) var treatDenied = 0
    static let greetAfter: TimeInterval = 15 * 60
    /// 每次保存后调用（App 用它让小组件重新加载时间线；WorldStore 本身不依赖 WidgetKit）
    var onPersist: (@MainActor () -> Void)?
    /// 当天的画面钟（`sceneHour`）
    @ObservationIgnored private var sceneClockCache: (place: Place, day: Range<Date>, clock: SceneClock)?

    let plus: PlusStatus
    let scheduler: any AlarmScheduling
    private let storage: WorldStorage
    private let log: EventLog

    init(storage: WorldStorage, log: EventLog, plus: PlusStatus, scheduler: any AlarmScheduling,
         catConfig: CatEngineConfig, economy: EconomyEngine, now: Date) {
        self.storage = storage
        self.log = log
        self.plus = plus
        self.scheduler = scheduler
        if let saved = try? storage.load() {
            world = CatWorld(state: saved, catConfig: catConfig, economy: economy)
        } else {
            world = .newPlayer(at: now, seed: UInt64.random(in: 1...UInt64.max), catConfig: catConfig, economy: economy)
        }
    }

    var isPlus: Bool { plus.isPlus }
    var cat: CatSnapshot { world.state.cat }
    /// 此刻布丁在房间里的样子：在玩、在吃零食、在生气时按互动来；刚买了家具就坐在它旁边看；
    /// 否则按她自己的作息（`CatWorld.presence`）。你对她慢眨眼时，她会转过来看你。
    func presence(at date: Date) -> CatPresence {
        if cat.state == .idleDaytime, let interactive = interactivePresence(at: date) { return interactive }
        var base = basePresence(at: date)
        if let from = sulkFrom, date < from { base.nextChange = min(base.nextChange, from) } // 嘟囔完就走开
        if let blink, date < blink.end, cat.state == .idleDaytime, !Self.asleep(base),
           ![.sit, .loaf, .stand].contains(base.pose) {
            var facing = base
            facing.pose = .sit
            facing.facing = 0
            facing.nextChange = min(base.nextChange, blink.end)
            return facing
        }
        return base
    }

    private func basePresence(at date: Date) -> CatPresence {
        if let id = catFocusItemID, let until = catFocusUntil, date < until, cat.state == .idleDaytime,
           world.state.room.furniture(itemID: id) != nil {
            let spot = world.catSpot(beside: id)
            return CatPresence(activity: .sit, pose: .sit, spot: spot, depth: .floor(spot.y), nextChange: until)
        }
        if let until = greetingUntil, date < until, cat.state == .idleDaytime {
            let home = RoomGeometry.catHome
            return CatPresence(activity: .sit, pose: .sit, spot: home, depth: .floor(home.y), nextChange: until)
        }
        return world.presence(at: date)
    }

    private func focus(on itemID: Int, now: Date) {
        catFocusItemID = itemID
        catFocusUntil = now.addingTimeInterval(Self.focusDuration)
    }

    // MARK: 事件

    /// App 回到前台：处理日志里的事件（包括锁屏上的操作），再推进时间。
    /// 熟了以后隔一阵子再打开，她会跑到前面来迎接你。
    func foreground(now: Date) {
        apply(world.ingest(log.readAll(), isPlus: isPlus))
        apply(world.foreground(at: now, isPlus: isPlus))
        let away = lastForegroundAt.map { now.timeIntervalSince($0) } ?? .infinity
        lastForegroundAt = now
        let style = CatStyle.of(world.activeCat)
        if away > style.greetAfter, cat.state == .idleDaytime, !world.isAnnoyed(at: now), (greetingUntil ?? .distantPast) < now {
            if world.bondStage >= world.temperament.greetStage {
                // 跑到面前迎接你（黏人的暹罗刚好奇就来，高冷的长毛猫要到信赖才来）
                greetingUntil = now.addingTimeInterval(style.greetingTime)
                greeted = false
                bubble = nil
            } else if world.bondStage >= .familiar {
                // 认得你了，但不过来：在原地看你一眼、慢慢眨一下眼
                pendingHello = true
            }
        }
        persist()
        try? log.prune(olderThan: now.addingTimeInterval(-world.eventRetention))
    }

    /// 熟了以后迎接你多久
    static let bondGreetingDuration: TimeInterval = 20

    /// App 内产生的事件（摸猫关闹钟、贪睡、领取礼物、开始睡前模式……）。和锁屏来的事件走同一条路。
    func send(_ event: CatEvent) {
        do {
            try log.append(LoggedEvent(id: UUID().uuidString, event: event))
        } catch {
            lastError = "写事件日志失败：\(error)"
        }
        apply(world.ingest(log.readAll(), isPlus: isPlus))
        persist()
    }

    /// 点猫。白天待机时她不说话，用动作回应你（歪头、叫一声、甩尾巴、走过来……，由 `CatWorld.react` 挑）；
    /// 刚到家时会吓一跳；短时间点太多下她会烦，跑到角落背对你一会儿；午睡被点只是动动耳朵。
    /// 其他状态（叫醒、送礼物、睡前……）还是说那个场景的台词。
    func tapCat(now: Date = .now) {
        guard cat.state == .idleDaytime else {
            bubble = world.tapScene().map { world.line(for: $0) }
            persist()
            return
        }
        bubble = nil
        if world.isAnnoyed(at: now) {
            if !performing(at: now) { perform(.tailFlick, now: now) }
            return
        }
        if world.noteTap(at: now) {
            startSulk(now: now)
            persist()
            return
        }
        guard !performing(at: now) else { return }
        // 按画面上的样子判断（刚领养在打招呼、在看新家具时是醒着的），不直接用 Core 的作息
        if Self.asleep(presence(at: now)) {
            perform(.tailFlick, now: now) // 睡着被点：动动耳朵，接着睡
            return
        }
        let reaction = world.react(to: .tap, at: now)
        switch reaction {
        case .scoot, .freeze:
            flinchAt = now
            perform(reaction, now: now)
        case .comeCloser:
            greetingUntil = now.addingTimeInterval(12) // 走到你面前来，到了蹭你一下
            greeted = false
        default:
            squish(now: now)
            perform(reaction, now: now)
        }
        persist()
    }

    private func squish(now: Date) {
        isBeingPetted = true
        pettedAt = now
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if pettedAt == now { isBeingPetted = false }
        }
    }

    /// 打开房间：白天待机时没有旁白（她用动作表达），只保留刚发生的事的那一句（刚买了家具、起床、送礼物……）。
    func sayAmbientLine(now: Date) {
        if keepBubbleOnRoomAppear {
            keepBubbleOnRoomAppear = false
            return
        }
        if cat.state == .idleDaytime { bubble = nil }
    }

    func collectGift(now: Date) {
        pendingGrants.removeAll()
        send(.giftCollected(at: now))
    }

    func clearMess(now: Date) {
        apply(world.clearMess(at: now, isPlus: isPlus))
        persist()
    }

    // MARK: 商店

    func buy(_ catalogID: String, now: Date) throws {
        do {
            let item = try world.buy(catalogID, isPlus: isPlus, at: now)
            bubble = world.line(for: .shopBought)
            if world.state.room.furniture(itemID: item.id) != nil {
                focus(on: item.id, now: now)
                keepBubbleOnRoomAppear = true
            }
            persist()
        } catch EconomyError.requiresPlus {
            paywallRequested = true
            throw EconomyError.requiresPlus(catalogID)
        }
    }

    func sell(itemID: Int) throws {
        try world.sell(itemID: itemID)
        bubble = world.line(for: .giftSold)
        persist()
    }

    // MARK: 布置房间

    /// 把收起来的家具摆回房间（默认位置），布丁走过去看。
    func placeFurniture(itemID: Int, now: Date) throws {
        try world.placeFurniture(itemID: itemID, at: nil, date: now)
        focus(on: itemID, now: now)
        persist()
    }

    /// 拖动家具。位置会被限制在能放的范围里。
    func moveFurniture(itemID: Int, to point: RoomPoint, now: Date) throws {
        try world.moveFurniture(itemID: itemID, to: point, date: now)
        persist()
    }

    func putAway(itemID: Int) throws {
        try world.putAway(itemID: itemID)
        if catFocusItemID == itemID { catFocusItemID = nil }
        persist()
    }

    #if DEBUG
    /// 只在 Debug 版本里有：`-debugFish 200` 启动参数（UI 走查用）。
    func debugGrantFish(_ amount: Int) {
        world.debugGrantFish(amount)
        persist()
    }

    /// 只在 Debug 版本里有：`-debugMornings 1` 启动参数，把过去三周填上示例的起床记录（看日历的样子）。
    func debugFillMornings(now: Date) {
        world.debugFillMornings(until: now)
        persist()
    }

    /// 只在 Debug 版本里有：`-debugBond 600` 启动参数，直接看某个好感阶段的样子。
    func debugSetBond(_ points: Int) {
        world.debugSetBond(points)
        persist()
    }
    #endif

    // MARK: 系统闹钟（AlarmKit）

    /// AlarmKit 的闹钟状态变了（RootView 监听 alarmUpdates 后调用）。
    /// 正在响的闹钟按排程补记响铃事件；顺便处理锁屏上停止 / 贪睡写进日志的事件。
    func alarmsUpdated(alertingIDs: [String], now: Date) {
        for id in alertingIDs {
            for event in world.alarmEvents(.alerting, alarmID: id, at: now) {
                try? log.append(event)
            }
        }
        ringingAlarmID = alertingIDs.first
        apply(world.ingest(log.readAll(), isPlus: isPlus))
        persist()
    }

    /// 在 App 里摸猫 10 下（或喂猫）关掉闹钟。
    func stopRingingAlarm(now: Date) {
        let id = ringingAlarmID
        ringingAlarmID = nil
        send(.alarmStopped(alarmID: id ?? "app", via: .petCat, at: now))
        guard let id else { return }
        let scheduler = scheduler
        Task { try? await scheduler.stop(alarmID: id) }
    }

    /// 在 App 里按贪睡。
    func snoozeRingingAlarm(now: Date) {
        let id = ringingAlarmID
        ringingAlarmID = nil
        send(.alarmSnoozed(alarmID: id ?? "app", at: now))
        guard let id else { return }
        let scheduler = scheduler
        Task { try? await scheduler.snooze(alarmID: id) }
    }

    // MARK: 闹钟

    /// 保存闹钟并交给 AlarmKit。免费用户超过 1 个时抛 `WorldError.alarmLimitReached`，界面据此弹付费墙。
    func setAlarm(_ alarm: AlarmConfig) throws {
        try world.setAlarm(alarm, isPlus: isPlus)
        persist()
        let scheduler = scheduler
        Task {
            do {
                if alarm.isEnabled {
                    try await scheduler.schedule(alarm)
                } else {
                    try await scheduler.cancel(alarmID: alarm.id)
                }
            } catch {
                lastError = "闹钟排程失败：\(error)"
            }
        }
    }

    func removeAlarm(id: String) {
        try? world.removeAlarm(id: id)
        persist()
        let scheduler = scheduler
        Task { try? await scheduler.cancel(alarmID: id) }
    }

    /// Plus 到期后调用：只保留最快会响的闹钟。
    func enforceAlarmLimit(now: Date) {
        let disabled = world.enforceAlarmLimit(isPlus: isPlus, now: now)
        persist()
        let scheduler = scheduler
        Task {
            for id in disabled { try? await scheduler.cancel(alarmID: id) }
        }
    }

    // MARK: 其他

    func completeOnboarding(now: Date) {
        pendingPrompts += world.completeOnboarding(at: now, isPlus: isPlus)
        bubble = world.line(for: .welcome)
        greetingUntil = now.addingTimeInterval(Self.greetingDuration)
        persist()
    }

    private func apply(_ update: WorldUpdate) {
        if let line = update.line { bubble = line }
        if let away = update.away {
            awayReport = away
            trace = away.trace
        }
        applyBond(update.bond)
        pendingGrants += update.grants.filter { $0.fish > 0 || !$0.items.isEmpty }
        pendingPrompts += update.prompts
        if !update.effects.isEmpty {
            lastEffects = update.effects
            effectsVersion += 1
        }
        if !update.issues.isEmpty { lastError = update.issues.joined(separator: "\n") }
    }

    private func persist() {
        do {
            try storage.save(world.state)
            onPersist?()
        } catch {
            lastError = "保存失败：\(error)"
        }
    }
}

// MARK: - 互动：摸、零食、逗猫棒、慢眨眼、生气、小请求

/// 摸她的一下
struct PetMoment: Equatable {
    var reaction: PetReaction
    var at: Date
}

/// 喂零食：她跑到前面，按她这次的吃法吃完这一小份（开心地吃、先闻闻、拨着玩、叼到一边、吃完还要……）
struct TreatMoment: Equatable {
    var start: Date
    /// 她这次怎么吃（`CatReaction` 里零食那几种）
    var style: CatReaction = .eatHappily
    /// 跑到了、开始吃的时间（还在路上时为 nil）
    var eatingFrom: Date?
    /// 叼起来跑到角落去吃了
    var carried = false
    /// 吃多久（按吃法的动作长度）
    var eatDuration: TimeInterval = 5
    /// 最多等她跑多久（睡醒伸懒腰、从家具上跳下来也算）
    static let maxWait: TimeInterval = 6
    /// 叼起来要多久
    static let pickUp: TimeInterval = 0.7
    /// 零食放在哪（她的右手边）
    static let spot = RoomPoint(x: 0.44, y: 0.86)
    /// 叼走以后去哪吃
    static let carrySpot = RoomPoint(x: 0.22, y: 0.76)

    /// 她吃的时候站在哪（零食在她右边）
    var catSpot: RoomPoint { carried ? Self.carrySpot : RoomPoint(x: Self.spot.x - 0.1, y: Self.spot.y) }
    /// 零食此刻在哪
    var treatSpot: RoomPoint { carried ? RoomPoint(x: Self.carrySpot.x + 0.1, y: Self.carrySpot.y) : Self.spot }
    var end: Date {
        (eatingFrom ?? start.addingTimeInterval(Self.maxWait * (carried ? 2 : 1))).addingTimeInterval(eatDuration)
    }
    /// 叼着跑的路上，地上没有零食
    var onFloor: Bool { !(carried && eatingFrom == nil) }
    /// 正要叼走（跑到了，叼起来那一下）
    var pickingUp: Bool { style == .carryAway && !carried && eatingFrom != nil }

    /// 吃掉了多少（0…1）
    func eaten(at date: Date) -> Double {
        guard let eatingFrom, !pickingUp else { return 0 }
        // 最后一小段是舔嘴巴，那时候已经吃完了
        return (date.timeIntervalSince(eatingFrom) / max(eatDuration - 1.3, 1)).clamped(to: 0...1)
    }
}

/// 一局逗猫棒：你拖着羽毛，她追过去、蹲一下、扑
struct PlaySession: Equatable {
    var start: Date
    /// 羽毛在画布上的位置（0–1）；还没碰屏幕时为 nil
    var feather: RoomPoint?
    /// 她要跑去的地板位置（羽毛正下方）
    var target: RoomPoint
    var lastMove: Date
    /// 跑到了的时间（在路上时为 nil）
    var arrivedAt: Date?
    var pounces: [Date] = []
    /// 这一局已经算过好感度了
    var rewarded = false

    /// 跑到以后蹲多久再扑
    static let crouch: TimeInterval = 0.7
    /// 两次扑之间至少隔多久
    static let pounceGap: TimeInterval = 1.6
    static let pounceDuration: TimeInterval = 0.55
    /// 扑几下算玩了一局
    static let pouncesPerGame = 3
    /// 多久不动羽毛就自动收起来
    static let idleTimeout: TimeInterval = 25
    /// 换目标的最小距离（手指的小抖动不让她来回跑）
    static let retarget = 0.05

    var lastPounce: Date? { pounces.last }
}

/// 你对她慢慢眨眼；她过一会儿（也许）眨回来
struct BlinkMoment: Equatable {
    var start: Date
    var returned: Bool
    /// 你的"眨眼"（屏幕上下合拢）多久
    static let playerDuration: TimeInterval = 1.0
    /// 她什么时候回应、闭眼多久
    static let replyAt: TimeInterval = 1.5
    static let replyDuration: TimeInterval = 1.4

    var end: Date { start.addingTimeInterval(Self.replyAt + Self.replyDuration + 0.6) }

    func catEyesClosed(at date: Date) -> Bool {
        let t = date.timeIntervalSince(start)
        return returned && t >= Self.replyAt && t < Self.replyAt + Self.replyDuration
    }
}

extension WorldStore {
    /// 互动时的样子（不在互动时为 nil）。
    fileprivate func interactivePresence(at date: Date) -> CatPresence? {
        let poll = date.addingTimeInterval(0.3) // 互动时常问一问：跑到了没有、该不该扑
        if let play {
            let facing = (play.feather?.x ?? 0.5) >= play.target.x ? 1 : -1
            return CatPresence(activity: .play, pose: .stand, spot: play.target, depth: .floor(play.target.y),
                               facing: facing, nextChange: poll)
        }
        if let treat, date < treat.end {
            let spot = treat.catSpot
            return CatPresence(activity: .eat, pose: treat.eatingFrom == nil ? .stand : .eat, spot: spot,
                               depth: .floor(spot.y), facing: 1, nextChange: min(poll, treat.end))
        }
        if let until = world.bond.annoyedUntil, date < until, date >= (sulkFrom ?? .distantPast) {
            let spot = sulkSpot ?? RoomPoint(x: 0.14, y: 0.76)
            return CatPresence(activity: nil, pose: .sitBack, spot: spot, depth: .floor(spot.y), nextChange: until)
        }
        return nil
    }

    /// 她是不是睡着了（午睡、晒太阳、蜷着 / 摊着的姿势）
    static func isAsleep(_ presence: CatPresence) -> Bool { asleep(presence) }

    fileprivate static func asleep(_ presence: CatPresence) -> Bool {
        [.nap, .sunbathe].contains(presence.activity ?? .sit) || [.curl, .sprawl, .purr, .sleepBelly].contains(presence.pose)
    }

    // MARK: 窗外的天气

    /// 此刻窗外的天气。Debug 版本可以用 `-debugWeather rain`（clear / cloudy / rain / snow）定住，方便看效果。
    func weather(at date: Date) -> Weather {
        #if DEBUG
        if let raw = UserDefaults.standard.string(forKey: "debugWeather"), let forced = Weather(rawValue: raw) { return forced }
        #endif
        return world.weather(at: date)
    }

    /// 地板上的阳光（晴天、有太阳的钟点才有）
    func sunbeam(at date: Date) -> RoomPoint? {
        weather(at: date).isSunny ? RoomGeometry.sunbeam(sceneHour: sceneHour(at: date)) : nil
    }

    // MARK: 窗外跟着你那里（docs/cat-life.md 4.5）

    /// 画面钟点：天空、光线、地板上的阳光按它画。知道用户的大概位置时跟着真实的日出日落，
    /// 不知道时就是墙上的钟点。每帧都会问，所以把当天的钟留着。
    func sceneHour(at date: Date) -> Double {
        let calendar = world.catConfig.calendar
        guard let place = world.place else { return CatWorld.clockHour(date, calendar: calendar) }
        if let cached = sceneClockCache, cached.place == place, cached.day.contains(date) {
            return cached.clock.hour(at: date)
        }
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400)
        let clock = SceneClock.make(for: date, at: place, calendar: calendar)
        sceneClockCache = (place, start..<end, clock)
        return clock.hour(at: date)
    }

    /// 拿到了位置和真实天气（`hourly` 为空表示这次只拿到了位置）。
    func observeSky(place: Place, hourly: [HourlyWeather], now: Date) {
        world.observeSky(place: place, hourly: hourly, at: now)
        persist()
    }

    /// 用户关掉了"跟着你那里"，或者收回了位置权限：位置和真实天气都忘掉。
    func forgetSky() {
        guard world.state.sky != SkyState() else { return }
        world.forgetSky()
        persist()
    }

    // MARK: 不止一只猫

    var activeCat: CatKind { world.activeCat }

    /// 领养一只新猫（要花小鱼干的会扣），她马上出来陪你。条件不够时抛错。
    func adoptCat(_ kind: CatKind, now: Date) throws {
        try world.adopt(kind, at: now)
        catArrived(now: now)
    }

    /// 换一只领养过的猫出来陪你。
    func switchCat(to kind: CatKind, now: Date) throws {
        guard kind != world.activeCat else { return }
        try world.switchCat(to: kind, at: now)
        catArrived(now: now)
    }

    /// 换了一只猫：之前那只的互动都收起来；新来的先到你面前看看你，再去过自己的日子。
    private func catArrived(now: Date) {
        performance = nil
        play = nil
        treat = nil
        blink = nil
        lastPet = nil
        request = nil
        sulkSpot = nil
        sulkFrom = nil
        purrUntil = nil
        bubble = nil
        awayReport = nil
        trace = nil
        catFocusItemID = nil
        greetingUntil = now.addingTimeInterval(15)
        greeted = false
        pendingHello = false
        interactionVersion += 1
        persist()
    }

    // MARK: 反应动作

    /// 演一段反应。`side`：你的手指在她哪边（-1 左、1 右），侧面的动作朝你那边；0 时按她原来的朝向。
    fileprivate func perform(_ reaction: CatReaction, now: Date, side: Int = 0) {
        let here = presence(at: now)
        let facing = side != 0 ? side : (here.facing != 0 ? here.facing : (Int(now.timeIntervalSince1970 * 10) % 2 == 0 ? 1 : -1))
        let show = CatPerformance(reaction, start: now, facing: facing, base: here.pose, style: CatStyle.of(world.activeCat))
        performance = show
        scheduleSounds(for: show)
        if show.purrs {
            purrUntil = show.end.addingTimeInterval(0.6)
            purr(times: Int(show.duration / 0.35))
        }
    }

    /// 按反应里每一段的时间发出声音。这段反应被别的打断了，后面的声音就不放了。
    private func scheduleSounds(for show: CatPerformance) {
        for cue in show.soundCues {
            if cue.offset <= 0 {
                soundCue = cue.sound
                soundSerial += 1
            } else {
                Task {
                    try? await Task.sleep(for: .seconds(cue.offset))
                    guard performance == show else { return }
                    soundCue = cue.sound
                    soundSerial += 1
                }
            }
        }
    }

    /// 正在演、还没演完
    fileprivate func performing(at date: Date) -> Bool {
        (performance?.end ?? .distantPast) > date
    }

    /// 她此刻是不是要跑过去（玩、吃零食、迎接你）
    func catHurries(at date: Date) -> Bool {
        play != nil || treat != nil || (greetingUntil ?? .distantPast) > date
    }

    /// 能不能和她互动（白天待机、没在布置房间以外的状态）
    var canInteract: Bool { cat.state == .idleDaytime }

    /// 房间每一拍（互动时每 0.3 秒）调用：她跑到了就开始吃 / 准备扑；顺便看看她有没有小请求。
    func interactionTick(now: Date, catArrived: Bool) {
        if var treat {
            let waited = now >= treat.start.addingTimeInterval(TreatMoment.maxWait * (treat.carried ? 2 : 1))
            if treat.eatingFrom == nil, catArrived || waited {
                treat.eatingFrom = now
                if treat.style == .carryAway, !treat.carried {
                    // 先叼起来
                    performance = CatPerformance(.eatHappily, start: now, facing: 1, base: .eat, style: CatStyle.of(world.activeCat))
                    if let show = performance { scheduleSounds(for: show) }
                } else {
                    let style = treat.style == .carryAway ? CatReaction.eatHappily : treat.style
                    perform(style, now: now, side: 1)
                    treat.eatDuration = performance?.duration ?? 5
                }
                self.treat = treat
                interactionVersion += 1
            } else if treat.pickingUp, let from = treat.eatingFrom, now >= from.addingTimeInterval(TreatMoment.pickUp) {
                // 叼着跑到角落去吃
                treat.carried = true
                treat.eatingFrom = nil
                performance = nil
                self.treat = treat
                interactionVersion += 1
            } else if now >= treat.end {
                self.treat = nil
                lastPet = PetMoment(reaction: .loves, at: now) // 吃完：开心的小爱心
                interactionVersion += 1
            }
        }
        if var play {
            if now.timeIntervalSince(play.lastMove) > PlaySession.idleTimeout {
                endPlay(now: now)
            } else {
                if catArrived {
                    if play.arrivedAt == nil { play.arrivedAt = now }
                } else {
                    play.arrivedAt = nil
                }
                if play.feather != nil, let arrived = play.arrivedAt, now.timeIntervalSince(arrived) >= PlaySession.crouch,
                   now.timeIntervalSince(play.lastPounce ?? .distantPast) >= PlaySession.pounceGap, !performing(at: now) {
                    // 每一扑都不太一样：扑中、扑空假装没事、站起来拍、抱住蹬、兴奋得满屋子跑
                    let side = (play.feather?.x ?? 0.5) >= play.target.x ? 1 : -1
                    perform(world.react(to: .pounce(play.pounces.count), at: now), now: now, side: side)
                    play.pounces.append(now)
                    purrTicks += 1
                    if play.pounces.count >= PlaySession.pouncesPerGame, !play.rewarded {
                        play.rewarded = true
                        self.play = play
                        lastPet = PetMoment(reaction: .loves, at: now)
                        applyBond(world.playedWithWand(at: now))
                        persist()
                        return
                    }
                }
                self.play = play
            }
        }
        if let blink, now >= blink.end { self.blink = nil }
        // 迎接你：跑到面前以后蹭你一下 / 叫一声
        if !greeted, let until = greetingUntil, now < until, catArrived, play == nil, treat == nil, !performing(at: now) {
            greeted = true
            // 刚到家的还怕生，只是歪头看看你；熟了叫一声；亲近了（或者黏人的暹罗）蹭过来
            let rubs = world.bondStage >= .close || (world.activeCat == .siamese && world.bondStage >= .curious)
            perform(rubs ? .comeCloser : (world.bondStage == .newcomer ? .headTilt : .meow), now: now)
            purrTicks += 1
        }
        let quiet = play == nil && treat == nil && !performing(at: now)
        if pendingHello, quiet {
            pendingHello = false
            if !Self.asleep(presence(at: now)) { perform(.blinkBack, now: now) }
        }
        // 话多的猫（暹罗）没事会自己叫一声
        let beat = Int((now.timeIntervalSinceReferenceDate / LifeSchedule.beat).rounded(.down))
        if beat != lastCallBeat, quiet, (greetingUntil ?? .distantPast) < now, world.callsOut(at: now) {
            lastCallBeat = beat
            perform(beat % 2 == 0 ? .meow : .chirp, now: now)
        }
        let asking = world.request(at: now)
        if asking != request {
            request = asking
            // 提请求时走到你面前叫一声（想法气泡里画着她想要的东西）
            if asking != nil, play == nil, treat == nil, !performing(at: now), !Self.asleep(presence(at: now)) {
                perform(.meow, now: now)
            }
        }
    }

    // MARK: 摸

    /// 摸她的某个部位（手指在她身上划过一段）。`side`：手指在她哪边（-1 左、1 右）。
    /// 她这次怎么回应由 Core 挑（`CatWorld.react`）：靠过来、顶你的手、抬下巴、翻肚皮、踩奶、拍你一爪……
    func pet(_ region: PetRegion, now: Date, side: Int = 0) {
        guard canInteract else { return }
        let previous = lastPet
        let newSession = previous.map { now.timeIntervalSince($0.at) > 4 } ?? true
        if world.isAnnoyed(at: now) {
            lastPet = PetMoment(reaction: .dislikes, at: now)
            flinchAt = now
            if newSession, !performing(at: now) { perform(.tailFlick, now: now) }
            return
        }
        let outcome = world.pet(region, at: now)
        lastPet = PetMoment(reaction: outcome.reaction, at: now)
        switch outcome.reaction {
        case .loves, .likes:
            squish(now: now)
            purr(times: outcome.reaction == .loves ? 6 : 2)
        case .tolerates:
            break
        case .dislikes:
            flinchAt = now
        }
        // 不喜欢的反应马上演（打断别的）；喜欢的等上一段演完再换一个，一直摸她会一段接一段地回应你
        if outcome.reaction == .dislikes || !performing(at: now.addingTimeInterval(0.25)) {
            perform(world.react(to: .pet(region, outcome.reaction), at: now), now: now, side: side)
        }
        bubble = nil
        if outcome.becameAnnoyed { startSulk(now: now) }
        applyBond(outcome.update)
        if outcome.update.gained > 0 || !outcome.update.memories.isEmpty || outcome.becameAnnoyed { persist() }
    }

    /// 呼噜：连着轻震几下
    private func purr(times: Int) {
        Task {
            for _ in 0..<times {
                purrTicks += 1
                try? await Task.sleep(for: .milliseconds(110))
            }
        }
    }

    // MARK: 生气

    /// 烦了：先原地炸毛嘟囔一下，再走到离她近的那个角落，背对着你坐一会儿。
    private func startSulk(now: Date) {
        let here = presence(at: now).spot
        sulkSpot = RoomPoint(x: here.x < 0.5 ? 0.13 : 0.87, y: 0.76)
        play = nil
        bubble = nil
        flinchAt = now
        perform(.grumble, now: now)
        sulkFrom = performance?.end
        interactionVersion += 1
    }

    // MARK: 零食

    /// 喂一份零食（花 3 条小鱼干）。不够时她说一句，不花钱。返回有没有喂成。
    @discardableResult
    func giveTreat(now: Date) -> Bool {
        guard canInteract, treat == nil else { return false }
        if world.isAnnoyed(at: now) {
            if !performing(at: now) { perform(.tailFlick, now: now) } // 还在生气：不理你
            return false
        }
        do {
            let update = try world.giveTreat(at: now)
            treat = TreatMoment(start: now, style: world.react(to: .treat, at: now))
            performance = nil
            play = nil
            greetingUntil = nil
            applyBond(update)
            interactionVersion += 1
            persist()
            return true
        } catch {
            treatDenied += 1 // 小鱼干不够：零食按钮抖一下，她歪头看看你
            if !performing(at: now), !Self.asleep(presence(at: now)) { perform(.headTilt, now: now) }
            return false
        }
    }

    // MARK: 逗猫棒

    /// 拿出逗猫棒：她先跑到前面等着。
    func startPlay(now: Date) {
        guard canInteract, play == nil else { return }
        if world.isAnnoyed(at: now) {
            if !performing(at: now) { perform(.tailFlick, now: now) }
            return
        }
        treat = nil
        greetingUntil = nil
        play = PlaySession(start: now, feather: nil, target: RoomPoint(x: 0.5, y: 0.84), lastMove: now)
        bubble = nil
        interactionVersion += 1
    }

    /// 羽毛移到了画布上的 `stage`（0–1），她要跑去的地板位置是 `floor`（界面按透视算好）。
    func moveFeather(stage: RoomPoint, floor: RoomPoint, now: Date) {
        guard var play else { return }
        play.feather = stage
        play.lastMove = now
        let dx = floor.x - play.target.x, dy = floor.y - play.target.y
        if (dx * dx + dy * dy).squareRoot() > PlaySession.retarget {
            play.target = floor
            play.arrivedAt = nil
            interactionVersion += 1
        }
        self.play = play
    }

    func endPlay(now: Date) {
        guard play != nil else { return }
        play = nil
        interactionVersion += 1
        persist()
    }

    // MARK: 慢眨眼

    /// 你对她慢慢眨眼。她醒着的时候按好感阶段的概率眨回来（过一会儿才回应）。
    func slowBlink(now: Date) {
        guard canInteract, (blink?.end ?? .distantPast) <= now else { return }
        guard !Self.asleep(presence(at: now)) else { return }
        let result = world.slowBlink(at: now)
        blink = BlinkMoment(start: now, returned: result.returned)
        interactionVersion += 1
        let update = result.update
        Task {
            try? await Task.sleep(for: .seconds(BlinkMoment.replyAt))
            let replyAt = now.addingTimeInterval(BlinkMoment.replyAt)
            perform(world.react(to: .blink(returned: result.returned), at: replyAt), now: replyAt)
            applyBond(update)
        }
        persist()
    }

    // MARK: 好感度变化

    /// 跨过阶段时说一句；新回忆排队弹出；请求满足了就收起气泡。
    fileprivate func applyBond(_ update: BondUpdate) {
        memoryToasts += update.memories.filter { !memoryToasts.contains($0) }
        if update.fulfilled != nil { request = nil }
    }

    /// "你不在的时候"那张卡片看完了
    func dismissAwayReport() {
        awayReport = nil
    }

    /// 把她丢在地上的玩具收起来。她醒着的话会歪头看你一眼
    func pickUpTrace(now: Date) {
        guard trace != nil else { return }
        trace = nil
        if canInteract, !performing(at: now), !Self.asleep(presence(at: now)) { perform(.headTilt, now: now) }
    }

    /// 回忆小卡片看完了
    func dismissMemoryToast() {
        if !memoryToasts.isEmpty { memoryToasts.removeFirst() }
    }
}
