#!/usr/bin/env python3
"""
Self-Healing Webhook Receiver
Receives alerts from Alertmanager and triggers appropriate Self-Healing scripts
"""

try:
    from fastapi import FastAPI, Request, HTTPException  # type: ignore
    from fastapi.responses import JSONResponse  # type: ignore
except ImportError as e:
    raise ImportError(
        "Missing required dependency 'fastapi'. Install it with:\n"
        "    pip install fastapi uvicorn\n"
        "or add 'fastapi' and 'uvicorn' to your project's requirements.\n"
        "Original error: " + str(e)
    ) from e

import logging
import subprocess
import json
from datetime import datetime
from typing import Dict, List
from pathlib import Path

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/opt/self-heal/logs/webhook.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

app = FastAPI(title="Self-Healing Webhook Receiver")

# Paths
LOG_DIR = Path("/opt/self-heal/logs")
PENDING_FILE = LOG_DIR / "pending_actions.json"

# Mapping من alert action لـ script path
SCRIPT_MAPPING = {
    "handle_high_cpu": "/opt/self-heal/scripts/handle_high_cpu.sh",
    "handle_high_memory": "/opt/self-heal/scripts/handle_high_memory.sh",
    "handle_disk_alert": "/opt/self-heal/scripts/handle_disk_alert.sh",
    "handle_network_issue": "/opt/self-heal/scripts/handle_network_issue.sh",
    "restart_service": "/opt/self-heal/scripts/restart_service.sh docker:myapp",
    "monitor": None  # للتنبيهات التحذيرية فقط (بدون action)
}


def create_pending_alert(alert_info: Dict, action: str) -> None:
    """
    Create pending alert for interactive handling
    Supports: CPU, Memory, Disk, Network
    """
    try:
        # Determine resource type
        resource_type = action.replace("handle_", "").replace("_alert", "").replace("high_", "").upper()
        
        # Try to get value from alert first, otherwise calculate it
        current_value = alert_info.get("current_value", None)
        threshold = "N/A"
        
        if not current_value:
            # Fallback: Calculate current value
            if "cpu" in action.lower():
                # Get CPU usage
                top_output = subprocess.run(["top", "-bn1"], capture_output=True, text=True, timeout=5).stdout
                cpu_line = [l for l in top_output.split('\n') if 'Cpu(s)' in l or '%Cpu' in l]
                if cpu_line:
                    idle = float([p for p in cpu_line[0].split(',') if 'id' in p][0].split()[0])
                    current_value = f"{round(100 - idle, 1)}%"
                else:
                    current_value = "N/A"
                threshold = "80%"
                
            elif "memory" in action.lower():
                # Get Memory usage
                mem_output = subprocess.run(["free"], capture_output=True, text=True, timeout=5).stdout
                mem_line = mem_output.split('\n')[1].split()
                mem_total = int(mem_line[1])
                mem_available = int(mem_line[6])
                current_value = f"{round((1 - mem_available / mem_total) * 100, 1)}%"
                threshold = "85%"
                
            elif "disk" in action.lower():
                # Get Disk usage
                disk_result = subprocess.run(["df", "/", "--output=pcent"], capture_output=True, text=True, timeout=5)
                current_value = disk_result.stdout.strip().split('\n')[1].strip()
                threshold = "85%"
                
            elif "network" in action.lower():
                current_value = "High errors detected"
                threshold = "10 errors/sec"
        else:
            # Set thresholds based on resource type
            if "CPU" in resource_type:
                threshold = "80%"
            elif "MEMORY" in resource_type:
                threshold = "85%"
            elif "DISK" in resource_type:
                threshold = "85%"
            elif "NETWORK" in resource_type:
                threshold = "10 errors/sec"
        
        pending_alert = {
            "timestamp": datetime.now().isoformat(),
            "alert_type": resource_type,
            "severity": alert_info.get("severity", "CRITICAL"),
            "current_usage": current_value,
            "threshold": threshold,
            "alert_name": alert_info.get("alertname", "Unknown"),
            "instance": alert_info.get("instance", "Unknown"),
            "description": alert_info.get("description", ""),
            "action": action,
            "timeout_seconds": 300  # 5 minutes
        }
        
        PENDING_FILE.write_text(json.dumps(pending_alert, indent=2))
        logger.info(f"Created pending alert for interactive handling: {resource_type} - {current_value}")
        
    except Exception as e:
        logger.error(f"Error creating pending alert: {e}")


