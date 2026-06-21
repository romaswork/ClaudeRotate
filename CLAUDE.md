# ClaudeRotate

## Что это
Менубарное (без иконки в Dock) приложение для macOS на SwiftUI. Назначение —
ротация учётных данных Claude API в JSON-файле конфигурации (формат Claude Code
`settings.json`) по таймеру. Пользователь ведёт список именованных ключей, может
включать/выключать каждый, а приложение по очереди подставляет включённые ключи
в целевой файл каждые N минут. Все данные хранятся локально.

## Поведение ротации
В целевом JSON-файле меняются ТОЛЬКО три поля, остальное содержимое сохраняется:
- `apiKeyHelper` → `echo '<ANTHROPIC_API_KEY>'` (формируется автоматически из ключа)
- `env.ANTHROPIC_API_KEY` → значение ключа
- `env.ANTHROPIC_BASE_URL` → базовый URL ключа

Файл читается через `JSONSerialization`, изменяются три поля, записывается обратно
с `[.prettyPrinted, .sortedKeys]`; экранирование слешей убирается. Все прочие ключи
и значения сохраняются (порядок ключей может нормализоваться).

## Ключевые решения
- **Песочница (App Sandbox) отключена** (`ENABLE_APP_SANDBOX = NO`) — приложение
  читает/пишет файл по произвольному пути, указанному вручную в настройках.
- **Только меню-бар** (`LSUIElement = YES`) — иконки в Dock нет.
- `apiKeyHelper` формируется автоматически из API-ключа.

## Структура проекта
- `ClaudeRotate/APIKey.swift` — модель ключа (id, name, apiKey, baseURL, enabled).
- `ClaudeRotate/AppStore.swift` — единый источник данных (`ObservableObject`),
  хранение конфигурации в `~/Library/Application Support/ClaudeRotate/config.json`, CRUD.
- `ClaudeRotate/RotationEngine.swift` — `writeKey(toPath:)` (запись в целевой файл)
  и `RotationManager` (таймер, `start`/`stop`/`rotateNow`).
- `ClaudeRotate/ClaudeRotateApp.swift` — точка входа: `MenuBarExtra` (меню в трее)
  и окно настроек; автостарт ротации при запуске.
- `ClaudeRotate/RootView.swift` — UI: вкладка «Keys» (CRUD/включение/порядок) и
  вкладка «Settings» (путь к файлу, интервал, автостарт, статус).
- `ClaudeRotate.xcodeproj/project.pbxproj` — настройки сборки.

## Сборка
xcodebuild требует полный Xcode (не Command Line Tools), поэтому указываем
`DEVELOPER_DIR`:

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project ClaudeRotate.xcodeproj -scheme ClaudeRotate \
  -configuration Debug -destination 'platform=macOS' build
```

Собранное приложение: `~/Library/Developer/Xcode/DerivedData/ClaudeRotate-*/Build/Products/Debug/ClaudeRotate.app`.

## Технические детали
- macOS deployment target: 26.5, Swift 5.0, изоляция по умолчанию — MainActor.
- Bundle ID: `xyz.ClaudeRotate`.
- `RotationManager` объявляет `nonisolated let objectWillChange`, т.к. не имеет
  собственных `@Published`-свойств (UI читает состояние из `AppStore`).
- Язык общения с пользователем в этом проекте — русский.

## Поддержание этого файла в актуальном состоянии
ВАЖНО: при любых значимых изменениях в проекте необходимо сразу обновлять этот
файл (`CLAUDE.md`), чтобы он оставался точным описанием проекта. Обновляй его, когда:
- добавляются/удаляются/переименовываются файлы или модули;
- меняется поведение ротации или формат целевого JSON;
- меняются ключевые архитектурные решения (песочница, меню-бар, хранение данных);
- меняются команды или процесс сборки/запуска;
- появляются новые настройки, экраны или возможности.

Обновление этого файла — часть задачи изменения, а не отдельный шаг: правишь код —
синхронно правишь соответствующий раздел здесь.
