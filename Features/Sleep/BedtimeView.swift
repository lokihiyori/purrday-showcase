import CatEngine
import SwiftUI

struct BedtimeView: View {
    @Environment(WorldStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var minutes = 30
    @AppStorage(BedtimeMix.ambientKey) private var ambient = BedtimeMix.Ambient.none.rawValue
    @AppStorage(BedtimeMix.purrVolumeKey) private var purrVolume = 0.7
    @AppStorage(BedtimeMix.ambientVolumeKey) private var ambientVolume = 0.5

    var body: some View {
        VStack(spacing: 18) {
            CatStillImage(still: CatArt.assetName(for: store.cat), kind: store.activeCat)
                .frame(maxWidth: 220, maxHeight: 220)
            Text(localized("bedtime.prompt", CatNames.name(store.activeCat)))
                .handwritten(22, relativeTo: .title3)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            HStack(spacing: 8) {
                ForEach([15, 30, 45, 60], id: \.self) { value in
                    Button { minutes = value } label: {
                        Text(localized("bedtime.minutes", value))
                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                            .foregroundStyle(minutes == value ? Color(red: 0.2, green: 0.2, blue: 0.36) : .white)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(minutes == value ? AnyShapeStyle(Color(red: 1, green: 0.93, blue: 0.75)) : AnyShapeStyle(.white.opacity(0.14)),
                                        in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(minutes == value ? .isSelected : [])
                }
            }
            soundMixer
            Button("bedtime.start") {
                store.send(.bedtimeTimerStarted(duration: TimeInterval(minutes * 60), at: RoomClock.now()))
            }
            .buttonStyle(CandyButtonStyle(color: Color(red: 0.5, green: 0.45, blue: 0.75)))
            Button("bedtime.notYet") {
                store.send(.bedtimeDismissed(at: RoomClock.now()))
                dismiss()
            }
            .font(.system(.subheadline, design: .rounded))
            .foregroundStyle(.white.opacity(0.8))
            Text("bedtime.tip")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            // 铺满整个屏幕（包括标签栏下面）
            Color(red: 0.36, green: 0.33, blue: 0.5)
                .overlay { Image("scene-night").resizable().scaledToFill() }
                .clipped()
                .ignoresSafeArea()
                .accessibilityHidden(true)
        }
        .navigationTitle("bedtime.title")
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    /// 睡前听什么：她的呼噜声，再叠一层环境音（可以不要）。两层各有音量，边放边调。
    private var soundMixer: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                ForEach(BedtimeMix.Ambient.allCases, id: \.self) { option in
                    let selected = ambient == option.rawValue
                    Button { ambient = option.rawValue } label: {
                        VStack(spacing: 3) {
                            Image(systemName: Self.symbol(option)).font(.system(size: 15, weight: .semibold))
                            Text(LocalizedStringKey(Self.nameKey(option)))
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .foregroundStyle(selected ? Color(red: 0.2, green: 0.2, blue: 0.36) : .white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(selected ? AnyShapeStyle(Color(red: 1, green: 0.93, blue: 0.75)) : AnyShapeStyle(.white.opacity(0.14)),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("bedtime.sound.\(option.rawValue)")
                }
            }
            volumeRow(symbol: "pawprint.fill", label: "bedtime.sound.purr", value: $purrVolume)
            if ambient != BedtimeMix.Ambient.none.rawValue {
                volumeRow(symbol: Self.symbol(BedtimeMix.Ambient(rawValue: ambient) ?? .rain), label: "bedtime.sound.ambient", value: $ambientVolume)
            }
        }
        .padding(12)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .animation(.snappy, value: ambient)
    }

    private func volumeRow(symbol: String, label: LocalizedStringKey, value: Binding<Double>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.85)).frame(width: 18)
            Slider(value: value, in: 0...1)
                .tint(Color(red: 1, green: 0.93, blue: 0.75))
                .accessibilityLabel(Text(label))
        }
    }

    static func symbol(_ ambient: BedtimeMix.Ambient) -> String {
        switch ambient {
        case .none: "speaker.slash.fill"
        case .rain: "cloud.rain.fill"
        case .fireplace: "flame.fill"
        case .ocean: "water.waves"
        }
    }

    static func nameKey(_ ambient: BedtimeMix.Ambient) -> String { "bedtime.sound.\(ambient.rawValue)" }
}