def run_healing_script(script_path: str, alert_info: Dict) -> Dict:
    """
    تشغيل سكريبت الـ Self-Healing
    """
    try:
        logger.info(f"Executing healing script: {script_path}")
        logger.info(f"Alert info: {alert_info}")
        
        # تشغيل السكريبت
        result = subprocess.run(
            ["bash", script_path],
            capture_output=True,
            text=True,
            timeout=300  # 5 minutes timeout
        )
        
        if result.returncode == 0:
            logger.info(f"Script executed successfully: {script_path}")
            return {
                "status": "success",
                "script": script_path,
                "stdout": result.stdout,
                "stderr": result.stderr
            }
        else:
            logger.error(f"Script failed: {script_path}, Return code: {result.returncode}")
            logger.error(f"STDERR: {result.stderr}")
            return {
                "status": "failed",
                "script": script_path,
                "return_code": result.returncode,
                "stdout": result.stdout,
                "stderr": result.stderr
            }
            
    except subprocess.TimeoutExpired:
        logger.error(f"Script timeout: {script_path}")
        return {
            "status": "timeout",
            "script": script_path,
            "error": "Script execution exceeded 5 minutes"
        }
    except Exception as e:
        logger.error(f"Error executing script {script_path}: {str(e)}")
        return {
            "status": "error",
            "script": script_path,
            "error": str(e)
        }


@app.get("/")
async def root():
    """Health check endpoint"""
    return {
        "service": "Self-Healing Webhook Receiver",
        "status": "running",
        "timestamp": datetime.now().isoformat()
    }


@app.get("/health")
async def health():
    """Health check for monitoring"""
    return {"status": "healthy"}


@app.get("/recommendations")
async def get_recommendations():
    """
    Get recent recommendations from the JSON file
    """
    try:
        import os
        rec_file = "/opt/self-heal/logs/recommendations.json"
        
        if not os.path.exists(rec_file):
            return {"recommendations": [], "count": 0}
        
        with open(rec_file, 'r') as f:
            content = f.read().strip()
            if not content or content == "[":
                return {"recommendations": [], "count": 0}
            
            # Fix incomplete JSON array
            if not content.endswith("]"):
                content += "\n]"
            
            recommendations = json.loads(content)
            
        return {
            "recommendations": recommendations[-10:],  # Last 10
            "count": len(recommendations),
            "timestamp": datetime.now().isoformat()
        }
    except Exception as e:
        logger.error(f"Error reading recommendations: {str(e)}")
        return {"recommendations": [], "count": 0, "error": str(e)}


@app.post("/approve-action")
async def approve_action(request: Request):
    """
    Approve and execute a recommended action
    Payload: {"action": "upgrade_instance", "resource": "CPU", "details": {...}}
    """
    try:
        payload = await request.json()
        action = payload.get("action")
        resource = payload.get("resource")
        
        logger.info(f"Action approval requested: {action} for {resource}")
        
        # Validate action
        valid_actions = [
            "upgrade_instance",
            "add_swap",
            "expand_disk",
            "restart_service",
            "optimize_app"
        ]
        
        if action not in valid_actions:
            raise HTTPException(status_code=400, detail=f"Invalid action: {action}")
        
        # Log the approval
        approval_log = {
            "timestamp": datetime.now().isoformat(),
            "action": action,
            "resource": resource,
            "status": "approved",
            "details": payload.get("details", {})
        }
        
        with open("/opt/self-heal/logs/approvals.log", "a") as f:
            f.write(json.dumps(approval_log) + "\n")
        
        # For now, just log. In production, this would trigger Terraform/automation
        logger.info(f"Action approved: {action} for {resource}")
        
        return {
            "status": "approved",
            "action": action,
            "resource": resource,
            "message": f"Action '{action}' has been logged and will be executed",
            "timestamp": datetime.now().isoformat()
        }
        
    except Exception as e:
        logger.error(f"Error approving action: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/dismiss-recommendation")
