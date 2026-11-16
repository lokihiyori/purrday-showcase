import CatEngine
import CatWorld
import SwiftUI

/// 新手引导：认识布丁 → 取名 → 设第一个闹钟 → 闹钟权限（计划书阶段 1）。
struct OnboardingView: View {
    @Environment(WorldStore.self) private var store
    @AppStorage("catName") private var catName = String(localized: "onboarding.name.placeholder")
    @State private var step = 0
    @State private var wakeTime = TimeOfDay(7).displayDate
    @FocusState private var nameFocused: Bool
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 0)
            switch step {
            case 0:
                page(image: "cat-idle", title: "onboarding.welcome.title", text: "onboarding.welcome.body")
            case 1:
                page(image: "cat-petted", title: "onboarding.adopt.title", text: "onboarding.adopt.body")
            case 2:
                page(image: "cat-meow", title: "onboarding.name.title", text: nil)
                ZStack {
                    // 卡片是输入框后面单独的一层：输入框本身的范围不变，点卡片也能开始输入
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Theme.card)
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.line))
                        .shadow(color: Color(red: 0.4, green: 0.25, blue: 0.2).opacity(0.12), radius: 8, y: 4)
                        .frame(width: 264, height: 52)
                        .onTapGesture { nameFocused = true }
                        .accessibilityHidden(true)
                    TextField("onboarding.name.placeholder", text: $catName)
                        .focused($nameFocused)
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 240)
                        .accessibilityIdentifier("onboarding.name")
                }
            case 3:
                page(image: "cat-sleep", title: "onboarding.alarm.title", text: nil)
                DatePicker("onboarding.alarm.title", selection: $wakeTime, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
            default:
                page(image: "cat-knead", title: "onboarding.permission.title", text: "onboarding.permission.body")
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                ForEach(0..<5, id: \.self) { i in
                    Capsule().fill(i == step ? Theme.caramel : Theme.line)
                        .frame(width: i == step ? 22 : 8, height: 8)
                }
            }
            .accessibilityHidden(true)
            Button(action: next) {
                Text(LocalizedStringKey(step < 4 ? "common.next" : "onboarding.permission.allow")).frame(maxWidth: .infinity)
            }
            .buttonStyle(CandyButtonStyle())
            .accessibilityIdentifier("onboarding.next")
        }
        .padding(32)
        .background(PaperBackground())
        .animation(.easeInOut, value: step)
    }

    @ViewBuilder
    private func page(image: String, title: LocalizedStringKey, text: LocalizedStringKey?) -> some View {
        Image(image).resizable().scaledToFit().frame(maxWidth: 280)
            .background(ItemSpotlight().scaleEffect(2.6))
            .accessibilityHidden(true)
        Text(title).gameTitle(28).multilineTextAlignment(.center)
        if let text {
            Text(text).font(.system(.body, design: .rounded)).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.center)
        }
    }

    private func next() {
        guard step >= 4 else {
            step += 1
            return
        }
        if catName.trimmingCharacters(in: .whitespaces).isEmpty {
            catName = String(localized: "onboarding.name.placeholder")
        }
        // 每天响：引导里问的是"明天几点叫你起床"，周五晚上设也要保证第二天会响；之后用户可以在闹钟页改成工作日
        let alarm = AlarmConfig(id: UUID().uuidString, time: TimeOfDay(wakeTime), repeatDays: Weekday.everyday, armedAt: .now)
        Task {
            _ = await store.scheduler.requestAuthorization()
            try? store.setAlarm(alarm)
            store.completeOnboarding(now: RoomClock.now())
            onFinish()
        }
    }
}
