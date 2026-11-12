#!/usr/bin/env bash
# Tests the iOS toolchain checks of Issue #70 without Xcode or macOS (it runs on the `plan` job
# of build-variants.yml, and locally):
#
#   1. tool/macho_info.py            the Mach-O reader, on synthetic binaries and the committed
#                                    Rust library
#   2. tool/verify_artifact.sh ios   the built-app toolchain verification, on synthetic Runner.app
#                                    bundles: the SDK recorded in Info.plist and in the executable,
#                                    the declared minimum OS, the embedded frameworks
#   3. tool/verify_ios_toolchain.sh  the pins shared by the two iOS workflows, the Podfile.lock
#                                    rules and the deployment targets, plus mutations of each rule
#   4. tool/check_build_drift.sh     Podfile.lock drift (or any tracked file changed by a build)
#                                    fails, on throwaway git repositories
#
#   tool/test_ios_toolchain.sh
#
# (No `grep -q` at the end of a pipeline: under pipefail an early-closed pipe is a SIGPIPE failure.)
# Version independent: nothing here assumes the application version (the synthetic app takes it
# from pubspec.yaml). Needs bash, python3, git, sed and grep. Exit 0 only if every check passes.
# shellcheck disable=SC2016
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
macho="$root/tool/macho_info.py"
verify_artifact="$root/tool/verify_artifact.sh"
verify_toolchain="$root/tool/verify_ios_toolchain.sh"
check_drift="$root/tool/check_build_drift.sh"

