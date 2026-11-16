import CatWorld
import SwiftUI

/// 房间里跟着真实时间变的东西：窗外的天空、地板上的阳光、早晚的光线、夜里的灯光。
enum RoomAtmosphere {
    /// 当地时间的小时数（带小数）
    static func hour(_ date: Date, calendar: Calendar = .current) -> Double {
        let c = calendar.dateComponents([.hour, .minute, .second], from: date)
        return Double(c.hour ?? 12) + Double(c.minute ?? 0) / 60 + Double(c.second ?? 0) / 3600
    }

    struct RGB: Equatable {
        var r, g, b: Double
        var color: Color { Color(red: r, green: g, blue: b) }
        func mixed(_ other: RGB, _ t: Double) -> RGB {
            RGB(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
        }
    }

    /// 按小时插值的关键帧
    static func interpolate(_ keys: [(Double, RGB)], at hour: Double) -> RGB {
        guard let first = keys.first, let last = keys.last else { return RGB(r: 1, g: 1, b: 1) }
        if hour <= first.0 { return first.1 }
        for (a, b) in zip(keys, keys.dropFirst()) where hour <= b.0 {
            return a.1.mixed(b.1, (hour - a.0) / (b.0 - a.0))
        }
        return last.1
    }

    private static let night = RGB(r: 0.13, g: 0.16, b: 0.29)
    /// 天空的上下两种颜色
    static func sky(at hour: Double) -> (top: RGB, bottom: RGB) {
        let top = interpolate([
            (0, night), (5, night), (6.5, RGB(r: 0.62, g: 0.70, b: 0.86)), (8, RGB(r: 0.55, g: 0.76, b: 0.92)),
            (16, RGB(r: 0.55, g: 0.76, b: 0.92)), (18, RGB(r: 0.56, g: 0.55, b: 0.78)), (19.5, RGB(r: 0.25, g: 0.27, b: 0.48)),
            (21, night), (24, night),
        ], at: hour)
        let bottom = interpolate([
            (0, RGB(r: 0.20, g: 0.23, b: 0.40)), (5, RGB(r: 0.20, g: 0.23, b: 0.40)), (6.5, RGB(r: 0.98, g: 0.80, b: 0.68)),
            (8, RGB(r: 0.86, g: 0.93, b: 0.97)), (16, RGB(r: 0.86, g: 0.93, b: 0.97)), (18, RGB(r: 0.99, g: 0.72, b: 0.52)),
            (19.5, RGB(r: 0.82, g: 0.52, b: 0.50)), (21, RGB(r: 0.20, g: 0.23, b: 0.40)), (24, RGB(r: 0.20, g: 0.23, b: 0.40)),
        ], at: hour)
        return (top, bottom)
    }

    /// 整个房间的光线（正片叠底）：白天是白色（不变），傍晚偏暖，夜里偏暗蓝
    static func light(at hour: Double) -> RGB {
        interpolate([
            (0, RGB(r: 0.45, g: 0.48, b: 0.70)), (5, RGB(r: 0.45, g: 0.48, b: 0.70)), (6.5, RGB(r: 0.96, g: 0.88, b: 0.84)),
            (8, RGB(r: 1, g: 1, b: 1)), (16, RGB(r: 1, g: 1, b: 1)), (17.5, RGB(r: 1.0, g: 0.90, b: 0.76)),
            (19, RGB(r: 0.80, g: 0.70, b: 0.78)), (20.5, RGB(r: 0.52, g: 0.54, b: 0.76)), (24, RGB(r: 0.45, g: 0.48, b: 0.70)),
        ], at: hour)
    }

    /// 天气对房间光线的影响（再乘上去）：阴天稍微灰一点，下雨更暗更冷，下雪偏白
    static func weatherTint(_ weather: Weather) -> RGB {
        switch weather {
        case .clear: RGB(r: 1, g: 1, b: 1)
        case .cloudy: RGB(r: 0.94, g: 0.94, b: 0.95)
        case .rain: RGB(r: 0.84, g: 0.87, b: 0.93)
        case .snow: RGB(r: 0.93, g: 0.95, b: 0.99)
        }
    }

