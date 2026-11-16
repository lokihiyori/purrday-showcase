import CatEngine
import CatWorld
import Economy
import Foundation
import Testing
import UIKit
@testable import Purrday

/// 房间里的互动（docs/cat-life.md 第 2 节）：摸、零食、逗猫棒、慢眨眼、生气、迎接、回忆。
@MainActor
@Suite("好感度互动")
struct BondInteractionTests {
    let base = WorldStoreTests()

    #if DEBUG
    /// 一只好感分数是 `points` 的猫，下午三点，白天待机
    private func store(points: Int, fish: Int = 30) throws -> (WorldStore, Date) {
        let now = base.date(2, 15)
        let store = try base.makeStore(now: now)
        store.debugSetBond(points)
        store.debugGrantFish(fish)
        try #require(store.canInteract)
        return (store, now)
    }

    @Test("摸最喜欢的地方：闭眼打呼噜、加好感，记下第一次摸、第一次呼噜")
    func petFavorite() throws {
        let (store, now) = try store(points: 60)
        let favorite = store.world.bond.favoriteRegion
        store.pet(favorite, now: now)
        #expect(store.lastPet == PetMoment(reaction: .loves, at: now))
        #expect(store.bubble == nil) // 她不说话，用动作回应
        #expect(store.world.bond.points > 60)
        #expect(store.memoryToasts == [.firstPet, .firstPurr])
        let show = try #require(store.performance)
        #expect(show.start == now)
        #expect(show.purrs)
        #expect(store.purrUntil != nil)

        // 这一段还没演完时接着摸：不打断，等演完再换下一个动作
        store.pet(favorite, now: now.addingTimeInterval(0.5))
        #expect(store.performance == show)
        let after = show.end.addingTimeInterval(0.1)
        store.pet(favorite, now: after)
        #expect(store.performance?.start == after)
        #expect(store.performance?.reaction != show.reaction)
    }

    @Test("刚到家：摸哪里她都只是忍着（\"……\"），点她会吓一跳")
    func newcomer() throws {
        let (store, now) = try store(points: 0)
        store.pet(.head, now: now)
        #expect(store.lastPet?.reaction == .tolerates)
        #expect([.freeze, .scoot].contains(try #require(store.performance?.reaction)))
        #expect(store.bubble == nil)
        #expect(store.world.bond.points == 0)

        store.tapCat(now: now.addingTimeInterval(10))
        #expect(store.bubble == nil)
        if !WorldStore.isAsleep(store.world.presence(at: now.addingTimeInterval(10))) {
            #expect(store.flinchAt == now.addingTimeInterval(10))
            #expect([.freeze, .scoot].contains(try #require(store.performance?.reaction)))
        }
    }

    @Test("摸尾巴：冒生气符号；连着摸她就烦了，走到角落背对你，3 分钟后才好")
    func tailAndSulk() throws {
        let (store, now) = try store(points: 300)
        store.pet(.tail, now: now)
        #expect(store.lastPet?.reaction == .dislikes)
        #expect(store.flinchAt == now)
        #expect([.grumble, .swat].contains(try #require(store.performance?.reaction)))
        store.pet(.tail, now: now.addingTimeInterval(1))
        store.pet(.tail, now: now.addingTimeInterval(2))
        #expect(store.world.isAnnoyed(at: now.addingTimeInterval(3)))
        #expect(store.performance?.reaction == .grumble) // 先原地炸毛嘟囔，再走开
        #expect(store.bubble == nil)

        let sulking = store.presence(at: now.addingTimeInterval(5))
        #expect(sulking.pose == .sitBack)
        #expect([0.13, 0.87].contains(sulking.spot.x))

        // 生气的时候：点她只是哼一声，零食也不吃（不花小鱼干），也不陪你玩
        let fish = store.world.state.economy.wallet.fish
        store.tapCat(now: now.addingTimeInterval(6))
        #expect(store.performance?.reaction == .tailFlick)
        #expect(!store.giveTreat(now: now.addingTimeInterval(7)))
        #expect(store.world.state.economy.wallet.fish == fish)
        store.startPlay(now: now.addingTimeInterval(8))
        #expect(store.play == nil)

        let later = now.addingTimeInterval(200)
        #expect(store.presence(at: later) == store.world.presence(at: later))
    }

    @Test("短时间点太多下：她烦了")
    func tooManyTaps() throws {
        let (store, now) = try store(points: 300)
        for i in 0..<7 { store.tapCat(now: now.addingTimeInterval(Double(i) * 0.5)) }
        #expect(store.world.isAnnoyed(at: now.addingTimeInterval(4)))
        #expect(store.performance?.reaction == .grumble)
        #expect(store.presence(at: now.addingTimeInterval(7)).pose == .sitBack) // 嘟囔完走到角落
    }

