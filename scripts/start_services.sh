#!/bin/bash
# Start Self-Healing Services
# Webhook Receiver (port 5000) + Dashboard (port 5001)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="/opt/self-heal/logs"

mkdir -p "$LOG_DIR"

echo "🚀 Starting Self-Healing Services..."
echo "=================================="

# Start Webhook Receiver (port 5000)
echo "📡 Starting Webhook Receiver on port 5000..."
cd "$SCRIPT_DIR"
python3 webhook_receiver.py > "$LOG_DIR/webhook.log" 2>&1 &
WEBHOOK_PID=$!
echo "   PID: $WEBHOOK_PID"

# Wait a bit
sleep 2

# Start Dashboard (port 5001)
echo "🌐 Starting Dashboard on port 5001..."
cd "$SCRIPT_DIR/dashboard"
python3 app.py > "$LOG_DIR/dashboard.log" 2>&1 &
DASHBOARD_PID=$!
echo "   PID: $DASHBOARD_PID"

echo ""
echo "✅ Services Started!"
echo "=================================="
echo "📡 Webhook Receiver: http://localhost:5000"
echo "🌐 Dashboard: http://<server-ip>:5001"
echo ""
echo "📋 Logs:"
echo "   Webhook:   $LOG_DIR/webhook.log"
echo "   Dashboard: $LOG_DIR/dashboard.log"
echo ""
echo "🛑 To stop: kill $WEBHOOK_PID $DASHBOARD_PID"
echo "=================================="

# Save PIDs
echo "$WEBHOOK_PID" > "$LOG_DIR/webhook.pid"
echo "$DASHBOARD_PID" > "$LOG_DIR/dashboard.pid"
