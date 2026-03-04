#!/bin/bash
# ============================================================
# Memory Stress Test - Trigger HighMemoryUsage Alert
# ============================================================

# Configuration
SIZE_MB=${1:-500}         # Memory to consume (MB)
DURATION=${2:-300}        # Duration in seconds
TARGET_HOST=${3:-}        # If provided, run on remote host

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEY_FILE="$SCRIPT_DIR/../Terraform/web-server-key.pem"
LOG="$SCRIPT_DIR/../logs/stress_tests.log"
mkdir -p "$(dirname "$LOG")"

echo "======================================" | tee -a "$LOG"
echo "[$(date)] Memory Stress Test Started" | tee -a "$LOG"
echo "Size: ${SIZE_MB}MB, Duration: ${DURATION}s" | tee -a "$LOG"
echo "======================================" | tee -a "$LOG"

# Function to run memory stress
run_memory_stress() {
    echo "[$(date)] Allocating ${SIZE_MB}MB of memory..." | tee -a "$LOG"
    
    # Use stress-ng if available, otherwise use dd
    if command -v stress-ng &> /dev/null; then
        stress-ng --vm 1 --vm-bytes ${SIZE_MB}M --timeout ${DURATION}s &
        pid=$!
        echo "  stress-ng started (PID: $pid)" | tee -a "$LOG"
    else
        # Fallback: allocate memory using Python
        python3 -c "
import time
data = ' ' * (1024 * 1024 * $SIZE_MB)
print('Memory allocated: ${SIZE_MB}MB')
time.sleep($DURATION)
" &
        pid=$!
        echo "  Python memory allocation started (PID: $pid)" | tee -a "$LOG"
    fi
    
    echo "[$(date)] Memory stress running for ${DURATION}s..." | tee -a "$LOG"
    echo "Monitor: http://localhost:9090/alerts" | tee -a "$LOG"
    echo "" | tee -a "$LOG"
    
    wait $pid
    echo "[$(date)] Memory stress test completed" | tee -a "$LOG"
}

# Execute
if [ -n "$TARGET_HOST" ]; then
    echo "[$(date)] Running on remote host: $TARGET_HOST" | tee -a "$LOG"
    ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no "$TARGET_HOST" bash <<EOF
echo "[$(date)] Allocating ${SIZE_MB}MB of memory..."

if command -v stress-ng &> /dev/null; then
    nohup stress-ng --vm 1 --vm-bytes ${SIZE_MB}M --timeout ${DURATION}s > /tmp/memory_stress.log 2>&1 &
    pid=\$!
    echo "  stress-ng started (PID: \$pid)"
else
    nohup python3 -c "import time; data = ' ' * (1024 * 1024 * ${SIZE_MB}); print('Memory allocated: ${SIZE_MB}MB'); time.sleep(${DURATION})" > /tmp/memory_stress.log 2>&1 &
    pid=\$!
    echo "  Python memory allocation started (PID: \$pid)"
fi

echo "[$(date)] Memory stress running for ${DURATION}s..."
sleep 2
free -h
echo ""
echo "Monitor Grafana for Memory Usage spike!"
EOF
else
    run_memory_stress
fi

echo "" | tee -a "$LOG"
echo "✅ Test completed. Check Prometheus alerts for HighMemoryUsage" | tee -a "$LOG"
