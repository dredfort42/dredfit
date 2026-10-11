//
//  The pull slot caps a push's sets, and two rules keep that cap honest: a
//  push enters its next set band only once the pull slot shows that many sets
//  after its own session, and a push whose position stands gets back exactly
//  the sets the cap has handed back since it was last shown. The golden
//  fixture pins both through whole scenarios; each test here names one face
//  of one rule, so a port that breaks it says which.
//
//  Port of PushGateTests.swift.
//

package com.dredfit.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull

class PushGateTest {

    // MARK: - Helpers

    /** A position on the TOP variation of `p`, with a journal that has shown
     *  every rung — the state a person who climbed the ladder carries. */
    private fun put(s: EngineState, p: Pattern, sets: Int = EngineConfig.setsBase,
                    dose: Int, sub: Int = 0, cut: Int = 0) {
        val top = Library.count(p)
        s.vars[p] = top
        s.doses[p] = dose
        if (sets == EngineConfig.setsBase) s.sets.remove(p) else s.sets[p] = sets
        if (sub > 0) s.sub[p] = sub else s.sub.remove(p)
        if (cut > 0) s.cut[p] = cut else s.cut.remove(p)
        val journal = mutableMapOf<Int, Int>()
        for (v in 1..top) journal[v] = Dose.grid(Library.unit(p, v)).max
        s.shown[p] = journal
    }

    /** The pull on its fourth variation — below the top, so no band ever
     *  opens for it, and its count of sets moves only by its cut. */
    private fun putLowPull(s: EngineState, dose: Int, cut: Int = 0) {
        s.vars[Pattern.pull] = 4
        s.doses[Pattern.pull] = dose
        if (cut > 0) s.cut[Pattern.pull] = cut else s.cut.remove(Pattern.pull)
        s.shown[Pattern.pull] = mutableMapOf(1 to 15, 2 to 15, 3 to 15, 4 to dose)
    }

    private fun onScreen(s: EngineState, p: Pattern): Int {
        val q = s.position(p)
        return Engine.setsAfterCut(sets = q.sets, cut = q.cut)
    }

    private fun exercise(s: EngineState, p: Pattern): SessionExercise? =
        Engine.generateSession(s).exercises.firstOrNull { it.pattern == p }

    /** One session of the app's order: the plan is shown, then rated, then
     *  the sets skipped during it land, then the steps added for next time. */
    private fun train(s: EngineState, result: FeedbackResult = FeedbackResult.plan,
                      overrides: Map<Pattern, Double> = emptyMap(),
                      skipped: Set<Pattern> = emptySet(),
                      setsSkipped: Map<Pattern, Int> = emptyMap(),
                      raised: Map<Pattern, Int> = emptyMap(),
                      gapDays: Double? = null): EngineState {
        val session = Engine.generateSession(s)
        return Engine.applyFeedback(state = s, session = session, result = result,
                                    overrides = overrides, skipped = skipped,
                                    setsSkipped = setsSkipped, gapDays = gapDays,
                                    probes = emptyMap(), raised = raised)
    }

    // MARK: - A push enters a band behind the pull

    /** Archer push-ups on their ceiling would enter 4×11 while the pull
     *  stands on three sets — and the cap would then show 3×11, a quarter less
     *  than the 3×15 just done, under a "Now 4 sets" that is not true. The
     *  push waits on its ceiling instead; with the pull on four it enters. */
    @Test
    fun aPushWaitsOnItsCeilingWhileThePullShowsFewerSets() {
        val s = EngineState.initial
        put(s, Pattern.pushH, dose = 15)
        put(s, Pattern.pull, dose = 14, sub = 2)
        val after = train(s)
        assertEquals(3, onScreen(after, Pattern.pull), "the pull stays on three this session")
        assertEquals(3, after.position(Pattern.pushH).sets, "the push does not enter band 4 ahead of the pull")
        assertEquals(15, after.position(Pattern.pushH).dose, "it waits on its ceiling")

        val control = EngineState.initial
        put(control, Pattern.pushH, dose = 15)
        put(control, Pattern.pull, sets = 4, dose = 11)
        val entered = train(control).position(Pattern.pushH)
        assertEquals(listOf(4, 11), listOf(entered.sets, entered.dose), "control: with the pull on four it enters")
    }