pass=0
failed=0
ok() { pass=$((pass + 1)); echo "ok   $1"; }
bad() { failed=$((failed + 1)); echo "FAIL $1"; [ -z "${2:-}" ] || echo "     $2"; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# --- fixture builders (python, standard library only) --------------------------------------
cat >"$tmp/mk.py" <<'PYEOF'
import plistlib, struct, sys

def ver(s):
    parts = [int(x) for x in s.split(".")] + [0, 0]
    return (parts[0] << 16) | (parts[1] << 8) | parts[2]

PLATFORM = {"ios": 2, "ios-simulator": 7, "macos": 1}
CPU = {"arm64": 0x0100000C, "x86_64": 0x01000007}

def thin(arch, platform, minos, sdk, form="build"):
    """A minimal 64-bit Mach-O: header plus one version load command."""
    if form == "build":
        cmd = struct.pack("<IIIIII", 0x32, 24, PLATFORM[platform], ver(minos), ver(sdk) if sdk else 0, 0)
    else:  # LC_VERSION_MIN_IPHONEOS
        cmd = struct.pack("<IIII", 0x25, 16, ver(minos), ver(sdk) if sdk else 0)
    return struct.pack("<IiiIIIII", 0xFEEDFACF, CPU[arch], 0, 2, 1, len(cmd), 0, 0) + cmd

def fat(slices):
    out, off = b"", 8 + 20 * len(slices)
    head = struct.pack(">II", 0xCAFEBABE, len(slices))
    body = b""
    for arch, data in slices:
        off = (off + 15) & ~15
        head += struct.pack(">iiIII", CPU[arch], 0, off, len(data), 4)
        body += b"\0" * (off - 8 - 20 * len(slices) - len(body)) + data
        off += len(data)
    return head + body

def ar(members):
    out = b"!<arch>\n"
    for name, data in members:
        out += (name.ljust(16) + "0".ljust(12) + "0".ljust(6) + "0".ljust(6) + "100644".ljust(8)
                + str(len(data)).ljust(10) + "`\n").encode()
        out += data + (b"\n" if len(data) % 2 else b"")
    return out

def write(path, data):
    with open(path, "wb") as f:
        f.write(data)

def app(dest, a):
    """A synthetic Runner.app. a: dict of options."""
    import os
    os.makedirs(dest + "/Frameworks/App.framework", exist_ok=True)
    info = {
        "CFBundleIdentifier": a["bundle_id"], "CFBundleDisplayName": a["name"],
        "CFBundleShortVersionString": a["short"], "CFBundleVersion": a["build"],
        "CFBundleExecutable": "Runner",
    }
    for k in ("DTPlatformName", "DTSDKName", "DTPlatformVersion", "DTXcode", "DTXcodeBuild",
              "DTSDKBuild", "MinimumOSVersion"):
        if a.get(k) is not None:
            info[k] = a[k]
    with open(dest + "/Info.plist", "wb") as f:
        plistlib.dump(info, f)
    write(dest + "/Runner", thin("arm64", a["exe_platform"], a["exe_minos"], a["exe_sdk"]))
    write(dest + "/Frameworks/App.framework/App", ("\0" + a["url"] + "\0").encode())
    for fw in a.get("frameworks", []):
        d = dest + "/Frameworks/" + fw["name"] + ".framework"
        os.makedirs(d, exist_ok=True)
        with open(d + "/Info.plist", "wb") as f:
            plistlib.dump({"CFBundleExecutable": fw["name"]}, f)
        write(d + "/" + fw["name"], thin("arm64", fw["platform"], fw["minos"], fw["sdk"]))
PYEOF

mkthin() { python3 -I -c '
import sys; sys.path.insert(0, sys.argv[1]); import mk
_, _, _, out, arch, plat, minos, sdk, form = sys.argv
mk.write(out, mk.thin(arch, plat, minos, sdk if sdk != "-" else "", form))' "$tmp" _ "$@"; }

# --- 1. the Mach-O reader --------------------------------------------------------------------
echo "== macho_info.py"
mi() { python3 -I "$macho" "$@"; }
expect_line() { # NAME FILE "EXPECTED OUTPUT"
  local got; got="$(mi "$2" 2>&1)" || { bad "$1" "exit status $?: $got"; return; }
  [ "$got" = "$3" ] && ok "$1" || bad "$1" "got: $got"
}
mkthin "$tmp/t1" arm64 ios 14.0 26.2 build
expect_line "thin binary: LC_BUILD_VERSION, iOS 14.0 minimum, SDK 26.2" "$tmp/t1" "arch=arm64 platform=ios minos=14.0 sdk=26.2 count=1"
mkthin "$tmp/t2" arm64 ios 15.5 26.0 build
expect_line "thin binary: minor versions are read" "$tmp/t2" "arch=arm64 platform=ios minos=15.5 sdk=26.0 count=1"
mkthin "$tmp/t3" arm64 ios 10.0 - min
expect_line "old LC_VERSION_MIN_IPHONEOS form without an SDK reads sdk=n/a" "$tmp/t3" "arch=arm64 platform=ios minos=10.0 sdk=n/a count=1"
mkthin "$tmp/t4" x86_64 ios-simulator 18.5 18.5 build
expect_line "simulator platform is named" "$tmp/t4" "arch=x86_64 platform=ios-simulator minos=18.5 sdk=18.5 count=1"
python3 -I -c '
import sys; sys.path.insert(0, sys.argv[1]); import mk
mk.write(sys.argv[2], mk.fat([("x86_64", mk.thin("x86_64", "ios-simulator", "14.0", "26.2")), ("arm64", mk.thin("arm64", "ios", "14.0", "26.2"))]))
mk.write(sys.argv[3], mk.ar([("a.o", mk.thin("arm64", "ios", "10.0", "17.2")), ("b.o", mk.thin("arm64", "ios", "10.0", "17.2")), ("c.o", mk.thin("arm64", "ios", "18.5", "18.5")), ("README", b"not an object\n")]))
mk.write(sys.argv[4], mk.fat([("arm64", mk.ar([("a.o", mk.thin("arm64", "ios", "10.0", "17.2"))]))]))' "$tmp" "$tmp/fat" "$tmp/ar" "$tmp/fatar"
expect_line "fat binary: one line per architecture" "$tmp/fat" "arch=arm64 platform=ios minos=14.0 sdk=26.2 count=1
arch=x86_64 platform=ios-simulator minos=14.0 sdk=26.2 count=1"
expect_line "static library: objects are counted per combination, non-objects ignored" "$tmp/ar" "arch=arm64 platform=ios minos=10.0 sdk=17.2 count=2
arch=arm64 platform=ios minos=18.5 sdk=18.5 count=1"
expect_line "static library inside a fat file" "$tmp/fatar" "arch=arm64 platform=ios minos=10.0 sdk=17.2 count=1"
printf 'not a mach-o file\n' >"$tmp/text"
mi "$tmp/text" >/dev/null 2>&1 && bad "a text file is rejected" || ok "a text file is rejected"
head -c 40 "$tmp/t1" >"$tmp/trunc"
mi "$tmp/trunc" >/dev/null 2>&1 && bad "a truncated Mach-O is rejected" || ok "a truncated Mach-O is rejected"
mi "$tmp/does-not-exist" >/dev/null 2>&1 && bad "a missing file is rejected" || ok "a missing file is rejected"
live="$(mi "$root/flutter_plugin/flutter_plugin/ios/Classes/libdlcplazacryptlib.a" 2>&1)"
case "$live" in
  *"arch=arm64 platform=ios "*"arch=x86_64 "*) ok "the committed Rust library reads: an arm64 iOS slice and an x86_64 slice" ;;
  *) bad "the committed Rust library reads: an arm64 iOS slice and an x86_64 slice" "$live" ;;
