//
//  The home-screen widget: what each size draws, and the Glance widget and
//  receiver that draw it. Port of ios/DredfitWidgets/TodayStatusWidget.swift.
//  The store writes the snapshot (WidgetBridge.kt); this file only reads it,
//  one entry per day (TodayProvider.kt).
//
//  The families (android/README.md, "The home-screen widget"):
//  - iOS's three home-screen families become ONE resizable widget with three
//    responsive layouts (`SizeMode.Responsive`): small, medium and large are
//    drawn up front and the launcher picks by the size the person gave it,
//    as the iOS gallery offers the three sizes — no redraw on a resize, no
//    app process for it. `TodayFamily` holds the breakpoints.
//  - The lock-screen accessories (circular, rectangular, inline) have no
//    Android twin. Android 16's lock-screen widgets are this same widget in
//    the hub the system shows while charging or docked — eligible by default,
//    with no layout of their own — so nothing here opts out (`not_keyguard`)
//    and nothing is drawn twice. Their words go with them: `subline`, the
//    spoken range, the glyph and the inline length are not ported.
//
//  What Glance cannot draw the way SwiftUI does, and what stands in:
//  circles and rings are tinted shape drawables (res/drawable/widget_*.xml);
//  "heavy"/"semibold" are Glance's Bold/Medium (it has three weights);
//  `minimumScaleFactor` and head truncation do not exist in RemoteViews, so a
//  long line ends in an ellipsis; no kerning; no tabular figures.
//

package com.dredfit.widgets

import android.app.UiModeManager
import android.content.Context
import android.content.Intent
import android.content.res.Resources
import android.os.Build
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.ColorFilter
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalSize
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.appWidgetBackground
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.color.ColorProvider
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.semantics.semantics
import androidx.glance.semantics.testTag
import androidx.glance.state.GlanceStateDefinition
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import com.dredfit.DredfitApp
import com.dredfit.MainActivity
import com.dredfit.R
import com.dredfit.ui.theme.Palette
import com.dredfit.ui.today.NextTrainingDateLabel
import com.dredfit.ui.tr
import com.dredfit.workout.Words
import java.time.format.TextStyle as DayNameStyle
import java.util.Locale

// MARK: - Words

/**
 * What a day says, as `Words` — iOS's `headline` and `nextPlanText`, which
 * WidgetTimelineTests pins per status, plus the week line iOS could not test
 * (its `Text` chain). Plain Kotlin: a JVM test reads it without a device.
 */
class TodayStatusView(val entry: TodayEntry) {

    val headline: Words
        get() = when (entry.status) {
            WidgetSnapshot.DayStatus.workout ->
                entry.sessionNumber?.let { Words.of("Workout %lld", it) } ?: Words.of("Workout day")
            WidgetSnapshot.DayStatus.done -> Words.of("Done ✓")
            WidgetSnapshot.DayStatus.rest -> Words.of("Rest day")
            WidgetSnapshot.DayStatus.unmarked, null -> Words.of("Dredfit")
        }

    /** The accent dot above a workout day's headline. */
    val marksWorkout: Boolean get() = entry.status == WidgetSnapshot.DayStatus.workout

    /** A rest day's headline is the quieter ink. */
    val restful: Boolean get() = entry.status == WidgetSnapshot.DayStatus.rest

    /** The entry's own next training day, spoken from the entry's day. */
    fun nextLabel(locale: Locale): Words? =
        entry.nextDate?.let { NextTrainingDateLabel.words(next = it, from = entry.date, locale = locale) }

    /** "Next: Workout 12 · tomorrow" — on a day that is not itself the
     *  workout, and only when both halves arrived: a half-line reads as a
     *  promise for today. */
    fun nextPlanText(locale: Locale): Words? {
        if (entry.status == WidgetSnapshot.DayStatus.workout) return null
        val n = entry.planSessionNumber ?: return null
        val whenWords = nextLabel(locale) ?: return null
        return Words.of("Next: Workout %lld · %@", n, whenWords)
    }

