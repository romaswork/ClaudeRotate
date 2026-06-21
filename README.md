# ClaudeRotate

Менубарное приложение для macOS, которое по таймеру ротирует учётные данные Claude API
в JSON-файле конфигурации (формат Claude Code `settings.json`).

## Возможности

- Список именованных ключей (`ANTHROPIC_API_KEY` + `ANTHROPIC_BASE_URL`) с
  добавлением, редактированием, удалением и включением/выключением каждого.
- Ротация включённых ключей по очереди каждые N минут.
- Значок в меню-баре и иконка в Dock.
- Все данные хранятся локально.

При ротации в целевом файле меняются только три поля, остальное содержимое сохраняется:

```json
{
  "apiKeyHelper": "echo '<ANTHROPIC_API_KEY>'",
  "env": {
    "ANTHROPIC_API_KEY": "<ключ>",
    "ANTHROPIC_BASE_URL": "<базовый URL>"
  }
}
```

## Сборка

Требуется полный Xcode (macOS 26.5+):

```sh
xcodebuild -project ClaudeRotate.xcodeproj -scheme ClaudeRotate \
  -configuration Debug -destination 'platform=macOS' build
```

Или откройте `ClaudeRotate.xcodeproj` в Xcode и нажмите Run.

## Использование

1. Откройте настройки из меню в трее.
2. Укажите путь к целевому JSON-файлу (например, `~/.claude/settings.json`).
3. Добавьте ключи и задайте интервал.
4. Нажмите «Start Rotation».

## Хранение данных

Конфигурация (ключи и настройки) хранится локально в
`~/Library/Application Support/ClaudeRotate/config.json`. API-ключи хранятся в
открытом виде.
