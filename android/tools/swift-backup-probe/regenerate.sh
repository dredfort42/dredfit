#!/bin/sh
# Rewrites the Swift-written fixtures the Android tests compare against.
# SWIFT_DETERMINISTIC_HASHING: Swift writes sets and [Pattern: X] arrays in a
# per-run hash order; pinned, two runs give the same bytes.
set -eu
cd "$(dirname "$0")"
swift build -c release --quiet
probe=.build/release/SwiftBackupProbe
ios=../../app/src/test/resources/ios
core=../../core/src/test/resources/swift
export SWIFT_DETERMINISTIC_HASHING=1
"$probe" sessions "$core/sessions.json" > /dev/null
"$probe" backup "$ios/ios-backup.json" "$ios/ios-state-pending.json" > /dev/null
"$probe" decode "$ios/ios-backup.json" > "$ios/ios-backup.swift-decoded.json"
"$probe" roundtrip "$ios/ios-state-pending.json" "$ios/ios-state-pending.swift-roundtrip.json" > /dev/null
echo "fixtures rewritten under android/app/src/test/resources/ios and android/core/src/test/resources/swift"
