//
//  SettingsSheet.swift
//  Dredfit
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
                        .fill(isRest ? Theme.accentSoft : Color.white)
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
