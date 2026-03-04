#!/bin/bash
# ---------------------------------
# Self-Healing: Restart Service
# ---------------------------------

# Resolve paths relative to this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$BASE_DIR/logs"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/self_heal.log"
REC="$LOG_DIR/recommendations.log"
SERVICE=${1:-nginx}

echo "[$(date)] [SERVICE] Checking $SERVICE..." >> "$LOG"

# Support docker:<container> to restart containers
if [[ "$SERVICE" == docker:* ]]; then
  CONTAINER_NAME="${SERVICE#docker:}"
  if ! command -v docker >/dev/null 2>&1; then
    echo "[$(date)] [SERVICE] ERROR: docker CLI not found" >> "$LOG"
    exit 1
  fi
  if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
    echo "[$(date)] [SERVICE] ALERT: container $CONTAINER_NAME not running" >> "$LOG"
    docker start "$CONTAINER_NAME" >/dev/null 2>&1 || true
  else
    echo "[$(date)] [SERVICE] Restarting container $CONTAINER_NAME" >> "$LOG"
    docker restart "$CONTAINER_NAME" >/dev/null 2>&1 || true
  fi
  sleep 3
  if docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
    echo "[$(date)] [SERVICE] SUCCESS: container $CONTAINER_NAME is running" >> "$LOG"
  else
    echo "[$(date)] [SERVICE] ERROR: container $CONTAINER_NAME failed" >> "$LOG"
  fi
  exit 0
fi

# Default: systemd service
if ! systemctl is-active --quiet "$SERVICE"; then
  echo "[$(date)] [SERVICE] ALERT: $SERVICE is down!" >> "$LOG"
  echo "[$(date)] [SERVICE] Attempting restart..." >> "$LOG"
  sudo systemctl restart "$SERVICE"
  sleep 3
  if systemctl is-active --quiet "$SERVICE"; then
    echo "[$(date)] [SERVICE] SUCCESS: $SERVICE restarted successfully" >> "$LOG"
  else
    echo "[$(date)] [SERVICE] ERROR: Failed to restart $SERVICE" >> "$LOG"
  fi
  echo "[$(date)] [SERVICE] Recommendation: investigate cause of $SERVICE failure" >> "$REC"
else
  echo "[$(date)] [SERVICE] OK: $SERVICE is running" >> "$LOG"
fi
