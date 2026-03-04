#!/bin/bash
# ============================================================
# CPU Stress Test - Trigger HighCPUUsage Alert
# ============================================================

# Configuration
DURATION=${1:-300}        # Default 5 minutes
CORES=${2:-2}             # Number of CPU cores to stress
TARGET_HOST=${3:-}        # If provided, run on remote host via SSH

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEY_FILE="$SCRIPT_DIR/../Terraform/web-server-key.pem"
LOG="$SCRIPT_DIR/../logs/stress_tests.log"
mkdir -p "$(dirname "$LOG")"

echo "======================================" | tee -a "$LOG"
echo "[$(date)] CPU Stress Test Started" | tee -a "$LOG"
echo "Duration: ${DURATION}s, Cores: $CORES" | tee -a "$LOG"
echo "======================================" | tee -a "$LOG"

# Function to run stress test
run_stress() {
    echo "[$(date)] Starting CPU stress with $CORES processes..." | tee -a "$LOG"
    
    # Start CPU-intensive processes
    pids=()
    for i in $(seq 1 $CORES); do
        yes > /dev/null &
        pids+=($!)
        echo "  Process $i started (PID: ${pids[$i-1]})" | tee -a "$LOG"
    done
    
    echo "[$(date)] CPU stress running for ${DURATION}s..." | tee -a "$LOG"
    echo "Monitor: http://localhost:9090/alerts" | tee -a "$LOG"
    echo "Dashboard: http://localhost:3000" | tee -a "$LOG"
    echo "" | tee -a "$LOG"
    
    # Wait for duration
    sleep "$DURATION"
    
    # Kill processes
    echo "[$(date)] Stopping CPU stress..." | tee -a "$LOG"
    for pid in "${pids[@]}"; do
        kill -9 "$pid" 2>/dev/null
        echo "  Killed PID: $pid" | tee -a "$LOG"
    done
    
    echo "[$(date)] CPU stress test completed" | tee -a "$LOG"
}

# Execute locally or remotely
if [ -n "$TARGET_HOST" ]; then
    echo "[$(date)] Running stress test on remote host: $TARGET_HOST" | tee -a "$LOG"
    ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no "$TARGET_HOST" bash <<EOF
echo "[$(date)] Starting CPU stress test..."
echo "Cores: ${CORES}, Duration: ${DURATION}s"

if command -v stress-ng &> /dev/null; then
    nohup stress-ng --cpu ${CORES} --timeout ${DURATION}s > /tmp/cpu_stress.log 2>&1 &
    pid=\$!
    echo "  stress-ng started (PID: \$pid)"
else
    # Fallback: use dd for CPU stress
    for i in \$(seq 1 ${CORES}); do
        nohup dd if=/dev/zero of=/dev/null bs=1M > /tmp/cpu_stress_\$i.log 2>&1 &
    done
    echo "  dd processes started for ${CORES} cores"
fi

echo "[$(date)] CPU stress running for ${DURATION}s..."
sleep 2
top -bn1 | head -5
echo ""
echo "Monitor Grafana for CPU Usage spike!"
EOF
else
    run_stress
fi

echo "" | tee -a "$LOG"
echo "✅ Test completed. Check Prometheus alerts for HighCPUUsage" | tee -a "$LOG"
echo "Expected: Alert should fire after 2 minutes" | tee -a "$LOG"