    @Test("零食：花 3 条小鱼干；她跑到前面，到了开始吃，吃完接着过日子")
    func treat() throws {
        let (store, now) = try store(points: 100)
        let fish = store.world.state.economy.wallet.fish
        #expect(store.giveTreat(now: now))
        #expect(store.world.state.economy.wallet.fish == fish - EconomyEngine.treatPrice)
        #expect(store.catHurries(at: now))
        let running = store.presence(at: now.addingTimeInterval(0.5))
        #expect(running.pose == .stand)
        #expect(running.facing == 1)
        #expect(!store.giveTreat(now: now.addingTimeInterval(0.5))) // 一次一份

        // 她这次怎么吃是挑出来的；叼走的那种要先叼起来、跑到角落再吃
        var clock = now.addingTimeInterval(1)
        store.interactionTick(now: clock, catArrived: true)
        if store.treat?.style == .carryAway {
            #expect(store.treat?.pickingUp == true)
            clock = clock.addingTimeInterval(TreatMoment.pickUp)
            store.interactionTick(now: clock, catArrived: true)
            #expect(store.treat?.carried == true)
            #expect(store.presence(at: clock).spot == TreatMoment.carrySpot)
            clock = clock.addingTimeInterval(2)
            store.interactionTick(now: clock, catArrived: true)
        }
        let treat = try #require(store.treat)
        #expect(treat.eatingFrom == clock)
        #expect(store.bubble == nil)
        #expect(store.presence(at: clock.addingTimeInterval(0.5)).pose == .eat)
        #expect(treat.eatDuration == store.performance?.duration)
        #expect(treat.eaten(at: clock) == 0)
        #expect(treat.eaten(at: treat.end) == 1)

        store.interactionTick(now: treat.end, catArrived: true)
        #expect(store.treat == nil)
        #expect(store.memoryToasts.contains(.firstTreat))
    }

    @Test("零食：跑太久（比如在睡觉）也会在几秒后开始吃")
    func treatTimeout() throws {
        let (store, now) = try store(points: 100)
        store.giveTreat(now: now)
        store.interactionTick(now: now.addingTimeInterval(TreatMoment.maxWait), catArrived: false)
        #expect(store.treat?.eatingFrom != nil)
    }

    @Test("小鱼干不够：她说一句，不花钱")
    func treatWithoutFish() throws {
        let (store, now) = try store(points: 100)
        var clock = now
        for _ in 0..<1000 where store.world.state.economy.wallet.fish >= EconomyEngine.treatPrice {
            #expect(store.giveTreat(now: clock))
            for _ in 0..<60 where store.treat != nil { // 一直等到她吃完（各种吃法长短不一样）
                clock = clock.addingTimeInterval(1)
                store.interactionTick(now: clock, catArrived: true)
            }
        }
        #expect(store.treat == nil)
        let fish = store.world.state.economy.wallet.fish
        let denied = store.treatDenied
        #expect(!store.giveTreat(now: clock))
        #expect(store.treatDenied == denied + 1) // 零食按钮抖一下
        #expect(store.bubble == nil)
        #expect(store.world.state.economy.wallet.fish == fish)
    }

