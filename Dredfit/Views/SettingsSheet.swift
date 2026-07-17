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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text("Settings")
                        .font(.system(size: 28, weight: .heavy))
                        .tracking(-0.5)
                        .padding(.top, 26)

                    restDaysSection
                    soundsSection
                    reminderSection
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