async def dismiss_recommendation(request: Request):
    """
    Dismiss a recommendation without taking action
    Payload: {"recommendation_id": "...", "reason": "..."}
    """
    try:
        payload = await request.json()
        rec_id = payload.get("recommendation_id")
        reason = payload.get("reason", "No reason provided")
        
        dismissal_log = {
            "timestamp": datetime.now().isoformat(),
            "recommendation_id": rec_id,
            "reason": reason,
            "status": "dismissed"
        }
        
        with open("/opt/self-heal/logs/dismissals.log", "a") as f:
            f.write(json.dumps(dismissal_log) + "\n")
        
        logger.info(f"Recommendation dismissed: {rec_id} - Reason: {reason}")
        
        return {
            "status": "dismissed",
            "recommendation_id": rec_id,
            "timestamp": datetime.now().isoformat()
        }
        
    except Exception as e:
        logger.error(f"Error dismissing recommendation: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/webhook")
async def receive_alert(request: Request):
    """
    Receive alerts from Alertmanager
    """
    try:
        # قراءة البيانات
        payload = await request.json()
        logger.info(f"Received alert webhook: {json.dumps(payload, indent=2)}")
        
        # معالجة كل alert
        results = []
        alerts = payload.get("alerts", [])
        
        for alert in alerts:
            alert_name = alert.get("labels", {}).get("alertname", "Unknown")
            action = alert.get("labels", {}).get("action", "monitor")
            severity = alert.get("labels", {}).get("severity", "unknown")
            status = alert.get("status", "firing")
            instance = alert.get("labels", {}).get("instance", "unknown")
            
            logger.info(f"Processing alert: {alert_name} (severity: {severity}, status: {status}, action: {action})")
            
            # إذا كان Alert resolved، نسجله فقط
            if status == "resolved":
                logger.info(f"Alert resolved: {alert_name} on {instance}")
                results.append({
                    "alert": alert_name,
                    "action": "logged",
                    "status": "resolved"
                })
                continue
            
            # إذا كان warning ومش محتاج action، نسجله فقط
            if severity == "warning" and action == "monitor":
                logger.warning(f"Warning alert (monitoring only): {alert_name} on {instance}")
                results.append({
                    "alert": alert_name,
                    "action": "monitor",
                    "status": "logged"
                })
                continue
            
            # تنفيذ الـ action المناسب
            script_path = SCRIPT_MAPPING.get(action)
            
            if script_path:
                alert_info = {
                    "alertname": alert_name,
                    "severity": severity,
                    "instance": instance,
                    "description": alert.get("annotations", {}).get("description", "")
                }
                
                # CRITICAL alerts → Always go to Dashboard for user choice
                if severity == "critical":
                    # Add alert value if available
                    alert_value = alert.get("annotations", {}).get("value", None)
                    if alert_value:
                        alert_info["current_value"] = alert_value
                    
                    create_pending_alert(alert_info, action)
                    logger.info(f"CRITICAL alert created - awaiting user choice on dashboard: {alert_name}")
                    results.append({
                        "alert": alert_name,
                        "action": "pending_user_choice",
                        "status": "waiting",
                        "message": "Check dashboard at http://<server-ip>:5001"
                    })
                else:
                    # WARNING alerts → Auto execution
                    result = run_healing_script(script_path, alert_info)
                    result["alert"] = alert_name
                    result["action"] = action
                    results.append(result)
            else:
                logger.warning(f"No script mapping found for action: {action}")
                results.append({
                    "alert": alert_name,
                    "action": action,
                    "status": "no_script_found"
                })
        
        return JSONResponse(
            status_code=200,
            content={
                "status": "processed",
                "alerts_count": len(alerts),
                "results": results,
                "timestamp": datetime.now().isoformat()
            }
        )
        
    except json.JSONDecodeError:
        logger.error("Invalid JSON payload received")
        raise HTTPException(status_code=400, detail="Invalid JSON")
    except Exception as e:
        logger.error(f"Error processing webhook: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    import uvicorn  # type: ignore
    
    logger.info("Starting Self-Healing Webhook Receiver on port 5000")
    uvicorn.run(
        app,
        host="0.0.0.0",
        port=5000,
        log_level="info"
    )
