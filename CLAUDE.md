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
  `KeyRotator/KeyRotator.entitlements`) — требование Mac App Store. Доступ к
  целевому файлу — только через **security-scoped bookmark**: пользователь выбирает
  файл вручную (`NSOpenPanel`), приложение хранит bookmark (`AppStore.fileBookmark`,
  app-scope) и перед каждым чтением/записью открывает доступ через
  `AppStore.withTargetAccess`. Произвольный ввод пути текстом больше не поддерживается;
  `filePath` остаётся только для отображения. При обновлении со старой (несендбокс)
  версии bookmark отсутствует — пользователь должен один раз заново выбрать файл.
  Entitlements: `app-sandbox`, `network.client` (проверка ключей и прокси),
  `files.user-selected.read-write`, `files.bookmarks.app-scope`.
- **Иконка в Dock + значок в меню-баре** — флаг `LSUIElement` не задан, приложение
  по умолчанию отображается и в Dock, и в трее. Видимость в Dock переключается в
  рантайме настройкой «Скрывать из Dock» (`hideFromDock`) через
  `NSApp.setActivationPolicy(.accessory/.regular)` — без перезапуска.
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
- `KeyRotator/APIKey.swift` — модель ключа (id, name, apiKey, baseURL, enabled,
  proxyID — привязанный прокси).
- `KeyRotator/Proxy.swift` — модель прокси (id, name, host, port, username, password),
  вычисляемые `url` (с percent-кодированием логина/пароля) и `displayName`.
- `KeyRotator/ProxyTester.swift` — `testProxy(_:)`: проверка прокси запросом к
  сервису геолокации (`ipwho.is`, HTTPS) через него. Возвращает `ProxyTestResult`
  с задержкой (ping) и страной выхода (`ProxyCheck`: latencyMs, countryCode → флаг и
  локализованное имя через `Locale`, ip). `407` = ошибка авторизации (через делегат
  сессии); транспортная ошибка = недоступен. UI-состояние — `ProxyTestState`.
- `KeyRotator/AppLanguage.swift` — перечисление языка интерфейса (`russian`/`english`),
  `displayName`, `systemDefault` (по локали системы).
- `KeyRotator/KeyRotator.entitlements` — entitlements песочницы (см. «Ключевые решения»).
- `KeyRotator/AppStore.swift` — единый источник данных (`ObservableObject`),
  хранение конфигурации в `~/Library/Application Support/ClaudeRotate/config.json`, CRUD
  ключей и прокси (`proxy(for:)` резолвит прокси ключа), локализация через `tr(ru, en)`.
  Доступ к целевому файлу: `setTargetFile(_:)` (создаёт bookmark из выбранного URL),
  `withTargetAccess(_:)` (резолвит bookmark, открывает security-scoped доступ,
  обновляет устаревший bookmark), `hasTargetFile`. Импорт/экспорт/сброс:
  `exportData()` (сериализует ключи, прокси, интервал, автозапуск, язык в JSON;
  bookmark и путь к целевому файлу НЕ включаются — доступ специфичен для машины),
  `importData(_:)` (заменяет настройки данными из файла, сбрасывает рантайм-состояние),
  `resetAll()` (очищает все ключи, прокси и настройки до значений по умолчанию и
  забывает целевой файл; сам settings.json пользователя не трогается).
- `KeyRotator/RotationEngine.swift` — `writeKey(_:proxy:to:)` (запись ключа и прокси
  в уже резолвнутый security-scoped URL, неатомарно) и `RotationManager` (таймер,
  `start`/`stop`/`rotateNow`/`rotatePrevious`/`applyCurrentKey`; запись идёт через
  `store.withTargetAccess`). `RotationError` включает `noFileSelected`/`accessDenied`.
- `KeyRotator/KeyRotatorApp.swift` — точка входа: `MenuBarExtra` (меню в трее)
  и окно настроек; автостарт ротации при запуске. `applyActivationPolicy(hidden:)`
  переключает видимость в Dock (`.accessory`/`.regular`) по флагу `store.hideFromDock`
  (применяется в `onAppear` и `onChange`).
