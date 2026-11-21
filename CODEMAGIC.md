# Сборка в Codemagic и отправка в TestFlight

Сборки описаны в [`codemagic.yaml`](codemagic.yaml):

- **`ios-ci`** — «FOLIO — сборка и тесты». Запускается на каждый push и pull request: компиляция всех targets без подписи и unit-тесты. Ключи Apple не нужны.
- **`ios-testflight`** — «FOLIO → TestFlight». Запускается вручную: проверка → тесты → сертификат и профили → IPA → загрузка в TestFlight. Нужна разовая настройка ниже.

## Состояние

| Что | Значение | Статус |
| --- | --- | --- |
| Название в App Store | **FOLIO — PDF & Scan** («FOLIO» занято). На главном экране iPhone — «FOLIO» | ✅ |
| Приложение (Bundle ID) | `com.neverlandplayworks.folio` | ✅ App ID создан, App Groups включены |
| Расширение «Поделиться» | `com.neverlandplayworks.folio.share` | ✅ App ID создан, App Groups включены |
| App Group | `group.com.neverlandplayworks.folio` | ✅ создана и привязана к обоим App ID |
| Карточка App Store Connect | SKU `folio-ios`, основной язык English (U.S.) | ✅ |
| Codemagic | приложение **folio**, workflow `ios-ci` зелёный (сборка + 36 тестов) | ✅ |
| Политика конфиденциальности | <https://github.com/sardorcos/folio/blob/main/PRIVACY.md> | ✅ |
| Поддержка (Support URL) | <https://github.com/sardorcos/folio/issues> | ✅ |
| Ключи для подписи и загрузки | группа `app_store_credentials` в Codemagic | ⏳ шаги 3–5 ниже |

Bundle ID задан в Build Settings проекта (`FOLIO_APP_BUNDLE_ID`); из него получаются идентификаторы расширения, тестов и App Group. Менять его больше нельзя — он уже зарегистрирован в App Store Connect.

Если нужен числовой **Apple ID** приложения (App Store Connect → App Information → General → Apple ID), добавьте его в `codemagic.yaml` как переменную `APP_STORE_APPLE_ID` — тогда номера сборок будут продолжаться от последнего в TestFlight. Без неё номер берётся из счётчика сборок Codemagic.

---

## Шаг 3. Ключ App Store Connect API (если ещё нет)

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

   Если у команды уже есть ключ App Store Connect API (он используется в других ваших приложениях Codemagic), можно взять те же три значения — новый ключ создавать не обязательно.

3. **Start new build** → ветка `main` → workflow **FOLIO → TestFlight**. Повторные загрузки запускаются так же (или добавьте в workflow блок `triggering`, чтобы отправлять каждый push в `main`).

## После сборки

- В разделе **Artifacts** будут IPA, dSYM и результаты тестов. Логи xcodebuild — в `/tmp/xcodebuild_logs`.
- После загрузки Apple обрабатывает сборку 5–30 минут, затем она появляется в App Store Connect → **TestFlight**.
- **Внутреннее тестирование:** TestFlight → Internal Testing → **+** → добавьте себя. Сборка станет доступна в приложении TestFlight на iPhone.
- При первой сборке App Store Connect может спросить про шифрование. Ответ уже указан в проекте (`ITSAppUsesNonExemptEncryption = NO`), вопрос появиться не должен.

## Если сборка упала

| Шаг | Частая причина | Что сделать |
| --- | --- | --- |
| Подпись | Профиль не содержит App Group | Проверить в Identifiers, что у обоих App ID в App Groups отмечена `group.com.neverlandplayworks.folio`, и запустить сборку снова |
| Подпись | Нет доступа к API | Проверить роль ключа (App Manager/Admin) и переменные группы |
| Подпись | Достигнут лимит сертификатов Distribution | Отозвать старый сертификат в Certificates или использовать тот же `CERTIFICATE_PRIVATE_KEY` |
| Unit-тесты | Ошибка компиляции или упавший тест | Открыть лог шага; ошибки компиляции нужно исправить в коде |
| Загрузка | «No suitable application records» | Проверить, что карточка «FOLIO — PDF & Scan» создана с Bundle ID `com.neverlandplayworks.folio` |
| Загрузка | «The bundle version must be higher» | Указать `APP_STORE_APPLE_ID` в `codemagic.yaml` или запустить сборку ещё раз |

## Что увидят тестировщики

Текст «What to Test» для TestFlight берётся из [`release_notes.txt`](release_notes.txt) (на английском — основной язык карточки). Интерфейс приложения пока на русском.
