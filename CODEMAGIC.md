# Сборка в Codemagic и отправка в TestFlight

Сборки описаны в [`codemagic.yaml`](codemagic.yaml):

- **`ios-ci`** — «FOLIO — сборка и тесты». Запускается на каждый push и pull request: компиляция всех targets без подписи и unit-тесты. Ключи Apple не нужны.
- **`ios-testflight`** — «FOLIO → TestFlight». Запускается вручную (Start new build или API): тестировщики TestFlight → номер сборки → тесты → сертификат и профили → IPA → загрузка в TestFlight. Всё настроено, дополнительных действий не нужно.

## Состояние

| Что | Значение | Статус |
| --- | --- | --- |
| Название в App Store | **FOLIO — PDF & Scan** («FOLIO» занято). На главном экране iPhone — «FOLIO» | ✅ |
| Приложение (Bundle ID) | `com.neverlandplayworks.folio` | ✅ App ID создан, App Groups включены |
| Расширение «Поделиться» | `com.neverlandplayworks.folio.share` | ✅ App ID создан, App Groups включены |
| App Group | `group.com.neverlandplayworks.folio` | ✅ создана и привязана к обоим App ID |
| Карточка App Store Connect | SKU `folio-ios`, основной язык English (U.S.) | ✅ |
| Codemagic | приложение **folio**: `ios-ci` и `ios-testflight` зелёные | ✅ |
| Политика конфиденциальности | <https://github.com/sardorcos/folio/blob/main/PRIVACY.md> | ✅ |
| Поддержка (Support URL) | <https://github.com/sardorcos/folio/issues> | ✅ |
| Ключ App Store Connect | интеграция команды Codemagic **`monetniy-mir-asc`** | ✅ |
| Сертификат Distribution | общий `R6X78X2AJN`, закрытый ключ — `CERTIFICATE_PRIVATE_KEY` в группе **`shared_signing`** (folio, zikr, ulash, codevia) | ✅ |
| Профили App Store | создаются/находятся автоматически (`fetch-signing-files --create`) | ✅ |
| TestFlight | внутренняя группа **FOLIO Internal** (доступ ко всем сборкам), владелец аккаунта добавлен | ✅ |
| Первая сборка | 0.6.0 (15) загружена в App Store Connect | ✅ |

Bundle ID задан в Build Settings проекта (`FOLIO_APP_BUNDLE_ID`); из него получаются идентификаторы расширения, тестов и App Group. Менять его больше нельзя — он уже зарегистрирован в App Store Connect.

Номер сборки подбирается сам: скрипт `scripts/asc_testflight.py` находит приложение (Apple ID `6837688523`), а шаг «Bundle ID и номер сборки» берёт «последний в TestFlight + 1».

---

## Как устроена подпись

- **Ключ App Store Connect API** берётся из интеграции команды `monetniy-mir-asc` (`integrations: app_store_connect` в `codemagic.yaml`). Codemagic передаёт его ссылкой `@file:…` на `~/.appstoreconnect/private_keys/AuthKey_<ID>.p8` — этот файл нельзя перезаписывать (скрипты FOLIO кладут свою копию в `~/folio_asc_key`).
- **Сертификат Apple Distribution** общий для приложений folio, zikr, ulash и codevia: его закрытый ключ хранится в защищённой переменной `CERTIFICATE_PRIVATE_KEY` группы `shared_signing` каждого из них. `app-store-connect fetch-signing-files … --certificate-key=@env:CERTIFICATE_PRIVATE_KEY` находит этот сертификат и не создаёт новый (у команды лимит — 3 сертификата Distribution).
- **Профили** для `com.neverlandplayworks.folio` и `.share` (с App Group) создаются автоматически при первой сборке и переиспользуются.
- **Development-сертификат не нужен**: `xcode-project use-profiles` + `build-ipa` подписывают сразу профилями App Store.
- **Облачная подпись Xcode** (`-allowProvisioningUpdates`) не используется: у ключа `monetniy-mir-asc` нет роли Admin.

## Запустить новую сборку

Codemagic → приложение **folio** → **Start new build** → ветка `main` → workflow **FOLIO → TestFlight**. Для повторного запуска без тестов (если код не менялся) можно передать переменную `SKIP_TESTS=1`.

## После сборки

- В разделе **Artifacts** будут IPA, dSYM и результаты тестов. Логи xcodebuild — в `/tmp/xcodebuild_logs`.
- После загрузки Apple обрабатывает сборку 5–30 минут, затем она появляется в App Store Connect → **TestFlight**.
- **Внутреннее тестирование:** TestFlight → Internal Testing → **+** → добавьте себя. Сборка станет доступна в приложении TestFlight на iPhone.
- При первой сборке App Store Connect может спросить про шифрование. Ответ уже указан в проекте (`ITSAppUsesNonExemptEncryption = NO`), вопрос появиться не должен.

## Если сборка упала

| Шаг | Частая причина | Что сделать |
| --- | --- | --- |
| Подпись | Профиль не содержит App Group | Проверить в Identifiers, что у обоих App ID в App Groups отмечена `group.com.neverlandplayworks.folio`, и запустить сборку снова |
| Подпись | «You already have a current Distribution certificate» | `CERTIFICATE_PRIVATE_KEY` не совпадает с общим сертификатом — проверить группу `shared_signing` (ключ должен быть одинаковым во всех приложениях) |
| Подпись | Сертификат `R6X78X2AJN` отозван | Сгенерировать новый ключ, обновить `shared_signing` во всех приложениях — сертификат создастся заново |
| Unit-тесты | Ошибка компиляции или упавший тест | Открыть лог шага; ошибки компиляции нужно исправить в коде |
| Загрузка | «No suitable application records» | Проверить, что карточка «FOLIO — PDF & Scan» создана с Bundle ID `com.neverlandplayworks.folio` |
| Загрузка | «The bundle version must be higher» | Указать `APP_STORE_APPLE_ID` в `codemagic.yaml` или запустить сборку ещё раз |

## Что увидят тестировщики

Текст «What to Test» для TestFlight берётся из [`release_notes.txt`](release_notes.txt) (на английском — основной язык карточки). Интерфейс приложения пока на русском.
