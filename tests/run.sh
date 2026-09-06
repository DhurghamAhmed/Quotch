#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_BUILD="$(mktemp -d "${TMPDIR:-/tmp}/notchusage-tests.XXXXXX")"
swiftc -swift-version 5 -module-cache-path "$TEST_BUILD/modules" \
  "$ROOT"/Quotch/Core/*.swift "$ROOT/Quotch/UI/Format.swift" \
  "$ROOT/tests/UsageTests.swift" -o "$TEST_BUILD/UsageTests"
"$TEST_BUILD/UsageTests"
