#!/bin/bash
# ============================================================
# Self-Healing: Smart Network Fix with Recommendations
# ============================================================

# Resolve paths relative to this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$BASE_DIR/logs"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/self_heal.log"
REC="$LOG_DIR/recommendations.json"

# Configuration
TEST_HOSTS=("8.8.8.8" "1.1.1.1" "208.67.222.222")  # Google, Cloudflare, OpenDNS

# ============================================================
# Helper Functions
# ============================================================

test_connectivity() {
    local host="$1"
    ping -c 2 -W 3 "$host" >/dev/null 2>&1
}

check_network_saturation() {
    # Check if network is saturated (high packet loss/latency)
    local result=$(ping -c 10 -i 0.2 8.8.8.8 2>/dev/null | tail -1)
    if echo "$result" | grep -q "packet loss"; then
        echo "$result" | awk -F',' '{print $3}' | awk '{print $1}' | tr -d '%'
    else
        echo "0"
    fi
}

restart_network_service() {
    echo "[$(date)] [NETWORK] Restarting network service..." >> "$LOG"
    
    if systemctl list-units | grep -q NetworkManager; then
        sudo systemctl restart NetworkManager
    elif systemctl list-units | grep -q systemd-networkd; then
        sudo systemctl restart systemd-networkd
    else
        sudo systemctl restart networking
    fi
    
    sleep 5
}

flush_dns() {
    echo "[$(date)] [NETWORK] Flushing DNS cache..." >> "$LOG"
    sudo systemd-resolve --flush-caches 2>/dev/null || true
    sudo resolvectl flush-caches 2>/dev/null || true
}

kill_network_hogs() {
    echo "[$(date)] [NETWORK] Checking for bandwidth hogs..." >> "$LOG"
    
    # Get top network-using processes (if ss/netstat available)
    if command -v ss &> /dev/null; then
        local conn_count=$(ss -tn | wc -l)
        echo "[$(date)] [NETWORK] Active TCP connections: $conn_count" >> "$LOG"
        
        # If excessive connections, log top processes
        if (( conn_count > 1000 )); then
            echo "[$(date)] [NETWORK] ⚠️  Excessive connections detected!" >> "$LOG"
            lsof -i -P -n 2>/dev/null | awk '{print $1}' | sort | uniq -c | sort -rn | head -5 >> "$LOG"
        fi
    fi
}

generate_recommendation() {
    local severity="$1"
    local connectivity_restored="$2"
    local packet_loss="$3"
    local actions="$4"
    
    local timestamp=$(date -Iseconds)
    local rec_file="/tmp/net_rec_$$.json"
    
    cat > "$rec_file" << EOF
{
  "timestamp": "$timestamp",
  "resource": "NETWORK",
  "severity": "$severity",
  "current_value": "Packet Loss: ${packet_loss}%",
  "threshold": "Network reachability",
  "actions_taken": {
    "connectivity_restored": $connectivity_restored,
    "actions_performed": "$actions"
  },
  "recommendations": {
    "immediate": [
      "Network service restarted",
      "DNS cache flushed",
      "Check security groups/firewall rules"
    ],
    "short_term": [
      "Monitor network metrics (bandwidth, latency, packet loss)",
      "Set up network performance baselines",
      "Implement connection limits",
      "Configure quality of service (QoS)"
    ],
    "long_term": [
      "Upgrade network bandwidth (enhance EC2 instance)",
      "Use enhanced networking (ENA driver)",
      "Implement CDN (CloudFront) for static content",
      "Set up VPC flow logs for analysis",
      "Consider Direct Connect for dedicated bandwidth",
      "Implement DDoS protection (AWS Shield)",
      "Use Elastic Load Balancer for traffic distribution"
    ]
  },
  "notification_channels": ["slack", "email"]
}
EOF
    
    if [ -f "$REC" ]; then
        echo "," >> "$REC"
    else
        echo "[" > "$REC"
    fi
    cat "$rec_file" >> "$REC"
    rm -f "$rec_file"
    
    if [ -x "$SCRIPT_DIR/notification_sender.sh" ]; then
        "$SCRIPT_DIR/notification_sender.sh" "NETWORK" "$severity" "connectivity" &
    fi
}

# ============================================================
# Main Logic
# ============================================================

echo "[$(date)] [NETWORK] Smart healing started..." >> "$LOG"

# Test connectivity to multiple hosts
connectivity_ok=false
reachable_hosts=0

for host in "${TEST_HOSTS[@]}"; do
    if test_connectivity "$host"; then
        reachable_hosts=$((reachable_hosts + 1))
        echo "[$(date)] [NETWORK] ✓ Host $host is reachable" >> "$LOG"
    else
        echo "[$(date)] [NETWORK] ✗ Host $host is NOT reachable" >> "$LOG"
    fi
done

if (( reachable_hosts == ${#TEST_HOSTS[@]} )); then
    echo "[$(date)] [NETWORK] All hosts reachable - Connectivity OK" >> "$LOG"
    
    # Check for packet loss even if connected
    packet_loss=$(check_network_saturation)
    if (( packet_loss > 10 )); then
        echo "[$(date)] [NETWORK] ⚠️  High packet loss detected: ${packet_loss}%" >> "$LOG"
        kill_network_hogs
        generate_recommendation "WARNING" "true" "$packet_loss" "Checked for network saturation"
    fi
    
    exit 0
fi

echo "[$(date)] [NETWORK] ALERT: Network connectivity issue detected!" >> "$LOG"
echo "[$(date)] [NETWORK] Reachable hosts: $reachable_hosts/${#TEST_HOSTS[@]}" >> "$LOG"

# Perform healing actions
actions_taken=""

# Action 1: Flush DNS
flush_dns
actions_taken="DNS flushed"

# Action 2: Check for network hogs
kill_network_hogs
actions_taken="$actions_taken, checked bandwidth"

# Action 3: Restart network service
restart_network_service
actions_taken="$actions_taken, service restarted"

# Retest connectivity
sleep 5
restored=false
for host in "${TEST_HOSTS[@]}"; do
    if test_connectivity "$host"; then
        echo "[$(date)] [NETWORK] ✓ SUCCESS: Connectivity to $host restored!" >> "$LOG"
        restored=true
        break
    fi
done

packet_loss=$(check_network_saturation)

if [ "$restored" = true ]; then
    echo "[$(date)] [NETWORK] Network connectivity restored" >> "$LOG"
    generate_recommendation "WARNING" "true" "$packet_loss" "$actions_taken"
else
    echo "[$(date)] [NETWORK] ✗ CRITICAL: Network still down after healing attempts" >> "$LOG"
    generate_recommendation "CRITICAL" "false" "100" "$actions_taken"
fi

echo "[$(date)] [NETWORK] Smart healing finished" >> "$LOG"
