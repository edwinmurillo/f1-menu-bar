#!/bin/bash
source "$(dirname "$0")/environment.sh"
F1_CONFIGURATION="${1:-Debug}"
Scripts/build.sh "$F1_CONFIGURATION"
open ".build/DerivedData/Build/Products/$F1_CONFIGURATION/F1 Menu Bar.app"