    /** The pull is read AFTER its own growth this session: a pull that
     *  enters band 4 in the same session lets the push in with it. */
    @Test
    fun aPushEntersBehindAPullThatRoseInTheSameSession() {
        val s = EngineState.initial
        put(s, Pattern.pushH, dose = 15)
        put(s, Pattern.pull, dose = 15)
        val after = train(s)
        assertEquals(4, after.position(Pattern.pull).sets, "the pull entered band 4 this session")
        assertEquals(listOf(4, 11), listOf(after.position(Pattern.pushH).sets, after.position(Pattern.pushH).dose))
    }

    /** The pull is read after its weekly window too. Its main loop enters
     *  band 4, the spent window takes that back, and the push reads the pull
     *  as it actually stands — on three. */
    @Test
    fun thePullIsReadAfterItsWeeklyWindow() {
        val s = EngineState.initial
        put(s, Pattern.pushH, dose = 15)
        put(s, Pattern.pull, dose = 15)
        s.weekGain[Pattern.pull] = EngineConfig.weeklyRiseSlow
        s.weekAgeDays = 1.0
        val after = train(s, gapDays = 0.5)
        assertEquals(3, after.position(Pattern.pull).sets, "the window kept the pull on three")
        assertEquals(3, after.position(Pattern.pushH).sets, "the push waits for the pull the window kept")
    }

    /** And after a fall in the same session: the pull showed four, a number
     *  below the floor of its variation sent it down to three sets. The
     *  better of "before" and "after" would let the push into 4×11 and the
     *  next plan would cap it at 3×11. */
    @Test
    fun thePullIsReadAfterAFallInTheSameSession() {
        val s = EngineState.initial
        put(s, Pattern.pushH, dose = 15)
        put(s, Pattern.pull, sets = 4, dose = 11)
        val after = train(s, overrides = mapOf(Pattern.pull to 2.0))
        assertEquals(Library.count(Pattern.pull) - 1, after.vars[Pattern.pull], "the pull went a variation down")
        assertEquals(3, onScreen(after, Pattern.pull))
        assertEquals(3, after.position(Pattern.pushH).sets, "the push waits for the pull that fell")
    }

    /** With the bar the weaker branch decides, and the cross-credit counts:
     *  the credit that carries the bar's branch into band 4 lets the push in
     *  within the same session; a credit that leaves the branch on three
     *  does not. */
    @Test
    fun withTheBarTheWeakerBranchDecidesAndTheCreditCounts() {
        fun slot(barDose: Int, barSub: Int): EngineState {
            val s = EngineState.initial
            s.hasBar = true
            put(s, Pattern.pushH, dose = 15)
            put(s, Pattern.pull, sets = 4, dose = 11)
            put(s, Pattern.pullBar, dose = barDose, sub = barSub)
            return s
        }
        val credited = train(slot(barDose = 15, barSub = 0))
        assertEquals(4, credited.position(Pattern.pullBar).sets, "the credit carried the bar's branch into band 4")
        assertEquals(4, credited.position(Pattern.pushH).sets, "and the push entered with it")

        val short = train(slot(barDose = 14, barSub = 1))
        assertEquals(3, short.position(Pattern.pullBar).sets, "a credit of one event leaves the branch on three")
        assertEquals(3, short.position(Pattern.pushH).sets, "the weaker branch keeps the push waiting")
    }

    /** The other branch's weekly window comes before the push too. The credit
     *  carries the bar's branch into band 4, its spent window takes that back,
     *  and the push reads the branch on three: it waits. Read before that
     *  window, both pushes entered 4×11 and the next plan capped one at 3×11.
     *  The control has budget left: the band stands, and the pushes follow. */
    @Test
    fun thePullIsReadAfterTheOtherBranchsWindow() {
        val s = EngineState.initial
        s.hasBar = true
        put(s, Pattern.pushH, dose = 15)
        put(s, Pattern.pushV, dose = Dose.grid(Library.unit(Pattern.pushV, Library.count(Pattern.pushV))).max)
        put(s, Pattern.pull, sets = 4, dose = Dose.grid(Library.unit(Pattern.pull, Library.count(Pattern.pull))).min)
        put(s, Pattern.pullBar, dose = Dose.grid(Library.unit(Pattern.pullBar, Library.count(Pattern.pullBar))).max)
        s.weekAgeDays = 1.0
        val spent = s.copy()
        spent.weekGain[Pattern.pullBar] = EngineConfig.weeklyRiseSlow

        val waits = train(spent, gapDays = 0.5)
        assertEquals(3, onScreen(waits, Pattern.pullBar), "the bar's window took back the band the credit gave it")
        assertEquals(listOf(3, 3), listOf(waits.position(Pattern.pushH).sets, waits.position(Pattern.pushV).sets),
                     "the pushes wait for the branch the window kept")

        val follows = train(s, gapDays = 0.5)
        assertEquals(4, onScreen(follows, Pattern.pullBar), "with budget left the credit's band stands")
        assertEquals(listOf(4, 4), listOf(follows.position(Pattern.pushH).sets, follows.position(Pattern.pushV).sets),
                     "and the pushes enter behind it")
    }

