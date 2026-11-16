import CatEngine
import Economy
import Foundation
import Testing
@testable import CatWorld

/// 检查 App 的 `Resources/Localizable.xcstrings`：Core 里引用到的 key 都在，四种语言都翻译了，占位符一致。
/// `Resources/InfoPlist.xcstrings`（系统权限弹窗等 Info.plist 文字）也要四种语言都翻译。
@Suite("本地化 Localizable.xcstrings")
struct LocalizationTests {
    static let languages = ["en", "zh-Hans", "zh-Hant", "ja"]

    struct StringsFile: Decodable {
        struct Entry: Decodable {
            struct Localization: Decodable {
                struct Unit: Decodable { var state: String; var value: String }
                var stringUnit: Unit?
            }
            var localizations: [String: Localization]?
        }
        var sourceLanguage: String
        var strings: [String: Entry]
    }

    static func load(_ name: String = "Localizable") throws -> StringsFile {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/\(name).xcstrings")
        return try JSONDecoder().decode(StringsFile.self, from: Data(contentsOf: url))
    }

    static func placeholders(_ s: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: "%(?:\\d+\\$)?(?:lld|ld|d|@|f)")
        return regex.matches(in: s, range: NSRange(s.startIndex..., in: s))
            .map { String(s[Range($0.range, in: s)!]) }.sorted()
    }

    @Test("每个 key 四种语言都已翻译，占位符一致", arguments: ["Localizable", "InfoPlist"])
    func allTranslated(_ name: String) throws {
        let file = try Self.load(name)
        #expect(file.sourceLanguage == "en")
        for (key, entry) in file.strings {
            let units = Self.languages.map { entry.localizations?[$0]?.stringUnit }
            #expect(units.allSatisfy { $0?.state == "translated" && !($0?.value.isEmpty ?? true) }, "\(key) 有语言没翻译")
            let english = Self.placeholders(units[0]?.value ?? "")
            for (language, unit) in zip(Self.languages, units) {
                #expect(Self.placeholders(unit?.value ?? "") == english, "\(key) 的 \(language) 占位符和英文不一致")
            }
        }
    }

    @Test("AlarmKit 权限弹窗的说明在 InfoPlist.xcstrings 里")
    func permissionDescriptions() throws {
        let keys = Set(try Self.load("InfoPlist").strings.keys)
        #expect(keys.contains("NSAlarmKitUsageDescription"))
    }

    @Test("目录里每件物品和每个稀有度都有名字")
    func catalogNames() throws {
        let keys = Set(try Self.load().strings.keys)
        let catalog = try Catalog.bundled()
        for item in catalog.items {
            #expect(keys.contains(item.nameKey), "缺少 \(item.nameKey)")
        }
        for rarity in Rarity.allCases {
            #expect(keys.contains("rarity.\(rarity.rawValue)"))
        }
    }

    @Test("猫的每个状态都有名字")
    func stateNames() throws {
        let keys = Set(try Self.load().strings.keys)
        for name in ["sleepingAtNight", "wakingUp", "givingGift", "makingMischief", "idleDaytime", "accompanying", "purringAtBedtime"] {
            #expect(keys.contains("state.\(name)"))
        }
    }

    @Test("布丁的每件日常活动都有名字（无障碍朗读用）")
    func activityNames() throws {
        let keys = Set(try Self.load().strings.keys)
        for activity in CatActivity.allCases {
            #expect(keys.contains("activity.\(activity.rawValue)"), "\(activity)")
        }
    }

    @Test("你不在的时候：每件事都有一句话，还有标题和时长")
    func awayKeys() throws {
        let keys = Set(try Self.load().strings.keys)
        for activity in CatActivity.allCases {
            #expect(keys.contains("away.\(activity.rawValue)"), "\(activity)")
        }
        for key in ["away.title", "away.night", "away.hours", "away.minutes"] {
            #expect(keys.contains(key), "\(key)")
        }
    }

    @Test("台词数量和 CatScene.lineCount 对得上")
    func dialogueLines() throws {
        let keys = Set(try Self.load().strings.keys)
        for scene in CatScene.allCases {
            for key in scene.lineKeys { #expect(keys.contains(key), "缺少 \(key)") }
            #expect(!keys.contains("line.\(scene.rawValue).\(scene.lineCount + 1)"), "\(scene) 的台词比 lineCount 多")
        }
        let sceneNames = Set(CatScene.allCases.map(\.rawValue))
        for key in keys where key.hasPrefix("line.") {
            #expect(sceneNames.contains(key.split(separator: ".")[1].description), "\(key) 不属于任何场景")
        }
    }
}
