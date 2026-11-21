#!/usr/bin/env python3
"""Подготовка TestFlight через App Store Connect API (запускается в Codemagic).

1. Находит приложение по Bundle ID и пишет его Apple ID в $CM_ENV (APP_STORE_APPLE_ID) — для номера сборки.
2. Создаёт внутреннюю группу «FOLIO Internal» с доступом ко всем сборкам (если её ещё нет).
3. Добавляет в группу владельца аккаунта (роль ACCOUNT_HOLDER) как внутреннего тестировщика.

Ключ берётся из переменных интеграции Codemagic: APP_STORE_CONNECT_ISSUER_ID,
APP_STORE_CONNECT_KEY_IDENTIFIER, APP_STORE_CONNECT_PRIVATE_KEY. Секреты в лог не выводятся.
Использование: asc_testflight.py <bundle id>
"""
import base64
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import jwt  # PyJWT + cryptography

API = "https://api.appstoreconnect.apple.com"
GROUP_NAME = "FOLIO Internal"


def resolve(value: str, depth: int = 0) -> str:
    """Значение в формате Codemagic CLI: текст, `@file:<путь>` или `@env:<переменная>`."""
    value = value.strip()
    if depth < 3 and value.startswith("@file:"):
        return resolve(open(os.path.expanduser(value[6:])).read(), depth + 1)
    if depth < 3 and value.startswith("@env:"):
        return resolve(os.environ.get(value[5:], ""), depth + 1)
    return value


def private_key() -> str:
    raw = os.environ["APP_STORE_CONNECT_PRIVATE_KEY"]
    key = resolve(raw)
    if "\\n" in key and "\n" not in key:
        key = key.replace("\\n", "\n")
    if "BEGIN" not in key:
        try:
            decoded = base64.b64decode(key, validate=False).decode()
            if "BEGIN" in decoded:
                key = decoded
        except (ValueError, UnicodeDecodeError):
            pass
    if "BEGIN" not in key:
        # Голое тело ключа без заголовков.
        body = "".join(key.split())
        key = "-----BEGIN PRIVATE KEY-----\n" + "\n".join(body[i:i + 64] for i in range(0, len(body), 64)) + "\n-----END PRIVATE KEY-----\n"
    # Безопасная диагностика формата (без содержимого ключа).
    print(f"Ключ API: формат источника {'@file' if raw.strip().startswith('@file:') else '@env' if raw.strip().startswith('@env:') else 'текст'}, "
          f"строк {key.count(chr(10)) + 1}, PEM-заголовок {'есть' if 'BEGIN' in key else 'нет'}")
    return key


def token() -> str:
    key = private_key()
    now = int(time.time())
    payload = {"iss": resolve(os.environ["APP_STORE_CONNECT_ISSUER_ID"]), "iat": now, "exp": now + 15 * 60,
               "aud": "appstoreconnect-v1"}
    return jwt.encode(payload, key, algorithm="ES256",
                      headers={"kid": resolve(os.environ["APP_STORE_CONNECT_KEY_IDENTIFIER"]), "typ": "JWT"})


TOKEN = None


