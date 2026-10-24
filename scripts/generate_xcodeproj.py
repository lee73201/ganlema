#!/usr/bin/env python3
"""Regenerate the dependency-free Xcode app, static framework, and test targets."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
objects = {}

def ident(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()

def add(key, isa, **fields):
    value = ident(key)
    objects[value] = dict(isa=isa, **fields)
    return value

def serialize(value, level=0):
    if isinstance(value, dict):
        return "{\n" + "".join("\t" * (level + 1) + str(k) + " = " + serialize(v, level + 1) + ";\n" for k, v in value.items()) + "\t" * level + "}"
    if isinstance(value, list):
        return "(" + ", ".join(serialize(v, level) for v in value) + ")"
    return json.dumps(str(value), ensure_ascii=False)

products = {}
targets = {}
for name, ext, kind in [("FocusDockCore", "framework", "wrapper.framework"), ("FocusDock", "app", "wrapper.application"), ("FocusDockCoreTests", "xctest", "wrapper.cfbundle")]:
    products[name] = add(name + ".product", "PBXFileReference", explicitFileType=kind, path=f"{'干了吗' if name == 'FocusDock' else name}.{ext}", sourceTree="BUILT_PRODUCTS_DIR")
    targets[name] = ident(name + ".target")

groups = []
target_sources = {}
for name, folder in [("FocusDockCore", "Sources/FocusDockCore"), ("FocusDock", "Sources/FocusDockApp"), ("FocusDockCoreTests", "Tests/FocusDockCoreTests")]:
    refs, builds = [], []
    for file in sorted((ROOT / folder).rglob("*.swift")):
        path = file.relative_to(ROOT).as_posix()
        ref = add(path, "PBXFileReference", lastKnownFileType="sourcecode.swift", path=path, sourceTree="SOURCE_ROOT")
        refs.append(ref)
        builds.append(add(path + ".build", "PBXBuildFile", fileRef=ref))
    target_sources[name] = add(name + ".sources", "PBXSourcesBuildPhase", buildActionMask="2147483647", files=builds, runOnlyForDeploymentPostprocessing="0")
    groups.append(add(name + ".group", "PBXGroup", name=name, children=refs, sourceTree="<group>"))

plist = add("Info.plist", "PBXFileReference", lastKnownFileType="text.plist.xml", path="Resources/Info.plist", sourceTree="SOURCE_ROOT")
groups.append(plist)
product_group = add("Products", "PBXGroup", name="Products", children=list(products.values()), sourceTree="<group>")
groups.append(product_group)
main_group = add("MainGroup", "PBXGroup", children=groups, sourceTree="<group>")

def configs(key, settings):
    ids = []
    for mode in ["Debug", "Release"]:
        cfg = settings.copy()
        if key == "project":
            cfg.update(SWIFT_OPTIMIZATION_LEVEL="-Onone" if mode == "Debug" else "-O", DEBUG_INFORMATION_FORMAT="dwarf" if mode == "Debug" else "dwarf-with-dsym")
            if mode == "Debug":
                cfg.update(ENABLE_TESTABILITY="YES", SWIFT_ACTIVE_COMPILATION_CONDITIONS="DEBUG")
        ids.append(add(key + "." + mode, "XCBuildConfiguration", name=mode, buildSettings=cfg))
    return add(key + ".configs", "XCConfigurationList", buildConfigurations=ids, defaultConfigurationIsVisible="0", defaultConfigurationName="Release")

project_configs = configs("project", dict(MACOSX_DEPLOYMENT_TARGET="14.0", SDKROOT="macosx", SWIFT_VERSION="5.0", CLANG_ENABLE_MODULES="YES", CODE_SIGN_STYLE="Automatic", CODE_SIGN_IDENTITY="-"))

for name in targets:
    frameworks, dependencies = [], []
    if name != "FocusDockCore":
        frameworks.append(add(name + ".linkcore", "PBXBuildFile", fileRef=products["FocusDockCore"]))
        proxy = add(name + ".proxy", "PBXContainerItemProxy", containerPortal=ident("project"), proxyType="1", remoteGlobalIDString=targets["FocusDockCore"], remoteInfo="FocusDockCore")
        dependencies.append(add(name + ".dependency", "PBXTargetDependency", target=targets["FocusDockCore"], targetProxy=proxy))
    phase = add(name + ".frameworks", "PBXFrameworksBuildPhase", buildActionMask="2147483647", files=frameworks, runOnlyForDeploymentPostprocessing="0")
    settings = dict(PRODUCT_NAME=name, PRODUCT_BUNDLE_IDENTIFIER="local.focusdock." + name.lower(), GENERATE_INFOPLIST_FILE="YES")
    if name == "FocusDockCore":
        settings.update(MACH_O_TYPE="staticlib", DEFINES_MODULE="YES", SKIP_INSTALL="YES")
        product_type = "com.apple.product-type.framework"
    elif name == "FocusDock":
        settings.update(PRODUCT_NAME="干了吗", EXECUTABLE_NAME="FocusDock", PRODUCT_MODULE_NAME="FocusDock", INFOPLIST_FILE="Resources/Info.plist", GENERATE_INFOPLIST_FILE="NO", PRODUCT_BUNDLE_IDENTIFIER="local.focusdock.app", ENABLE_APP_SANDBOX="NO", LD_RUNPATH_SEARCH_PATHS="$(inherited) @executable_path/../Frameworks")
        product_type = "com.apple.product-type.application"
    else:
        settings.update(CODE_SIGNING_ALLOWED="NO", LD_RUNPATH_SEARCH_PATHS="$(inherited) @loader_path/../Frameworks")
        product_type = "com.apple.product-type.bundle.unit-test"
    add(name + ".target", "PBXNativeTarget", name=name, productName=name, productReference=products[name], productType=product_type, buildConfigurationList=configs(name, settings), buildPhases=[target_sources[name], phase], buildRules=[], dependencies=dependencies)

project_id = add("project", "PBXProject", attributes=dict(LastUpgradeCheck="1600"), buildConfigurationList=project_configs, compatibilityVersion="Xcode 14.0", developmentRegion="zh_CN", knownRegions=["zh_CN", "en", "Base"], mainGroup=main_group, productRefGroup=product_group, projectDirPath="", projectRoot="", targets=list(targets.values()))
project = ROOT / "FocusDock.xcodeproj"
project.mkdir(exist_ok=True)
(project / "project.pbxproj").write_text("// !$*UTF8*$!\n" + serialize(dict(archiveVersion="1", classes={}, objectVersion="56", objects=objects, rootObject=project_id)) + "\n")

scheme_dir = project / "xcshareddata/xcschemes"
scheme_dir.mkdir(parents=True, exist_ok=True)
def reference(name):
    extension = "app" if name == "FocusDock" else "xctest"
    display_name = "干了吗" if name == "FocusDock" else name
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{targets[name]}" BuildableName="{display_name}.{extension}" BlueprintName="{name}" ReferencedContainer="container:FocusDock.xcodeproj"/>'
(scheme_dir / "FocusDock.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
    <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference("FocusDock")}</BuildActionEntry>
  </BuildActionEntries></BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{reference("FocusDockCoreTests")}</TestableReference></Testables></TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference("FocusDock")}</BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference("FocusDock")}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
print(project)
