import AVFoundation
import CatWorld

/// 猫的声音：叫、颤音、讨吃的、嘟囔、吓一跳、咔嚓咔嚓吃东西
/// （Resources/Sounds/cat-<猫>-<声音>-<序号>.m4a，由 design/sound/cat_sounds.py 生成）。
/// 每种猫的音调不一样（暹罗尖一点，长毛猫低一点）——是提前做进文件里的；同一种声音有几条就轮着放。
/// 用最基础的 AVAudioPlayer，并且放在后台队列：音频服务没响应时不会卡住界面。
/// 用 ambient 类别：跟着静音键，不打断你在听的音乐。找不到文件就不出声。
final class CatVoice: @unchecked Sendable {
    static let shared = CatVoice()
    /// 设置里的开关（"我的猫"页面最下面）
    static let enabledKey = "catSounds"

    private let queue = DispatchQueue(label: "purrday.cat-voice", qos: .userInitiated)
    // 下面这些只在 queue 上用
    private var players: [AVAudioPlayer] = []
    private var lastVariant: [String: Int] = [:]

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) == nil || UserDefaults.standard.bool(forKey: enabledKey)
    }

    /// 每种声音有几条录音、放多大声
    static func recipe(_ sound: CatSound) -> (variants: Int, volume: Float) {
        switch sound {
        case .meow: (2, 0.8)
        case .trill: (2, 0.75)
        case .ask: (1, 0.85)
        case .grumble: (1, 0.7)
        case .squeak: (1, 0.6)
        case .crunch: (1, 0.6)
        }
    }

    /// 资源名。吃东西的咔嚓声三只猫共用
    static func file(_ sound: CatSound, kind: CatKind, variant: Int) -> String {
        sound == .crunch ? "cat-crunch-\(variant)" : "cat-\(kind.rawValue)-\(sound.rawValue)-\(variant)"
    }

    /// 这只猫的呼噜声
    static func purrFile(_ kind: CatKind) -> String { "cat-\(kind.rawValue)-purr-1" }

    func play(_ sound: CatSound, kind: CatKind) {
        guard Self.isEnabled else { return }
        queue.async { [self] in
            let recipe = Self.recipe(sound)
            // 轮着放，不连着放同一条
            let key = "\(kind.rawValue)-\(sound.rawValue)"
            let variant = (lastVariant[key] ?? 0) % recipe.variants + 1
            lastVariant[key] = variant
            guard let url = Bundle.main.url(forResource: Self.file(sound, kind: kind, variant: variant), withExtension: "m4a"),
                  let player = try? AVAudioPlayer(contentsOf: url) else { return }
            Self.prepareSession()
            player.volume = recipe.volume
            player.enableRate = true
            player.rate = Float.random(in: 0.96...1.04) // 每次快慢差一点点，听起来不重复
            player.play()
            players.removeAll { !$0.isPlaying }
            players.append(player)
        }
    }

    /// 睡前模式在放声音（playback）时不改它的设置
    static func prepareSession() {
        let session = AVAudioSession.sharedInstance()
        if session.category != .playback {
            try? session.setCategory(.ambient, options: [.mixWithOthers])
            try? session.setActive(true)
        }
    }
}