    @Test("逗猫棒：她跑到羽毛下面，蹲一下再扑；扑三下算陪她玩了一局")
    func play() throws {
        let (store, now) = try store(points: 300)
        store.startPlay(now: now)
        let session = try #require(store.play)
        #expect(store.presence(at: now).activity == .play)
        #expect(store.presence(at: now).spot == session.target)

        store.moveFeather(stage: RoomPoint(x: 0.75, y: 0.5), floor: RoomPoint(x: 0.75, y: 0.8), now: now)
        #expect(store.play?.target == RoomPoint(x: 0.75, y: 0.8))
        #expect(store.presence(at: now).facing == 1)
        // 手指的小抖动不换目标
        store.moveFeather(stage: RoomPoint(x: 0.76, y: 0.5), floor: RoomPoint(x: 0.76, y: 0.81), now: now)
        #expect(store.play?.target == RoomPoint(x: 0.75, y: 0.8))

        store.interactionTick(now: now.addingTimeInterval(1), catArrived: false)
        #expect(store.play?.pounces.isEmpty == true)
        var clock = now.addingTimeInterval(2)
        store.interactionTick(now: clock, catArrived: true) // 跑到了，开始蹲
        #expect(store.play?.pounces.isEmpty == true)
        var moves = Set<CatReaction>()
        for _ in 0..<PlaySession.pouncesPerGame {
            // 每一扑的动作演完、隔够了才扑下一下
            clock = max(clock.addingTimeInterval(PlaySession.pounceGap + 0.01), (store.performance?.end ?? clock).addingTimeInterval(0.01))
            store.interactionTick(now: clock, catArrived: true)
            moves.insert(try #require(store.performance?.reaction))
        }
        #expect(store.play?.pounces.count == PlaySession.pouncesPerGame)
        #expect(store.play?.rewarded == true)
        #expect(moves.count >= 2) // 每一扑不太一样
        #expect(store.bubble == nil)
        #expect(store.memoryToasts.contains(.firstPlay))

        store.endPlay(now: clock)
        #expect(store.play == nil)
    }

    @Test("逗猫棒：很久不动羽毛就自己收起来")
    func playTimeout() throws {
        let (store, now) = try store(points: 300)
        store.startPlay(now: now)
        store.interactionTick(now: now.addingTimeInterval(PlaySession.idleTimeout + 1), catArrived: true)
        #expect(store.play == nil)
    }

    @Test("慢眨眼：她转过来看你；信赖你的猫几乎总会眨回来")
    func slowBlink() throws {
        let (store, now) = try store(points: 1200)
        let life = store.world.presence(at: now)
        store.slowBlink(now: now)
        if [.nap, .sunbathe].contains(life.activity ?? .sit) || [.curl, .sprawl, .purr].contains(life.pose) {
            #expect(store.blink == nil) // 睡着了，看不见你眨眼
            return
        }
        let blink = try #require(store.blink)
        #expect([.sit, .loaf, .stand].contains(store.presence(at: now.addingTimeInterval(1)).pose))
        if blink.returned {
            #expect(blink.catEyesClosed(at: now.addingTimeInterval(BlinkMoment.replyAt + 0.1)))
            #expect(!blink.catEyesClosed(at: now.addingTimeInterval(0.5)))
        }
        #expect(store.bubble == nil)
        store.interactionTick(now: blink.end, catArrived: true)
        #expect(store.blink == nil)
    }

    @Test("熟了以后隔一阵子打开 App，她跑过来迎接；刚到家不会；马上再打开也不会")
    func greeting() throws {
        let (friend, now) = try store(points: 300)
        friend.foreground(now: now)
        #expect(friend.greetingUntil == now.addingTimeInterval(WorldStore.bondGreetingDuration))
        #expect(friend.bubble == nil)
        #expect(friend.catHurries(at: now))
        #expect(friend.presence(at: now.addingTimeInterval(5)).spot == RoomGeometry.catHome)
        // 跑到你面前以后叫一声 / 蹭你一下（只做一次）
        friend.interactionTick(now: now.addingTimeInterval(3), catArrived: true)
        let hello = try #require(friend.performance)
        #expect([.meow, .comeCloser].contains(hello.reaction))
        friend.interactionTick(now: hello.end.addingTimeInterval(0.1), catArrived: true)
        #expect(friend.performance == hello)
        friend.foreground(now: now.addingTimeInterval(120))
        #expect(friend.greetingUntil == now.addingTimeInterval(WorldStore.bondGreetingDuration))

        let (stranger, _) = try store(points: 0)
        stranger.foreground(now: now)
        #expect(stranger.greetingUntil == nil)
    }

    @Test("新回忆排队弹出，看完一个下一个")
    func memoryToasts() throws {
        let (store, now) = try store(points: 60)
        store.pet(store.world.bond.favoriteRegion, now: now)
        #expect(store.memoryToasts.first == .firstPet)
        store.dismissMemoryToast()
        #expect(store.memoryToasts == [.firstPurr])
        store.dismissMemoryToast()
        store.dismissMemoryToast()
        #expect(store.memoryToasts.isEmpty)
    }
    #endif
}

@Suite("摸到了哪里")
struct PetMapTests {
    @Test("正面坐着：头、下巴、脸颊、肚子、背、尾巴")
    func sit() {
        #expect(PetMap.squareRegion(pose: .sit, x: 0.5, y: 0.15) == .head)
        #expect(PetMap.squareRegion(pose: .sit, x: 0.5, y: 0.36) == .chin)
        #expect(PetMap.squareRegion(pose: .sit, x: 0.33, y: 0.3) == .cheek)
        #expect(PetMap.squareRegion(pose: .sit, x: 0.5, y: 0.6) == .belly)
        #expect(PetMap.squareRegion(pose: .sit, x: 0.28, y: 0.6) == .back)
        #expect(PetMap.squareRegion(pose: .sit, x: 0.7, y: 0.82) == .tail)
        #expect(PetMap.squareRegion(pose: .sit, x: 0.05, y: 0.05) == nil)
    }

    @Test("侧面站着（朝右）：头在右边，尾巴在左上")
    func stand() {
        #expect(PetMap.squareRegion(pose: .stand, x: 0.8, y: 0.42) == .head)
        #expect(PetMap.squareRegion(pose: .stand, x: 0.2, y: 0.4) == .tail)
        #expect(PetMap.squareRegion(pose: .stand, x: 0.5, y: 0.55) == .back)
        #expect(PetMap.squareRegion(pose: .stand, x: 0.5, y: 0.7) == .belly)
    }

