#!/bin/bash
source "$(dirname "$0")/environment.sh"
F1_CONFIGURATION="${1:-Debug}"
Scripts/bootstrap.sh
if ! xcodebuild -project F1MenuBar.xcodeproj -scheme F1MenuBar -configuration "$F1_CONFIGURATION" -destination 'platform=macOS' -derivedDataPath .build/DerivedData build > ".build/build-$F1_CONFIGURATION.log" 2>&1; then
  tail -100 ".build/build-$F1_CONFIGURATION.log"
  exit 1
fi
echo "Built .build/DerivedData/Build/Products/$F1_CONFIGURATION/F1 Menu Bar.app"
