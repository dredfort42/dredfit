# R8 rules of the app's own. Every library ships its keep rules; these two
# repair rules written before R8's full mode (AGP's default since 8.0), which
# no longer keeps a kept class's no-argument constructor unless asked.
#
# WorkManager 2.7.1 — under Glance's widget sessions — and its Room 2.2.5 keep
# these classes by name only, then create them by reflection. Without the
# constructors the widget never drew: "Failed to create an instance of
# androidx.work.impl.WorkDatabase" (release smoke on the API 37 emulator,
# 11.10.2026), and every session's input merger would fail the same way.
# WorkManager 2.8+ and Room 2.6+ carry these member rules themselves.
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep class * extends androidx.work.InputMerger { <init>(); }