    /// 天气对天空颜色的影响：往灰色靠多少、那种灰是什么颜色
    static func overcast(_ weather: Weather) -> (amount: Double, color: RGB) {
        switch weather {
        case .clear: (0, RGB(r: 1, g: 1, b: 1))
        case .cloudy: (0.55, RGB(r: 0.80, g: 0.82, b: 0.85))
        case .rain: (0.8, RGB(r: 0.60, g: 0.64, b: 0.70))
        case .snow: (0.9, RGB(r: 0.85, g: 0.86, b: 0.89))
        }
    }

    /// 夜里有多黑（0 白天，1 深夜）：决定开灯、星星
    static func darkness(at hour: Double) -> Double {
        let light = light(at: hour)
        return ((1 - (light.r + light.g + light.b) / 3) / 0.44).clamped(to: 0...1)
    }
}

/// 窗外：天空渐变、飘过的云、夜里的月亮和星星、偶尔飞过的小鸟；
/// 跟着天气和季节变（`CatWorld.weather`）：阴天云多天灰，下雨有雨丝，下雪飘雪花；
/// 晴天时春天飘花瓣、秋天落叶、夏天夜里有萤火虫。画在背景图后面，从透明的窗玻璃里看到。
struct WindowSky: View {
    let date: Date
    var weather: Weather = .clear
    var season: Season = .summer
    /// 画面钟点（`WorldStore.sceneHour`）；不给就用墙上的钟点
    var sceneHour: Double?

