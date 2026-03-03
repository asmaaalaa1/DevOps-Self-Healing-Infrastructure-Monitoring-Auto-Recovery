#!/bin/bash
# Quick Start Script - Complete Setup and Deployment

set -e  # Exit on error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "╔════════════════════════════════════════════════════════╗"
echo "║   🚀 Self-Healing Infrastructure - Quick Start         ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Pre-flight checks
echo -e "${BLUE}🔍 Pre-flight Checks...${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check Docker
if ! command -v docker &> /dev/null; then
    echo -e "${RED}❌ Docker is not installed${NC}"
    echo -e "${YELLOW}📝 Install Docker first:${NC}"
    echo "   curl -fsSL https://get.docker.com -o get-docker.sh"
    echo "   sudo sh get-docker.sh"
    echo "   sudo usermod -aG docker \$USER"
    exit 1
fi
echo -e "${GREEN}✅ Docker found: $(docker --version)${NC}"

# Check Docker Compose
if ! command -v docker-compose &> /dev/null; then
    echo -e "${RED}❌ Docker Compose is not installed${NC}"
    echo -e "${YELLOW}📝 Install Docker Compose first:${NC}"
    echo "   sudo apt install docker-compose"
    echo "   OR"
    echo "   sudo curl -L \"https://github.com/docker/compose/releases/latest/download/docker-compose-\$(uname -s)-\$(uname -m)\" -o /usr/local/bin/docker-compose"
    echo "   sudo chmod +x /usr/local/bin/docker-compose"
    exit 1
fi
echo -e "${GREEN}✅ Docker Compose found: $(docker-compose --version)${NC}"

# Check Terraform
if ! command -v terraform &> /dev/null; then
    echo -e "${RED}❌ Terraform is not installed${NC}"
    echo -e "${YELLOW}📝 Install Terraform first:${NC}"
    echo "   wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip"
    echo "   unzip terraform_1.6.0_linux_amd64.zip"
    echo "   sudo mv terraform /usr/local/bin/"
    exit 1
fi
echo -e "${GREEN}✅ Terraform found: $(terraform version | head -1)${NC}"

# Check Docker daemon is running
if ! docker ps &> /dev/null; then
    echo -e "${RED}❌ Docker daemon is not running${NC}"
    echo -e "${YELLOW}📝 Start Docker:${NC}"
    echo "   sudo systemctl start docker"
    exit 1
fi
echo -e "${GREEN}✅ Docker daemon is running${NC}"

echo ""

# Step 1: Deploy Infrastructure
echo -e "${BLUE}📦 Step 1/5: Deploying AWS Infrastructure...${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
cd "$SCRIPT_DIR/Terraform"

if [ ! -f "web-server-key.pem" ]; then
    echo -e "${RED}❌ Error: web-server-key.pem not found${NC}"
    exit 1
fi

chmod 400 web-server-key.pem

echo "Initializing Terraform..."
terraform init -input=false

echo "Deploying infrastructure..."
terraform apply -auto-approve -input=false

EC2_IP=$(terraform output -raw public_ip)
echo -e "${GREEN}✅ EC2 Deployed: $EC2_IP${NC}"
echo ""

# Step 2: Wait for EC2 to be ready
echo -e "${BLUE}⏳ Step 2/5: Waiting for EC2 to be ready...${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
sleep 30

echo "Testing SSH connection..."
ssh -i web-server-key.pem -o StrictHostKeyChecking=no -o ConnectTimeout=10 ec2-user@$EC2_IP "echo 'SSH OK'" > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ SSH connection established${NC}"
else
    echo -e "${YELLOW}⚠️  SSH not ready yet, waiting 30 more seconds...${NC}"
    sleep 30
fi
echo ""

# Step 3: Verify services on EC2
echo -e "${BLUE}🔍 Step 3/5: Verifying EC2 services...${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "Checking Docker app..."
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://$EC2_IP || echo "000")
if [ "$HTTP_STATUS" = "200" ]; then
    echo -e "${GREEN}✅ Docker app is running (HTTP $HTTP_STATUS)${NC}"
else
    echo -e "${YELLOW}⚠️  Docker app status: HTTP $HTTP_STATUS${NC}"
fi

