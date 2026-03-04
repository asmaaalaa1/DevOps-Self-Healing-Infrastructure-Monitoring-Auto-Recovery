#!/bin/bash
# ----------------------------
# Website Load Test (HTTP GET)
# ----------------------------

# Resolve paths relative to this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$BASE_DIR/logs"
mkdir -p "$LOG_DIR"

URL="${1:-http://localhost}"
CONNECTIONS=${2:-50}
DURATION=${3:-30}
LOG="$LOG_DIR/self_heal.log"

echo "[$(date)] Starting web load test on $URL for ${DURATION}s with ${CONNECTIONS} concurrent connections" | tee -a "$LOG"

# Install ApacheBench if needed
if ! command -v ab >/dev/null 2>&1; then
  echo "[*] Installing apache bench tool..." | tee -a "$LOG"
  sudo apt-get update -y && sudo apt-get install -y apache2-utils || sudo dnf install -y httpd-tools
fi

ab -n $((CONNECTIONS * DURATION)) -c "$CONNECTIONS" "$URL"/ >> "$LOG" 2>&1

echo "[$(date)] Web load test completed." | tee -a "$LOG"
