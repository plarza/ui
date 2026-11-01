#!/bin/sh
# Build the package for iPhone and Mac, as the apps will.
set -eu
set -o pipefail
cd "$(dirname "$0")/.."
for dest in 'generic/platform=iOS' 'generic/platform=iOS Simulator' 'platform=macOS'; do
  xcodebuild -scheme AzaUI-Package -destination "$dest" -derivedDataPath build build -quiet
  echo "built for $dest"
done
