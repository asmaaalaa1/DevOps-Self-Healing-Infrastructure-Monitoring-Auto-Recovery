# 🚀 Self-Healing Infrastructure Monitoring System

## 📋 Overview
DevOps project for self-monitoring and automatic healing using:
- **Terraform**: Deploy infrastructure on AWS
- **Prometheus**: Metrics collection and monitoring
- **Alertmanager**: Alert management  
- **Grafana**: Monitoring dashboards
- **Node Exporter**: System metrics from EC2
- **Self-Healing Scripts**: Automatic problem resolution
- **Interactive Dashboard**: Manual intervention & monitoring

---

## 🎯 Architecture

```
┌─────────────────────────────────────────────────────────┐
│                  Your Machine (Local)                   │
│                                                         │
│  ┌─────────────┐  ┌──────────────┐  ┌─────────────┐     │
│  │ Prometheus  │→ │ Alertmanager │→ │   Grafana   │     │
│  │   :9090     │  │    :9093     │  │    :3000    │     │
│  └──────┬──────┘  └──────┬───────┘  └─────────────┘     │
│         │                 │                             │
└─────────┼─────────────────┼─────────────────────────────┘
          │                 │
          │ scrape:9100     │ webhook:5000
          ↓                 ↓
┌─────────────────────────────────────────────────────────┐
│                   EC2 (Amazon Linux 2023)               │
│                                                         │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐   │
│  │ Node Exporter│  │   Webhook    │  │  Dashboard   │   │
│  │    :9100     │  │  Receiver    │  │    :5001     │   │
│  │              │  │    :5000     │  │              │   │
│  └──────────────┘  └──────┬───────┘  └──────┬───────┘   │
│                           │                 │           │
│                           ↓                 ↓           │
│  ┌──────────────────────────────────────────────────┐   │
│  │         Self-Healing Scripts & Monitoring        │   │
│  └──────────────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────────────┐   │
│  │  Docker Container: Patient Web App (Port 80)     │   │
│  └──────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

---

## 📦 Requirements

### On Your Machine:
- Terraform >= 1.0
- Docker & Docker Compose
- AWS CLI (optional)
- Python 3.8+ (for tests)

### On EC2 (Auto-installed):
- Docker
- Python 3 + pip
- Node Exporter
- FastAPI + Uvicorn + Flask

---

## 🚀 Quick Start (Automated Deployment)

### One-Command Deployment

```bash
cd "/home/abdelatty/Graduation_Project/DevOps_Self-Healing_Infra_Monitoring&Auto-Recovery"
bash quick_start.sh
```

This will automatically:
1. ✅ Deploy AWS infrastructure with Terraform
2. ✅ Update monitoring configs with EC2 IP
3. ✅ Start Prometheus, Grafana, Alertmanager
4. ✅ Verify all services are running

---

## 🧪 Testing the System

### Automated Demo Commands

```bash
# 1. Deploy everything
cd /home/abdelatty/Graduation_Project/DevOps_Self-Healing_Infra_Monitoring&Auto-Recovery
bash quick_start.sh

# 2. Get EC2 IP
EC2_IP=$(cd Terraform && terraform output -raw public_ip)

# 3. SSH to EC2 and navigate to tests
ssh -i Terraform/web-server-key.pem ec2-user@$EC2_IP
cd /opt/self-heal/tests

# 4. Run CPU Stress Test (2 minutes)
bash test_cpu_stress.sh 2

# 5. Run Memory Stress Test (600MB for 2 minutes)  
bash test_memory_stress.sh 600 2

# 6. Run Disk Stress Test (create 2GB files)
bash test_disk_stress.sh 2000

# 7. Run Web Load Test (100 users for 30 seconds)
bash test_web_load.sh 100 30