    /** The pull caps pushes only: a squat on its ceiling enters its band
     *  whatever the pull shows. */
    @Test
    fun onlyAPushWaitsForThePull() {
        val s = EngineState.initial
        put(s, Pattern.squat, dose = 15)
        put(s, Pattern.pull, dose = 14, sub = 2)
        val after = train(s)
        assertEquals(3, onScreen(after, Pattern.pull))
        assertEquals(listOf(4, 11), listOf(after.position(Pattern.squat).sets, after.position(Pattern.squat).dose))
    }

    /** What is compared is the push's BAND, not the sets it shows. A push on
     *  3×15 with a set taken off, while its hold ticks, grows into the band:
     *  band 4 against a pull on three waits, though 4 − 1 on screen would fit. */
    @Test
    fun theBandIsComparedNotTheSetsOnScreen() {
        val s = EngineState.initial
        put(s, Pattern.pushH, dose = 15, cut = 1)
        s.setsHold[Pattern.pushH] = 1
        putLowPull(s, dose = 10)
        val after = train(s)
        assertEquals(3, onScreen(after, Pattern.pull))
        assertEquals(3, after.position(Pattern.pushH).sets, "band 4 waits for a pull on three")
        assertEquals(1, after.position(Pattern.pushH).cut, "the hold kept the set off")
    }

    // MARK: - A lifted gate gives a standing push its sets back

    /** Push and pull on 5×15, one pull set skipped. The press shows 4×15 at
     *  its next appearance — the pull really does show four — and the pull
     *  returns its set in that session. Once the cap has lifted, the press is
     *  back on 5×15. Without the rule the repair would hold it on 4×15 at every
     *  appearance until the press fell: at the top of the scale it cannot
     *  rise. */
    @Test
    fun aLiftedGateGivesAFrozenPushItsSetsBack() {
        var s = EngineState.initial
        put(s, Pattern.pushH, sets = 5, dose = 15)
        put(s, Pattern.pushV, sets = 5, dose = 15)
        put(s, Pattern.pull, sets = 5, dose = 15)
        val shown = mutableListOf<Int>()
        for (k in 0 until 6) {
            exercise(s, Pattern.pushV)?.let { shown.add(it.sets) }
            s = train(s, setsSkipped = if (k == 0) mapOf(Pattern.pull to 1) else emptyMap(), gapDays = 7.0 / 3)
        }
        assertEquals(listOf(5, 4, 5, 5), shown, "capped once while the pull showed four, then back")
    }

    /** A set of the push skipped at its last showing keeps the repair's hold
     *  when the cap lifts: a cut is a descent. Here the press got a set back
     *  in that session and the same set was skipped, so its position stands
     *  and its own sets equal those it was shown with — only the skip's trace
     *  tells the hold apart from a cap. */
    @Test
    fun aSkippedPushSetKeepsTheRepairsHold() {
        var s = EngineState.initial
        put(s, Pattern.pushH, sets = 5, dose = 12, cut = 1)
        put(s, Pattern.pull, dose = 14, sub = 2)
        s = train(s, setsSkipped = mapOf(Pattern.pushH to 1))
        s = train(s)
        assertEquals(4, onScreen(s, Pattern.pull), "the cap lifted from three to four")
        val held = exercise(s, Pattern.pushH)
        assertEquals(3, held?.sets, "the skipped set is not handed back")
    }