    /** "This week · 3 workouts · +6 steps": the sign is its own segment, so a
     *  deload week reads −2 rather than hiding. Only inside its week. */
    val weekSummary: Words?
        get() {
            val week = entry.summary ?: return null
            val sign = if (week.stepsDelta >= 0) "+" else ""
            return Words.join("%@ · %@%@%@", Words.of("This week"), Words.of("%lld workouts", week.workouts),
                              Words.of(" · %@", sign), Words.of("%lld steps", week.stepsDelta))
        }

    /** The medium size's number beside "steps". */
    val totalSteps: Words? get() = entry.totalSteps?.let { Words.of("%lld", it) }
}

// MARK: - Sizes

/** iOS's home-screen families, by the size Glance draws for. The
 *  breakpoints are what each layout needs: the small two cells square, the
 *  medium's week strip under its headline about 140 dp of height across four
 *  columns, the large's plan list a four-by-four (a 4×3 is still a medium:
 *  six plan rows would not fit it). */
enum class TodayFamily {
    small, medium, large;

    companion object {
        val SMALL = DpSize(110.dp, 110.dp)
        val MEDIUM = DpSize(250.dp, 140.dp)
        val LARGE = DpSize(250.dp, 320.dp)
        val sizes: Set<DpSize> = setOf(SMALL, MEDIUM, LARGE)

        fun of(size: DpSize): TodayFamily = when {
            size.width >= LARGE.width && size.height >= LARGE.height -> large
            size.width >= MEDIUM.width && size.height >= MEDIUM.height -> medium
            else -> small
        }
    }
}

// MARK: - The palette

/** The app's tokens (ui/theme), light by day and dark by night: the host
 *  picks by the SYSTEM's mode on Android 12+, never by the in-app Appearance
 *  — which the Settings caption says. Increased contrast takes the second
 *  column, as on iOS, read when the widget is drawn. */
class WidgetColors(highContrast: Boolean) {
    private val day = Palette.of(dark = false, highContrast = highContrast)
    private val night = Palette.of(dark = true, highContrast = highContrast)

    val bg: ColorProvider = ColorProvider(day.bg, night.bg)
    val ink: ColorProvider = ColorProvider(day.ink, night.ink)
    val ink2: ColorProvider = ColorProvider(day.ink2, night.ink2)
    val hairline: ColorProvider = ColorProvider(day.hairline, night.hairline)
    val restFill: ColorProvider = ColorProvider(day.restFill, night.restFill)
    val accent: ColorProvider = ColorProvider(day.accent, night.accent)
    /** iOS's `Theme.planned`, an alias of ink3 — a graphics tone. */
    val planned: ColorProvider = ColorProvider(day.ink3, night.ink3)

    companion object {
        /** Android 14's contrast setting — iOS's Increased Contrast. */
        fun highContrast(context: Context): Boolean {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return false
            val manager = context.getSystemService(UiModeManager::class.java) ?: return false
            return manager.contrast > 0f
        }
    }
}

// MARK: - The views

/**
 * One entry, drawn at one family. `say` resolves the words — the widget's
 * own catalog first (`Resources.tr(…, widget = true)`) — and `locale` names
 * the weekdays and the next day.
 */
@Composable
fun TodayStatusContent(entry: TodayEntry, family: TodayFamily, colors: WidgetColors,
                       say: (Words) -> String, locale: Locale, open: Intent?) {
    val view = TodayStatusView(entry)
    val tap = open?.let { GlanceModifier.clickable(actionStartActivity(it)) } ?: GlanceModifier
    // The system's widget radius exists from Android 12; below it a widget
    // has square corners, as every other one on that launcher.
    val corners = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        GlanceModifier.cornerRadius(android.R.dimen.system_app_widget_background_radius)
    } else GlanceModifier
    Box(GlanceModifier.fillMaxSize().appWidgetBackground().background(colors.bg).then(corners)
            .then(tap).padding(16.dp)) {
        when (family) {
            TodayFamily.small -> Column(GlanceModifier.fillMaxSize()) {
                Kicker(say, locale, colors)
                Spacer(GlanceModifier.defaultWeight())
                StatusBlock(view, 20.sp, say, colors)
            }
            TodayFamily.medium -> Column(GlanceModifier.fillMaxSize()) {
                Row(GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.Bottom) {
                    Kicker(say, locale, colors)
                    Spacer(GlanceModifier.defaultWeight())
                    TotalSteps(view, say, colors)
                }
                Spacer(GlanceModifier.defaultWeight())
                StatusBlock(view, 22.sp, say, colors)
                Spacer(GlanceModifier.defaultWeight())
                Hairline(colors)
                Spacer(GlanceModifier.height(10.dp))
                WeekStrip(entry, locale, colors)
            }
            TodayFamily.large -> Column(GlanceModifier.fillMaxSize()) {
                Kicker(say, locale, colors)
                Spacer(GlanceModifier.height(10.dp))
                StatusBlock(view, 22.sp, say, colors)
                view.nextPlanText(locale)?.let {
                    Spacer(GlanceModifier.height(12.dp))
                    Line(say(it), 11.sp, FontWeight.Medium, colors.ink2, "widget-next")
                }
                if (entry.plan.isNotEmpty()) {
                    Spacer(GlanceModifier.height(10.dp))
                    PlanList(entry, say, colors)
                }
                Spacer(GlanceModifier.defaultWeight())
                view.weekSummary?.let { Line(say(it), 11.5.sp, FontWeight.Normal, colors.ink2, "widget-week") }
            }
        }
    }
}