echo "Checking Node Exporter..."
METRICS=$(curl -s http://$EC2_IP:9100/metrics | head -n 1)
if [ ! -z "$METRICS" ]; then
    echo -e "${GREEN}✅ Node Exporter is running${NC}"
else
    echo -e "${YELLOW}⚠️  Node Exporter not responding${NC}"
fi

echo "Checking Webhook Receiver..."
HEALTH=$(curl -s http://$EC2_IP:5000/health)
if [[ "$HEALTH" == *"healthy"* ]]; then
    echo -e "${GREEN}✅ Webhook Receiver is running${NC}"
else
    echo -e "${YELLOW}⚠️  Webhook Receiver not ready yet${NC}"
fi
echo ""

# Step 4: Update monitoring configs
echo -e "${BLUE}📝 Step 4/5: Configuring monitoring stack...${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
cd "$SCRIPT_DIR"

echo "Updating EC2 IP in configurations..."
bash scripts/update_ec2_ip.sh $EC2_IP

echo -e "${GREEN}✅ Configurations updated with IP: $EC2_IP${NC}"
echo ""

# Step 5: Start monitoring stack
echo -e "${BLUE}🎛️  Step 5/5: Starting monitoring stack...${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "Moving to monitoring directory: $SCRIPT_DIR/monitoring"
cd "$SCRIPT_DIR/monitoring"

if [ ! -f "docker-compose.yml" ]; then
    echo -e "${RED}❌ Error: docker-compose.yml not found in $(pwd)${NC}"
    echo "Expected location: $SCRIPT_DIR/monitoring/docker-compose.yml"
    exit 1
fi

echo "Starting Prometheus, Alertmanager, and Grafana..."
docker-compose up -d

sleep 5

# Check if services are running
if docker-compose ps | grep -q "Up"; then
    echo -e "${GREEN}✅ Monitoring stack is running${NC}"
else
    echo -e "${RED}❌ Some services failed to start${NC}"
    docker-compose ps
fi
echo ""

# Final summary
echo "╔════════════════════════════════════════════════════════╗"
echo "║              🎉 Setup Complete!                        ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""
echo -e "${GREEN}📊 Access URLs:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "  🌐 Website:        ${BLUE}http://$EC2_IP${NC}"
echo -e "  📈 Prometheus:     ${BLUE}http://localhost:9090${NC}"
echo -e "  🚨 Alertmanager:   ${BLUE}http://localhost:9093${NC}"
echo -e "  📊 Grafana:        ${BLUE}http://localhost:3000${NC} (admin/admin123)"
echo -e "  🎛️  Dashboard:      ${BLUE}http://$EC2_IP:5001${NC} ⭐ ${GREEN}Interactive Control${NC}"
echo ""
echo -e "${GREEN}🔍 Monitoring Endpoints:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "  📊 Node Exporter:  ${BLUE}http://$EC2_IP:9100/metrics${NC}"
echo -e "  🪝 Webhook:        ${BLUE}http://$EC2_IP:5000/webhook${NC}"
echo -e "  📋 Recommendations:${BLUE}http://$EC2_IP:5000/recommendations${NC}"
echo -e "  ❤️  Health Check:  ${BLUE}http://$EC2_IP:5000/health${NC}"
echo ""
echo -e "${GREEN}🧪 Run Self-Healing Tests:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "  ${YELLOW}# Interactive menu - choose CPU/Memory/Disk tests${NC}"
echo -e "  ${YELLOW}cd $SCRIPT_DIR/tests${NC}"
echo -e "  ${YELLOW}./run_resource_tests.sh ec2-user@$EC2_IP${NC}"
echo ""
echo -e "  ${YELLOW}# Or run individual tests:${NC}"
echo -e "  ${YELLOW}./test_cpu_stress.sh 300 2 ec2-user@$EC2_IP${NC}     # 5min CPU test"
echo -e "  ${YELLOW}./test_memory_stress.sh 800 300 ec2-user@$EC2_IP${NC} # Memory test"
echo -e "  ${YELLOW}./test_disk_stress.sh 2 ec2-user@$EC2_IP${NC}        # Disk test"
echo ""
echo -e "${GREEN}🌐 Website Load Tests (Optional):${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "  ${YELLOW}cd $SCRIPT_DIR/tests${NC}"
echo -e "  ${YELLOW}./test_web_latency.sh http://$EC2_IP 50${NC}"
echo -e "  ${YELLOW}./test_web_load.sh http://$EC2_IP 200${NC}"
echo -e "  ${YELLOW}./run_website_tests.sh http://$EC2_IP${NC}"
echo ""
echo -e "${BLUE}💡 Note: Tests trigger alerts → self-healing scripts execute → recommendations generated${NC}"
echo ""
echo -e "${GREEN}📝 View Logs:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "  ${YELLOW}# Local monitoring logs${NC}"
echo -e "  ${YELLOW}cd $SCRIPT_DIR/monitoring && docker-compose logs -f${NC}"
echo ""
echo -e "  ${YELLOW}# SSH to EC2 and check logs${NC}"
echo -e "  ${YELLOW}ssh -i $SCRIPT_DIR/Terraform/web-server-key.pem ec2-user@$EC2_IP${NC}"
echo ""
echo -e "  ${YELLOW}# On EC2: Self-healing logs${NC}"
echo -e "  ${YELLOW}tail -f /opt/self-heal/logs/self_heal.log${NC}"
echo -e "  ${YELLOW}cat /opt/self-heal/logs/recommendations.json | jq .${NC}"
echo -e "  ${YELLOW}sudo journalctl -u webhook-receiver -f${NC}"
echo ""
echo -e "${GREEN}🔧 Approve/Dismiss Recommendations:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "  ${YELLOW}# View recommendations${NC}"
echo -e "  ${YELLOW}curl http://$EC2_IP:5000/recommendations | jq .${NC}"
echo ""
echo -e "  ${YELLOW}# Approve action${NC}"
echo -e "  ${YELLOW}curl -X POST http://$EC2_IP:5000/approve-action \\${NC}"
echo -e "  ${YELLOW}  -H 'Content-Type: application/json' \\${NC}"
echo -e "  ${YELLOW}  -d '{\"action\":\"upgrade_instance\",\"resource\":\"CPU\"}'${NC}"
echo ""
echo -e "  ${YELLOW}# Dismiss recommendation${NC}"
echo -e "  ${YELLOW}curl -X POST http://$EC2_IP:5000/dismiss-recommendation \\${NC}"
echo -e "  ${YELLOW}  -H 'Content-Type: application/json' \\${NC}"
echo -e "  ${YELLOW}  -d '{\"recommendation_id\":\"123\",\"reason\":\"Not needed\"}'${NC}"
echo ""
echo -e "${BLUE}📚 For more details, see: README.md${NC}"
echo ""
