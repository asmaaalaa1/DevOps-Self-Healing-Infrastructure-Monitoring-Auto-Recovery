#!/bin/bash
# ---------------------------------
# Website Spike Test (sudden burst)
# ---------------------------------

# Resolve paths relative to this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$BASE_DIR/logs"
mkdir -p "$LOG_DIR"

URL="${1:-http://localhost}"
SPIKE_SIZE=${2:-500}
LOG="$LOG_DIR/self_heal.log"

echo "[$(date)] Starting SPIKE test: $SPIKE_SIZE requests at once to $URL" | tee -a "$LOG"

if ! command -v curl >/dev/null 2>&1; then
  sudo apt-get update -y && sudo apt-get install -y curl || sudo dnf install -y curl
fi

for i in $(seq 1 "$SPIKE_SIZE"); do
  curl -s -o /dev/null -w "%{http_code}\n" "$URL" &
done

wait
echo "[$(date)] Spike test completed (sent $SPIKE_SIZE requests)." | tee -a "$LOG"
