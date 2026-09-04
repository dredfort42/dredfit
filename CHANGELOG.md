# Changelog

## 2.2.0

**The warm-up counts the switch.** Four of its moves have a middle their own
instructions name — the single-leg Romanian deadlift and the bird dog are done
one side at a time, and the arm and hip circles say to reverse direction halfway
— and every one of them ran its thirty seconds in silence, so the side or the
direction you started on was usually the one you finished on unless you counted
for yourself. They now run the way the cool-down's stretches have run since
1.8.0: fifteen seconds a half, a five-second pause between them with its own
falling tone and its own line on the screen, and a technique sheet that names the
length of one half instead of of both. The words follow what is actually
switched — **Switch sides** and "second side" for the two that have sides,
**Switch direction** and "the other way" for the two that reverse — because a
circle is not a side. Torso rotations and cat-cow keep their single countdown:
they alternate continuously, so there is no one moment to announce. The pause can
be paused like everything else in the block, and a phone locked across the whole
move comes back where the clock says it should, with no signal sounded for a
switch that is already over.

**Every announced session is one minute longer, and the minute is real.** The
warm-up and the cool-down share a reserve inside every duration the app
announces, and that reserve was spent to the second. The switch pauses cost
fifteen seconds in the composition that draws three of them, so the reserve had
to grow —
an engine change, made through the same reference chain the ladders go through,
and priced out loud rather than absorbed: a clean start now reads ≈ 32 minutes
where it read 31. Nothing else about the plan moves. The exercises, the sets,
the doses and the probe are what 2.1.0 generated, bit for bit, out of the same
recorded trace of the JavaScript reference, and there is no migration: the state
and journal formats are untouched.

**A hold's rest stops counting you in twice, and can now be paused.** A hold
exercise you start once runs itself, and every set after the first begins when
its rest ends. On top of that rest the app used to lay another fifteen seconds
— its own 3-2-1, its own go — so a minute between sets actually took a minute
and a quarter and announced the same set twice. The rest IS the time to get
back into position: it counts its own last seconds down and the set begins on
its go. Cutting a rest short with **Skip rest** still buys the five-second
count-in every start tap earns, because that tap is somebody saying they are
ready and nothing should land under the thumb that made it. And that rest is
the one clock in a workout that acts on its own, which made it the one place
where answering the door cost you a set: **Pause** freezes it, **Resume** hands
the clock back, and a rest resumed with a second left still gives you five
before the hold starts.

## 2.1.0

**Holds are hands-free now, and two screens stopped asking for a decision at
the one moment it cannot be given.** A hold movement is bought with a single tap
and the phone can stay where you put it until the movement is over; the time on
its clock is agreed before the effort instead of reported after it; and the
seconds are put right on a screen that comes back once the work is behind you.
The other half of the release is the same idea from the other side. The two
escapes on the work screen used to fire on contact, and the offer of a gentler
variation sat under every row of the plan — a question asked mid-set, and a
question asked before the workout has told you anything at all. Each now asks
first, or asks somewhere else.

**What this release does not touch.** The engine is not changed by a single
line. The ladders, the rotation, the probe, the comeback after a break and the
entry point — three sets of four in the gentlest variation of each of six
movements, which is the entry point and not the bottom — are exactly what 2.0.0
shipped, and `GoldenTests` still replays the same recorded trace of the
JavaScript reference, bit for bit, out of the same unedited fixture. The state
format stays v3 and the journal format stays as it is, so **there is no
migration in this release** and nothing about your history is touched by
installing it. No new kind of Health data is read or written and no permission
text changed, so the App Store privacy answer stands where it was: **Data Not
Collected** — no account, no analytics, no ads and no network request of any
kind.

### Holds run without the phone in your hand

**A hold exercise costs one tap.** Three sets of a plank took four touches, and
three of them were taken between sets by somebody lying on the floor — which is
the one moment the phone is furthest away and the effort has just ended.
**Start exercise** now buys the whole movement: the rest ends, the next set
counts itself in, and nothing has to be picked up until the exercise is over.
The screen before the tap says what is being bought — how many sets and how
long the rest between them — and promises only what the app can keep: put the
phone down, not lock the screen, because a suspended app runs no timers and
plays no tones.

**The count-in before a set the run opened is longer than the one a tap earns.**
A tap is somebody saying "I am ready" and needs only the beat between saying it
and being counted in. A set the run opened was agreed to sets ago by somebody
who has since been lying through a rest, so it is priced as travel to the
position — the same length the warm-up and cool-down give a position you have
to get down into.

**You say how long a hold will run, before it runs.** The one thing a hold
screen takes before the effort is the time on the clock — a target, not a
report, which is what makes it a fair question to ask of somebody who has not
done the set yet. **Set the time** raises it (or lowers it, on a day when the
plan is too much), the clock counts down from that number on every set of the
exercise, and **Stop** cuts a set short and records what was actually held. So
the number the engine reads is still measured, never declared.

A set that was cut short still speaks: the sets after it follow what was shown,
capped by what was declared. Aiming at 60 and managing 50 does not put 60 back
on the clock.

This is what the per-side holds needed. Such a set is recorded as the smaller
of its two sides, and the second side runs for exactly what the first one ran —
so nothing that happens after the plan is met can raise its number, and half
the hold movements had no way to show more at all. Both sides now run from the
declared time, with no exception for the shape.

**Stop names the number it will write.** "Stop · 60 s" instead of "Stop": the
figure on the button is what the set records if the tap lands now, so ending a
hold early is a decision rather than a surprise. Inside the first three seconds
it stays plain **Stop**, because that tap cancels the set and stores nothing at
all — a figure there would be a lie.

**A hold ended by tap is written down by three seconds.** The thumb arrives
after the effort has stopped: the person comes off the floor and reaches for
the phone, and the timestamp of the tap is not the timestamp of the last second
held. The correction only ever goes down, never below the five seconds a hold
can be stored as, and it is what the button already named.

**A hold that ends itself no longer takes the screen with it.** The flow used to
leave in the same frame the number was produced in, so the seconds a plank had
just recorded could not be looked at, and after the last set of a movement no
screen about that movement ever came back. The clock still owns the end of the
effort — the finale sounds the moment you stop, because your eyes may be shut —
but it no longer owns the record: the movement closes on a summary of its own,
and that is where a number is put right. Every set before the last one still
runs into its rest by itself, with no tap between the effort and the recovery.

**A finished hold movement now shows every set on one screen, and any of them
can be corrected.** Until now only the last one could: a number entered on the
work screen writes the set under way and clears the sets after it, which is
right while they have not happened and wrong once they have. Set one of three
had never been correctable at all. Tap a card, change the number, and the other
sets keep what they ran at. Sets that ended under a thumb are marked "≈", so a
figure the app estimated is never shown with the confidence of one the clock
produced. There are no escapes on this screen — the movement is behind, and
there is nothing left to skip.

**"Went differently" is gone from the planned sets of a hold.** It asked for a
number about a set nobody had performed yet, and the one moment it was
genuinely needed — a hold that ran long — is the moment both hands are on the
floor. The **Set the time** answers that moment before the effort and the
summary answers the correction after it. The first-workout hint that pointed at
the control on a hold went with it: it named something that could not be
reached. The screen for sets of reps is untouched, button for button.

**One hold keeps it, and the exception is the reason rather than a leftover.**
A probe is measured on its own: its number is a separate answer about a
variation you are not on yet, and the summary of a hold movement says nothing
about it deliberately, because folding it in with that movement's sets would
report it as work you did in the variation you are in. So a probing hold does
not hand the screen over to a summary at all — it settles in place, with the
seconds it produced and the control that corrects them, which is the one hold
whose record would otherwise have nowhere to be put right.

**A time set for one movement stays with that movement.** Saying "hold 20" and
then skipping a set of the same exercise put the sets after it silently back on
the plan — the skip cleared the declaration along with the state that really
does belong to one set — and it dropped the "≈" marks off numbers the app had
guessed at, so a figure it had estimated was printed with the confidence of one
the clock produced. In the other direction the same time outlived the exercise
entirely: finish the plank at 20 s and the side plank, whose own plan is 15,
opened its clock on 20. The declaration now begins and ends with the movement it
was set for.

**A declared time survives the app being killed.** The snapshot that lets an
interrupted workout be resumed carries the hold fields now, so a session picked
up after the app was force-quit or evicted comes back on the number you
announced, not on the one the plan started with — the declaration is the part of
that screen you would have to be told twice to re-enter. A snapshot written by
an earlier build has none of those fields and is read anyway rather than thrown
away: an upgrade must not cost somebody the workout they were in the middle
of.

### Nothing is skipped on contact

**Skipping a set or an exercise asks first.** Both escapes are 44 pt targets
sitting 18 pt under the button that logs the set, and they used to fire on
contact. A workout has no undo, so a brushed thumb took a set — or a whole
movement together with every number already entered for it — and nothing
anywhere could put it back. Each one now states what is actually lost and waits
for an answer; the question can only be answered by a button, so the stray tap
that raised it cannot also confirm it. All four questions look the same on
purpose, down to the buttons: none of them is red, and all of them answer to
the same short **Skip**. What leaving a movement destroys is the numbers you
entered for it, and the sentence says so; the movement itself stays exactly
where it was, no penalty and no rollback, which is not something to paint as a
danger.

### The easier variation moved into the movement's own card

**The easier variation moved off the plan and into the movement's own card.**
Every row of the plan carried a line under it offering a gentler version of that
movement — and since 2.0 that meant six of them, one under every row, because
the carry-over from the old format put every movement above the first rung of
its ladder. The plan has been cleared of controls like this twice already, both
times for the same reason: they ask for a decision before the person can know
the answer. This one now lives behind the card the row already opened, directly
under the line that says **variation 3 of 7** — the one place in the app that
can show a movement which is not in today's plan, which is exactly what the rung
below is. The block has room for what a 12.5 pt line could not say: the
movement, the dose it comes with, and — on the pull-up ladder — that the rung
below counts seconds instead of reps.

**It is offered before the workout, never during one.** The same card opens from
the work screen and carries no switch there. A session is fixed when you press
Start, so a movement changed halfway through would move the plan out from under
the workout you are in the middle of — and the rating at the end lands on both
at once.

**And it asks before it acts.** A plan has no undo, and the way back up a ladder
is not a tap: it is a probe, which arrives only once the dose has climbed to the
ceiling again. So the switch puts the same question the four skips put, in the
same words and with the same two answers.

**One grey line pays for the handle that is no longer visible.** Above the Start
button: *tap a movement for how it's done — and for the version one step below
it.* It stands until the first time somebody opens one of those cards, from any
screen, and never again.

### The probe is written down, and the plan says one is coming

**History remembers the probe.** A workout whose last set was a probe was
recorded as though it never happened: the sheet printed the working sets beside
the movement's name — "2 × 15" for a session that also had somebody trying a
pull-up they had never done — and said nothing about the set that followed. What
the probe showed was worse off than unprinted: the number reached the engine and
was never written down, so the moment the rating landed it was gone for good.
It is kept now, and the line under the movement reads *Probe: Inverted row
(table) · 5 — passed*, or *— not this time*, which is the same neutral sentence
the workout itself gives a probe that did not land. Records written before this
keep their verdict — that much can still be read off the position the session
ended on — and simply have no number to show.

**The plan says when a set is a probe.** An exercise that ends in one is
planned with a working set fewer — the probe takes the last of them — so a
three-set plan whose third set was a probe printed "2 × 15" and said nothing
about the set standing after it, while the minutes above the plan counted it.
The row now carries the line the number could not: *then a probe: one set of
Bar hang · 15 sec.*

### Your weight follows Health

**Your weight follows Health.** It used to be copied once — the day the Health
toggle went on, and only into a field you had left empty — and then never looked
at again. Weigh yourself a month later and the calories written for every
workout were still priced from the number you had on the day you switched it on.
It is re-read now at every launch, at every return from the background, and once
more at the head of every export, so the figure that reaches Health is the one
your scales gave. The **Body weight** row says where the number came from and
stops offering an editor while Health supplies it: a field that took a number
the next foreground would silently replace was a lie. It comes back the moment
Health has nothing to say — no record there, or the read refused, which look
identical from the outside — and a reading that is not there never erases the
one you typed. A restored backup brings the number but not the claim about where
it came from; this phone's Health answers for itself.

**"Leave calories out" says what it does.** The switch that keeps the estimate
out of Health was named for one of the two reasons to want it — a watch already
recording the same session. The other reason used to live in the weight field:
clearing it switched the estimate off. Now that the weight follows Health, that
answer cannot be said there any more, so the switch carries the name of its
effect and its caption names both reasons.

### Two screens were read against the App Store frames, and both were wrong

**The progress chart was losing the date its line ends on.** The axis asks for
three dates — the first workout, the middle of the history and the last one —
and drew two. Swift Charts anchors a date label at its own date and grows it to
the right; the last date sits on the right edge of the plot, so its label ran
into the column of numbers on the y-axis, and a label that does not fit is
neither nudged nor clipped but dropped. The line therefore ran up to yesterday
while the axis stopped on a date in the middle of the history: the one screen
that exists to show progress you can see was printing a third less history than
it had just drawn, and the person reading it was reading their own record
short. Only the last label is anchored by its trailing edge now, so it grows
leftwards, clear of the digits; the other two are on exactly the pixels they
were on before. The cause was measured off rendered frames rather than
reasoned about, and the new test fails on the old code as well as on three
mutations of the fix.

**A German movement name was losing its capital letter.** The line under the
title of the technique sheet was assembled through `.lowercased()`, and in
German that broke all ten movement names — "horizontales drücken" where the
catalog says **Horizontales Drücken**, while the progress screen one tap away
printed the same word correctly. In six of the seven languages lowering the
case is harmless; in the seventh it is a grammatical error, because German
capitalises nouns as grammar and not as decoration. Nothing was in a position
to catch it: the sentence is assembled at run time, the catalog itself is
right, and the localization check asks whether a translation exists, not what
case it is in. The catalog value is now printed as it stands — the terminology
that the glossary fixes for all seven languages is correct in every one of them
by definition, and no screen should be re-typing it.

### Housekeeping

- **596 → 657 automated tests**, counted across the same three layers 2.0.0
  counted: **70** in the engine package, **513** in the app, **74** in the UI
  suite. The engine's 70 did not move, and that is the honest reading of this
  release — nothing in `DredfitCore` was touched, so nothing there needed a new
  guard. All of the growth is in the app, and it sits on the things this wave
  could have got wrong quietly: which sets a declared time belongs to and when
  it expires, a correction on the summary that must leave the other sets alone,
  the "≈" that separates an estimate from a measurement, the snapshot round-trip
  in both directions, all four skip questions, the weight being re-read at
  launch, at foreground and at the head of an export, and — last to arrive — the
  three cases that pin the date axis: which dates it asks for, and that the
  label at the end of the line is anchored so that it is drawn at all.
- **The one kicker that labels a control is darker than the ones that label
  sections.** `Kicker` carried `ink3` as a constant, which is the right ink for
  a heading standing over content that speaks for itself — the palette pins it
  at 3:1, a section's ratio and not a label's. The line this release adds,
  **One step below**, is not that kind of line: it labels the only thing on the
  technique sheet that does anything, and at 12 pt semibold it is small text,
  where the floor this project holds itself to is 4.5:1. That kicker is `ink2`,
  and the component takes its colour as an argument now instead of deciding for
  every screen at once. Every kicker that was already on a screen keeps `ink3`
  and is unchanged.
- **The work screen moved into a file of its own** and the hold summary into
  two more, with no change in behaviour: the screen that grew this release was
  already the tallest file in the app, and the size ceiling is a CI error here
  rather than a warning, so it is split before it is grown.
- **All forty new strings ship complete in all six translations**, and no
  existing translation moved. Three strings were retired with the controls they
  belonged to — the plan's "Easier · …" line and the old name and caption of the
  calorie switch — so nothing outside the app may quote them any more.
- **The plan's one-off technique hint is centred.** A one-line aside that does
  not line up with the block it belongs to reads as a stray label rather than a
  hint, and this one stands above **Start**, where nothing should look like a
  control that is not one.

## 2.0.0