def call(method: str, path: str, body=None, query=None):
    url = API + path + ("?" + urllib.parse.urlencode(query) if query else "")
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(url, data=data, method=method, headers={
        "Authorization": f"Bearer {TOKEN}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            raw = response.read()
            return response.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as error:
        raw = error.read()
        try:
            return error.code, json.loads(raw)
        except ValueError:
            return error.code, {"raw": raw.decode(errors="replace")[:500]}


def errors(payload) -> str:
    return "; ".join(f'{e.get("code")}: {e.get("detail") or e.get("title")}' for e in payload.get("errors", [])) or str(payload)[:300]


def main() -> int:
    global TOKEN
    bundle_id = sys.argv[1]
    TOKEN = token()

    status, apps = call("GET", "/v1/apps", query={"filter[bundleId]": bundle_id, "fields[apps]": "name,bundleId"})
    if status != 200 or not apps.get("data"):
        print(f"❌ Приложение {bundle_id} не найдено в App Store Connect ({status}: {errors(apps)})")
        return 1
    app = apps["data"][0]
    app_id = app["id"]
    print(f"Приложение: {app['attributes'].get('name')} — Apple ID {app_id}")
    # Team ID (seedId Bundle ID) и файл ключа для облачной подписи xcodebuild (-allowProvisioningUpdates).
    team_id = ""
    status, bundles = call("GET", "/v1/bundleIds", query={"filter[identifier]": bundle_id, "limit": 20})
    if status == 200:
        team_id = next((b["attributes"].get("seedId", "") for b in bundles["data"]
                        if b["attributes"]["identifier"] == bundle_id), "")
    print(f"Team ID: {team_id or 'не найден'}")
    # Отдельная папка: интеграция Codemagic сама хранит ключ в ~/.appstoreconnect/private_keys
    # и ссылается на него через @file: — перезапись того же файла обнулила бы ключ.
    key_dir = os.path.expanduser("~/folio_asc_key")
    os.makedirs(key_dir, mode=0o700, exist_ok=True)
    key_id = resolve(os.environ["APP_STORE_CONNECT_KEY_IDENTIFIER"])
    key_text = private_key()
    key_path = os.path.join(key_dir, f"AuthKey_{key_id}.p8")
    with open(key_path, "w") as handle:
        handle.write(key_text)
    os.chmod(key_path, 0o600)
    env_file = os.environ.get("CM_ENV")
    if env_file:
        with open(env_file, "a") as handle:
            handle.write(f"APP_STORE_APPLE_ID={app_id}\n")
            handle.write(f"FOLIO_TEAM_ID={team_id}\n")
            handle.write(f"ASC_KEY_PATH={key_path}\n")
            handle.write(f"ASC_KEY_ID={key_id}\n")
            handle.write(f"ASC_ISSUER_ID={resolve(os.environ['APP_STORE_CONNECT_ISSUER_ID'])}\n")

    status, groups = call("GET", f"/v1/apps/{app_id}/betaGroups", query={"limit": 200})
    if status != 200:
        print(f"⚠️ Не удалось получить группы TestFlight ({status}: {errors(groups)})")
        return 0
    group = next((g for g in groups["data"] if g["attributes"].get("isInternalGroup")
                  and g["attributes"].get("name") == GROUP_NAME), None)
    if group is None:
        status, created = call("POST", "/v1/betaGroups", body={"data": {
            "type": "betaGroups",
            "attributes": {"name": GROUP_NAME, "isInternalGroup": True, "hasAccessToAllBuilds": True},
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})
        if status not in (200, 201):
            print(f"⚠️ Не удалось создать внутреннюю группу ({status}: {errors(created)})")
            return 0
        group = created["data"]
        print(f"Создана внутренняя группа «{GROUP_NAME}» с доступом ко всем сборкам")
    else:
        print(f"Внутренняя группа «{GROUP_NAME}» уже есть")
    group_id = group["id"]

    status, users = call("GET", "/v1/users", query={"filter[roles]": "ACCOUNT_HOLDER", "limit": 10})
    if status != 200 or not users.get("data"):
        print(f"⚠️ Не удалось найти владельца аккаунта ({status}: {errors(users)})")
        return 0

    status, current = call("GET", f"/v1/betaGroups/{group_id}/betaTesters", query={"limit": 200})
    present = {t["attributes"].get("email", "").lower() for t in current.get("data", [])} if status == 200 else set()

    for user in users["data"]:
        attrs = user["attributes"]
        email = attrs.get("username") or attrs.get("email") or ""
        masked = email[:2] + "…@" + email.split("@")[-1] if "@" in email else "владелец"
        if email.lower() in present:
            print(f"Тестировщик {masked} уже в группе")
            continue
        status, created = call("POST", "/v1/betaTesters", body={"data": {
            "type": "betaTesters",
            "attributes": {"email": email, "firstName": attrs.get("firstName") or "", "lastName": attrs.get("lastName") or ""},
            "relationships": {"betaGroups": {"data": [{"type": "betaGroups", "id": group_id}]}}}})
        if status in (200, 201):
            print(f"✅ Владелец аккаунта {masked} добавлен во внутреннюю группу")
            continue
        # Тестировщик уже существует в аккаунте — добавляем его в группу отдельно.
        status, found = call("GET", "/v1/betaTesters", query={"filter[email]": email, "limit": 1})
        if status == 200 and found.get("data"):
            tester_id = found["data"][0]["id"]
            status, linked = call("POST", f"/v1/betaGroups/{group_id}/relationships/betaTesters",
                                  body={"data": [{"type": "betaTesters", "id": tester_id}]})
            if status in (200, 204):
                print(f"✅ Владелец аккаунта {masked} добавлен во внутреннюю группу")
                continue
            print(f"⚠️ Не удалось добавить {masked} в группу ({status}: {errors(linked)})")
        else:
            print(f"⚠️ Не удалось добавить {masked} ({errors(created)})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
