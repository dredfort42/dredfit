#!/usr/bin/env python3
"""Write a seeded dredfit-state.json into the simulator app container.

Usage: seed.py <udid> A|B|C|D
Seed A: counter 11 (Workout 12 next), second variations — Today + workout flow.
Seed B: counter 34, mostly third variations — Progress.
Seed C: seed A with push_h parked on its dose ceiling — the probe (§40.4).
Seed D: counter 14, hinge alone in a four-set band — the skip inside a workout.
Dates encode as seconds since the reference date (Foundation default).

v3.0: the state is a POSITION per movement — variation plus dose — and not a
level, so the seeds carry `vars`/`doses` instead of `levels`. Those two keys are
REQUIRED by the decoder: a file with `levels` is a v2 file, the engine refuses
it and the app starts clean (§40.8), which would have seeded screenshots of a
first workout instead of a trained one. Every dose below sits on its own grid
(reps 4…15 step 1, holds 15…45 step 5) — off-grid values are snapped down by
the sanitizer and the frame would show a number the seed never asked for.

The ordinal sums are the engine's own measure of the seeded positions, `posOrd`
summed over the ten patterns — each one recomputed on the shipped reference for
the seed it belongs to, never carried over from another seed. They matter
because the Progress screen shows the same number: a hand-picked total would
contradict the bars drawn next to it.

WHY THE COUNTER IS PART OF A SEED AND NOT A CONVENIENCE. Which six movements a
session is made of, and in what order, is a pure function of `counter`
(rotationStep 3 over the eight rotating patterns, then sorted by
`Pattern.ordered`). Both new seeds need a NAMED movement to be the FIRST
exercise, because the capture route walks one exercise and stops:
  counter 11 → push_h, hinge, pull, push_v, lunge, core_anti_ext  (A, C)
  counter 14 → hinge, pull, push_v, lunge, core_anti_ext, core_rot  (D)
Change a counter and the frame changes movement without a word of warning.
"""
import json, subprocess, sys, datetime, os

udid, seed = sys.argv[1], sys.argv[2]
REF = datetime.datetime(2001, 1, 1, tzinfo=datetime.timezone.utc)
now = datetime.datetime.now(datetime.timezone.utc)

PATTERNS = ["squat", "push_h", "hinge", "pull", "push_v",
            "lunge", "core_anti_ext", "core_rot", "calf", "pull_bar"]

SETS_BASE = 3


def pattern_array(d, default=0):
    """[Pattern: Int] on the wire: an UNKEYED alternating array. Pattern is a
    plain String-raw enum on purpose (never CodingKeyRepresentable), and that
    is what fixes this shape — see CLAUDE.md."""
    out = []
    for p in PATTERNS:
        out += [p, d.get(p, default)]
    return out


def shown_array(positions):
    """[Pattern: [Int: Int]] — the outer map is the same alternating array, the
    inner one is a keyed object, because Swift special-cases integer keys. The
    journal of what was actually shown is what a descent lands on (§40.6), so a
    seed without it would let one "hard" throw the frame back to the floor.

    It is also half of the probe gate (§41.4): the probe asks that the CEILING
    was actually shown, not merely that the plan climbed to it — which is why
    seed C moves the dose and the journal entry together."""
    out = []
    for p in PATTERNS:
        var, dose = positions[p]
        out += [p, {str(var): dose}]
    return out


def records(count, totals, positions, sets):
    recs = []
    after = {p: {"variation": v, "sets": sets.get(p, SETS_BASE), "dose": d}
             for p, (v, d) in positions.items()}
    flat = []
    for p in PATTERNS:
        flat += [p, after[p]]
    for i in range(count):
        # every other day, last one yesterday evening
        date = now - datetime.timedelta(days=2 * (count - 1 - i) + 1)
        recs.append({
            "sessionNumber": i + 1,
            "date": (date - REF).total_seconds(),
            "result": "plan",
            # The scale has no inverse (§40.2), so the record keeps the position
            # itself; the scalar beside it is only the sum of the ordinals.
            "totalProgressAfter": totals[i],
            "positionsAfter": flat,
        })
    return recs