esac

# --- 2. built-app toolchain verification -----------------------------------------------------
echo "== verify_artifact.sh ios (synthetic apps)"
pubspec_version="$(sed -n 's/^version:[[:space:]]*//p' "$root/pubspec.yaml" | head -n1 | tr -d '[:space:]')"
short="${pubspec_version%%+*}"; build="${pubspec_version##*+}"
STAGING_URL=https://staging.purabitcoin.com/app

# mkapp NAME [key=value ...]: overrides of the default (good) staging app
mkapp() {
  local name="$1"; shift
  python3 -I - "$tmp" "$tmp/app_$name" "$short" "$build" "$STAGING_URL" "$@" <<'PYEOF'
import sys, json, shutil, os
sys.path.insert(0, sys.argv[1]); import mk
dest, short, build, url = sys.argv[2:6]
a = {"bundle_id": "com.app.cadenabitcoin.staging", "name": "Cadena Signer STAGING", "short": short,
     "build": build, "url": url, "DTPlatformName": "iphoneos", "DTSDKName": "iphoneos26.2",
     "DTPlatformVersion": "26.2", "DTXcode": "2630", "DTXcodeBuild": "17C529", "DTSDKBuild": "23C53",
     "MinimumOSVersion": "14.0", "exe_platform": "ios", "exe_minos": "14.0", "exe_sdk": "26.2",
     "frameworks": [{"name": "Flutter", "platform": "ios", "minos": "13.0", "sdk": "18.5"}]}
for kv in sys.argv[6:]:
    k, v = kv.split("=", 1)
    if v == "__none__":
        a[k] = None
    elif k == "fw":                       # fw=NAME,PLATFORM,MINOS,SDK  (adds a framework)
        n, p, m, s = v.split(",")
        a["frameworks"].append({"name": n, "platform": p, "minos": m, "sdk": s})
    else:
        a[k] = v
shutil.rmtree(dest, ignore_errors=True)
mk.app(dest, a)
PYEOF
}
va() { # APP [args...] -> output in $VA_OUT, status returned
  local app="$1"; shift
  VA_OUT="$(bash "$verify_artifact" ios staging "$app" "$@" 2>&1)"; return $?
}
accepts() { # NAME APP [args...]
  local name="$1" app="$2"; shift 2
  if va "$app" "$@"; then ok "$name"; else bad "$name" "$(printf '%s' "$VA_OUT" | grep -E 'FAIL|ERROR' | head -n 4 | tr '\n' ' ')"; fi
}
rejects() { # NAME APP EXPECTED_TEXT [args...]
  local name="$1" app="$2" want="$3"; shift 3
  if va "$app" "$@"; then bad "$name" "the app was accepted"
  elif [[ "$VA_OUT" == *"$want"* ]]; then ok "$name"
  else bad "$name" "rejected, but not for '$want': $(printf '%s' "$VA_OUT" | grep -E 'FAIL|ERROR' | head -n 3 | tr '\n' ' ')"; fi
}

mkapp good
accepts "an app built with the iOS 26.2 SDK passes with --min-sdk 26" "$tmp/app_good" --min-sdk 26
case "$VA_OUT" in
  *"built_sdk_name=iphoneos26.2"*"executable_sdk=26.2"*) ok "the evidence records the SDK from Info.plist and from the executable" ;;
  *) bad "the evidence records the SDK from Info.plist and from the executable" "$VA_OUT" ;;
