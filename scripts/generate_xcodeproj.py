#!/usr/bin/env python3
"""Generate a deterministic basic Xcode 15+ iOS app project without external dependencies."""
from pathlib import Path
from hashlib import sha1
R=Path(__file__).resolve().parent.parent
project=R/'FOLIO.xcodeproj'; project.mkdir(exist_ok=True)
sources=sorted((R/'FOLIO').rglob('*.swift'))
assets='FOLIO/Resources/Assets.xcassets'
tests=sorted((R/'FOLIOTests').glob('*.swift'))

def uid(k): return sha1(k.encode()).hexdigest()[:24].upper()
def s(v): return '"'+str(v).replace('\\','\\\\').replace('"','\\"')+'"'
entries={}
def add(key, comment, body): entries[uid(key)]=(comment,body)

appTarget='TARGET.APP'; testTarget='TARGET.TEST'
projectKey='PROJECT'; mainGroup='GROUP.MAIN'; productsGroup='GROUP.PRODUCTS'
appSource='PHASE.APP.SOURCES'; appResource='PHASE.APP.RESOURCES'; appFrameworks='PHASE.APP.FRAMEWORKS'
testSource='PHASE.TEST.SOURCES'; testFrameworks='PHASE.TEST.FRAMEWORKS'
appConfigList='CONFIG.APP'; testConfigList='CONFIG.TEST'; projectConfigList='CONFIG.PROJECT'
appProduct='PRODUCT.APP'; testProduct='PRODUCT.TEST'

