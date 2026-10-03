//
//  Rest days, equipment, sounds, a reminder, Apple Health, backup.
//

import SwiftUI
import UIKit

/// The screen's own sheets, behind one `.sheet(item:)` so that two can never be
/// up at once. The import's file picker belongs to BackupSection.
private enum Destination: Identifiable {
    case howItWorks
    case export(URL)

    var id: String {
        switch self {
        case .howItWorks: "howItWorks"
        case .export(let url): "export:\(url)"
        }
    }
}

struct SettingsSheet: SettingsGroup {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var destination: Destination?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text("Settings")
                        .dredfitFont(28, weight: .heavy)
                        .tracking(-0.5)
                        .padding(.top, 26)

                    // ONE grammar for the whole screen, so that what a line
                    // belongs to is read off the page and not guessed (owner,
                    // 13.09.2026: everything ran into one heap). Every group
                    // opens with a kicker; inside a group a caption sits
                    // 6 pt under the control it explains and 14 pt from the
                    // next control; groups stand 28 pt apart. Two blocks used
                    // to have no kicker — Sounds read as part of Equipment,
                    // Reminder as part of Appearance — and the reminder lives
                    // with the rest days now: it fires on training days only,
                    // and toggling a rest day reschedules it (`toggleRestDay`).
                    howItWorksSection
                    RhythmSection()
                    EquipmentSection()
                    SoundsSection()
                    AppearanceSection()
                    HealthSection()
                    BackupSection { destination = .export($0) }
                    AboutSection()
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
        .sheet(item: $destination) { destination in
            switch destination {
            case .howItWorks:
                HowItWorksView()
            case .export(let url):
                ShareSheet(url: url) { self.destination = nil }
            }
        }
    }

    // MARK: - How it works

    private var howItWorksSection: some View {
        Button {
            destination = .howItWorks
        } label: {
            backupRow(icon: "questionmark.circle",
                      title: String(localized: "How it works"))
        }
        .accessibilityIdentifier("how-it-works")
    }
}

// MARK: - The grammar of the screen

/// What every group of the screen draws with: one kicker, one caption, one
/// row, so a section in its own struct looks like its neighbours.
protocol SettingsGroup: View {}

extension SettingsGroup {

    /// The name of a group, read by VoiceOver as a heading — the rotor can
    /// jump group to group, which is what a kicker is for. The identifier is
    /// what a UI test anchors on to say "Settings opened": the words are
    /// localized and uppercased, the identifier is neither.
    func settingsKicker(_ text: String, id: String) -> some View {
        Kicker(text: text)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier(id)
    }

    /// The one caption style of the screen: 12.5 pt ink2, wrapping rather
    /// than truncating whatever the text size is, and placed by its caller
    /// 6 pt under the control it explains — closer than the 14 pt to the
    /// next control, which is what says what it belongs to.
    func caption(_ text: String) -> some View {
        Text(text)
            .dredfitFont(12.5)
            .foregroundStyle(Theme.ink2)
            .fixedSize(horizontal: false, vertical: true)
    }

    func backupRow(icon: String, title: String) -> some View {
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
}

// MARK: - The share sheet

/// `ShareLink` cannot be raised from code, and the file exists only once the
/// row has been tapped — so the activity sheet is presented directly. It is
/// the very same controller `ShareLink` would have shown.
private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    let onFinish: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url],
                                                  applicationActivities: nil)
        // Embedded in a SwiftUI sheet the controller cannot dismiss itself:
        // cancelling would leave an empty sheet standing.
        controller.completionWithItemsHandler = { _, _, _, _ in onFinish() }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
