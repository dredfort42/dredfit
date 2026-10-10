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
import android.app.UiModeManager
import android.content.res.Configuration
import android.os.Build
import android.os.LocaleList
import com.dredfit.ongoing.OngoingNotification
import com.dredfit.reminders.SystemNotificationScheduler
import com.dredfit.signals.DeviceSignals
import com.dredfit.store.AppStore
import com.dredfit.ui.FlowHolder
import com.dredfit.ui.Observed
import com.dredfit.ui.workout.ReviewPrompt
import com.dredfit.widgets.WidgetCenter
import androidx.work.Configuration as WorkConfiguration
import java.nio.file.Path
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class DredfitApp : Application(), WorkConfiguration.Provider {

    /** WorkManager, on demand (AndroidManifest.xml removes its startup
     *  initializer): only a widget's draw needs it. */
    override fun getWorkManagerConfiguration(): WorkConfiguration = WorkConfiguration.Builder().build()

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
    val flows by lazy { FlowHolder(ongoing) }

    /** The ongoing-workout notification and its service — one per process,
     *  as there is one flow. */
    val ongoing by lazy { OngoingNotification(this) }

    /** The reminders' alarms, channel and permission — one per process, so
     *  a question asked from Settings is answered to the store that asked,
     *  whichever activity the answer reaches. Built on first use, by the
     *  disk thread that builds the store or a receiver on the main one. */
    val reminders by lazy { SystemNotificationScheduler(this) }

    /** The home-screen widget's feed, file and redraws — one per process, as
     *  every widget session and the store must see the same feed. Its file
     *  writes share the store's disk thread. */
    val widgets by lazy { WidgetCenter(this, disk) }

    /** What the widget was last drawn for: the language, and the night mode
     *  where Glance resolves it itself. */
    private var drawnFor: Pair<LocaleList, Int>? = null

    private fun drawnFor(config: Configuration): Pair<LocaleList, Int> = config.locales to
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) 0 else config.uiMode and Configuration.UI_MODE_NIGHT_MASK

    override fun onCreate() {
        super.onCreate()
        drawnFor = drawnFor(resources.configuration)
        // Android 14's contrast is no configuration change (RootScreen
        // listens the same way): a raised level redraws the widget in the
        // palette's second column while the process lives; a dead one draws
        // it at the next draw.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            getSystemService(UiModeManager::class.java)
                ?.addContrastChangeListener(mainExecutor) { widgets.refresh() }
        }
    }

    /**
     * A per-app language changed in the system's settings reaches a live
     * process here and no broadcast says it, so the widget is redrawn in the
     * new language — and on Android 10–11, where Glance resolves the day/night
     * colours when it draws (12+ hands both to the launcher), in the new mode.
     */
    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        val now = drawnFor(newConfig)
        if (now == drawnFor) return
        drawnFor = now
        widgets.refresh()
    }

    /** The UI suite's stand-in for Play In-App Review, so a walk sees the
     *  ask the milestone's Done makes instead of sending it to Play. Set
     *  only by androidTest (ReviewAskWalkTest) before the activity opens;
     *  nothing in the app writes it, so a release build always asks Play. */
    @Volatile
    var reviewPromptForTests: ReviewPrompt? = null

    /** Hands the store to `ready` on the main thread: at once when it is
     *  loaded, after the load otherwise. */
    fun withStore(ready: (Observed<AppStore>) -> Unit) {
        store?.let { return ready(it) }
        waiting += ready
        if (loading) return
        loading = true
        disk.execute {
            val loaded = AppStore(statePath, disk = disk, main = mainExecutor, notifications = reminders,
                                  widgets = widgets)
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
            // Closed, not just dropped: a flow dropped alone would keep its
            // beat, its service and its wake lock into the next test.
            flows.active?.close()
            flows.active = null
        })
        disk.submit { seed(statePath) }.get()
    }
}
