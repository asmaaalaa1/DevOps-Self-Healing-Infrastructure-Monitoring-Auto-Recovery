#!/bin/bash
# ------------------------------------------------------
# Smart Recommendation Engine (Interactive Self-Healing)
# ------------------------------------------------------

# Resolve paths relative to this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$BASE_DIR/logs"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/self_heal.log"
REC="$LOG_DIR/recommendations.log"

ALERT_TYPE="$1"   # نوع المشكلة: CPU / MEMORY / DISK / SERVICE / NETWORK

if [ -z "$ALERT_TYPE" ]; then
  echo "Usage: $0 <ALERT_TYPE>"
  echo "Example: $0 CPU"
  exit 1
fi

echo "[$(date)] [RECOMMENDATION] Alert Type: $ALERT_TYPE" >> "$LOG"

# قاعدة بيانات الاقتراحات
declare -A RECOMMENDATIONS

RECOMMENDATIONS["CPU"]="1) Kill top consuming process
2) Restart high CPU service (e.g., nginx)
3) Scale up CPU cores (add vCPU)
4) Optimize application code or background tasks"

RECOMMENDATIONS["MEMORY"]="1) Clear system cache
2) Restart heavy memory processes
3) Add more RAM or increase swap
4) Profile memory leaks"

RECOMMENDATIONS["DISK"]="1) Clean /tmp and old log files
2) Remove large unused files
3) Extend storage volume
4) Move data to external storage"

RECOMMENDATIONS["SERVICE"]="1) Restart failed service
2) Check configuration files
3) Rollback latest deployment
4) Investigate logs manually"

RECOMMENDATIONS["NETWORK"]="1) Restart network service
2) Check DNS or routing tables
3) Verify firewall rules
4) Replace NIC or driver"

# عرض الحلول بناءً على نوع التنبيه
if [[ -n "${RECOMMENDATIONS[$ALERT_TYPE]}" ]]; then
  echo "⚠️  Issue detected: $ALERT_TYPE"
  echo "Suggested solutions:"
  echo "${RECOMMENDATIONS[$ALERT_TYPE]}"
  echo
  read -p "Choose a solution (1-4) or 0 to skip: " choice

  case $ALERT_TYPE in
    CPU)
      case $choice in
        1) bash "$SCRIPT_DIR/handle_high_cpu.sh" ;;
        2) bash "$SCRIPT_DIR/restart_service.sh" nginx ;;
        3) echo "[$(date)] [CPU] Suggestion: scale up CPU" >> "$REC" ;;
        4) echo "[$(date)] [CPU] Suggestion: optimize app code" >> "$REC" ;;
      esac
      ;;
    MEMORY)
      case $choice in
        1) bash "$SCRIPT_DIR/handle_high_memory.sh" ;;
        2) pkill -9 -f python || true ;;
        3) echo "[$(date)] [MEMORY] Suggestion: add more RAM" >> "$REC" ;;
        4) echo "[$(date)] [MEMORY] Suggestion: run memory profiler" >> "$REC" ;;
      esac
      ;;
    DISK)
      case $choice in
        1) bash "$SCRIPT_DIR/handle_disk_alert.sh" ;;
        2) sudo find /home -type f -size +500M -delete ;;
        3) echo "[$(date)] [DISK] Suggestion: extend volume" >> "$REC" ;;
        4) echo "[$(date)] [DISK] Suggestion: move data to external storage" >> "$REC" ;;
      esac
      ;;
    SERVICE)
      case $choice in
        1) bash "$SCRIPT_DIR/restart_service.sh" ;;
        2) echo "[$(date)] [SERVICE] Suggestion: check config" >> "$REC" ;;
        3) echo "[$(date)] [SERVICE] Suggestion: rollback last deploy" >> "$REC" ;;
        4) echo "[$(date)] [SERVICE] Suggestion: investigate logs" >> "$REC" ;;
      esac
      ;;
    NETWORK)
      case $choice in
        1) bash "$SCRIPT_DIR/handle_network_issue.sh" ;;
        2) echo "[$(date)] [NETWORK] Suggestion: check DNS routes" >> "$REC" ;;
        3) echo "[$(date)] [NETWORK] Suggestion: verify firewall rules" >> "$REC" ;;
        4) echo "[$(date)] [NETWORK] Suggestion: replace NIC driver" >> "$REC" ;;
      esac
      ;;
  esac

  echo "[$(date)] [RECOMMENDATION] Choice $choice executed for $ALERT_TYPE" >> "$LOG"
else
  echo "[$(date)] [RECOMMENDATION] Unknown alert type: $ALERT_TYPE" >> "$LOG"
fi