- `KeyRotator/RootView.swift` — UI. Навигация — нативный `NavigationSplitView` с
  боковой панелью (`List(selection:)` по `RootView.Tab`: Обзор/Ключи/Прокси/Настройки,
  иконка+подпись, заголовок detail через `.navigationTitle`). В шапке боковой панели
  (`.safeAreaInset(edge: .top)`) — всегда видимый логотип-бренд (`sidebarBrand`):
  реальная иконка приложения (`Image(nsImage: NSApp.applicationIconImage)`, всегда
  совпадает с иконкой в Dock), название «KeyRotator» и подпись «Ротация ключей»;
  фон `.bar`, снизу `Divider`. Раздел «Обзор»
  (`DashboardView`): баннер «нет файла», единый блок-герой (`heroCard`) и ряд плиток
  статистики (`statsGrid`), баннер ошибки. `heroCard`: слева крупное круговое кольцо
  обратного отсчёта (`countdownRing` — `Circle().trim` внутри `TimelineView`,
  прогресс = 1 − remaining/total, в центре время + «осталось»), справа детали
  текущего ключа (`keyDetails`: имя, индикатор проверки, позиция «n / N», капсула
  статуса `statusBadge` активна/остановлена, masked API-ключ, base URL, прокси,
  время применения), снизу единая группа управления `controlGroup` — компактные
  иконочные «Предыдущий»/«Следующий» по краям и растянутая prominent-кнопка
  Запустить/Остановить в центре. `statsGrid`: 4 плитки (`statTile`) — включено
  ключей (N/всего), интервал, число прокси (или «выключены»), время следующей смены.
  Каждая плитка — кнопка (`.buttonStyle(.plain)`), переключающая `RootView.Tab`
  (биндинг `tab` передаётся в `DashboardView`): включено→Ключи, интервал→Настройки,
  прокси→Прокси, след. смена→Настройки.
  Ленты с именами предыдущего/следующего ключей нет. Раздел «Ключи» (CRUD/включение/порядок,
  привязка прокси в редакторе), «Прокси» (`ProxiesView`: CRUD/порядок/проверка) и
  «Настройки» (выбор целевого файла кнопкой «Выбрать…» через `NSOpenPanel` →
  `store.setTargetFile`; интервал — `TextField`+`Stepper` и segmented-пресеты
  15/30/60/120; автостарт; язык; «Скрывать из Dock» (`hideFromDock`); секция «Данные»: экспорт `NSSavePanel` →
  `store.exportData`, импорт `NSOpenPanel` → `store.importData`; отдельная секция со
  сбросом — `.alert` → `store.resetAll`). Все строки UI — через `store.tr(...)`.
  Списки ключей/прокси: поиск по имени и baseURL/host (`ListSearchField`, при активном
  поиске перетаскивание `onMove` отключается, т.к. индексы не совпадают со `store`);
  строки показывают действия (Проверить/Изменить/Сделать активным/Удалить) при
  наведении (`hovering` + opacity, чтобы не «прыгала» вёрстка); результат проверки
  выводится текстом (Валиден / HTTP-код). Заливка строк — единым механизмом
  `listRowBackground` во всю ширину (системная зебра `alternatesRowBackgrounds`
  не используется — она расходилась по форме с подсветкой): «зебра» рисуется вручную
  по чётности индекса (`Color.primary.opacity(0.04)`), активный ключ — зелёная
  заливка (`Color.green.opacity(0.22)`), выключенный — серая; форма у зебры и
  подсветки совпадает, края скругляет контейнер `.listStyle(.inset)`. Удаление ключа
  или прокси — через `.alert`-подтверждение (`keyToDelete`/`proxyToDelete`, кнопки
  Удалить/Отмена, Esc = отмена); все точки удаления (наведение, контекстное меню,
  кнопка «−») открывают диалог, а не удаляют сразу. Пустые состояния —
  `ContentUnavailableView` (и `.search(text:)` при отсутствии совпадений). Общие компоненты: `ToolbarIconButton` (иконки нижнего тулбара),
  `ListSearchField`, модификатор `tagChip(tint:opacity:)` (единый стиль бейджей-капсул)
  и `dashboardCard(padding:tint:)` (единый стиль карточек дашборда — материал-фон,
  тонкая обводка, опциональный цветовой акцент).
- `ClaudeRotate.xcodeproj/project.pbxproj` — настройки сборки (группа файлов
  синхронизируется с ФС: новые `.swift`-файлы подхватываются автоматически).

## Сборка
xcodebuild требует полный Xcode (не Command Line Tools), поэтому указываем
`DEVELOPER_DIR`:

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project ClaudeRotate.xcodeproj -scheme KeyRotator \
  -configuration Debug -destination 'platform=macOS' build
```

Собранное приложение: `~/Library/Developer/Xcode/DerivedData/ClaudeRotate-*/Build/Products/Debug/KeyRotator.app`.

## Технические детали
- macOS deployment target: 26.5, Swift 5.0, изоляция по умолчанию — MainActor.
- Bundle ID: `com.romas.clauderotatekey`. Таргет, папка исходников (`KeyRotator/`) и
  имя приложения (`CFBundleName`/`CFBundleDisplayName`/`PRODUCT_NAME`) — **KeyRotator**
  (нейтральное, без товарного знака «Claude»; совместимость с Claude Code указывается
  только в подзаголовке/описании). Файл проекта остаётся `ClaudeRotate.xcodeproj`, а
  каталог конфига — `~/Library/Application Support/ClaudeRotate/` (не переименован,
  чтобы не потерять существующие настройки).
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