    var body: some View {
        let hour = sceneHour ?? RoomAtmosphere.hour(date)
        let clearSky = RoomAtmosphere.sky(at: hour)
        let dark = RoomAtmosphere.darkness(at: hour)
        let t = date.timeIntervalSinceReferenceDate
        let overcast = RoomAtmosphere.overcast(weather)
        // 阴雨天的灰也跟着昼夜变暗
        let gray = overcast.color.mixed(RoomAtmosphere.RGB(r: 0.16, g: 0.18, b: 0.27), dark)
        let sky = (top: clearSky.top.mixed(gray, overcast.amount), bottom: clearSky.bottom.mixed(gray, overcast.amount * 0.8))
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            context.fill(Path(rect), with: .linearGradient(
                Gradient(colors: [sky.top.color, sky.bottom.color]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            // 星星和月亮：天黑透了、没有云挡着才出来
            let night = ((dark - 0.5) * 2).clamped(to: 0...1) * (1 - overcast.amount)
            if night > 0 {
                // 星星和月亮（天黑透了才出来）
                let stars: [(Double, Double, Double)] = [(0.12, 0.15, 1.6), (0.3, 0.32, 1.1), (0.55, 0.12, 1.4), (0.78, 0.26, 1.2),
                                                         (0.88, 0.08, 1.0), (0.2, 0.55, 1.0), (0.66, 0.48, 1.3), (0.42, 0.7, 0.9)]
                for (i, (x, y, r)) in stars.enumerated() {
                    let twinkle = 0.6 + 0.4 * sin(t * 1.3 + Double(i) * 1.7)
                    context.fill(Path(ellipseIn: CGRect(x: x * size.width, y: y * size.height, width: r * 2, height: r * 2)),
                                 with: .color(.white.opacity(twinkle * night)))
                }
                let moon = CGRect(x: size.width * 0.66, y: size.height * 0.14, width: size.width * 0.16, height: size.width * 0.16)
                context.fill(Path(ellipseIn: moon.insetBy(dx: -6, dy: -6)), with: .color(.white.opacity(0.12 * night)))
                context.fill(Path(ellipseIn: moon), with: .color(Color(red: 1, green: 0.95, blue: 0.78).opacity(night)))
                context.fill(Path(ellipseIn: moon.offsetBy(dx: moon.width * 0.3, dy: -moon.height * 0.12)),
                             with: .color(sky.top.color.opacity(night)))
            }
            // 云：慢慢往右飘。阴雨天云更多、更大、更灰
            var clouds: [(Double, Double, Double)] = [(0.0, 0.22, 1.0), (0.45, 0.42, 0.75), (0.8, 0.12, 0.6)]
            if weather != .clear { clouds += [(0.2, 0.05, 1.5), (0.62, 0.3, 1.3), (0.33, 0.58, 1.1), (0.9, 0.5, 1.4)] }
            let cloudTone = weather == .rain ? 0.72 : (weather == .clear ? 1.0 : 0.9)
            for (offset, y, scale) in clouds {
                let span = size.width * 1.6
                let x = ((t * 3 * scale + offset * span).truncatingRemainder(dividingBy: span)) - size.width * 0.3
                cloud(&context, at: CGPoint(x: x, y: y * size.height), width: size.width * 0.34 * scale,
                      opacity: 0.85 - dark * 0.6, tone: cloudTone)
            }
            switch weather {
            case .rain: rain(&context, size: size, t: t, dark: dark)
            case .snow: snow(&context, size: size, t: t, dark: dark)
            case .clear: seasonal(&context, size: size, t: t, dark: dark)
            case .cloudy: break
            }
            // 晴朗的白天偶尔飞过一只小鸟（每 45 秒一次，飞 7 秒）
            let cycle = t.truncatingRemainder(dividingBy: 45)
            if dark < 0.4, cycle < 7, !weather.isFalling {
                let p = cycle / 7
                let bird = CGPoint(x: size.width * (1.1 - 1.3 * p), y: size.height * (0.35 + 0.1 * sin(p * 6)))
                let flap = sin(t * 14) * 3
                var path = Path()
                path.move(to: CGPoint(x: bird.x - 6, y: bird.y - flap))
                path.addQuadCurve(to: bird, control: CGPoint(x: bird.x - 3, y: bird.y - 4))
                path.addQuadCurve(to: CGPoint(x: bird.x + 6, y: bird.y - flap), control: CGPoint(x: bird.x + 3, y: bird.y - 4))
                context.stroke(path, with: .color(Color(red: 0.3, green: 0.25, blue: 0.25).opacity(0.8)), lineWidth: 1.4)
            }
        }
    }

    private func cloud(_ context: inout GraphicsContext, at point: CGPoint, width: Double, opacity: Double, tone: Double = 1) {
        let h = width * 0.32
        var path = Path()
        path.addEllipse(in: CGRect(x: point.x, y: point.y + h * 0.3, width: width, height: h * 0.7))
        path.addEllipse(in: CGRect(x: point.x + width * 0.18, y: point.y, width: width * 0.42, height: h))
        path.addEllipse(in: CGRect(x: point.x + width * 0.45, y: point.y + h * 0.12, width: width * 0.36, height: h * 0.8))
        context.fill(path, with: .color(Color(white: tone).opacity(max(0.15, opacity))))
    }

    /// 0–1 的固定"随机数"（同一个 i 每次一样）
    private static func noise(_ i: Int, _ salt: Double) -> Double {
        let x = sin(Double(i) * 12.9898 + salt * 78.233) * 43758.5453
        return x - x.rounded(.down)
    }

    /// 雨丝：两层（远的细而慢，近的粗而快），稍微斜着落
    private func rain(_ context: inout GraphicsContext, size: CGSize, t: Double, dark: Double) {
        let color = Color(red: 0.86, green: 0.91, blue: 0.97)
        for layer in 0..<2 {
            let count = layer == 0 ? 46 : 26
            let speed = layer == 0 ? 0.9 : 1.5
            let length = size.height * (layer == 0 ? 0.07 : 0.11)
            for i in 0..<count {
                let u = Self.noise(i, Double(layer) + 1)
                let phase = Self.noise(i, Double(layer) + 5)
                let v = (t * speed * (0.8 + 0.4 * phase) + phase).truncatingRemainder(dividingBy: 1)
                let x = u * size.width * 1.15 - v * size.width * 0.12
                let y = v * (size.height + length) - length
                var path = Path()
                path.move(to: CGPoint(x: x, y: y))
                path.addLine(to: CGPoint(x: x - length * 0.16, y: y + length))
                context.stroke(path, with: .color(color.opacity((layer == 0 ? 0.32 : 0.5) * (1 - dark * 0.45))),
                               style: StrokeStyle(lineWidth: layer == 0 ? 0.8 : 1.2, lineCap: .round))
            }
        }
    }

    /// 雪花：慢慢飘，左右晃
    private func snow(_ context: inout GraphicsContext, size: CGSize, t: Double, dark: Double) {
        for i in 0..<44 {
            let u = Self.noise(i, 2)
            let phase = Self.noise(i, 7)
            let r = 1.2 + Self.noise(i, 11) * 2.2
            let v = (t * (0.035 + 0.05 * phase) * (0.6 + r / 3.4) + phase).truncatingRemainder(dividingBy: 1)
            let x = u * size.width + sin(t * (0.5 + phase) + Double(i)) * size.width * 0.035
            let y = v * (size.height + 8) - 4
            context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                         with: .color(.white.opacity((0.55 + 0.4 * phase) * (1 - dark * 0.35))))
        }
    }

    /// 晴天时每个季节的小东西：春天飘花瓣，秋天落叶，夏天夜里的萤火虫
    private func seasonal(_ context: inout GraphicsContext, size: CGSize, t: Double, dark: Double) {
        switch season {
        case .spring, .autumn:
            guard dark < 0.7 else { return }
            let colors: [Color] = season == .spring
                ? [Color(red: 1, green: 0.80, blue: 0.86), Color(red: 1, green: 0.90, blue: 0.93)]
                : [Color(red: 0.90, green: 0.52, blue: 0.22), Color(red: 0.80, green: 0.36, blue: 0.20), Color(red: 0.93, green: 0.72, blue: 0.30)]
            for i in 0..<(season == .spring ? 9 : 7) {
                let u = Self.noise(i, 3)
                let phase = Self.noise(i, 9)
                let v = (t * (0.03 + 0.03 * phase) + phase).truncatingRemainder(dividingBy: 1)
                let x = u * size.width + sin(t * (0.7 + phase) + Double(i) * 2) * size.width * 0.08 + v * size.width * 0.15
                let y = v * (size.height + 12) - 6
                let w = season == .spring ? 4.0 : 6.5
                var leaf = context
                leaf.translateBy(x: x, y: y)
                leaf.rotate(by: .radians(t * (0.8 + phase) + Double(i)))
                leaf.fill(Path(ellipseIn: CGRect(x: -w / 2, y: -w * 0.3, width: w, height: w * 0.6)),
                          with: .color(colors[i % colors.count].opacity(0.9 * (1 - dark))))
            }
        case .summer:
            guard dark > 0.6 else { return }
            for i in 0..<6 {
                let phase = Self.noise(i, 4)
                let x = (0.15 + 0.7 * Self.noise(i, 6)) * size.width + sin(t * 0.3 * (0.5 + phase) + Double(i)) * size.width * 0.1
                let y = (0.45 + 0.45 * Self.noise(i, 8)) * size.height + cos(t * 0.25 * (0.6 + phase) + Double(i) * 2) * size.height * 0.06
                let glow = max(0, sin(t * (0.9 + phase) + Double(i) * 1.7))
                let color = Color(red: 0.95, green: 1, blue: 0.6)
                context.fill(Path(ellipseIn: CGRect(x: x - 5, y: y - 5, width: 10, height: 10)), with: .color(color.opacity(0.18 * glow * dark)))
                context.fill(Path(ellipseIn: CGRect(x: x - 1.5, y: y - 1.5, width: 3, height: 3)), with: .color(color.opacity(0.95 * glow * dark)))
            }
        case .winter:
            break
        }
    }
}

/// 窗户照进来的阳光：地板上一块窗格形状的光斑（`.floor`，画在家具下面），
/// 和从窗户斜照下来的光柱、光里飘着的灰尘（`.shaft`，盖在家具上面，很淡）。随时间从右往左移。
struct Sunbeam: View {
    enum Part { case floor, shaft }

