#!/bin/bash
# ============================================================
# Self-Healing: Smart High CPU Usage Fix with Recommendations
# ============================================================

# Resolve paths relative to this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$BASE_DIR/logs"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/self_heal.log"
REC="$LOG_DIR/recommendations.json"
NOTIF="$LOG_DIR/notifications.log"

# Configuration
TARGET_CPU=80          # Target CPU to reach
KILL_THRESHOLD=40      # Kill processes using > 40% CPU
MAX_ITERATIONS=5       # Max kill attempts
WAIT_TIME=10          # Seconds to wait between kills

# Critical processes to preserve (comma-separated)
CRITICAL_PROCS="systemd,sshd,dockerd,containerd,python3,node,postgres,mysql,nginx,apache2"

# ============================================================
# Helper Functions
# ============================================================

get_cpu_usage() {
    LANG=C top -bn1 | grep "Cpu(s)" | awk '{print 100 - $8}' | cut -d. -f1
}

is_critical_process() {
    local proc_name="$1"
    echo "$CRITICAL_PROCS" | grep -wq "$proc_name"
}

generate_recommendation() {
    local severity="$1"
    local cpu="$2"
    local killed_procs="$3"
    local critical_procs="$4"
    
    local timestamp=$(date -Iseconds)
    local rec_file="/tmp/cpu_rec_$$.json"
    
    cat > "$rec_file" << EOF
{
  "timestamp": "$timestamp",
  "resource": "CPU",
  "severity": "$severity",
  "current_value": "${cpu}%",
  "threshold": "80%",
  "actions_taken": {
    "killed_processes": $killed_procs,
    "critical_processes_found": $critical_procs
  },
  "recommendations": {
    "immediate": [
      "Killed non-critical high CPU processes",
      "Monitor for recurring issues"
    ],
    "short_term": [
      "Optimize application code",
      "Add process limits (cgroups)",
      "Enable CPU throttling for non-critical services"
    ],
    "long_term": [
      "Upgrade instance type (t3.micro → t3.small for 2 vCPUs)",
      "Upgrade to t3.medium for 4 vCPUs",
      "Implement Auto Scaling for horizontal scaling",
      "Use compute-optimized instances (c6i family)",
      "Set up CPU usage trending and capacity planning"
    ]
  },
  "notification_channels": ["slack", "email"]
}
EOF
    
    # Append to recommendations file
    if [ -f "$REC" ]; then
        echo "," >> "$REC"
    else
        echo "[" > "$REC"
    fi
    cat "$rec_file" >> "$REC"
    rm -f "$rec_file"
    
    # Call notification system
    if [ -x "$SCRIPT_DIR/notification_sender.sh" ]; then
        "$SCRIPT_DIR/notification_sender.sh" "CPU" "$severity" "$cpu" &
    fi
}

# ============================================================
# Main Logic
# ============================================================

echo "[$(date)] [CPU] Smart healing started..." >> "$LOG"

current_cpu=$(get_cpu_usage)
echo "[$(date)] [CPU] Current usage: ${current_cpu}%" >> "$LOG"

if (( current_cpu < TARGET_CPU )); then
    echo "[$(date)] [CPU] Normal usage: ${current_cpu}%" >> "$LOG"
    exit 0
fi

echo "[$(date)] [CPU] ALERT: High CPU usage detected (${current_cpu}%)" >> "$LOG"
echo "[$(date)] [CPU] Starting gradual process termination..." >> "$LOG"

killed_count=0
critical_found=0
iteration=0

while (( $(get_cpu_usage) > TARGET_CPU && iteration < MAX_ITERATIONS )); do
    iteration=$((iteration + 1))
    echo "[$(date)] [CPU] Iteration $iteration - Current CPU: $(get_cpu_usage)%" >> "$LOG"
    
    # Get top CPU process
    top_proc=$(ps -eo pid,comm,%cpu --sort=-%cpu | grep -v "PID" | head -n 1)
    pid=$(echo "$top_proc" | awk '{print $1}')
    proc_name=$(echo "$top_proc" | awk '{print $2}')
    proc_cpu=$(echo "$top_proc" | awk '{print $3}' | cut -d. -f1)
    
    # Skip if process uses less than threshold
    if (( proc_cpu < KILL_THRESHOLD )); then
        echo "[$(date)] [CPU] Top process $proc_name uses only ${proc_cpu}%, below kill threshold" >> "$LOG"
        break
    fi
    
    # Check if critical
    if is_critical_process "$proc_name"; then
        echo "[$(date)] [CPU] ⚠️  CRITICAL process detected: $proc_name (PID=$pid) using ${proc_cpu}%" >> "$LOG"
        echo "[$(date)] [CPU] Recommendation: $proc_name is critical - consider scaling resources" >> "$LOG"
        critical_found=$((critical_found + 1))
        
        # Generate high-priority recommendation
        generate_recommendation "CRITICAL" "$(get_cpu_usage)" "$killed_count" "$critical_found"
        break
    fi
    
    # Kill non-critical process
    echo "[$(date)] [CPU] Killing non-critical process: $proc_name (PID=$pid) using ${proc_cpu}%" >> "$LOG"
    if sudo kill -9 "$pid" 2>/dev/null; then
        echo "[$(date)] [CPU] ✓ Process $pid terminated successfully" >> "$LOG"
        killed_count=$((killed_count + 1))
    else
        echo "[$(date)] [CPU] ✗ Failed to kill process $pid" >> "$LOG"
    fi
    
    # Wait before next iteration
    if (( iteration < MAX_ITERATIONS )); then
        echo "[$(date)] [CPU] Waiting ${WAIT_TIME}s before next check..." >> "$LOG"
        sleep "$WAIT_TIME"
    fi
done

# Final status
final_cpu=$(get_cpu_usage)
echo "[$(date)] [CPU] Healing completed - Final CPU: ${final_cpu}%" >> "$LOG"
echo "[$(date)] [CPU] Processes killed: $killed_count, Critical processes found: $critical_found" >> "$LOG"

# Generate final recommendation
if (( killed_count > 0 || critical_found > 0 )); then
    severity="WARNING"
    if (( final_cpu > 90 || critical_found > 0 )); then
        severity="CRITICAL"
    fi
    generate_recommendation "$severity" "$final_cpu" "$killed_count" "$critical_found"
fi

echo "[$(date)] [CPU] Smart healing finished" >> "$LOG"
