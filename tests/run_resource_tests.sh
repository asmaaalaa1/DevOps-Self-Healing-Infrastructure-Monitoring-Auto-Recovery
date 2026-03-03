#!/bin/bash
# ============================================================
# Run All Resource Stress Tests
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG="$SCRIPT_DIR/../logs/stress_tests.log"
TARGET_HOST="$1"  # Optional: SSH target (e.g., ec2-user@IP)

mkdir -p "$(dirname "$LOG")"

echo "=========================================" | tee -a "$LOG"
echo "  Self-Healing Resource Stress Tests" | tee -a "$LOG"
echo "=========================================" | tee -a "$LOG"
echo "Start Time: $(date)" | tee -a "$LOG"
echo "" | tee -a "$LOG"

if [ -n "$TARGET_HOST" ]; then
    echo "Target: Remote host ($TARGET_HOST)" | tee -a "$LOG"
else
    echo "Target: Local host" | tee -a "$LOG"
fi

echo "" | tee -a "$LOG"
echo "Tests will trigger the following alerts:" | tee -a "$LOG"
echo "  1. HighCPUUsage (>80% for 2min)" | tee -a "$LOG"
echo "  2. HighMemoryUsage (>85%)" | tee -a "$LOG"
echo "  3. HighDiskUsage (>85%)" | tee -a "$LOG"
echo "" | tee -a "$LOG"

# Test selection
echo "Select test to run:" | tee -a "$LOG"
echo "  1) CPU Stress Test" | tee -a "$LOG"
echo "  2) Memory Stress Test" | tee -a "$LOG"
echo "  3) Disk Stress Test" | tee -a "$LOG"
echo "  4) All Tests (sequential)" | tee -a "$LOG"
echo "  5) Exit" | tee -a "$LOG"
echo "" | tee -a "$LOG"

read -p "Enter choice [1-5]: " choice

case $choice in
    1)
        echo "" | tee -a "$LOG"
        echo "🔥 Running CPU Stress Test..." | tee -a "$LOG"
        bash "$SCRIPT_DIR/test_cpu_stress.sh" 300 2 "$TARGET_HOST"
        ;;
    2)
        echo "" | tee -a "$LOG"
        echo "🧠 Running Memory Stress Test..." | tee -a "$LOG"
        # For t3.micro (1GB RAM), allocate 800MB to reach ~80%
        bash "$SCRIPT_DIR/test_memory_stress.sh" 800 300 "$TARGET_HOST"
        ;;
    3)
        echo "" | tee -a "$LOG"
        echo "💾 Running Disk Stress Test..." | tee -a "$LOG"
        bash "$SCRIPT_DIR/test_disk_stress.sh" 2 "$TARGET_HOST"
        ;;
    4)
        echo "" | tee -a "$LOG"
        echo "🚀 Running ALL Tests Sequentially..." | tee -a "$LOG"
        echo "" | tee -a "$LOG"
        
        echo "[1/3] CPU Stress Test (5 minutes)..." | tee -a "$LOG"
        bash "$SCRIPT_DIR/test_cpu_stress.sh" 300 2 "$TARGET_HOST"
        echo "Waiting 2 minutes before next test..." | tee -a "$LOG"
        sleep 120
        
        echo "[2/3] Memory Stress Test (5 minutes)..." | tee -a "$LOG"
        bash "$SCRIPT_DIR/test_memory_stress.sh" 800 300 "$TARGET_HOST"
        echo "Waiting 2 minutes before next test..." | tee -a "$LOG"
        sleep 120
        
        echo "[3/3] Disk Stress Test..." | tee -a "$LOG"
        bash "$SCRIPT_DIR/test_disk_stress.sh" 2 "$TARGET_HOST"
        ;;
    5)
        echo "Exiting..." | tee -a "$LOG"
        exit 0
        ;;
    *)
        echo "Invalid choice!" | tee -a "$LOG"
        exit 1
        ;;
esac

echo "" | tee -a "$LOG"
echo "=========================================" | tee -a "$LOG"
echo "  Tests Completed" | tee -a "$LOG"
echo "=========================================" | tee -a "$LOG"
echo "End Time: $(date)" | tee -a "$LOG"
echo "" | tee -a "$LOG"
echo "📊 View Results:" | tee -a "$LOG"
echo "  - Prometheus Alerts: http://localhost:9090/alerts" | tee -a "$LOG"
echo "  - Grafana Dashboard: http://localhost:3000" | tee -a "$LOG"
echo "  - Healing Logs: cat /opt/self-heal/logs/self_heal.log" | tee -a "$LOG"
echo "  - Recommendations: cat /opt/self-heal/logs/recommendations.json" | tee -a "$LOG"