The major number moves for one reason: **the scale you measured yourself by is
gone.** Until this release every movement carried a level between 0 and 47 — on
the progress chart, on the share card, in the VoiceOver line "Squat, level 18 of
47" — and a number a person has been reading about themselves for a year is not
an implementation detail. It was removed because it was a *prediction*: one
integer per pattern, out of which the app derived a variation, a set count and a
dose it had never seen anyone do. What stands in its place is a measurement. A
position is the variation you are on together with the dose you actually did in
it, and nothing is ever put into a plan that you have not already shown. The
library grew from 40 exercises to 59 so that could hold; the way into a harder
variation became a probe you perform rather than an unlock that happens to you;
and every decision about how long a workout is moved inside the workout, where
you are the one making it.

**1.9.0 is the last version that reached the App Store.** Everything prepared as
1.10.0 — twenty engine waves, the dark theme, the adaptive palette — was tagged
and never submitted, so it is folded into this section rather than left standing
as a heading for a release nobody can install.

**What this release does not touch.** The rotation is the same: a pull in every
session, the other patterns coming round five times in every eight workouts, and
the same six slots in the same order. The guided warm-up and cool-down still
open and close every session, both pausable, both with a transition before every
position, and the bar module is still off until you turn it on. There is still
no account, no analytics, no ads, and no network request of any kind — the app
has never made one and does not start now.

**Three things inside that shape did change, and the list above would be a lie
without them.** The warm-up is no longer six fixed movements: it is a pool of
nine, six of them drawn per session, three of which came down from the strength
ladders. The cool-down is a minute longer — the reserve the two blocks share had
to pay for the ten-second transition before every position — so **every announced
duration in the app is one minute longer than it was**, and the engine's own
acceptance asserts "grew by 1.0" rather than "unchanged". And the bar ladder went
from four rungs to seven: a scapular hang between the hang and the negatives, and
two assisted rungs under the full pull-up, so the vertical pull stopped being the
one ladder in the library you had to jump. The slot that alternates the two pulls
now also carries growth across to the branch that did not train, so the ladder you
were not on that week does not fall behind the one you were.

**And your history carries over.** The state format steps from v2 to v3, and the upgrade is positional: each
movement lands on the position that matches what it was doing, the journal is
decoded record by record so one unreadable entry cannot cost you the file, and
Today says out loud that the carry-over happened. Nobody starts again from zero.

Twelve waves stand above the twenty prepared as 1.10.0, newest first. The
newest is two defects found by re-reading the diff of everything below it: a
Health export that could not stop, and a restored backup that carried an
upgrade over without saying so. Before it, one line of settings: a fresh
install rests three days a week instead of two. Before it, Apple Health gets
what a workout cost, not only how long it took. Before it, a hardening pass: a
position read back out of the journal could take the app down, and two tests
that stood guard could not have caught it. Before it, **v3.3**, found by
reading the comeback card in the re-shot screens a second time: the "easier"
offer after a probing session was a set short of the position behind it, and
the depth of a comeback stopped being monotone in the length of the break.
Before it, **v3.2**: the comeback card offered an "easier" plan with more work
in it than the one it replaced. Before it, a truthfulness pass: an audit read
every screen against the engine and found nineteen places where the words — or
the numbers — promised something the code does not do. **Before it,** an
app-layer wave added a count-in before every clock and made one rating earned.
**v3.1** closes what a full audit of v3.0 found. Before it, the engine stepped
to **v3.0** and stopped predicting what you can do; **v2.27** moved the
decision about the length of a workout inside the workout; and five app-layer
fixes came out of the design re-review.

**The v3.0 section rewrites parts of everything below it.** They were written against
the 0–47 level scale, and that scale is gone: the duration table by level, the
per-level numbers, and the VoiceOver line "Squat, level 18 of 47" all describe
the engine as it was before this wave. They are left as written rather than
quietly edited — what they say about *why* each change was made still holds.

**One of those reversals is worth naming here rather than leaving to be found.**
A heading further down reads "Updating starts you over — deliberately", and when
it was written that was true: a state from before v3 could not be read, so the
engine started clean. **It is not true of what ships.** v3.1 gave the upgrade a
positional carry-over — every movement lands on the position matching what it
was doing, with your doses, your rotation and your bar answer — and 470 of the
480 possible positions land no heavier than they were. Nothing about your
progress is reset by installing this version. If you read that heading below and
stopped, read this paragraph instead.

**The declared floor below is also a stale number, in both of its halves.** A
paragraph further down says the easiest workout is "three sets of eight ... about
34 minutes" and the shortest "about 25 minutes". Those were true of the v2.27
library on the old scale. On what ships: the app starts you at **three sets of
four** in the gentlest variation of each of six movements, **about 31 minutes**
with the warm-up and cool-down — and three sets of four is the entry point, not
the bottom. `setsFloor` is **two**, so answering "tough" walks a movement down to
two sets of four, and six movements standing there is the **23 minutes** that the
range above Start quotes as its low end. The store listing and the site carry
these numbers; the paragraph below carries the ones they replaced.

### A Health export that could not stop, and a restore that said nothing

Two entries in one journal can share an identity. `resetProgress` starts the
session counter again while the history survives, so "session 1" can appear
twice, and what tells two entries apart is the session number together with the
date. The Health export chose the next workout to send by *not sent yet* and then
wrote the mark by identity alone — so with a colliding pair every mark landed on
the first of the two. The second stayed unsent, was chosen again, and the loop
put another workout into Health on every turn, without end, into a place the app
cannot tidy up afterwards. Both questions ask the same thing now, so each turn
retires exactly one entry. Only a journal edited by hand outside the app gets
there, which is the input the rest of that file is already written against.

Restoring a backup made before v3 carried the old positions across and then said
nothing about it. That upgrade is announced by a card on Today, shown once: the
ordinary launch raises it, and so does the launch that could not read its file
the first time. Restoring was a third way in, and it not only missed the card but
overwrote the reminder to show it with the settings out of the very file it had
just carried over. The announcement exists because the way back to your own
numbers — entering what you actually did — is explained by one line in the app,
and that line only appears to someone whose history is empty, which is never true
of someone upgrading.

Neither had a test. Both do now, and both of them fail against the code as it
stood.

### The rhythm the app ships with is four workouts a week

A fresh install rested on Sunday and Wednesday — five workouts a week. The app
had already written down twice that this is one too many: "3–4 workouts a week is
the sweet spot" in How it works, "2–3 rest days a week is the recommended rhythm"
under the chips in Settings. Those two ranges overlap in exactly one place — four
workouts, three rest days — and the shipped default sat outside it.

The number behind the recommendation is the rotation. Each of the eight rotating
patterns stands in five of every eight sessions, so N workouts a week are
0.625 × N appearances of each one: five give 3.1, four give 2.5, and the evidence
corridor is two to three (ACSM 2011, the source the weekly growth ceiling already
rests on). The engine says the same thing from its own side — the pull slot
stands in *every* session against a weekly budget of three sub-steps, so on
honest "on plan" answers the fourth session of a week is the last one that can
grow it and a fifth cannot move it at all.

The default is now Monday, Wednesday and Friday: spread rather than adjacent, so
the gaps between workouts come out 1-2-2-2 and no day is ever the third training
day in a row — the point where Today stops offering the plan and starts offering
rest. Nothing changes for anyone already installed. The decode path keeps
whatever a stored file holds, exactly as it has since #36: an upgrade must not
add a rest day the person never chose.

**What got worse.** Rest days are weekday-shaped, so the weekday an app is
installed on can be one of them — and on a rest day Today shows the rest screen,
with "Train anyway" as a secondary button, rather than the plan and Start. That
was two installs in seven and is now three. The promise on the box is "open the
app, your workout is ready", and for those three it is one tap further away than
it reads.

### Workouts reach Health with what they cost

A finished workout has always arrived in Health as an interval and nothing
else. iOS does not estimate calories on an app's behalf, so the entry sat there
with a duration and a blank where the energy goes. It carries an estimate now.

The estimate is built from the plan, not from the clock. The engine already
knows how a session divides — warm-up, the seconds each set is actually under
way, the rest between sets and between exercises, the cool-down — and each part
gets its own rate from the Compendium of Physical Activities. So the same work
with forty-five seconds of rest is priced differently from the same work with
ninety, which one figure for "strength training" cannot do. The wall clock is
only a ceiling: a workout left in the background for twenty minutes bills none
of them, while a session cut short is scaled down in proportion.

Health means *above rest* by active energy, so the resting cost of those same
minutes is subtracted — the difference between this estimate and a figure half
again as large. It uses the best resting rate on hand: the one Apple has
already computed for you where a watch has been writing it, otherwise the
Mifflin-St Jeor equation from height, age and sex, otherwise the textbook
constant everybody shares. Each rung falls through to the next in silence,
because there is nothing to announce — a Health read that was refused looks
exactly like data that was never there.

Nothing is written without a weight. It is the factor the whole estimate is
multiplied by, so a default would not be an approximation; it would be a number
that reads in Health exactly like a true one. Turning Health on takes the
weight from it without asking, and the Health section carries a row to type one
when it is not there.

A session also recorded on an Apple Watch already carries its own measured
energy, and ours would land on top of it. The app looks for a workout from
another source over the same minutes and drops the calories — only the
calories, never the workout — when it finds one. That look can be refused like
any other read, and a refusal is indistinguishable from finding nothing, so
there is a switch that says it outright.

The two guided blocks are charged for what they ran, not for what they promised.
Each of them ends on one tap of a footer button, and the estimate was billing
their planned nine minutes regardless — 27 % of a median session, to a person
who may have declined both. The flow measures them now: declined is zero,
half-done is the half, and a block that ran long bills the plan, because it runs
long for reasons that are not effort. A session in which nothing at all was
performed gets no figure: the workout is still a fact and still reaches Health,
but its cost would be a claim about training that did not happen.

The energy sample carries two labels — which revision of the estimate produced
it, and the identifier the workout has in Dredfit's own history. Neither is
visible in ordinary use; both exist so that a number written today stays
distinguishable from one written after the model next changes. A test pins every
constant the model is made of and fails, by name, telling you to move the
revision — a version nobody is obliged to raise is worse than no version at all.

It remains an estimate. Without a heart rate, expect it within about a quarter
of the truth for a given session, and closer than that across many.

### The promise about Health, corrected everywhere it was made

Reading anything from Health falsified a claim this app had been making
prominently and in seven languages: that the permission is write-only and that
nothing is ever read. That sentence was in the privacy policy at all seven filed
URLs, in the App Store description, in the review notes, in the README and in
two code comments that gave it as the *reason* for a rule. It has been corrected
in each of those places, and the privacy page now says plainly what is read,
what each value does — only body weight scales the figure; height, date of birth
and sex refine the resting share alone — and what refusing each one costs. It
also says the thing that is easy to leave out: the workout permission is not a
narrow one. Health grants workouts as a whole, and refusing that read silently
disables the double-count check, because Health never tells an app whether a
read was allowed.

What has not changed is the part that was always the point: nothing leaves the
device. The reading happens in order to divide by it.

### A stored position can no longer kill the app, and two guards that could not go red

Every number a finished workout leaves behind is clamped as it is read back —
the journal is an input, and in Swift a subtraction on a hand-edited number
takes the process down rather than saturating. The position snapshot was the
one field that was not: its five coordinates went straight into the measure,
and `Dose.snap` runs *before* the dose is clamped, so the subtraction that
opens `Dose.rung` met the raw number. A journal carrying an `Int.min` dose
killed the app on the Progress screen with SIGTRAP.

The test that stood guard over exactly this had been green the whole time. It
walked a variation of `Int.min` and sets of 99 — but a dose of 4 and 99, both
perfectly ordinary. The variation is clamped by the library and the sets by the
engine's own reader before anything subtracts; the dose is the one coordinate
that traps, and it was the one the test never bent. Both ends of its range are
walked now, and the sparse coordinates with them.

The anniversary block measured its "then" and "now" without those sparse
coordinates. Growth that happened entirely in sub-steps came out as zero, no
movement cleared the bar, and the block vanished for someone who had in fact
grown; a `cut` on the current position read a step higher than it stands and
could crown a movement that had gone down. It reads all six coordinates now,
like the chart beside it.

Two tests are honest again. The question that guards leaving a workout became an
alert in the last wave, and an alert is modal: the tap outside is swallowed
whole. The test still performed that tap and waited for the question to close,
which it never can — it pins what an alert actually guarantees now, that a stray
tap neither answers the question nor reaches the screen underneath. And the
next-workout preview tapped its card without waiting, over a rating screen still
animating away, so the tap was lost silently.

### The pair on the work screen reads like every other pair

"Went differently" is a secondary button now, and it stands ABOVE "Done" rather
than under it. The two read as a pair the way every other pair in the app does:
the filled one is what the screen expects, the outlined one is the other answer.
The accent outline is gone with the swap — this is the alternative to finishing
the set at plan, not a rival to it.

`ink3` for the outline, not `hairline`: the paired-secondary idiom uses hairline,
but both of its call sites draw on `cardBG`, and here the ground is `bg`, where
hairline comes to ≈1.2:1 and the border is simply not there. ink3 reads ≈2.4:1,
past the 1.5:1 the palette holds for quiet graphics, while the ink2 label keeps
the 4.5:1 small text needs.

The entry now opens IN THE SLOT OF THE BUTTON THAT OPENS IT, directly over the
primary one, with the informational lines standing down while it is up. And the
row of three labels is finally gone: the actions row holds the two escapes, and
"Went differently" is a view of its own.

### One vertical step above the button and below it

The stack read unevenly: 10 pt from the message to "Done", 18 pt from "Done" to
the row under it. Both are 18 now — levelled UP, not down. The 18 is load-bearing:
it is the only thing between a thumb aimed at "Went differently" and the button
that LOGS THE SET, and levelling down to 10 would have spent that guard to buy
symmetry. It is the measure for the whole stack now rather than an exception in
it — the entry, the maximum note and the first-run hint all keep it, and the rest
offer on Today keeps it above Start too.

### The same distance to the button, and the number entry back over it

The maximum note stood further from "Done" than the rest offer stands from
"Start" — 10 pt plus the height of a HIDDEN first-run hint plus 10, because the
hint sat between them holding its space open. The same reserved strip left the
number entry floating as a narrow pill in the middle of the screen.

The hint is declared first in the block now, before the note: its height is still
reserved, so nothing jumps mid-exercise, but it no longer stands between the note
and the button. Both screens read the same 10 pt.

The entry itself is the width of the button and sits directly on top of it, and
while a number is being entered it REPLACES the messages above rather than
stacking under them — one thing to read at a time, and the panel lands where the
eye already is. Nothing below moves: the block after the spacer is bottom-aligned,
so what is added or removed above the button changes where the block starts, never
where the button sits.

### One window, one way out, and controls that reach the bottom of the screen

**The same question drew two different windows.** iOS 26 presents a
`confirmationDialog` as an anchored popover, and a popover clings to the view its
modifier is attached to — so "Leave the workout?" opened centred over the flow
while "Add past workouts to Health?" grew a tail pointing at the toggle row it
was declared on. All four are alerts now. An alert has no anchor: one window,
centred, wherever it was raised from.

**And the workaround the popover forced is gone with it.** A popover suppresses
its cancel action, because tapping outside IS the cancel — which is why the
escape had to be added as a second, role-less button. An alert does not:
measured, the node is `Alert` with no `Popover` beside it and every declared
button stands in the accessibility tree, `.cancel` included. So the escape is one
button again, carrying the role AND the name that says what it does. "Cancel"
answered "cancel what?"; "Keep training", "Keep my progress" and "Keep my
history" do not. The catalog key went with it, and six translations behind it.

**"Went differently" is a control now.** It was one of three bare labels sharing
a row, and the most important of the three did not look like a button at all —
entering what actually happened is the main thing that screen offers besides
finishing the set. It is a bordered accent button across the width; the two
escapes moved to the line below, where they answer a different question. The 18 pt
between it and "Done" stays: "Done" logs the set.

**The first-run hint moved above the button.** It hid itself with `opacity` so the
layout would not jump mid-exercise, and the height reserved for it left the
controls floating in the middle of the screen with a hole underneath. It now sits
beside the maximum note, above the button — the controls are last in the stack, so
they reach the bottom, and nothing jumps.

**The rest-day run offer is an accent card**, the same one the work screen gives
the maximum note. Grey 13.5 pt under the plan was the one place nobody looks, and
both lines carry the same status: worth reading, blocks nothing.

### Today stops asking a question it does not answer

"Why this plan?" sat beside the duration on Today and read as an answer about
THIS plan — these six movements, these numbers. It opened the static explainer,
which names none of them and does not know what today's plan is: the same class
of claim the truthfulness pass above is about, in the one place where the label
itself made the promise.