esac
case "$VA_OUT" in
  *"minimum_os_version=14.0"*"deployment_target_conflicts=0"*) ok "the evidence records the declared minimum OS and no conflicts" ;;
  *) bad "the evidence records the declared minimum OS and no conflicts" ;;
esac
accepts "without --min-sdk the SDK is only recorded" "$tmp/app_good"
accepts "--min-sdk 26 is the exact boundary (SDK 26.0)" "$(mkapp b26 DTSDKName=iphoneos26.0 DTPlatformVersion=26.0 exe_sdk=26.0; echo "$tmp/app_b26")" --min-sdk 26
rejects "--min-sdk 27 rejects an iOS 26.2 SDK app (Info.plist)" "$tmp/app_good" "Info.plist records the iOS 26.2 SDK; SDK 27 or later is required" --min-sdk 27

mkapp old DTSDKName=iphoneos18.5 DTPlatformVersion=18.5 DTXcode=1640 DTXcodeBuild=16F6 exe_sdk=18.5
rejects "an app built with the iOS 18.5 SDK is rejected (Info.plist)" "$tmp/app_old" "Info.plist records the iOS 18.5 SDK; SDK 26 or later is required" --min-sdk 26
rejects "an app built with the iOS 18.5 SDK is rejected (executable)" "$tmp/app_old" "was linked against the iOS 18.5 SDK; SDK 26 or later is required" --min-sdk 26
mkapp plistonly DTSDKName=iphoneos18.5 DTPlatformVersion=18.5
rejects "an executable on the iOS 26 SDK does not excuse an Info.plist from iOS 18.5" "$tmp/app_plistonly" "Info.plist records the iOS 18.5 SDK" --min-sdk 26
mkapp exeonly exe_sdk=18.5
rejects "an Info.plist claiming iOS 26 does not excuse an executable linked on iOS 18.5" "$tmp/app_exeonly" "executable slice arm64 was linked against the iOS 18.5 SDK" --min-sdk 26
mkapp nosdk DTSDKName=__none__
rejects "a missing DTSDKName is rejected" "$tmp/app_nosdk" "DTSDKName '' does not name an iPhoneOS SDK version" --min-sdk 26
mkapp junksdk DTSDKName=iphoneosXX
rejects "an unreadable DTSDKName is rejected" "$tmp/app_junksdk" "does not name an iPhoneOS SDK version" --min-sdk 26
mkapp sim exe_platform=ios-simulator
rejects "a simulator executable is rejected" "$tmp/app_sim" "built for 'ios-simulator', not iOS devices" --min-sdk 26
mkapp wrongplat DTPlatformName=iphonesimulator
rejects "a simulator DTPlatformName is rejected" "$tmp/app_wrongplat" "DTPlatformName is 'iphonesimulator'" --min-sdk 26
mkapp nosdkver exe_sdk=0.0
rejects "an executable recording no SDK is rejected when a minimum is required" "$tmp/app_nosdkver" "executable slice arm64 records no SDK version" --min-sdk 26

# declared minimum OS
mkapp mismatch MinimumOSVersion=15.0
rejects "MinimumOSVersion different from the executable's minimum OS is rejected" "$tmp/app_mismatch" "executable slice arm64 needs iOS 14.0 but Info.plist MinimumOSVersion is '15.0'" --min-sdk 26
mkapp nomin MinimumOSVersion=__none__
rejects "a missing MinimumOSVersion is rejected" "$tmp/app_nomin" "Info.plist has no MinimumOSVersion" --min-sdk 26
mkapp below12 MinimumOSVersion=12.0 exe_minos=12.0
rejects "a minimum OS below Apple's iOS 13 floor is rejected" "$tmp/app_below12" "App Store Connect needs 13.0 or later" --min-sdk 26
mkapp is13 MinimumOSVersion=13.0 exe_minos=13.0
accepts "iOS 13.0 is the boundary of Apple's floor" "$tmp/app_is13" --min-sdk 26

# embedded frameworks
mkapp fwnew "fw=Sumsub,ios,15.5,26.2"
accepts "a framework needing a newer OS than the app declares is only a warning" "$tmp/app_fwnew" --min-sdk 26
case "$VA_OUT" in
  *"WARN  framework Sumsub.framework needs iOS 15.5 but the app declares iOS 14.0"*"deployment_target_conflicts=1"*) ok "the conflict is reported as WARN and counted in the evidence" ;;
  *) bad "the conflict is reported as WARN and counted in the evidence" ;;
