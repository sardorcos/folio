# Сборка в Codemagic и отправка в TestFlight

Сборки описаны в [`codemagic.yaml`](codemagic.yaml):

- **`ios-ci`** — «FOLIO — сборка и тесты». Запускается на каждый push и pull request: компиляция всех targets без подписи и unit-тесты. Ключи Apple не нужны.
- **`ios-testflight`** — «FOLIO → TestFlight». Запускается вручную: проверка → тесты → сертификат и профили → IPA → загрузка в TestFlight. Нужна разовая настройка ниже.

Bundle ID задан в проекте: **`com.neverlandplayworks.folio`** (Build Settings проекта → `FOLIO_APP_BUNDLE_ID`).
От него получаются:

| Что | Идентификатор |
| --- | --- |
| Приложение | `com.neverlandplayworks.folio` |
| Расширение «Поделиться» | `com.neverlandplayworks.folio.share` |
| App Group | `group.com.neverlandplayworks.folio` |

Если нужен другой идентификатор, поменяйте его **до** шага 1 (в `project.pbxproj` или в Xcode). После первой загрузки в App Store Connect его уже нельзя изменить.

---

## Шаг 1. Apple Developer: App Group и два App ID

Нужен платный аккаунт Apple Developer Program. Это единственная часть, которую нельзя автоматизировать: API Apple не умеет создавать App Group.

1. [developer.apple.com/account](https://developer.apple.com/account) → **Certificates, Identifiers & Profiles** → **Identifiers**.
2. **+** → **App Groups** → Description `FOLIO`, Identifier `group.com.neverlandplayworks.folio` → Register.
3. **+** → **App IDs** → **App** → Description `FOLIO`, Bundle ID (Explicit) `com.neverlandplayworks.folio`. В Capabilities отметьте **App Groups** → Continue → Register.
4. Повторите для расширения: Description `FOLIO Share`, Bundle ID `com.neverlandplayworks.folio.share`, тоже с **App Groups**.
5. Откройте каждый из двух App ID → **App Groups** → **Configure** → отметьте `group.com.neverlandplayworks.folio` → Save.

## Шаг 2. App Store Connect: карточка приложения

1. [appstoreconnect.apple.com](https://appstoreconnect.apple.com) → **Apps** → **+** → **New App**.
2. Platform **iOS**, Name **FOLIO** (если занято — например «FOLIO — PDF и сканы»), Primary Language **Russian**, Bundle ID `com.neverlandplayworks.folio`, SKU — любой, например `folio-ios`.
3. Необязательно: скопируйте **Apple ID** приложения (App Information → General). Это число нужно для переменной `APP_STORE_APPLE_ID` в `codemagic.yaml`, тогда номера сборок будут продолжаться от последнего в TestFlight.

## Шаг 3. Ключ App Store Connect API

1. App Store Connect → **Users and Access** → **Integrations** → **App Store Connect API** → **Team Keys** → **+**.
2. Name `Codemagic`, Access **App Manager** (или Admin) → Generate.
3. Сохраните **Issuer ID**, **Key ID** и скачайте файл `AuthKey_XXXX.p8`. Скачать его можно только один раз.

## Шаг 4. Ключ для сертификата подписи

Codemagic сам создаст сертификат Apple Distribution, но ему нужен закрытый RSA-ключ. Создайте его на любом компьютере:

```bash
ssh-keygen -t rsa -b 2048 -m PEM -f folio_cert_key -q -N ""
```

Нужен файл `folio_cert_key` (без `.pub`). Храните его надёжно: тем же ключом пользуются следующие сборки.

## Шаг 5. Codemagic

1. Приложение **folio** в Codemagic уже добавлено (репозиторий `sardorcos/folio`), workflow `ios-ci` проходит: сборка и 36 тестов.
2. Приложение **folio** → **Environment variables** → создайте группу **`app_store_credentials`** с переменными (все отметьте **Secure**):

   | Переменная | Значение |
   | --- | --- |
   | `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID из шага 3 |
   | `APP_STORE_CONNECT_KEY_IDENTIFIER` | Key ID из шага 3 |
   | `APP_STORE_CONNECT_PRIVATE_KEY` | всё содержимое `AuthKey_XXXX.p8`, включая строки `-----BEGIN/END PRIVATE KEY-----` |
   | `CERTIFICATE_PRIVATE_KEY` | всё содержимое `folio_cert_key` из шага 4 |

3. **Start new build** → ветка `main` → workflow **FOLIO → TestFlight**. Повторные загрузки запускаются так же (или добавьте в workflow блок `triggering`, чтобы отправлять каждый push в `main`).

## После сборки

- В разделе **Artifacts** будут IPA, dSYM и результаты тестов. Логи xcodebuild — в `/tmp/xcodebuild_logs`.
- После загрузки Apple обрабатывает сборку 5–30 минут, затем она появляется в App Store Connect → **TestFlight**.
- **Внутреннее тестирование:** TestFlight → Internal Testing → **+** → добавьте себя. Сборка станет доступна в приложении TestFlight на iPhone.
- При первой сборке App Store Connect может спросить про шифрование. Ответ уже указан в проекте (`ITSAppUsesNonExemptEncryption = NO`), вопрос появиться не должен.

## Если сборка упала

| Шаг | Частая причина | Что сделать |
| --- | --- | --- |
| Подпись | `group.com.neverlandplayworks.folio` не привязана к App ID | Повторить шаг 1, пункт 5 |
| Подпись | Нет доступа к API | Проверить роль ключа (App Manager/Admin) и переменные группы |
| Подпись | Достигнут лимит сертификатов Distribution | Отозвать старый сертификат в Certificates или использовать тот же `CERTIFICATE_PRIVATE_KEY` |
| Unit-тесты | Ошибка компиляции или упавший тест | Открыть лог шага; ошибки компиляции нужно исправить в коде |
| Загрузка | «No suitable application records» | Создать карточку приложения (шаг 2) с тем же Bundle ID |
| Загрузка | «The bundle version must be higher» | Указать `APP_STORE_APPLE_ID` в `codemagic.yaml` или запустить сборку ещё раз |
