#!/usr/bin/env python3
"""Профили App Store для FOLIO под сертификат, уже установленный в keychain сборки.

Новый сертификат Apple Distribution создать нельзя (лимит команды), поэтому используется
командный сертификат из Codemagic (ios_signing → certificates). Скрипт:
1. берёт SHA-1 подписывающих сертификатов из keychain (`security find-identity`);
2. находит такой же сертификат Distribution в App Store Connect;
3. для каждого Bundle ID находит действующий профиль IOS_APP_STORE «FOLIO …» с этим сертификатом
   или создаёт новый (возможности App ID, включая App Groups, попадают в профиль автоматически);
4. сохраняет профили в ~/Library/MobileDevice/Provisioning Profiles для `xcode-project use-profiles`.

Использование: asc_profiles.py <bundle id> [<bundle id> ...]
"""
import base64
import hashlib
import os
import re
import subprocess
import sys

from asc_testflight import errors
import asc_testflight

PROFILES_DIR = os.path.expanduser("~/Library/MobileDevice/Provisioning Profiles")


def keychain_identities() -> set:
    output = subprocess.run(["security", "find-identity", "-v", "-p", "codesigning"],
                            capture_output=True, text=True).stdout
    found = set(re.findall(r"\b([0-9A-F]{40})\b", output))
    names = re.findall(r'"([^"]+)"', output)
    print(f"Подписывающих сертификатов в keychain: {len(found)} ({', '.join(n.split(':')[0] for n in names)})")
    return found


def find_certificates(identities: set) -> list:
    """Сертификаты Distribution для профиля: совпадающий с keychain, а если keychain пуст — все действующие."""
    status, certs = asc_testflight.call("GET", "/v1/certificates", query={
        "filter[certificateType]": "DISTRIBUTION,IOS_DISTRIBUTION", "limit": 200})
    if status != 200:
        raise SystemExit(f"❌ Не удалось получить сертификаты ({status}: {errors(certs)})")
    chosen = []
    for cert in certs["data"]:
        attrs = cert["attributes"]
        content = attrs.get("certificateContent")
        if not content:
            continue
        digest = hashlib.sha1(base64.b64decode(content)).hexdigest().upper()
        if not identities or digest in identities:
            print(f"Сертификат: {attrs.get('name')} (до {attrs.get('expirationDate', '')[:10]})")
            chosen.append(cert["id"])
    if not chosen:
        raise SystemExit("❌ Подходящий сертификат Distribution не найден в App Store Connect")
    return chosen


def bundle_resource(identifier: str) -> str:
    status, result = asc_testflight.call("GET", "/v1/bundleIds", query={
        "filter[identifier]": identifier, "filter[platform]": "IOS", "limit": 50})
    if status != 200:
        raise SystemExit(f"❌ Bundle ID {identifier}: {status} {errors(result)}")
    for item in result["data"]:
        if item["attributes"]["identifier"] == identifier:
            return item["id"]
    raise SystemExit(f"❌ Bundle ID {identifier} не зарегистрирован в Apple Developer")


def profile_for(identifier: str, bundle_id: str, cert_ids: list) -> dict:
    name = f"FOLIO {identifier} App Store"
    status, existing = asc_testflight.call("GET", "/v1/profiles", query={
        "filter[name]": name, "filter[profileType]": "IOS_APP_STORE", "limit": 20})
    if status == 200:
        for profile in existing["data"]:
            if profile["attributes"].get("profileState") != "ACTIVE":
                continue
            status, certs = asc_testflight.call("GET", f"/v1/profiles/{profile['id']}/certificates", query={"limit": 50})
            if status == 200 and set(cert_ids) <= {c["id"] for c in certs["data"]}:
                print(f"Профиль «{name}» уже есть")
                return profile
            # Профиль с другим сертификатом — удаляем, чтобы не плодить дубликаты.
            asc_testflight.call("DELETE", f"/v1/profiles/{profile['id']}")
    status, created = asc_testflight.call("POST", "/v1/profiles", body={"data": {
        "type": "profiles",
        "attributes": {"name": name, "profileType": "IOS_APP_STORE"},
        "relationships": {
            "bundleId": {"data": {"type": "bundleIds", "id": bundle_id}},
            "certificates": {"data": [{"type": "certificates", "id": c} for c in cert_ids]}}}})
    if status not in (200, 201):
        raise SystemExit(f"❌ Не удалось создать профиль «{name}» ({status}: {errors(created)})")
    print(f"✅ Создан профиль «{name}»")
    return created["data"]


def save(profile: dict) -> None:
    os.makedirs(PROFILES_DIR, exist_ok=True)
    content = base64.b64decode(profile["attributes"]["profileContent"])
    uuid = profile["attributes"].get("uuid") or profile["id"]
    with open(os.path.join(PROFILES_DIR, f"{uuid}.mobileprovision"), "wb") as handle:
        handle.write(content)
    entitlements = "App Groups" if b"com.apple.security.application-groups" in content else "без App Groups"
    print(f"   сохранён {uuid}.mobileprovision ({entitlements})")


def main() -> int:
    asc_testflight.TOKEN = asc_testflight.token()
    identities = keychain_identities()
    cert_ids = find_certificates(identities)
    for identifier in sys.argv[1:]:
        bundle_id = bundle_resource(identifier)
        save(profile_for(identifier, bundle_id, cert_ids))
    return 0


if __name__ == "__main__":
    sys.exit(main())
