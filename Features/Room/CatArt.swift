import CatEngine

/// 猫的状态 → 形象稿资源名（Resources/Assets.xcassets/Cat）。以后换成 Rive 时，这里改成 Rive 状态名。
enum CatArt {
    static func assetName(for cat: CatSnapshot, petted: Bool = false) -> String {
        assetName(state: cat.state, mischief: cat.mischief, petted: petted)
    }

    static func assetName(state: CatState, mischief: MischiefKind?, petted: Bool = false) -> String {
        if petted { return "cat-petted" }
        switch state {
        case .sleepingAtNight: return "cat-sleep"
        case .wakingUp: return "cat-meow"
        case .givingGift: return "cat-gift"
        case .makingMischief:
            switch mischief ?? .stepOnFace {
            case .stepOnFace: return "cat-knead"
            case .pushCup: return "cat-push-cup"
            case .lieOnPhone: return "cat-phone"
            }
        case .idleDaytime: return "cat-idle"
        case .accompanying(.focus): return "cat-focus"
        case .accompanying(.read): return "cat-read"
        case .accompanying(.move): return "cat-walk"
        case .purringAtBedtime: return "cat-purr"
        }
    }

    /// 状态名的本地化 key（无障碍和小组件用）。
    static func stateKey(_ state: CatState) -> String {
        switch state {
        case .sleepingAtNight: "state.sleepingAtNight"
        case .wakingUp: "state.wakingUp"
        case .givingGift: "state.givingGift"
        case .makingMischief: "state.makingMischief"
        case .idleDaytime: "state.idleDaytime"
        case .accompanying: "state.accompanying"
        case .purringAtBedtime: "state.purringAtBedtime"
        }
    }
}
