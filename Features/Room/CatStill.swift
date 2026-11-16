import CatWorld
import SwiftUI

/// 特殊时刻的整张画（cat-meow、cat-gift……）按猫来取（规则在 `CatArtNames.still`）。
enum CatStill {
    static func name(_ still: String, kind: CatKind) -> String { CatArtNames.still(still, kind: kind) }
}

/// 一张猫的画，按现在陪着你的那只猫来。
struct CatStillImage: View {
    let still: String
    let kind: CatKind

    var body: some View {
        Image(CatStill.name(still, kind: kind))
            .resizable()
            .scaledToFit()
    }
}

/// 每只猫的名字（用户自己起的，存在 UserDefaults）。布丁沿用最早的 "catName"。
enum CatNames {
    static func key(_ kind: CatKind) -> String {
        kind == .pudding ? "catName" : "catName.\(kind.rawValue)"
    }

    static func defaultName(_ kind: CatKind) -> String {
        switch kind {
        case .pudding: String(localized: "onboarding.name.placeholder")
        case .siamese: String(localized: "cats.siamese.name")
        case .fluffy: String(localized: "cats.fluffy.name")
        }
    }

    static func name(_ kind: CatKind) -> String {
        let saved = UserDefaults.standard.string(forKey: key(kind))?.trimmingCharacters(in: .whitespaces) ?? ""
        return saved.isEmpty ? defaultName(kind) : saved
    }
}
