# ClaudeRotate

## Что это
Приложение для macOS на SwiftUI с иконкой в Dock и значком в меню-баре. Назначение —
ротация учётных данных Claude API в JSON-файле конфигурации (формат Claude Code
`settings.json`) по таймеру. Пользователь ведёт список именованных ключей, может
включать/выключать каждый, а приложение по очереди подставляет включённые ключи
в целевой файл каждые N минут. Все данные хранятся локально.

## Поведение ротации
В целевом JSON-файле меняются ТОЛЬКО следующие поля, остальное содержимое сохраняется:
- `apiKeyHelper` → `echo '<ANTHROPIC_API_KEY>'` (формируется автоматически из ключа)
- `env.ANTHROPIC_API_KEY` → значение ключа
- `env.ANTHROPIC_BASE_URL` → базовый URL ключа
- `env.HTTPS_PROXY` / `env.HTTP_PROXY` → URL прокси, привязанного к ключу. Если
  прокси не назначен, эти поля **удаляются** из `env` (чтобы убрать прокси,
  оставшийся от предыдущего ключа).

Файл читается через `JSONSerialization`, изменяются перечисленные поля, записывается
обратно с `[.prettyPrinted, .sortedKeys]`; экранирование слешей убирается. Все прочие
ключи и значения сохраняются (порядок ключей может нормализоваться).

Запись **неатомарная** (`Data.write(to:)` без `.atomic`). Причина: под App Sandbox
bookmark даёт доступ только к самому файлу, но не к его каталогу, а `.atomic` создаёт
временный файл рядом и делает rename — для этого нужен доступ к директории. Файл
крошечный, запись занимает доли мс, риск повреждения при сбое минимален.

## Ключевые решения
- **Песочница (App Sandbox) включена** (`ENABLE_APP_SANDBOX = YES`, entitlements в
  `ClaudeRotate/ClaudeRotate.entitlements`) — требование Mac App Store. Доступ к
  целевому файлу — только через **security-scoped bookmark**: пользователь выбирает
  файл вручную (`NSOpenPanel`), приложение хранит bookmark (`AppStore.fileBookmark`,
  app-scope) и перед каждым чтением/записью открывает доступ через
  `AppStore.withTargetAccess`. Произвольный ввод пути текстом больше не поддерживается;
  `filePath` остаётся только для отображения. При обновлении со старой (несендбокс)
  версии bookmark отсутствует — пользователь должен один раз заново выбрать файл.
  Entitlements: `app-sandbox`, `network.client` (проверка ключей и прокси),
  `files.user-selected.read-write`, `files.bookmarks.app-scope`.
- **Иконка в Dock + значок в меню-баре** — флаг `LSUIElement` не задан, приложение
  отображается и в Dock, и в трее.
- `apiKeyHelper` формируется автоматически из API-ключа.
- **Локализация интерфейса** (RU/EN) — не через `.strings`/`.lproj`, а через
  `AppStore.tr(ru, en)`: строки задаются прямо в коде парами, выбранный язык хранится
  в конфиге (`language`), смена применяется мгновенно без перезапуска (т.к. `language`
  — `@Published`, любой вызов `tr` в `body` перерисовывается). Все новые строки UI
  обязательно оборачивать в `store.tr(...)`.
- **Прокси** — отдельный список именованных прокси (с авторизацией или без). Ключу
  можно привязать прокси (`APIKey.proxyID`); при ротации URL прокcи пишется в
  `env.HTTPS_PROXY`/`env.HTTP_PROXY`. URL прокси: `http://[user:pass@]host[:port]`,
  логин/пароль percent-кодируются. При удалении прокси он автоматически отвязывается
  от всех ключей.

## Структура проекта
- `ClaudeRotate/APIKey.swift` — модель ключа (id, name, apiKey, baseURL, enabled,
  proxyID — привязанный прокси).
- `ClaudeRotate/Proxy.swift` — модель прокси (id, name, host, port, username, password),
  вычисляемые `url` (с percent-кодированием логина/пароля) и `displayName`.
- `ClaudeRotate/ProxyTester.swift` — `testProxy(_:)`: проверка прокси запросом к
  сервису геолокации (`ipwho.is`, HTTPS) через него. Возвращает `ProxyTestResult`
  с задержкой (ping) и страной выхода (`ProxyCheck`: latencyMs, countryCode → флаг и
  локализованное имя через `Locale`, ip). `407` = ошибка авторизации (через делегат
  сессии); транспортная ошибка = недоступен. UI-состояние — `ProxyTestState`.
- `ClaudeRotate/AppLanguage.swift` — перечисление языка интерфейса (`russian`/`english`),
  `displayName`, `systemDefault` (по локали системы).
- `ClaudeRotate/ClaudeRotate.entitlements` — entitlements песочницы (см. «Ключевые решения»).
- `ClaudeRotate/AppStore.swift` — единый источник данных (`ObservableObject`),
  хранение конфигурации в `~/Library/Application Support/ClaudeRotate/config.json`, CRUD
  ключей и прокси (`proxy(for:)` резолвит прокси ключа), локализация через `tr(ru, en)`.
  Доступ к целевому файлу: `setTargetFile(_:)` (создаёт bookmark из выбранного URL),
  `withTargetAccess(_:)` (резолвит bookmark, открывает security-scoped доступ,
  обновляет устаревший bookmark), `hasTargetFile`.
- `ClaudeRotate/RotationEngine.swift` — `writeKey(_:proxy:to:)` (запись ключа и прокси
  в уже резолвнутый security-scoped URL, неатомарно) и `RotationManager` (таймер,
  `start`/`stop`/`rotateNow`/`rotatePrevious`/`applyCurrentKey`; запись идёт через
  `store.withTargetAccess`). `RotationError` включает `noFileSelected`/`accessDenied`.
- `ClaudeRotate/ClaudeRotateApp.swift` — точка входа: `MenuBarExtra` (меню в трее)
  и окно настроек; автостарт ротации при запуске.
- `ClaudeRotate/RootView.swift` — UI: вкладка «Обзор» (`DashboardView`: карточка
  текущего ключа с прокси, статус ротации с таймером и кнопкой Запустить/Остановить,
  карточки предыдущего/следующего ключа, кнопки «Предыдущий»/«Следующий»), вкладка
  «Ключи» (CRUD/включение/порядок, привязка прокси в редакторе), вкладка «Прокси»
  (`ProxiesView`: CRUD/порядок/проверка прокси) и вкладка «Настройки» (выбор целевого
  файла кнопкой «Выбрать…» через `NSOpenPanel` → `store.setTargetFile`, интервал,
  автостарт, язык интерфейса, статус). Все строки UI — через `store.tr(...)`.
- `ClaudeRotate.xcodeproj/project.pbxproj` — настройки сборки (группа файлов
  синхронизируется с ФС: новые `.swift`-файлы подхватываются автоматически).

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