    @Test("每个姿势：身体中间能摸到，图外面摸不到；头那一块是头或脸")
    func everyPose() {
        for pose in CatPose.allCases {
            let b = CatPoseArt.bounds(pose)
            let middle = PetMap.region(pose: pose, wideX: (b.x0 + b.x1) / 2, y: b.y0 + b.height * 0.62)
            #expect(middle != nil, "\(pose)")
            #expect(PetMap.region(pose: pose, wideX: 0.02, y: 0.02) == nil, "\(pose)")
        }
        #expect(PetMap.region(pose: .bellyUp, wideX: 0.55, y: 0.6) == .belly)
        #expect(PetMap.region(pose: .lieSide, wideX: 0.75, y: 0.4) == .head)
        #expect(PetMap.region(pose: .chinUp, wideX: 0.5, y: 0.15) == .head)
        #expect(PetMap.region(pose: .crouch, wideX: 0.22, y: 0.6) == .tail)
    }

    @Test("宽画布和方图的换算：方图在宽画布中间")
    func wide() {
        #expect(PetMap.toSquare(0.5) == 0.5)
        #expect(abs(PetMap.toSquare(0.5 + 0.25 / CatPoseArt.wideAspect) - 0.75) < 1e-9)
        #expect(PetMap.region(pose: .sit, wideX: 0.5, y: 0.15) == .head)
    }
}

@Suite("互动的美术资源")
struct BondArtTests {
    @Test("眨眼图、回忆的插画、零食和羽毛都在")
    func art() {
        for kind in CatKind.allCases {
            for pose in CatPoseArt.blinkPoses {
                let name = CatPoseArt.prefix(kind) + pose
                #expect(CatPoseArt.blinkName(for: name) == "\(name)-blink")
                #expect(UIImage(named: "\(name)-blink") != nil, "\(name)-blink")
            }
        }
        #expect(CatPoseArt.blinkName(for: "cat-pose-groom") == nil)
        for memory in CatMemory.allCases {
            #expect(UIImage(named: MemoryArt.still(for: memory)) != nil, "\(memory)")
        }
        for name in ["item-feather", "item-fish_cracker"] {
            #expect(UIImage(named: name) != nil, "\(name)")
        }
    }

    @Test("每只猫的每个姿势都有图；走路四帧、坐着的小动作图都在；能当玩具的东西都有图标")
    func poseArt() throws {
        for kind in CatKind.allCases {
            for pose in CatPose.allCases where pose != .stateArt {
                let name = try #require(CatPoseArt.name(for: pose, kind: kind))
                #expect(UIImage(named: name) != nil, "\(name)")
            }
            for name in CatPoseArt.walkFrames(kind) + CatPoseArt.fidgetFiles.map({ CatPoseArt.prefix(kind) + $0 }) {
                #expect(UIImage(named: name) != nil, "\(name)")
            }
        }
        let catalog = try Catalog.bundled()
        for id in LifeSchedule.toys {
            let item = try #require(catalog.item(id), "\(id)")
            #expect(UIImage(named: Theme.art(for: item)) != nil, "\(id)")
        }
    }
}

@Suite("反应动作怎么演")
struct CatPerformanceTests {
    @Test("每种反应都有动作，时间不长不短；按时间走到每一段")
    func scripts() {
        let start = Date(timeIntervalSinceReferenceDate: 1000)
        for reaction in CatReaction.allCases {
            for base in [CatPose.sit, .loaf, .curl, .stand] {
                let show = CatPerformance(reaction, start: start, facing: 0, base: base)
                #expect(!show.steps.isEmpty, "\(reaction)")
                #expect((0.5...6).contains(show.duration), "\(reaction)")
                #expect(show.frame(at: start)?.index == 0)
                #expect(show.frame(at: show.end.addingTimeInterval(-0.01))?.index == show.steps.count - 1)
                #expect(show.frame(at: show.end) == nil)
                #expect(show.frame(at: start.addingTimeInterval(-1)) == nil)
                #expect(show.facing != 0) // 侧面的动作总有个朝向
            }
        }
    }

    @Test("身体的形变都在合理范围里（不会把她甩出画面）")
    func deformations() {
        let start = Date(timeIntervalSinceReferenceDate: 1000)
        for reaction in CatReaction.allCases {
            let show = CatPerformance(reaction, start: start, facing: 1, base: .sit)
            var t = 0.0
            while t < show.duration {
                if let frame = show.frame(at: start.addingTimeInterval(t)) {
                    let b = CatRigView.performanceBody(frame, time: 1000 + t)
                    #expect(abs(b.bend) < 0.15 && abs(b.stretch) < 0.2 && b.lift > -0.02 && b.lift < 0.3, "\(reaction) @\(t)")
                    #expect(abs(b.shift) < 1.5 && abs(b.tilt) < 20, "\(reaction) @\(t)")
                }
                t += 0.05
            }
        }
    }

