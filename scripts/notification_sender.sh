#!/bin/bash
# ============================================================
# Notification Sender - Send recommendations to Slack/Email
# ============================================================

# Configuration (set via environment or defaults)
SLACK_WEBHOOK_URL="${SLACK_WEBHOOK_URL:-}"
EMAIL_RECIPIENT="${EMAIL_RECIPIENT:-abdelatym00@gmail.com}"
AWS_SNS_TOPIC="${AWS_SNS_TOPIC:-}"

# Script arguments
RESOURCE="$1"      # CPU, MEMORY, DISK, NETWORK
SEVERITY="$2"      # WARNING, CRITICAL
VALUE="$3"         # Current value

# Resolve paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$BASE_DIR/logs"
LOG="$LOG_DIR/notifications.log"

mkdir -p "$LOG_DIR"

# ============================================================
# Slack Notification
# ============================================================

send_slack_notification() {
    if [ -z "$SLACK_WEBHOOK_URL" ]; then
        echo "[$(date)] [NOTIF] Slack webhook not configured, skipping..." >> "$LOG"
        return
    fi
    
    local color="#FFA500"  # Orange for WARNING
    if [ "$SEVERITY" == "CRITICAL" ]; then
        color="#FF0000"  # Red for CRITICAL
    fi
    
    local emoji="⚠️"
    if [ "$SEVERITY" == "CRITICAL" ]; then
        emoji="🚨"
    fi
    
    local message=$(cat <<EOF
{
  "attachments": [
    {
      "color": "$color",
      "title": "$emoji $SEVERITY: High $RESOURCE Usage",
      "text": "*Resource:* $RESOURCE\n*Current Value:* $VALUE\n*Severity:* $SEVERITY\n*Time:* $(date '+%Y-%m-%d %H:%M:%S')",
      "fields": [
        {
          "title": "Actions Taken",
          "value": "• Self-healing script executed\n• Check logs for details\n• Recommendations generated",
          "short": false
        },
        {
          "title": "Next Steps",
          "value": "• Review recommendations in Grafana dashboard\n• Consider scaling resources\n• Monitor for recurring issues",
          "short": false
        }
      ],
      "footer": "Self-Healing System",
      "footer_icon": "https://platform.slack-edge.com/img/default_application_icon.png",
      "ts": $(date +%s)
    }
  ]
}
EOF
)
    
    if curl -X POST -H 'Content-type: application/json' --data "$message" "$SLACK_WEBHOOK_URL" 2>/dev/null; then
        echo "[$(date)] [NOTIF] ✓ Slack notification sent for $RESOURCE" >> "$LOG"
    else
        echo "[$(date)] [NOTIF] ✗ Failed to send Slack notification" >> "$LOG"
    fi
}

# ============================================================
# Email Notification (AWS SES)
# ============================================================

send_email_notification() {
    if [ -z "$EMAIL_RECIPIENT" ]; then
        echo "[$(date)] [NOTIF] Email recipient not configured, skipping..." >> "$LOG"
        return
    fi
    
    if ! command -v aws &> /dev/null; then
        echo "[$(date)] [NOTIF] AWS CLI not installed, skipping email..." >> "$LOG"
        return
    fi
    
    local subject="[$SEVERITY] High $RESOURCE Usage Alert"
    local body="Self-Healing Alert\n\nResource: $RESOURCE\nCurrent Value: $VALUE\nSeverity: $SEVERITY\nTime: $(date)\n\nSelf-healing actions have been executed. Please check the Grafana dashboard for detailed recommendations."
    
    aws ses send-email \
        --from "alerts@example.com" \
        --to "$EMAIL_RECIPIENT" \
        --subject "$subject" \
        --text "$body" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo "[$(date)] [NOTIF] ✓ Email sent to $EMAIL_RECIPIENT" >> "$LOG"
    else
        echo "[$(date)] [NOTIF] ✗ Failed to send email" >> "$LOG"
    fi
}

# ============================================================
# SMS Notification (AWS SNS)
# ============================================================

send_sms_notification() {
    if [ -z "$AWS_SNS_TOPIC" ]; then
        echo "[$(date)] [NOTIF] SNS topic not configured, skipping..." >> "$LOG"
        return
    fi
    
    if ! command -v aws &> /dev/null; then
        echo "[$(date)] [NOTIF] AWS CLI not installed, skipping SMS..." >> "$LOG"
        return
    fi
    
    local message="[$SEVERITY] High $RESOURCE usage ($VALUE) detected. Self-healing executed. Check dashboard."
    
    aws sns publish \
        --topic-arn "$AWS_SNS_TOPIC" \
        --message "$message" \
        --subject "Self-Healing Alert: $RESOURCE" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo "[$(date)] [NOTIF] ✓ SMS notification sent" >> "$LOG"
    else
        echo "[$(date)] [NOTIF] ✗ Failed to send SMS" >> "$LOG"
    fi
}

# ============================================================
# Main Execution
# ============================================================

echo "[$(date)] [NOTIF] Sending notifications for $RESOURCE alert (Severity: $SEVERITY)" >> "$LOG"

# Send to all configured channels in parallel
send_slack_notification &
send_email_notification &
send_sms_notification &

# Wait for all to complete
wait

echo "[$(date)] [NOTIF] Notification process completed" >> "$LOG"