    /** The twin of the test above: the same state with the trace wiped is a
     *  standing push under a cap that rose by one, and gets that set back. So
     *  it is the trace, and nothing else, that keeps the skipped set off. */
    @Test
    fun withoutItsTraceTheSkippedSetWouldComeBack() {
        var s = EngineState.initial
        put(s, Pattern.pushH, sets = 5, dose = 12, cut = 1)
        put(s, Pattern.pull, dose = 14, sub = 2)
        s = train(s, setsSkipped = mapOf(Pattern.pushH to 1))
        s = train(s)
        assertEquals(setOf(Pattern.pushH), s.shownSkip, "the skipped set left its trace")
        val wiped = s.copy()
        wiped.shownSkip = mutableSetOf()
        assertEquals(4, exercise(wiped, Pattern.pushH)?.sets)
    }

    /** What comes back is the rise of the push's OWN cap, min(own, pull),
     *  on top of whatever the repair holds for its own reasons. Band 4: the
     *  cap never cut the press (three of its own under a pull on three), so a
     *  rising pull adds nothing and the hold for its skipped set stays. Band
     *  5: the cap cut one set, it lifts by one, and one set comes back on top
     *  of the held 13-12. */
    @Test
    fun theLiftIsTheRiseOfThePushsOwnCap() {
        fun chain(band: Int): EngineState {
            var s = EngineState.initial
            s.counter = 2
            put(s, Pattern.pushH, sets = band, dose = 12)
            put(s, Pattern.pull, sets = 4, dose = 11, cut = 1)
            fun session(skipped: Set<Pattern>, skipSet: Boolean) {
                val w = Engine.generateSession(s)
                s = Engine.recordShown(state = s, session = w)
                s = Engine.applyFeedback(state = s, session = w, result = FeedbackResult.plan, skipped = skipped,
                                         setsSkipped = if (skipSet) mapOf(Pattern.pushH to 1) else emptyMap(),
                                         gapDays = 2.0)
            }
            session(skipped = setOf(Pattern.pull), skipSet = true)
            session(skipped = setOf(Pattern.pushH), skipSet = false)
            session(skipped = emptySet(), skipSet = false)
            return s
        }
        val four = assertNotNull(exercise(chain(band = 4), Pattern.pushH))
        assertEquals(listOf(13, 12), four.loads, "band 4: the cap never cut, nothing comes back")
        val five = assertNotNull(exercise(chain(band = 5), Pattern.pushH))
        assertEquals(listOf(13, 12, 12), five.loads, "band 5: one set back, on top of the hold")
    }

    /** Fewer own sets than at the last showing keep the hold too: "hard" on
     *  the dose floor took a set off, the raise handle put the position back
     *  where it stood. The pull returns its set and the cap rises — but the
     *  press has a set fewer of its own, and that is a descent. */
    @Test
    fun fewerOwnSetsKeepTheHold() {
        var s = EngineState.initial
        put(s, Pattern.pushH, sets = 5, dose = 4)
        putLowPull(s, dose = 8, cut = 1)
        s = train(s, FeedbackResult.less, raised = mapOf(Pattern.pushH to 1), gapDays = 7.0 / 3)
        assertEquals(1, s.position(Pattern.pushH).cut, "the descent took a set off")
        s = train(s, gapDays = 7.0 / 3)
        assertEquals(3, onScreen(s, Pattern.pull), "the pull returned its set")
        val held = assertNotNull(exercise(s, Pattern.pushH))
        assertEquals(listOf(5, 4), held.loads, "the hold stands though the cap rose")
    }

    /** A state written before the gate memory existed carries the memory of
     *  what was shown and nothing about the cap. A standing push on it gets
     *  its whole cap back once — the press frozen at 4×15 under a pull long
     *  back on five — and a push that FELL since its showing stays under the
     *  repair: a descent never adds work. */
    @Test
    fun aStateWithoutGateMemoryIsReleasedOnce() {
        var s = EngineState.initial
        put(s, Pattern.pushH, sets = 5, dose = 15)
        put(s, Pattern.pushV, sets = 5, dose = 13)
        put(s, Pattern.pull, sets = 5, dose = 15)
        s.shownWork = mutableMapOf(Pattern.pushH to 4 * 15 * 2, Pattern.pushV to 4 * 14)
        s.shownOrd = mutableMapOf(
            Pattern.pushH to Engine.posOrd(Pattern.pushH, s.position(Pattern.pushH)),
            Pattern.pushV to Engine.posOrd(Pattern.pushV,
                Position(variation = Library.count(Pattern.pushV), sets = 5, dose = 14, sub = 0, cut = 0)),
        )
        val session = Engine.generateSession(s)
        val press = assertNotNull(session.exercises.firstOrNull { it.pattern == Pattern.pushH })
        assertEquals(5, press.sets, "the frozen press gets its cap back")
        val handstand = assertNotNull(session.exercises.firstOrNull { it.pattern == Pattern.pushV })
        assertEquals(listOf(4, 13), listOf(handstand.sets, handstand.load), "the fallen one stays under the repair")

        // From the next showing on, the ordinary rule: the pull loses a set,
        // the cap takes one; the pull returns it, the press follows.
        val shown = mutableListOf<Int>()
        for (k in 0 until 10) {
            exercise(s, Pattern.pushH)?.let { shown.add(it.sets) }
            s = train(s, setsSkipped = if (k == 2) mapOf(Pattern.pull to 1) else emptyMap(), gapDays = 7.0 / 3)
        }
        assertEquals(listOf(5, 5, 4, 5, 5), shown.take(5))
    }

