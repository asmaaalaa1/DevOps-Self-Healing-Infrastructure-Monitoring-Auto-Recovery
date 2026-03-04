#!/bin/bash
# ---------------------------------
# Master Self-Healing Script
# ---------------------------------

# Resolve paths relative to this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$BASE_DIR/logs"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/self_heal.log"

echo "[$(date)] === Running Full Self-Healing Check ===" >> "$LOG"

bash "$SCRIPT_DIR/handle_high_cpu.sh"
bash "$SCRIPT_DIR/handle_high_memory.sh"
bash "$SCRIPT_DIR/handle_disk_alert.sh"
bash "$SCRIPT_DIR/handle_network_issue.sh"
bash "$SCRIPT_DIR/restart_service.sh" nginx

echo "[$(date)] === Self-Healing Cycle Completed ===" >> "$LOG"