    @Test("睡着时被摸：在原来的姿势上演，不会突然坐起来")
    func lyingDown() {
        let steps = CatPerformance.script(for: .leanIn, base: .curl)
        #expect(steps.first?.pose == .curl)
        #expect(CatPerformance.script(for: .leanIn, base: .stand).first?.pose == .sit)
    }
}

@MainActor
@Suite("不止一只猫")
struct CatsStoreTests {
    let base = WorldStoreTests()

    #if DEBUG
    @Test("领养暹罗：她换出来，先到你面前看看你；之前那只的互动都收起来；换回布丁，好感还在")
    func adoptAndSwitch() throws {
        let now = base.date(2, 15)
        let store = try base.makeStore(now: now)
        store.debugSetBond(300)
        store.debugGrantFish(30)
        store.startPlay(now: now)
        #expect(store.activeCat == .pudding)

        try store.adoptCat(.siamese, now: now)
        #expect(store.activeCat == .siamese)
        #expect(store.play == nil && store.performance == nil && store.bubble == nil)
        #expect(store.world.bondStage == .newcomer)
        #expect(store.presence(at: now.addingTimeInterval(3)).spot == RoomGeometry.catHome)
        store.interactionTick(now: now.addingTimeInterval(3), catArrived: true)
        #expect(store.performance?.reaction == .headTilt) // 新来的还怕生：歪头看看你

        try store.switchCat(to: .pudding, now: now.addingTimeInterval(30))
        #expect(store.activeCat == .pudding)
        #expect(store.world.bondStage == .familiar)

        // 重新打开 App：还是布丁，暹罗在休息
        let reopened = try base.makeStore(now: now.addingTimeInterval(60))
        #expect(reopened.activeCat == .pudding)
        #expect(reopened.world.availability(of: .siamese) == .resting)
    }

    @Test("小鱼干不够领养长毛猫：报错，什么都不变")
    func cannotAfford() throws {
        let now = base.date(2, 15)
        let store = try base.makeStore(now: now)
        #expect(throws: (any Error).self) { try store.adoptCat(.fluffy, now: now) }
        #expect(store.activeCat == .pudding)
    }
    #endif

    @Test("别的猫：特殊时刻的画用她自己的姿势图；名字各自存")
    func stillsAndNames() {
        #expect(CatStill.name("cat-meow", kind: .pudding) == "cat-meow")
        #expect(CatStill.name("cat-meow", kind: .siamese) == "cat-siamese-meow") // 专属画
        #expect(CatStill.name("cat-push-cup", kind: .fluffy) == "cat-fluffy-push-cup")
        #expect(CatStill.name("cat-sleep", kind: .fluffy) == "cat-fluffy-pose-curl") // 没有专属画的用姿势图
        #expect(CatStill.name("cat-idle", kind: .siamese) == "cat-siamese-pose-sit")
        for kind in [CatKind.siamese, .fluffy] {
            for still in ["cat-sleep", "cat-meow", "cat-gift", "cat-knead", "cat-push-cup", "cat-phone", "cat-idle", "cat-focus",
                          "cat-read", "cat-walk", "cat-purr", "cat-petted", "cat-stretch"] {
                #expect(UIImage(named: CatStill.name(still, kind: kind)) != nil, "\(kind) \(still)")
            }
        }
        #expect(CatNames.key(.pudding) == "catName")
        #expect(CatNames.key(.siamese) == "catName.siamese")
        #expect(!CatNames.defaultName(.fluffy).isEmpty)
    }

    @Test("别的猫摸到哪里：按她自己的身体范围分")
    func petMap() {
        for kind in [CatKind.siamese, .fluffy] {
            for pose in CatPose.allCases {
                let b = CatPoseArt.bounds(pose, kind: kind)
                #expect(b.width > 0.1 && b.height > 0.1, "\(kind) \(pose)")
                #expect(PetMap.region(pose: pose, wideX: (b.x0 + b.x1) / 2, y: b.y0 + b.height * 0.62, kind: kind) != nil, "\(kind) \(pose)")
            }
            let sit = CatPoseArt.bounds(.sit, kind: kind)
            #expect(PetMap.region(pose: .sit, wideX: (sit.x0 + sit.x1) / 2, y: sit.y0 + sit.height * 0.08, kind: kind) == .head)
        }
    }
}

@Suite("每种猫动起来不一样")
struct CatStyleTests {
    private let start = Date(timeIntervalSinceReferenceDate: 5000)

    @Test("同一个反应：暹罗演得快，长毛猫慢，而且先愣一下才动")
    func tempo() {
        func show(_ kind: CatKind) -> CatPerformance {
            CatPerformance(.leanIn, start: start, facing: 1, base: .sit, style: .of(kind))
        }
        #expect(show(.siamese).duration < show(.pudding).duration)
        #expect(show(.fluffy).duration > show(.pudding).duration + CatStyle.of(.fluffy).delay)
        #expect(show(.fluffy).steps.first?.pose == nil)
        #expect(show(.fluffy).steps.first?.duration == CatStyle.of(.fluffy).delay)
        #expect(show(.pudding).steps.count == 1)
    }

