//
//  The one file the app keeps: engine state, journal, settings and the
//  workout in progress, read and written whole. One atomic write of one file
//  is what keeps the four consistent with each other across a crash.
//  Port of ios/Dredfit/StateFile.swift.
//
//  Plain java.nio, no Android import: the store and its tests run on the JVM.
//  The app hands it `filesDir/dredfit-state.json` — the counterpart of
//  Application Support.
//

package com.dredfit.store

import com.dredfit.core.SwiftDecodingException
import java.io.IOException
import java.nio.ByteBuffer
import java.nio.channels.FileChannel
import java.nio.file.AtomicMoveNotSupportedException
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.StandardCopyOption
import java.nio.file.StandardOpenOption
import java.util.UUID
import java.util.logging.Logger

class StateFile(val path: Path) {

    sealed interface Read {
        /** No file: a fresh install. */
        data object Absent : Read

        /** The file is there and cannot be read — or it was read but could not
         *  be put aside before a write would replace it. Nothing is touched:
         *  it may be the only copy of the journal. */
        data object Unreadable : Read

        /** The file does not decode as a whole. It was moved aside, so the
         *  next write cannot overwrite the only copy of the journal. */
        data object Undecodable : Read

        class Loaded(val data: AppData) : Read
    }

    /**
     * Reads the file. One that does not decode is MOVED aside; one whose
     * engine state or some of whose records could not be read is COPIED aside
     * first, because the next write rewrites the positions from `initial`, or
     * the journal without the unreadable entries (#279/#282). An unreadable
     * settings block or snapshot costs only itself and is not copied.
     */
    fun read(reload: Boolean): Read {
        val whenLabel = if (reload) " on reload" else ""
        val bytes = try {
            Files.readAllBytes(path)
        } catch (_: IOException) {
            return if (Files.exists(path)) Read.Unreadable else Read.Absent
        }
        val data = try {
            AppData.decode(bytes.toString(Charsets.UTF_8))
        } catch (e: SwiftDecodingException) {
            log.severe("state file failed to decode$whenLabel: ${e.message}")
            return if (quarantine(bytes, keepOriginal = false, whenLabel)) Read.Undecodable else Read.Unreadable
        }
        if (data.engineStateReset) {
            // A v2 state is carried over, so this is a state that is neither
            // v3 NOR v2 — a future build's, or one damaged past reading.
            log.info("engine state unreadable in both shapes$whenLabel, journal whole")
            if (!quarantine(bytes, keepOriginal = true, whenLabel)) return Read.Unreadable
        }
        if (data.droppedRecordCount > 0) {
            log.warning("${data.droppedRecordCount} unreadable record(s)$whenLabel")
            if (!quarantine(bytes, keepOriginal = true, whenLabel)) return Read.Unreadable
        }
        return Read.Loaded(data)
    }

    /**
     * One atomic write: the file is either the old one or the new one, never
     * half of each — Swift's `.atomic`. The bytes go to a sibling temp file,
     * are forced to the disk, and replace the target in one rename; a failed
     * write leaves the old file exactly as it was.
     */
    @Throws(IOException::class)
    fun write(data: AppData) = write(data.encode().toByteArray(Charsets.UTF_8))

    /** The same write for bytes already encoded: the store encodes on the
     *  thread that made the change and writes on its disk thread. */
    @Throws(IOException::class)
    fun write(bytes: ByteArray) {
        // No directory is created here: Swift's `.atomic` write fails into a
        // missing one too, and the app's files directory always exists.
        val temp = Files.createTempFile(path.toAbsolutePath().parent, ".${path.fileName}", ".tmp")
        try {
            FileChannel.open(temp, StandardOpenOption.WRITE, StandardOpenOption.TRUNCATE_EXISTING).use { ch ->
                val buffer = ByteBuffer.wrap(bytes)
                while (buffer.hasRemaining()) ch.write(buffer)
                ch.force(true)
            }
            try {
                Files.move(temp, path, StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
            } catch (_: AtomicMoveNotSupportedException) {
                // Every Android data directory is one filesystem, where a
                // rename is atomic; this is a JVM host without that promise,
                // and replacing is the best it offers.
                Files.move(temp, path, StandardCopyOption.REPLACE_EXISTING)
            }
        } finally {
            Files.deleteIfExists(temp)
        }
    }

    /**
     * Moves (or copies, when the readable part is kept) the file to
     * `<name>.corrupt.json`. An earlier quarantine is NEVER replaced — after a
     * whole-file failure it is the only copy of the journal the app started
     * over from; a later one gets a unique name, and the same bytes already
     * kept aside are not kept twice. Returns whether the bytes are safe aside:
     * when not, the read reports the file unreadable and the launch freezes
     * rather than write on top of the only copy.
     */
    private fun quarantine(bytes: ByteArray, keepOriginal: Boolean, whenLabel: String): Boolean {
        val dir = path.toAbsolutePath().parent
        val name = path.fileName.toString().substringBeforeLast('.')
        // A directory that cannot be listed shows nothing kept; the copy or
        // move below then answers for itself.
        val kept = try {
            Files.newDirectoryStream(dir).use { s -> s.filter { it.fileName.toString().startsWith("$name.corrupt") } }
        } catch (_: IOException) {
            emptyList()
        }
        if (kept.any { p -> (try { Files.readAllBytes(p) } catch (_: IOException) { null })?.contentEquals(bytes) == true }) {
            // Already kept: whether the original goes too only decides
            // whether it is read again next launch.
            if (!keepOriginal) {
                try {
                    Files.deleteIfExists(path)
                } catch (_: IOException) {
                    // Read again next launch, and found already kept again.
                }
            }
            log.info("state file already kept aside$whenLabel")
            return true
        }
        var dest = dir.resolve("$name.corrupt.json")
        if (Files.exists(dest)) dest = dir.resolve("$name.corrupt-${UUID.randomUUID().toString().uppercase()}.json")
        return try {
            if (keepOriginal) Files.copy(path, dest) else Files.move(path, dest)
            log.info("state file put aside$whenLabel")
            true
        } catch (e: IOException) {
            log.severe("state file not put aside$whenLabel: ${e.message}")
            false
        }
    }

    private companion object {
        val log: Logger = Logger.getLogger("com.dredfit.store")
    }
}