esac
case "$VA_OUT" in
  *"framework.Flutter.framework=ios minos=13.0 sdk=18.5"*"framework.Sumsub.framework=ios minos=15.5 sdk=26.2"*) ok "every framework's platform, minimum OS and SDK are recorded" ;;
  *) bad "every framework's platform, minimum OS and SDK are recorded" ;;
esac
mkapp fwsim "fw=Sumsub,ios-simulator,13.0,26.2"
rejects "a simulator framework inside a device app is rejected" "$tmp/app_fwsim" "framework Sumsub.framework is built for 'ios-simulator'" --min-sdk 26

# the existing identity checks still apply
mkapp wrongid bundle_id=com.example.other
rejects "a wrong bundle identifier is still rejected" "$tmp/app_wrongid" "bundle identifier is 'com.example.other'" --min-sdk 26
mkapp wrongurl url=https://cadenabitcoin.com/app
rejects "a snapshot with the other environment's URL is still rejected" "$tmp/app_wrongurl" "App.framework/App failed the staging check" --min-sdk 26

# self-test mode proves the SDK check can fail
st="$(bash "$verify_artifact" selftest ios staging "$tmp/app_good" --min-sdk 26 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && [[ "$st" == *"rejects the app when a newer SDK than it was built with is required"* ]]; then ok "selftest also proves a newer required SDK is rejected"
else bad "selftest also proves a newer required SDK is rejected" "$st"; fi
st="$(bash "$verify_artifact" selftest ios staging "$tmp/app_old" --min-sdk 26 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && ok "selftest fails for an app built with an old SDK" || bad "selftest fails for an app built with an old SDK" "$st"
bash "$verify_artifact" ios staging "$tmp/app_good" --min-sdk 2x >/dev/null 2>&1 && bad "--min-sdk needs a whole number" || ok "--min-sdk needs a whole number"
bash "$verify_artifact" apk staging "$tmp/app_good" --min-sdk 26 >/dev/null 2>&1 && bad "--min-sdk is refused for non-iOS kinds" || ok "--min-sdk is refused for non-iOS kinds"

# --- 3. the shared pins and the deployment targets ---------------------------------------------
echo "== verify_ios_toolchain.sh"
vt() { bash "$verify_toolchain" "$1" 2>&1; }
out="$(vt "$root")"; rc=$?
[ "$rc" -eq 0 ] && ok "the repository's two iOS workflows agree and meet Apple's floor" || bad "the repository's two iOS workflows agree and meet Apple's floor" "$out"
case "$out" in
  *"WARN  pods whose podspec declares a minimum below iOS 13 are built for the Podfile platform"*) ok "the Podfile/project deployment-target difference is reported, not hidden" ;;
  *) ok "no Podfile/project deployment-target difference to report" ;;
esac

