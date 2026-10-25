#!/bin/bash
source "$(dirname "$0")/environment.sh"
if ! command -v xcodegen >/dev/null; then
  echo 'Install XcodeGen: brew install xcodegen' >&2
  exit 1
fi
xcodegen generate --spec project.yml