    // MARK: - The plan a build without the memory drew

    /** The frozen press of the legacy state above, redrawn as the build before
     *  the memory drew it — the plan a workout started on that build is keyed
     *  on. The press stays on four sets, and nothing else moves. */
    @Test
    fun thePlanWithoutTheOneTimeReleaseKeepsTheFrozenPush() {
        val s = EngineState.initial
        put(s, Pattern.pushH, sets = 5, dose = 15)
        put(s, Pattern.pull, sets = 5, dose = 15)
        s.shownWork = mutableMapOf(Pattern.pushH to 4 * 15 * 2)
        s.shownOrd = mutableMapOf(Pattern.pushH to Engine.posOrd(Pattern.pushH, s.position(Pattern.pushH)))
        val drawn = Engine.generateSession(s)
        val before = Engine.sessionWithoutTheOneTimeRelease(s)
        assertEquals(5, drawn.exercises.firstOrNull { it.pattern == Pattern.pushH }?.sets, "drawn now, the press is released")
        assertEquals(4, before.exercises.firstOrNull { it.pattern == Pattern.pushH }?.sets, "the build before held it on four")
        assertEquals(drawn.exercises.filter { it.pattern != Pattern.pushH },
                     before.exercises.filter { it.pattern != Pattern.pushH }, "only the release differs")
    }

    /** A push WITH the memory keeps its lift: what is left out is the release
     *  of a push that has none, not the rule. Once both pushes remember a
     *  showing, it is the plan drawn now — the showing the cap lifts included. */
    @Test
    fun withTheMemoryInPlaceItIsThePlanDrawnNow() {
        var s = EngineState.initial
        put(s, Pattern.pushH, sets = 5, dose = 15)
        put(s, Pattern.pushV, sets = 5, dose = 15)
        put(s, Pattern.pull, sets = 5, dose = 15)
        s = train(s, gapDays = 7.0 / 3)
        assertEquals(setOf(Pattern.pushH, Pattern.pushV), s.shownCap.keys.toSet(), "workout 1 showed both pushes")
        val shown = mutableListOf<Int>()
        for (k in 0 until 5) {
            assertEquals(Engine.generateSession(s), Engine.sessionWithoutTheOneTimeRelease(s), "showing ${k + 2}")
            exercise(s, Pattern.pushH)?.let { shown.add(it.sets) }
            s = train(s, setsSkipped = if (k == 0) mapOf(Pattern.pull to 1) else emptyMap(), gapDays = 7.0 / 3)
        }
        assertEquals(listOf(4, 5, 5), shown, "capped once while the pull showed four, then lifted back")
    }

    // MARK: - The memory itself

    /** The feedback remembers the cap a push was SHOWN under — read off the
     *  state the plan was built from, as the position is. Here the pull
     *  returns a set in that very session and the press returns one of its
     *  own: the memory keeps three and three, the numbers on screen, not the
     *  four and four the session ends on. A push skipped whole was shown all
     *  the same, and remembers too. */
    @Test
    fun theFeedbackRemembersTheCapAtTheShowing() {
        val s = EngineState.initial
        put(s, Pattern.pushH, sets = 4, dose = 12, cut = 1)
        put(s, Pattern.pushV, sets = 4, dose = 12)
        put(s, Pattern.pull, sets = 4, dose = 15, cut = 1)
        s.shownSkip = mutableSetOf(Pattern.pushH, Pattern.pushV)
        val after = train(s, skipped = setOf(Pattern.pushV))
        assertEquals(0, after.position(Pattern.pull).cut, "the pull returned its set this session")
        assertEquals(0, after.position(Pattern.pushH).cut, "and so did the press")
        assertEquals(mapOf(Pattern.pushH to 3, Pattern.pushV to 3), after.shownCap)
        assertEquals(mapOf(Pattern.pushH to 3, Pattern.pushV to 4), after.shownOwn)
        assertEquals(emptySet(), after.shownSkip, "a showing closes the trace of a cut")
    }

