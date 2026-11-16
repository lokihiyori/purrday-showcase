import XCTest

/// 在模拟器里把 App 从新手引导开始点一遍，每一屏存一张截图（`docs/mac-setup.md` 第 4 节第 1 步）。
///
/// 用 `scripts/ui_walkthrough.sh` 运行：脚本会先卸载 App 保证从新手引导开始，
/// 并通过 `TEST_RUNNER_WALKTHROUGH_LANG` 选择语言，最后把截图导出到 `build/walkthrough/<语言>/`。
///
/// 这是"看一眼"用的走查，不是严格的回归测试：可选的界面（例如新手引导后的付费墙）没出现时只记录，不中断。
///
/// 启动时带 `-debugFish 320`（只在 Debug 版本生效）：够买纸箱、地毯、猫爬架、布丁沙发，剩 5 条，鱼缸买不起。
@MainActor
final class WalkthroughTests: XCTestCase {
    private var app: XCUIApplication!
    private var language = "en"
    private var shotIndex = 0

    override func setUp() async throws {
        continueAfterFailure = true
        language = ProcessInfo.processInfo.environment["WALKTHROUGH_LANG"] ?? "en"
        app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(\(language))", "-AppleLocale", Self.locale(for: language), "-debugFish", "320",
                                 "-debugHour", "14"] // 时间拨到下午两点：什么时候跑走查，猫都是醒着的
    }

    func testWalkthrough() throws {
        app.launch()
        onboarding()
        room()
        alarms()
        shop()
        decorate()
        backpack()
        bond()
        window()
    }

    // MARK: - 各个界面

    private func onboarding() {
        let next = app.buttons["onboarding.next"]
        guard next.waitForExistence(timeout: 10) else {
            XCTFail("没有出现新手引导（App 没有被卸载干净？）")
            shot("onboarding-missing")
            return
        }
        shot("onboarding-1-welcome")
        next.tap()
        shot("onboarding-2-adopt")
        next.tap()

        let name = app.textFields["onboarding.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 3), "取名输入框不见了")
        shot("onboarding-3-name")
        if name.exists {
            name.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap() // 点最右边，光标落在末尾
            let current = name.value as? String ?? ""
            name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count) + "Mochi")
            shot("onboarding-3-name-typed")
            dismissKeyboard()
        }
        next.tap()
        shot("onboarding-4-alarm")
        next.tap()
        shot("onboarding-5-permission")
        next.tap()

        // AlarmKit 的系统权限弹窗由 SpringBoard 显示
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        if alert.waitForExistence(timeout: 5) {
            shot("onboarding-6-alarmkit-permission")
            alert.buttons.element(boundBy: alert.buttons.count - 1).tap() // 最后一个按钮是"允许"
        } else {
            record("没有出现 AlarmKit 权限弹窗")
        }

        // 计划书第 7 节：新手引导结束后展示一次付费墙
        let later = app.buttons["paywall.later"]
        if later.waitForExistence(timeout: 5) {
            shot("onboarding-7-paywall")
            later.tap()
        } else {
            record("新手引导结束后没有出现付费墙")
        }
    }

    private func room() {
        tab("tab.room")
        let cat = app.descendants(matching: .any)["room.cat"]
        XCTAssertTrue(cat.waitForExistence(timeout: 5), "房间里没有猫")
        dismissGiftIfShown()
        shot("room-1")
        if cat.exists {
            cat.tap()
            shot("room-2-petted")
        }
    }

    private func alarms() {
        tab("tab.alarms")
        shot("alarms-1-list")
        XCTAssertTrue(app.staticTexts[L("alarms.repeat.everyday")].exists, "新手引导设的闹钟应该是每天响")

        // 打开新手引导时设的闹钟
        let firstRow = app.buttons.matching(identifier: "alarms.row").firstMatch
        if firstRow.waitForExistence(timeout: 3) {
            firstRow.tap()
            if app.buttons["alarms.cancel"].waitForExistence(timeout: 3) {
                shot("alarms-2-edit")
                app.buttons["alarms.cancel"].tap()
            } else {
                record("点闹钟没有打开编辑页")
            }
        } else {
            record("闹钟列表是空的：新手引导设的闹钟没保存？")
        }

        // 免费用户只能有 1 个闹钟：再加一个应该提示升级
        app.buttons["alarms.add"].tap()
        if app.buttons["alarms.save"].waitForExistence(timeout: 3) {
            shot("alarms-3-new")
            app.buttons["alarms.save"].tap()
            let limit = app.alerts.firstMatch
            if limit.waitForExistence(timeout: 3) {
                shot("alarms-4-limit")
                let upgrade = limit.buttons[L("paywall.title")]
                if upgrade.exists {
                    upgrade.tap()
                    if app.buttons["paywall.later"].waitForExistence(timeout: 3) {
                        shot("alarms-5-paywall")
                        app.buttons["paywall.later"].tap()
                    } else {
                        record("闹钟数量提示里点升级，没有出现付费墙")
                    }
                } else {
                    limit.buttons.firstMatch.tap()
                }
            } else {
                record("添加第 2 个闹钟没有出现数量限制提示")
                shot("alarms-4-after-save")
            }
        } else {
            record("点 + 没有打开新闹钟页")
        }
    }

    private func shop() {
        tab("tab.shop")
        shot("shop-1")
        // 今日推荐：点第一件，看看它摆在房间里的样子
        let pick = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'shop.pick.'")).firstMatch
        if pick.waitForExistence(timeout: 3) {
            pick.tap()
            if app.buttons["shop.sheet.close"].waitForExistence(timeout: 3) {
                shot("shop-1b-preview")
                app.buttons["shop.sheet.close"].tap()
            } else {
                record("点今日推荐没有打开详情")
            }
        } else {
            record("商店里没有今日推荐")
        }
        buy("cardboard_box")
        buy("rug_round")
        shot("shop-2-bought")
        buy("cat_tree")
        buy("pudding_sofa")
        shot("shop-3-scrolled")
        // 剩 5 条小鱼干，鱼缸（110）买不起
        let tank = app.buttons["shop.buy.furniture.fish_tank"]
        if reveal(tank) {
            tank.tap()
            let alert = app.alerts.firstMatch
            if alert.waitForExistence(timeout: 2) {
                shot("shop-4-not-enough-fish")
                alert.buttons.firstMatch.tap()
            } else {
                record("小鱼干不够时没有提示")
            }
        }
    }

    /// 商店是两栏的网格，卡片滑到屏幕里才会出现：先往下找，找不到再往上找。
    private func reveal(_ element: XCUIElement) -> Bool {
        if element.waitForExistence(timeout: 1), element.isHittable { return true }
        for _ in 0..<8 {
            app.swipeUp()
            if element.exists, element.isHittable { return true }
        }
        for _ in 0..<12 {
            app.swipeDown()
            if element.exists, element.isHittable { return true }
        }
        return false
    }

    private func buy(_ key: String) {
        let button = app.buttons["shop.buy.furniture.\(key)"]
        guard reveal(button) else {
            record("商店里找不到 \(key) 的购买按钮")
            return
        }
        button.tap()
        if app.alerts.firstMatch.waitForExistence(timeout: 1) {
            record("买 \(key) 时弹出了提示（小鱼干不够？）")
            app.alerts.firstMatch.buttons.firstMatch.tap()
        }
    }

    /// 买完家具回到房间：布丁在最后买的沙发旁边；进入布置模式，拖动沙发、收起猫爬架、再摆回来。
    private func decorate() {
        tab("tab.room")
        let sofa = app.descendants(matching: .any)["room.furniture.furniture.pudding_sofa"]
        XCTAssertTrue(sofa.waitForExistence(timeout: 5), "买的沙发没出现在房间里")
        shot("room-3-furnished")

        let edit = app.buttons["room.edit"]
        guard edit.waitForExistence(timeout: 3) else {
            XCTFail("找不到布置按钮")
            return
        }
        edit.tap()
        shot("room-4-decorate")

        if sofa.exists {
            let from = sofa.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
            let to = from.withOffset(CGVector(dx: 90, dy: 40))
            from.press(forDuration: 0.2, thenDragTo: to)
            shot("room-5-dragged-sofa")
        }

        let putAway = app.buttons["room.putAway.furniture.cat_tree"]
        if putAway.waitForExistence(timeout: 2) {
            putAway.tap()
            XCTAssertTrue(app.buttons["room.tray.furniture.cat_tree"].waitForExistence(timeout: 2), "收起的猫爬架没出现在下面一栏")
            shot("room-6-put-away")
            app.buttons["room.tray.furniture.cat_tree"].tap()
            shot("room-7-placed-back")
        } else {
            record("布置模式下找不到猫爬架的收起按钮")
        }

        edit.tap()
        shot("room-8-done")
    }

    private func backpack() {
        tab("tab.backpack")
        shot("backpack-1")
    }

    /// 好感度和互动：重新打开 App，把好感调到"亲近"（`-debugBond 600`）——她会跑过来迎接；
    /// 摸一摸、喂零食、逗猫、慢眨眼，最后看收藏册里的回忆。
    private func bond() {
        app.terminate()
        app.launchArguments += ["-debugBond", "600"]
        app.launch()
        tab("tab.room")
        dismissGiftIfShown()
        let cat = app.descendants(matching: .any)["room.cat"]
        XCTAssertTrue(cat.waitForExistence(timeout: 5), "房间里没有猫")
        shot("bond-1-greeting")
        let treat = app.buttons["room.action.treat"]
        guard treat.waitForExistence(timeout: 3) else {
            record("房间里没有陪她玩的按钮（她现在不是白天待机？）")
            return
        }
        Thread.sleep(forTimeInterval: 2) // 等她跑到前面

        // 摸：在头顶上横着摸一下（模拟的拖动只有起点和终点，终点要落在头上）
        cat.coordinate(withNormalizedOffset: CGVector(dx: 0.36, dy: 0.12))
            .press(forDuration: 0.05, thenDragTo: cat.coordinate(withNormalizedOffset: CGVector(dx: 0.62, dy: 0.14)))
        shot("bond-2-petted", wait: 0.3)

        treat.tap()
        Thread.sleep(forTimeInterval: 2.5)
        shot("bond-3-treat")
        Thread.sleep(forTimeInterval: 7)

        let play = app.buttons["room.action.play"]
        if play.waitForExistence(timeout: 3) {
            play.tap()
            shot("bond-4-play")
            let window = app.windows.firstMatch
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5))
                .press(forDuration: 0.1, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: 0.55)))
            shot("bond-5-chase", wait: 1.2)
            Thread.sleep(forTimeInterval: 1.2)
            shot("bond-6-pounce", wait: 0.4)
            let done = app.buttons["room.play.done"]
            if done.waitForExistence(timeout: 2) { done.tap() }
        } else {
            record("找不到逗猫按钮")
        }

        let blink = app.buttons["room.action.blink"]
        if blink.waitForExistence(timeout: 3), blink.isEnabled {
            blink.tap()
            shot("bond-7-blink", wait: 0.3)
            Thread.sleep(forTimeInterval: 1.0)
            shot("bond-8-blink-back", wait: 0.1)
        } else {
            record("慢眨眼按钮不能点（她在睡觉？）")
        }

        tab("tab.backpack")
        let memories = app.buttons["backpack.tab.memories"]
        if memories.waitForExistence(timeout: 3) {
            memories.tap()
            shot("bond-9-memories")
        } else {
            record("收藏册里没有回忆页")
        }
        cats()
    }

    /// 更多的猫：点左上角的名字打开"我的猫"，领养暹罗（已经和布丁熟了，不花钱）和长毛猫（300 小鱼干），
    /// 看她们进房间、摸一摸，再换回布丁。
    private func cats() {
        tab("tab.room")
        let name = app.buttons["room.cats"]
        guard name.waitForExistence(timeout: 3) else {
            record("房间左上角没有名字按钮")
            return
        }
        for kind in ["siamese", "fluffy"] {
            name.tap()
            let adopt = app.buttons["cats.adopt.\(kind)"]
            guard adopt.waitForExistence(timeout: 3) else {
                record("我的猫里没有 \(kind) 的领养按钮")
                shot("cats-\(kind)-missing")
                if app.buttons["cats.done"].exists { app.buttons["cats.done"].tap() }
                continue
            }
            shot("cats-\(kind)-1-sheet")
            adopt.tap()
            let cat = app.descendants(matching: .any)["room.cat"]
            XCTAssertTrue(cat.waitForExistence(timeout: 5), "领养以后房间里没有猫")
            shot("cats-\(kind)-2-arrived", wait: 2.5)
            if cat.exists {
                cat.tap()
                shot("cats-\(kind)-3-tapped", wait: 0.5)
                // 喂一份零食：新来的猫怕生，也会过来吃
                let treat = app.buttons["room.action.treat"]
                if treat.waitForExistence(timeout: 2) {
                    treat.tap()
                    shot("cats-\(kind)-4-treat", wait: 3.5)
                    Thread.sleep(forTimeInterval: 6)
                }
            }
        }
        name.tap()
        shot("cats-3-all")
        let back = app.buttons["cats.switch.pudding"]
        if back.waitForExistence(timeout: 3) {
            back.tap()
            shot("cats-4-pudding-back", wait: 2)
        } else {
            record("我的猫里不能换回布丁")
        }
    }

    /// 窗外：点窗户打开小卡片，打开"跟着你那里的天气"，允许位置权限，看到日出日落。
    /// 模拟器里没有开通 WeatherKit，天气拿不到是预期的：这里看的是位置这条路和"拿不到天气"时的说明。
    private func window() {
        tab("tab.room")
        let pane = app.descendants(matching: .any)["room.window"]
        guard pane.waitForExistence(timeout: 3) else {
            record("房间里的窗户点不到")
            return
        }
        pane.tap()
        let toggle = app.switches["window.follow"]
        guard toggle.waitForExistence(timeout: 3) else {
            record("没有出现窗外卡片")
            shot("window-missing")
            return
        }
        shot("window-1-off")
        // SwiftUI 的开关：点里面那个真正的开关（点整行的中间不会拨动它）
        let knob = toggle.switches.firstMatch
        if knob.exists { knob.tap() } else { toggle.tap() }
        // 位置权限的系统弹窗由 SpringBoard 显示：三个按钮里中间那个是"使用 App 时允许"
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        if alert.waitForExistence(timeout: 5) {
            shot("window-2-location-permission")
            alert.buttons.element(boundBy: min(1, alert.buttons.count - 1)).tap()
        } else {
            record("没有出现位置权限弹窗")
        }
        let sun = app.descendants(matching: .any)["window.sun"]
        if sun.waitForExistence(timeout: 30) {
            shot("window-3-following", wait: 1.5)
        } else {
            record("打开以后没有显示日出日落")
            shot("window-3-no-sun")
        }
        if app.buttons["window.done"].exists { app.buttons["window.done"].tap() }
        shot("window-4-room", wait: 1.5)
    }

    // MARK: - 工具

    private func tab(_ key: String) {
        let button = app.tabBars.buttons[L(key)]
        if button.waitForExistence(timeout: 5) {
            button.tap()
        } else {
            XCTFail("找不到标签：\(L(key))")
        }
    }

    private func dismissGiftIfShown() {
        let collect = app.buttons[L("wake.gift.collect")]
        if collect.waitForExistence(timeout: 1) {
            shot("room-0-gift")
            collect.tap()
        }
    }

    private func dismissKeyboard() {
        // 模拟器连着 Mac 键盘（"硬件键盘"）时，软键盘在屏幕外面点不到，直接输入回车
        let returnKey = app.keyboards.buttons["Return"]
        if returnKey.exists, returnKey.isHittable {
            returnKey.tap()
        } else {
            app.typeText("\n")
        }
    }

    /// 截图，按顺序编号，导出时用名字作为文件名。
    private func shot(_ name: String, wait: TimeInterval = 0.8) {
        Thread.sleep(forTimeInterval: wait) // 等 SwiftUI 的过渡动画播完，不然会拍到两页叠在一起
        shotIndex += 1
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = String(format: "%02d-%@", shotIndex, name)
        attachment.lifetime = .keepAlways
        add(attachment)
        checkNoRawKeys(name)
    }

    /// 屏幕上不应该出现没翻译的 key（例如 "rarity.common"）：所有 key 都是 "小写单词.单词" 的形式。
    private func checkNoRawKeys(_ screen: String) {
        let tree = app.debugDescription
        let regex = try! NSRegularExpression(pattern: "label: '([a-z]+(?:\\.[a-zA-Z0-9]+)+)'")
        let keys = Set(regex.matches(in: tree, range: NSRange(tree.startIndex..., in: tree)).map {
            String(tree[Range($0.range(at: 1), in: tree)!])
        })
        for key in keys.sorted() {
            XCTFail("\(screen)：屏幕上显示了没翻译的 key \(key)")
        }
    }

    /// 记一条"看起来不对"的观察，不中断走查。
    private func record(_ message: String) {
        let note = XCTAttachment(string: message)
        note.name = String(format: "%02d-note", shotIndex)
        note.lifetime = .keepAlways
        add(note)
        XCTContext.runActivity(named: "⚠️ \(message)") { _ in }
    }

    /// 按当前语言查 App 的文字（标签栏、弹窗按钮这些没法加 identifier 的地方用）。
    private func L(_ key: String) -> String {
        let bundle = Bundle(for: WalkthroughTests.self)
        guard let path = bundle.path(forResource: language, ofType: "lproj"),
              let localized = Bundle(path: path) else { return key }
        return localized.localizedString(forKey: key, value: key, table: nil)
    }

    private static func locale(for language: String) -> String {
        switch language {
        case "zh-Hans": "zh_CN"
        case "zh-Hant": "zh_TW"
        case "ja": "ja_JP"
        default: "en_US"
        }
    }
}
