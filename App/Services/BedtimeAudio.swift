import AVFoundation
import CatEngine
import CatWorld

/// 睡前模式放什么：她的呼噜声，可以再叠一层环境音（雨声 / 壁炉 / 海浪），两层各有音量。存在 UserDefaults 里。
struct BedtimeMix: Equatable {
    enum Ambient: String, CaseIterable {
        case none, rain, fireplace, ocean
    }

    var ambient: Ambient = .none
    var purrVolume = 0.7
    var ambientVolume = 0.5

    static let ambientKey = "bedtime.ambient"
    static let purrVolumeKey = "bedtime.purrVolume"
    static let ambientVolumeKey = "bedtime.ambientVolume"
    /// 定时结束前多久开始慢慢变小
    static let fadeOut: TimeInterval = 30

    static func saved(_ defaults: UserDefaults = .standard) -> BedtimeMix {
        var mix = BedtimeMix()
        if let raw = defaults.string(forKey: ambientKey), let ambient = Ambient(rawValue: raw) { mix.ambient = ambient }
        if defaults.object(forKey: purrVolumeKey) != nil { mix.purrVolume = defaults.double(forKey: purrVolumeKey) }
        if defaults.object(forKey: ambientVolumeKey) != nil { mix.ambientVolume = defaults.double(forKey: ambientVolumeKey) }
        return mix
    }

    /// 离定时结束还有 `remaining` 秒时的整体音量（最后半分钟慢慢变小，不会突然没声）
    static func gain(remaining: TimeInterval) -> Double {
        min(max(remaining / fadeOut, 0), 1)
    }
}

/// 睡前模式的声音 + 睡眠定时器：她的呼噜声和一层环境音同时放（两个播放器），可以边放边调。
///
/// 音频在 Resources/Sounds。呼噜是真实录音（cat-<猫>-purr-1，没有就用合成的 purr）；
/// 雨声、壁炉、海浪也是真实录音（CC0，来源见 design/sound/README.md），做成了无缝循环。
@MainActor
final class BedtimeAudio {
    private var purr: AVAudioPlayer?
    private var ambient: AVAudioPlayer?
    private var ambientName: String?
    private var endsAt: Date?
    private var timer: Task<Void, Never>?

    /// 执行 CatWorld 输出的音频副作用；定时结束时调用 `onTimerEnd`（App 据此写 bedtimeTimerEnded 事件）。
    func apply(_ effects: [CatEffect], kind: CatKind = .pudding, onTimerEnd: @escaping @MainActor () -> Void) {
        for effect in effects {
            switch effect {
            case let .startBedtimeAudio(endsAt):
                start(kind: kind, until: endsAt, onTimerEnd: onTimerEnd)
            case .stopBedtimeAudio:
                stop()
            default:
                break
            }
        }
    }

    private func start(kind: CatKind, until endsAt: Date, onTimerEnd: @escaping @MainActor () -> Void) {
        stop()
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
        self.endsAt = endsAt
        purr = Self.loop(Bundle.main.url(forResource: CatVoice.purrFile(kind), withExtension: "m4a") != nil ? CatVoice.purrFile(kind) : "purr")
        purr?.play()
        refresh()
        timer = Task { [weak self] in
            // 每秒看一次：最后半分钟慢慢变小，到时间停下
            while !Task.isCancelled {
                let remaining = endsAt.timeIntervalSince(RoomClock.now())
                if remaining <= 0 { break }
                if remaining <= BedtimeMix.fadeOut + 1 { self?.refresh() }
                try? await Task.sleep(for: .seconds(min(1, remaining)))
            }
            guard !Task.isCancelled else { return }
            self?.stop()
            onTimerEnd()
        }
    }

    /// 按现在保存的设置调整：换环境音、调两层的音量。没在放时什么都不做。
    func refresh() {
        guard purr != nil, let endsAt else { return }
        let mix = BedtimeMix.saved()
        let gain = BedtimeMix.gain(remaining: endsAt.timeIntervalSince(RoomClock.now()))
        purr?.setVolume(Float(mix.purrVolume * gain), fadeDuration: 0.4)
        let wanted = mix.ambient == .none ? nil : mix.ambient.rawValue
        if wanted != ambientName {
            ambient?.stop()
            ambient = wanted.flatMap(Self.loop)
            ambient?.volume = 0
            ambient?.play()
            ambientName = wanted
        }
        ambient?.setVolume(Float(mix.ambientVolume * gain), fadeDuration: 0.4)
    }

    private static func loop(_ name: String) -> AVAudioPlayer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "m4a"), let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.numberOfLoops = -1
        player.volume = 0
        return player
    }

    func stop() {
        purr?.stop()
        ambient?.stop()
        purr = nil
        ambient = nil
        ambientName = nil
        endsAt = nil
        timer?.cancel()
        timer = nil
    }
}