    let center: RoomPoint
    let stage: CGSize
    let date: Date
    let part: Part

    var body: some View {
        let pane = RoomArt.windowPane
        let p = RoomPerspective.project(center, groundY: center.y, onWall: false)
        let bottomY = (center.y + 0.06) * stage.height
        let topY = (RoomGeometry.floorLine + 0.035) * stage.height
        let bottomX = p.x * stage.width
        let topX = (0.5 + (p.x - 0.5) * 0.35) * stage.width
        let bottomW = pane.width * stage.width * 1.35
        let topW = pane.width * stage.width * 0.95
        // 光斑的四个角（左上、右上、右下、左下）
        let tl = CGPoint(x: topX - topW / 2, y: topY), tr = CGPoint(x: topX + topW / 2, y: topY)
        let br = CGPoint(x: bottomX + bottomW / 2, y: bottomY), bl = CGPoint(x: bottomX - bottomW / 2, y: bottomY)
        switch part {
        case .floor:
            Canvas { context, _ in
                context.addFilter(.blur(radius: 3))
                let warm = Color(red: 1, green: 0.95, blue: 0.80)
                for (u0, u1) in [(0.0, 0.485), (0.515, 1.0)] {
                    for (v0, v1) in [(0.0, RoomArt.windowTransom - 0.02), (RoomArt.windowTransom + 0.02, 1.0)] {
                        var path = Path()
                        path.move(to: quad(tl, tr, br, bl, u0, v0))
                        path.addLine(to: quad(tl, tr, br, bl, u1, v0))
                        path.addLine(to: quad(tl, tr, br, bl, u1, v1))
                        path.addLine(to: quad(tl, tr, br, bl, u0, v1))
                        path.closeSubpath()
                        context.fill(path, with: .color(warm.opacity(0.38)))
                    }
                }
            }
            .blendMode(.screen)
            .allowsHitTesting(false)
        case .shaft:
            let windowBottom = pane.maxY * stage.height
            Canvas { context, size in
                var shaft = Path()
                shaft.move(to: CGPoint(x: pane.minX * stage.width, y: pane.minY * stage.height))
                shaft.addLine(to: CGPoint(x: pane.maxX * stage.width, y: pane.minY * stage.height))
                shaft.addLine(to: br)
                shaft.addLine(to: bl)
                shaft.closeSubpath()
                context.fill(shaft, with: .linearGradient(
                    Gradient(colors: [Color(red: 1, green: 0.96, blue: 0.84).opacity(0.0), Color(red: 1, green: 0.96, blue: 0.84).opacity(0.13)]),
                    startPoint: CGPoint(x: 0, y: windowBottom), endPoint: CGPoint(x: 0, y: bottomY)))
                // 光里慢慢飘的灰尘
                let t = date.timeIntervalSinceReferenceDate
                for i in 0..<14 {
                    let seed = Double(i) * 12.9898
                    let u = (sin(seed) * 43758.5453).truncatingRemainder(dividingBy: 1).magnitude
                    let v = ((t * (0.006 + u * 0.006) + Double(i) * 0.37).truncatingRemainder(dividingBy: 1))
                    let wobble = sin(t * 0.4 + seed) * 0.03
                    let point = quad(CGPoint(x: pane.minX * stage.width, y: pane.minY * stage.height),
                                     CGPoint(x: pane.maxX * stage.width, y: pane.minY * stage.height), br, bl,
                                     (u + wobble).clamped(to: 0.05...0.95), 1 - v)
                    let r = 1.0 + u * 1.4
                    let twinkle = 0.35 + 0.35 * sin(t * 1.7 + seed)
                    context.fill(Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)),
                                 with: .color(.white.opacity(twinkle)))
                }
            }
            .blendMode(.screen)
            .allowsHitTesting(false)
        }
    }

    /// 四边形里 (u, v) 处的点（双线性插值）
    private func quad(_ tl: CGPoint, _ tr: CGPoint, _ br: CGPoint, _ bl: CGPoint, _ u: Double, _ v: Double) -> CGPoint {
        let top = CGPoint(x: tl.x + (tr.x - tl.x) * u, y: tl.y + (tr.y - tl.y) * u)
        let bottom = CGPoint(x: bl.x + (br.x - bl.x) * u, y: bl.y + (br.y - bl.y) * u)
        return CGPoint(x: top.x + (bottom.x - top.x) * v, y: top.y + (bottom.y - top.y) * v)
    }
}
