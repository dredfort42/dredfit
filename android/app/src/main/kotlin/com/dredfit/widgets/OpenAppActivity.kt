//
//  The widget's tap: the app as it was left, as iOS's widget opens it (it
//  sets no `widgetURL`) — a running workout stays in front, Settings stays
//  open (owner decision, 11.10.2026). No Swift twin.
//
//  Why an activity of its own: Glance gives every click intent a unique data
//  URI, and an intent that differs from the task's root intent makes Android
//  stack a NEW MainActivity on top instead of bringing the task forward. So
//  the widget starts this one — invisible, in no task of the app's
//  (taskAffinity "") — and it moves the app's existing task to the front
//  exactly as it stands, whatever started it (the launcher, a reminder). With
//  no task left, it launches the app as its icon does. Allowed from Android
//  12 on: the restriction on trampolines is for notifications, and this one
//  runs in the foreground the widget's tap gave it.
//

package com.dredfit.widgets

import android.app.Activity
import android.app.ActivityManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Bundle
import com.dredfit.MainActivity

class OpenAppActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val main = MainActivity::class.java.name
        // The task that shows MainActivity, at its root or on top (a Play
        // review card or a picker can sit above it) — never this one.
        val existing = getSystemService(ActivityManager::class.java).appTasks.firstOrNull { task ->
            // A task can end between the listing and the look at it.
            val info = try { task.taskInfo } catch (_: IllegalArgumentException) { null }
            info != null && info.taskId != taskId &&
                (info.baseActivity?.className == main || info.topActivity?.className == main)
        }
        if (existing != null) {
            existing.moveToFront()
        } else {
            // The icon's intent (MAIN, LAUNCHER, no package or data), so the
            // icon later finds this task its own. NEW_TASK without the icon's
            // RESET_TASK_IF_NEEDED: with that flag a task of the app's
            // affinity that does not hold MainActivity would only be brought
            // forward, and MainActivity never shown.
            startActivity(Intent.makeMainActivity(ComponentName(this, MainActivity::class.java))
                              .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
        // Theme.NoDisplay: gone before it would be drawn.
        finish()
    }

    companion object {
        /** What the widget's tap starts. */
        fun intent(context: Context): Intent = Intent(context, OpenAppActivity::class.java)
    }
}
