//
//  Backup: export and import of the history file.
//

import SwiftUI
import UniformTypeIdentifiers

struct BackupSection: SettingsGroup {
    @Environment(AppStore.self) private var store

    @State private var importPickerShown = false
    @State private var pendingImportURL: URL?
    @State private var importConfirmShown = false
    @State private var importFailed = false
    @State private var exportFailed = false

    /// Raises the share sheet for a file that was just built. The share sheet
    /// is one of the screen's own, so this section only says which file.
    let onExport: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            settingsKicker(String(localized: "Backup"), id: "settings-backup")
            // The control says "history"; the file holds the whole `settings`
            // block too, weight included (AppStore+Backup.exportURL). The
            // IMPORT alert names settings as well, but it is read, if at all,
            // long after the file has been sent somewhere. Nothing here goes
            // anywhere by itself, yet the person has to know what they send —
            // so this line stands ABOVE the rows, where the other groups put
            // theirs below: it has to be read BEFORE the tap, because after
            // Export the file has already gone.
            caption(String(localized: """
                 The file holds your history, your plan and your settings — \
                 including your weight, if you entered one. It goes only where \
                 you send it.
                 """))
            exportRow
            Button {
                importPickerShown = true
            } label: {
                backupRow(icon: "square.and.arrow.down",
                          title: String(localized: "Import history"))
            }
            // A frozen launch would import into the empty state that stood in
            // for the real journal.
            .disabled(store.journalFrozen)
            // backupRow sets Theme.ink itself, so `disabled` alone leaves a
            // live-looking row that quietly does nothing.
            .opacity(store.journalFrozen ? 0.4 : 1)
            if store.journalFrozen { frozenNote }
        }
        .fileImporter(isPresented: $importPickerShown,
                      allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                pendingImportURL = url
                importConfirmShown = true
            case .failure(let error):
                // A file the picker could not hand over could not be read
                // either; ignoring it left the tap looking dead.
                if (error as? CocoaError)?.code != .userCancelled { importFailed = true }
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
            // An alert also keeps its cancel action, which a popover suppresses
            // because tapping outside IS the cancel: measured on iPhone 17
            // Pro / iOS 26.5, the node is `Alert` with no `Popover` beside it,
            // and the `.cancel` button stands in the accessibility tree. So
            // the escape is one button, carrying the role AND the name that
            // says what it does. "Cancel" answers "cancel what?"; this one
            // does not. It also carries the cleanup, so the picked file does
            // not stay in state once the person keeps their history.
            Button(String(localized: "Keep my history"), role: .cancel) { pendingImportURL = nil }
            Button(String(localized: "Replace"), role: .destructive) { runImport() }
        } message: {
            Text("Import replaces your current history and settings.")
        }
        .alert(String(localized: "Couldn't read this file."), isPresented: $importFailed) {
            Button("OK", role: .cancel) { }
        }
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

    /// The file is built by the TAP and only then shared, not handed to
    /// `ShareLink` as a lazy `Transferable`: that shape has nowhere to put a
    /// failure — the throw happens inside the transfer representation, so a
    /// file that could not be written produces silence and leaves the belief
    /// that a backup exists. Built here, a failure gets an alert, as an import
    /// does.
    ///
    /// The alert hangs HERE rather than on the root view, which already
    /// carries the screen's sheet.
    private var exportRow: some View {
        Button {
            do {
                try onExport(store.exportURL())
            } catch {
                exportFailed = true
            }
        } label: {
            backupRow(icon: "square.and.arrow.up",
                      title: String(localized: "Export history"))
        }
        // A frozen launch would export the empty state that stood in for the
        // real journal.
        .disabled(store.journalFrozen)
        .opacity(store.journalFrozen ? 0.4 : 1)
        .alert(String(localized: "Couldn't build the backup file."), isPresented: $exportFailed) {
            Button("OK", role: .cancel) { }
        }
    }

    /// A frozen launch disables both backup rows; this says why, beside them.
    private var frozenNote: some View {
        caption(String(localized: """
             Your history couldn't be read on this launch, so it can't be \
             backed up. Unlock the phone and open Dredfit again.
             """))
    }
}
