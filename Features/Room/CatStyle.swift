import CatWorld
import Foundation

/// 每种猫"怎么动"（docs/cat-life.md 4.3）。同一个反应，暹罗演得又快又大，长毛猫慢半拍、幅度小，布丁带一点肉肉的回弹。
/// 她们"做什么"的差别（爱挑哪种反应、爱做什么事）在 Core 的 `Temperament` 里。
struct CatStyle: Equatable {
    /// 动作的时长倍数（小于 1 更快）
    var tempo = 1.0
    /// 动作的幅度倍数（弯多少、跳多高）
    var amplitude = 1.0
    /// 回应前先愣多久（秒）
    var delay = 0.0
    /// 走路、跑的速度倍数
    var speed = 1.0
    /// 呼吸的周期倍数（大于 1 更慢更深）
    var breath = 1.0
    /// 换姿势时弹一下的幅度倍数
    var bounce = 1.0
    /// 换姿势时淡入淡出多久（秒）
    var fade = 0.22
    /// 你回来时她跑到面前待多久（秒）
    var greetingTime: TimeInterval = 20
    /// 隔多久再打开 App 算"你回来了"
    var greetAfter: TimeInterval = 15 * 60

    static func of(_ kind: CatKind) -> CatStyle {
        switch kind {
        case .pudding:
            // 圆滚滚：不快不慢，换姿势时肉肉地多弹一下
            CatStyle(bounce: 1.35)
        case .siamese:
            // 轻快：动作快、幅度大，走得快；一会儿不见就要来迎接，在你面前待得久
            CatStyle(tempo: 0.82, amplitude: 1.15, speed: 1.3, breath: 0.85, bounce: 0.8, fade: 0.16,
                     greetingTime: 35, greetAfter: 5 * 60)
        case .fluffy:
            // 慢悠悠：回应慢半拍，动作慢而沉、幅度小，走得慢，呼吸又慢又深
            CatStyle(tempo: 1.3, amplitude: 0.72, delay: 0.35, speed: 0.75, breath: 1.3, bounce: 0.6, fade: 0.3)
        }
    }
}
