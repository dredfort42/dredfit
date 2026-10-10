//
//  A home screen of the suite's own: places the Today widget through
//  AppWidgetManager the way a launcher does (the shell's `appwidget
//  grantbind` gives this package the launcher's bind permission), and shows
//  each placed widget at a chosen size in an activity — ui-test-manifest's
//  ComponentActivity, so nothing is added to the app. What the views show is
//  what the launcher would inflate: the RemoteViews Glance sent through
//  AppWidgetService. No Swift twin: XCUITest cannot place a widget either,
//  and the iOS suite never renders one.
//

package com.dredfit

import android.appwidget.AppWidgetHost
import android.appwidget.AppWidgetHostView
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProviderInfo
import android.content.ComponentName
import android.content.Context
import android.content.res.Configuration
import android.os.Bundle
import android.util.SizeF
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import com.dredfit.widgets.TodayStatusWidgetReceiver
import org.junit.Assert.assertTrue
import java.io.BufferedReader
import java.io.InputStreamReader
import kotlin.math.ceil

class WidgetHost : AutoCloseable {

    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    val app: Context = instrumentation.targetContext.applicationContext
    private val manager = AppWidgetManager.getInstance(app)
    private val provider = ComponentName(app, TodayStatusWidgetReceiver::class.java)
    private val host = AppWidgetHost(app, HOST_ID)
    private val ids = mutableListOf<Int>()
    private val scenario: ActivityScenario<ComponentActivity>
    private lateinit var screen: FrameLayout

    init {
        // `--user current` kills the command on API 37 (exit 137); the user
        // is named instead.
        val user = shell("am get-current-user").trim()
        shell("appwidget grantbind --package ${app.packageName} --user $user")
        // A host left by a run that died before its close.
        host.deleteHost()
        instrumentation.runOnMainSync { host.startListening() }
        scenario = ActivityScenario.launch(ComponentActivity::class.java)
        scenario.onActivity { activity ->
            screen = FrameLayout(activity)
            activity.setContentView(screen)
        }
    }

    val info: AppWidgetProviderInfo
        get() = manager.installedProviders.first { it.provider == provider }

    /** A widget placed at `size`, drawn in `night` mode or not, `top` px
     *  down the screen. */
    fun place(size: DpSize, night: Boolean = false, top: Int = 0): AppWidgetHostView {
        val id = host.allocateAppWidgetId()
        ids += id
        assertTrue("the shell's grantbind must let the suite bind", manager.bindAppWidgetIdIfAllowed(id, provider))
        lateinit var view: AppWidgetHostView
        val density = app.resources.displayMetrics.density
        val config = Configuration(app.resources.configuration).apply {
            uiMode = (uiMode and Configuration.UI_MODE_NIGHT_MASK.inv()) or
                if (night) Configuration.UI_MODE_NIGHT_YES else Configuration.UI_MODE_NIGHT_NO
        }
        scenario.onActivity { activity ->
            view = host.createView(activity.createConfigurationContext(config), id, info)
            view.updateAppWidgetSize(Bundle(), listOf(SizeF(size.width.value, size.height.value)))
            // Rounded up: a layout a pixel short of the size reads as the
            // next family down.
            screen.addView(view, FrameLayout.LayoutParams(ceil(size.width.value * density).toInt(),
                                                          ceil(size.height.value * density).toInt()).apply { topMargin = top })
        }
        return view
    }

    /** Every text the widget shows right now, in tree order. */
    fun texts(view: View): List<String> {
        val found = mutableListOf<String>()
        fun walk(v: View) {
            if (v is TextView && v.visibility == View.VISIBLE) found += v.text.toString()
            if (v is ViewGroup) for (i in 0 until v.childCount) walk(v.getChildAt(i))
        }
        instrumentation.runOnMainSync { walk(view) }
        return found
    }

    /** Waits until the widget shows `text`; fails with what it shows. */
    fun awaitText(view: View, text: String, timeoutMs: Long = 30_000) {
        val end = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < end) {
            if (text in texts(view)) return
            Thread.sleep(200)
        }
        throw AssertionError("the widget never showed \"$text\"; it shows ${texts(view)}")
    }

    /** The first view that takes a tap — the widget's whole surface. */
    fun tap(view: View) {
        fun clickable(v: View): View? {
            if (v.hasOnClickListeners()) return v
            if (v is ViewGroup) for (i in 0 until v.childCount) clickable(v.getChildAt(i))?.let { return it }
            return null
        }
        instrumentation.runOnMainSync { checkNotNull(clickable(view)) { "nothing in the widget takes a tap" }.performClick() }
    }

    /** Removes one placed widget, as dragging it off the home screen does. */
    fun remove(view: AppWidgetHostView) {
        host.deleteAppWidgetId(view.appWidgetId)
        ids -= view.appWidgetId
        scenario.onActivity { screen.removeView(view) }
    }

    override fun close() {
        ids.forEach(host::deleteAppWidgetId)
        ids.clear()
        instrumentation.runOnMainSync { host.stopListening() }
        host.deleteHost()
        scenario.close()
    }

    companion object {
        /** Any id: a host is the package's, and this package has no other. */
        private const val HOST_ID = 0xD4ED

        /** What a phone launcher gives a 2×2, a 4×2 and a 4×4 (Pixel-class
         *  grid, portrait) — the sizes the suite places and photographs. */
        val SMALL = DpSize(170.dp, 170.dp)
        val MEDIUM = DpSize(350.dp, 170.dp)
        val LARGE = DpSize(350.dp, 380.dp)

        fun shell(command: String): String {
            val pfd = InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand(command)
            return BufferedReader(InputStreamReader(android.os.ParcelFileDescriptor.AutoCloseInputStream(pfd))).use { it.readText() }
        }
    }
}
