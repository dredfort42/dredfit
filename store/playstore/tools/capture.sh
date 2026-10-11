#!/bin/sh
# Take the raws for the Play frames on one emulator and pull them into RAW_DIR.
#
#   ANDROID_SERIAL=emulator-5556 RAW_DIR=/tmp/play-raw store/playstore/tools/capture.sh
#
# Needs the debug app and its test APK installed on that emulator
# (android/: ./gradlew :app:assembleDebug :app:assembleDebugAndroidTest, then
# `adb install -r -g` both). Light theme only: the iOS set is light, and Play
# shows one set per locale. About five minutes a locale on a loaded host.
set -eu
: "${ANDROID_SERIAL:?name the emulator, never a phone: ANDROID_SERIAL=emulator-5556}"
: "${RAW_DIR:?RAW_DIR=<folder the raws are pulled into>}"
export ANDROID_SERIAL
ADB="${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb"
RUNNER=com.dredfit.dredfit.test/androidx.test.runner.AndroidJUnitRunner
SCREENS=/sdcard/Android/data/com.dredfit.dredfit/files/screens
LOCALES="${LOCALES:-en ru es pt-BR de fr it}"

case "$ANDROID_SERIAL" in
  emulator-*) ;;
  *) echo "refusing $ANDROID_SERIAL: a phone's status bar and state are not a store frame's" >&2; exit 2 ;;
esac

# A status bar that says the same thing in every frame: 12:00, full battery,
# Wi-Fi, no mobile signal. Notification icons are blanked by compose_play.py.
"$ADB" shell settings put global sysui_demo_allowed 1
for cmd in "enter" "clock -e hhmm 1200" \
           "battery -e level 100 -e plugged false -e powersave false" \
           "network -e wifi show -e level 4 -e fully true" "network -e mobile hide" \
           "notifications -e visible false"; do
  # shellcheck disable=SC2086  # the extras are words on purpose
  "$ADB" shell am broadcast -a com.android.systemui.demo -e command $cmd > /dev/null
done

# `am instrument` exits 0 on a failed test; its report is the only witness.
run() {
  out=$("$ADB" shell am instrument -w "$@" "$RUNNER")
  echo "$out" | tail -3
  case "$out" in *"OK (1 test)"*) ;; *) echo "capture failed: $*" >&2; exit 1 ;; esac
}

"$ADB" shell rm -rf "$SCREENS"
for loc in $LOCALES; do
  echo "== $loc"
  # The walk keeps the per-app language it is started in (keepLanguage).
  "$ADB" shell cmd locale set-app-locales com.dredfit.dredfit --locales "$loc"
  run -e class com.dredfit.ScreenshotWalk#captureTheWalk -e screens "$loc-light" -e appearance light
  run -e class com.dredfit.ScreenshotWalk#captureTheScreens -e screens "$loc-light" -e appearance light
done
echo "== widget"
run -e class com.dredfit.WidgetScreenshots#captureTheWidget -e screens widget \
    -e langs "$(echo "$LOCALES" | tr ' ' ',')"
"$ADB" shell cmd locale set-app-locales com.dredfit.dredfit --locales en
"$ADB" shell am broadcast -a com.android.systemui.demo -e command exit > /dev/null
mkdir -p "$RAW_DIR"
"$ADB" pull "$SCREENS" "$RAW_DIR/"
echo "raws in $RAW_DIR/screens — RAW_DIR=$RAW_DIR/screens python3 store/playstore/tools/compose_play.py"
