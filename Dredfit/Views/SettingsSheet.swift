//
//  SettingsSheet.swift
//  Dredfit
//
//  v1.1: the few settings the thermostat allows itself — rest days,
//  sounds, a reminder, and a manual backup. No questionnaires.
//

import SwiftUI
import UniformTypeIdentifiers
import DredfitCore

struct SettingsSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var exportURL: URL?
    @State private var importPickerShown = false
    @State private var pendingImportURL: URL?
    @State private var importConfirmShown = false
    @State private var importFailed = false
    @State private var backfillPromptShown = false   // v1.3: Apple Health
    @State private var howItWorksShown = false       // v1.4
    /// Optimistic Health-toggle value while authorization is in flight —
    /// without it the switch visibly bounces off before the system sheet
    /// appears (settings.healthEnabled only flips after the async grant).
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

            // "Done", not "Got it": settings are a place you act in, not a
            // message you acknowledge. Keyed like milestone.done — the same
            // English word as the workout's set button, different meaning.
            PrimaryButton(title: String(localized: "settings.done",
                                        defaultValue: "Done")) { dismiss() }
                .accessibilityIdentifier("settings-done")
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear { exportURL = try? store.exportURL() }
        // The share copy is a point-in-time snapshot: toggles flipped in this
        // very sheet (rest days, the pull-up bar) must land in the export.
        .onChange(of: store.settings) { exportURL = try? store.exportURL() }
        .onChange(of: store.engineState) { exportURL = try? store.exportURL() }
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
        .confirmationDialog(String(localized: "Replace history?"),
                            isPresented: $importConfirmShown,
                            titleVisibility: .visible) {
            Button(String(localized: "Replace"), role: .destructive) { runImport() }
            Button(String(localized: "Cancel"), role: .cancel) { pendingImportURL = nil }
        } message: {
            Text("Import replaces your current history and settings.")
        }
        .alert(String(localized: "Couldn't read this file."), isPresented: $importFailed) {
            Button("OK", role: .cancel) { }
        }
    }

    // MARK: - How it works (v1.4)

    /// First section deliberately: the one thing a user cannot infer from the
    /// rest of the UI is why the plan keeps moving.
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

    /// Weekdays in the user's calendar order (respects the locale's first day).
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
            // ink2, not ink3: the one line explaining what the chips mean.
            Text("Highlighted days are rest days")
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
                        .fill(isRest ? Theme.accentSoft : Color.white)
                        .overlay(RoundedRectangle(cornerRadius: 12)
                            .stroke(isRest ? Theme.accent : Theme.hairline, lineWidth: 1.5))
                )
                // ink, not accent: accent text on accentSoft is 2.91:1. The
                // fill and stroke already carry "selected"; the label's only
                // job is to be readable.
                .foregroundStyle(isRest ? Theme.ink : Theme.ink2)
        }
        .accessibilityIdentifier("weekday-\(weekday)")
        // Colour alone doesn't reach VoiceOver — without the trait a chip
        // announces only "Mon" and the rest-day state is invisible.
        .accessibilityAddTraits(isRest ? [.isSelected] : [])
    }

    // MARK: - Equipment (v2.2)

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

    // MARK: - Apple Health (v1.3)

    private var healthSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Kicker(text: String(localized: "Health"))
            Toggle(isOn: healthBinding) {
                Text("Save workouts to Health")
                    .dredfitFont(16, weight: .medium)
            }
            .tint(Theme.accent)
            .accessibilityIdentifier("health-toggle")
            Text("Workouts appear in the Health app. Nothing is read or shared.")
                .dredfitFont(12.5)
                .foregroundStyle(Theme.ink2)
        }
        .confirmationDialog(String(localized: "Add past workouts to Health?"),
                            isPresented: $backfillPromptShown,
                            titleVisibility: .visible) {
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
    }

    /// Enabling asks for write-only authorization first; a denial simply
    /// leaves the toggle off. On success, past history is offered once.
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
            if let exportURL {
                ShareLink(item: exportURL) {
                    backupRow(icon: "square.and.arrow.up",
                              title: String(localized: "Export history"))
                }
            }
            Button {
                importPickerShown = true
            } label: {
                backupRow(icon: "square.and.arrow.down",
                          title: String(localized: "Import history"))
            }
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

    // MARK: - About (v1.4)

    /// The two places a review can be asked for on purpose. The automatic ask
    /// happens once, after a milestone; these are here so someone who wants to
    /// leave one never has to wait for it.
    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Kicker(text: String(localized: "About"))
            Link(destination: Self.reviewURL) {
                backupRow(icon: "star", title: String(localized: "Rate in App Store"))
            }
            .accessibilityIdentifier("rate-app")
            ShareLink(item: Self.appStoreURL) {
                backupRow(icon: "heart", title: String(localized: "Recommend Dredfit"))
            }
            .accessibilityIdentifier("recommend-app")
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
            exportURL = try? store.exportURL()   // refresh the share copy
        } catch {
            importFailed = true
        }
    }
}
