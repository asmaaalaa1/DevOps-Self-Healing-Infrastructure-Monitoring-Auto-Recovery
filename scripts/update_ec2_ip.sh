#!/bin/bash
# ============================================================
# Update EC2 IP in all configuration files after deployment
# ============================================================

if [ -z "$1" ]; then
    echo "Usage: $0 <EC2_PUBLIC_IP>"
    echo "Example: $0 54.123.45.67"
    exit 1
fi

EC2_IP="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "Updating EC2 IP to: $EC2_IP"

# Update Prometheus configuration
PROM_CONFIG="$BASE_DIR/monitoring/prometheus.yml"
if [ -f "$PROM_CONFIG" ]; then
    sed -i "s/targets: \['.*:9100'\]/targets: ['$EC2_IP:9100']/" "$PROM_CONFIG"
    echo "✓ Updated Prometheus config"
fi

# Update Alertmanager configuration
ALERT_CONFIG="$BASE_DIR/monitoring/alertmanager.yml"
if [ -f "$ALERT_CONFIG" ]; then
    sed -i "s|url: 'http://.*:5000/webhook'|url: 'http://$EC2_IP:5000/webhook'|" "$ALERT_CONFIG"
    echo "✓ Updated Alertmanager config"
fi

# Update Grafana dashboard
DASHBOARD="$BASE_DIR/monitoring/grafana/provisioning/dashboards/self-healing.json"
if [ -f "$DASHBOARD" ]; then
    sed -i "s/EC2_IP/$EC2_IP/g" "$DASHBOARD"
    echo "✓ Updated Grafana dashboard"
fi

echo ""
echo "✅ All configurations updated with IP: $EC2_IP"
echo ""
echo "Next steps:"
echo "1. Restart monitoring stack: cd monitoring && docker-compose restart"
echo "2. Verify Prometheus targets: http://localhost:9090/targets"
echo "3. Open Grafana dashboard: http://localhost:3000"