    @Test("幅度：同一个动作，暹罗弯得多、跳得高，长毛猫收着")
    func amplitude() {
        func peak(_ kind: CatKind, _ reaction: CatReaction) -> (bend: Double, lift: Double) {
            let show = CatPerformance(reaction, start: start, facing: 1, base: .sit, style: .of(kind))
            var bend = 0.0, lift = 0.0
            var t = 0.0
            while t < show.duration {
                if let frame = show.frame(at: start.addingTimeInterval(t)) {
                    let body = CatRigView.performanceBody(frame, time: t)
                    bend = max(bend, abs(body.bend))
                    lift = max(lift, body.lift)
                }
                t += 0.02
            }
            return (bend, lift)
        }
        #expect(peak(.siamese, .leanIn).bend > peak(.pudding, .leanIn).bend)
        #expect(peak(.fluffy, .leanIn).bend < peak(.pudding, .leanIn).bend * 0.85)
        #expect(peak(.siamese, .catchIt).lift > peak(.fluffy, .catchIt).lift * 1.3)
    }

    @Test("走路：暹罗走得快，长毛猫走得慢")
    func walking() {
        let from = CatPresence(activity: .sit, pose: .sit, spot: RoomPoint(x: 0.2, y: 0.85), depth: .floor(0.85),
                               nextChange: start.addingTimeInterval(20))
        let to = CatPresence(activity: .sit, pose: .sit, spot: RoomPoint(x: 0.8, y: 0.85), depth: .floor(0.85),
                             nextChange: start.addingTimeInterval(20))
        func travel(_ kind: CatKind) -> TimeInterval {
            var actor = CatActor()
            actor.update(to: from, now: start, animated: false, itemBottoms: [:])
            actor.update(to: to, now: start, animated: true, itemBottoms: [:], speed: CatStyle.of(kind).speed)
            return actor.segments.reduce(0) { $0 + $1.duration }
        }
        #expect(travel(.siamese) < travel(.pudding))
        #expect(travel(.fluffy) > travel(.pudding))
    }
}

@MainActor
@Suite("每种猫迎接你的方式不一样")
struct CatGreetingTests {
    let base = WorldStoreTests()

    #if DEBUG
    /// 换成某只猫陪着你，好感分数是 points
    private func store(_ kind: CatKind, points: Int) throws -> (WorldStore, Date) {
        let base = WorldStoreTests() // 每次一个新存档
        let now = base.date(2, 15)
        let store = try base.makeStore(now: now)
        store.debugSetBond(300)
        store.debugGrantFish(300)
        try store.adoptCat(kind, now: now)
        store.debugSetBond(points)
        return (store, now.addingTimeInterval(3600))
    }

    @Test("暹罗刚好奇就跑来迎接，待得久，到了就蹭你")
    func siamese() throws {
        let (store, later) = try store(.siamese, points: 60)
        store.foreground(now: later)
        #expect(store.greetingUntil == later.addingTimeInterval(CatStyle.of(.siamese).greetingTime))
        #expect(store.catHurries(at: later))
        store.interactionTick(now: later.addingTimeInterval(2), catArrived: true)
        #expect(store.performance?.reaction == .comeCloser)
    }

    @Test("长毛猫熟了也不跑过来：在原地慢慢眨一下眼（慢半拍）；要到信赖才来迎接")
    func fluffy() throws {
        let (store, later) = try store(.fluffy, points: 300)
        store.foreground(now: later)
        #expect((store.greetingUntil ?? .distantPast) < later)
        store.interactionTick(now: later.addingTimeInterval(1), catArrived: true)
        if !WorldStore.isAsleep(store.presence(at: later.addingTimeInterval(1))) {
            let hello = try #require(store.performance)
            #expect(hello.reaction == .blinkBack)
            #expect(hello.steps.first?.pose == nil && hello.steps.first?.duration == CatStyle.of(.fluffy).delay)
        }

        let (devoted, t) = try self.store(.fluffy, points: 1200)
        devoted.foreground(now: t)
        #expect(devoted.greetingUntil == t.addingTimeInterval(CatStyle.of(.fluffy).greetingTime))
    }

    @Test("话多的暹罗没事会自己叫一声（一拍最多一次）")
    func calls() throws {
        let (store, later) = try store(.siamese, points: 300)
        var called = 0
        var clock = later
        for _ in 0..<1080 { // 6 个小时（她有时在睡觉、躲着，那时候不叫）
            clock = clock.addingTimeInterval(LifeSchedule.beat)
            let before = store.performance
            store.interactionTick(now: clock, catArrived: true)
            if let show = store.performance, show != before, [.meow, .chirp].contains(show.reaction) { called += 1 }
            store.interactionTick(now: clock.addingTimeInterval(1), catArrived: true) // 同一拍再问：不会再叫
        }
        #expect(called >= 10)
        #expect(called <= 1080)
    }
    #endif
}

@Suite("猫的声音")
struct CatSoundTests {
    private let start = Date(timeIntervalSinceReferenceDate: 9000)

