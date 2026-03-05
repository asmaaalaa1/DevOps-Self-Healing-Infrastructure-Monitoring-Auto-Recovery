#!/bin/bash
# Script to update EC2 IP in monitoring configuration files

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "🔍 Getting EC2 IP from Terraform..."

# Get EC2 IP from Terraform output
cd "$BASE_DIR/Terraform"
EC2_IP=$(terraform output -raw public_ip 2>/dev/null)

if [ -z "$EC2_IP" ]; then
    echo "❌ Failed to get EC2 IP from Terraform"
    echo "   Make sure you have run 'terraform apply' first"
    exit 1
fi

echo "✅ Found EC2 IP: $EC2_IP"
echo ""

# Update prometheus.yml
echo "📝 Updating prometheus.yml..."
cd "$BASE_DIR/monitoring"

if [ -f "prometheus.yml" ]; then
    sed -i.bak "s/<EC2_PUBLIC_IP>/$EC2_IP/g" prometheus.yml
    sed -i.bak "s/- targets: \['[0-9.]*:9100'\]/- targets: ['$EC2_IP:9100']/g" prometheus.yml
    echo "   ✅ prometheus.yml updated"
else
    echo "   ❌ prometheus.yml not found"
fi

# Update alertmanager.yml
echo "📝 Updating alertmanager.yml..."
if [ -f "alertmanager.yml" ]; then
    sed -i.bak "s/<EC2_PUBLIC_IP>/$EC2_IP/g" alertmanager.yml
    sed -i.bak "s|url: 'http://[0-9.]*:5000/webhook'|url: 'http://$EC2_IP:5000/webhook'|g" alertmanager.yml
    echo "   ✅ alertmanager.yml updated"
else
    echo "   ❌ alertmanager.yml not found"
fi

echo ""
echo "🎉 Configuration files updated successfully!"
echo ""
echo "📋 Summary:"
echo "   EC2 IP: $EC2_IP"
echo "   Node Exporter: http://$EC2_IP:9100/metrics"
echo "   Webhook Receiver: http://$EC2_IP:5000/webhook"
echo ""
echo "🚀 Next steps:"
echo "   1. cd $BASE_DIR/monitoring"
echo "   2. docker-compose up -d"
echo "   3. Open Grafana: http://localhost:3000"
echo ""
