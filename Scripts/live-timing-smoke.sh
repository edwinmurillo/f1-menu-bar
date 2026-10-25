#!/bin/bash
source "$(dirname "$0")/environment.sh"
F1_CONFIGURATION="${1:-Release}"
F1_PRODUCTS="$F1_PROJECT_ROOT/.build/DerivedData/Build/Products/$F1_CONFIGURATION"
Scripts/build.sh "$F1_CONFIGURATION"
xcrun swiftc -parse-as-library -swift-version 6 -F "$F1_PRODUCTS" -framework F1Core -Xlinker -rpath -Xlinker "$F1_PRODUCTS" Scripts/live-timing-smoke.swift -o .build/live-timing-smoke
.build/live-timing-smoke