    @Test("每种反应配的声音：叫、蹭你的颤音、嘟囔、吓一跳；吃东西咔嚓；讨零食在站起来那一下叫")
    func cues() {
        func sounds(_ reaction: CatReaction) -> [CatSound] {
            CatPerformance(reaction, start: start, facing: 1, base: .sit).soundCues.map(\.sound)
        }
        #expect(sounds(.meow) == [.meow])
        #expect(sounds(.chirp) == [.trill])
        #expect(sounds(.comeCloser) == [.trill])
        #expect(sounds(.grumble) == [.grumble])
        #expect(sounds(.swat) == [.grumble])
        #expect(sounds(.scoot) == [.squeak])
        #expect(sounds(.eatHappily) == [.crunch])
        #expect(sounds(.beg) == [.crunch, .ask])
        #expect(sounds(.leanIn).isEmpty) // 打呼噜另外放（PurrSound）

        let beg = CatPerformance(.beg, start: start, facing: 1, base: .sit)
        #expect(beg.soundCues.last?.offset == beg.duration - (beg.steps.last?.duration ?? 0))
        // 慢半拍的长毛猫：先愣一下，声音也跟着晚一点
        let slow = CatPerformance(.meow, start: start, facing: 1, base: .sit, style: .of(.fluffy))
        #expect(slow.soundCues.first?.offset == CatStyle.of(.fluffy).delay)
    }

    @Test("每只猫的每种声音都有文件（音调提前做进文件里）；吃东西的咔嚓声共用；每只猫有自己的呼噜")
    func files() {
        for kind in CatKind.allCases {
            for sound in CatSound.allCases {
                let recipe = CatVoice.recipe(sound)
                #expect(recipe.variants >= 1 && recipe.volume > 0)
                for variant in 1...recipe.variants {
                    let name = CatVoice.file(sound, kind: kind, variant: variant)
                    #expect(Bundle.main.url(forResource: name, withExtension: "m4a") != nil, "缺 \(name).m4a")
                }
            }
            #expect(Bundle.main.url(forResource: CatVoice.purrFile(kind), withExtension: "m4a") != nil, "\(kind) 的呼噜")
        }
        #expect(CatVoice.file(.crunch, kind: .siamese, variant: 1) == "cat-crunch-1")
        #expect(CatVoice.file(.meow, kind: .fluffy, variant: 2) == "cat-fluffy-meow-2")
    }

    #if DEBUG
    @MainActor
    @Test("摸尾巴：她嘟囔一声（房间据此放声音）")
    func storeCue() throws {
        let base = WorldStoreTests()
        let now = base.date(2, 15)
        let store = try base.makeStore(now: now)
        store.debugSetBond(300)
        #expect(store.soundSerial == 0)
        store.pet(.tail, now: now)
        #expect(store.soundCue == .grumble)
        #expect(store.soundSerial == 1)
    }
    #endif
}

@MainActor
@Suite("你不在的时候")
struct AwayStoreTests {
    let base = WorldStoreTests()

    #if DEBUG
    @Test("离开一小时以上再打开：有一张小卡片说她做了什么，看完收起来；马上再打开没有")
    func report() throws {
        let now = base.date(2, 9)
        let store = try base.makeStore(now: now)
        store.debugSetBond(300)
        store.foreground(now: now)
        #expect(store.awayReport == nil)
        store.foreground(now: now.addingTimeInterval(20 * 60))
        #expect(store.awayReport == nil)

        let later = now.addingTimeInterval(6 * 3600)
        store.foreground(now: later)
        let report = try #require(store.awayReport)
        #expect(report.to == later)
        #expect(!report.highlights.isEmpty)
        store.dismissAwayReport()
        #expect(store.awayReport == nil)
    }

    @Test("换了一只猫：上一只留下的卡片和玩具都收起来")
    func switchingClears() throws {
        let now = base.date(2, 9)
        let store = try base.makeStore(now: now)
        store.debugSetBond(300)
        store.foreground(now: now)
        store.foreground(now: now.addingTimeInterval(6 * 3600))
        #expect(store.awayReport != nil)
        try store.adoptCat(.siamese, now: now.addingTimeInterval(6 * 3600 + 10))
        #expect(store.awayReport == nil && store.trace == nil)
    }
    #endif

