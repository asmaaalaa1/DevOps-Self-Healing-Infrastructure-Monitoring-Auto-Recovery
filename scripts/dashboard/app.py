#!/usr/bin/env python3
"""
Self-Healing Web Dashboard
Professional control center for infrastructure self-healing
"""

from flask import Flask, render_template, jsonify, request
import subprocess
import json
from datetime import datetime
from pathlib import Path

app = Flask(__name__)

# Configuration
LOG_DIR = Path("/opt/self-heal/logs")
PENDING_FILE = LOG_DIR / "pending_actions.json"
HISTORY_FILE = LOG_DIR / "actions_history.json"

def ensure_dirs():
    """Ensure required directories exist"""
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    if not HISTORY_FILE.exists():
        HISTORY_FILE.write_text("[]")

def get_system_metrics():
    """Get current system resource usage"""
    try:
        # CPU Usage
        top_output = subprocess.run(
            ["top", "-bn1"],
            capture_output=True,
            text=True,
            timeout=5
        ).stdout
        
        cpu_line = [l for l in top_output.split('\n') if 'Cpu(s)' in l or '%Cpu' in l]
        if cpu_line:
            parts = cpu_line[0].split(',')
            idle = float([p for p in parts if 'id' in p][0].split()[0])
            cpu_usage = round(100 - idle, 1)
        else:
            cpu_usage = 0
        
        # Memory Usage
        mem_output = subprocess.run(
            ["free"],
            capture_output=True,
            text=True,
            timeout=5
        ).stdout
        
        mem_line = mem_output.split('\n')[1].split()
        mem_total = int(mem_line[1])
        mem_available = int(mem_line[6])
        mem_usage = round((1 - mem_available / mem_total) * 100, 1)
        
        # Disk Usage
        disk_output = subprocess.run(
            ["df", "/", "--output=pcent"],
            capture_output=True,
            text=True,
            timeout=5
        ).stdout
        
        disk_usage = int(disk_output.strip().split('\n')[1].strip('%'))
        
        return {
            "cpu": cpu_usage,
            "memory": mem_usage,
            "disk": disk_usage
        }
    
    except Exception as e:
        print(f"Error getting metrics: {e}")
        return {"cpu": 0, "memory": 0, "disk": 0}

def get_large_files():
    """Get list of largest files"""
    try:
        result = subprocess.run(
            "du -sh /home/ec2-user/* /var/log /var/cache 2>/dev/null | sort -rh | head -10",
            shell=True,
            capture_output=True,
            text=True,
            timeout=10
        )
        
        files = []
        for line in result.stdout.strip().split('\n'):
            if line:
                parts = line.split(maxsplit=1)
                if len(parts) == 2:
                    files.append({"size": parts[0], "path": parts[1]})
        
        return files
    except:
        return []

def get_top_cpu_processes():
    """Get top CPU-consuming processes for manual selection"""
    try:
        result = subprocess.run(
            ["ps", "aux", "--sort=-pcpu"],
            capture_output=True,
            text=True,
            timeout=5
        )
        
        processes = []
        lines = result.stdout.strip().split('\n')[1:]  # Skip header
        
        for line in lines[:15]:  # Top 15 processes
            parts = line.split(None, 10)
            if len(parts) >= 11:
                cpu = float(parts[2])
                if cpu > 0.1:  # Include processes using >0.1% CPU
                    processes.append({
                        "pid": parts[1],
                        "user": parts[0],
                        "cpu": f"{cpu}%",
                        "mem": f"{parts[3]}%",
                        "command": parts[10][:80],  # Show more of command
                        "action": f"kill -15 {parts[1]}"
                    })
        
        return processes
    except Exception as e:
        print(f"Error getting CPU processes: {e}")
        return []

