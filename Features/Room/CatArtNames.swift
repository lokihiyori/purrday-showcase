import CatWorld

/// 猫的图片资源叫什么名字。App 和小组件共用（小组件的 target 里也有这个文件），所以这里不能依赖界面代码。
enum CatArtNames {
    /// 姿势图的前缀：布丁是 cat-pose-，其他猫是 cat-<种类>-pose-
    static func posePrefix(_ kind: CatKind) -> String {
        kind == .pudding ? "cat-pose-" : "cat-\(kind.rawValue)-pose-"
    }

    /// 姿势对应的图名（不带前缀）
    static func poseFile(_ pose: CatPose) -> String? {
        switch pose {
        case .sit: "sit"
        case .groom: "groom"
        case .loaf: "loaf"
        case .curl, .purr: "curl"
        case .sitBack: "sitback"
        case .sprawl: "sprawl"
        case .stretch: "stretch"
        case .stand: "stand"
        case .eat: "eat"
        case .bellyUp: "bellyup"
        case .rub: "rub"
        case .chinUp: "chinup"
        case .knead: "knead"
        case .lieSide: "lieside"
        case .headTilt: "headtilt"
        case .crouch: "crouch"
        case .leap: "leap"
        case .bat: "bat"
        case .lickLips: "licklips"
        case .meow: "meow"
        case .annoyed: "annoyed"
        case .startled: "startled"
        case .sleepBelly: "sleepbelly"
        case .run: "run"
        case .toyKick: "toykick"
        case .reach: "reach"
        case .stateArt: nil
        }
    }

    static func pose(_ pose: CatPose, kind: CatKind) -> String? {
        poseFile(pose).map { posePrefix(kind) + $0 }
    }

    /// 特殊时刻的整张画（cat-meow、cat-gift……）。布丁的叫 cat-<名字>；别的猫有专属画的叫 cat-<种类>-<名字>，
    /// 没有的（idle、sleep、stretch）用她自己的姿势图。
    static let exclusiveStills: Set<String> = ["cat-meow", "cat-gift", "cat-knead", "cat-push-cup", "cat-phone", "cat-purr",
                                               "cat-petted", "cat-focus", "cat-read", "cat-walk"]

    static func still(_ still: String, kind: CatKind) -> String {
        guard kind != .pudding else { return still }
        if exclusiveStills.contains(still) { return "cat-\(kind.rawValue)-" + still.dropFirst(4) }
        let pose = switch still {
        case "cat-sleep": "curl"
        case "cat-stretch": "stretch"
        default: "sit"
        }
        return posePrefix(kind) + pose
    }
}
