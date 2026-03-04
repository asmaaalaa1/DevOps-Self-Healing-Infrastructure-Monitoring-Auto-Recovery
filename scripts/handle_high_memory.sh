#!/bin/bash
# ================================================================
# Self-Healing: Smart High Memory Usage Fix with Recommendations
# ================================================================

# Resolve paths relative to this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$BASE_DIR/logs"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/self_heal.log"
REC="$LOG_DIR/recommendations.json"

# Configuration
TARGET_MEM=80          # Target memory usage
KILL_THRESHOLD=15      # Kill processes using > 15% memory
MAX_ITERATIONS=3       # Max kill attempts
WAIT_TIME=10          # Seconds to wait

# Critical processes to preserve
CRITICAL_PROCS="systemd,sshd,dockerd,containerd,nginx,apache2,postgres,mysql"

# ============================================================
# Helper Functions
# ============================================================

get_mem_usage() {
    # Calculate memory usage based on available memory (more accurate)
    free | awk '/Mem:/ {avail=$7; total=$2; used=total-avail; printf("%.0f"), used/total * 100}'
}

is_critical_process() {
    local proc_name="$1"
    echo "$CRITICAL_PROCS" | grep -wq "$proc_name"
}

clear_cache() {
    echo "[$(date)] [MEMORY] Clearing cache..." >> "$LOG"
    sudo sync
    echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null 2>&1
    sleep 2
}

generate_recommendation() {
    local severity="$1"
    local mem="$2"
    local cache_cleared="$3"
    local killed_procs="$4"
    local critical_procs="$5"
    
    local timestamp=$(date -Iseconds)
    local rec_file="/tmp/mem_rec_$$.json"
    
    cat > "$rec_file" << EOF
{
  "timestamp": "$timestamp",
  "resource": "MEMORY",
  "severity": "$severity",
  "current_value": "${mem}%",
  "threshold": "85%",
  "actions_taken": {
    "cache_cleared": $cache_cleared,
    "killed_processes": $killed_procs,
    "critical_processes_found": $critical_procs
  },
  "recommendations": {
    "immediate": [
      "Cleared system cache",
      "Killed memory-hungry non-critical processes",
      "Monitor for memory leaks"
    ],
    "short_term": [
      "Add swap space (2-4GB virtual memory)",
      "Restart applications with memory leaks",
      "Configure memory limits (systemd/Docker)",
      "Enable memory compression (zswap)"
    ],
    "long_term": [
      "Upgrade instance type (t3.micro 1GB → t3.small 2GB)",
      "Upgrade to t3.medium for 4GB RAM",
      "Use memory-optimized instances (r6i family)",
      "Separate DB to RDS",
      "Implement caching layer (Redis/ElastiCache)",
      "Optimize application memory usage",
      "Set up memory profiling and leak detection"
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
        "$SCRIPT_DIR/notification_sender.sh" "MEMORY" "$severity" "$mem" &
    fi
}

# ============================================================
# Main Logic
# ============================================================

echo "[$(date)] [MEMORY] Smart healing started..." >> "$LOG"

current_mem=$(get_mem_usage)
echo "[$(date)] [MEMORY] Current usage: ${current_mem}%" >> "$LOG"

if (( current_mem < TARGET_MEM )); then
    echo "[$(date)] [MEMORY] Normal usage: ${current_mem}%" >> "$LOG"
    exit 0
fi

echo "[$(date)] [MEMORY] ALERT: High memory usage detected (${current_mem}%)" >> "$LOG"

# Step 1: Clear cache first
clear_cache
cache_cleared=true
current_mem=$(get_mem_usage)
echo "[$(date)] [MEMORY] Usage after cache clear: ${current_mem}%" >> "$LOG"

if (( current_mem < TARGET_MEM )); then
    echo "[$(date)] [MEMORY] Resolved by clearing cache" >> "$LOG"
    generate_recommendation "WARNING" "$current_mem" "true" "0" "0"
    exit 0
fi

# Step 2: Gradual process termination
echo "[$(date)] [MEMORY] Starting gradual process termination..." >> "$LOG"

killed_count=0
critical_found=0
iteration=0

while (( $(get_mem_usage) > TARGET_MEM && iteration < MAX_ITERATIONS )); do
    iteration=$((iteration + 1))
    echo "[$(date)] [MEMORY] Iteration $iteration - Current Memory: $(get_mem_usage)%" >> "$LOG"
    
    # Get top memory process
    top_proc=$(ps -eo pid,comm,%mem --sort=-%mem | grep -v "PID" | head -n 1)
    pid=$(echo "$top_proc" | awk '{print $1}')
    proc_name=$(echo "$top_proc" | awk '{print $2}')
    proc_mem=$(echo "$top_proc" | awk '{print $3}' | cut -d. -f1)
    
    if (( proc_mem < KILL_THRESHOLD )); then
        echo "[$(date)] [MEMORY] Top process $proc_name uses only ${proc_mem}%, below threshold" >> "$LOG"
        break
    fi
    
    if is_critical_process "$proc_name"; then
        echo "[$(date)] [MEMORY] ⚠️  CRITICAL process: $proc_name (PID=$pid) using ${proc_mem}%" >> "$LOG"
        critical_found=$((critical_found + 1))
        generate_recommendation "CRITICAL" "$(get_mem_usage)" "$cache_cleared" "$killed_count" "$critical_found"
        break
    fi
    
    echo "[$(date)] [MEMORY] Killing: $proc_name (PID=$pid) using ${proc_mem}%" >> "$LOG"
    if sudo kill -9 "$pid" 2>/dev/null; then
        echo "[$(date)] [MEMORY] ✓ Process $pid terminated" >> "$LOG"
        killed_count=$((killed_count + 1))
    else
        echo "[$(date)] [MEMORY] ✗ Failed to kill process $pid" >> "$LOG"
    fi
    
    if (( iteration < MAX_ITERATIONS )); then
        sleep "$WAIT_TIME"
    fi
done

# Final status
final_mem=$(get_mem_usage)
echo "[$(date)] [MEMORY] Healing completed - Final Memory: ${final_mem}%" >> "$LOG"
echo "[$(date)] [MEMORY] Cache cleared: $cache_cleared, Killed: $killed_count, Critical: $critical_found" >> "$LOG"

# Generate final recommendation
severity="WARNING"
if (( final_mem > 90 || critical_found > 0 )); then
    severity="CRITICAL"
fi
generate_recommendation "$severity" "$final_mem" "$cache_cleared" "$killed_count" "$critical_found"

echo "[$(date)] [MEMORY] Smart healing finished" >> "$LOG"
