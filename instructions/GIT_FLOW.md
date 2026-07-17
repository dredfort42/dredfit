# Git flow проекта Dredfit

## Ветки

| Ветка | Назначение |
|---|---|
| `develop` | основная ветка разработки (default). Вся текущая работа попадает сюда |
| `feature/<имя>` | опционально: крупная задача; вливается в `develop` через PR |
| `release/X.Y.Z` | подготовка релиза: правки версий, стабилизация. Создаётся от `develop` |
| `hotfix/<имя>` | срочная правка релиза. Создаётся от `main`, вливается в `main` и `develop` |
| `main` | только релизные состояния. Каждый релиз помечается тегом `vX.Y.Z` |

## Цикл релиза

```
develop ──► release/X.Y.Z ──► main ──► тег vX.Y.Z
                │                          │
                └────── обратно в develop ─┘
```

1. `git checkout develop && git checkout -b release/X.Y.Z`
2. В ветке релиза: поднять `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`, добить стабилизацию. Пуш ветки запускает **полный** прогон тестов (включая UI).
3. Влить в `main`: `git checkout main && git merge release/X.Y.Z`
4. Тег: `git tag vX.Y.Z && git push origin main vX.Y.Z` — по тегу CI сам создаст GitHub Release с changelog.
5. Вернуть релизные правки в разработку: `git checkout develop && git merge main && git push`
6. TestFlight: архив и выгрузка — **вручную из Xcode** (Product → Archive) с ветки `main` на теге.

## Что и когда запускает CI

| Workflow | Триггер | Содержимое | Время |
|---|---|---|---|
| **CI** | push/PR в `develop`, `main`, `release/**`, `hotfix/**` | юнит-тесты пакета + приложения (без UI) | ~5–15 мин |
| **Full Tests** | ночью (02:30 UTC) на `develop`; push в `release/**`, `hotfix/**`; вручную (Run workflow) | весь тест-план, включая UI-тесты | ~20–45 мин |
| **Lint** | push/PR туда же | SwiftLint | ~20 с |
| **CodeQL** | push в `develop`/`main` + еженедельно | анализ безопасности Swift | ~15 мин |
| **Release** | тег `v*` | GitHub Release с changelog из коммитов | ~1 мин |

Dependabot еженедельно обновляет версии actions и swift-зависимости PR-ами в `develop`.

## Правила

- В `main` напрямую не коммитим — только merge из `release/**` или `hotfix/**`.
- Тег ставится только на `main`; формат `vX.Y.Z` (совпадает с `MARKETING_VERSION`).
- Красный **CI** — не мержим. Красный **Full Tests** ночью — разобраться до следующего релиза.
- UI-тесты иногда флачат на раннерах GitHub: одиночное падение — перезапустить джобу, повторное — смотреть xcresult-артефакт.