# mutate NAME FILE 'sed expression' EXPECTED_FAIL_TEXT: a copy of the repo parts with one edit
copy_parts() { # DIR
  mkdir -p "$1/.github/workflows" "$1/ios/Runner.xcodeproj" "$1/ios/Flutter" "$1/flutter_plugin/flutter_plugin/ios"
  cp "$root/.github/workflows/ios-ci-validation.yml" "$root/.github/workflows/build-variants.yml" "$1/.github/workflows/"
  cp "$root/ios/Runner.xcodeproj/project.pbxproj" "$1/ios/Runner.xcodeproj/"
  cp "$root/ios/Podfile" "$root/ios/Podfile.lock" "$1/ios/"; cp "$root/ios/Flutter/AppFrameworkInfo.plist" "$1/ios/Flutter/"
  cp "$root/flutter_plugin/flutter_plugin/ios/dlc_wallet.podspec" "$1/flutter_plugin/flutter_plugin/ios/"
}
mutate() { # NAME FILE SED_EXPR EXPECTED_TEXT
  local d="$tmp/mut_$RANDOM"; copy_parts "$d"
  if ! grep -q -- "$(printf '%s' "$3" | sed -n 's/^s|\([^|]*\)|.*/\1/p')" "$d/$2" 2>/dev/null; then bad "$1" "mutation does not apply to $2"; return; fi
  sed -i.bak "$3" "$d/$2" && rm -f "$d/$2.bak"
  local o; o="$(vt "$d")"; local r=$?
  if [ "$r" -eq 0 ]; then bad "$1" "the mutated copy was accepted"
  elif [[ "$o" == *"$4"* ]]; then ok "$1"
  else bad "$1" "rejected, but not for '$4': $(printf '%s' "$o" | grep FAIL | head -n 3 | tr '\n' ' ')"; fi
}
V=.github/workflows/ios-ci-validation.yml
B=.github/workflows/build-variants.yml
mutate "Xcode changed in one workflow only is rejected" $V 's|EXPECTED_XCODE: "26.3"|EXPECTED_XCODE: "26.2"|' "EXPECTED_XCODE differs"
mutate "the Xcode path not matching the Xcode version is rejected" $B 's|XCODE_APP: /Applications/Xcode_26.3.app|XCODE_APP: /Applications/Xcode_16.4.app|' "XCODE_APP differs"
mutate "an Xcode path that does not match EXPECTED_XCODE is rejected" $V 's|/Applications/Xcode_26.3.app|/Applications/Xcode_26.2.app|' "is not /Applications/Xcode_26.3.app"
mutate "a minimum SDK below Apple's floor is rejected" $V 's|EXPECTED_MIN_SDK_MAJOR: "26"|EXPECTED_MIN_SDK_MAJOR: "18"|' "EXPECTED_MIN_SDK_MAJOR differs"
mutate "the minimum SDK differing between workflows is rejected" $B 's|EXPECTED_MIN_SDK_MAJOR: "26"|EXPECTED_MIN_SDK_MAJOR: "27"|' "EXPECTED_MIN_SDK_MAJOR differs"
mutate "CocoaPods differing between workflows is rejected" $B 's|EXPECTED_COCOAPODS: "1.17.0"|EXPECTED_COCOAPODS: "1.16.2"|' "EXPECTED_COCOAPODS differs"
mutate "the Flutter version differing between workflows is rejected" $V 's|EXPECTED_FLUTTER: "3.35.3"|EXPECTED_FLUTTER: "3.38.0"|' "EXPECTED_FLUTTER differs"
mutate "the Rust library checksum differing between workflows is rejected" $B 's|EXPECTED_RUST_LIB_SHA256: 203dcd|EXPECTED_RUST_LIB_SHA256: 203dce|' "EXPECTED_RUST_LIB_SHA256 differs"
mutate "a moving runner image is rejected" $V 's|runs-on: macos-15|runs-on: macos-latest|' "runs-on differs"
mutate "a different runner image in one workflow is rejected" $B 's|runs-on: macos-15|runs-on: macos-26|' "runs-on differs"
mutate "a renamed Xcode step is rejected" $V 's|name: Select Xcode 26.3|name: Select Xcode 16.4|' "no step 'Select Xcode 26.3'"
mutate "dropping the SDK assertion is rejected" $B 's|Expected an iPhoneOS SDK|Saw an iPhoneOS SDK|' "does not assert the iPhoneOS SDK"
mutate "dropping the CocoaPods assertion is rejected" $V 's|\$EXPECTED_COCOAPODS|\$COCOAPODS_SEEN|g' "does not assert the CocoaPods version"
mutate "an artifact verification without --min-sdk is rejected (validation)" $V 's|--min-sdk "\$EXPECTED_MIN_SDK_MAJOR" ||' "do not pass --min-sdk"
mutate "an artifact self-test without --min-sdk is rejected (variants)" $B 's|selftest ios "\$BUILD_ENV" "\$APP_PATH" --min-sdk "\$EXPECTED_MIN_SDK_MAJOR"|selftest ios "$BUILD_ENV" "$APP_PATH"|' "do not pass --min-sdk"
mutate "a CocoaPods version in Podfile.lock other than the pinned one is rejected" ios/Podfile.lock 's|COCOAPODS: 1.17.0|COCOAPODS: 1.16.2|' "ios/Podfile.lock was generated by CocoaPods 1.16.2"
mutate "a missing drift check in the validation workflow is rejected" $V 's|run: /bin/bash tool/check_build_drift.sh|run: echo skipped|' "ios-ci-validation.yml: does not run tool/check_build_drift.sh"
mutate "a missing drift check in the build-variants workflow is rejected" $B 's|run: /bin/bash tool/check_build_drift.sh|run: echo skipped|' "build-variants.yml: does not run tool/check_build_drift.sh"
mutate "a drift check that may fail silently (validation) is rejected" $V 's|      - name: No tracked file may be changed by the build (ios/Podfile.lock drift fails)|&\n        continue-on-error: true|' "a step may fail silently"
mutate "a drift check that may fail silently (variants) is rejected" $B 's|      - name: No tracked file may be changed by the build (ios/Podfile.lock drift fails)|&\n        continue-on-error: true|' "a step may fail silently"
mutate "drift reported only as a warning is rejected" $B 's|      - name: No tracked file may be changed by the build (ios/Podfile.lock drift fails)|      - name: warn ::warning title=ios/Podfile.lock drift::x|' "still reports Podfile.lock drift as a warning"
# the drift check moved in front of the build is rejected
d="$tmp/mut_order"; copy_parts "$d"
python3 -I - "$d/$V" "$d/$B" <<'PYEOF'
import sys
for path in sys.argv[1:]:
    lines = open(path).read().split("\n")
    start = next(i for i, l in enumerate(lines) if l.startswith("      # A build must not rewrite any tracked file."))
    end = next(i for i in range(start, len(lines)) if lines[i].strip() == "run: /bin/bash tool/check_build_drift.sh") + 1
    block = lines[start:end] + [""]
    del lines[start:end + 1]
    first_build = next(i for i, l in enumerate(lines) if "flutter build ios --release --no-codesign --flavor" in l and "run" in l or "| tee diagnostics/build.log" in l)
    # insert before the comment/step that holds the build (walk up to its step header)
    j = first_build
    while not lines[j].lstrip().startswith("- name:"):
        j -= 1
    while lines[j - 1].lstrip().startswith("#"):
        j -= 1
    lines[j:j] = block
    open(path, "w").write("\n".join(lines))
