#!/bin/bash
# ---------------------------------------------
# Run all website-level stress tests sequentially
# ---------------------------------------------

# Resolve paths relative to this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$BASE_DIR/logs"
mkdir -p "$LOG_DIR"

URL="${1:-http://localhost}"
LOG="$LOG_DIR/self_heal.log"

echo "[$(date)] ==== Starting WEBSITE Self-Heal Tests on $URL ====" | tee -a "$LOG"

bash "$SCRIPT_DIR/test_web_latency.sh" "$URL" 10
bash "$SCRIPT_DIR/test_web_load.sh" "$URL" 50 30
bash "$SCRIPT_DIR/test_web_spike.sh" "$URL" 500
bash "$SCRIPT_DIR/test_web_downtime.sh" "$URL" 60

echo "[$(date)] ==== All WEBSITE tests completed ====" | tee -a "$LOG"
