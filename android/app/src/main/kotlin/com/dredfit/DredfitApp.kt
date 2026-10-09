//
//  The process-wide owner of the one store — iOS's `@State private var store`
//  in `DredfitApp`. One store for the life of the process: two would each
//  write the file from their own memory.
//
//  THE LOAD IS OFF THE MAIN THREAD. iOS reads the state file inside the
//  store's initializer, synchronously; here the store is constructed on the
//  ONE disk thread — the same thread that later writes it — and handed to the
//  main thread when it is ready, so a large journal on slow flash cannot hold
//  up the first frame long enough to ANR. Everything that asks for the store
//  before then waits for it (`withStore`), and the screen draws only the
//  ground meanwhile. Because the read and every write share one thread, no
//  write can ever reach the file before the read that the store was built
//  from: the disk sees exactly the order the store made its changes in.
//

package com.dredfit

import android.app.Application
import com.dredfit.signals.DeviceSignals
import com.dredfit.store.AppStore
import com.dredfit.ui.FlowHolder
import com.dredfit.ui.Observed
import java.nio.file.Path
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class DredfitApp : Application() {

    /** Every read and write of the state file, in order. */
    private val disk: ExecutorService = Executors.newSingleThreadExecutor { Thread(it, "dredfit-disk") }

    private val statePath: Path get() = filesDir.toPath().resolve(AppStore.STATE_FILE_NAME)

    // Main-thread state below: touched only from the main thread.
    private var store: Observed<AppStore>? = null
    private var loading = false
    private val waiting = mutableListOf<(Observed<AppStore>) -> Unit>()
    private var signals: DeviceSignals? = null

    /** The workout in flight — the process's, so a recreated activity finds
     *  it; a process death loses it to the snapshot and Today's resume card. */
    val flows = FlowHolder()

    /** Hands the store to `ready` on the main thread: at once when it is
     *  loaded, after the load otherwise. */
    fun withStore(ready: (Observed<AppStore>) -> Unit) {
        store?.let { return ready(it) }
        waiting += ready
        if (loading) return
        loading = true
        disk.execute {
            val loaded = AppStore(statePath, disk = disk, main = mainExecutor)
            mainExecutor.execute {
                val observed = Observed(loaded)
                // The one subscription: every change the store makes — a
                // write result coming back included — redraws what read it.
                loaded.observe { observed.changed() }
                store = observed
                loading = false
                waiting.toList().forEach { it(observed) }
                waiting.clear()
            }
        }
    }

    /** The real tones and haptics, built once on first use; they fire on the
     *  main thread, where the store lives. */
    fun signals(): DeviceSignals =
        signals ?: DeviceSignals(this) { store?.value?.settings?.playsTonesInSilentMode ?: false }
            .also { signals = it }

    /**
     * The UI suite's `--uitest-reset`: drops the loaded store and the flow,
     * then runs `seed` on the disk thread — after every write already queued,
     * so nothing the previous test made lands on top of the seed. The next
     * `withStore` loads afresh from what the seed left. Called from the
     * instrumentation thread with no activity open.
     */
    internal fun resetForTests(onMain: (Runnable) -> Unit, seed: (Path) -> Unit) {
        onMain(Runnable {
            store = null
            flows.active = null
        })
        disk.submit { seed(statePath) }.get()
    }
}
