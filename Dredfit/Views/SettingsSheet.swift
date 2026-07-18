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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text("Settings")
                        .font(.system(size: 28, weight: .heavy))
                        .tracking(-0.5)
                        .padding(.top, 26)

                    howItWorksSection
                    restDaysSection
                    equipmentSection
                    soundsSection
                    reminderSection
                    healthSection
                    backupSection
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }

            PrimaryButton(title: String(localized: "Got it")) { dismiss() }
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
            Text("Highlighted days are rest days")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.ink3)
        }
    }

    private func dayChip(_ weekday: Int) -> some View {
        let isRest = store.settings.restWeekdays.contains(weekday)
        let symbol = Calendar.current.shortWeekdaySymbols[weekday - 1]
        return Button {
            store.toggleRestDay(weekday)
        } label: {
            Text(symbol)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isRest ? Theme.accentSoft : Color.white)
                        .overlay(RoundedRectangle(cornerRadius: 12)
                            .stroke(isRest ? Theme.accent : Theme.hairline, lineWidth: 1.5))
                )
                .foregroundStyle(isRest ? Theme.accent : Theme.ink2)
        }
        .accessibilityIdentifier("weekday-\(weekday)")
    }

    // MARK: - Equipment (v2.2)

    private var equipmentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Kicker(text: String(localized: "Equipment"))
            Toggle(isOn: Binding(
                get: { store.engineState.hasBar },
                set: { store.setHasBar($0) })) {
                Text("Pull-up bar")
                    .font(.system(size: 16, weight: .medium))
            }
            .tint(Theme.accent)
            .accessibilityIdentifier("hasbar-toggle")
            Text("Every other workout swaps the row for a vertical pull")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.ink3)
        }
    }

    // MARK: - Sounds

    private var soundsSection: some View {
        Toggle(isOn: Binding(
            get: { store.settings.soundsEnabled },
            set: { store.setSounds($0) })) {
            Text("Sounds and haptics")
                .font(.system(size: 16, weight: .medium))
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
                    .font(.system(size: 16, weight: .medium))
            }
            .tint(Theme.accent)

            if store.settings.reminderEnabled {
                DatePicker(String(localized: "Time"),
                           selection: reminderTimeBinding,
                           displayedComponents: .hourAndMinute)
                    .font(.system(size: 15))
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
                    .font(.system(size: 16, weight: .medium))
            }
            .tint(Theme.accent)
            .accessibilityIdentifier("health-toggle")
            Text("Workouts appear in the Health app. Nothing is read or shared.")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.ink3)
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
            get: { store.settings.healthEnabled },
            set: { on in
                guard on else { return store.disableHealth() }
                Task {
                    if await store.enableHealth(), store.healthBackfillCount > 0 {
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
                .font(.system(size: 15, weight: .medium))
            Text(title)
                .font(.system(size: 16, weight: .medium))
            Spacer()
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(Theme.cardBG, in: RoundedRectangle(cornerRadius: 14))
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
