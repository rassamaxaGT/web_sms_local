#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

echo "[1/4] Building Web Client..."
flutter build web --release --target lib/main_web.dart --base-href / --no-tree-shake-icons

echo "[2/4] Cleaning old assets..."
rm -f assets/web.zip
mkdir -p assets
rm -f build/web/assets/assets/web.zip

echo "[3/4] Zipping Web Client..."
(cd build/web && zip -rq ../../assets/web.zip .)

echo "[4/4] Running Android Host..."
flutter run "$@"
