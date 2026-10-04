//
//  Apple Health: the switch, the body weight, and the calorie opt-out.
//

import SwiftUI

struct HealthSection: SettingsGroup {
    @Environment(AppStore.self) private var store

    @State private var backfillPromptShown = false
    @State private var bodyMassPromptShown = false
    @State private var bodyMassField = ""
    /// Optimistic value while authorization is in flight: without it the
    /// switch visibly bounces off before the system sheet appears.
    @State private var healthSwitch: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            settingsKicker(String(localized: "Health"), id: "settings-health")
            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: healthBinding) {
                    Text("Save workouts to Health")
                        .dredfitFont(16, weight: .medium)
                }
                .tint(Theme.accent)
                caption(String(localized: "Workouts appear in the Health app. Nothing leaves your device."))
            }
            if store.settings.healthEnabled {
                bodyMassRow
                watchToggle
            }
        }
        .alert(String(localized: "Add past workouts to Health?"),
               isPresented: $backfillPromptShown) {
            Button {
                Task { await store.backfillHealth() }
            } label: {
                Text("Export \(store.healthBackfillCount) workouts")
            }
            Button {
                store.skipHealthBackfill()
            } label: {
                Text("Only new ones")
            }
        }
        .alert(String(localized: "Body weight"), isPresented: $bodyMassPromptShown) {
            TextField(massUnitLabel, text: $bodyMassField)
                .keyboardType(.decimalPad)
            Button(String(localized: "Save")) { commitBodyMass() }
            Button(String(localized: "Cancel"), role: .cancel) { }
        } message: {
            Text("Used only to estimate the calories of each workout. It stays on this device.")
        }
    }

    /// Weight is the factor the whole estimate is multiplied by, so an absent
    /// one is not an empty field — it is the reason no calories are written.
    ///
    /// The row ALWAYS opens the editor, whether the number in force came from
    /// Health or was typed: the scale's last reading can be a month old, and a
    /// row that took no typed number would leave no way to say otherwise. The
    /// later statement wins, so a typed number stands until Health logs a
    /// NEWER one, and the caption says where the number in force came from
    /// and when, so a stale reading is seen for what it is rather than
    /// trusted for being Health's.
    private var bodyMassRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                bodyMassField = editableBodyMass
                bodyMassPromptShown = true
            } label: {
                bodyMassContent(chevron: true)
            }
            .accessibilityIdentifier("body-mass-row")
            if let text = bodyMassCaption {
                caption(text)
                    .accessibilityIdentifier("body-mass-caption")
            }
        }
    }

    /// Absent: why that matters. Present and Health is on: where the number
    /// came from, when, and that a newer statement from either side replaces
    /// it. Present with Health off: nothing to explain — it is the typed
    /// number and nothing competes with it. A number with no date (a file
    /// from before the date was kept) says nothing rather than a guessed
    /// day; it ranks below any Health sample, so the next activation that
    /// finds one replaces it with a dated number. "Set in the app", not
    /// "typed here": a restored backup sets the number too, dated by the
    /// journal it came with, and a caption claiming it was typed on this
    /// phone would be wrong about both the hand and the day.
    private var bodyMassCaption: String? {
        guard store.settings.bodyMassKg != nil else {
            return String(localized: "Without it, workouts are saved with no calorie estimate.")
        }
        guard store.settings.healthEnabled, let date = store.settings.bodyMassDate else { return nil }
        let when = date.formatted(date: .abbreviated, time: .omitted)
        return store.settings.bodyMassFromHealth
            ? String(localized: "From Health, \(when). A newer weight — typed here or logged there — takes over.")
            : String(localized: "Set in the app, \(when). A newer weight logged in Health takes over.")
    }

    private func bodyMassContent(chevron: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "scalemass")
                .dredfitFont(15, weight: .medium)
                .accessibilityHidden(true)
            Text("Body weight")
                .dredfitFont(16, weight: .medium)
            Spacer(minLength: 8)
            Text(bodyMassDisplay)
                .dredfitFont(15)
                .foregroundStyle(Theme.ink2)
            if chevron {
                Image(systemName: "chevron.right")
                    .dredfitFont(12, weight: .semibold)
                    .foregroundStyle(Theme.ink2)
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        // 44 pt: the row is a target, and it keeps that height whatever the
        // caption under it does, so the toggle underneath does not move.
        .frame(minHeight: 44)
        .background(Theme.cardBG, in: RoundedRectangle(cornerRadius: 14))
    }

    /// The manual half of the double-count guard. The automatic half reads the
    /// other workouts in Health, and HealthKit never says whether that read was
    /// allowed — a refusal looks exactly like "nothing found there", which is
    /// the wrong answer for precisely the person wearing a watch.
    ///
    /// And, because the weight follows Health, the ONLY way to say "write no
    /// estimate at all": a cleared weight is filled again from Health on the
    /// next activation. So the label names the EFFECT and the caption names
    /// both reasons. The stored key stays `watchRecordsWorkouts` — it is the
    /// wire name in every saved file, and a label is not a reason to move it.
    private var watchToggle: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(
                get: { store.settings.watchRecordsWorkouts },
                set: { store.setWatchRecordsWorkouts($0) })) {
                Text("Leave calories out")
                    .dredfitFont(16, weight: .medium)
            }
            .tint(Theme.accent)
            .accessibilityIdentifier("watch-records-toggle")
            caption(String(localized: """
                 Turn it on if an Apple Watch records the same workouts — \
                 otherwise the session counts twice — or if you simply want \
                 no estimate written.
                 """))
        }
    }

    /// A denial leaves the toggle off. On success, past history is offered
    /// once.
    private var healthBinding: Binding<Bool> {
        Binding(
            get: { healthSwitch ?? store.settings.healthEnabled },
            set: { on in
                guard on else {
                    healthSwitch = nil
                    return store.disableHealth()
                }
                healthSwitch = true
                Task {
                    let granted = await store.enableHealth()
                    healthSwitch = nil   // reality (granted or denied) takes over
                    if granted, store.healthBackfillCount > 0 {
                        backfillPromptShown = true
                    }
                }
            })
    }

    // MARK: - Body weight, shown in the locale's unit and stored in one

    /// Displayed in pounds where the locale uses them; the store keeps
    /// kilograms always, because a file carrying both cannot be read back.
    private var massUnit: UnitMass {
        Locale.current.measurementSystem == .us ? .pounds : .kilograms
    }

    private var massUnitLabel: String {
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .providedUnit
        formatter.unitStyle = .medium
        return formatter.string(from: massUnit)
    }

    private var bodyMassDisplay: String {
        guard let kg = store.settings.bodyMassKg else { return String(localized: "Not set") }
        return Measurement(value: kg, unit: UnitMass.kilograms)
            .converted(to: massUnit)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided,
                                    numberFormatStyle: .number.precision(.fractionLength(0...1))))
    }

    private var editableBodyMass: String {
        guard let kg = store.settings.bodyMassKg else { return "" }
        return Measurement(value: kg, unit: UnitMass.kilograms)
            .converted(to: massUnit).value
            .formatted(.number.precision(.fractionLength(0...1)).grouping(.never))
    }

    /// Only an EMPTY field clears the weight; an unreadable one keeps the old
    /// number, because a typo is not a request to erase it. Clearing does not
    /// switch the calories off either: "write no estimate" is said with the
    /// toggle below. The comma is accepted because half the shipping locales
    /// type one.
    private func commitBodyMass() {
        let typed = bodyMassField
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        guard !typed.isEmpty else { return store.setBodyMass(nil) }
        guard let value = Double(typed), value.isFinite, value > 0 else { return }
        store.setBodyMass(Measurement(value: value, unit: massUnit)
            .converted(to: .kilograms).value)
    }
}
