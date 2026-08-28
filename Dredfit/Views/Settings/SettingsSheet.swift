//
//  Rest days, equipment, sounds, a reminder, Apple Health, backup.
//

import SwiftUI
import CoreTransferable
import UniformTypeIdentifiers
import DredfitCore

struct SettingsSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var importPickerShown = false
    @State private var pendingImportURL: URL?
    @State private var importConfirmShown = false
    @State private var importFailed = false
    @State private var backfillPromptShown = false   // Apple Health
    @State private var bodyMassPromptShown = false
    @State private var bodyMassField = ""
    @State private var howItWorksShown = false
    /// Optimistic value while authorization is in flight: without it the
    /// switch visibly bounces off before the system sheet appears.
    @State private var healthSwitch: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text("Settings")
                        .dredfitFont(28, weight: .heavy)
                        .tracking(-0.5)
                        .padding(.top, 26)

                    howItWorksSection
                    restDaysSection
                    equipmentSection
                    soundsSection
                    reminderSection
                    healthSection
                    backupSection
                    aboutSection
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }

            // Keyed like milestone.done — the same English word as the
            // workout's set button, different meaning.
            PrimaryButton(title: String(localized: "settings.done",
                                        defaultValue: "Done")) { dismiss() }
                .accessibilityIdentifier("settings-done")
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.bg)
        .sheet(isPresented: $howItWorksShown) {
            HowItWorksView()
        }
        .fileImporter(isPresented: $importPickerShown,
                      allowedContentTypes: [.json]) { result in
            if case .success(let url) = result {
                pendingImportURL = url
                importConfirmShown = true
            }
        }
        .alert(String(localized: "Replace history?"),
               isPresented: $importConfirmShown) {
            // An ALERT, not a confirmationDialog: iOS 26 presents the latter
            // as an anchored popover, so the same question drew a centred card
            // in the workout and a tailed bubble pointing at a settings row.
            // An alert has no anchor — every one of these is the same window,
            // centred, whatever it was raised from.
            //
            // And the workaround the popover forced is gone with it. A popover
            // suppresses its cancel action, because tapping outside IS the
            // cancel, so the escape had to be a SECOND, role-less button. An
            // alert does not: measured on iPhone 17 Pro / iOS 26.5, the node is
            // `Alert` with no `Popover` beside it, and all four buttons stood in
            // the accessibility tree — the `.cancel` one included. So the escape
            // is one button again, carrying the role AND the name that says what
            // it does. "Cancel" answers "cancel what?"; this one does not.
            // It also carries the cancel action's own cleanup: dismissing by a
            // tap outside never ran `pendingImportURL = nil`, so the picked
            // file stayed in state with no way to reach the line that clears
            // it.
            Button(String(localized: "Keep my history"), role: .cancel) { pendingImportURL = nil }
            Button(String(localized: "Replace"), role: .destructive) { runImport() }
        } message: {
            Text("Import replaces your current history and settings.")
        }
        .alert(String(localized: "Couldn't read this file."), isPresented: $importFailed) {
            Button("OK", role: .cancel) { }
        }
    }

    // MARK: - How it works

    private var howItWorksSection: some View {
        Button {
            howItWorksShown = true
        } label: {
            backupRow(icon: "questionmark.circle",
                      title: String(localized: "How it works"))
        }
        .accessibilityIdentifier("how-it-works")
    }

    // MARK: - Rest days

    /// Respects the locale's first day.
    private var weekdaysInDisplayOrder: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { ((first - 1 + $0) % 7) + 1 }
    }

    private var restDaysSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Kicker(text: String(localized: "Rest days"))
            HStack(spacing: 8) {
                ForEach(weekdaysInDisplayOrder, id: \.self) { wd in
                    dayChip(wd)
                }
            }
            Text("Highlighted days are rest days")
                .dredfitFont(12.5)
                .foregroundStyle(Theme.ink2)
            Text("2–3 rest days a week is the recommended rhythm")
                .dredfitFont(12.5)
                .foregroundStyle(Theme.ink2)
        }
    }

    private func dayChip(_ weekday: Int) -> some View {
        let isRest = store.settings.restWeekdays.contains(weekday)
        let symbol = Calendar.current.shortWeekdaySymbols[weekday - 1]
        return Button {
            store.toggleRestDay(weekday)
        } label: {
            Text(symbol)
                .dredfitFont(13, weight: .semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isRest ? Theme.accentSoft : Theme.bg)
                        .overlay(RoundedRectangle(cornerRadius: 12)
                            .stroke(isRest ? Theme.accent : Theme.hairline, lineWidth: 1.5))
                )
                // ink, not accent: accent text on accentSoft is 2.91:1.
                .foregroundStyle(isRest ? Theme.ink : Theme.ink2)
        }
        .accessibilityIdentifier("weekday-\(weekday)")
        // Colour alone doesn't reach VoiceOver: without the trait a chip
        // announces only "Mon".
        .accessibilityAddTraits(isRest ? [.isSelected] : [])
    }

    // MARK: - Equipment

    private var equipmentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Kicker(text: String(localized: "Equipment"))
            Toggle(isOn: Binding(
                get: { store.engineState.hasBar },
                set: { store.setHasBar($0) })) {
                Text("Pull-up bar")
                    .dredfitFont(16, weight: .medium)
            }
            .tint(Theme.accent)
            .accessibilityIdentifier("hasbar-toggle")
            Text("Every other workout swaps the row for a vertical pull")
                .dredfitFont(12.5)
                .foregroundStyle(Theme.ink2)
        }
    }

    // The session-length picker is gone. The audit measured what its rungs
    // actually did: 10, 15 and 20 produced the SAME plan, and the "20" rung
    // missed its own target in 100 % of sessions. The plan handle that replaced
    // it is gone too, for a different reason: it still asked how much of the
    // workout the person had in them BEFORE they had done any of it. The engine
    // announces the range a session can land in, and the shortening happens on
    // the work screen, one skipped set at a time, where the answer is known.

    // MARK: - Sounds

    private var soundsSection: some View {
        Toggle(isOn: Binding(
            get: { store.settings.soundsEnabled },
            set: { store.setSounds($0) })) {
            Text("Sounds and haptics")
                .dredfitFont(16, weight: .medium)
        }
        .tint(Theme.accent)
    }

    // MARK: - Reminder

    private var reminderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: Binding(
                get: { store.settings.reminderEnabled },
                set: { store.setReminderEnabled($0) })) {
                Text("Reminder")
                    .dredfitFont(16, weight: .medium)
            }
            .tint(Theme.accent)

            if store.settings.reminderEnabled {
                DatePicker(String(localized: "Time"),
                           selection: reminderTimeBinding,
                           displayedComponents: .hourAndMinute)
                    .dredfitFont(15)
                    .foregroundStyle(Theme.ink2)
                    .tint(Theme.accent)
            }
        }
    }

    private var reminderTimeBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(from: DateComponents(
                    hour: store.settings.reminderHour,
                    minute: store.settings.reminderMinute)) ?? .now
            },
            set: {
                let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                store.setReminderTime(hour: c.hour ?? 9, minute: c.minute ?? 0)
            })
    }

    // MARK: - Apple Health

    private var healthSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Kicker(text: String(localized: "Health"))
            Toggle(isOn: healthBinding) {
                Text("Save workouts to Health")
                    .dredfitFont(16, weight: .medium)
            }
            .tint(Theme.accent)
            Text("Workouts appear in the Health app. Nothing leaves your device.")
                .dredfitFont(12.5)
                .foregroundStyle(Theme.ink2)
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
    private var bodyMassRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                bodyMassField = editableBodyMass
                bodyMassPromptShown = true
            } label: {
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
                    Image(systemName: "chevron.right")
                        .dredfitFont(12, weight: .semibold)
                        .foregroundStyle(Theme.ink2)
                        .accessibilityHidden(true)
                }
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .background(Theme.cardBG, in: RoundedRectangle(cornerRadius: 14))
            }
            .accessibilityIdentifier("body-mass-row")
            if store.settings.bodyMassKg == nil {
                Text("Without it, workouts are saved without calories.")
                    .dredfitFont(12.5)
                    .foregroundStyle(Theme.ink2)
            }
        }
    }

    /// The manual half of the double-count guard. The automatic half reads the
    /// other workouts in Health, and HealthKit never says whether that read was
    /// allowed — a refusal looks exactly like "nothing found there", which is
    /// the wrong answer for precisely the person wearing a watch.
    private var watchToggle: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(
                get: { store.settings.watchRecordsWorkouts },
                set: { store.setWatchRecordsWorkouts($0) })) {
                Text("I record workouts on Apple Watch")
                    .dredfitFont(16, weight: .medium)
            }
            .tint(Theme.accent)
            .accessibilityIdentifier("watch-records-toggle")
            Text("Calories are left out, so the same workout is not counted twice.")
                .dredfitFont(12.5)
                .foregroundStyle(Theme.ink2)
        }
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

    /// An empty or unreadable field CLEARS the weight rather than keeping the
    /// old one: "never mind" has to be expressible, and a silently kept number
    /// would keep feeding calories the person believes they switched off. The
    /// comma is accepted because half the shipping locales type one.
    private func commitBodyMass() {
        let typed = bodyMassField
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        guard let value = Double(typed), value > 0 else {
            return store.setBodyMass(nil)
        }
        store.setBodyMass(Measurement(value: value, unit: massUnit)
            .converted(to: .kilograms).value)
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

    // MARK: - Backup

    private var backupSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Kicker(text: String(localized: "Backup"))
            ShareLink(item: BackupFile { [store] in try store.exportURL() },
                      preview: SharePreview(String(localized: "Export history"))) {
                backupRow(icon: "square.and.arrow.up",
                          title: String(localized: "Export history"))
            }
            // A frozen launch would export, and import into, the empty state
            // that stood in for the real journal.
            .disabled(store.journalFrozen)
            Button {
                importPickerShown = true
            } label: {
                backupRow(icon: "square.and.arrow.down",
                          title: String(localized: "Import history"))
            }
            .disabled(store.journalFrozen)
        }
    }

    private func backupRow(icon: String, title: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .dredfitFont(15, weight: .medium)
                .accessibilityHidden(true)
            Text(title)
                .dredfitFont(16, weight: .medium)
            Spacer()
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(Theme.cardBG, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Kicker(text: String(localized: "About"))
            Link(destination: Self.reviewURL) {
                backupRow(icon: "star", title: String(localized: "Rate on the App Store"))
            }
            ShareLink(item: Self.appStoreURL) {
                backupRow(icon: "heart", title: String(localized: "Recommend Dredfit"))
            }
            Text(versionLine)
                .dredfitFont(12.5)
                .foregroundStyle(Theme.ink3)
        }
    }

    private static let appStoreURL = URL(string: "https://apps.apple.com/app/id6791739610")!
    private static let reviewURL = URL(string:
        "https://apps.apple.com/app/id6791739610?action=write-review")!

    private var versionLine: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "Dredfit \(version) (\(build))"
    }

    private func runImport() {
        guard let url = pendingImportURL else { return }
        pendingImportURL = nil
        do {
            try store.importBackup(from: url)
        } catch {
            importFailed = true
        }
    }
}

// MARK: - Lazy backup file

/// ShareLink wants its item up front, but the JSON is produced only when the
/// user commits to sharing — not on every settings change.
private nonisolated struct BackupFile: Transferable {
    let makeURL: @MainActor @Sendable () throws -> URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { backup in
            SentTransferredFile(try await backup.makeURL())
        }
    }
}