It is gone. The explainer is untouched and still reachable from the door that
describes it honestly — Settings → "How it works" — which is also where anyone
who skipped onboarding is told to look. The duration row is a single line again,
the `HStack` around it went with the button, and the catalog key went with the
six translations behind it: a dead key outlives a control in silence.

Nine frames of the contact sheet moved, not one — the row is drawn by `planView`,
so it stands on every state of Today that carries a plan.

### Engine v3.3.0 — a comeback stops charging for the set the probe borrowed

A probing appearance replaces the last working set (§40.4), so the plan reads
`2×15` plus one set of the next movement while the position still holds three.
§41.10 wrote the memory of that showing by its WORKING sets — 30 — and the
postcondition then read any plan that came back to three sets as a rise and cut
one off. A comeback after twenty days landed on `2×13` with `sets = 3` in the
state: the only place in the engine where the plan and the position disagree.

**The depth of a comeback was not monotone in the length of the break.** The
trim stops firing exactly when `s × new dose ≤ (s−1) × old dose` — dose ≤ 10 for
three sets at 15 — so a break long enough to knock the dose that far let the
third set back in and the plan jumped UP. Measured on the reference: 14–28 days
gave `2×13` (26), 56–70 days `2×11` (22), and 84–95 days `3×10` (30). Eighty-four
days met a person **higher than fifty-six did**, while the card on that screen
promises "the longer the break, the lower the plan meets you". Out of an ordinary
appearance the same ladder is clean — `3×12 → 3×11 → 3×10 → 3×9` — so the probe
was the whole of it.

**§41.11:** the memory of a probing appearance counts the set the probe occupied
— the plan the position implies, `shownWorkOf` rather than `exerciseWork`. The
probe does not remove a set, it borrows one; `estimatedMin` has always counted it
as its own set because the session is no shorter for trying. Counting the probe
at its own dose instead does not help: the repair can only TAKE SETS OFF, so its
base has to be about slots, not reps.

Named plainly, because it undoes half of what §41.10 claimed: a quiet week after
a probing session now lands on `3×14`, not `2×14`. The "+40 % of the work the
person had just seen" that argued for `2×14` was measured against 30, where the
probe counts as nothing — the session held 15 + 15 + 4 in three slots, and three
sets of 14 is three slots, each one lighter. The dose axis is still guarded: `3×15`
is the standing position and the grid goes no higher.

The reference gates stayed clean through the change (74 772 property checks — 217
of them new — the acceptance script, the model sweep and the static audit), and
the fixture moved wherever a probe appears. `verify2` block 30 and two sweeps in
`DescentSweepTests` pin the invariant that did not exist before: for any two
breaks, the longer one may not land higher. Both go red on the old rule; the four
tests that pinned §41.10 were rewritten to §41.11 rather than relaxed.

### Every question that can cost you something now shows the way to say no

Three dialogs asked something destructive and drew no way out. "Leave the
workout?" drew two buttons, both of which leave the workout and one of them
without saving. "Start from scratch?" drew exactly one button, and it resets
every movement. "Replace history?" drew one, and it overwrites the journal. In
each the way to back out was a tap on the dimmed area outside the card, which
nothing on screen mentions.

Each declares `Button("Cancel", role: .cancel)`, and on this iOS that button
does not exist: not drawn, and absent from the accessibility tree entirely —
`descendants(matching: .any).matching(identifier: "Cancel").count` is zero with
the dialog open, so VoiceOver cannot reach it either. The cause is not ours:
iOS 26 presents a `confirmationDialog` as an anchored popover — the tree
carries a `Popover` and a `PopoverDismissRegion` — and UIKit suppresses a
popover's cancel action, because tapping outside IS the cancel. Measured across
seven variants at two independent call sites: it is not a cap on the number of
buttons, not declaration order, and not the title or the message.

A button with NO role renders, is hittable and is reachable. Each dialog now
declares one FIRST, so it draws furthest from the destructive row, and each
says what it does rather than "Cancel": "Keep training", "Keep my progress",
"Keep my history". The `.cancel` button stays beside it — it costs nothing on
this OS and it is what an OS that does not eat the role would use.

"Keep my history" also carries the cleanup the cancel action never got to run:
dismissing that dialog by a tap outside left the picked file in state, with no
way to reach the line that clears it.

The tap outside still works and its test still passes; what changed is that it
is no longer the only way.

### Both sides of a per-side hold carry the same load

A per-side hold runs one set as side one, a five-second switch pause, side two.
The second side started from the PLAN — and the first side does not have to
have reached it. Stop the first side at 20 seconds of a planned 30 and the
second still asked for 30.

Those ten seconds went nowhere: the fact recorded for the set is
`min(side one, side two)`, so the extra time on the stronger side could not
show up in the number, and the two sides of one set were loaded differently.
The second side now runs for what the first side actually ran.

`holdTotal` itself moves, not just the countdown and its end date —
`stopHoldEarly` measures what was held as `holdTotal - remaining`, so leaving
the old total standing would have made an early stop on the SECOND side report
more than was held. Nothing in the engine is touched: the number it receives is
the same `min` it always was, and the path that changed only decides how long
the second side runs.

Pinned by a UI test, since the hold's state lives in the view: at the
adjuster's 90-second ceiling the old answer and the new one are ninety seconds
apart, and reverting the one line reddens it.

### The rating screen says which movements it does not touch

Under the list of what was skipped stood "These keep their place either way."
A bare plural demonstrative over a list that usually holds one movement; a
"place" the screen names nowhere; and the part that actually matters — that it
is true whichever of the three cards you press — folded into an idiom. It reads
"The rating doesn't apply to these — they stay as they were." now: the thing
the reader is about to press, and what happens to the movements it skips over.
"These movements" rather than "the skipped ones", because the same list carries
the row that says "not finished".

### The probe stops printing its own number twice

"One set to try it: 4" put the target in the caption under the dots — and the
big number directly above it is that same target: on a probe set before a
number is entered, `workNumber` returns exactly `current.planned`. The caption
reads "One set to try it." now.

On a hold probe the big number starts counting down once the timer runs, so
the target then shows nowhere — which is what an ORDINARY hold already does,
so the probe simply stops being the one screen that repeated itself.

### A probe that fell short says what happens, not where the engine stands

"We'll stay with the current variation" needed explaining, and for two reasons.
It said *variation* — a word this app's own vocabulary uses nowhere else on
screen. And it pointed at something that is NOT on screen: on the probe set the
title is the NEXT movement under a "Probe" badge, so "the current one" is a name
the reader has to reconstruct, while the passing line names its movement
outright. It reads "Not this time — the plan stays as it is." now: the
consequence, which is the thing the reader will actually see tomorrow.

It deliberately does not promise the probe comes back next time. Usually it
does — but a session later rated "tough" that lands on this pattern suppresses
it, and that is the same over-promise the passing caption was just fixed for.

### The note about a maximum says the true thing, and says it out loud

Entering more than the plan on a set that is not the last one put a line on
screen: grey 13 pt, in the fine-print slot directly above the black primary
button — the one place on that screen nobody reads. It is an accent card now,
in the fill the app already uses for the variation badge (`accentText` on
`accentSoft`; the plain accent is 2.91:1 on that fill and would not do). It
still blocks nothing and still appears once per exercise: the number stands
either way.

**And it now advises the thing that is actually true.** It used to read "Do the
plan, and leave your maximum for the last set", which is about the ORDER of the
sets — and the order does not reach the engine at all. The fold is the mean, so
12-6-6 and 6-6-12 arrive as the same 8.00 and land the same next plan; what
moves the plan is the total. Measured on a plan of 3×8: holding the plan and
adding a maximum (8-8-12) folds to 9.33 and the next plan is 3×9, while trading
the other two sets for one big one (12-6-6) folds to 8.00 and the next plan is
9-8-8. The card says that instead — a maximum now takes the strength out of the
sets after it, and what counts is the whole exercise. It also stopped
addressing the reader formally in Russian, which was one of the three such
strings the glossary had on its register.

The rule behind it moved out of the view body into `SetFacts`, where a test can
reach it — the same reason `didFullPlan` lives there — and is pinned twice: the
predicate itself, and the measurement that the engine cannot tell the two
orders apart.

### The way back in from a pause is a count-in, not a walk

Pausing a guided block and tapping Resume put a **ten-second** "Get ready" on
screen — the length of the transition that walks you to a position. But Resume
is tapped by someone already standing on the mat, and the tree said so in two
places and denied it in a third: `BlockPause` called it "a count-in, not travel
time" while wiring it to the transition, the test pinning it called being
counted back in "travel, not a turn inside one", and `GetReady.countInSeconds`
claimed the way back in already got the same five seconds it does. It got ten.

It is five now — the same beat every start tap buys. The 3-2-1 still fits with
two beats to spare, and the reserve the two blocks are budgeted to the second
against is untouched: a pause is not part of the announced duration, so this
can only make a paused session shorter. `--uitest-long-transition` no longer
stretches it, which is now written where the flag is defined instead of being
true only by accident.

### Engine v3.2.0 — a descent stops handing a set back

A probing appearance replaces its last working set (§40.4), so the plan on
screen is `2×15` plus one set of the NEXT movement. The memory of that showing
was not written at all — `recordShown` and the rating both skipped an exercise
carrying a probe, on the grounds that "2×15 plus a probe" and "3×15" are
incommensurable. So the base the postcondition compares against stayed a
showing two appearances old.

Any descent then knocked the dose off the ceiling, the probe went with it, and
**the third working set came back**. Measured on the reference: a quiet week
(the silent decay, which shows nothing at all) turned `2×15` into `3×14` —
**+40 % of the work the person had just seen**. A comeback of two to four steps
did the same at +30 %, +20 % and +10 %; holds went `2×45 s` → `3×40 s`, +33 %.
The comeback card printed the two offers side by side, and the "easier" one
carried the bigger number.

**§41.10:** a probing appearance writes its memory too, by its WORKING sets —
`exerciseWork` already counts only those, because the probe is a set of another
movement. What is compared is not two sets of movements but the work of one
movement's working sets: same variation, same unit, same sides, commensurable
by construction. The descent now lands on `2×14` and `2×13` instead of `3×14`
and `3×13`. `repairDescent` still leaves a probing plan alone — there is
nothing to trim inside it.

The reference's own gates stayed clean through the change (74 555 property
checks, the acceptance script, the model sweep and the static audit), and nine
of the fixture's 28 scenarios moved — every one of them a scenario that reaches
a variation ceiling. Two tests that pinned the old rule were rewritten to the
new one, and the case their rationale feared — "the next ordinary plan reads as
a rise and gets trimmed" — is now pinned as its own test: a PASSED probe raises
the position, and a risen position is never trimmed, because the repair keys on
the position ordinal and not on the work.

**The comeback card shows the whole plan.** Its "as it was" row printed only
the working sets, so the probe on top of them was invisible and the two offers
could not be compared by eye. It now reads `… · 2×15 + probe: … · 4`.

### The screen stops promising what the engine does not do

An audit walked every UI surface against the engine (the reference document
first, the code as the arbiter) and nineteen claims did not survive it. All of
them are fixed; none of them changed what the engine does — only what the
screen says and shows about it.

**Numbers that lied by a comparison.** The work screen's accented "actual N"
and the history sheet both compared against an exercise's flat base dose,
which stopped being the whole plan the day plans became uneven (9-8-8): an
untouched top set displayed the plan as an entered fact, and a recorded
shortfall equal to the base displayed as nothing at all. Both now compare set
for set, through two small policies in `SetFacts` where a test can reach them.
The per-pattern chart also plots all six coordinates of a position now — a
snapshot without the sub-step and the cut sat up to two steps off the number
beside it — and the journal snapshot records those two sparse coordinates,
optional-with-default like every field ever added to a persisted type.

**Promises the mechanics could break.** "Next time: <the new movement>" after
a passed probe is now silent when the working sets already fell short — the
engine reads that session as "hard", and a hard pattern's probe does not count
(§40.4). The first-workout hint no longer says a big number lands "right
away" (facts are capped by the variation's own grid; the way up crosses
variations only by probe). The comeback card says what the drop really is —
the longer the break, the lower — instead of always "a couple of steps". The
migration card stops claiming "same movements, same numbers": ten hold cells
of 480 rise to the new floor, a band above a non-top variation comes off, and
the card now says a few numbers moved a step. "The next asks a little more"
gained "where there is room" — the weekly budget and the parked ceiling both
make quiet sessions, and the caption used to contradict the plan on screen.

**Labels that named the wrong thing.** The Live Activity called the probe set
by the old movement's name while the person was doing the new one; it now
names the probe. The "New variation" kicker stood over set-band milestones —
more sets of the same movement, the opposite of a new one; those rows now say
"More volume". "Eleven things worth knowing" sat over twelve sections numbered
1–9, 12, 10, 11; it says twelve, in order. The jubilee's "since your first
workout" was measured from the first v3 record — for a journal carried over
from v2 that is not the first workout, so the line now speaks of the interval
between its own "then" and "now". The progress forecast counted growth events
to the dose ceiling while the milestone itself — the probe, the band — stands
one point past it (and a taken-off set returns first), so the countdown now
lands on the same tick the bar draws, and the probe's label says the probe
decides. Skipping the probe set carried an accessibility hint promising the
set would be "kept off next time" — a probe skip keeps nothing off, it just
comes back; the hint now says so. And the line under the progress chart no
longer credits a break for a drop that the returning session's own skipped
sets caused.

Every changed base string was re-translated in all six languages by editing
the existing catalog entries in place, so the established terminology and the
French typography survive. The fixes are pinned by `UITruthFixTests` — each
test fails against the code as it stood — and the set-band kicker's UI test
now asserts the honest label it used to document as a known wrong one.

### The clock waits for you, and "easy" is earned

**Five seconds between the tap and the clock.** "I'm ready" and "Start hold"
used to put the countdown under your thumb: the number jumped from the
transition's to the position's — or from the plank's target straight into
running — while your hand was still moving away from the glass. Every start tap
now buys the same five-second count-in the way back from a pause already got.
On a hold this is preparation time that always existed, just moved inside the
app's clock: it used to be spent *before* the tap, and on a hold it came off
the number the engine measures. On a transition the count-in can only shorten
what is already running — the two blocks are budgeted to the second. While it
runs, the escapes are hidden rather than removed, so nothing jumps up under
your thumb.

**"Easy, could do more" is for a workout done in full.** It is the one rating
that claims *more* than the plan, so the plan has to have been finished for it.
Skipping an exercise or typing your own number already kept it away; a movement
that quietly lost a set did not, and the tap still bought the full two steps on
the dose. The card now dims when anything fell short, with one line under the
three saying why — and the same sentence travels as the card's VoiceOver hint,
because "dimmed" on its own is a riddle. Honesty downward is never gated: "hard,
did less" and "on plan" stay live in every state.

**The technique card reads as steps and mistakes.** The three steps are
numbered in filled circles instead of sharing one bullet with the two mistakes,
which now carry a ✕. Nothing was reworded; the card simply stops asking you to
work out which line is which.

**A towel over the table edge.** The setup step for table rows now says what to
do when the edge cuts into your fingers — a grip that hurts ends the set before
your back does.

**Localization.** The French catalogs are now uniform on the typography French
actually uses — non-breaking spaces before `: ; ! ?` and inside guillemets, and
the typographic apostrophe throughout — which is 79 strings that read the same
and break correctly. Three technique steps in French, Italian and German gained
the pronoun those languages want for a body part. The progress chart's axis
label was still the retired word "level", which VoiceOver reads aloud: it now
says steps, in your language.

### Engine v3.1.0 — what the audit of v3.0 found

A full audit of the engine that shipped in v3.0 — thirteen independent passes
over the model, then a round of trying to knock each finding down. Eight
survived. Every one of them is fixed here, and each fix carries a sweep that
would have caught it.

**"Make it easier" was making things harder.** Pressing the handle drops you one
variation, and the engine put you back at the number that variation last showed
you. But the movement below is often trained *one side at a time*, so the same
number is twice the work: sliding leg curls at 3×15 became single-leg glute
bridges at 3×15 **per leg** — 45 reps turning into 90, right after you said it
was too much. Measured across the whole library, work went **up on 49 boundaries
out of 49**, by as much as ×11.25 in time under load. The landing now walks down
from that remembered number until the plan fits the work you were already doing.
Three boundaries out of 49 still rise, at most ×2.00, because there is nothing
lighter in the library to land on — they are named in the spec rather than left
to be discovered.

