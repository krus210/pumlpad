#!/usr/bin/env bash
# Time from launching Pumlpad with a file to its first rendered diagram, as the app logs it.
# The app opens in the background and is quit after each run.
# Usage: scripts/bench-launch.sh [file.puml]   (RUNS=5, APP=build/Pumlpad.app)
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
app="${APP:-$root/build/Pumlpad.app}"
file="${1:-$root/Samples/sequence.puml}"
runs="${RUNS:-5}"

for run in $(seq 1 "$runs"); do
  pkill -x Pumlpad 2>/dev/null || true
  sleep 2
  since="$(date '+%Y-%m-%d %H:%M:%S')"
  open -g -a "$app" "$file" --args -ApplePersistenceIgnoreState YES
  result=""
  for _ in $(seq 1 40); do
    result="$(log show --start "$since" --style compact \
      --predicate 'subsystem == "com.sskorolev.pumlpad" AND category == "performance"' 2>/dev/null \
      | grep -o 'First preview [0-9]* ms' | tail -1 || true)"
    [[ -n "$result" ]] && break
    sleep 0.5
  done
  echo "run $run: ${result:-no preview within 20 s}"
done
pkill -x Pumlpad 2>/dev/null || true
