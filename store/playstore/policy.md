# Google Play — policy declarations (draft)

The answers the Play Console's **Policy > App content** pages ask for, drafted
for the Android app's first release (2.5.0, phones only, internal testing
first). Nothing here is submitted: the owner pastes it into the Console.
Every answer names the code or the Google page it rests on, so a later change
to either shows which answer it moves.

## Сводка для владельца (ru)

- **Политика конфиденциальности.** На dredfit.com/privacy.html (и в шести
  переводах) теперь есть раздел «Health Connect (Android)» с якорем
  `#health-connect`, плюс Android в разделах о резервном копировании,
  уведомлениях, третьих сторонах и удалении данных. Дата — 11 октября 2026.
  Сайт отдает GitHub Pages из `docs/` ветки main: пока изменения не попали в
  main, по ссылке из Play Console и с экрана разрешений Health Connect
  открывается старая политика, где об Android нет ни слова.
- **Data safety.** Рекомендация: «данные не собираются и не передаются».
  Само приложение ничего не передает (разрешения INTERNET нет). Два места,
  где решение за владельцем: карточка отзыва Google Play и автоматическое
  резервное копирование Android, которое увозит файл состояния в аккаунт
  Google (ниже, раздел 2).
- **Health Connect.** Пять разрешений, для каждого готов текст обоснования
  (раздел 3). Экран обоснования — HealthPrivacyActivity: он открывает
  политику в браузере, а не показывает ее внутри приложения. Это риск на
  проверке (раздел 3.3).
- **Foreground service `health`.** Описание, последствия отсрочки и
  прерывания и сценарий видео — раздел 4. Видео Google требует для каждого
  типа службы.
- **Остальное.** Рейтинг IARC ожидается самый низкий (раздел 6). Целевая аудитория —
  предлагается 18+ (решение владельца). Рекламы нет, входа нет, рекламный
  идентификатор не используется.

## Sources

Read on 11.10.2026. Google moves these pages; re-read before submitting.