# 8. Run Service Downtime Test
bash test_web_downtime.sh
```

### Monitor Live System

```bash
# In parallel terminal, watch resources in real-time:
watch -n 1 "df -h / && echo '---' && free -m && echo '---' && uptime"
```

### Access Dashboards

- **Interactive Dashboard**: `http://<EC2_IP>:5001`
- **Grafana**: `http://localhost:3000` (admin/admin123)
- **Prometheus**: `http://localhost:9090`
- **Alertmanager**: `http://localhost:9093`

---

## 📊 Alert Rules Configuration

| Alert | Threshold | Duration | Auto-Action |
|-------|-----------|----------|-------------|
| **HighCPUUsage**  | > 80% | 30s | `handle_high_cpu.sh` |
| **HighMemoryUsage** | > 75% | 30s | `handle_high_memory.sh` |
| **HighDiskUsage** | > 85% | 30s | `handle_disk_alert.sh` |
| **HighNetworkErrors** | > 10/s | 3m | `handle_network_issue.sh` |
| **ServiceDown** | down | 1m | `restart_service.sh` |

---

## 🎨 Interactive Dashboard Features

Access at: `http://<EC2_IP>:5001`

**Features:**
- ✅ Real-time alert monitoring
- ✅ Alert history with timestamps
- ✅ System status overview
- ✅ Manual intervention options:
  - **CPU**: Kill high-usage processes
  - **Memory**: Clear cache or kill processes
  - **Disk**: Delete files or clear package cache
- ✅ Auto-refresh every 5 seconds
- ✅ Action result feedback

---

## 🔧 Service Management

### On Your Machine (Monitoring Stack):

```bash
cd monitoring

# Stop services
docker-compose down

# Restart services
docker-compose restart

# Delete data and restart fresh
docker-compose down -v
docker-compose up -d

# View logs
docker-compose logs -f
```

### On EC2:

```bash
# Node Exporter
sudo systemctl status node_exporter
sudo systemctl restart node_exporter

# Webhook Receiver
sudo systemctl status webhook
sudo systemctl restart webhook

# Dashboard
sudo systemctl status dashboard
sudo systemctl restart dashboard

# Docker App
docker ps
docker logs myapp
docker restart myapp
```

---

## 📁 Project Structure

```
DevOps_Self-Healing_Infra_Monitoring&Auto-Recovery/
├── Terraform/              # AWS Infrastructure
├── monitoring/             # Prometheus, Grafana, Alertmanager
├── scripts/                # Self-healing scripts & services
│   ├── dashboard/          # Interactive Flask dashboard
│   ├── webhook_receiver.py # Alert webhook handler
│   └── handle_*.sh         # Healing action scripts
├── tests/                  # Stress & performance tests
├── Patient-Web-interface/  # Flask web application
└── quick_start.sh          # One-command deployment
```

---

## 🐛 Troubleshooting

### Prometheus not scraping metrics

```bash
# Check Node Exporter on EC2
ssh -i Terraform/web-server-key.pem ec2-user@$EC2_IP
sudo systemctl status node_exporter
curl localhost:9100/metrics
```

### Alerts not reaching EC2

```bash
# Check Webhook Receiver
sudo systemctl status webhook
curl localhost:5000/health
sudo journalctl -u webhook -f
```

### Dashboard not accessible

```bash
# Check dashboard service
sudo systemctl status dashboard
sudo journalctl -u dashboard -f
sudo systemctl restart dashboard
```

---

## 🔐 Security Best Practices

1. **Restrict Security Group**: Use your IP instead of `0.0.0.0/0`
2. **Change Grafana Password**: Update in `docker-compose.yml`
3. **Protect SSH Key**: `chmod 400 web-server-key.pem`
4. **Use HTTPS**: Add SSL/TLS certificates

---

## ✅ Success Indicators

**System is working if:**
- ✅ All Prometheus targets show **UP** status
- ✅ Grafana displays real-time metrics
- ✅ Dashboard shows current alerts
- ✅ Stress tests trigger alerts within 30s
- ✅ Manual options work correctly
- ✅ Auto-healing executes successfully

---

**🚀 Ready for Production! Happy Monitoring!**
