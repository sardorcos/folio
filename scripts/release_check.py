#!/usr/bin/env python3
"""Статическая проверка готовности FOLIO к сборке и отправке в App Store.

Запуск из корня проекта:  python3 scripts/release_check.py
Не заменяет сборку в Xcode и тесты — проверяет структуру проекта и то, что забывают перед релизом.
Код выхода 1 — есть ошибки; предупреждения (⚠️) не блокируют, но их нужно закрыть перед отправкой.
"""
import json
import plistlib
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
errors, warnings = [], []


def parse_pbxproj(text):
    """Минимальный разбор формата OpenStep plist, которым записан project.pbxproj."""
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    text = re.sub(r'^//.*$', '', text, flags=re.M)
    pos = 0
    token = re.compile(r'[A-Za-z0-9_$./\-+]+')

    def skip():
        nonlocal pos
        while pos < len(text) and text[pos].isspace():
            pos += 1

    def value():
        nonlocal pos
        skip()
        ch = text[pos]
        if ch == '{':
            pos += 1
            result = {}
            while True:
                skip()
                if text[pos] == '}':
                    pos += 1
                    return result
                key = value()
                skip()
                assert text[pos] == '=', f'ожидался "=" на позиции {pos}'
                pos += 1
                result[key] = value()
                skip()
                assert text[pos] == ';', f'ожидался ";" на позиции {pos}'
                pos += 1
        if ch == '(':
            pos += 1
            items = []
            while True:
                skip()
                if text[pos] == ')':
                    pos += 1
                    return items
                items.append(value())
                skip()
                if text[pos] == ',':
                    pos += 1
        if ch == '"':
            pos += 1
            out = ''
            while text[pos] != '"':
                if text[pos] == '\\':
                    out += text[pos + 1]
                    pos += 2
                else:
                    out += text[pos]
                    pos += 1
            pos += 1
            return out
        match = token.match(text, pos)
        assert match, f'непонятный токен на позиции {pos}'
        pos = match.end()
        return match.group()

    return value()


def check_project():
    path = ROOT / 'FOLIO.xcodeproj/project.pbxproj'
    try:
        project = parse_pbxproj(path.read_text(encoding='utf-8'))
    except Exception as exc:  # noqa: BLE001
        errors.append(f'project.pbxproj не разбирается: {exc}')
        return
    objects = project['objects']

    def refs(node):
        if isinstance(node, str) and re.fullmatch(r'[0-9A-F]{24}', node):
            yield node
        elif isinstance(node, dict):
            for item in node.values():
                yield from refs(item)
        elif isinstance(node, list):
            for item in node:
                yield from refs(item)

    for key, obj in objects.items():
        for ref in refs(obj):
            if ref not in objects:
                errors.append(f'pbxproj: объект {key} ссылается на несуществующий {ref}')
    for obj in objects.values():
        if obj.get('isa') == 'PBXFileSystemSynchronizedRootGroup' and not (ROOT / obj['path']).is_dir():
            errors.append(f'pbxproj: нет папки {obj["path"]}')
    configs = [o.get('buildSettings', {}) for o in objects.values() if o.get('isa') == 'XCBuildConfiguration']
    bundle_ids = {c['FOLIO_APP_BUNDLE_ID'] for c in configs if 'FOLIO_APP_BUNDLE_ID' in c}
    if not bundle_ids:
        errors.append('pbxproj: не задан FOLIO_APP_BUNDLE_ID (уровень проекта)')
    elif any(b.startswith('com.example') for b in bundle_ids):
        warnings.append(f'FOLIO_APP_BUNDLE_ID = {", ".join(sorted(bundle_ids))} — замените на свой '
                        '(Build Settings проекта; App Group станет group.<bundle id>)')
    app = [c for c in configs if 'ASSETCATALOG_COMPILER_APPICON_NAME' in c]
    share = [c for c in configs if c.get('INFOPLIST_FILE', '').endswith('FOLIOShare-Info.plist')]
    if app and not app[0].get('DEVELOPMENT_TEAM'):
        warnings.append('DEVELOPMENT_TEAM не задан — выберите Team для FOLIO, FOLIOShare и FOLIOTests')
    if not share:
        errors.append('pbxproj: нет target расширения FOLIOShare')
    for key in ('MARKETING_VERSION', 'CURRENT_PROJECT_VERSION'):
        values = {c.get(key) for c in app + share}
        if len(values) > 1:
            errors.append(f'{key} у приложения и расширения должны совпадать, сейчас: {sorted(map(str, values))}')
    expected = {'FOLIO': '$(FOLIO_APP_BUNDLE_ID)', 'FOLIOShare': '$(FOLIO_APP_BUNDLE_ID).share'}
    for name, group in (('FOLIO', app), ('FOLIOShare', share)):
        for config in group:
            if config.get('PRODUCT_BUNDLE_IDENTIFIER') != expected[name]:
                warnings.append(f'{name}: Bundle ID «{config.get("PRODUCT_BUNDLE_IDENTIFIER")}» не по схеме '
                                f'{expected[name]} — App Group может не совпасть')
                break


