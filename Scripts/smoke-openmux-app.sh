#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
LOG_DIR="$ROOT_DIR/.build/smoke"
LOG_FILE="$LOG_DIR/openmux-app.log"
SAMPLE_FILE="$LOG_DIR/openmux-app.sample.txt"
WAIT_SECONDS="${SMOKE_WAIT_SECONDS:-10}"

mkdir -p "$LOG_DIR"
rm -f "$LOG_FILE" "$SAMPLE_FILE"

cd "$ROOT_DIR"
swift build --product OpenMUXApp >/dev/null
BIN_PATH="$(swift build --show-bin-path)/OpenMUXApp"

"$BIN_PATH" >"$LOG_FILE" 2>&1 &
APP_PID=$!

cleanup() {
  if kill -0 "$APP_PID" 2>/dev/null; then
    kill "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

elapsed=0
while [ "$elapsed" -lt "$WAIT_SECONDS" ]; do
  if ! kill -0 "$APP_PID" 2>/dev/null; then
    wait "$APP_PID" || true
    echo "OpenMUXApp exited before smoke test completed" >&2
    cat "$LOG_FILE" >&2
    exit 1
  fi

  sleep 1
  elapsed=$((elapsed + 1))
done

sample "$APP_PID" 1 1 >"$SAMPLE_FILE" 2>&1 || true

if grep -q "CGhosttyRuntime.scheduleTick" "$SAMPLE_FILE" &&
   grep -Eq "__DISPATCH_WAIT_FOR_QUEUE__|_dispatch_sync_f_slow|runOnMain" "$SAMPLE_FILE"
then
  echo "Detected the previous CGhosttyRuntime main-thread deadlock signature" >&2
  cat "$SAMPLE_FILE" >&2
  exit 1
fi

echo "OpenMUXApp smoke test passed"
