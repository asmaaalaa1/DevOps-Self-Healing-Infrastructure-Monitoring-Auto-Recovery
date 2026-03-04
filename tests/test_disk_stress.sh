#!/bin/bash
# ============================================================
# Disk Stress Test - Trigger HighDiskUsage Alert
# ============================================================

# Configuration
SIZE_GB=${1:-5}           # Size to fill (GB) - default 5GB to reach 85% on 8GB disk
TARGET_HOST=${2:-}        # If provided, run on remote host
DURATION=${3:-300}        # Duration to keep files (seconds) - default 5 minutes

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEY_FILE="$SCRIPT_DIR/../Terraform/web-server-key.pem"
LOG="$SCRIPT_DIR/../logs/stress_tests.log"
mkdir -p "$(dirname "$LOG")"

echo "======================================" | tee -a "$LOG"
echo "[$(date)] Disk Stress Test Started" | tee -a "$LOG"
echo "Size to fill: ${SIZE_GB}GB" | tee -a "$LOG"
echo "======================================" | tee -a "$LOG"

# Function to run disk stress
run_disk_stress() {
    TEST_DIR="/tmp/disk_stress_test"
    mkdir -p "$TEST_DIR"
    
    echo "[$(date)] Creating ${SIZE_GB}GB file in $TEST_DIR..." | tee -a "$LOG"
    
    # Create large file
    dd if=/dev/zero of="$TEST_DIR/large_file.dat" bs=1M count=$((SIZE_GB * 1024)) 2>&1 | tee -a "$LOG"
    
    echo "[$(date)] File created. Disk usage:" | tee -a "$LOG"
    df -h / | tee -a "$LOG"
    
    echo "" | tee -a "$LOG"
    echo "Monitor: http://localhost:9090/alerts" | tee -a "$LOG"
    echo "" | tee -a "$LOG"
    echo "⚠️  File will remain until self-healing cleans it or you manually delete it" | tee -a "$LOG"
    echo "To cleanup manually: rm -rf $TEST_DIR" | tee -a "$LOG"
}

# Execute
if [ -n "$TARGET_HOST" ]; then
    echo "[$(date)] Running on remote host: $TARGET_HOST" | tee -a "$LOG"
    ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no "$TARGET_HOST" bash <<'EOF'
set -e

echo "======================================"
echo "[$(date)] Disk Stress Test Starting"
echo "======================================"

TEST_DIR="/home/ec2-user/disk_stress_test"
mkdir -p "$TEST_DIR"

# Get current disk usage
CURRENT_USAGE=$(df / | awk 'NR==2 {gsub("%",""); print $5}')
echo "📊 Current disk usage: ${CURRENT_USAGE}%"

# Calculate how much to fill to reach 95%
TOTAL_SIZE=$(df / | awk 'NR==2 {print $2}')
TARGET_USAGE=95
USED_SIZE=$(df / | awk 'NR==2 {print $3}')
TARGET_SIZE=$((TOTAL_SIZE * TARGET_USAGE / 100))
NEED_TO_FILL=$((TARGET_SIZE - USED_SIZE))

# Convert to MB for easier handling
NEED_MB=$((NEED_TO_FILL / 1024))

echo "🎯 Target: ${TARGET_USAGE}% (need to add ~$((NEED_MB / 1024))GB)"
echo ""

# Fill in 256MB chunks (smaller and safer)
CHUNK_SIZE=256  # MB
MAX_CHUNKS=30   # Safety limit
CHUNKS_WRITTEN=0

echo "📝 Filling disk in ${CHUNK_SIZE}MB chunks..."

while [ $CHUNKS_WRITTEN -lt $MAX_CHUNKS ]; do
    # Check if we need more space
    CURRENT=$(df / | awk 'NR==2 {gsub("%",""); print $5}')
    
    if [ "$CURRENT" -ge "$TARGET_USAGE" ]; then
        echo "✅ Reached ${CURRENT}% - Target achieved!"
        break
    fi
    
    # Write chunk with low priority
    CHUNKS_WRITTEN=$((CHUNKS_WRITTEN + 1))
    nice -n 19 dd if=/dev/zero of="$TEST_DIR/chunk_${CHUNKS_WRITTEN}.dat" bs=1M count=$CHUNK_SIZE 2>&1 | tail -1
    
    # Update progress
    CURRENT=$(df / | awk 'NR==2 {gsub("%",""); print $5}')
    echo "  ⏳ Chunk #${CHUNKS_WRITTEN}: Disk now at ${CURRENT}%"
    
    # Breathe
    sleep 0.5
done

echo ""
echo "======================================"
echo "📊 Final Disk Status:"
df -h / | grep -v Filesystem
echo "======================================"
echo "📁 Test files location: $TEST_DIR"
echo "📈 Monitor: Grafana Dashboard"
echo "🧹 Cleanup: rm -rf $TEST_DIR"
echo "======================================"
EOF
else
    run_disk_stress
fi

echo "" | tee -a "$LOG"
echo "✅ Test completed. Check Prometheus alerts for HighDiskUsage" | tee -a "$LOG"