@Composable
private fun Line(text: String, size: TextUnit, weight: FontWeight, color: ColorProvider, tag: String,
                 modifier: GlanceModifier = GlanceModifier) {
    Text(text, modifier.semantics { testTag = tag },
         style = TextStyle(color = color, fontSize = size, fontWeight = weight), maxLines = 1)
}

@Composable
private fun Kicker(say: (Words) -> String, locale: Locale, colors: WidgetColors) {
    Line(say(Words.of("Today")).uppercase(locale), 11.sp, FontWeight.Medium, colors.ink2, "widget-kicker")
}

@Composable
private fun StatusBlock(view: TodayStatusView, size: TextUnit, say: (Words) -> String, colors: WidgetColors) {
    Column {
        if (view.marksWorkout) {
            Mark(R.drawable.widget_dot, colors.accent, 10, "widget-dot")
            Spacer(GlanceModifier.height(6.dp))
        }
        Line(say(view.headline), size, FontWeight.Bold, if (view.restful) colors.ink2 else colors.ink, "widget-headline")
    }
}

@Composable
private fun TotalSteps(view: TodayStatusView, say: (Words) -> String, colors: WidgetColors) {
    val steps = view.totalSteps ?: return
    Row(verticalAlignment = Alignment.Bottom) {
        Line(say(steps), 22.sp, FontWeight.Bold, colors.ink, "widget-steps")
        Spacer(GlanceModifier.width(4.dp))
        Line(say(Words.of("steps")), 10.5.sp, FontWeight.Normal, colors.ink2, "widget-steps-unit")
    }
}

@Composable
private fun Hairline(colors: WidgetColors) {
    Spacer(GlanceModifier.fillMaxWidth().height(0.5.dp).background(colors.hairline))
}

@Composable
private fun WeekStrip(entry: TodayEntry, locale: Locale, colors: WidgetColors) {
    Row(GlanceModifier.fillMaxWidth()) {
        for (day in entry.week) {
            Column(GlanceModifier.defaultWeight(), horizontalAlignment = Alignment.CenterHorizontally) {
                // One tone for all seven letters: the day's state is the MARK
                // below (TodayStatusWidget.swift says why not ink3).
                Line(day.date.dayOfWeek.getDisplayName(DayNameStyle.NARROW, locale), 10.sp, FontWeight.Medium,
                     colors.ink2, "widget-day-${day.date}")
                Spacer(GlanceModifier.height(5.dp))
                DayMark(day, isToday = day.date == entry.date, colors)
            }
        }
    }
}

@Composable
private fun DayMark(day: WidgetSnapshot.Day, isToday: Boolean, colors: WidgetColors) {
    Box(GlanceModifier.size(14.dp), contentAlignment = Alignment.Center) {
        when (day.status) {
            WidgetSnapshot.DayStatus.done -> Mark(R.drawable.widget_dot, colors.accent, 14, "mark-done")
            WidgetSnapshot.DayStatus.rest -> Mark(R.drawable.widget_dot, colors.restFill, 14, "mark-rest")
            WidgetSnapshot.DayStatus.workout -> Mark(R.drawable.widget_ring, colors.planned, 14, "mark-workout")
            WidgetSnapshot.DayStatus.unmarked -> Unit
        }
        if (isToday && day.status != WidgetSnapshot.DayStatus.done) {
            Mark(R.drawable.widget_ring_today, colors.accent, 14, "mark-today")
        }
    }
}

