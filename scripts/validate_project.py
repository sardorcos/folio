#!/usr/bin/env python3
"""Static checks runnable on Linux; not a substitute for xcodebuild on macOS."""
import json
import subprocess
from pathlib import Path
import xml.etree.ElementTree as ET
from html.parser import HTMLParser
root=Path(__file__).resolve().parent.parent
swift_files=sorted(root.glob('FOLIO/**/*.swift'))+sorted(root.glob('FOLIOTests/**/*.swift'))
issues=[]
for file in swift_files:
    p=subprocess.run(['swiftc','-frontend','-parse',str(file)],capture_output=True,text=True)
    if p.returncode!=0:issues.append(f'{file.relative_to(root)}: {p.stderr[:400]}')
pbx=root/'FOLIO.xcodeproj/project.pbxproj'
p=subprocess.run(['plutil','-lint',str(pbx)],capture_output=True,text=True)
if p.returncode:issues.append('Invalid pbxproj: '+p.stderr)
j=subprocess.run(['plutil','-convert','json','-o','-',str(pbx)],capture_output=True,text=True)
try:
    project=json.loads(j.stdout); objects=project['objects']
    for obj in objects.values():
        if obj.get('isa')=='PBXFileReference' and obj.get('sourceTree')=='<group>':
            path=obj.get('path','')
            if path and not (root/path).exists():issues.append('Missing referenced file: '+path)
    source_refs=sum(1 for o in objects.values() if o.get('isa')=='PBXFileReference' and o.get('lastKnownFileType')=='sourcecode.swift')
except Exception as exc:
    issues.append('Cannot read pbxproj objects: '+str(exc)); source_refs=0
try:ET.parse(root/'FOLIO.xcodeproj/xcshareddata/xcschemes/FOLIO.xcscheme')
except Exception as exc:issues.append('Invalid scheme: '+str(exc))
for f in (root/'FOLIO/Resources/Assets.xcassets').rglob('Contents.json'):
    try:json.loads(f.read_text())
    except Exception as exc:issues.append('Invalid asset catalog JSON '+str(f)+': '+str(exc))
class H(HTMLParser):
    def __init__(self):super().__init__();self.buttons=0
    def handle_starttag(self,t,a):
        if t=='button':self.buttons+=1
parser=H();parser.feed((root/'Preview/FOLIO_UI_preview.html').read_text())
if parser.buttons<10:issues.append('HTML preview does not have enough functional controls')
expected=['PDF, фото и сканы','Объединить PDF','Фото в PDF','Изменить страницы','Уменьшить размер','Добавить файлы','Сканировать']
html=(root/'Preview/FOLIO_UI_preview.html').read_text()
for x in expected:
    if x not in html:issues.append('Missing first screen message: '+x)
status={'swift_files_parsed':len(swift_files),'xcode_source_refs':source_refs,'xcode_objects':len(objects) if 'objects' in locals() else None,'preview_buttons':parser.buttons,'issues':issues,'xcodebuild_executed':False,'swift_typecheck_executed':False,'ios_device_tested':False}
(root/'VALIDATION.json').write_text(json.dumps(status,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(status,ensure_ascii=False,indent=2))
raise SystemExit(bool(issues))