POS_A = {"squat": (2, 9), "push_h": (2, 8), "hinge": (2, 7),
         "pull": (2, 8), "push_v": (2, 6), "lunge": (2, 7),
         "core_anti_ext": (2, 30), "core_rot": (2, 25),
         "calf": (2, 10), "pull_bar": (1, 20)}

POS_B = {"squat": (3, 11), "push_h": (3, 10), "hinge": (3, 9),
         "pull": (3, 12), "push_v": (2, 12), "lunge": (2, 13),
         "core_anti_ext": (3, 35), "core_rot": (3, 30),
         "calf": (3, 12), "pull_bar": (1, 30)}

# Seed C — the probe. §40.4 asks for four things at once, and all four are
# stated here rather than hoped for: the dose is ON the ceiling of the reps
# grid (15), the journal says that ceiling was actually shown (§41.4), the
# variation is not the top one (push_h has six, this is the second), and
# `lastHard` is absent from the file, so no pattern is carrying a "hard".
# push_h ALONE is parked — every other dose stays below its ceiling, so the
# session contains exactly one probe and it is the first exercise.
# The probe it opens is variation 3, "Push-up": REPS. A hold probe would turn
# the frame's big number into a countdown the moment the timer runs.
POS_C = dict(POS_A, push_h=(2, 15))

# Seed D — the skip inside a workout. A four-set band lives ONLY above the top
# variation of a ladder (§40.5), so "the movement on screen carries four sets"
# is a position, not a number that can be set on its own: hinge goes to its
# seventh and last rung ("Assisted Nordic curl", reps, not per side) with the
# band-entry dose of 11.
#
# hinge, and not the push side. push_h and push_v are capped by the pull slot's
# set count (`min(ownSets, pullSets)`), so a four-set band on either of them is
# shown as three and the frame would be a lie the driver could not see.
#
# ONE movement in the band, not ten. `--uitest-long-session` plants every
# ladder at four sets and produces a 67-minute session; this file's listing
# promises 30.5 min for a full one. With the band on hinge alone the header on
# the frame reads "≈ 30 min left" — verified against Engine.estimatedMin
# through SessionAhead's own arithmetic, not eyeballed.
POS_D = dict(POS_A, hinge=(7, 11))

# counter, positions, per-pattern sets above the base, ordinal total, ramp
SEEDS = {
    "A": (11, POS_A, {}, 375, 1.1),
    "B": (34, POS_B, {}, 667, 1.4),
    "C": (11, POS_C, {}, 396, 1.1),
    "D": (14, POS_D, {"hinge": 4}, 570, 1.1),
}

if seed not in SEEDS:
    sys.exit(f"unknown seed {seed!r}: expected one of {', '.join(sorted(SEEDS))}")

counter, positions, sets, total, ramp = SEEDS[seed]
totals = [round(10 + (total - 10) * (i / (counter - 1)) ** ramp) for i in range(counter)]
totals[-1] = total

data = {
    "engineState": {
        "counter": counter,
        "vars": pattern_array({p: v for p, (v, _) in positions.items()}, 1),
        "doses": pattern_array({p: d for p, (_, d) in positions.items()}, 4),
        # Clamped by the decoder to [3, setsCeil(p, v)], and setsCeil is 3
        # anywhere but the top variation — a band asked for below the top is
        # dropped in silence, which is the trap seed D is written around.
        "sets": pattern_array(sets, SETS_BASE),
        "shown": shown_array(positions),
        "failStreak": pattern_array({}),
    },
    "records": records(counter, totals, positions, sets),
    "settings": {
        "restWeekdays": [],
        "soundsEnabled": True,
        "reminderEnabled": False,
        "reminderHour": 9,
        "reminderMinute": 0,
        "onboardingCompleted": True,
    },
}

cont = subprocess.check_output(
    ["xcrun", "simctl", "get_app_container", udid, "com.dredfit.Dredfit", "data"],
    text=True).strip()
target = os.path.join(cont, "Library", "Application Support", "dredfit-state.json")
os.makedirs(os.path.dirname(target), exist_ok=True)
with open(target, "w") as f:
    json.dump(data, f)
print("seeded", seed, "->", target, f"(counter {counter}, total {total})")
