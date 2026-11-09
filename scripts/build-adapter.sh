#!/bin/sh
# Builds the vendored MediaRemote adapter (perl script + universal framework) into build/mediaremote/.
# The Xcode "Bundle mediaremote adapter" phase copies it into the app. Without it now playing is off.
set -e
cd "$(dirname "$0")/.."
MR=vendor/mediaremote-adapter
cmake -S "$MR" -B build/adapter -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 >/dev/null
cmake --build build/adapter >/dev/null
rm -rf build/mediaremote && mkdir -p build/mediaremote
cp "$MR/bin/mediaremote-adapter.pl" build/mediaremote/
cp -R build/adapter/MediaRemoteAdapter.framework build/mediaremote/
rm -rf build/adapter
