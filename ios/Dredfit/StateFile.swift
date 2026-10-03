//
//  The one file the app keeps: engine state, journal, settings and the
//  workout in progress, read and written whole. One atomic write of one file
//  is what keeps the four consistent with each other across a crash.
//

import Foundation
import os

struct StateFile {
    let url: URL

    private static let log = Logger(subsystem: "app.dredfit", category: "store")

    /// Application Support, created on first use.
    static var defaultURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory,
                                           in: .userDomainMask)[0]
        // A directory that cannot be created surfaces as the write that fails.
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("dredfit-state.json")
    }

    enum Read {
        /// No file: a fresh install.
        case absent
        /// The file is there and cannot be read yet — data protection before
        /// the first unlock, or I/O. Nothing is touched: it may be the only
        /// copy of the journal, and perfectly fine.
        case unreadable
        /// The file does not decode as a whole. It has been moved aside, so the
        /// next write cannot overwrite the only copy of the journal.
        case undecodable
        case loaded(AppData)
    }

    /// Reads the file. What cannot be kept as it stands goes aside before
    /// anything is written over it: a file that does not decode is moved, and
    /// one whose engine state or some of whose records could not be read is
    /// copied — the next write rewrites the positions from `initial`, or the
    /// journal without the unreadable entries.
    func read() -> Read {
        guard let bytes = try? Data(contentsOf: url) else {
            return FileManager.default.fileExists(atPath: url.path) ? .unreadable : .absent
        }
        let data: AppData
        do {
            data = try JSONDecoder().decode(AppData.self, from: bytes)
        } catch {
            quarantine(keepOriginal: false)
            Self.log.fault("state file failed to decode, moved aside: \(error.localizedDescription)")
            return .undecodable
        }
        if data.engineStateReset {
            // A v2 state migrates (§41.7), so reaching here means the state was
            // neither v3 NOR v2 — a file from a future build, or one damaged
            // past reading. The journal beside it is whole.
            quarantine(keepOriginal: true)
            Self.log.notice("engine state unreadable in both shapes — started clean, journal kept")
        }
        if data.droppedRecordCount > 0 {
            quarantine(keepOriginal: true)
            Self.log.error("dropped \(data.droppedRecordCount) unreadable record(s), original kept aside")
        }
        return .loaded(data)
    }

    /// One atomic write: the file is either the old one or the new one, never
    /// half of each.
    func write(_ data: AppData) throws {
        try JSONEncoder().encode(data).write(to: url, options: .atomic)
    }

    /// Moves (or copies, when the readable part is kept) the file to
    /// `<name>.corrupt.json`, so a decode failure never costs the journal. An
    /// earlier quarantine is NEVER replaced: after a whole-file failure it is
    /// the only copy of the journal the app started over from. A later one
    /// gets a unique name; the same bytes already kept aside are not kept
    /// twice.
    private func quarantine(keepOriginal: Bool) {
        let fm = FileManager.default
        let name = url.deletingPathExtension().lastPathComponent
        var dest = url.deletingLastPathComponent().appendingPathComponent(name + ".corrupt.json")
        if fm.fileExists(atPath: dest.path) {
            if let kept = try? Data(contentsOf: dest), kept == (try? Data(contentsOf: url)) {
                if !keepOriginal { try? fm.removeItem(at: url) }
                return
            }
            dest = url.deletingLastPathComponent()
                .appendingPathComponent(name + ".corrupt-\(UUID().uuidString).json")
        }
        if keepOriginal {
            try? fm.copyItem(at: url, to: dest)
        } else {
            try? fm.moveItem(at: url, to: dest)
        }
    }
}