    @Test("卡片上的话：时长说成小时或分钟；每件事都有图标")
    func sentences() {
        #expect(AwayCard.duration(45) == localized("away.minutes", 45))
        #expect(AwayCard.duration(125) == localized("away.hours", 2))
        #expect(AwayCard.duration(100) == localized("away.hours", 2)) // 四舍五入
        #expect(AwayCard.sentenceKey(.night) == "away.night")
        #expect(AwayCard.sentenceKey(.activity(.sunbathe)) == "away.sunbathe")
        for activity in CatActivity.allCases {
            #expect(!AwayCard.symbol(.activity(activity)).isEmpty)
            #expect(!AwayCard.sentence(AwayHighlight(kind: .activity(activity), minutes: 90)).hasPrefix("away."), "\(activity)")
        }
    }
}

@MainActor
@Suite("商店：今日推荐和房间预览")
struct ShopUITests {
    @Test("每种用途都有一句话和图标；详情里的用途去重、顺序固定")
    func uses() throws {
        let catalog = try Catalog.bundled()
        for use in FurnitureUse.allCases {
            #expect(!ShopView.symbol(use).isEmpty)
            #expect(!String(localized: String.LocalizationValue(ShopItemSheet.useKey(use))).hasPrefix("shop.use."), "\(use)")
        }
        let tree = try #require(catalog.item("furniture.cat_tree"))
        let uses = ShopItemSheet.uses(of: tree)
        #expect(Set(uses).count == uses.count)
        #expect(uses.contains(.perch) && uses.contains(.scratch))
    }
}

@Suite("小组件和特殊时刻的图")
struct WidgetArtTests {
    @Test("每只猫在每个状态、每种捣乱下都有图（小组件、叫醒页、睡前页用）")
    func stateArt() {
        let states: [CatState] = [.sleepingAtNight, .wakingUp, .givingGift, .makingMischief, .idleDaytime,
                                  .accompanying(.focus), .accompanying(.read), .accompanying(.move), .purringAtBedtime]
        for kind in CatKind.allCases {
            for state in states {
                for mischief in [MischiefKind.stepOnFace, .pushCup, .lieOnPhone] {
                    let name = CatArtNames.still(CatArt.assetName(state: state, mischief: mischief), kind: kind)
                    #expect(UIImage(named: name) != nil, "\(name)")
                }
            }
            #expect(UIImage(named: CatArtNames.still("cat-petted", kind: kind)) != nil)
        }
    }

    @Test("小组件白天用她在做的那件事的姿势图：每只猫每个姿势都有")
    func poseArt() {
        for kind in CatKind.allCases {
            for pose in CatPose.allCases where pose != .stateArt {
                let name = CatArtNames.pose(pose, kind: kind)
                #expect(name.map { UIImage(named: $0) != nil } == true, "\(kind) \(pose)")
            }
            #expect(CatArtNames.pose(.stateArt, kind: kind) == nil)
        }
    }
}

@Suite("睡前的声音")
struct BedtimeMixTests {
    @Test("最后半分钟慢慢变小；每种环境音都有文件、名字和图标")
    func mix() {
        #expect(BedtimeMix.gain(remaining: 600) == 1)
        #expect(BedtimeMix.gain(remaining: BedtimeMix.fadeOut / 2) == 0.5)
        #expect(BedtimeMix.gain(remaining: 0) == 0)
        #expect(BedtimeMix.gain(remaining: -5) == 0)
        for ambient in BedtimeMix.Ambient.allCases {
            #expect(!BedtimeView.symbol(ambient).isEmpty)
            #expect(!String(localized: String.LocalizationValue(BedtimeView.nameKey(ambient))).hasPrefix("bedtime.sound."))
            if ambient != .none {
                #expect(Bundle.main.url(forResource: ambient.rawValue, withExtension: "m4a") != nil, "\(ambient)")
            }
        }
    }

    @Test("设置存在 UserDefaults 里；没存过就是只放呼噜")
    func saved() throws {
        let defaults = try #require(UserDefaults(suiteName: "bedtime-mix-test-\(UUID().uuidString)"))
        #expect(BedtimeMix.saved(defaults) == BedtimeMix())
        defaults.set("rain", forKey: BedtimeMix.ambientKey)
        defaults.set(0.2, forKey: BedtimeMix.ambientVolumeKey)
        #expect(BedtimeMix.saved(defaults) == BedtimeMix(ambient: .rain, purrVolume: 0.7, ambientVolume: 0.2))
    }
}

@Suite("起床日历的界面")
struct MorningCalendarCardTests {
    @Test("星期的简写从日历的第一天开始排，一共七个；每种爪印都有说明")
    func symbols() {
        var sunday = Calendar(identifier: .gregorian)
        sunday.firstWeekday = 1
        var monday = sunday
        monday.firstWeekday = 2
        let a = MorningCalendarCard.weekdaySymbols(sunday), b = MorningCalendarCard.weekdaySymbols(monday)
        #expect(a.count == 7 && b.count == 7)
        #expect(Array(a[1...]) + [a[0]] == b)
        for mark in [MorningMark.onTime, .late(snoozes: 1), .none] {
            #expect(!String(localized: String.LocalizationValue(MorningCalendarCard.markKey(mark))).hasPrefix("calendar."))
        }
    }
}
