#!/bin/bash
set -euo pipefail
F1_PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -z "${DEVELOPER_DIR:-}" ]]; then
  F1_SELECTED_XCODE="$(xcode-select -p)"
  if [[ "$F1_SELECTED_XCODE" == */Contents/Developer ]]; then
    export DEVELOPER_DIR="$F1_SELECTED_XCODE"
  else
    for F1_XCODE_APP in /Applications/Xcode.app /Applications/Xcode-*.app; do
      if [[ -x "$F1_XCODE_APP/Contents/Developer/usr/bin/xcodebuild" ]]; then
        export DEVELOPER_DIR="$F1_XCODE_APP/Contents/Developer"
        break
      fi
    done
  fi
fi
if [[ -z "${DEVELOPER_DIR:-}" ]]; then
  echo 'Install full Xcode, or set DEVELOPER_DIR to its Contents/Developer directory.' >&2
  exit 1
fi
cd "$F1_PROJECT_ROOT"
mkdir -p .build
