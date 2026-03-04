#!/bin/bash
# ----------------------------
# Website Response Time Check
# ----------------------------

# Resolve paths relative to this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$BASE_DIR/logs"
mkdir -p "$LOG_DIR"

URL="${1:-http://localhost}"
ITERATIONS=${2:-20}
LOG="$LOG_DIR/self_heal.log"

# Ensure bc exists
if ! command -v bc >/dev/null 2>&1; then
  sudo apt-get update -y && sudo apt-get install -y bc || sudo dnf install -y bc
fi

echo "[$(date)] Measuring response time for $URL ($ITERATIONS requests)" | tee -a "$LOG"

for i in $(seq 1 "$ITERATIONS"); do
  TIME=$(curl -o /dev/null -s -w "%{time_total}\n" "$URL")
  echo "[$(date)] Request #$i -> ${TIME}s" | tee -a "$LOG"
  if (( $(echo "$TIME > 2.0" | bc -l) )); then
    echo "[$(date)] ⚠️ ALERT: Response time too high (${TIME}s)" | tee -a "$LOG"
  fi
  sleep 1
done

echo "[$(date)] Latency test completed." | tee -a "$LOG"
