#!/bin/bash
source "$(dirname "$0")/environment.sh"
Scripts/bootstrap.sh
F1_CONFIGURATION="${1:-Debug}"
if ! xcodebuild -project F1MenuBar.xcodeproj -scheme F1MenuBar -configuration "$F1_CONFIGURATION" -destination 'platform=macOS' -derivedDataPath ".build/TestProducts/$F1_CONFIGURATION" ENABLE_TESTABILITY=YES test > ".build/test-$F1_CONFIGURATION.log" 2>&1; then
  tail -120 ".build/test-$F1_CONFIGURATION.log"
  exit 1
fi
tail -25 ".build/test-$F1_CONFIGURATION.log"
