# store/playstore

Google Play materials for the Android app — the sibling of `store/appstore/`,
empty until there is an Android build to list. Laid out now so the release
regulation and the translator agents have a fixed place to write to.

```text
playstore/
├── listing/<locale>/     title (≤ 30), short description (≤ 80),
│                         full description (≤ 4000), what's new (≤ 500) —
│                         Play's limits, not the App Store's, so a text that
│                         fits one storefront may not fit the other
├── graphics/             icon 512×512, feature graphic 1024×500
├── screenshots/<locale>/ phone frames, captured from the emulator by the
│                         same accessibility identifiers the iOS capture uses
├── tools/                capture and compose scripts, when they exist
└── release_texts_*.md    the release's copy for both storefronts — local only,
                          the root .gitignore pattern already covers it here
```

Locales are Play's codes — `en-US`, `ru-RU`, `es-ES`, `pt-BR`, `de-DE`,
`fr-FR`, `it-IT` — for the same seven languages the app ships. Terminology
follows `instructions/GLOSSARY.md`, and the translation rules
`scripts/check_release_texts.py` enforces on the App Store package apply here
unchanged: the Russian `е`, the French non-breaking spaces, the German dash,
the informal address.
