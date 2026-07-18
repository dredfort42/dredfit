# Git flow проекта Dredfit

## Ветки

| Ветка | Назначение |
|---|---|
| `develop` | основная ветка разработки (default). Вся текущая работа попадает сюда |
| `feature/<имя>` | опционально: крупная задача; вливается в `develop` через PR |
| `release/X.Y.Z` | подготовка релиза: правки версий, стабилизация. Создаётся от `develop` |
| `hotfix/<имя>` | срочная правка релиза. Создаётся от `main`, вливается в `main` и `develop` |
| `main` | только релизные состояния. Каждый релиз помечается тегом `vX.Y.Z` |

## Повседневная работа

Простая правка — прямо в `develop`:

```bash
git checkout develop
git pull --ff-only
# ... правки ...
git add -A
git commit -m "fix: короткое описание сути правки"
git push origin develop
```

Крупная задача — через ветку и PR (чтобы CI прогнался до мержа):

```bash
git checkout develop
git pull --ff-only
git checkout -b feature/rest-day-picker

# ... работа, несколько коммитов ...
git push -u origin feature/rest-day-picker

gh pr create --base develop --title "feat: выбор нескольких дней отдыха" \
  --body "Что сделано и почему."

# следим за проверками PR
gh pr checks --watch

# после зелёных проверок и ревью
gh pr merge --squash --delete-branch
```

## Цикл релиза

```
develop ──► release/X.Y.Z ──► main ──► тег vX.Y.Z
                │                          │
                └────── обратно в develop ─┘
```

**0. Прогнать UI-тесты локально — обязательный шаг перед релизной веткой.**

UI-тесты в CI не гоняются на релизных ветках и релиз не блокируют (см. таблицу ниже). Их ворота — локальная машина, до создания ветки:

```bash
# Симулятор должен быть чистым. Ошибка "Application failed preflight checks"
# (раннер UI-тестов не стартует) бывает по двум причинам: на устройстве уже
# стоит вручную установленное приложение, либо xcodebuild плодит клоны
# симулятора. Erase лечит первую, флаг -parallel-testing-enabled NO — вторую.
xcrun simctl shutdown all
xcrun simctl erase "iPhone 17 Pro"

set -o pipefail
xcodebuild test \
  -project Dredfit.xcodeproj \
  -scheme Dredfit \
  -testPlan Dredfit \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  -parallel-testing-enabled NO \
  -retry-tests-on-failure \
  -test-iterations 3 \
  CODE_SIGNING_ALLOWED=NO
```

`-parallel-testing-enabled NO` **обязателен**: без него xcodebuild плодит клоны симулятора, они не подключаются, и прогон падает не по вине кода.

Проверять именно итог, а не код возврата пайпа: `... | tail` вернёт код `tail`, а не `xcodebuild`, и красный прогон выглядит зелёным. Смотреть на `** TEST SUCCEEDED **` и на строки `Executed N tests, with 0 failures`. Ожидаемо: 38 (ядро) + 27 (приложение, 1 skipped) + 16 (UI) = 81 тест.

Красные UI локально — релиз не собираем, чиним сначала.

**1. Завести ветку релиза от `develop`:**

```bash
git checkout develop
git pull --ff-only
git checkout -b release/1.2.0
git push -u origin release/1.2.0
```

Пуш ветки запускает **CI** (юнит-тесты) и **Lint** — это и есть ворота релиза. Проверить статус:

```bash
gh run list --branch release/1.2.0 --limit 5
gh run watch                     # следить за текущим прогоном в интерактиве
```

**2. В ветке релиза — поднять версии и стабилизировать:**

```bash
# MARKETING_VERSION и CURRENT_PROJECT_VERSION правятся в Xcode
# (Target → General) или прямо в project.pbxproj

git add Dredfit.xcodeproj/project.pbxproj
git commit -m "chore: bump version to 1.2.0 (build 3)"
git push
```

Если во время стабилизации нашёлся баг — чинить прямо в этой ветке:

```bash
git add -A
git commit -m "fix: описание"
git push
```

**3. Влить релиз в `main`:**

```bash
git checkout main
git pull --ff-only
git merge --no-ff release/1.2.0
git push origin main
```

**4. Поставить тег — CI сам создаст GitHub Release с changelog:**

```bash
git tag v1.2.0
git push origin v1.2.0

# проверить, что Release отработал
gh run list --workflow=release.yml --limit 3
gh release view v1.2.0
```

**5. Вернуть релизные правки (версии, фиксы) обратно в `develop`:**

```bash
git checkout develop
git pull --ff-only
git merge --no-ff main
git push origin develop
```

**6. TestFlight — вручную из Xcode**, с `main` на только что поставленном теге:

```bash
git checkout main
git status                       # убедиться, что рабочая копия чистая
# Xcode → Product → Archive → Distribute App → TestFlight
```

**7. Убрать ветку релиза, если она больше не нужна:**

```bash
git push origin --delete release/1.2.0
git branch -d release/1.2.0
```

## Hotfix (срочная правка уже выпущенного релиза)

```bash
git checkout main
git pull --ff-only
git checkout -b hotfix/crash-on-export

# ... правка ...
git add -A
git commit -m "fix: падение при экспорте пустой истории"
git push -u origin hotfix/crash-on-export
```

Пуш запускает **CI** и **Lint**. Хотфикс срочный, поэтому полный локальный прогон UI не обязателен — но если правка задевает экран или поток тренировки, прогнать UI локально по рецепту из шага 0 релизного цикла. После зелёного — вливаем в обе стороны:

```bash
git checkout main
git merge --no-ff hotfix/crash-on-export
git tag v1.2.1
git push origin main v1.2.1

git checkout develop
git merge --no-ff main
git push origin develop

git push origin --delete hotfix/crash-on-export
```

## Что и когда запускает CI

| Workflow | Триггер | Содержимое | Время | Ворота? |
|---|---|---|---|---|
| **CI** | push в `develop`, `main`, `release/**`, `hotfix/**`; PR **в** `develop`/`main` | юнит-тесты пакета + приложения (без UI) | ~5–15 мин | **да** |
| **Lint** | триггеры те же, что у CI | SwiftLint | ~20 с | **да** |
| **UI Tests** | ночью (02:30 UTC) на `develop`; вручную (Run workflow) | только `DredfitUITests` | ~20–45 мин | нет |
| **CodeQL** | push в `develop`/`main` + еженедельно | анализ безопасности Swift | ~15 мин | нет |
| **Release** | тег `v*` | GitHub Release с changelog из коммитов | ~1 мин | — |

Dependabot еженедельно обновляет версии actions и swift-зависимости PR-ами в `develop`.

## Правила

- В `main` напрямую не коммитим — только merge из `release/**` или `hotfix/**`.
- Тег ставится только на `main`; формат `vX.Y.Z` (совпадает с `MARKETING_VERSION`).
- Красный **CI** или **Lint** — не мержим и релиз не собираем.
- **UI Tests в CI релиз не блокируют.** Красный ночной прогон — задача разобраться до следующего релиза, а не повод его останавливать. Решение о выкатке принимается по зелёному **CI** плюс локальному прогону UI (шаг 0 релизного цикла).
- UI-тесты иногда флачат на раннерах GitHub: одиночное падение — перезапустить джобу, повторное — смотреть xcresult-артефакт. Именно из-за этой нестабильности они вынесены из ворот релиза.
- Локальный прогон UI — обязателен перед созданием релизной ветки, с `-parallel-testing-enabled NO` и на чистом симуляторе.
