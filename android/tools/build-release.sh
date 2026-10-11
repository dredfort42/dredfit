#!/usr/bin/env bash
#
# The Google Play upload: builds android/app's release App Bundle signed with
# the upload key, checks the signature, and prints what to compare with Play
# Console. The owner runs it on his Mac; nothing else holds the key.
#
#   android/tools/build-release.sh      # on main, as origin has it
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
# Tracing (`bash -x`, SHELLOPTS=xtrace) would print the password the moment
# the Keychain hands it over: refuse to run traced.
case $- in
    *x*) echo "build-release: refusing to run traced (bash -x): it would print the password" >&2
         exit 1 ;;
esac

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

# Only what main holds ships: the tag must name a commit that stays, and a
# squash merge discards a branch's own commits. The fetch also brings every
# tag, which the version check below compares the code with.
git -C "$root" fetch --quiet --tags origin main \
    || fail "cannot fetch origin's main and tags"
commit="$(git -C "$root" rev-parse HEAD)"
[ "$commit" = "$(git -C "$root" rev-parse origin/main)" ] \
    || fail "HEAD ($commit) is not origin/main; check out main and pull first"

# Read as Gradle reads a property: key, then "=", ":" or blanks.
property() {
    sed -nE "s/^[[:space:]]*dredfit\.$1([[:space:]]*[=:][[:space:]]*|[[:space:]]+)//p" \
        "$android_dir/gradle.properties"
}
version="$(property versionName)"
code="$(property versionCode)"
# The Android gate: versionName is the tree's product version (iOS's
# MARKETING_VERSION), the code is above every code a tag has used, and the
# CHANGELOG has the version's Android section.
python3 "$root/scripts/check_version.py" --android
tag="android-v$version+$code"

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
# the build. AGP still records an unsalted SHA-256 of the password in
# android/.gradle/<gradle version>/executionHistory (its up-to-date check);
# android/README.md, "Signing", says why that is left there.
#
# Gradle runs in the background so that an interrupt reaches the trap at
# once (bash runs a trap only after its foreground command ends): the trap
# stops the Gradle client, and a bundle that was signed but never verified
# is deleted, so nothing unchecked is left to upload.
aab="$android_dir/app/build/outputs/bundle/release/app-release.aab"
gradle="" verified=0
finish() {
    if [ -n "$gradle" ]; then
        kill "$gradle" 2>/dev/null || true
        wait "$gradle" 2>/dev/null || true
    fi
    [ "$verified" = 1 ] || rm -f "$aab"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
rm -f "$aab"
cd "$android_dir"
./gradlew --no-daemon --no-configuration-cache \
    -Pkotlin.compiler.execution.strategy=in-process \
    --console=plain :app:bundleRelease &
gradle=$!
if ! wait "$gradle"; then
    gradle=""
    fail "the Gradle build failed"
fi
gradle=""
unset DREDFIT_UPLOAD_PASSWORD

[ -f "$aab" ] || fail "no bundle at $aab"

# An App Bundle is a JAR-signed zip: apksigner reads APKs only.
verify="$("$jarsigner" -verify "$aab")" || fail "jarsigner -verify failed: $verify"
case "$verify" in
    *"jar verified."*) ;;
    *) fail "the bundle is not signed: $verify" ;;
esac
aab_sha="$("$keytool" -printcert -jarfile "$aab" | sed -n 's/^[[:space:]]*SHA256: //p')" \
    || fail "keytool could not read the bundle's certificate"
[ -n "$aab_sha" ] || fail "keytool printed no SHA-256 for the bundle's certificate"
[ "$aab_sha" = "$key_sha" ] || fail "the bundle's certificate ($aab_sha) is not the key's ($key_sha)"
verified=1

cat <<EOF

Bundle:      $aab
Size:        $(stat -f%z "$aab") bytes
Version:     $version (versionCode $code)
Commit:      $commit (origin/main)
Tag:         $tag
Signature:   jarsigner -verify: jar verified.
Upload key:  SHA-256 $aab_sha

Next (.github/WORKFLOWS.md, "Android release"):
  1. Play Console, App integrity: the upload key certificate's SHA-256 must
     be the one above.
  2. Play Console, Internal testing: create a release, upload the bundle.
  3. git tag $tag $commit && git push origin $tag
EOF
