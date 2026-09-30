#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir="${TMPDIR:-/tmp}/batteryscope-tests"
mkdir -p "$test_dir"
test_sources=(
  Sources/BatteryScope/Domain/BatteryAssessment.swift
  Sources/BatteryScope/Domain/ObservationSeries.swift
  Sources/BatteryScope/Domain/DeviceSummary.swift
  Sources/BatteryScope/Domain/Battery.swift
  Sources/BatteryScope/Domain/PowerReadings.swift
  Sources/BatteryScope/Infrastructure/SystemCommand.swift
  Sources/BatteryScope/Devices/BatteryParser.swift
  Sources/BatteryScope/Devices/MacHealthReader.swift
  Sources/BatteryScope/Devices/MacBatteryReader.swift
  Sources/BatteryScope/Reports/Export.swift
  Sources/BatteryScope/Devices/ConnectedDeviceReader.swift
  Sources/BatteryScope/History/HistoryDatabase.swift
  Sources/BatteryScope/Devices/TechnicalReader.swift
  Sources/BatteryScope/Platform/SystemCapabilities.swift
  Sources/BatteryScope/UI/Shared/FieldLabels.swift
  Sources/BatteryScope/History/HistoryFolderSync.swift
  Sources/BatteryScope/History/CloudFolder.swift
  Tests/BatteryScopeTests/BatteryTests.swift
)
swiftc -module-cache-path "$test_dir/modules" "${test_sources[@]}" -o "$test_dir/BatteryTests"
"$test_dir/BatteryTests" "$@"