PYEOF
o="$(vt "$d")"; r=$?
if [ "$r" -ne 0 ] && [[ "$o" == *"ios-ci-validation.yml: tool/check_build_drift.sh does not run after the build"* ]] && [[ "$o" == *"build-variants.yml: tool/check_build_drift.sh does not run after the build"* ]]; then ok "a drift check that runs before the build is rejected in both workflows"
else bad "a drift check that runs before the build is rejected in both workflows" "rc=$r $(printf '%s' "$o" | grep FAIL | head -n 3 | tr '\n' ' ')"; fi
# deployment targets
mutate "two different project deployment targets are rejected" ios/Runner.xcodeproj/project.pbxproj '0,/IPHONEOS_DEPLOYMENT_TARGET = 14.0;/s||IPHONEOS_DEPLOYMENT_TARGET = 15.0;|' "2 different IPHONEOS_DEPLOYMENT_TARGET values"
mutate "a project deployment target below iOS 13 is rejected" ios/Runner.xcodeproj/project.pbxproj 's|IPHONEOS_DEPLOYMENT_TARGET = 14.0;|IPHONEOS_DEPLOYMENT_TARGET = 12.0;|' "Xcode project: iOS 12.0 is below Apple's floor"
mutate "a Podfile platform below iOS 13 is rejected" ios/Podfile "s|platform :ios, '15.5'|platform :ios, '12.0'|" "Podfile: iOS 12.0 is below Apple's floor"
mutate "a podspec needing a newer iOS than the Podfile is rejected" flutter_plugin/flutter_plugin/ios/dlc_wallet.podspec "s|:ios, '12.0'|:ios, '16.0'|" "the dlc_wallet podspec needs iOS 16.0 but the Podfile platform is iOS 15.5"