**Tapping "Done" on a probe did not count as doing it.** The probe is the last
set of an exercise and the only way into a new movement. Finishing a hold
recorded itself, because the timer had a number to record; finishing a set of
reps by tapping the button recorded nothing at all, so the engine concluded the
probe had not happened. **Eight of the ten ladders were frozen this way** — the
only people who advanced were the ones who happened to adjust the number by
hand. A tap now records the target it asked for, exactly as the timer already
did.

**Your journal recorded the plan, not what you did.** When a plan is uneven —
8-7-7 — and you did all of it, the app collapsed that to a single rounded 7 and
the engine, unable to tell "took the top set" from "did not", wrote the plan's
top into your journal instead. A number that was in none of your sets. Across
the model that was **2 903 inflated cells out of 28 880**, and the journal is
what a descent lands on, so an inflated cell put you back on a set you never
did. What travels now is the honest average with its fraction intact — 7.33 is
the plan met, 7.00 is not — and the journal stores whole reps as before.

**Two weeks of honest training could leave you below where you started.**
Between workouts the plan eases off very slightly, which is right after a real
break and wrong for someone with a long, *regular* cycle: coming every ten days
was read as ten days off, every time. Someone training that way for two years
ended up on the first variation of all ten movements. The engine now recognises
a rhythm from eight intervals instead of three, so a steady cycle is read as a
cycle.

**Upgrading no longer starts you from zero.** A state written before v3 could
not be read, so the engine started clean — and your history stayed, which made
it worse: the one line explaining how to enter your own numbers only appears
when the journal is empty, so an upgrading trainee never saw it once. Your
answer about the pull-up bar went too. Every position from the old scale now
maps onto the new one, with your doses, your rotation and your bar. **470 of the
480 possible positions land no heavier than they were**; the remaining ten are
holds that used to go below the shortest hold the app now offers, and they come
*up* to it. A card on Today says what happened, once.

**Five constants that exist for safety are now pinned twice** — once as a
number, once as the behaviour they buy. A silently edited "at most ×1.50" is not
something any sweep would have noticed.

**Three of the six gates a release runs did not run at all.** They called
functions the v3.0 wave had removed and died before their first check, which
reads exactly like passing. It was the second wave in a row to lose gates that
way, so the checklist is now machine-read by a runner
(`scripts/check_engine_gates.py`) that fails on a gate which did not print its
clean line. The wave's own acceptance set was rebuilt for v3 — twenty blocks,
including one that proves the "not heavier" check is no longer comparing the
plan against itself. It had been doing exactly that: breaking the rule on
purpose produced **zero** failures.

### Engine v3.0.0 — the engine stops predicting and starts measuring

The wave before this one gave you the decisions. This one takes away the
engine's guesses.

**The principle is one sentence: the engine does not predict — the engine
measures.** Nothing can be assigned that you have not already done. Every number
in your plan is either something you showed, or that same thing plus one rep in
one set.

**What made this necessary was a workout, not a theory.** Closing out Bulgarian
split squats at 3×13 per leg unlocked pistol squats at 3×5 per leg — and not one
of them was possible. The engine was certain it had done you a favour: by its
own arithmetic the new plan was **×0.38** of the old one in time under load. It
was measuring the wrong thing. Thirteen Bulgarian split squats say nothing about
whether one pistol squat will happen, and **on all thirty variation boundaries
the old engine thought it had made things easier** — up to six times easier on
the hinge ladder. The better you had gone through the previous variation, the
higher you stood when the new one arrived, and the harder you fell. And when you
answered honestly that it was too much, the fall did not stop at the step that
failed: the descent landed on the *floor of the tier*, taking back the whole
tier you had climbed.

**Everything below follows from removing the guess.**

#### One number per movement is gone. Position is a variation and a dose.

The level `L ∈ [0, 47]` encoded the variation, the rep target and the set count
at once, and every one of those was derived by arithmetic from a single integer.
That arithmetic is deleted, not deprecated — with it go the rep ladders per
tier, the tier and band floors, the landing rule for unit changes, the level
decoder, and the inversion that turned an honest number back into a level.

What replaces it is what you can point at: **which variation you are on, how
many reps or seconds per set, how many sets** — plus a journal of what you have
actually shown in each variation. That journal is what a descent lands on now.
Not a floor: the last dose you really did in that variation.

Progress screens follow. A movement's scale is now its position along **its own**
ladder, with its own denominator and a tick where each variation begins, because
the ladders have genuinely different lengths — four variations for lunges, seven
for the hinge — and one shared 0–47 axis would be a fiction. "Total level" became **"total steps"**, and
a workout recorded before this wave says it has no number on that scale rather
than inventing one.

#### The library: 59 positions instead of 40, and no step you cannot reach

Fourteen new exercises and nine assisted steps, so that the gap between
neighbours is something a person can cross. The rule is written down and checked
by a number: **the load of one position may not exceed the previous by more than
×1.5.** Across the 48 comparable boundaries of the shipped library there are now
**zero gaps**, and the largest step is **×1.49**. The shipped v2.27 library had
twelve gaps out of thirty.

The old grid had a second problem, quieter and worse: because the dose dropped
at every boundary, each boundary silently claimed that one rep of the new
movement was some number of times harder than the old one. That number had a
median of **×2.60** and a maximum of **×6.00**, and it was written down nowhere —
it fell out of the encoding. Now the difficulty of every position is stated in
the spec with its provenance, and the step density is an invariant the reference
suite checks, not a by-product.

Three movements moved out of the strength ladders into the warm-up — Y-T-W,
bird-dog and the single-leg Romanian deadlift — and jump lunges with a pause
left altogether. The warm-up is a **pool of nine now, six per session** (the way
the cool-down already picks 6 of 9), and each session's warm-up still runs
exactly 245 seconds, as before.

#### The probe: you try the next movement before it becomes your plan

When your dose reaches the top of the grid, the **last working set of that
movement is replaced by one set of the next variation**, with a target of 4 reps
(15 seconds). Not an extra set — a replacement, so the session does not get
longer for trying. It is not a new question either: you answer it with the same
per-set number you already use.

- You do 4 or more → the next variation becomes your plan, starting at **3×4**.
- You do fewer, or skip it → nothing moves. The working sets you did still
  count, and the probe comes back next time.

**A failed probe is information, not a failure**, and the app says so: under the
number it reads "We'll stay with the current variation." There is no penalty, no
lost progress, and no set taken away. The one boundary in the whole library
where the unit changes — from a hang in seconds to negative pull-ups in reps —
is now crossed **only** by a probe, because seconds and reps were never
comparable and the old engine's rule for comparing them is deleted.

#### Updating starts you over — deliberately, and without touching your history

> **Reversed later in this same release.** What follows was true of v3.0 and was
> undone by v3.1: the upgrade carries every position across instead of starting
> clean. Kept as written because the *reason* below is still why the carry-over
> had to be positional. See "Upgrading no longer starts you from zero" above.

There is no state migration. A saved plan from an older build is not readable by
this engine, and rather than guess a conversion, **every movement starts at 3×4
again**. Your **workout journal, settings and history are untouched** — that was
the one thing this could not cost, and a defect that would have quarantined the
whole file along with the engine was found and fixed before shipping.

Getting back is not a climb through the old scale, because the rule "facts
outrank the plan" does it for you: show more than the plan asked, and the next
plan equals what you showed. In the reference run, going from a clean start back
to Bulgarian split squats took **four appearances** — the spec had promised
"around five".

#### What did not change

Rotation and slots, the pull-up bar gate, warm-up and cool-down as the previous
wave built them, skipping a set or the rest of a movement during the workout,
per-set numbers, one question a day and one finger. No network, no dependencies,
no analytics: "Data Not Collected" stays literally true.

#### The numbers this wave was held to

The reference suite runs **71 334 checks with 0 failures**. A separate acceptance
script sweeps the model rather than the table: **59 264 transitions**, none of
them assigning more than "what you showed, plus one"; **49 entries into a new
variation**, every one of them exactly 3×4. The golden fixture — 24 scenarios,
257 steps — regenerates byte-for-byte, and the Swift port matches it bit for
bit.

### Engine v2.27.0 — you decide during the workout, not before it

The wave before this one took away everything that decided for you and gave you
handles instead. Two of those handles still sat **in front of** the workout, on
the plan — "fewer sets" on a movement, and "a shorter session today" — and both
asked you to answer a question you cannot answer yet: *how much have I got in
me today?* You find that out on the third set, not while you are looking at a
list.

So the decision moves to where the answer is. On the work screen, under the
button that logs the set, there is now **"Skip this set"** and one escape for
the movement — **"Skip remaining sets"** when you have already done some of it,
**"Skip exercise"** when you have not. Skipping goes straight to the next set:
no rest on the way, because nothing was done to recover from.

**Three rules make that honest, and each of them exists because the obvious
implementation gets it wrong.**

- The skip reaches the engine **after** the rating, never before it. A session
  you finished well hands a set back instead of a level (that is how sets
  return since v2.26), so a cut written in advance is eaten by exactly the event
  that should have returned it later. Written in the right order, one skipped
  set at level 24 turns 3×4 into 2×4 next time; written in the wrong one, the
  skip silently never happened.
- **On the floor of two sets there is nothing to record**, so the tap travels as
  an ordinary skipped exercise — never as a dose of 0, which would cost eight
  levels for work of perfectly ordinary quality. You did the sets you did, at
  full dose; you did fewer of them.
- **The escape also works per movement**, because sixteen separate taps is not a
  thing anyone does. At level 47 fitting a session under 45 minutes takes 16
  single-set skips — or **6 taps**, one per movement.

**The number follows the decision instead of predicting it.** The work screen
carries what is **left** of the session and drops it the moment you skip
something. Today carries a **range** — the full plan, and the shortest that
session can be made from inside it — so "will this fit today" has an answer
without pulling anything first:

| Level | Full plan | Shortest | |
|---|---|---|---|
| 0 | 34.0 min | 25.7 | −24 % |
| 16 | 32.6 | 24.8 | −24 % |
| 24 | 38.0 | 27.3 | −28 % |
| 32 | 52.0 | 29.0 | −44 % |
| 40 | 79.7 | 33.7 | −58 % |
| 47 | 94.3 | 39.5 | −58 % |

Both numbers are the engine's own arithmetic handed a shorter list, not an
app-side estimate that would drift from the line on the plan by exactly the
amount nobody could account for.

**What is gone, and what it costs you.** Three things leave with this wave, and
one of them is a real loss rather than a simplification:

- **The short version is gone.** "Short on time? Three of the six exercises" was
  the app choosing which three movements you would skip today — the same
  philosophy as the time budget the previous wave removed, and the last piece of
  it left. It also lived outside the engine, which is how it quietly broke the
  promise the store makes: it delivered **20.5 minutes** while the listing and
  the spec said the shortest possible workout is **24.8**. **So the floor of the
  app really did move up, from 20.5 minutes to 24.8**, and anyone who was using
  the short version to fit training into twenty minutes has lost that. There is
  no smaller version coming: level 0 — three sets of eight in the gentlest
  variation of six movements — is the declared bottom of the product, and about
  25 minutes is what it costs. If that is not what you have, this is the wrong
  app, and we would rather say it here than let you discover it.
- **The session handle is gone**, and with it the preview it gave: *37 → 26 min*,
  both numbers on screen before you agreed to anything. If certainty before the
  start is what you wanted, a range and a live recount are a worse answer than
  the one you had. It is named here rather than buried: the wave traded
  certainty in advance for a decision you make when you actually know.
- **"Fewer sets" / "More sets" on the plan rows are gone.** The axis they wrote
  is untouched — the same cut, moved by the same person, at the moment they know
  the answer.

**The journal now counts skipped sets.** Nothing on screen shows them yet. They
are recorded because the open question this wave leaves — whether a skip that
costs nothing becomes the thing everyone reaches for, and the plan drifts
quietly down — can only ever be answered from the journal, and a record that
kept only the rating could not answer it.

**Everything else is bit-for-bit what it was.** The engine loses one exported
function and nothing more: across 4,070 cells of pattern × level × cut ×
sub-step the plans are identical to 2.26.0, all 16 state fields survive a
session unchanged, a year of levels comes out within ±0.0 % on four different
answering styles, and the announced duration moved by **exactly zero** minutes —
asserted as a number, so it cannot creep the way it did (deliberately, by one
minute) in the previous wave.

**One thing got worse and is not fixed here.** At the accessibility Dynamic Type
sizes the work screen still has no scroll view, and this wave puts one more line
in its header and one more control under its button. The Today half of the same
problem is gone with the handles that caused it. The remaining half is a layout
decision, and a layout decision hidden inside a feature wave is a decision
nobody reviewed — it stays on the register as I-15.

### The design re-review

Five app-layer fixes. The engine is untouched by these: `DredfitCore/` has no
diff and `golden.json` is the same file.

- **The break band says its length legibly.** The "N days" label on the grey
  band of the Progress chart was ink3 on that fill — 2.16 : 1 in light,
  2.57 in dark, against the 4.5 : 1 floor the wave that drew the band set
  for itself. It is ink2 now: 4.55 and 5.94, and 5.99 / 6.54 in the two
  Increased Contrast variants. It also went from 10 pt to 11, which was the
  only text in the app below 11, so the width a band must have to carry a
  label went up by the same tenth — otherwise the narrowest band's label
  would lie across the line it explains.
- **The badge pill follows the theme.** It is rendered to a bitmap, and the
  bitmap was cached without the appearance in its key, so a pill drawn on a
  light Today survived into dark mode. Both the key and the render now carry
  the colour scheme and the contrast setting.
- **Four controls that were smaller than a fingertip** — the flow's Exit and
  its "technique" affordance, Today's per-movement handles, and the session
  handles, whose code said 34 pt while its own comment promised 44 — are 44
  pt of target. The flow's header grows about 26 pt for it and a plan row
  about 29.5.
- **A tap on a plan row stops rewriting the plan.** With every button in the
  row default-styled, a List treats the row as one control: one tap on the
  empty strip beside "Fewer sets" took a set off and the announced duration
  went from 35 min to 33. A UI test holds it now. The calendar also stops
  lending "day-N" to cells of the neighbouring month.
- **VoiceOver gets the scale.** A Progress row read "Squat, 18" — a number
  with nothing to measure it against, because the scale is drawn as a bar.
  It reads "Squat, level 18 of 47". On the work screen the number and its
  unit are one element, so "8 reps per side" arrives as one fact.

### The twenty waves that were prepared as 1.10.0

The longest stretch of work in the project's history, and the one that changed
the least about what you see. Three multi-agent audits of the engine and its
golden contour — 2026-08-11, 2026-08-16 and 2026-08-23 — confirmed findings
faster than any single wave could carry, so this stretch is the remediation
itself: the engine steps from **v2.5 to v2.26** in twenty waves, each a full
pass of the reference cycle (spec → reference → verifier → golden → Swift
port). The verifier grew from 9,367 property checks to 638,696 and then came
back to **443,415** when the last wave removed two mechanisms; the golden
fixture went from 11 scenarios to 28 and back to **24** for the same reason.
Every new field decodes tolerantly — the state and journal formats still need
no migrations.

What the waves are about, in the order the priority ladder puts them:

- **Do no harm.** A descent may never add load: the "not harder" gate now
  counts sides and stands on every path down, not one of three (v2.19), and
  the engine finally has a way to say *the same exercise, but less of it* —
  sets come off without touching the level, so a plan that has to go lighter
  can (v2.25).
  "Tough" steps back exactly the way it came, one position at a time
  (v2.23). A comeback lands no heavier than your last workout (v2.12), and
  the Swift port sanitizes anything a corrupt file hands it (v2.13). The pain
  channel was rebuilt three times across v2.19, v2.20 and v2.23 and then
  **removed** in v2.26, because the 2026-08-23 audit found it broken in four
  independent places at once — see that entry for what answers "this hurts"
  now.
- **Keep the habit.** A steady rhythm stopped being read as a break
  (v2.13), and the plan parks on what you can actually do instead of
  running ahead of it — growth adds one set's worth at a time (v2.22).
  In v2.26 the lighter plan of v2.25 became something **you** reach for: two
  handles on the plan, and a session length the app announces instead of
  enforcing. The
  45-minute default of v2.24 went with the enforcing — it is the last thing
  in this stretch that was built and taken back.