for filepath in sources+tests:
    rel=filepath.relative_to(R).as_posix()
    add('FILE.'+rel,filepath.name,f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {s(rel)}; sourceTree = "<group>";')
    add('BUILD.'+rel,filepath.name+' in Sources',f'isa = PBXBuildFile; fileRef = {uid("FILE."+rel)} /* {filepath.name} */;')
add('FILE.'+assets,'Assets.xcassets',f'isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = {s(assets)}; sourceTree = "<group>";')
add('BUILD.'+assets,'Assets in Resources',f'isa = PBXBuildFile; fileRef = {uid("FILE."+assets)} /* Assets.xcassets */;')
add(appProduct,'FOLIO.app','isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = FOLIO.app; sourceTree = BUILT_PRODUCTS_DIR;')
add(testProduct,'FOLIOTests.xctest','isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = FOLIOTests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
add(productsGroup,'Products','isa = PBXGroup; children = ('+','.join(f'{uid(k)} /* {label} */' for k,label in [(appProduct,'FOLIO.app'),(testProduct,'FOLIOTests.xctest')])+',); name = Products; sourceTree = "<group>";')
groupChildren=[(f'FILE.{f.relative_to(R).as_posix()}',f.name) for f in sources+tests]
groupChildren.append(('FILE.'+assets,'Assets.xcassets'))
groupChildren.append((productsGroup,'Products'))
add(mainGroup,'Main Group','isa = PBXGroup; children = ('+''.join(f'{uid(k)} /* {n} */, ' for k,n in groupChildren)+'); sourceTree = "<group>";')

add(appSource,'Sources','isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ('+''.join(f'{uid("BUILD."+f.relative_to(R).as_posix())} /* {f.name} in Sources */, ' for f in sources)+'); runOnlyForDeploymentPostprocessing = 0;')
add(testSource,'Tests Sources','isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ('+''.join(f'{uid("BUILD."+f.relative_to(R).as_posix())} /* {f.name} in Sources */, ' for f in tests)+'); runOnlyForDeploymentPostprocessing = 0;')
add(appResource,'Resources','isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ('+f'{uid("BUILD."+assets)} /* Assets.xcassets in Resources */'+',); runOnlyForDeploymentPostprocessing = 0;')
for k in [appFrameworks,testFrameworks]:add(k,'Frameworks','isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')

appConfigs=[]; testConfigs=[]; projectConfigs=[]
for name in ['Debug','Release']:
    flag='YES' if name=='Debug' else 'NO'
    pk='PROJECT.'+name
    add(pk,name,f'isa = XCBuildConfiguration; buildSettings = {{ ALWAYS_SEARCH_USER_PATHS = NO; CLANG_ENABLE_MODULES = YES; CODE_SIGN_STYLE = Automatic; IPHONEOS_DEPLOYMENT_TARGET = 17.0; SDKROOT = iphoneos; SWIFT_VERSION = 5.9; SWIFT_OPTIMIZATION_LEVEL = {s("-Onone" if name=="Debug" else "-O")}; }}; name = {name};')
    projectConfigs.append(pk)
    ak='APP.'+name
    appSettings=(
        'ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES; '
        'CODE_SIGN_STYLE = Automatic; CURRENT_PROJECT_VERSION = 4; '
        'GENERATE_INFOPLIST_FILE = YES; '
        'INFOPLIST_KEY_CFBundleDisplayName = FOLIO; '
        'INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.productivity"; '
        'INFOPLIST_KEY_NSCameraUsageDescription = "Сканируйте бумажные документы, чтобы сохранить их как PDF."; '
        'INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES; '
        'INFOPLIST_KEY_UILaunchScreen_Generation = YES; '
        'IPHONEOS_DEPLOYMENT_TARGET = 17.0; '
        'MARKETING_VERSION = 0.4.0; '
        'PRODUCT_BUNDLE_IDENTIFIER = com.example.folio.documents; '
        'PRODUCT_NAME = "$(TARGET_NAME)"; '
        'SWIFT_EMIT_LOC_STRINGS = YES; '
        'SWIFT_VERSION = 5.9; '
        'TARGETED_DEVICE_FAMILY = "1"; '
    )
    add(ak,name,f'isa = XCBuildConfiguration; buildSettings = {{{appSettings}}}; name = {name};')
    appConfigs.append(ak)
    tk='TEST.'+name
    testSettings=(
        'BUNDLE_LOADER = "$(TEST_HOST)"; CODE_SIGN_STYLE = Automatic; '
        'GENERATE_INFOPLIST_FILE = YES; '
        'IPHONEOS_DEPLOYMENT_TARGET = 17.0; '
        'PRODUCT_BUNDLE_IDENTIFIER = com.example.folio.documents.tests; '
        'PRODUCT_NAME = "$(TARGET_NAME)"; '
        'SWIFT_VERSION = 5.9; '
        'TARGETED_DEVICE_FAMILY = "1"; '
        'TEST_HOST = "$(BUILT_PRODUCTS_DIR)/FOLIO.app/FOLIO"; '
    )
    add(tk,name,f'isa = XCBuildConfiguration; buildSettings = {{{testSettings}}}; name = {name};')
    testConfigs.append(tk)
for k,lst in [(projectConfigList,projectConfigs),(appConfigList,appConfigs),(testConfigList,testConfigs)]:
    add(k,'Build configuration list', 'isa = XCConfigurationList; buildConfigurations = ('+''.join(f'{uid(x)} /* {x.rsplit(".",1)[-1]} */, ' for x in lst)+'); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')

add(appTarget,'FOLIO','isa = PBXNativeTarget; buildConfigurationList = '+uid(appConfigList)+' /* Build configuration list */; buildPhases = ('+f'{uid(appSource)} /* Sources */, {uid(appFrameworks)} /* Frameworks */, {uid(appResource)} /* Resources */'+'); buildRules = (); dependencies = (); name = FOLIO; productName = FOLIO; productReference = '+uid(appProduct)+' /* FOLIO.app */; productType = "com.apple.product-type.application";')
add(testTarget,'FOLIOTests','isa = PBXNativeTarget; buildConfigurationList = '+uid(testConfigList)+' /* Build configuration list */; buildPhases = ('+f'{uid(testSource)} /* Sources */, {uid(testFrameworks)} /* Frameworks */'+'); buildRules = (); dependencies = (); name = FOLIOTests; productName = FOLIOTests; productReference = '+uid(testProduct)+' /* FOLIOTests.xctest */; productType = "com.apple.product-type.bundle.unit-test";')
add(projectKey,'Project object','isa = PBXProject; attributes = { BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 1600; TargetAttributes = {'+f'{uid(appTarget)} = {{ CreatedOnToolsVersion = 15.0; }}; {uid(testTarget)} = {{ CreatedOnToolsVersion = 15.0; TestTargetID = {uid(appTarget)}; }}; '+'}; }; buildConfigurationList = '+uid(projectConfigList)+' /* Build configuration list */; compatibilityVersion = "Xcode 14.0"; developmentRegion = ru; hasScannedForEncodings = 0; knownRegions = (ru, en, Base); mainGroup = '+uid(mainGroup)+' /* Main Group */; productRefGroup = '+uid(productsGroup)+' /* Products */; projectDirPath = ""; projectRoot = ""; targets = ('+f'{uid(appTarget)} /* FOLIO */, {uid(testTarget)} /* FOLIOTests */'+');')

pbx=['// !$*UTF8*$!','{','\tarchiveVersion = 1;','\tclasses = {};','\tobjectVersion = 56;','\tobjects = {']
for ident,(comment,body) in entries.items(): pbx.append(f'\t\t{ident} /* {comment} */ = {{ {body} }};')
pbx.extend(['\t};',f'\trootObject = {uid(projectKey)} /* Project object */;','}'])
(project/'project.pbxproj').write_text('\n'.join(pbx)+'\n')
print(f'Generated Xcode project: {len(entries)} objects, {len(sources)} app source files, {len(tests)} test source files.')
