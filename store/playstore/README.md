# store/playstore

Google Play materials for the Android app — the sibling of `store/appstore/`.

```text
playstore/
├── listing/<locale>/     title.txt (≤ 30), short_description.txt (≤ 80),
│                         full_description.txt (≤ 4000), whats_new.txt (≤ 500) —
│                         Play's limits, not the App Store's, so a text that
│                         fits one storefront may not fit the other. One file
│                         per field, pasted into Play Console as it is (the
│                         single trailing newline is the editor's, not Play's)
├── graphics/             icon-512.png, feature-graphic/<locale>.png (1024 × 500)
├── screenshots/<locale>/ NN-<slot>.png, phone, 1440 × 2560 (9:16), light
├── tools/                check_listing.py, captions.py, capture.sh,
│                         compose_play.py, graphics.py
└── release_texts_*.md    the release's copy for both storefronts — local only,
                          the root .gitignore pattern already covers it here
```

Locales are Play's codes — `en-US`, `ru-RU`, `es-ES`, `pt-BR`, `de-DE`,
`fr-FR`, `it-IT` — for the same seven languages the app ships. Terminology
follows `instructions/GLOSSARY.md`, and the translation rules
`scripts/check_release_texts.py` enforces on the App Store package apply here
unchanged: the Russian `е`, the French non-breaking spaces, the German dash.
`check_listing.py` adds the informal address from
`scripts/check_translation_rules.py`.

## The texts

The listing was adapted from the shipped App Store texts of 2.5.0, and every
claim in it must be true **on Android** — the App Store copy promised a Live
Activity, Apple Health, iPhone, iOS 17 and an App Privacy label, none of which
the Android app has. What replaced them, and the evidence:

| App Store says | Play says | Android source |
|---|---|---|
| a Live Activity on the lock screen | a notification counts the rest and a hold down | `ongoing/OngoingNotification.kt` (chronometer countdown) |
| widgets in every size | one home-screen widget: the day, then the week, then the plan as it grows | `widgets/TodayStatusWidget.kt` (three layouts by size) |
| workouts saved to Apple Health | saved to Health Connect if turned on, with an energy estimate once the weight is known | `health/HealthExporter.kt`, `HealthConnectWriter.kt` |
| no network requests at all | no internet permission | `AndroidManifest.xml` (none declared; `HealthPermissionsTest`) |
| the file goes only where you send it | …and into the phone's own backup, if that is on | `android:allowBackup="true"` |
| free, for iPhone, iOS 17+ | free, no in-app purchases, Android 10 or newer | `minSdk = 29` |

Play's metadata policy shaped the rest: section headings are no longer in
capitals, the emphasis capitals ("in ONE set") are gone, and the title and
short description carry no price, ranking or call to action. The density
clause ("no step up is more than half again as hard…") was cut to fit 4000 in
every locale: its translations had drifted apart, and it was the one claim the
listing could lose without losing a feature.

## The frames

Eight slots, Play's maximum, in the order and with the captions of the iOS set
where a slot has an iOS twin; which slots and why the others stay out is
written in `tools/captions.py`. Three steps:

1. **Capture** on an emulator, never a phone:
   `ANDROID_SERIAL=emulator-5556 RAW_DIR=/tmp/play-raw store/playstore/tools/capture.sh`.
   It sets demo mode on the status bar, runs `ScreenshotWalk` (the workout on
   the Session2 seed, the tabs on the History seed) per locale and
   `WidgetScreenshots` in all seven languages, and pulls the raws.
2. **Compose**: `RAW_DIR=/tmp/play-raw/screens python3 store/playstore/tools/compose_play.py`
   (needs Pillow and macOS's Helvetica). It refuses a clipped caption and fails
   on a missing raw instead of keeping last time's frame.
3. **Look** at every locale before uploading — nothing downstream reads pixels.
   The capture names files by the language it SET; a language the app did not
   take would still be filed under it.

## The graphics

`python3 store/playstore/tools/graphics.py` draws the icon and the feature
graphics from the geometry of `store/appstore/icons/final_light.svg`. The icon
is full-square, as Play wants (Play cuts the corners). The feature graphic
carries the word-mark and the App Store subtitle of its locale, so it is one
file per locale.

## The check

`python3 store/playstore/tools/check_listing.py` — limits, coverage, the
translation rules, another platform's words, Play's promotional words, emoji,
capitals, a field left in English, and the same rules over the captions. Each
rule is proved able to fail before it is believed. Run it before anything is
pasted into Play Console; CI does not run it.
