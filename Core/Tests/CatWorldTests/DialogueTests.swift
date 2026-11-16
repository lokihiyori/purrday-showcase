import CatEngine
import Economy
import Foundation
import Testing
@testable import CatWorld

@Suite("布丁的台词")
struct DialogueTests {
    @Test("同一个场景不会连着说同一句")
    func noImmediateRepeat() throws {
        var world = try makeWorld()
        for scene in CatScene.allCases {
            var last = world.line(for: scene)
            for _ in 0..<30 {
                let next = world.line(for: scene)
                #expect(next != last)
                #expect(scene.lineKeys.contains(next))
                last = next
            }
        }
    }

    @Test("台词不影响掉落：多说几句话，礼物结果不变")
    func dialogueDoesNotAffectLoot() throws {
        var quiet = try makeWorld(seed: 9)
        var chatty = try makeWorld(seed: 9)
        for _ in 0..<7 { _ = chatty.line(for: .petted) }
        let a = quiet.ingest(onTimeMorning(2), isPlus: false).grants
        let b = chatty.ingest(onTimeMorning(2), isPlus: false).grants
        #expect(a == b)
    }

    @Test("准时起床配送礼物的台词；贪睡配捣乱的台词；贪睡后起床配小懒虫")
    func scenesFromEvents() throws {
        var world = try makeWorld()
        let gift = world.ingest(onTimeMorning(2), isPlus: false)
        #expect([.gift, .rareGift, .legendaryGift].contains(gift.scene))
        #expect(gift.line?.hasPrefix("line.") == true)

        let fire = world.ingest([LoggedEvent(id: "f3", event: .alarmFired(alarmID: "A", at: t(3, 7)))], isPlus: false)
        #expect(fire.scene == .wake)
        let snooze1 = world.ingest([LoggedEvent(id: "z1", event: .alarmSnoozed(alarmID: "A", at: t(3, 7, 1)))], isPlus: false)
        #expect(snooze1.scene == .snooze1)
        world.ingest([LoggedEvent(id: "f4", event: .alarmFired(alarmID: "A", at: t(3, 7, 10)))], isPlus: false)
        let snooze2 = world.ingest([LoggedEvent(id: "z2", event: .alarmSnoozed(alarmID: "A", at: t(3, 7, 11)))], isPlus: false)
        #expect(snooze2.scene == .snooze2)
        let stop = world.ingest([LoggedEvent(id: "s", event: .alarmStopped(alarmID: "A", via: .petCat, at: t(3, 7, 15)))], isPlus: false)
        #expect(stop.scene == .lateWake)
    }

    @Test("一批里有多件事时，取最后发生的那件")
    func lastSceneWins() throws {
        var world = try makeWorld()
        let update = world.ingest([
            LoggedEvent(id: "1", event: .alarmFired(alarmID: "A", at: t(2, 7))),
            LoggedEvent(id: "2", event: .alarmSnoozed(alarmID: "A", at: t(2, 7, 1))),
            LoggedEvent(id: "3", event: .alarmFired(alarmID: "A", at: t(2, 7, 10))),
            LoggedEvent(id: "4", event: .alarmStopped(alarmID: "A", via: .lockScreen, at: t(2, 7, 11))),
        ], isPlus: false)
        #expect(update.scene == .lateWake)
    }

    @Test("稀有礼物配稀有的台词")
    func rareGiftScene() throws {
        // 找一个第一次就掉稀有以上礼物的种子
        let catalog = try Catalog.bundled()
        for seed in UInt64(1)...500 {
            var world = try makeWorld(seed: seed)
            let update = world.ingest(onTimeMorning(2), isPlus: false)
            let rarity = update.grants[0].items.compactMap { catalog.item($0.catalogID)?.rarity }.first!
            switch rarity {
            case .legendary: #expect(update.scene == .legendaryGift); return
            case .rare: #expect(update.scene == .rareGift)
            default: #expect(update.scene == .gift)
            }
        }
    }

    @Test("番茄钟：开始、完成、放弃")
    func focusScenes() throws {
        var world = try makeWorld(at: t(2, 9))
        #expect(world.ingest([LoggedEvent(id: "1", event: .sessionStarted(.focus, at: t(2, 10)))], isPlus: false).scene == .focusStart)
        #expect(world.ingest([LoggedEvent(id: "2", event: .sessionEnded(.focus, completed: true, at: t(2, 10, 25)))], isPlus: false).scene == .focusDone)
        world.ingest([LoggedEvent(id: "3", event: .sessionStarted(.focus, at: t(2, 11)))], isPlus: false)
        #expect(world.ingest([LoggedEvent(id: "4", event: .sessionEnded(.focus, completed: false, at: t(2, 11, 5)))], isPlus: false).scene == .focusAbandoned)
    }

    @Test("到了睡前时间、开启睡前模式")
    func bedtimeScenes() throws {
        var world = try makeWorld(at: t(2, 20))
        #expect(world.tick(at: t(2, 23), isPlus: false).scene == nil) // tick 不配台词，App 打开时才说
        var other = try makeWorld(at: t(2, 20))
        #expect(other.foreground(at: t(2, 23, 1), isPlus: false).scene == .bedtimePrompt)
        #expect(other.ingest([LoggedEvent(id: "b", event: .bedtimeTimerStarted(duration: 1800, at: t(2, 23, 5)))], isPlus: false).scene == .purring)
    }

    @Test("三天没打开 App：回来时说想你了；收拾乱子说谢谢")
    func returnedAndMess() throws {
        var world = try makeWorld()
        world.foreground(at: t(2, 12), isPlus: false)
        #expect(world.foreground(at: t(3, 12), isPlus: false).scene == nil)
        #expect(world.foreground(at: t(7, 12), isPlus: false).scene == .returned)
        #expect(world.clearMess(at: t(7, 12, 1), isPlus: false).scene == .messCleared)
    }

    @Test("点她时的旁白跟着状态走；白天待机时没有旁白（她用动作回应）")
    func tapNarration() throws {
        var world = try makeWorld(at: t(2, 12))
        #expect(world.tapScene() == nil)
        world.foreground(at: t(3, 1), isPlus: false)
        #expect(world.tapScene() == .purring) // 23:00 进入睡前呼噜后没开定时器
        world.tick(at: t(3, 2, 30), isPlus: false)
        #expect(world.tapScene() == .sleepingTapped)
    }
}

@Suite("台词只对最近的事")
struct DialogueRecencyTests {
    @Test("隔天中午打开 App，不会再说昨晚的睡前台词")
    func noStaleBedtimeLine() throws {
        var world = try makeWorld(at: t(2, 20))
        let update = world.foreground(at: t(3, 12), isPlus: false)
        #expect(update.transitions.contains(.t8))
        #expect(update.scene == nil)
    }
}

@Suite("旧存档里的台词记录")
struct DialogueMigrationTests {
    @Test("存档里记着已经删掉的场景（她以前会说话）：照样能读，认识的留下")
    func removedScenes() throws {
        var world = try makeWorld()
        _ = world.line(for: .wake)
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(world.state)) as? [String: Any])
        var lines = try #require(json["lastLines"] as? [String: String])
        #expect(lines["wake"] != nil)
        lines["idleMorning"] = "line.idleMorning.2"
        lines["affectionate"] = "line.affectionate.1"
        json["lastLines"] = lines
        let loaded = try JSONDecoder().decode(WorldState.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(loaded.lastLines == world.state.lastLines)
    }
}