    /** `recordShown` writes the same memory a feedback does, from the state the
     *  plan was built from, for the pushes on that plan and for nothing else;
     *  a push not on the plan keeps both its memory and its trace. The golden
     *  fixture never renders a plan, so this is the only pin on it. */
    @Test
    fun recordShownWritesTheCapMemory() {
        val s = EngineState.initial
        s.counter = 1   // the vertical press stands in this session, the horizontal one does not
        put(s, Pattern.pushV, sets = 4, dose = 12, cut = 1)
        put(s, Pattern.pull, sets = 4, dose = 15, cut = 2)
        s.shownSkip = mutableSetOf(Pattern.pushH, Pattern.pushV)
        s.shownCap[Pattern.pushH] = 4
        s.shownOwn[Pattern.pushH] = 3
        val session = Engine.generateSession(s)
        assertFalse(session.exercises.any { it.pattern == Pattern.pushH })
        val recorded = Engine.recordShown(state = s, session = session)
        assertEquals(mapOf(Pattern.pushV to 2, Pattern.pushH to 4), recorded.shownCap)
        assertEquals(mapOf(Pattern.pushV to 3, Pattern.pushH to 3), recorded.shownOwn)
        assertEquals(setOf(Pattern.pushH), recorded.shownSkip, "the press not on the plan keeps its trace")
        assertEquals(recorded, Engine.recordShown(state = recorded, session = session),
                     "recording the same showing again changes nothing")
    }

    /** The trace marks a GROWING cut on a push, and only that: a cut given back,
     *  a cut set to what it is, and a cut on anything but a push leave none. */
    @Test
    fun setCutLeavesATraceOnlyWhenAPushsCutGrows() {
        val s = EngineState.initial
        put(s, Pattern.pushH, sets = 4, dose = 12)
        put(s, Pattern.pushV, sets = 4, dose = 12, cut = 1)
        put(s, Pattern.squat, sets = 4, dose = 12)
        assertEquals(setOf(Pattern.pushH), Engine.setCut(state = s, pattern = Pattern.pushH, cut = 1).shownSkip)
        assertEquals(emptySet(), Engine.setCut(state = s, pattern = Pattern.pushV, cut = 0).shownSkip)
        assertEquals(emptySet(), Engine.setCut(state = s, pattern = Pattern.pushV, cut = 1).shownSkip)
        assertEquals(emptySet(), Engine.setCut(state = s, pattern = Pattern.squat, cut = 1).shownSkip)
    }

    /** Read leniently and healed: a file without the memory opens with none
     *  (the state of a build before the memory, released once); a file with it
     *  keeps it; a pattern the cap does not reach, or a count no plan can show,
     *  is healed away before the engine reads it. */
    @Test
    fun theCapMemoryDecodesLenientlyAndHeals() {
        val bare = """{"counter":3,"vars":["push_h",6],"doses":["push_h",12]}"""
        val old = EngineState.decode(bare)
        assertEquals(emptyMap(), old.shownCap)
        assertEquals(emptyMap(), old.shownOwn)
        assertEquals(emptySet(), old.shownSkip)

        val full = """{"counter":3,"vars":["push_h",6],"doses":["push_h",12],""" +
            """"shownCap":["push_h",4,"squat",3,"push_v",9],""" +
            """"shownOwn":["push_h",3,"push_v",-1,"moon",2],""" +
            """"shownSkip":["push_v","squat","moon"]}"""
        val kept = EngineState.decode(full)
        assertEquals(4, kept.shownCap[Pattern.pushH])
        val healed = kept.sanitized()
        assertEquals(mapOf(Pattern.pushH to 4, Pattern.pushV to EngineConfig.setsMax), healed.shownCap)
        assertEquals(mapOf(Pattern.pushH to 3, Pattern.pushV to EngineConfig.setsFloor), healed.shownOwn)
        assertEquals(setOf(Pattern.pushV), healed.shownSkip)

        val roundTrip = EngineState.decode(healed.encode())
        assertEquals(healed, roundTrip)
    }
}