def get_top_memory_processes():
    """Get top memory-consuming processes for manual selection"""
    try:
        result = subprocess.run(
            ["ps", "aux", "--sort=-rss"],
            capture_output=True,
            text=True,
            timeout=5
        )
        
        options = [{
            "type": "action",
            "name": "Clear System Cache (Safe)",
            "description": "Drop page cache, dentries and inodes",
            "action": "clear_cache",
            "impact": "Low risk - Frees cache memory"
        }]
        
        lines = result.stdout.strip().split('\n')[1:]  # Skip header
        
        for line in lines[:15]:  # Top 15 processes
            parts = line.split(None, 10)
            if len(parts) >= 11:
                mem = float(parts[3])
                if mem > 0.1:  # Include processes using >0.1% memory
                    options.append({
                        "type": "process",
                        "pid": parts[1],
                        "user": parts[0],
                        "cpu": f"{parts[2]}%",
                        "mem": f"{mem}%",
                        "command": parts[10][:80],  # Show more of command
                        "action": f"kill -15 {parts[1]}"
                    })
        
        return options
    except Exception as e:
        print(f"Error getting memory processes: {e}")
        return [{"type": "error", "message": f"Failed to get process list: {e}"}]

def get_large_files_detailed():
    """Get detailed list of large files for manual deletion"""
    try:
        # Find large files in common locations
        result = subprocess.run(
            "find /home/ec2-user /var/log /tmp -type f -size +10M 2>/dev/null | xargs ls -lh 2>/dev/null | awk '{print $5, $9}' | sort -rh | head -15",
            shell=True,
            capture_output=True,
            text=True,
            timeout=15
        )
        
        files = []
        for line in result.stdout.strip().split('\n'):
            if line:
                parts = line.split(None, 1)
                if len(parts) == 2:
                    files.append({
                        "size": parts[0],
                        "path": parts[1],
                        "action": f"rm {parts[1]}",
                        "safe": "log" in parts[1].lower() or "tmp" in parts[1].lower()
                    })
        
        # Add cache cleanup option
        files.insert(0, {
            "type": "action",
            "name": "Clear Package Cache",
            "size": "~100-500MB",
            "action": "clear_package_cache",
            "safe": True,
            "description": "Clean yum/dnf cache safely"
        })
        
        return files
    except:
        return []

def get_pending_alert():
    """Check if there's a pending alert"""
    if PENDING_FILE.exists():
        try:
            return json.loads(PENDING_FILE.read_text())
        except:
            return None
    return None

def get_history():
    """Get action history"""
    try:
        return json.loads(HISTORY_FILE.read_text())
    except:
        return []

def add_history(action_type, details):
    """Add entry to history"""
    history = get_history()
    history.insert(0, {
        "timestamp": datetime.now().isoformat(),
        "type": action_type,
        "details": details
    })
    # Keep last 100 entries
    history = history[:100]
    HISTORY_FILE.write_text(json.dumps(history, indent=2))

# ============================================================
# Routes
# ============================================================

@app.route('/')
def index():
    """Main dashboard page"""
    return render_template('index.html')

@app.route('/api/status')
def api_status():
    """Get current system status and pending alerts"""
    metrics = get_system_metrics()
    pending = get_pending_alert()
    files = get_large_files() if pending else []
    
    return jsonify({
        "status": metrics,
        "pending_alert": pending,
        "large_files": files,
        "timestamp": datetime.now().isoformat()
    })

@app.route('/api/history')
def api_history():
    """Get action history"""
    return jsonify({
        "history": get_history(),
        "timestamp": datetime.now().isoformat()
    })

