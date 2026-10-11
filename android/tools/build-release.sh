#!/usr/bin/env bash
#
# The Google Play upload: builds android/app's release App Bundle signed with
# the upload key, checks the signature, and prints what to compare with Play
# Console. The owner runs it on his Mac; nothing else holds the key.
#
#   android/tools/build-release.sh
#
# The keystore's password lives ONLY in the macOS Keychain (generic password,
# service "dredfit-release-keystore"). The script asks the Keychain for it —
# macOS shows its own prompt — and hands it to Gradle and keytool through the
# environment: never echoed, never written to a file, never on a command line,
# where `ps` would show it to every process on the machine.
#
# Overrides (environment):
#   DREDFIT_UPLOAD_KEYSTORE   default ~/keys/dredfit-release.jks
#   DREDFIT_UPLOAD_KEY_ALIAS  default dredfit — `keytool -list -v -keystore
#                             ~/keys/dredfit-release.jks </dev/null` lists the
#                             aliases without the password
#   JAVA_HOME, ANDROID_HOME   default to Android Studio's JBR and SDK
#
set -euo pipefail

android_dir="$(cd "$(dirname "$0")/.." && pwd)"
root="$(cd "$android_dir/.." && pwd)"

export JAVA_HOME="${JAVA_HOME:-/Applications/Android Studio.app/Contents/jbr/Contents/Home}"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export DREDFIT_UPLOAD_KEYSTORE="${DREDFIT_UPLOAD_KEYSTORE:-$HOME/keys/dredfit-release.jks}"
export DREDFIT_UPLOAD_KEY_ALIAS="${DREDFIT_UPLOAD_KEY_ALIAS:-dredfit}"
keytool="$JAVA_HOME/bin/keytool"
jarsigner="$JAVA_HOME/bin/jarsigner"

fail() { echo "build-release: $*" >&2; exit 1; }

[ -x "$keytool" ] && [ -x "$jarsigner" ] || fail "no keytool/jarsigner in JAVA_HOME ($JAVA_HOME)"
[ -f "$DREDFIT_UPLOAD_KEYSTORE" ] || fail "no keystore at $DREDFIT_UPLOAD_KEYSTORE"

# The tag names the commit the bundle was built from, so the bundle must BE
# that commit: an uncommitted edit under android/ would ship from nowhere.
if [ -n "$(git -C "$root" status --porcelain -- android)" ]; then
    git -C "$root" status --short -- android >&2
    fail "android/ has uncommitted changes; build from a clean checkout of the commit to tag"
fi
commit="$(git -C "$root" rev-parse HEAD)"

version="$(sed -n 's/^dredfit\.versionName=//p' "$android_dir/gradle.properties")"
code="$(sed -n 's/^dredfit\.versionCode=//p' "$android_dir/gradle.properties")"
# The same gate the release branch runs: versionName equals iOS's version, the
# code is a positive integer above the last android-v* tag's, and the
# CHANGELOG has the version's section.
python3 "$root/scripts/check_version.py" "$version"

# A PKCS12 store lists its aliases without the password (the certificates
# stay encrypted): a wrong alias stops here, before the Keychain is asked.
if ! "$keytool" -list -v -keystore "$DREDFIT_UPLOAD_KEYSTORE" </dev/null 2>/dev/null \
        | grep -qxF "Alias name: $DREDFIT_UPLOAD_KEY_ALIAS"; then
    "$keytool" -list -v -keystore "$DREDFIT_UPLOAD_KEYSTORE" </dev/null 2>/dev/null \
        | grep "^Alias name:" >&2 || true
    fail "no alias '$DREDFIT_UPLOAD_KEY_ALIAS' in $DREDFIT_UPLOAD_KEYSTORE (set DREDFIT_UPLOAD_KEY_ALIAS)"
fi

if ! DREDFIT_UPLOAD_PASSWORD="$(security find-generic-password -s dredfit-release-keystore -w)"; then
    fail "the Keychain gave no password for 'dredfit-release-keystore'"
fi
export DREDFIT_UPLOAD_PASSWORD

# The key's own certificate, read with the password from the environment
# (-storepass:env names the variable, not the value); a wrong password stops
# here rather than deep in Gradle.
key_list="$("$keytool" -list -v -keystore "$DREDFIT_UPLOAD_KEYSTORE" \
    -alias "$DREDFIT_UPLOAD_KEY_ALIAS" -storepass:env DREDFIT_UPLOAD_PASSWORD)" \
    || fail "keytool could not open the key with the Keychain's password"
key_sha="$(printf '%s\n' "$key_list" | sed -n 's/^[[:space:]]*SHA256: //p')"
[ -n "$key_sha" ] || fail "keytool printed no SHA-256 for the key's certificate"

# No daemon and no configuration cache: a daemon would keep the password in
# its environment for hours after the build, and the configuration cache
# would write the signing config — password included — under android/.gradle.
# The Kotlin compiler runs in-process for the same reason: its daemon outlives
# the build.
cd "$android_dir"
./gradlew --no-daemon --no-configuration-cache \
    -Pkotlin.compiler.execution.strategy=in-process \
    --console=plain :app:bundleRelease
unset DREDFIT_UPLOAD_PASSWORD

aab="$android_dir/app/build/outputs/bundle/release/app-release.aab"
[ -f "$aab" ] || fail "no bundle at $aab"

# An App Bundle is a JAR-signed zip: apksigner reads APKs only.
verify="$("$jarsigner" -verify "$aab")" || fail "jarsigner -verify failed: $verify"
case "$verify" in
    *"jar verified."*) ;;
    *) fail "the bundle is not signed: $verify" ;;
esac
aab_sha="$("$keytool" -printcert -jarfile "$aab" | sed -n 's/^[[:space:]]*SHA256: //p')"
[ "$aab_sha" = "$key_sha" ] || fail "the bundle's certificate ($aab_sha) is not the key's ($key_sha)"

cat <<EOF

Bundle:      $aab
Size:        $(stat -f%z "$aab") bytes
Version:     $version (versionCode $code)
Commit:      $commit
Signature:   jarsigner -verify: jar verified.
Upload key:  SHA-256 $aab_sha

Next:
  1. Play Console > Test and release > App integrity: the upload key
     certificate's SHA-256 must be the one above.
  2. Testing > Internal testing > Create new release: upload the bundle.
  3. git tag android-v$version $commit && git push origin android-v$version
EOF
