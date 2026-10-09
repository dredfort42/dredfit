//
//  The Play half of the review ask (review/PlayReview.kt) against Play's own
//  FakeReviewManager: a card Play agrees to is launched over the activity
//  that asked, and a refusal (no Play Store, among others) launches nothing
//  and crashes nothing. WHEN the ask happens is ReviewAskTest's (JVM).
//

package com.dredfit

import android.app.Activity
import androidx.activity.ComponentActivity
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.dredfit.review.PlayReviewPrompt
import com.google.android.gms.tasks.Task
import com.google.android.gms.tasks.Tasks
import com.google.android.play.core.review.ReviewInfo
import com.google.android.play.core.review.ReviewManager
import com.google.android.play.core.review.testing.FakeReviewManager
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class PlayReviewPromptTest {

    /** FakeReviewManager, with a record of what was launched over what — and
     *  optionally Play saying no. */
    private class Recording(private val play: ReviewManager, private val refuses: Boolean) : ReviewManager {
        val launchedOver = mutableListOf<Activity>()

        override fun requestReviewFlow(): Task<ReviewInfo> =
            if (refuses) Tasks.forException(IllegalStateException("no Play Store")) else play.requestReviewFlow()

        override fun launchReviewFlow(activity: Activity, reviewInfo: ReviewInfo): Task<Void> {
            launchedOver += activity
            return play.launchReviewFlow(activity, reviewInfo)
        }
    }

    /** Asks over a live activity and lets the main looper deliver Play's answer. */
    private fun ask(refuses: Boolean): Pair<Recording, Activity> {
        ActivityScenario.launch(ComponentActivity::class.java).use { scenario ->
            lateinit var result: Pair<Recording, Activity>
            scenario.onActivity { activity ->
                val manager = Recording(FakeReviewManager(activity), refuses)
                PlayReviewPrompt(activity, manager).request()
                result = manager to activity
            }
            InstrumentationRegistry.getInstrumentation().waitForIdleSync()
            scenario.onActivity { }
            return result
        }
    }

    @Test
    fun aCardPlayAgreesToIsLaunchedOverTheAskingActivity() {
        val (manager, activity) = ask(refuses = false)
        assertEquals(1, manager.launchedOver.size)
        assertSame(activity, manager.launchedOver.single())
    }

    @Test
    fun aRefusalLaunchesNothing() {
        val (manager, _) = ask(refuses = true)
        assertEquals(0, manager.launchedOver.size)
    }
}