@Composable
private fun Mark(drawable: Int, color: ColorProvider, sizeDp: Int, tag: String) {
    Image(ImageProvider(drawable), contentDescription = null,
          modifier = GlanceModifier.size(sizeDp.dp).semantics { testTag = tag },
          colorFilter = ColorFilter.tint(color))
}

@Composable
private fun PlanList(entry: TodayEntry, say: (Words) -> String, colors: WidgetColors) {
    // A Glance column holds at most ten children, so each row carries the
    // hairline above it rather than standing beside it.
    Column(GlanceModifier.fillMaxWidth().semantics { testTag = "widget-plan" }) {
        entry.plan.forEachIndexed { index, row ->
            Column(GlanceModifier.fillMaxWidth()) {
                if (index > 0) Hairline(colors)
                Row(GlanceModifier.fillMaxWidth().padding(vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically) {
                    // The name takes what the dose leaves: one line each, or a
                    // long dose would grow every row of a list that already
                    // fills the widget.
                    Line(say(row.title), 13.5.sp, FontWeight.Normal, colors.ink, "widget-plan-name",
                         GlanceModifier.defaultWeight())
                    Spacer(GlanceModifier.width(8.dp))
                    Line(say(row.detail), 13.sp, FontWeight.Medium, colors.ink2, "widget-plan-detail")
                }
            }
        }
    }
}

// MARK: - The widget

class TodayStatusWidget : GlanceAppWidget() {

    override val sizeMode: SizeMode = SizeMode.Responsive(TodayFamily.sizes)

    override val previewSizeMode: SizeMode.Responsive = SizeMode.Responsive(TodayFamily.sizes)

    /** No per-widget state: every placed widget draws the one snapshot, so
     *  Glance's own store per widget would be a file per widget for nothing. */
    override val stateDefinition: GlanceStateDefinition<*>? = null

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val center = (context.applicationContext as DredfitApp).widgets
        center.prepare()
        val colors = WidgetColors(WidgetColors.highContrast(context))
        val open = MainActivity.openToday(context)
        provideContent {
            // Collected, not read once: a session outlives the update that
            // started it, and a write or a midnight inside it must redraw it.
            val feed by center.feed.collectAsState()
            Draw(context.resources, TodayProvider.entry(feed.snapshot, feed.today), colors, open)
        }
    }

    override suspend fun providePreview(context: Context, widgetCategory: Int) {
        val center = (context.applicationContext as DredfitApp).widgets
        center.prepare()
        val feed = center.feed.value
        val colors = WidgetColors(highContrast = false)
        provideContent {
            Draw(context.resources, TodayProvider.entry(feed.snapshot, feed.today), colors, open = null)
        }
    }

    @Composable
    private fun Draw(res: Resources, entry: TodayEntry, colors: WidgetColors, open: Intent?) {
        TodayStatusContent(entry, TodayFamily.of(LocalSize.current), colors, say = { res.tr(it, widget = true) },
                           locale = res.configuration.locales[0], open = open)
    }
}

/** The widget's door from the system: placement, resize, removal, a system
 *  language change (Glance redraws on LOCALE_CHANGED) and the midnight
 *  alarm WidgetCenter books. */
class TodayStatusWidgetReceiver : GlanceAppWidgetReceiver() {

    override val glanceAppWidget: GlanceAppWidget = TodayStatusWidget()

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == WidgetCenter.ACTION_MIDNIGHT) {
            // The same snapshot, for the day it is now; the next midnight
            // is booked by the redraw.
            (context.applicationContext as DredfitApp).widgets.refresh()
            return
        }
        super.onReceive(context, intent)
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        // The last widget is gone: nothing is left to redraw at midnight.
        (context.applicationContext as DredfitApp).widgets.cancelMidnight()
    }
}
