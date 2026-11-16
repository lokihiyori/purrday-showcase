import AVFoundation
import CatWorld

/// 摸她舒服时的呼噜声（真实录音 cat-<猫>-purr-1；没有就用睡前模式那段合成的 purr）。
/// 淡入淡出，跟着反应动作的长短放。放在后台队列，音频服务没响应时不会卡住界面。
/// 用 ambient 类别：不打断你在听的音乐，静音键打开时不出声。睡前模式正在放声音时不抢。
final class PurrSound: @unchecked Sendable {
    static let shared = PurrSound()
    private let queue = DispatchQueue(label: "purrday.purr", qos: .userInitiated)
    // 下面这些只在 queue 上用
    private var player: AVAudioPlayer?
    private var playing: String?
    private var generation = 0

    func purr(until end: Date, kind: CatKind) {
        guard CatVoice.isEnabled else { return }
        queue.async { [self] in
            if AVAudioSession.sharedInstance().category == .playback, player == nil { return } // 睡前模式在放声音
            let name = Bundle.main.url(forResource: CatVoice.purrFile(kind), withExtension: "m4a") != nil ? CatVoice.purrFile(kind) : "purr"
            if player == nil || playing != name {
                player?.stop()
                guard let url = Bundle.main.url(forResource: name, withExtension: "m4a"),
                      let fresh = try? AVAudioPlayer(contentsOf: url) else { return }
                CatVoice.prepareSession()
                fresh.numberOfLoops = -1
                fresh.volume = 0
                fresh.currentTime = Double.random(in: 0..<max(0.1, fresh.duration * 0.8))
                fresh.play()
                player = fresh
                playing = name
            }
            player?.setVolume(0.55, fadeDuration: 0.35)
            generation += 1
            let mine = generation
            // 到时间淡出、停下；中间又被摸了（generation 变了）就接着放
            queue.asyncAfter(deadline: .now() + max(0.2, end.timeIntervalSinceNow)) { [self] in
                guard generation == mine else { return }
                player?.setVolume(0, fadeDuration: 0.6)
                queue.asyncAfter(deadline: .now() + 0.7) { [self] in
                    guard generation == mine else { return }
                    player?.stop()
                    player = nil
                    playing = nil
                }
            }
        }
    }
}
