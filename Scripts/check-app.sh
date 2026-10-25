#!/bin/bash
source "$(dirname "$0")/environment.sh"
F1_CONFIGURATION="${1:-Release}"
F1_APP=".build/DerivedData/Build/Products/$F1_CONFIGURATION/F1 Menu Bar.app"
F1_EXECUTABLE="$F1_APP/Contents/MacOS/F1 Menu Bar"
/usr/bin/codesign --verify --deep --strict "$F1_APP"
case "$(/usr/bin/otool -L "$F1_EXECUTABLE")" in
  *F1Core.framework*)
    echo 'F1Core must be linked statically so the locally signed app can launch.' >&2
    exit 1
    ;;
esac
if [[ -d "$F1_APP/Contents/Frameworks/F1Core.framework" ]]; then
  echo 'A stale dynamic F1Core framework remains. Clean the build products and rebuild.' >&2
  exit 1
fi
echo 'App signature and static core packaging verified.'
