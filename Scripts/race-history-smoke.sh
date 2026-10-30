#!/bin/bash
source "$(dirname "$0")/environment.sh"
if [[ $# -ne 4 ]]; then
  echo 'Usage: Scripts/race-history-smoke.sh YEAR MEETING_ID RACE_SESSION_ID START_ISO8601' >&2
  exit 1
fi
F1_PRODUCTS="$F1_PROJECT_ROOT/.build/DerivedData/Build/Products/Release"
xcrun swiftc -parse-as-library -swift-version 6 -F "$F1_PRODUCTS" -framework F1Core Scripts/race-history-smoke.swift -o .build/race-history-smoke
.build/race-history-smoke "$@"