- **Improve results.** The aim reaches the weak link instead of the loudest
  movement (v2.15), honest facts are never scored worse than a tap (v2.14),
  the push plan stopped flickering (v2.16), the vertical push gained the
  rung its ladder was missing between the pike push-up and the wall
  handstand (v2.18), and hold ladders became per-tier tables with
  a one-second entry corridor, so a single second short costs a single rung
  (v2.21).

Three things were built and withdrawn inside this same cycle: **"hold this
level"** (v2.6, withdrawn v2.22), the **pain channel** in the shape v2.19–v2.23
gave it, and the **45-minute default** (v2.24, withdrawn v2.26). None of them
reached the App Store, and nothing in a saved file carries them forward. They
are named in the list below rather than dropped from it: a changelog that
quietly deletes what it got wrong is harder to trust than one that says so.

### The engine waves, one line each (v2.6 → v2.26)

Newest first. Each was a full pass of the reference cycle — spec, reference
implementation, verifier, golden fixture, Swift port — and what each wave
measured to prove itself lives in the commits and the pull requests. What is
kept here is what changed for the person training.

- **v2.26 — you decide, not the app.** Two mechanisms come out whole. The pain
  channel was broken in four independent places at once: an honest repeat of
  "it hurt here" never ended the episode, and a "tough" after it left the dose
  above where the pain started. The time budget was no better — of the rungs it
  offered, 10, 15 and 20 minutes all produced the same plan. What replaces them
  is handles you press yourself, on the plan rather than inside the workout: an
  easier variation, one set off or back on a movement, fewer sets everywhere,
  fewer movements. Each shows the exercise, the dose and the new duration
  *before* you agree, and the announced length is a statement, not a rule the
  app enforces behind your back. Level 0 became a declared floor rather than a
  hole: the easiest workout the app could build was three sets of eight in the
  gentlest variation of each of six movements, about 34 minutes, and the
  shortest it could build at all, with the handle pulled down, about 25
  minutes. The price is named rather than buried: for
  someone training six times a week and answering "easy", the median session
  went from 41 to 65 minutes, because nothing trims it for them any more. The
  levels they reach over a year are the same either way.
- **v2.26, in the guided blocks.** The run-in before every warm-up and cool-down
  position doubled to ten seconds — fifteen where you have to walk to a wall or
  get down on the floor — and both blocks now say how many positions and roughly
  how many minutes before they start you. This is the wave that made every
  announced duration in the app one minute longer.
- **v2.25 — the sets handle.** The engine had no way to say *the same exercise,
  but less of it*: a level chose the variation and the dose together, so the only
  way down was to change the movement, and the top of the tier below is heavier
  than the bottom of the one you stand on. Sets became a second axis, and the
  four ways a plan could come out **heavier** when it had to come out lighter — a
  comeback after a week away, a pain report, an honest "tough", the "I was ill"
  lens — all went to zero. A plan you looked at and did not train stopped being
  invisible to the engine.
- **v2.24 — a short workout stops overshooting.** Trimming used to cap every
  movement at once, so asking for 45 minutes could hand you 30 with the missing
  quarter-hour buying nothing; the plan now gives up the single most expensive
  set at a time. It never removes a movement — a set costs you nothing in
  progress, a missing movement costs all of it. And a day became a calendar day
  in your timezone, so a workout at 23:00 and one at 01:00 stopped being the
  same day and a flight stopped inventing one.
- **v2.23 — "tough" steps back the way it came.** Saying a session was tough
  could hand you five times the work, because a whole level down often crossed
  into the middle of an easier variation where the dose starts higher. It now
  gives back exactly what the last step up added, and the deload that follows
  three tough sessions passes through the same "no harder" check as everything
  else.
- **v2.22 — one set at a time.** A step up used to add its dose to every set at
  once — a quarter more work of your hardest variation for saying "on plan", so
  the plan could never settle where you actually were. Growth now lands on one
  set: 3×8 becomes 9-8-8, then 9-9-8, then 3×9, and the plan parks on your
  capacity instead of overshooting and falling back. "Hold this level" was
  removed in the same wave.
- **v2.21 — hold steps go relative.** Every step up in a hold was a flat five
  seconds, which is half again as much work at the bottom of the hardest tier
  and a rounding error at the top of the easiest. A step is now about a tenth of
  the dose you are on, and seconds are entered one at a time rather than snapped
  to the nearest five. Reps are untouched.
- **v2.20 — a pain episode ends without numbers too.** One tap of "this hurt"
  could park a movement for good: the only way out was logging an exact number,
  and this app is built for one question answered with one finger. Three clean
  appearances now close an episode as well.
- **v2.19 — a descent never adds load.** A pain report used to drop the movement
  a whole tier, and where the tier below is one-sided the volume went *up* — 3×4
  became 3×5 a leg, two and a half times the work for a tap that meant the
  opposite. The first report now keeps the movement you know at its lightest
  dose; only a second one changes the exercise. Training twice in one day also
  stopped freezing progress permanently.
- **v2.18 — the rung the push-up ladder was missing.** Pike push-ups led straight
  into a wall handstand entered by kicking up at nearly full bodyweight. A
  feet-elevated step now sits between them, and getting in and out of the
  handstand — walk up, walk down, turn the head and step over — became part of
  the instruction rather than an assumption.
- **v2.17 — you decide how long a workout is.** A session length in Settings,
  a set band that no longer halves the work when you enter it, a real two-minute
  rest on the hardest variations, and a weekly ceiling so training every day
  cannot outrun tendon adaptation.
- **v2.16 — the push plan stops flickering.** With a bar, the rule keeping the
  push from running ahead of the pull read whichever pull branch was in today's
  session, so the push plan flipped between 5×4 and 3×6 every session with no
  cause shown. It now reads the weaker branch.
- **v2.15 — the aim reaches the weak link.** When one movement was beyond you and
  the rest were fine, the app eased off everything except that movement — the
  rule picked the *highest* one in the session, and a weak link is by definition
  the lowest. The movement that keeps failing is now the one that steps down, one
  inflated first session no longer costs a month of deloads, and Today asks once
  about the movement "tough" keeps landing on.
- **v2.14 — honest facts are never scored worse than a tap.** Holding a plank for
  21 seconds against a 20-second plan moved nothing while stopping at exactly 20
  earned a step; beating a plan the app itself had trimmed lowered your level; and
  an honest zero high on the scale handed back half again as many reps. Meeting
  the plan became a window rather than a point, and a descent never asks for more
  than what you were just given.
- **v2.13 — a corrupt save file cannot break the plan.** A nonsense level in a
  damaged file used to be read as the level you were at, so every honest session
  counted as a shortfall and the app handed out an unearned deload. Every number
  the state and journal hold is clamped to what it can mean.
- **v2.12 — a comeback lands no heavier than your last workout.** Three weeks
  away from a mid-scale level used to return you to 1.86× the work of your last
  session, and half a year of illness could still offer tier-4 archer rows. Every
  landing is now capped at the bottom of its range, repeated returns dig deeper,
  and "I was sick" became one tap that makes the next six workouts easier without
  touching your levels.
- **v2.11 — pain takes the load off and asks before growth resumes.** A pain
  report used to freeze a movement at its full load and then quietly resume
  growth into the sore joint a week and a half later. It now unloads the movement,
  and growth waits for evidence rather than for a timer.
- **v2.10 — the pull keeps up with the push when you have a bar.** With the bar
  on, the pull slot alternates between two branches and each kept its own count,
  so the pull climbed at half speed while the push climbed at full — 22 weeks out
  of 94 below the balance the model is built on. Training one branch now carries
  the step to the other, and the push never shows more sets than the pull it
  belongs beside.
- **v2.9 — "harder than usual" stops punishing the movements that were fine.**
  One tap handed the same step down to all six movements of the session; over 48
  workouts of identical behaviour that spread the movements 24 levels apart and
  stood some of them still forever. The tap now goes where you pointed, and when
  you named nothing, to the one movement standing highest.
- **v2.8 — the polish wave.** An exact number equal to the plan now counts as
  progress, so logging honestly every session stopped being worth less than
  tapping. The rest between sets follows the set band — 60, 90, 120 seconds —
  instead of one minute everywhere including the heaviest work in the library.
- **v2.7 — the do-no-harm gate.** Calibrating from zero stopped teleporting the
  plan across the scale; long breaks land where the body actually is; a 7–13-day
  pause stopped counting toward a deload; and garbage in a state file heals on
  the next engine call instead of poisoning the plan.
- **v2.6 — "Hold this level".** Built here, withdrawn by v2.22. It asked the
  athlete to make a decision mid-workout that the finer growth step now makes for
  itself, and it was tapped zero times in the 24 sessions it existed for. It
  shipped to nobody.

### The app-layer changes of that stretch

- **"Went differently" belongs to the set you tapped it on.** A number entered on
  the last set of three was recorded for the whole exercise — one rep short at
  the end of an honest workout cost a level and a tick toward a deload. Each set
  now carries its own number, the sets are shown as they ran ("15 · 15 · 10"),
  and the engine is told the volume you actually did.
- **A steady rhythm is not a break.** The app promoted a weekly cadence and then
  read every one of those weeks as a lapse: two years of never missing a Sunday
  drained a level a week while a six-day twin climbed to the top. A gap that
  matches your own last three gaps is now your rhythm — no silent decay, no
  comeback card, the plan simply waits.
- **The 45-minute default**, built in this stretch and withdrawn with the budget
  in v2.26. It reached no one.
- **Two quiet lines on Today**: one when a movement has hurt twice running,
  pointing at the ways down and, from the third time, at seeing a specialist; one
  offering a rest day before a fourth consecutive training day. Nothing is
  persisted, nothing blocks, no count is presented as an achievement.
- **The care note became a checklist you have to see.** The contraindications are
  named — heart condition or chest pain under load, treated or high blood
  pressure, dizziness, a joint injury that flares, pregnancy or recent childbirth
  — Skip now lands *on* that card rather than past it, and its button reads "I
  understand — start". No questions are asked and nothing is gated on the answer.
- **A longer run-in for positions you have to walk to** in the warm-up and
  cool-down: five seconds where you already stand, ten where you have to get down
  on the floor or reach a wall. v2.26 later doubled both.
- **The pull climbs one step at a time from the second variation.** Its fixed slot
  puts it in every workout, so at identical feedback it climbed 1.6× faster than
  anything else in the model.
- **The tones grew a voice of their own.** Three bare sines became seven sounds
  with a body and a hierarchy — the frequent quiet, the rare bright — and every
  ending is announced, whatever ended it. Switching sides is a rhythm rather than
  a melody, because eyes closed halfway through a stretch you cannot tell two
  melodic pairs apart. All of it is code, deterministic and pinned by tests; no
  audio asset ships.
- **The app follows the system appearance.** The forced-light pin came out, every
  screen sits on one explicit background token, and labels over ink-filled shapes
  flip with the scheme instead of painting white on near-white. Increased Contrast
  gained real values in both schemes.
- **One palette, one source.** The brand colours moved into the asset catalog, so
  the widget stopped keeping its own hand-maintained copy of the same ten values,
  and the mark's third ring — invisible at favicon size since a contrast pass
  retired its grey — came back at a colour you can see.
- **The golden fixture names the reference that generated it**, and the verifier
  closed the holes an audit found in itself. Neither changes anything you can see;
  both are why the waves above can be trusted to have measured what they claim.

### Fixes

