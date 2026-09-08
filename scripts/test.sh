#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir="${TMPDIR:-/tmp}/batteryscope-tests"
mkdir -p "$test_dir"
swiftc -module-cache-path "$test_dir/modules" Sources/BatteryScope/Battery.swift Sources/BatteryScope/Export.swift Sources/BatteryScope/Devices.swift Sources/BatteryScope/Database.swift Sources/BatteryScope/Technical.swift Tests/BatteryScopeTests/BatteryTests.swift -o "$test_dir/BatteryTests"
"$test_dir/BatteryTests" "$@"