@app.route('/api/action', methods=['POST'])
def api_action():
    """Execute chosen action"""
    data = request.json
    action = data.get('action', 'auto')
    
    # Get alert_type from pending alert or from request
    alert_type = 'unknown'
    if PENDING_FILE.exists():
        try:
            pending_data = json.loads(PENDING_FILE.read_text())
            alert_type = pending_data.get('alert_type', 'unknown').lower()
        except:
            pass
    
    # Override with request data if provided
    if 'alert_type' in data:
        alert_type = data['alert_type'].lower()
    
    result = {"status": "success", "action": action}
    
    try:
        if action == "auto":
            # Execute auto cleanup script
            script_path = f"/opt/self-heal/scripts/handle_{alert_type}_alert.sh"
            subprocess.run([script_path], timeout=60)
            result["message"] = "Auto cleanup completed successfully"
            
        elif action == "manual":
            result["message"] = "Manual mode - SSH to server and investigate"
            
        elif action == "scale":
            result["message"] = "Scaling recommended - check AWS console or Terraform"
        
        # Clear pending alert
        if PENDING_FILE.exists():
            pending_data = json.loads(PENDING_FILE.read_text())
            pending_data['user_choice'] = action
            pending_data['resolved_at'] = datetime.now().isoformat()
            # Archive it
            add_history(f"{alert_type.upper()}_RESOLVED", {
                "action": action,
                "alert": pending_data
            })
            PENDING_FILE.unlink()
        
        # Add to history
        add_history(f"{alert_type.upper()}_ACTION", result)
        
        return jsonify(result)
    
    except Exception as e:
        return jsonify({
            "status": "error",
            "message": str(e)
        }), 500

@app.route('/api/dismiss', methods=['POST'])
def api_dismiss():
    """Dismiss alert without action"""
    try:
        if PENDING_FILE.exists():
            pending_data = json.loads(PENDING_FILE.read_text())
            add_history("ALERT_DISMISSED", {"alert": pending_data})
            PENDING_FILE.unlink()
        
        return jsonify({"status": "dismissed"})
    
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/api/manual-options/<resource>', methods=['GET'])
def api_manual_options(resource):
    """Get manual remediation options based on alert type"""
    try:
        alert_type = resource.upper()
        
        if alert_type == 'CPU':
            options = get_top_cpu_processes()
            return jsonify({
                "status": "success",
                "alert_type": "CPU",
                "title": "High CPU Processes",
                "description": "Select processes to terminate (SIGTERM)",
                "options": options
            })
        
        elif alert_type == 'MEMORY':
            options = get_top_memory_processes()
            return jsonify({
                "status": "success",
                "alert_type": "MEMORY",
                "title": "Memory Management Options",
                "description": "Select action to free memory",
                "options": options
            })
        
        elif alert_type == 'DISK':
            options = get_large_files_detailed()
            return jsonify({
                "status": "success",
                "alert_type": "DISK",
                "title": "Large Files & Cleanup Options",
                "description": "Select files/actions to free disk space",
                "options": options
            })
        
        else:
            return jsonify({
                "status": "error",
                "message": f"Unknown alert type: {alert_type}"
            }), 400
    
    except Exception as e:
        return jsonify({
            "status": "error",
            "message": str(e)
        }), 500

@app.route('/api/execute-manual', methods=['POST'])
def api_execute_manual():
    """Execute manual action selected by user"""
    try:
        data = request.json
        action_type = data.get('action_type')
        target = data.get('target')
        
        result = {"status": "success"}
        
        if action_type == "kill_process":
            # Kill specific process
            subprocess.run(["kill", "-15", target], timeout=5, check=True)
            result["message"] = f"Process {target} terminated (SIGTERM)"
            
        elif action_type == "clear_cache":
            # Clear system cache
            subprocess.run(["sync"], timeout=5)
            subprocess.run(
                ["sudo", "sh", "-c", "echo 3 > /proc/sys/vm/drop_caches"],
                timeout=5,
                check=True
            )
            result["message"] = "System cache cleared successfully"
            
        elif action_type == "clear_package_cache":
            # Clear package manager cache
            subprocess.run(["sudo", "dnf", "clean", "all"], timeout=30, check=True)
            result["message"] = "Package cache cleared successfully"
            
        elif action_type == "delete_file":
            # Delete specific file
            subprocess.run(["sudo", "rm", "-f", target], timeout=10, check=True)
            result["message"] = f"File deleted: {target}"
        
        else:
            return jsonify({
                "status": "error",
                "message": f"Unknown action type: {action_type}"
            }), 400
        
        # Add to history
        add_history("MANUAL_ACTION", {
            "action_type": action_type,
            "target": target,
            "result": result["message"]
        })
        
        # Clear pending alert
        if PENDING_FILE.exists():
            PENDING_FILE.unlink()
        
        return jsonify(result)
    
    except subprocess.CalledProcessError as e:
        return jsonify({
            "status": "error",
            "message": f"Command failed: {e}"
        }), 500
    
    except Exception as e:
        return jsonify({
            "status": "error",
            "message": str(e)
        }), 500