- Silent decay now fires on a cold launch too (issue #93). The 7–13-day
  blind-zone decay used to run only on a scene-phase transition, which a
  cold launch never produces — the most ordinary comeback ("return after
  8 days, open the app, train") ran the whole session on pre-break levels.
  The activation sequence now lives in one store seam, `activate()`,
  called from both `onAppear` and the `.active` transition, with a
  cold-start regression test.
- Importing an unrelated backup no longer hides its workouts from Apple
  Health (issue #103). The import used to keep this device's high-water
  export mark and stamp every foreign record beneath it "already
  exported" — those workouts silently never reached Health, with no way
  back. Journals now count as the same lineage only when they share a
  record identity (session number + date); an unrelated journal keeps its
  own mark. The legacy mark→flags migration runs only on flag-free files,
  which also stops a reload from stamping a post-reset session 1 under
  the old mark. Restoring an older backup of your own journal keeps
  today's guarantee: nothing re-exports.

### Housekeeping

- **343 → 596 automated tests**, counted across the same three layers 1.9.0
  counted: **70** in the engine package, **464** in the app, **62** in the UI
  suite. The engine's share is small on purpose and grew the way the engine did:
  it is
  compared against the JavaScript reference rather than against itself, and
  `GoldenTests` replays the recorded trace of 28 scenarios and 282 steps
  bit-for-bit, so a port that is plausible-but-different is a red test and not a
  judgement call. The app's share is where the growth is, and most of it is
  guards written *after* something was found: the export loop that could not
  stop, the stored position that took the app down from the Progress screen, the
  restore that carried an upgrade over in silence, the descent that handed a set
  back, the comeback whose depth stopped being monotone in the length of the
  break. Every one of those tests was run against the code as it stood before
  the fix and observed to fail — a fix pinned by a test that stays green either
  way is not pinned.
- **The reference gates are read out of `TESTPLAN.md` by a script now.** Three of
  them had twice died before their first check, which prints nothing and reads
  exactly like passing; each row of that table names the clean line its gate must
  print, and a gate that did not print it fails.
- **The golden fixture names the reference that generated it**, and a manifest
  check fails CI on a fixture changed without provenance — a fixture regenerated
  from a stale local reference used to be indistinguishable from an honest one.
- **The UI suite gates nothing and is run anyway**, locally, before the tag. It
  drives the whole flow through one shared walk rather than a copy per test, so
  what it protects is the sequence — a countdown that survives a locked phone, a
  workout resumed after the app was killed, a rest day that offers rest — none of
  which a unit test can see.

## 1.9.0

The largest release the project has shipped, and the first to reach the App
Store since 1.8.0: three versions' worth of waves in one submission. The
regulator gains the dimension it never had — how fast a movement is allowed to
climb — and an answer for "my joint hurt" that is not "tough". Both guided
blocks gain a pause and a run-in before every position. German, French and
Italian join, so the app speaks seven languages. And the screens stop
promising more than the engine can deliver. The engine steps to v2.5, verified
against the reference at 9,367 property checks; the state format and the
journal format are untouched, so there are no migrations.

### Engine safety wave: growth ceiling and discomfort (issue #38, closes #64–#67)

- The regulator gains a dimension it never had: how fast a movement is allowed
  to climb. The single `+2` ceiling becomes a table by movement and variation,
  because tissue is not uniform — calves climb one step per workout at every
  variation (everything loads the Achilles), the vertical push from the wall
  handstand up, and every movement on its fourth variation, where the archer
  variants and the set bands live. Everything else keeps two. The cap is the
  only dial that acts before an overload rather than after it.
- "Tough" no longer has to stand for both "my muscles gave out" and "my joint
  hurts". A new **Something hurt** action on the exercise screen — one tap, no
  dialog, its own line next to the skip — ends that exercise and rests the
  movement: it keeps its place in the plan at the same level and stops
  climbing for its next three appearances. A level can still go *down* while
  it rests, and no deload can fire on top of the rest.
- Today carries a quiet line while a movement rests ("Resting for now: …"),
  the rating screen lists it under **Discomfort** rather than **Skipped**, and
  the calendar's history row says "hurt". A ninth "How it works" section
  explains what the report does and repeats the stop rule.
- Reporting survives everything a skip survives: process death mid-workout,
  the resume card, and a break — neither the silent decay nor the comeback
  clears a rest, on purpose. State files written before this decode unchanged.
- Engine v2.5.0: reference spec §15, 9,367 property checks, and a new golden
  scenario for the freeze. The ceiling table lives in the spec and the
  verifier compares it against the shipped one cell by cell, so the two cannot
  drift apart silently. Strings complete in all seven languages.

### Screen honesty pass (issue #73)

- The rating screen stops promising a multiple. "Easy, could do more" said
  progress comes twice as fast and the completed state repeated it, which the
  growth ceiling made untrue in v2.5: a session built from fourth variations
  climbs exactly like "on plan". Both captions now promise a direction and no
  size, because the size is knowable only after the answer is applied.
- The freeze says how long it lasts. A resting movement carries its own
  counter on Today — "3 more times" — read from the engine's own
  `freezeRemaining`, which the screen had never asked. It counts appearances
  of that movement rather than workouts, and the wording drops the claim of
  rest so it stays true for the second, milder entrance being added in #75.
- The rating states its scope once. The banner under the heading and the
  summary card said the same thing, under a comment demanding the two never
  contradict each other; the count moves into the card header, where the
  itemisation right below already answers "which ones".
- Rest can be extended, not only cut short. "+15 s" sits beside "Skip rest",
  both outlined and of equal weight, repeatable to twice the planned rest and
  greying out in place at the cap. Someone who is not recovered used to have
  the choice of standing at an expired timer or starting a set they would not
  finish — and the engine reads the second as "tough", so this protects the
  regulator's input rather than comfort.
- A break owns its cost. The silent decay lands between two journal entries
  while the chart draws one point per entry, so the drop appeared inside a
  completed workout — deliberate quiet reading as an accusation. Gaps of a
  week or more now carry a band behind the line with their length inside it,
  and one line under the chart. That line names a cost only where the levels
  fell across the gap *and* the first workout back cannot account for the drop
  itself — neither by its rating nor by a number entered in it. Anything less
  strict would put the mistake this wave removes from the rating screen back
  on the chart.
- Two lines earn their removal: "Last time you chose" re-weighted three cards
  that are meant to be equal, and the weekly summary gave its space to the
  chart. The load caption under the big number stops printing the number
  again.

### Warm-up and cool-down: a "Get ready" transition before each position (issue #52)

- Both guided blocks used to start every position cold: the 30 seconds of a
  warm-up move and the timer of a cool-down stretch began the instant the
  previous one ended, while you were still getting off the floor, reading the
  next name or looking for the wall. The first seconds of the interval went
  into moving house, not into moving — and for a beginner that reads as "I
  can't keep up" rather than "the timer starts too early".
- Every position is now preceded by a five-second "Get ready: <move>" — the
  first one included, because you have just pressed Start and are still
  standing by the phone. It names what is coming, opens its technique sheet
  like the position itself does, runs the usual 3-2-1 into the go that starts
  the movement, and carries the same two escapes (this position, the whole
  block). "I'm ready" starts the position at once: the transition is a floor
  on the pause between positions, never a wait.
- The go-tone moved to where the movement actually starts. A position now
  ends silently and the transition speaks with its own 3-2-1 — two gos five
  seconds apart would have said nothing twice. The falling "switch sides"
  tone keeps its one meaning.
- The pattern already half-existed: the side-switch pause of 1.8.2 counts a
  transition inside a position, this one counts the transition between them.
  Same five seconds, same wall clock, same survival of a locked screen; a
  backgrounded block still jumps whole stages instead of stretching itself.
- No estimate moves. The engine reserves 8 minutes for the two blocks
  (`warmupMin` 5 + `cooldownMin` 3); with the transitions they spend 210 s on
  the warm-up and 220–235 s on the cool-down — 430–445 s of the reserved 480.
  The number on "Today" keeps promising at least what the flow delivers, and
  the engine, `estimatedTotalMin` and the golden fixtures are untouched.
- VoiceOver reads the transition as one phrase, "Get ready: Cat-cow". At the
  accessibility text sizes a three-line position name plus the countdown no
  longer fits the screen, so the block's content scrolls and its escapes stay
  pinned — the running move and stretch screens gained the same treatment.
- Strings in every shipping language. "I'm ready" is translated by sense —
  «Начать» / "Empezar" / "Começar" / "Commencer" / "Inizia" — because "ready"
  takes a gendered adjective in Russian, Spanish, Portuguese and French; only
  German keeps the adjective, where "Bereit" has no gender to take.

### Warm-up and cool-down: a pause for the guided blocks (issue #61)

- The guided blocks are the only part of a workout that runs strictly on
  timers. Working sets are self-paced, and a rest timer that kept counting
  while you answered the door merely granted extra rest — but in the warm-up
  and the cool-down the block kept marching through positions without you.
  The only two options were to let it run past, so the flow pretended you did
  positions you didn't, or to throw the whole block away. The honest move —
  pausing — did not exist, and this app is built for people training at home,
  where the doorbell, the kettle and a child are normal.
- Every timed screen of both blocks now carries a **Pause**: the position
  countdowns, the "Get ready" transitions, the "Switch sides" pause. Paused,
  the countdown stops on the second it showed, the number dims, the unit under
  it says so, and every tone ahead of it goes quiet. Like every other timer in
  the app the pause is wall-clock based — with no deadline left to run out, a
  locked screen or a backgrounded app changes nothing.
- **Resume** counts you back in rather than dropping you mid-position: five
  seconds naming the position, the same 3-2-1 into the go a "Get ready" plays,
  and then the interval continues from the seconds it froze on — never from
  the top, never a position later. The two transitions are the exception —
  "Get ready" and "Switch sides" already are ways back in, each with its own
  signal still ahead of it, so they simply carry on.
- The pattern already half-existed, twice. Opening a position's technique
  sheet freezes the countdown (reading is not stretching), and the "Get ready"
  beat is a screen where the flow already knows how to stand still. This
  promotes that hidden freeze to a control you can find. Where the two meet,
  the user's pause wins: closing the mini-sheet never restarts a block that
  was stopped on purpose.
- Nothing about the numbers moves. The pause is user-initiated, so
  `estimatedTotalMin` keeps promising what an uninterrupted flow delivers, and
  the duration written to Health stays the wall-clock truth of the session.
  Working sets and their rest timers are untouched — they are self-paced by
  design. The engine and the golden fixtures are untouched.
- VoiceOver announces "Paused" and "Resumed", and the state is readable under
  the countdown. Strings in every shipping language.

### Localization: German (issue #63)

- German joins English, Russian, Spanish and Brazilian Portuguese, complete —
  every key across the four String Catalogs: the 40-exercise
  library with its technique steps and common mistakes, the 15 warm-up and
  cool-down position sheets, the "In real life" lines, onboarding, "How it
  works", milestones, the anniversary retrospective, the widgets and the
  Health permission strings.
- The register is du — lowercase, calm, and gender-free: the athlete is never
  named by a gendered noun. The terminology keeps the app's three concepts as
  disjoint in German as everywhere else — Variante (which exercise, 1 of 4),
  Stufe (one unit of level change), Level (the number itself) — and prefers
  the words German home training actually uses: Kniebeuge, Liegestütze,
  Klimmzüge, Ausfallschritte, with Plank kept English because that is what
  German says. A bare "Pause" only ever means the seconds between sets; a
  longer absence is a Trainingspause, and a deload an Entlastung.
- No code changed for the language: the one locale-sensitive label ("on
  Monday") already had a default path that German's uniform "am + weekday"
  fits, so the catalog carries "am %@" and the switch in
  `nextTrainingDateLabel` stays three cases long. The engine and the golden
  fixtures are untouched.
- The marketing site ships the same five languages: dredfit.com/de (landing
  and privacy policy), with hreflang alternates and sitemap entries on every
  page. Nine German store screenshots join the set, captured through the
  standard pipeline.

### Localization: French and Italian (issue #69)

- French and Italian join the shipping languages, each complete across the four
  String Catalogs: the 40-exercise library with its technique steps and common
  mistakes, the 15 warm-up and cool-down position sheets, the "In real life"
  lines, onboarding, "How it works", milestones, the anniversary retrospective,
  the widgets and the Health permission strings. Seven languages now.
- Both address the reader as *tu*, and neither ever genders them: French leans
  on impersonal turns ("C'est fait") rather than a masculine "Prêt", and
  Italian on `avere` participles ("hai fatto") rather than an *essere* one.
  Buttons follow each platform convention — French infinitives ("Commencer"),
  Italian second-person imperatives ("Inizia").
- The app's three-way distinction survives translation intact in both: French
  *variante · cran · niveau*, Italian *variante · gradino · livello*, with the
  words for a technique step kept clear of them (*étape*, *passaggio*). The
  rest cluster is likewise disjoint — French *repos · jour de repos · coupure ·
  allègement*, Italian *recupero · giorno di riposo · pausa · scarico* — so a
  sixty-second rest never reads like a fortnight away from training.
- French typography is honoured rather than approximated: narrow no-break
  spaces before `? ! ;`, a no-break space before `:`, typographic apostrophes,
  and never an elision against a placeholder.
- No code changed for either language: both take the same default branch of
  `nextTrainingDateLabel` that German uses, with the weekday label carried in
  the catalogs ("le %@" in French; the bare day in Italian, whose article is
  gendered). The engine and the golden fixtures are untouched.
- dredfit.com ships /fr and /it — landing and privacy policy — with hreflang
  alternates and sitemap entries across all seven locales, and nine store
  screenshots per language through the standard pipeline.

### Localization audit across the seven languages

- French and Italian stop bending the grammar of the exercise they name. A
  participle after the placeholder cannot agree with "Pompes" or "Flessioni",
  so the skipped and unfinished labels now carry their own noun — "Pompes,
  exercice ignoré", "Flessioni, esercizio saltato" — instead of a masculine
  ending glued to a feminine name.
- Nothing addresses the reader by gender any more. The Russian privacy page
  drops the formal "вы" that it alone still used, the "you export it yourself"
  lines lose their masculine "сам" / "tú mismo" / "você mesmo", and six Spanish
  and Portuguese starting positions turn from "Acostado boca arriba" into the
  imperative the rest of the library already used.
- Terminology reconnects to the glossary: Brazilian "Deload" becomes
  "Descarga", the wall handstand goes back to the name the exercise library
  gives it in each language — the Spanish copy had picked up "el pino", a
  Spain-only word — and German "Equipment" becomes the "Zubehör" the site was
  already using.
- The English source loses its one piece of gym jargon: "kipping doesn't count"
  is now "using momentum doesn't count", and the Russian, Spanish and
  Portuguese calques go with it.
- The site says what to tap. "Tap it during the workout" had no antecedent on a
  page that shows no button, so every language now names the control, and the
  German "Ein Tipp" (a hint) becomes "Ein Fingertipp" (a tap). Typographic
  quotes replace the straight ones left in English, Spanish and Portuguese, and
  the landing page gains the card for the discomfort feature.
- The glossary records the decisions that let the drift happen: a row for the
  wall handstand, the French and Italian placeholder rule, "ты" for Russian
  legal copy, and gym jargon banned in the English source too.

### Widget: the longest exercise names fit the large size again

- On the large home-screen widget in Russian the longest name in the catalog
  — «Птица-собака» (удержание) — ended in an ellipsis. The plan row carries
  the load in the long form the snapshot writes ("3×20 сек на сторону"),
  which left the name short of the width it needs. The name now shrinks a
  little instead of truncating, the way every other line of the widget
  already does — and an ellipsis is the worst of the two, because sibling
  variations differ at the end of the name. Brazilian Portuguese already fit;
  English is nowhere near the edge.

### Widget: it stops asking to be refreshed once its snapshot runs out

- The app writes the widget two weeks of days; the widget asked for its next
  timeline "after the last one". Once only today was left, that moment had
  already passed by the time the timeline arrived, so the widget re-asked
  immediately, got the same expired answer, and spent the day's whole refresh
  budget on it — which is exactly the budget a real change needs the moment
  the app is opened again. It now asks again after midnight instead. Reachable
  after two weeks without opening the app, which is a break the app already
  models rather than an accident.
- The same budget went on the one-off Apple Health backfill: exporting a year
  of history poked the widget once per workout, for content none of those
  exports can change.

### Cool-down: the "swap sides" steps say something useful now

- "Chest and shoulders at the wall" and "Wrists and forearms" still had
  "Swap arms — or hands — halfway through" as their third technique step,
  left over from when the user did the counting. Since 1.8.2 the app counts
  both sides itself, so the line only repeated the timer. Both now carry a
  technique line like the other four one-sided stretches: keep the shoulder
  down and away from the ear, and pull the wrist only to a stretch. In every
  shipping language.

### Calendar: the footer names the month you are looking at

- Paged back to June, the card under the grid still read "This month" over
  June's count — a sentence about August stating June's number. It now names
  the month on screen whenever that is not the current one.

### Site

- dredfit.com stops advertising the public TestFlight link (issue #72). It sat
  in the hero line under the download button and again in the footer, on the
  landing and the privacy page alike, in all seven languages — an advertised
  entry point that has to stay correct, with a build expiring every 90 days
  and a beta review to keep passing, next to an App Store button that keeps
  the same promise better and has been the real call to action since 1.8.0.
  Internal TestFlight distribution is untouched, and testers already invited
  keep their builds.

### Housekeeping

- One more finding from the review that produced the widget and calendar fixes
  above: the go-tone could sound over a "Get ready" screen. A long absence —
  a locked phone, a backgrounded app — crosses several stage boundaries at
  once, so the boundary that opened the run and the stage the countdown
  actually landed on are two different things. Choosing the signal from the
  first alone announced a movement over the name of one that had not started;
  both blocks read the landing too now.
- The technique button on a position screen carries an accessibility
  identifier. It was the one control the tests drive that had none, so it was
  addressed by its English label, and a localized run could not open the
  technique sheet at all.
- 284 → 343 automated tests. The engine's new ceiling table is compared
  against the reference cell by cell, so the shipped one and the spec cannot
  drift apart in silence; the rest covers the discomfort report surviving
  process death and a break, the freeze horizon counting appearances rather
  than workouts, rest extended to its cap, the gap band under the progress
  chart and the single line that may accompany it, both guided blocks pausing
  and resuming, and the get-ready transition as a floor on the pause between
  positions rather than a wait.
- The nightly UI job's retry flags fire for the first time since it was split
  out of the release gate: `-retry-tests-on-failure` had never once produced a
  second iteration, so a flake cost a red run rather than a retry. Two races
  in the suite itself went with it — a hold countdown that expired under its
  own Stop tap, and a transition the tests had five real seconds to find and
  tap.
- Every comment in the app, the engine, the widget and the tests was read and
  reduced to what an edit would break without, and the repository's counters
  match the code again: README's three test layers, TESTPLAN's header, and the
  pull-request checklist, which still asked for three translations when six
  ship.

## 1.8.2

A fix release for the cool-down: the two stretches that told you to swap
sides now have the app counting them, like the other four already did. No new
features; the engine, the state format and the journal format are untouched,
so there are no migrations.

### Cool-down

- "Chest and shoulders at the wall" and "Wrists and forearms" ran as a single
  30-second countdown while their own technique steps said to swap arms —
  or hands — halfway through. They were the two positions where the app knew
  the stretch was two-sided and still handed the count back to the user: no
  "15 s per side" line on screen, no five-second switch pause, no falling tone
  to move on. Both are counted now: 15 seconds a side with the pause between
  them, exactly like the hip flexors that open the block.
- Why they were missed: the per-side flag was introduced with the cool-down
  itself, when it only decided whether to print the "15 s per side" hint, and
  the counted switch was later built on the same flag without re-reading which
  positions are actually one-sided. A unit test then pinned the old
  classification under the name "unilateral positions only", so the mismatch
  looked deliberate.
- The block is a little longer as a result: never under 3:10, up to 3:25 when
  three of the session-mapped stretches are one-sided too. The reserved
  cool-down minutes in the engine's estimate are unchanged — the pauses ride
  on top, inside the "≈" every duration carries.

### Housekeeping

- 283 → 284 automated tests. The new one is a guard rather than a regression
  test for this bug: it asserts that no position the app treats as bilateral
  tells the user to swap sides, so a step text and its flag cannot drift apart
  again the way these two did.

## 1.8.1

A small fix release: a widget that keeps asking for fresh data instead of
sitting on a timeline dated in the past, and a documentation pass that makes
the repository describe the app it actually ships. No new features; the
engine, the state format and the journal format are untouched, so there are
no migrations.

### Widgets

- The fallback timeline entry — the one used when the App Group snapshot is
  missing or cannot be decoded, which is the state a widget added before the
  app's first launch is in — was a stored `static let` built with `.now`.
  A stored static is initialised once per process, so its date froze at the
  first access and every later timeline request in the same extension process
  received an entry already dated in the past, asking WidgetKit to refresh a
  timeline that had expired before it was handed over. The entry is computed
  now and carries the time it was actually built.

### Housekeeping

- The countdown tones clamp their sample conversion into `Int16` range.
  Nothing changes for the three tones that ship — every sample was already in
  range — but the tones are generated inside a `static let`, so raising an
  amplitude past 1.0 would have trapped at the first countdown of a workout
  rather than at the edit that caused it.
- Documentation caught up with the code. README still described the v2.2 level
  encoding (`reps = 8 + L % 8`, a ceiling of 5 × 15) although per-tier floors
  landed in v2.3 — it is `repStart[tier] + L % 8` with floors 8/6/5/4, so the
  ceiling is 5 × 11 — and still counted the reference cycle at 4,150 checks
  and 133 steps across 9 scenarios instead of 8,009 / 143 / 10. The app
  section predated 1.8.0: no short version, no cool-down, no side-switch
  pause, and widgets described as home-screen only. TESTPLAN promised 24
  reminders "with the default rest day" after the default became two days
  (a 28-day window holds 20) and still expected six "How it works" sections
  where there are eight. Four files pointed at `instructions/GIT_FLOW.md`,
  which does not exist; `.github/WORKFLOWS.md` now carries the local UI-run
  procedure itself and the workflow comments point there.
- 281 → 283 automated tests. Neither code fix earns one — the widget one is a
  static-initialisation timing issue whose regression test would pass or fail
  depending on the order tests run in, and the clamp is a no-op for every
  amplitude the app ships. The two new tests are the release smoke instead:
  the S1–S7 block of TESTPLAN, which was walked by hand before every release
  and never changed between them, is now a suite that walks it in English and
  in Russian. Running the full test plan before cutting a release covers that
  block by itself. The walk that drives a workout to the rating moved into one
  shared driver at the same time: it existed in a single copy, and the release
  smoke needed the same steps — two copies of it would drift, and the last
  time this walk drifted it cost the nightly six red runs.

## 1.8.0

A feature release that makes the workout whole: the cool-down the estimates
always promised, a short version for the days there is no time, technique
help on every warm-up and cool-down position, a counted side switch, and
honest guidance on weekly rest. Around the session, Progress learned to draw
the journey, the widget grew into every size, and the milestone card shows
where you started. The engine steps to v2.4 — a silent level decay for
7–13-day breaks, verified against the reference and recorded as golden
scenario 10; the state format and the journal format are untouched, so there
are no migrations.

### Widget: every timeline day speaks from its own date

- The "Next workout today / tomorrow" line was computed once when the app
  wrote the snapshot and copied into all fourteen timeline entries, so a
  rest-day entry rendered days after the app was last opened could claim
  "Next workout today". The app now precomputes the label for every day —
  localization, including the Russian accusative and the pt-BR weekday
  gender, stays app-side — and each widget entry reads its own word.
- "This week" on the large family is stamped with the Monday it tallies
  and no longer shows on next-week entries, where last week's numbers
  would read as the current week's.
- The timeline mapping and the widget's word choices are under unit tests
  now: the widget sources compile into DredfitTests, and the Live Activity
  contract moved to ActivityShared.swift so app and test types never twin.

### Localization audit: ru / es-419 / pt-BR pass over all four catalogs

- Russian athlete-facing strings no longer assume a male user: the three
  feedback buttons («Готово», «Легко, могу больше», «Тяжело, получилось
  меньше»), the stop line and the onboarding copy now use gender-free
  forms — the previous masculine past tense read as a male self-description
  under a female user's finger.
- es-419 is now actually Latin American: Apple-lexicon UI terms (Agregar,
  Respaldo, Configuración, Restablecer, Calificar), gym terms (pantorrilla,
  parada de manos, flexión pike, enfriamiento) and «Omitir» for the whole
  skip family; peninsular forms (hacia delante, todo el rato, gemelos,
  tumbado, sustituir) are gone. Status labels with a substituted exercise
  name switched to invariable phrasings («%@, quedó fuera») because the
  old participles broke on feminine names.
- pt-BR: the same invariable status fix («Prancha, ficou de fora» instead
  of the ungrammatical «Prancha, pulado»), «alguns passos» instead of the
  «um par de passos» calque, Deload kept in English, the barra fixa family
  completed (negativa/parcial), suspensão instead of the noun «pendurada».
- Counts decline correctly now: the exercises number in "≈ %lld min ·
  %lld exercises" got plural forms via a substitution bound to the second
  argument (all four languages, app and widget catalogs), the rest
  countdown got its missing English singular, and the big-number caption
  agrees with the number above it («1 повтор / 3 повтора / 12 повторов»)
  instead of a frozen genitive.
- The "on %@" weekday phrase moved into code: Russian accusative
  («в среду», «во вторник») replaces the old prefix heuristic that
  produced «в среда», and pt-BR now picks no/na by weekday gender.
- Four English source cues were reworded where the source itself was
  flawed (hollow shape, active hang, the Y-T-W rep definition, the
  2-second hold ambiguity) — catalog keys and Library.swift renamed
  together, translations already matched the intended reading.
- The ru Health privacy description no longer promises more than the
  English source ("nothing else is shared", not "shared nowhere").

### Engine v2.4: silent level decay for 7–13 day gaps (issue #37)

- The comeback only starts at 14 days, leaving the 7–13 day zone blind —
  the most common real-life break length (vacation, work trip, a cold) met
  an overestimated plan on the single most churn-prone session. Now a
  quiet −1 lands on every pattern when the gap enters that zone: no card,
  no UI, applied once per break on scene activation, clamped at 0.
  `failStreak` and `counter` are deliberately untouched.
- The two drops never stack (spec §14.2): if the silent −1 already hit the
  break, a later comeback weakens by one — the break's total is exactly
  the table value, and whoever peeked at the app mid-break is never
  punished harder than whoever stayed away. The comeback card shows the
  weakened remainder.
- Full reference cycle: spec addendum §14, reference implementation,
  verify 8 009 checks / 0 failures (was 4 150 — most of the growth is the
  exhaustive non-stacking sweep over all 48 levels), golden scenario 10
  `silent_decay` including the "decay → tough → no premature deload"
  branch. The nine existing golden scenarios reproduce bit-exact.

### Technique mini-sheets for warm-up and cool-down positions (issue #34)

- Every one of the 15 positions (6 warm-up moves, 9 cool-down pool) now
  opens a reduced technique sheet from a "technique" affordance under its
  name: the position name, a block capsule ("cool-down · 15 s per side"),
  2–3 numbered steps and "Got it". For a beginner "Lat stretch with
  support" was an empty label — and the context is harsher than for
  exercises: a countdown is running, there is no time to look anything up.
- The position countdown freezes while the sheet is open and resumes from
  the same second on close — reading is not stretching. A deliberate
  divergence from the rest-phase sheet, where the timer keeps ticking.
- The steps carry the safety the names could not: no bouncing, no pushing
  into pain, unroll the spine to come up. ~40 new keys in all four
  languages; when position schematics arrive, the steps stay as captions.
- Engine and golden fixtures untouched; the warm-up block moved out of the
  flow view into its own model (Warmup.swift) on the way.

### Side-switch pause for timed unilateral work (issue #35)

- Unilateral cool-down positions no longer ask you to count the side switch
  yourself: 15 s for the first side, a 5-second "Switch sides" pause, then
  15 s for the second — an app that gives audio cues even to the warm-up
  now counts the switch too. The pause rides on top of the reserved three
  minutes, within the "≈" every estimate has always carried; `cooldownMin`
  and the golden fixtures are untouched.
- Per-side holds run the same pause between sides, and the second side now
  starts itself on the usual go-tone — no tap needed with hands busy in a
  side plank. The recorded actual is still the smaller of the two sides,
  and the mis-tap grace on a stopped side still returns the set.
- The pause opens with its own signal — the go-tone inverted, a falling
  two-tone — so eyes-closed stretching can tell "switch sides" from "new
  position"; a medium haptic mirrors it under silent mode. The usual 3-2-1
  ticks precede the end of each side; none play inside the pause.
- One shared app-layer constant (`sideSwitchPauseSec = 5`), deliberately
  not a user setting. Per-side rep exercises are untouched — they are
  self-paced.

### How much rest is enough (issue #36)

- Fresh installs now start with two spread-out rest days (Sunday and
  Wednesday) instead of Sunday alone. Six strength sessions a week is ~3.7
  hits per movement pattern — overuse territory for slow-adapting connective
  tissue; five sits at the top of the safe corridor. Existing installs are
  untouched: a stored settings file keeps whatever week it has, including
  one written before the key existed.
- "How it works" gained a "Weekly rhythm" section: 3–4 workouts a week is
  the sweet spot — muscle adapts in weeks, tendons in months, and rest days
  protect the slower half.
- The rest-day picker in Settings carries the one-line recommendation
  ("2–3 rest days a week") — guidance, not a gate: any spread still works.
  The six-day default also quietly contradicted the no-guilt philosophy;
  this closes the cheapest known strike at the engine's uniform-feedback
  weakness by lowering stress frequency itself.

### The cool-down the estimate always promised (issue #28)

- Every "≈ N min" estimate since 1.0 has reserved three minutes for a
  cool-down that did not exist. Now it does: six stretch positions × 30 s
  between the last exercise and the rating — the block materialises exactly
  the minutes already promised, so no estimate anywhere changes.
- Composition is deterministic from what was actually performed: hip flexors
  and chest-and-shoulders first, three positions mapped from the session's
  movements (deduplicated, topped up from a pool of nine), the rest pose
  always last. A short workout stretches its three performed movements.
- Same manners as the warm-up: per-position skip, whole-block skip, wall-
  clock countdown that absorbs backgrounding. Per-side positions take one
  30 s slot with a "15 s per side" hint.
- Honest edges: "Finish now" goes straight to the rating (whoever cut the
  workout short is out of time by definition); a workout of pure skips gets
  no cool-down; process death during the block restores to the rating. The
  cool-down counts toward the duration written to Health — it is part of
  the workout.
- No levels, no journal entry, engine and golden fixtures untouched.

### A workout for the days there is no time (issue #27)

- Today offers a short version under Start: three of the session's six
  exercises, warm-up and cool-down included, around a third of the clock.
  The other three are recorded as honest skips — levels frozen, the counter
  and the rotation advancing exactly as they would have.
- Which three: the pull slot always (shoulder balance is not negotiable), the
  first movement of the current rotation window, and the lowest-level
  movement of what remains. Because the window shifts by three over eight
  rotating patterns, that anchor visits all eight within any eight
  consecutive sessions — nothing is starved even for someone who only ever
  trains short.
- The session is not regenerated: it is the same list Today shows, so an
  interrupted short workout resumes short, and its resume card counts "of 3".
- The choice is never remembered. Every day opens on the full workout, and
  nothing anywhere says "again?".
- The engine gained two read-only helpers (the rotation anchor and the
  duration estimate for a list of exercises) so the app layer holds no copy
  of either formula. Behaviour and the golden fixtures are unchanged.
- Along the way: the rating screen's summary now labels its lists separately
  — "Adjusted" only over adjusted rows, "Skipped" over skips — and says each
  thing once: skipped rows are dimmed names with no per-row echo of the
  header. The only per-row word left is "not finished" on a "Finish now"
  interruption, precisely because it differs from the header. VoiceOver
  still reads every row with its state.

### The jubilee remembers where you started (issue #26)

- Anniversary milestones ({10, 25, 50, 100, then every 50}) now carry a
  "Then → now" comparison with the first workout, built from the levelsAfter
  snapshots the journal has kept since 1.1: "Then: Knee push-up · 3×8 — Now:
  Push-up · 3×14", plus how long ago that first workout was (weeks, months
  from week nine).
- The movement shown is the one with the largest level gain; ties resolve in
  rotation order. Every number comes from the core's own encoding
  (`Level.decode`), so the v2.3 per-tier floors are respected and no level
  arithmetic lives in the app layer.
- The milestone share card carries the same two lines — still no body
  metrics, no names; the level curve gives up room rather than crowding the
  footer.
- Honest degradations: a journal without snapshots, a history without growth,
  or a bar module younger than the first snapshot simply show the jubilee as
  before. Standing still is never dressed up as progress.

### The "why" behind every movement (issue #25)

- Every technique sheet ends with an "In life" line translating the movement
  into everyday ability — "lifting a bag, a child, a suitcase — with your
  hips, not your lower back". The app explained *how* since 1.0; this is the
  first time it says *why*.
- The "New variation" milestone carries the same line under the variation
  name: an unlock reads as an ability gained, not an index incremented. Set
  bands and jubilees are deliberately left alone — volume and habit are not
  abilities.
- A closed list of four standout variations (pistol squat, push-up, pull-up,
  chest-to-wall handstand push-up) overrides the movement line where the
  variation says more than the movement. The override → base rule lives in
  one place (`LifeBenefit`), shared by both surfaces.
- Copy discipline, enforced in review rather than code: every line is a fact
  of mechanics, never a health promise. 15 new keys × 4 languages; the
  engine, the state format and the golden fixtures are untouched.

### The level curve on the share card (issue #24)

- The milestone card now draws the level curve — the total level after every
  workout, oldest first — above its footer, the same line the Progress chart
  draws. The curve takes only the room the headline leaves behind, capped so
  it never becomes the point of the card, and gives up its place entirely
  when the words need it.
- Fewer than two journal snapshots — no curve: a first-workout card stays
  exactly what it was. Still no body metrics and no names on the card.
- A workout that unlocks several variations now names every one of them in
  the headline, not just the first row on screen; the render and the
  share-sheet preview read the same line, so the two can never drift apart.

### The widget widens to medium, large and the lock screen (issue #23)

- One widget family became six. The medium spends its extra width on the week
  strip — spanning the whole card instead of crowding into a corner — and
  carries the total level in its header; the large lists the next workout's
  plan and closes with the week's tally; the lock screen gets all three
  accessories: a single glyph for the only at-a-glance question, a two-line
  rectangle, and an inline line.

### A design pass over Progress, Today, Rating and Calendar (issues #21, #22)

- Progress fits one screen: the pattern rows became a single legible list,
  and the chart projects the total level — or, when a row is picked, that
  pattern's own line built from the journal's snapshots — over a sparse
  first/middle/last date axis. The duplicate chips row is gone: it was the
  same list of patterns twice.
- A row's small print about where its level is heading shows only while that
  pattern is the one on the chart — detail on demand instead of eight rows of
  it at once. The chart title holds still when a pattern is picked, and the
  total level keeps to one row.
- Today marks a variation debut with an inline "new variation" pill at the
  end of the exercise name — a tier crossing swaps the exercise itself, the
  most meaningful event in the system — and quietly links the "how it works"
  explainer for everyone who skipped onboarding.
- The rating's consequence lines speak workout language — "on plan — the next
  asks a little more", "easy — progressing twice as fast" — instead of
  "+1 step / +2 steps", and "Finish now" says plainly that it keeps what is
  done and marks the rest skipped. The calendar's planned days open the
  next-workout preview.

### Site

- The landing dropped its "app is still in English" hedges: es and pt-BR
  have shipped complete since 1.7.0, so the note is gone and the technique
  card says "in your language" on all four locales.

### Housekeeping

- The RU catalog calls inverted rows «Тяга под опорой» again across all
  surfaces — «под опорой» pinpoints the body position (lying under the
  table) that the replacement name had blurred; the RU landing mockup
  follows (issue #19).
- The skip-all UI test asserts the rating summary's "Skipped" header plus
  all six rows via their accessibility labels — what VoiceOver actually
  reads — instead of the per-row word the rating redesign removed (issue #32).
- 198 → 281 automated tests: the variation-debut badge, the share card's
  headline and curve, the widget's timeline mapping and per-day words, the
  short workout's picks and the rotation anchor, cool-down composition and
  its honest edges, the side-switch pause, the position technique sheets,
  the silent decay and its non-stacking sweep against the comeback, and the
  rest-day defaults. The README table now counts what the runners actually
  execute, layer by layer.

## 1.7.1

A fix release: signals you can actually hear, reminders that know the workout
is already done, and a journal that is never overwritten by a launch that
could not read it. No new features; the engine, the state format and the
journal format are untouched, so there are no migrations.

### Countdown and reminders

- The 3-2-1 countdown and the tone at zero play at **media** volume through an
  ambient audio session. They used to be the system Tink/Tock sounds, which
  follow the *ringer* volume — routinely near zero while music plays at full
  volume, so the signals drowned exactly when they were needed. They still mix
  with whatever is already playing instead of pausing it, and the silent
  switch still mutes them (haptics remain the silent-mode channel).
- The audio session is primed when the workout opens, so the first tick is no
  longer the one that pays for warming it up.
- Reminders are one-shot notifications per upcoming training date within a
  28-day window instead of a weekly repeating series. A workout finished in
  the morning takes tonight's reminder down with it, tomorrow's still stands,
  and every activation slides the window forward.

### Data safety

- A state file that exists but cannot be read — data protection before the
  first unlock, a transient I/O failure — now freezes persistence instead of
  starting empty and overwriting the journal on the next save. The scene
  becoming active retries the read and unfreezes it. While frozen the app
  never shows the first-run onboarding, never publishes an empty widget
  snapshot, leaves the pending reminder window untouched, and refuses to
  export or import a backup — an empty file that looks like a backup is how
  a scare turns into real data loss. A launch the user has already worked in
  stays frozen: swapping the journal in mid-session would erase what they
  just did and leave the workout unable to record itself.
- Apple Health export: the backfill re-checks the toggle between records, so
  switching Health off stops it; it flags a record by identity instead of by
  an index captured before the save, so an import that replaces the journal
  mid-export can no longer mark the wrong workout; and the exported duration
  is clamped to at least a minute, because HealthKit rejects an interval that
  does not move forward and one bad record used to block the whole tail.
- The backup file is built when the user actually shares it, instead of being
  rewritten into the temporary directory on every settings and engine change.

### Site

- All four landing pages gained an FAQ section — free, offline, equipment,
  data, breaks, beginners — with matching FAQPage structured data.

### Housekeeping

- Version markers ("v1.5:", "v2.2:") are gone from code comments: the git
  history already records when a thing arrived, and a comment should explain
  the code as it stands.
- 182 → 198 automated tests: the frozen-journal launch and its reload, the
  work a reload must not overwrite, the widget snapshot and reminder window a
  frozen launch must leave alone, Health export under a journal that moves
  mid-flight, a disabled toggle mid-backfill, and non-positive durations. The
  Health suite moved into its own file.

## 1.7.0

Localization release: Spanish and Brazilian Portuguese join English and
Russian, each complete. The engine is untouched — no state, journal or
settings format changes, and no migrations.

### Localization

- Spanish and Brazilian Portuguese ship complete: every screen, all exercise
  technique and common mistakes, onboarding, settings, the widget and the
  Live Activity — 444 keys across four String Catalogs. Both address the
  reader informally (tú / você) and take their exercise and pattern
  vocabulary from the shared glossary; each reads as idiomatic rather than
  literal, and Spanish is neutral (no vosotros, no narrow regionalisms).
- Spanish and Portuguese count strings that always read plural now inflect:
  "1 completado" / "1 concluído", not "1 completados".

### Terminology

- English now separates the two senses that "step" used to carry — the
  exercise you do is a *variation*, the unit of level change is a *step*:
  "New step" → "New variation", "step N of 4" → "variation N of 4".
- Russian follows the same split: the rating captions moved from "+1 шаг" to
  "+1 ступень" (вариация / ступень).

### Site

- The marketing site is now four languages (en, ru, es, pt-BR), served from
  `docs/`.

## 1.6.0

Design-audit wave (2026-07): the three findings that cost user trust —
workouts dying with the process, an Exit that could only discard, and a
rating screen that nudged toward "On plan" — plus a contrast pass.

### Workouts survive

- The flow snapshots its position (exercise, set, rest countdown, actuals,
  skips) into the state file on every phase transition. If iOS evicts the
  app mid-workout — or it is swipe-killed — Today offers "Continue the
  workout?" with "Start over" as the alternative for up to three hours.
  Completing, discarding or resetting clears the snapshot; a corrupt
  snapshot degrades to "nothing to resume" without touching the journal.
- The snapshot carries a fingerprint of the generated exercise list: a
  session number alone is not identity (the bar toggle and an accepted
  comeback regenerate a different session under the same number), and a
  mismatched snapshot is never offered. A snapshot with no actual progress
  (warm-up just ended, first set untouched) is not offered either — that
  launch gets the plain Start, warm-up included. A kill on the rating
  screen resumes onto the rating screen, not the last set.
- Snapshot writes deliberately skip the WidgetKit poke that every other
  persisted change makes: none of the widget's three states can change
  while a workout is running, and 35 reloads of identical content per
  session would spend the day's refresh budget for nothing.
- Exit now confirms when there is progress on the clock, and offers
  "Finish now": the remaining exercises are marked as skipped (keeping
  their level, as skips always did) and the flow proceeds to the rating —
  running out of time no longer means losing the workout. The exercise cut
  mid-way is labelled "not finished" on the rating summary; only fully
  untouched ones read "skipped". With nothing done yet, Exit still leaves
  quietly.

### Honest inputs

- The three rating cards carry equal visual weight. The filled "On plan"
  card read as "the correct answer is the middle one" — a nudge aimed at
  the regulator's only input. Order alone now carries the scale.
- "next: +1 rep" became "next: +1 step" (also in Today's and history's
  rating captions): a step up can be a new, harder variation, not a rep.

### Calendar

- Past days without a workout no longer wear the "planned" ring — they are
  plain dimmed numbers, as the header always promised. "Planned" is future
  only, and VoiceOver stays equally silent about missed days.
- The rest-day fill is a dedicated `restFill` token (#E2E3E6) instead of
  cardBG (1.07:1 — invisible on most real screens): quiet at cell size,
  still visible as the 13 pt legend dot, with an ink2 digit. The planned
  ring darkened from #D9D9DB (1.41:1) to ink3.

### Contrast pass

- New `accentText` token (#B44504, ≥4.5:1 on white) for accent-colored
  text: "actual N" in the workout, rating summary and history, "second
  side", the onboarding diagram. Rings, chart lines and dots keep #E8590C.
- Selected chips (pattern filter, rest-day picker) use ink text — accent on
  accentSoft was 2.91:1, and the fill plus stroke already say "selected".
- Informative captions moved from ink3 (2.35:1) to ink2: the first-run
  calibration hint (also bumped to 14 pt — it works exactly once), rest-day
  chip legend, Health and pull-up bar notes, "Your rating applies to the
  rest", skipped markers, empty states, the rest-day paragraph, the
  onboarding care note, "2 / 6" in the workout header, month chevrons.

### Smaller

- The app always opens on Today; the cold-start jump to the calendar after
  a completed workout is gone (Today's own "completed" state answers that
  launch, with the calendar card one tap away).
- One warm-up move can be skipped on its own ("Skip this move") without
  abandoning the whole block.
- Settings close with "Done" instead of "Got it" — settings are a place you
  act in, not a message you acknowledge.
- The Progress share button moved out of the top corner, where it floated
  beside the global settings gear pinned by a hardcoded mirror of that
  gear's metrics, into a labelled pill next to the totals it shares.

## 1.5.1

Hardening wave after a full-project review. No new features; the engine's
arithmetic is untouched (golden parity holds bit for bit).

### Data safety

- An unreadable state file is moved aside (`dredfit-state.corrupt.json`)
  instead of being silently replaced on the next save; one unreadable journal
  entry no longer discards the rest of the file; unknown engine patterns
  (e.g. after an app downgrade) decode leniently instead of wiping progress.
- Feedback replay protection: a session that does not match the engine's
  counter is rejected by both the engine and the store, so a crash between
  saving and clearing feedback can no longer advance levels twice.
- The UI-test hooks (`--uitest-*`) are compiled out of Release builds — a
  production binary can no longer be told to wipe its own journal.
- Persist failures are logged instead of swallowed.

### Apple Health

- Export is tracked per record instead of a high-water session number. A
  failed export can no longer be leapfrogged by a later success (previously
  that workout was silently lost to Health forever), "Start from scratch" no
  longer confuses the export bookkeeping, and "Only new ones" can no longer
  re-export old workouts after a reset.
- `finishWorkout` returning no workout without throwing now counts as a
  failure and stays retriable.

### Time and Live Activity

- Crossing midnight while the app sits in memory now refreshes Today, the
  calendar ring and the week summary on the next activation (previously the
  app could show yesterday's "completed" state with no Start button until a
  cold launch).
- A killed or crashed workout no longer leaves a frozen Live Activity on the
  lock screen: stale content dims, and the next launch removes orphans.
  Activity updates are serialized, so a quick "Skip rest" can no longer lose
  the race and leave a stale countdown.
- The warm-up absorbs backgrounded time instead of replaying one move per
  expiry; an accidental "Stop" in the first three seconds of a hold cancels
  the countdown instead of recording a 5-second set.

### UI, accessibility, localization

- Feedback and onboarding screens scroll at accessibility text sizes instead
  of clipping; workout "Exit", onboarding "Skip" and "Start from scratch" meet
  contrast requirements; rest-day and chart chips announce their selected
  state to VoiceOver; calendar days speak their date and state, and the month
  chevrons grew to full tap targets.
- The workout cover snapshots its session, so the rating screen no longer
  flashes the next session's data during dismissal; the share card renders
  only when its numbers changed; the review prompt waits out the dismissal
  transition instead of burning its 60-day stamp on a dropped request.
- History resolves exercise names in the current language; the calendar
  legend and grid use one planned-day color; the widget snapshot refreshes on
  every backgrounding; reminders re-request authorization after an import;
  Russian is registered in the project, the Health share purpose string is
  localized, and stale catalog entries are gone.

### Testing

- 142 → 161 automated tests: reminder scheduling (new injectable seam),
  corrupted-file quarantine, Health export ordering regressions, day-anchor
  rollover, Live Activity staleDate arithmetic, lenient decode, replay
  no-ops, config-integrity and golden-generator pins.
- The widget snapshot test injects its URL and runs on CI instead of
  self-skipping; sleep-based waits replaced with awaitable tasks; UI-test
  assertions that could never fail now target identified elements; the UI
  target retries on failure in the test plan.

## 1.5.0

Engine v2.3. Three changes to how the regulator behaves, aimed at the two
moments where the old model was worst: your very first workout, and your
first workout back after a break.

### Calibration — the first workout now counts properly

- A pointed number entered from a standing start sets the level outright
  instead of being capped at +2. Someone who does 3×20 against a 3×8 plan
  lands on their real load in one workout rather than about ten.
- The cap is unchanged everywhere else, a skip still outranks a number, and a
  number below the plan at zero leaves you at zero without starting a
  shortfall streak.
- The rating screen says so on the first workout, once, and only while no
  exact number has been entered.

### Coming back after a break

- Two weeks away or more, and Today offers to start a couple of steps lower —
  further down the longer the break, to a floor of eight steps at twenty weeks.
  Accepting recalculates the plan; declining leaves it exactly as it was. Either
  answer closes the question for that break.
- Shortfall streaks reset on return. Without that, the first hard session back
  would ride the old streak straight into a deload and drop the level twice.
- After half a year there is also a quiet option to start from scratch. The
  journal survives, and so does the pull-up bar setting.
- No push notification, no count of missed workouts, no apology asked for.

### Softer tier changes

- Reps and holds now start lower on harder variations, so moving up a tier is
  a step down in volume rather than a jump onto a harder movement at full
  reps. A pistol squat arrives at 5 per side instead of 8.
- Level arithmetic is untouched: same 48 levels, same deltas, same deload,
  same rotation. Tier 1 is identical to before.

### Copy

- Onboarding card 2 no longer promises the load "within two or three
  workouts" — it says the load becomes yours step by step. With calibration
  the old count is true only for someone who enters an exact number; the
  softer wording is honest for everyone. This deliberately changes the
  reference Russian text («и нагрузка шаг за шагом станет твоей»).

### Verification

- Reference: 4,150 property checks, 0 failures (was 3,223).
- Golden fixtures regenerated with two new scenarios (calibration, comeback).
  Every changed step in the existing fixtures was classified against the rules
  for what this change is allowed to move; nothing fell outside them.
- Core suite 38 → 56 tests, app suite gains the comeback and migration cases.

## 1.4.0

First experience and milestones. The engine is untouched in this release — the
adaptive core is identical to 1.3.0, bit for bit.

### First run

- **Onboarding.** Three cards on a fresh install, explaining the one thing the
  UI cannot show by itself: the plan moves because you answer, and the first
  workout is deliberately easy because it is a starting point, not a test.
  Skipping counts as seen.
- **"How it works"** — the first row in Settings. Six sections covering the
  level, what a rating does, deload, rotation, skips, and why there are no
  questionnaires. Every number in it matches the engine rather than rounding
  for the story.

### Milestones

- A workout that unlocks a harder variation, crosses into another set band, or
  lands on the 10th, 25th or every 50th session ends on one screen listing what
  it earned. Tier-ups above the jubilee, no confetti, no badges.
- Only upward movement is announced. A deload or a shortfall is never
  commented on.
- **Share card** — rendered on device at 1080×1350 and passed to the system
  share sheet: a milestone line, a date, the wordmark. No body metrics, no
  streak, no network. Also available from Progress as a totals card.

### Asking for a review

- One automatic trigger: closing a milestone screen, and only after five
  workouts, never following a session rated harder than planned, and at most
  once every sixty days. Settings gains an About section so a review can always
  be left on purpose instead.

### Accessibility

- Every screen honours Dynamic Type. The few display numbers that are already
  enormous by design scale to a cap rather than pushing the screen out from
  under themselves; the rest timer's ring grows with the countdown it frames.
- VoiceOver labels on the controls that were reading as bare symbol names, and
  decorative icons hidden from the rotor.

### Fixes

- A rest day showed a live plan with a Start button on Today while the widget
  said "Rest day" and the next-workout date skipped the day — three answers to
  one question. Today now agrees with both, and keeps a "Train anyway" escape
  hatch, because a rest day is the user's own setting.
- Rest days in the calendar carried no mark and read like days outside the
  month. They now have a soft fill and a legend entry.

## 1.3.0

Two development waves ship together: the engine work originally staged as 1.2.0 (which was never released) and the progress-and-integrations wave.

### Engine — v2.2

- **Level ceiling raised from 31 to 47.** Above tier 4 progression continues by adding a set instead of a variation: 3 sets up to level 31, 4 sets for 32–39, 5 sets for 40–47. The top of the system is now 5 × 15 rather than a dead end at 4 × 15.
- **Pull-up bar module.** An optional vertical-pull branch — bar hang, negative pull-up, partial pull-up, pull-up — with its own independent level. With the bar enabled, every other session swaps the floor pull for a vertical one. Turning it off freezes the branch without losing progress.
- Library grew from 36 to 40 exercises (10 patterns × 4 tiers), each with technique steps and common mistakes in both languages.
- Reference verification: 3,223 property checks, 0 failures. Golden fixtures: 7 scenarios, 113 steps, reproduced bit-for-bit by the Swift port.

### Progress and history

- **Level chart** across sessions (Swift Charts), with per-pattern projections and an "All" total view.
- **Weekly summary** — workouts and level delta for the current ISO week. A deload week honestly shows a minus.
- Per-pattern level bars, including the vertical-pull branch once it exists.

### System integrations

- **Apple Health** — write-only export of completed workouts as functional strength training. Nothing is ever read. Existing history can be backfilled; a high-water mark makes export idempotent, so a repeated backfill never creates duplicates.
- **Live Activity** — the rest countdown on the lock screen and in the Dynamic Island, ending automatically when the workout does.
- **Home-screen widget** — today's status at a glance (workout / done / rest day), flipping at midnight without the app running.

### Fixes

- Health export no longer advances its high-water mark on a failed save, so a failed workout stays retriable instead of being silently lost.
- Backfill stops at the first failure rather than marking the whole tail exported.
- Live Activity no longer races itself when a second workout starts right after the first.
- Progress chips and chart outlines use `strokeBorder`, so the outline is no longer clipped.
- The backup snapshot rebuilds when settings change while the sheet is open.
- Technique is reachable from the rest screen, not only from the plan.
- Russian strings normalized to use `е` rather than `ё` throughout.
- The widget extension's bundle version was stuck at 1.1 (build 2) while the app moved on; all four targets now ship the same version, which App Store validation requires.

### Documentation

- README rewritten to match the shipped product — it had been describing v1.0 (level range 0–31, 36 exercises, 4 golden scenarios). Two claims that were never true were also removed: the exercise library is hand-written rather than generated from a bilingual table, and the calendar does not mark rest days.
- TESTPLAN.md added: a manual QA checklist for what automation cannot cover — system integrations, wall-clock behavior, both locales — plus an issue registry.

## 1.1.0

- Honest skips (engine v2.1.1): a skipped exercise no longer inherits the session rating — its level and streak are left untouched.
- Hold timer for static exercises, with a 3-2-1 countdown; an early stop records the actual.
- Warm-up block; the screen no longer sleeps mid-workout.
- Settings: rest days, sounds and haptics, a reminder on training days.
- Local reminders, backup export/import, and a `levelsAfter` snapshot stored with each record.

## 1.0.1

- Privacy page restyled to match the landing page.

## 1.0.0

First release. Engine v2.1 (levels 0–31, 4 tiers, pull in every session), seven screens, local persistence.
