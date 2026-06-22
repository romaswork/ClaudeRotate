# Privacy Policy — KeyRotator

_Last updated: 2026-06-22_

KeyRotator is a macOS utility that manages and rotates Claude API credentials for use with Claude Code. This Privacy Policy explains what data the app handles and how.

## Summary

**KeyRotator does not collect, transmit, or share any personal data.** All your data stays on your Mac. There are no accounts, no analytics, no tracking, and no backend servers operated by us.

## Data stored locally

The app stores the following information **only on your device**, in your user Application Support directory (`~/Library/Application Support/ClaudeRotate/`):

- API keys you add (names, key values, base URLs, enabled state).
- Proxies you configure (names, hosts, ports, usernames, passwords).
- App settings (target file reference, rotation interval, autostart, interface language).

This data is never sent to us or to any third party. We have no access to it.

## Access to your settings file

The app runs in the macOS App Sandbox. To write rotated keys into your Claude Code settings file, you must select that file manually. The app then stores a security-scoped bookmark so it can access **only that file** — it cannot read your other files or directories.

When rotating, the app modifies only the key- and proxy-related fields in the selected JSON file and preserves the rest of its contents.

## Network usage

The app makes outbound network connections **only** in two optional, user-initiated cases:

1. **Proxy test** — when you press "Test" on a proxy, the app sends a request through that proxy to a public geolocation service (`ipwho.is`) to report latency and exit country.
2. **API key check** — when you choose to validate a key, the app contacts the corresponding API endpoint.

These checks are triggered manually by you and are not required for normal operation. No usage data, telemetry, or personal information is transmitted to us during these requests.

## Third parties

KeyRotator is an independent utility and is not affiliated with Anthropic. When you use proxy testing or key validation, your request reaches the respective third-party service (e.g. `ipwho.is`, your API provider). Those services are governed by their own privacy policies.

## Children's privacy

The app is not directed at children and does not knowingly collect any data from anyone.

## Changes to this policy

If this policy changes, the updated version will be published at this same location with a new "Last updated" date.

## Contact

For questions or support, please open an issue:
`https://github.com/<your-account>/<repository>/issues`

---

# Политика конфиденциальности — KeyRotator

_Последнее обновление: 2026-06-22_

KeyRotator — это утилита для macOS, которая управляет учётными данными Claude API и ротирует их для использования с Claude Code. Эта политика описывает, какие данные обрабатывает приложение и как.

## Кратко

**KeyRotator не собирает, не передаёт и не раскрывает никаких персональных данных.** Все ваши данные остаются на вашем Mac. Нет учётных записей, аналитики, отслеживания и каких-либо наших серверов.

## Данные, хранящиеся локально

Приложение хранит следующую информацию **только на вашем устройстве**, в каталоге Application Support (`~/Library/Application Support/ClaudeRotate/`):

- Добавленные вами API-ключи (названия, значения ключей, базовые URL, состояние «включён»).
- Настроенные прокси (названия, хосты, порты, логины, пароли).
- Настройки приложения (ссылка на целевой файл, интервал ротации, автозапуск, язык интерфейса).

Эти данные никогда не отправляются нам или третьим лицам. У нас нет к ним доступа.

## Доступ к вашему файлу настроек

Приложение работает в песочнице macOS (App Sandbox). Чтобы записывать ротируемые ключи в файл настроек Claude Code, вы выбираете этот файл вручную. Приложение сохраняет security-scoped bookmark и получает доступ **только к этому файлу** — оно не может читать другие ваши файлы или каталоги.

При ротации приложение изменяет в выбранном JSON-файле только поля, относящиеся к ключу и прокси, сохраняя остальное содержимое без изменений.

## Использование сети

Приложение устанавливает исходящие сетевые соединения **только** в двух необязательных случаях, инициированных вами:

1. **Проверка прокси** — при нажатии «Проверить» приложение отправляет запрос через прокси к публичному сервису геолокации (`ipwho.is`), чтобы показать задержку и страну выхода.
2. **Проверка ключа** — при выборе проверки ключа приложение обращается к соответствующему API.

Эти проверки запускаются вами вручную и не нужны для обычной работы. Никакие данные об использовании, телеметрия или персональная информация нам при этом не передаются.

## Третьи стороны

KeyRotator — независимая утилита и не связана с Anthropic. При проверке прокси или ключа ваш запрос достигает соответствующего стороннего сервиса (например, `ipwho.is`, вашего API-провайдера). Эти сервисы регулируются собственными политиками конфиденциальности.

## Конфиденциальность детей

Приложение не предназначено для детей и сознательно не собирает данные ни о ком.

## Изменения политики

При изменении политики обновлённая версия будет опубликована по этому же адресу с новой датой «Последнее обновление».

## Контакты

По вопросам и для поддержки создайте issue:
`https://github.com/<ваш-аккаунт>/<репозиторий>/issues`