# --- 4. Podfile.lock drift fails the build -----------------------------------------------------
echo "== check_build_drift.sh"
mkrepo() { # NAME : a throwaway repository with a tracked lock, a tracked source and a look-alike file
  local d="$tmp/drift_$1"; mkdir -p "$d/ios" "$d/lib"
  ( cd "$d" && git init -q . \
    && printf 'COCOAPODS: 1.17.0\n' >ios/Podfile.lock && printf 'x\n' >lib/x.dart && printf 'y\n' >ios/Podfile.lock.bak \
    && git add . && git -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false commit -q -m base )
  echo "$d"
}
drift() { # REPO : output, status in $?
  local envf="$1/.env_out"; : >"$envf"; GITHUB_ENV="$envf" bash "$check_drift" "$1" 2>&1
}
d="$(mkrepo clean)"; out="$(drift "$d")"; rc=$?
if [ "$rc" -eq 0 ] && [[ "$out" == *"No tracked file was modified"* ]] && [ "$(cat "$d/.env_out")" = "PODFILE_LOCK_DRIFT=no" ]; then ok "a clean tree passes and records no drift"
else bad "a clean tree passes and records no drift" "rc=$rc $out"; fi
d="$(mkrepo untracked)"; printf 'new\n' >"$d/ios/new.txt"; out="$(drift "$d")"; rc=$?
[ "$rc" -eq 0 ] && ok "an untracked file does not count" || bad "an untracked file does not count" "$out"
d="$(mkrepo lock)"; printf 'COCOAPODS: 1.16.2\n' >"$d/ios/Podfile.lock"; out="$(drift "$d")"; rc=$?
if [ "$rc" -eq 1 ] && [[ "$out" == *"::error title=ios/Podfile.lock drift::"* ]] && [[ "$out" == *"-COCOAPODS: 1.17.0"* ]] && [[ "$out" == *"+COCOAPODS: 1.16.2"* ]] \
   && [ "$(cat "$d/.env_out")" = "PODFILE_LOCK_DRIFT=yes" ]; then ok "a rewritten Podfile.lock fails, prints its diff and records the drift"
else bad "a rewritten Podfile.lock fails, prints its diff and records the drift" "rc=$rc $out"; fi
d="$(mkrepo lockdel)"; rm "$d/ios/Podfile.lock"; out="$(drift "$d")"; rc=$?
[ "$rc" -eq 1 ] && ok "a deleted Podfile.lock fails" || bad "a deleted Podfile.lock fails" "rc=$rc $out"
d="$(mkrepo other)"; printf 'changed\n' >"$d/lib/x.dart"; out="$(drift "$d")"; rc=$?
if [ "$rc" -eq 1 ] && [[ "$out" == *"tracked files other than ios/Podfile.lock"* ]] && [[ "$out" == *"lib/x.dart"* ]] && [[ "$out" != *"drift::"* ]]; then ok "another tracked file changed by the build fails, and is not called lock drift"
else bad "another tracked file changed by the build fails, and is not called lock drift" "rc=$rc $out"; fi
d="$(mkrepo lookalike)"; printf 'changed\n' >"$d/ios/Podfile.lock.bak"; out="$(drift "$d")"; rc=$?
if [ "$rc" -eq 1 ] && [[ "$out" == *"tracked files other than ios/Podfile.lock"* ]] && [[ "$out" != *"drift::"* ]]; then ok "a file that only resembles the lock is not mistaken for it"
else bad "a file that only resembles the lock is not mistaken for it" "rc=$rc $out"; fi
d="$(mkrepo both)"; printf 'COCOAPODS: 1.16.2\n' >"$d/ios/Podfile.lock"; printf 'changed\n' >"$d/lib/x.dart"; out="$(drift "$d")"; rc=$?
if [ "$rc" -eq 1 ] && [[ "$out" == *"drift::"* ]] && [[ "$out" == *"tracked files other than ios/Podfile.lock"* ]]; then ok "lock drift and another change are both reported"
else bad "lock drift and another change are both reported" "rc=$rc $out"; fi
d="$(mkrepo noenv)"; printf 'COCOAPODS: 1.16.2\n' >"$d/ios/Podfile.lock"; out="$(env -u GITHUB_ENV bash "$check_drift" "$d" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] && ok "it also works outside GitHub Actions (no GITHUB_ENV)" || bad "it also works outside GitHub Actions (no GITHUB_ENV)" "rc=$rc $out"
bash -n "$check_drift" && ok "the drift check is valid bash" || bad "the drift check is valid bash"

echo
echo "$pass passed, $failed failed"
[ "$failed" -eq 0 ]
