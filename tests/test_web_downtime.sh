#!/bin/bash
# --------------------------------------
# Website Downtime Simulation & Recovery
# --------------------------------------

# Resolve paths relative to this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$BASE_DIR/logs"
mkdir -p "$LOG_DIR"

SERVICE="nginx"  # Change to docker:myapp if using container
URL="${1:-http://localhost}"
WAIT=${2:-30}
LOG="$LOG_DIR/self_heal.log"

echo "[$(date)] Simulating service failure for $SERVICE" | tee -a "$LOG"
sudo systemctl stop "$SERVICE"

echo "[$(date)] Checking website availability..." | tee -a "$LOG"
for i in $(seq 1 "$WAIT"); do
  CODE=$(curl -s -o /dev/null -w "%{http_code}" "$URL" || echo 000)
  if [ "$CODE" = "200" ]; then
    echo "[$(date)] ✅ Website recovered (HTTP 200) after $i seconds" | tee -a "$LOG"
    sudo systemctl start "$SERVICE"
    exit 0
  else
    echo "[$(date)] Waiting... ($i/$WAIT) Site not reachable [HTTP $CODE]" | tee -a "$LOG"
  fi
  sleep 1
done

echo "[$(date)] ❌ Website did not recover automatically within ${WAIT}s" | tee -a "$LOG"
sudo systemctl start "$SERVICE"