- Play Console Help, [Android Health Permissions: Guidance and FAQs](https://support.google.com/googleplay/android-developer/answer/12991134)
  — approved use cases, "a clear and detailed justification" per permission,
  and the policy's required content: what health data is accessed, how it is
  used, stored and shared, retention and deletion, security.
- Play Policy Center, [Permissions and APIs that access sensitive information](https://support.google.com/googleplay/android-developer/answer/9888170),
  section "Health Connect by Android Permissions" — Limited Use, Minimum
  Scope, and "Transparent and Accurate Notice and Control" (identify the app,
  the data types and the feature each serves, every use and sharing, how to
  manage and delete data, how data is handled securely).
- Android Developers, [Declare Health Connect data type access](https://developer.android.com/health-and-fitness/guides/health-connect/publish/declare-access)
  — the **Health apps** form on the App content page: features first, then an
  explanation per data type; the Play listing's policy "must be the same
  privacy policy that is displayed to users when they click the privacy
  policy link in Health Connect".
- Android Developers, [Get started with Health Connect](https://developer.android.com/health-and-fitness/health-connect/get-started)
  — the rationale activity (`ACTION_SHOW_PERMISSIONS_RATIONALE`, and the
  `VIEW_PERMISSION_USAGE` alias from Android 14), which "must display the same
  privacy policy you provide for your app in the Google Play Console".
- Play Console Help, [Provide information for Google Play's Data safety section](https://support.google.com/googleplay/android-developer/answer/10787469)
  — "collect" means transmitting data off the device from your app; data
  processed only on the device is not disclosed; data sent off the device by
  SDKs in the app counts as the app's.
- Android Developers, [In-app reviews](https://developer.android.com/guide/playcore/in-app-review),
  section "Data Safety" — what the Play Store itself does with a review.
- Play Console Help, [Understanding foreground service and full-screen intent requirements](https://support.google.com/googleplay/android-developer/answer/13392821)
  — per type: a description, the impact if deferred or interrupted, a video
  link, a use case.
- Android Developers, [Back up user data with Auto Backup](https://developer.android.com/identity/data/autobackup)
  — where Android's backup goes and how it is encrypted.

## 1. What the answers rest on

The merged release manifest
(`./gradlew :app:processReleaseMainManifest`, then
`app/build/intermediates/merged_manifest/release/processReleaseMainManifest/AndroidManifest.xml`,
develop cea8648) declares exactly these permissions:

| Permission | Kind | Why |
| --- | --- | --- |
| `VIBRATE` | normal | the haptic half of every countdown signal |
| `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_HEALTH` | normal | the workout's ongoing notification (section 4) |
| `HIGH_SAMPLING_RATE_SENSORS` | normal | only the `health` service type's prerequisite; no sensor is read (section 5) |
| `POST_NOTIFICATIONS` | runtime, Android 13+ | the ongoing notification and the training reminder |
| `WAKE_LOCK` | normal | the CPU kept up while a countdown runs with the screen off |
| `RECEIVE_BOOT_COMPLETED` | normal | rebuilds the reminder's alarms after a reboot |
| `SCHEDULE_EXACT_ALARM` | special access ("Alarms & reminders"), granted by the person | the training reminder on its set minute instead of up to an hour late |
| `health.WRITE_EXERCISE`, `health.WRITE_ACTIVE_CALORIES_BURNED`, `health.READ_WEIGHT`, `health.READ_BASAL_METABOLIC_RATE`, `health.READ_EXERCISE` | Health Connect | section 3 |
| `app.dredfit.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` | app-defined | added by AndroidX core for its own receivers |

Not declared: `INTERNET`, `ACCESS_NETWORK_STATE` (WorkManager's, removed in
`AndroidManifest.xml`), `AD_ID`, any location, `USE_EXACT_ALARM`, full-screen-intent,
media or `QUERY_ALL_PACKAGES` permission. The one `<queries>` entry names a
single package, `com.google.android.apps.healthdata` (Health Connect on
Android 10–13).

Libraries (`android/gradle/libs.versions.toml`): AndroidX (Compose,
Activity, Core, Fragment, Glance, WorkManager, Health Connect client 1.1.0,
which brings Guava and a protobuf runtime), JetBrains' kotlinx serialization
and coroutines, and one third-party SDK: `com.google.android.play:review`
2.0.2 (Play In-App Review, which brings play-services-basement and -tasks).

`android:allowBackup="true"` with no backup rules: Android's Auto Backup
copies `filesDir` (the state file — history, settings, body weight — and the
reminder's sound file) and leaves out `noBackupFilesDir` and the cache.

## 2. Data safety

**Privacy policy URL:** `https://dredfit.com/privacy.html`.

**Does your app collect or share any of the required user data types?** —
**No.**

Per data type, for the record:

| Data type (Play's list) | What the app does | Collected? | Shared? |
| --- | --- | --- | --- |
| Health and fitness › Fitness info | the training history, kept in the app's own file; finished workouts and their estimated active calories written to Health Connect, on the device; other apps' exercise sessions read from Health Connect, on the device | No — the app transmits none of it (the ways it leaves the app are below) | No |
| Health and fitness › Health info | weight and basal metabolic rate read from Health Connect, on the device; the weight kept in the app's own file | No — as above | No |
| Files and docs | a backup file the user picks is written (export) or read (import) on the device | No — on the device only | No |
| App info and performance | the app has no crash reporter and no analytics | No | No |
| Everything else (location, personal info, financial, messages, photos, audio, calendar, contacts, web browsing, app activity, device IDs) | none of it is accessed | No | No |

The ways data leaves the app are all user-initiated or the system's own, and
none of them reaches the developer:

- **Backup export** — the system's "save to" picker (SAF `CreateDocument`),
  to a place the user picks. A user-initiated transfer to a destination the
  user chooses; the app transmits nothing.
- **Share card** — the system share sheet (`ACTION_SEND`), to an app the user
  picks.
- **Health Connect** — on-device IPC to the Health Connect service; Google
  describes Health Connect as a database stored on the device.

Two judgment calls for the owner:

1. **Play In-App Review.** The library lets the app ask the Play Store to
   show its review card; the Play Store app draws it and sends the review,
   and the API tells the app nothing back (not even whether the card
   appeared). Google's "Data Safety" note for the library lists
   "User-entered data (rating and free-text review)", used "to leave a review
   on the Play Store", and adds that the Play Store "runs its own processes,
   which include handling data as governed by the Google Play Terms of
   Service" — while also saying the developer alone decides how to answer.
   **Recommended: not declared**, because the data never passes through the
   app: it is the Play Store app that collects it, under Play's terms, and
   the developer receives nothing the app sent. **Conservative alternative:**
   declare *App activity › Other user-generated content* as collected,
   optional, purpose *App functionality*, not shared. Note that in a closed
   test track Google shares the review privately with the developer — the
   privacy policy says so.
2. **Android Auto Backup.** With backup on, the system's backup service
   uploads the state file (history, settings, body weight) to the user's
   own Google account — end-to-end encrypted on Android 9+ when the phone
   has a screen lock; the app sets no rule that would skip the backup
   without one ("The backup data can't be read by the user or other apps on
   the device"). The developer cannot read it. The Data safety help does not
   address Auto Backup either way (searched 11.10.2026). **Recommended: not
   declared** — the upload is the operating system's, to the user's account,
   as iCloud backup is on iOS, where the app ships as "Data Not Collected". The privacy policy describes
   it in full ("Where your data lives"). If the owner prefers not to rely on
   that reading, the alternative is not a declaration but `allowBackup`
   false, which the owner already decided against (09.10.2026).

With "No" to the first question the form asks nothing about encryption in
transit or deletion requests. Optional badges (independent security review):
none.

## 3. Health Connect — the Health apps declaration

### 3.1 Health features

**Health and fitness › Activity and fitness.** Nothing else: the app reads
weight only to scale the calorie estimate and offers no weight management.

### 3.2 Data types — the explanation per permission

The form lists the types in categories; find each of these five there. Each
text below can be pasted as it is.

**Exercise — write (`WRITE_EXERCISE`).**
Dredfit is an adaptive bodyweight-training app. When the user turns on "Save
workouts to Health Connect" in the app's Settings (off by default), every
workout they finish is written to Health Connect as one exercise session
(calisthenics) with its start and end time, an identifier from the app's own
history, and the phone it was recorded on. That is the feature the switch
names: the user's workouts appear in Health Connect and in the other fitness
apps they connect to it. Writing a workout again with the same identifier
replaces it, so nothing is duplicated. Dredfit itself transmits nothing: it
has no internet permission.

**Active calories burned — write (`WRITE_ACTIVE_CALORIES_BURNED`).**
With each written workout, Dredfit writes the active calories of the same
interval: an estimate computed on the phone from the session's exercises and
their durations, the user's body weight and, where recorded, their basal
metabolic rate. The estimate is left out when there is no weight, when
nothing was performed, or when another app already recorded the same session
with its own measured energy. The user can refuse this permission alone (the
workout is then written without calories) or turn on "Leave calories out" in
Settings.

**Weight — read (`READ_WEIGHT`).**
The calorie estimate is proportional to body weight. Dredfit reads the
newest weight in Health Connect and shows it as the body weight in Settings,
where the user can also type one. Without a weight, no calories are written.
The weight and its date are kept in the app's own data on the phone — and so
in a backup the user exports and in Android's backup of the app to the
user's Google account; the developer never receives it.

**Basal metabolic rate — read (`READ_BASAL_METABOLIC_RATE`).**
Active calories are the energy of the workout minus what the body burns at
rest over the same minutes. Dredfit reads the user's recorded basal
metabolic rate to subtract that resting share over exactly the workout's
interval, and only where a rate was actually recorded. Without it, a
standard resting rate is used and the estimate is rougher.

**Exercise — read (`READ_EXERCISE`).**
Before writing calories, Dredfit reads the exercise sessions other apps wrote
around the workout — a watch, for example, that recorded the same session
with its own measured calories — so the same session is not counted twice:
when another app's session overlaps, the workout is written without calories.
It reads only sessions that began from a day before the oldest workout it
has yet to write, and uses only which app wrote each one and its start and
end time.

Not requested: `READ_HEALTH_DATA_HISTORY` (owner decision 11.10.2026),
`READ_HEALTH_DATA_IN_BACKGROUND`, any height, sex, date-of-birth or
heart-rate type.

### 3.3 The privacy-policy link and the rationale screen

`health/HealthPrivacyActivity.kt` handles
`androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE` (Android 10–13) and the
`ViewPermissionUsageActivity` alias for `VIEW_PERMISSION_USAGE` +
`HEALTH_PERMISSIONS` (Android 14+). It opens the policy in the browser —
`https://dredfit.com/privacy.html`, or `/<lang>/privacy.html` for de, es, fr,
it, pt-BR and ru — and finishes. The app has no internet permission, so it
cannot show the page in a WebView.

- **Same policy.** The Console URL must be the page the link shows. The
  localized pages are translations of the same policy; the English page is
  the one to list.
- **Risk.** Google's sample shows the policy inside the app. A reviewer could
  read "the activity must display the privacy policy" as excluding a hand-off
  to the browser. Not seen in a review yet; if it is raised, the fix is an
  in-app copy of the Health Connect section, which the Android README
  currently rejects (a second copy of a legal text drifts).
- **What the page covers**, against Google's list: the app's identity
  ("Who is responsible"), each data type and the feature it serves ("Health
  Connect (Android)"), every use and sharing ("Third parties"), how to
  withdraw access and delete data ("Health Connect (Android)", "Retention and
  your rights"), and security ("Where your data lives": the app transmits
  nothing; app-private storage; the Android backup's end-to-end encryption
  when the phone has a screen lock).

## 4. Foreground service — type `health`

Policy > App content > **Foreground service permissions**. One type is
declared: `health` (`ongoing/OngoingNotification.kt`,
`OngoingWorkoutService`). Google's help maps `health` to fitness-category
apps such as exercise trackers; pick the use case the Console offers for it.

**Description of the feature.**
Dredfit guides a bodyweight workout: timed rests between sets, timed holds
(planks), a guided warm-up and cool-down. While a workout the user started is
in progress, the app shows an ongoing notification — the current exercise or
what the rest leads into, the set, and the countdown — and counts the last
seconds of every rest and hold out with a 3-2-1 of tones and vibrations, so
the user, exercising on the floor away from the phone, knows when the next
set starts. The foreground service of type `health` carries that
notification while the workout is in progress and no longer: it starts when
the user starts the workout and stops when the workout ends (the rating,
"Finish now", closing it), or after three hours with nothing saved. Off
screen, a countdown that reaches zero waits there until the user comes back.
The service type requires a prerequisite permission; the app declares
`HIGH_SAMPLING_RATE_SENSORS` for that reason only and reads no sensor.

**Impact if the task is deferred (does not start immediately).**
The workout's first rest or hold would run without its notification, and on
Android 14 and later the app is frozen seconds after it leaves the screen, so
the 3-2-1 that counts the rest out would not sound: the user would miss the
start of the next set. The service has to start when the user taps Start.

**Impact if the task is interrupted (paused or restarted).**
The countdown tones, the vibration and the lock-screen countdown stop
mid-workout. The workout itself is not lost — it is saved at every
transition and continues when the user comes back to the app — but the user
is no longer told when a rest or a hold ends.

**Video — what to record** (a phone on Android 14 or later, a fresh install;
the system screen recorder with device audio, so the tones are heard; upload
unlisted and paste the link):

1. Open Dredfit and go through the first-launch screens. Today shows the
   plan; tap **Start**.
2. The system asks for notification permission (Android 13+): tap **Allow**.
3. Skip the warm-up on its first screen (during the warm-up the notification
   only says WARM-UP). Do the first set and tap **Done**: a rest begins. Pull
   down the shade: the ongoing Dredfit notification shows "Next up", the
   exercise and the countdown.
4. Press Home (or open another app) during the rest: the 3-2-1 sounds with
   Dredfit off screen; at zero the notification drops its countdown and
   waits.
5. Tap the notification: the workout comes back where it is.
6. Tap the exit button, answer "Leave the workout?" with **Finish now**: the
   notification disappears, and the rating opens.

The lock screen cannot be captured by the screen recorder; if Google asks
for it, film it with a second phone.

## 5. Other permissions

- **`HIGH_SAMPLING_RATE_SENSORS`** — a normal permission, granted at
  install. It is not on the list of permissions with a Play declaration in
  "Permissions and APIs that access sensitive information", and it is not a
  body-sensor permission. No separate declaration was found (searched
  11.10.2026, not confirmed in the Console itself); the foreground-service
  description above says why it is declared. Unverified: whether the Console
  asks about it when the build is uploaded.
- **`RECEIVE_BOOT_COMPLETED`** — normal, no declaration.
- **`SCHEDULE_EXACT_ALARM`** — special access the person grants in the
  phone's "Alarms & reminders" (Android 12–13 grant it at install; from 14
  a fresh install starts without it). It serves a user-facing function: the
  training reminder at the time the person set. Without it the reminder
  still comes, inexact, up to an hour late (`reminders/ExactAlarm.kt`).
  `USE_EXACT_ALARM`, which Play keeps for alarm-clock and calendar apps, is
  not declared. Unverified (12.10.2026): whether the Console asks for an
  exact-alarm declaration when a build with `SCHEDULE_EXACT_ALARM` is
  uploaded.
- **`POST_NOTIFICATIONS`** — a runtime permission with no Play declaration.
  Asked once when the first workout starts, and when the reminder is turned
  on.
- **`VIBRATE`, `WAKE_LOCK`, `FOREGROUND_SERVICE`** — normal, no declaration.
- **Package visibility** — one `<queries>` package
  (`com.google.android.apps.healthdata`), not `QUERY_ALL_PACKAGES`: no
  declaration.

## 6. Content rating (IARC questionnaire)

Category: the one for apps that are not games, social, news or stores (the
Console's wording is "All other app types" or similar — check the list).
Answers:

| Question area | Answer | Why |
| --- | --- | --- |
| Violence, blood, fear | No | exercise instructions only |
| Sexuality, nudity | No | |
| Language (profanity, crude humor) | No | |
| Controlled substances (drugs, alcohol, tobacco) | No | |
| Gambling, simulated gambling | No | |
| Users interact or exchange content (chat, UGC) | No | no account, no in-app messaging; a share card goes through the system share sheet to an app the user picks |
| Shares the user's location | No | no location permission |
| Digital purchases | No | free, no in-app purchases |
| Unrestricted internet / web browser | No | links (the privacy policy, the Play listing) open in the user's own browser |

Expected outcome: the lowest rating in every region. Answer again if the app
ever gains a feature above.

## 7. Target audience and content

- **Age groups: 18 and over** (recommended). The README calls Dredfit "a
  general-fitness tool for healthy adults", and onboarding tells the user to
  talk to a doctor about conditions such as pregnancy and treated blood
  pressure. The privacy policy's "Children" section stays true either way.
  Owner's call; choosing any group under 13 brings in the Families policy.
- **Appeals to children:** No.

## 8. The remaining declarations

- **Ads:** No, the app contains no ads.
- **App access:** All functionality is available without special access — no
  account, no login. Health Connect is optional (Settings › Health Connect);
  on Android 10–13 it needs Google's Health Connect app.
- **Advertising ID:** No (no `AD_ID` permission in the merged manifest).
- **Government app:** No. **Financial features:** none. **News app:** No.
- **Health apps:** section 3.

## 9. Before submitting

1. The privacy page with the Health Connect section must be live on
   dredfit.com (GitHub Pages serves main's `docs/`) — check
   `https://dredfit.com/privacy.html#health-connect` in a browser and from
   Health Connect's permission screen on a phone.
2. Re-read the sources above; Google revises the forms.
3. Upload the foreground-service video.
