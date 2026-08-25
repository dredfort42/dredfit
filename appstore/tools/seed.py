#!/usr/bin/env python3
"""Write a seeded dredfit-state.json into the simulator app container.

Usage: seed.py <udid> A|B
Seed A: counter 11 (Workout 12 next), second variations — Today + workout flow.
Seed B: counter 34, mostly third variations — Progress.
Dates encode as seconds since the reference date (Foundation default).

v3.0: the state is a POSITION per movement — variation plus dose — and not a
level, so the seeds carry `vars`/`doses` instead of `levels`. Those two keys are
REQUIRED by the decoder: a file with `levels` is a v2 file, the engine refuses
it and the app starts clean (§40.8), which would have seeded screenshots of a
first workout instead of a trained one. Every dose below sits on its own grid
(reps 4…15 step 1, holds 15…45 step 5) — off-grid values are snapped down by
the sanitizer and the frame would show a number the seed never asked for.

The two ordinal sums (375 and 667) are the engine's own measure of the seeded
positions, `posOrd` summed over the ten patterns — recomputed on the shipped
reference, not carried over from the level scale. They matter because the
Progress screen shows the same number: a hand-picked total would contradict the
bars drawn next to it.
"""
import json, subprocess, sys, datetime, os

udid, seed = sys.argv[1], sys.argv[2]
REF = datetime.datetime(2001, 1, 1, tzinfo=datetime.timezone.utc)
now = datetime.datetime.now(datetime.timezone.utc)

PATTERNS = ["squat", "push_h", "hinge", "pull", "push_v",
            "lunge", "core_anti_ext", "core_rot", "calf", "pull_bar"]


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
    seed without it would let one "hard" throw the frame back to the floor."""
    out = []
    for p in PATTERNS:
        var, dose = positions[p]
        out += [p, {str(var): dose}]
    return out


def records(count, totals, positions):
    recs = []
    after = {p: {"variation": v, "sets": 3, "dose": d}
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


if seed == "A":
    positions = {"squat": (2, 9), "push_h": (2, 8), "hinge": (2, 7),
                 "pull": (2, 8), "push_v": (2, 6), "lunge": (2, 7),
                 "core_anti_ext": (2, 30), "core_rot": (2, 25),
                 "calf": (2, 10), "pull_bar": (1, 20)}
    total = 375
    counter = 11
    totals = [round(10 + (total - 10) * (i / (counter - 1)) ** 1.1) for i in range(counter)]
    totals[-1] = total
else:
    positions = {"squat": (3, 11), "push_h": (3, 10), "hinge": (3, 9),
                 "pull": (3, 12), "push_v": (2, 12), "lunge": (2, 13),
                 "core_anti_ext": (3, 35), "core_rot": (3, 30),
                 "calf": (3, 12), "pull_bar": (1, 30)}
    total = 667
    counter = 34
    totals = [round(10 + (total - 10) * (i / (counter - 1)) ** 1.4) for i in range(counter)]
    totals[-1] = total

data = {
    "engineState": {
        "counter": counter,
        "vars": pattern_array({p: v for p, (v, _) in positions.items()}, 1),
        "doses": pattern_array({p: d for p, (_, d) in positions.items()}, 4),
        "shown": shown_array(positions),
        "failStreak": pattern_array({}),
    },
    "records": records(counter, totals, positions),
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
