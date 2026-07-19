# App Store / TestFlight copy — 1.5.1

Prepared 2026-07-19. A hardening release on top of 1.5.0: no new features,
no engine changes — reliability, accessibility and localization. Subtitle,
promotional text, keywords, description and screenshots are unchanged from
[store_copy_1.5.md](store_copy_1.5.md); only What's New and the TestFlight
notes below are specific to 1.5.1.

Character budgets: What's New ≤ 4000.

---

## What's New — 1.5.1

**en**

```
A reliability pass over the whole app. Nothing new to learn — everything you already do just holds up better.

• Your data is safer: a damaged history file is set aside and recovered from, never silently replaced. Every workout now reaches Apple Health even if an earlier export failed mid-way.
• Crossing midnight with the app open no longer freezes Today on yesterday's "completed" screen.
• A workout interrupted by a force-quit no longer leaves a frozen rest timer on the lock screen.
• An accidental "Stop" in the first seconds of a plank cancels the countdown instead of recording a 5-second set. The warm-up now skips ahead correctly after you step away.
• Larger text sizes: the rating and onboarding screens now scroll instead of clipping. Buttons that were hard to see got proper contrast, and VoiceOver now announces which rest days and chart filters are selected.
• History shows exercise names in your current language, and workout history opens correctly after switching languages.
```

**ru**

```
Большая проверка надежности всего приложения. Ничего нового учить не нужно — все привычное просто работает крепче.

• Данные целее: поврежденный файл истории откладывается в сторону и восстанавливается, а не затирается молча. Каждая тренировка теперь доходит до Apple Здоровья, даже если предыдущий экспорт оборвался.
• Полночь с открытым приложением больше не замораживает «Сегодня» на вчерашнем экране «выполнено».
• Тренировка, прерванная закрытием приложения, больше не оставляет застывший таймер отдыха на заблокированном экране.
• Случайный «Стоп» в первые секунды планки отменяет отсчет, а не записывает подход в 5 секунд. Разминка корректно перематывается, если отвлекся.
• Крупный текст: экраны оценки и знакомства теперь прокручиваются, а не обрезаются. Малозаметные кнопки получили нормальный контраст, а VoiceOver называет выбранные дни отдыха и фильтры графика.
• История показывает названия упражнений на текущем языке и корректно открывается после смены языка.
```

---

## TestFlight — What to Test (1.5.1)

**en**

```
This build is a reliability pass — the main question is "does everything still feel solid?"

• Complete a workout in the evening, leave the app open overnight: next morning Today must offer the new day, not yesterday's "completed".
• Force-quit the app mid-rest: the lock-screen timer should dim and disappear on the next launch — no frozen card.
• Start a hold and tap Stop immediately: the countdown must cancel and the set must survive. Stop after ~5 seconds: the held time is recorded.
• If Health export is on: every completed workout should appear in Apple Health, in order, even after toggling Health off and on.
• Turn on the largest text size (Settings → Accessibility): the rating screen after a workout and the three intro cards must scroll, nothing clipped.
• With VoiceOver: rest-day chips in Settings should announce "selected"; calendar days should speak their date and state.
• Switch the device language en↔ru: past workouts in the calendar should show exercise names in the new language.
```

**ru**

```
Эта сборка — про надежность, главный вопрос: «все ли по-прежнему держится крепко?»

• Заверши тренировку вечером и оставь приложение открытым на ночь: утром «Сегодня» должно предложить новый день, а не вчерашнее «выполнено».
• Закрой приложение свайпом во время отдыха: таймер на заблокированном экране должен потускнеть и исчезнуть при следующем запуске — без застывшей карточки.
• Начни удержание и сразу нажми «Стоп»: отсчет должен отмениться, подход — сохраниться. «Стоп» после ~5 секунд — время записывается.
• Если включен экспорт в Здоровье: каждая завершенная тренировка должна появляться в Apple Здоровье по порядку, даже после выключения и включения тумблера.
• Включи самый крупный текст (Настройки → Универсальный доступ): экран оценки после тренировки и три карточки знакомства должны прокручиваться, ничего не обрезано.
• С VoiceOver: чипы дней отдыха в настройках должны объявлять «выбрано»; дни календаря — называть дату и состояние.
• Переключи язык устройства en↔ru: прошлые тренировки в календаре должны показывать названия упражнений на новом языке.
```

---

## Screenshots

The 1.5.0 set (`screenshots/{en,ru}/`, 6.9" 1320×2868) stays current for
1.5.1: the visible changes are limited to contrast on secondary buttons and
the calendar legend swatch, none of which appear in the nine framed screens.
Recapture with `tools/` only if the set is refreshed for other reasons.
