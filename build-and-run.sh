#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

./build-debug.sh
./run.sh "$@"
