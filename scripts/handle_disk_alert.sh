#!/bin/bash
# ============================================================
# Self-Healing: Smart Disk Space Fix with Recommendations
# ============================================================

# Resolve paths relative to this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$BASE_DIR/logs"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/self_heal.log"
REC="$LOG_DIR/recommendations.json"

# Configuration
TARGET_DISK=85         # Target disk usage

# ============================================================
# Helper Functions
# ============================================================

get_disk_usage() {
    df / | awk 'NR==2 {print $5}' | tr -d '%'
}

clean_logs() {
    local freed=0
    echo "[$(date)] [DISK] Cleaning old logs (>7 days)..." >> "$LOG"
    local before=$(df / | awk 'NR==2 {print $3}')
    sudo find /var/log -name "*.log" -type f -mtime +7 -delete 2>/dev/null
    sudo find /var/log -name "*.gz" -type f -mtime +7 -delete 2>/dev/null
    local after=$(df / | awk 'NR==2 {print $3}')
    freed=$((before - after))
    echo "[$(date)] [DISK] Freed ${freed}KB from logs" >> "$LOG"
    echo $freed
}

clean_tmp() {
    local freed=0
    echo "[$(date)] [DISK] Cleaning /tmp (>3 days)..." >> "$LOG"
    local before=$(df / | awk 'NR==2 {print $3}')
    sudo find /tmp -type f -atime +3 -delete 2>/dev/null
    local after=$(df / | awk 'NR==2 {print $3}')
    freed=$((before - after))
    echo "[$(date)] [DISK] Freed ${freed}KB from /tmp" >> "$LOG"
    echo $freed
}

clean_cache() {
    local freed=0
    echo "[$(date)] [DISK] Cleaning package cache..." >> "$LOG"
    local before=$(df / | awk 'NR==2 {print $3}')
    sudo yum clean all 2>/dev/null || sudo apt-get clean 2>/dev/null
    local after=$(df / | awk 'NR==2 {print $3}')
    freed=$((before - after))
    echo "[$(date)] [DISK] Freed ${freed}KB from cache" >> "$LOG"
    echo $freed
}

clean_cores() {
    echo "[$(date)] [DISK] Removing core dumps..." >> "$LOG"
    sudo find / -type f -name "core" -delete 2>/dev/null
    sudo find / -type f -name "core.*" -delete 2>/dev/null
}

clean_docker() {
    local freed=0
    if command -v docker &> /dev/null; then
        echo "[$(date)] [DISK] Cleaning Docker resources..." >> "$LOG"
        local before=$(df / | awk 'NR==2 {print $3}')
        sudo docker system prune -af 2>/dev/null
        local after=$(df / | awk 'NR==2 {print $3}')
        freed=$((before - after))
        echo "[$(date)] [DISK] Freed ${freed}KB from Docker" >> "$LOG"
    fi
    echo $freed
}

generate_recommendation() {
    local severity="$1"
    local disk="$2"
    local freed_logs="$3"
    local freed_tmp="$4"
    local freed_cache="$5"
    local freed_docker="$6"
    
    local timestamp=$(date -Iseconds)
    local total_freed=$((freed_logs + freed_tmp + freed_cache + freed_docker))
    local rec_file="/tmp/disk_rec_$$.json"
    
    cat > "$rec_file" << EOF
{
  "timestamp": "$timestamp",
  "resource": "DISK",
  "severity": "$severity",
  "current_value": "${disk}%",
  "threshold": "85%",
  "actions_taken": {
    "logs_cleaned_kb": $freed_logs,
    "tmp_cleaned_kb": $freed_tmp,
    "cache_cleaned_kb": $freed_cache,
    "docker_cleaned_kb": $freed_docker,
    "total_freed_mb": $((total_freed / 1024))
  },
  "recommendations": {
    "immediate": [
      "Cleaned old logs and temporary files",
      "Removed package cache",
      "Check for large files: du -sh /* | sort -rh | head -10"
    ],
    "short_term": [
      "Set up log rotation (logrotate)",
      "Enable automatic cleanup cron jobs",
      "Move logs to separate volume",
      "Archive old data to S3"
    ],
    "long_term": [
      "Expand EBS volume (8GB → 16GB or 32GB)",
      "Add secondary EBS volume for data",
      "Implement lifecycle policies for logs",
      "Use EFS for shared storage",
      "Set up automated backups with cleanup",
      "Monitor disk growth trends"
    ]
  },
  "notification_channels": ["slack", "email"]
}
EOF
    
    if [ -f "$REC" ]; then
        echo "," >> "$REC"
    else
        echo "[" > "$REC"
    fi
    cat "$rec_file" >> "$REC"
    rm -f "$rec_file"
    
    if [ -x "$SCRIPT_DIR/notification_sender.sh" ]; then
        "$SCRIPT_DIR/notification_sender.sh" "DISK" "$severity" "$disk" &
    fi
}

# ============================================================
# Main Logic
# ============================================================

echo "[$(date)] [DISK] Smart healing started..." >> "$LOG"

current_disk=$(get_disk_usage)
echo "[$(date)] [DISK] Current usage: ${current_disk}%" >> "$LOG"

if (( current_disk < TARGET_DISK )); then
    echo "[$(date)] [DISK] Normal usage: ${current_disk}%" >> "$LOG"
    exit 0
fi

echo "[$(date)] [DISK] ALERT: High disk usage detected (${current_disk}%)" >> "$LOG"
echo "[$(date)] [DISK] Starting cleanup operations..." >> "$LOG"

# Perform all cleanup operations
freed_logs=$(clean_logs)
freed_tmp=$(clean_tmp)
freed_cache=$(clean_cache)
clean_cores
freed_docker=$(clean_docker)

# Check final status
final_disk=$(get_disk_usage)
total_freed=$((freed_logs + freed_tmp + freed_cache + freed_docker))
total_freed_mb=$((total_freed / 1024))

echo "[$(date)] [DISK] Healing completed - Final disk usage: ${final_disk}%" >> "$LOG"
echo "[$(date)] [DISK] Total space freed: ${total_freed_mb}MB" >> "$LOG"

# Generate recommendation
severity="WARNING"
if (( final_disk > 90 )); then
    severity="CRITICAL"
fi
generate_recommendation "$severity" "$final_disk" "$freed_logs" "$freed_tmp" "$freed_cache" "$freed_docker"

echo "[$(date)] [DISK] Smart healing finished" >> "$LOG"