@app.route('/api/manual-execute', methods=['POST'])
def api_manual_execute():
    """Execute manual selections from modal"""
    try:
        data = request.json
        resource = data.get('resource')  # cpu, memory, disk
        selections = data.get('selections', [])  # Array of selected items
        
        if not selections:
            return jsonify({
                "status": "error",
                "message": "No selections provided"
            }), 400
        
        results = []
        errors = []
        
        if resource == 'cpu':
            # Kill selected processes
            for pid in selections:
                try:
                    subprocess.run(["sudo", "kill", "-15", pid], timeout=5, check=True)
                    results.append(f"Killed PID {pid}")
                except Exception as e:
                    errors.append(f"Failed to kill PID {pid}: {e}")
        
        elif resource == 'memory':
            # Execute memory cleanup actions
            for item in selections:
                if item == 'cache':
                    try:
                        subprocess.run(["sync"], timeout=5)
                        subprocess.run(
                            ["sudo", "sh", "-c", "echo 3 > /proc/sys/vm/drop_caches"],
                            timeout=5,
                            check=True
                        )
                        results.append("System cache cleared")
                    except Exception as e:
                        errors.append(f"Failed to clear cache: {e}")
                else:
                    # It's a PID
                    try:
                        subprocess.run(["sudo", "kill", "-15", item], timeout=5, check=True)
                        results.append(f"Killed PID {item}")
                    except Exception as e:
                        errors.append(f"Failed to kill PID {item}: {e}")
        
        elif resource == 'disk':
            # Delete selected files or execute cleanup actions
            for item in selections:
                if item == 'clear_package_cache':
                    # Clear yum/dnf cache
                    try:
                        subprocess.run(["sudo", "yum", "clean", "all"], 
                                     timeout=30, check=True, 
                                     capture_output=True, text=True)
                        results.append("Package cache cleared")
                    except Exception as e:
                        errors.append(f"Failed to clear package cache: {e}")
                elif item.startswith('/'):
                    # It's a file path
                    try:
                        subprocess.run(["sudo", "rm", "-f", item], 
                                     timeout=10, check=True,
                                     capture_output=True, text=True)
                        results.append(f"Deleted: {item}")
                    except Exception as e:
                        errors.append(f"Failed to delete {item}: {e}")
                else:
                    errors.append(f"Unknown disk action: {item}")
        
        else:
            return jsonify({
                "status": "error",
                "message": f"Unknown resource: {resource}"
            }), 400
        
        # Add to history
        add_history(f"MANUAL_{resource.upper()}_CLEANUP", {
            "selections": selections,
            "results": results,
            "errors": errors
        })
        
        # Clear pending alert
        if PENDING_FILE.exists():
            PENDING_FILE.unlink()
        
        message = f"Completed {len(results)} actions"
        if errors:
            message += f" ({len(errors)} failed)"
        
        return jsonify({
            "status": "success" if not errors else "partial",
            "message": message,
            "results": results,
            "errors": errors
        })
    
    except Exception as e:
        return jsonify({
            "status": "error",
            "message": str(e)
        }), 500

# ============================================================
# Main
# ============================================================

if __name__ == '__main__':
    ensure_dirs()
    print("\n" + "="*60)
    print("🌐 Self-Healing Dashboard Starting...")
    print("="*60)
    print("📊 Access at: http://<server-ip>:5001")
    print("🔧 Press Ctrl+C to stop")
    print("="*60 + "\n")
    
    app.run(host='0.0.0.0', port=5001, debug=False)
