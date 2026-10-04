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
        /// the first unlock, or I/O — or it was read but could not be put
        /// aside before a write would replace it. Nothing is touched: it may
        /// be the only copy of the journal.
        case unreadable
        /// The file does not decode as a whole. It is moved aside, so the next
        /// write cannot overwrite the only copy of the journal.
        case undecodable
        case loaded(AppData)
    }

    /// Reads the file. A file that does not decode is moved aside; one whose
    /// engine state or some of whose records could not be read is copied aside
    /// first, because the next write rewrites the positions from `initial`, or
    /// the journal without the unreadable entries. An unreadable settings block
    /// or a snapshot from a newer build is not copied: it costs only itself.
    /// `reload` only labels the log lines, so a launch and a reload can be told
    /// apart in Console.
    func read(reload: Bool) -> Read {
        let when = reload ? " on reload" : ""
        guard let bytes = try? Data(contentsOf: url) else {
            return FileManager.default.fileExists(atPath: url.path) ? .unreadable : .absent
        }
        let data: AppData
        do {
            data = try JSONDecoder().decode(AppData.self, from: bytes)
        } catch {
            Self.log.fault("state file failed to decode\(when): \(error.localizedDescription)")
            guard quarantine(bytes, keepOriginal: false, when: when) else { return .unreadable }
            return .undecodable
        }
        if data.engineStateReset {
            // A v2 state migrates (§41.7), so reaching here means the state was
            // neither v3 NOR v2 — a file from a future build, or one damaged
            // past reading. The journal beside it is whole.
            Self.log.notice("engine state unreadable in both shapes\(when), journal whole")
            guard quarantine(bytes, keepOriginal: true, when: when) else { return .unreadable }
        }
        if data.droppedRecordCount > 0 {
            Self.log.error("\(data.droppedRecordCount) unreadable record(s)\(when)")
            guard quarantine(bytes, keepOriginal: true, when: when) else { return .unreadable }
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
    /// gets a unique name; the same bytes already kept aside, under either
    /// name, are not kept twice.
    ///
    /// Returns whether the bytes are safe aside. When they are not, the read
    /// reports the file unreadable, so the launch freezes rather than start
    /// over and write on top of the only copy.
    private func quarantine(_ bytes: Data, keepOriginal: Bool, when: String) -> Bool {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        let name = url.deletingPathExtension().lastPathComponent
        // A directory that cannot be listed shows nothing kept; the copy or
        // move below then answers for itself.
        let kept = ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix(name + ".corrupt") }
        if kept.contains(where: { (try? Data(contentsOf: $0)) == bytes }) {
            // Already kept: whether the original goes too only decides
            // whether it is read again next launch.
            if !keepOriginal { try? fm.removeItem(at: url) }
            Self.log.notice("state file already kept aside\(when)")
            return true
        }
        var dest = dir.appendingPathComponent(name + ".corrupt.json")
        if fm.fileExists(atPath: dest.path) {
            dest = dir.appendingPathComponent(name + ".corrupt-\(UUID().uuidString).json")
        }
        do {
            if keepOriginal {
                try fm.copyItem(at: url, to: dest)
            } else {
                try fm.moveItem(at: url, to: dest)
            }
            Self.log.notice("state file put aside\(when)")
            return true
        } catch {
            Self.log.fault("state file could not be put aside\(when), left in place: \(error.localizedDescription)")
            return false
        }
    }
}
