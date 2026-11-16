import CatEngine
import CatWorld
import SwiftUI

struct AlarmEditView: View {
    @Environment(WorldStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("wakeAction") private var wakeAction = "pet"
    @State private var alarm: AlarmConfig
    @State private var time: Date
    @State private var repeatChoice: RepeatChoice
    let onLimitReached: () -> Void

    init(alarm: AlarmConfig, onLimitReached: @escaping () -> Void) {
        _alarm = State(initialValue: alarm)
        _time = State(initialValue: alarm.time.displayDate)
        _repeatChoice = State(initialValue: RepeatChoice(alarm.repeatDays))
        self.onLimitReached = onLimitReached
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    CatStillImage(still: "cat-meow", kind: store.activeCat).frame(height: 120)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                    DatePicker("alarms.edit", selection: $time, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                }
                .listRowBackground(Theme.card)
                Section {
                    Picker("alarms.repeat", selection: $repeatChoice) {
                        ForEach(RepeatChoice.allCases, id: \.self) { choice in
                            Text(LocalizedStringKey(choice.titleKey)).tag(choice)
                        }
                    }
                    Picker("alarms.wakeAction", selection: $wakeAction) {
                        Text("alarms.wakeAction.pet").tag("pet")
                        Text("alarms.wakeAction.feed").tag("feed")
                    }
                }
                .listRowBackground(Theme.card)
            }
            .scrollContentBackground(.hidden)
            .background(PaperBackground())
            .foregroundStyle(Theme.ink)
            .navigationTitle("alarms.edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("common.cancel") { dismiss() }.accessibilityIdentifier("alarms.cancel") }
                ToolbarItem(placement: .confirmationAction) { Button("common.save", action: save).accessibilityIdentifier("alarms.save") }
            }
        }
    }

    private func save() {
        alarm.time = TimeOfDay(time)
        alarm.repeatDays = repeatChoice.days
        alarm.isEnabled = true
        alarm.armedAt = .now
        do {
            try store.setAlarm(alarm)
            dismiss()
        } catch WorldError.alarmLimitReached {
            dismiss()
            onLimitReached()
        } catch {
            dismiss()
        }
    }
}