def check_resources():
    for path in (ROOT / 'FOLIO').rglob('Contents.json'):
        try:
            json.loads(path.read_text(encoding='utf-8'))
        except Exception as exc:  # noqa: BLE001
            errors.append(f'{path.relative_to(ROOT)}: неверный JSON ({exc})')
    icon = ROOT / 'FOLIO/Resources/Assets.xcassets/AppIcon.appiconset'
    contents = json.loads((icon / 'Contents.json').read_text(encoding='utf-8'))
    files = [img.get('filename') for img in contents['images'] if img.get('filename')]
    if not files or not all((icon / name).exists() for name in files):
        errors.append('AppIcon: нет файла иконки 1024×1024')
    else:
        try:
            from PIL import Image  # необязательная зависимость
            with Image.open(icon / files[0]) as image:
                if image.size != (1024, 1024):
                    errors.append(f'AppIcon: размер {image.size}, нужен 1024×1024')
                if 'A' in image.getbands():
                    errors.append('AppIcon: у иконки App Store не должно быть альфа-канала')
        except ImportError:
            pass
    warnings.append('AppIcon — временная иконка. Перед релизом замените её финальной (1024×1024, без прозрачности)')
    try:
        manifest = plistlib.loads((ROOT / 'FOLIO/Resources/PrivacyInfo.xcprivacy').read_bytes())
        if manifest.get('NSPrivacyTracking') is not False:
            errors.append('PrivacyInfo: NSPrivacyTracking должен быть false')
    except Exception as exc:  # noqa: BLE001
        errors.append(f'PrivacyInfo.xcprivacy: {exc}')
    for name in ('FOLIO.entitlements', 'FOLIOShare.entitlements'):
        try:
            entitlements = plistlib.loads((ROOT / 'Config' / name).read_bytes())
            groups = entitlements.get('com.apple.security.application-groups', [])
            if groups != ['group.$(FOLIO_APP_BUNDLE_ID)']:
                errors.append(f'Config/{name}: App Group должна быть group.$(FOLIO_APP_BUNDLE_ID)')
        except Exception as exc:  # noqa: BLE001
            errors.append(f'Config/{name}: {exc}')
    try:
        extension = plistlib.loads((ROOT / 'Config/FOLIOShare-Info.plist').read_bytes())['NSExtension']
        if extension.get('NSExtensionPointIdentifier') != 'com.apple.share-services':
            errors.append('FOLIOShare-Info.plist: неверный NSExtensionPointIdentifier')
        rule = extension.get('NSExtensionAttributes', {}).get('NSExtensionActivationRule')
        if not isinstance(rule, str) or 'TRUEPREDICATE' in rule:
            errors.append('FOLIOShare-Info.plist: нужно правило активации (TRUEPREDICATE App Store не принимает)')
    except Exception as exc:  # noqa: BLE001
        errors.append(f'Config/FOLIOShare-Info.plist: {exc}')
    try:
        catalog = json.loads((ROOT / 'FOLIO/Resources/Localizable.xcstrings').read_text(encoding='utf-8'))
        for key in ('%lld страниц', '%lld документов', '%lld файлов'):
            plural = catalog['strings'][key]['localizations']['ru']['variations']['plural']
            if set(plural) != {'one', 'few', 'many', 'other'}:
                errors.append(f'Localizable.xcstrings: у «{key}» должны быть формы one/few/many/other')
    except Exception as exc:  # noqa: BLE001
        errors.append(f'Localizable.xcstrings: {exc}')


def check_sources():
    swift_files = sorted(p for folder in ('FOLIO', 'Shared', 'FOLIOShare', 'FOLIOTests')
                         for p in ROOT.glob(f'{folder}/**/*.swift'))
    swiftc = shutil.which('swiftc')
    for path in swift_files:
        text = path.read_text(encoding='utf-8')
        if 'Демонстрационный' in text:
            errors.append(f'{path.relative_to(ROOT)}: остался демонстрационный текст')
        if swiftc:
            result = subprocess.run([swiftc, '-frontend', '-parse', str(path)], capture_output=True, text=True)
            if result.returncode:
                errors.append(f'{path.relative_to(ROOT)}: синтаксическая ошибка\n{result.stderr[:400]}')
    if not swiftc:
        warnings.append('swiftc не найден — синтаксис Swift не проверялся (на Mac он есть вместе с Xcode)')
    config = (ROOT / 'FOLIO/App/AppConfig.swift').read_text(encoding='utf-8')
    if 'example.com' in config:
        warnings.append('AppConfig.swift: укажите реальные privacyPolicyURL и supportEmail')


check_project()
check_resources()
check_sources()

for message in warnings:
    print('⚠️ ', message)
for message in errors:
    print('❌', message)
if not errors:
    print('✅ Структура проекта в порядке.' + (' Закройте предупреждения перед отправкой.' if warnings else ''))
sys.exit(1 if errors else 0)
