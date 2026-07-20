#!/usr/bin/env python3
"""Write a seeded dredfit-state.json into the simulator app container.

Usage: seed.py <udid> A|B
Seed A: counter 11 (Workout 12 next), varied tier-2 levels — Today + workout flow.
Seed B: counter 34, levels 20/18/20/25/15/17/14/13/16 (sum 158) — Progress.
Dates encode as seconds since the reference date (Foundation default).
"""
import json, subprocess, sys, datetime, os

udid, seed = sys.argv[1], sys.argv[2]
REF = datetime.datetime(2001, 1, 1, tzinfo=datetime.timezone.utc)
now = datetime.datetime.now(datetime.timezone.utc)

PATTERNS = ["squat", "push_h", "hinge", "pull", "push_v",
            "lunge", "core_anti_ext", "core_rot", "calf", "pull_bar"]

def levels_array(d):
    out = []
    for p in PATTERNS:
        out += [p, d.get(p, 0)]
    return out

def records(count, totals):
    recs = []
    for i in range(count):
        # every other day, last one yesterday evening
        date = now - datetime.timedelta(days=2 * (count - 1 - i) + 1)
        recs.append({
            "sessionNumber": i + 1,
            "date": (date - REF).total_seconds(),
            "result": "plan",
            "totalLevelAfter": totals[i],
        })
    return recs

if seed == "A":
    levels = {"squat": 18, "push_h": 13, "hinge": 12, "pull": 14, "push_v": 10,
              "lunge": 11, "core_anti_ext": 13, "core_rot": 8, "calf": 12}
    total = sum(levels.values())
    counter = 11
    totals = [round(9 + (total - 9) * (i / (counter - 1)) ** 1.1) for i in range(counter)]
    totals[-1] = total
else:
    levels = {"squat": 20, "push_h": 18, "hinge": 20, "pull": 25, "push_v": 15,
              "lunge": 17, "core_anti_ext": 14, "core_rot": 13, "calf": 16}
    total = sum(levels.values())  # 158
    counter = 34
    totals = [round(9 + (total - 9) * (i / (counter - 1)) ** 1.4) for i in range(counter)]
    totals[-1] = total

data = {
    "engineState": {
        "counter": counter,
        "levels": levels_array(levels),
        "failStreak": levels_array({}),
    },
    "records": records(counter, totals),
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
