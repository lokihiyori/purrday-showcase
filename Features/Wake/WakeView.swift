import CatEngine
import CatWorld
import SwiftUI

/// 叫醒中 / 捣乱时的全屏界面：摸她 10 下（或喂她）关掉闹钟。
struct WakeView: View {
    @Environment(WorldStore.self) private var store
    @AppStorage("wakeAction") private var wakeAction = "pet"
    @State private var pets = 0
    private let petsNeeded = 10

    var body: some View {
        VStack(spacing: 24) {
            if let line = store.bubble {
                SpeechBubble(key: line)
            }
            CatStillImage(still: CatArt.assetName(for: store.cat), kind: store.activeCat)
                .frame(maxWidth: 300)
                .onTapGesture(perform: pet)
                .sensoryFeedback(.impact(weight: .light), trigger: pets)
                .accessibilityAddTraits(.isButton)
            Text(LocalizedStringKey(wakeAction == "feed" ? "wake.feed.hint" : "wake.pet.hint"))
                .gameTitle(20)
            // 摸一下点亮一个小脚印
            HStack(spacing: 6) {
                ForEach(0..<petsNeeded, id: \.self) { i in
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(i < pets ? Theme.caramel : Theme.line)
                        .scaleEffect(i == pets - 1 ? 1.25 : 1)
                        .animation(.spring(duration: 0.3), value: pets)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(Text(verbatim: "\(pets) / \(petsNeeded)"))
            if store.cat.state == .wakingUp {
                Button("wake.snooze") {
                    store.snoozeRingingAlarm(now: RoomClock.now())
                }
                .buttonStyle(CandyButtonStyle(prominent: false))
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Image("scene-dawn").resizable().scaledToFill().ignoresSafeArea().accessibilityHidden(true))
    }

    private func pet() {
        pets += 1
        guard pets >= petsNeeded else { return }
        pets = 0
        store.stopRingingAlarm(now: RoomClock.now())
    }
}
