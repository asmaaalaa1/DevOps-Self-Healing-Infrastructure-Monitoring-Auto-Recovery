// Self-Healing Dashboard - Frontend Logic

let countdownInterval = null;
let currentAlertId = null;  // Track current alert to avoid resetting timer

// Update system status every 5 seconds
function updateStatus() {
    fetch('/api/status')
        .then(res => res.json())
        .then(data => {
            const status = data.status;
            
            // Update CPU
            updateMetric('cpu', status.cpu);
            
            // Update Memory
            updateMetric('memory', status.memory);
            
            // Update Disk
            updateMetric('disk', status.disk);
            
            // Update alert section
            if (data.pending_alert) {
                // Create unique ID for alert
                const alertId = `${data.pending_alert.alert_type}_${data.pending_alert.timestamp}`;
                
                // Only show alert if it's new (different from current)
                if (alertId !== currentAlertId) {
                    currentAlertId = alertId;
                    showAlert(data.pending_alert, data.large_files);
                }
                // else: alert is same, don't restart countdown
            } else {
                currentAlertId = null;
                hideAlert();
            }
            
            // Update last update time
            const now = new Date();
            document.getElementById('last-update').textContent = now.toLocaleTimeString();
        })
        .catch(err => console.error('Error fetching status:', err));
}

function updateMetric(name, value) {
    const valueEl = document.getElementById(`${name}-value`);
    const fillEl = document.getElementById(`${name}-fill`);
    const cardEl = document.getElementById(`${name}-card`);
    
    // Update value
    valueEl.textContent = `${value}%`;
    
    // Update progress bar
    fillEl.style.width = `${value}%`;
    
    // Color based on thresholds
    let color, className;
    if (value < 60) {
        color = '#10b981'; // green
        className = 'ok';
    } else if (value < 80) {
        color = '#f59e0b'; // yellow
        className = 'warning';
    } else {
        color = '#ef4444'; // red
        className = 'critical';
    }
    
    fillEl.style.background = color;
    
    // Update card class
    cardEl.className = 'status-card ' + className;
}

function showAlert(alert, files) {
    document.getElementById('alert-section').classList.remove('hidden');
    document.getElementById('no-alert').classList.add('hidden');
    
    // Determine alert type
    const alertType = (alert.alert_type || 'DISK').toLowerCase();
    
    // Set alert details
    document.getElementById('alert-title').textContent = 
        `${alert.alert_type || 'DISK'} Alert - ${alert.current_usage}`;
    
    const detailsHtml = `
        <p><strong>Severity:</strong> ${alert.severity}</p>
        <p><strong>Threshold:</strong> ${alert.threshold}</p>
        <p><strong>Current:</strong> ${alert.current_usage}</p>
    `;
    document.getElementById('alert-details').innerHTML = detailsHtml;
    
    // Show preview based on alert type
    const filesContainer = document.getElementById('alert-files');
    
    if (alertType.includes('disk')) {
        // Show large files for DISK alerts only
        if (files && files.length > 0) {
            const filesHtml = `
                <h3>� Largest Files:</h3>
                ${files.slice(0, 5).map(f => `
                    <div class="file-item">
                        <span class="file-path">${f.path}</span>
                        <span class="file-size">${f.size}</span>
                    </div>
                `).join('')}
            `;
            filesContainer.innerHTML = filesHtml;
        } else {
            filesContainer.innerHTML = '';
        }
    } else if (alertType.includes('cpu')) {
        // Show CPU info preview
        filesContainer.innerHTML = `
            <div class="alert-preview">
                <p>💻 <strong>High CPU Usage Detected</strong></p>
                <p style="color: var(--text-dim);">Click "Manual Control" to see top processes</p>
            </div>
        `;
    } else if (alertType.includes('memory')) {
        // Show Memory info preview
        filesContainer.innerHTML = `
            <div class="alert-preview">
                <p>🧠 <strong>High Memory Usage Detected</strong></p>
                <p style="color: var(--text-dim);">Click "Manual Control" to see top processes</p>
            </div>
        `;
    } else {
        filesContainer.innerHTML = '';
    }
    
    // Update button descriptions based on alert type
    updateButtonDescriptions(alertType);
    
    // Start countdown
    startCountdown(300); // 5 minutes
}

function updateButtonDescriptions(alertType) {
    const autoDesc = document.getElementById('auto-desc');
    const manualDesc = document.getElementById('manual-desc');
    const scaleDesc = document.getElementById('scale-desc');
    
    if (!autoDesc || !manualDesc || !scaleDesc) return;
    
    if (alertType.includes('cpu')) {
        autoDesc.textContent = 'Kill high CPU processes';
        manualDesc.textContent = 'Choose which processes to kill';
        scaleDesc.textContent = 'Upgrade to more CPU cores';
    } else if (alertType.includes('memory')) {
        autoDesc.textContent = 'Clear cache & kill processes';
        manualDesc.textContent = 'Choose processes or cache';
        scaleDesc.textContent = 'Upgrade to more RAM';
    } else if (alertType.includes('disk')) {
        autoDesc.textContent = 'Safe - logs, cache, docker only';
        manualDesc.textContent = 'Choose files to delete';
        scaleDesc.textContent = 'Expand disk storage';
    } else if (alertType.includes('service') || alertType.includes('down')) {
        autoDesc.textContent = 'Auto restart service';
        manualDesc.textContent = 'Check logs & restart';
        scaleDesc.textContent = 'Deploy redundant instance';
    } else {
        autoDesc.textContent = 'Automated safe cleanup';
        manualDesc.textContent = 'Choose what to fix';
        scaleDesc.textContent = 'Expand resources';
    }
}

function hideAlert() {
    document.getElementById('alert-section').classList.add('hidden');
    document.getElementById('no-alert').classList.remove('hidden');
    
    if (countdownInterval) {
        clearInterval(countdownInterval);
        countdownInterval = null;
    }
    
    currentAlertId = null;  // Reset alert ID
}

function startCountdown(seconds) {
    if (countdownInterval) {
        clearInterval(countdownInterval);
    }
    
    let remaining = seconds;
    const timerEl = document.getElementById('alert-timer');
    
    function updateTimer() {
        const mins = Math.floor(remaining / 60);
        const secs = remaining % 60;
        timerEl.textContent = `⏰ ${mins}:${secs.toString().padStart(2, '0')}`;
        
        if (remaining <= 0) {
            clearInterval(countdownInterval);
            // Auto-execute cleanup
            chooseAction('auto');
        }
        
        remaining--;
    }
    
    updateTimer();
    countdownInterval = setInterval(updateTimer, 1000);
}

function chooseAction(action) {
    if (action === 'manual') {
        // Show manual options based on alert type
        showManualOptions();
        return;
    }
    
    if (!confirm(`Execute ${action.toUpperCase()} action?`)) {
        return;
    }
    
    fetch('/api/action', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json'
        },
        body: JSON.stringify({ action: action })
    })
    .then(res => res.json())
    .then(data => {
        alert(`✅ Action executed: ${data.message}`);
        hideAlert();
        updateStatus();
        updateHistory();
    })
    .catch(err => {
        console.error('Error executing action:', err);
        alert('❌ Error executing action');
    });
}

function showManualOptions() {
    // Get current alert info
    fetch('/api/status')
        .then(res => res.json())
        .then(data => {
            if (!data.pending_alert) {
                alert('No active alert');
                return;
            }
            
            const alertType = data.pending_alert.alert_type || 'DISK';
            const resource = alertType.replace(' Usage High', '').toLowerCase();
            
            // Fetch manual options for this specific resource
            showManualOptionsModal(resource);
        })
        .catch(err => {
            console.error('Error getting alert info:', err);
            alert('❌ Error loading manual options');
        });
}

function showManualOptionsModal(resource) {
    // Create modal overlay
    const modal = document.createElement('div');
    modal.className = 'modal-overlay';
    modal.innerHTML = `
        <div class="modal-content">
            <div class="modal-header">
                <h2>🔧 Manual ${resource.toUpperCase()} Options</h2>
                <button class="modal-close" onclick="closeManualModal()">✖</button>
            </div>
            <div class="modal-body" id="manual-options-content">
                <div class="loading">⏳ Loading options...</div>
            </div>
        </div>
    `;
    modal.id = 'manual-modal';
    document.body.appendChild(modal);
    
    // Fetch options based on resource type
    fetch(`/api/manual-options/${resource}`)
        .then(res => res.json())
        .then(data => {
            const content = document.getElementById('manual-options-content');
            
            if (resource === 'cpu') {
                content.innerHTML = renderCPUOptions(data);
            } else if (resource === 'memory') {
                content.innerHTML = renderMemoryOptions(data);
            } else if (resource === 'disk') {
                content.innerHTML = renderDiskOptions(data);
            }
        })
        .catch(err => {
            console.error('Error loading manual options:', err);
            document.getElementById('manual-options-content').innerHTML = 
                '<div class="error">❌ Error loading options</div>';
        });
}

function renderCPUOptions(data) {
    const processes = data.options || [];
    
    if (processes.length === 0) {
        return '<p>No high CPU processes found</p>';
    }
    
    return `
        <h3>💻 Top CPU Processes</h3>
        <div class="options-list">
            ${processes.map((proc, idx) => `
                <div class="option-item">
                    <input type="checkbox" id="cpu-proc-${idx}" value="${proc.pid}">
                    <label for="cpu-proc-${idx}">
                        <strong>PID ${proc.pid}</strong> (${proc.user})<br>
                        ${proc.command}
                        <span class="badge">${proc.cpu} CPU</span>
                        <span class="badge">${proc.mem} MEM</span>
                    </label>
                </div>
            `).join('')}
        </div>
        <button class="action-btn auto" onclick="executeManualSelection('cpu')">
            ✅ Kill Selected Processes
        </button>
        <button class="action-btn" onclick="closeManualModal()">Cancel</button>
    `;
}

function renderMemoryOptions(data) {
    let html = '<h3>🧠 Memory Cleanup Options</h3><div class="options-list">';
    
    // Separate processes and actions from options
    const processes = data.options ? data.options.filter(opt => opt.type === 'process') : [];
    const cacheAction = data.options ? data.options.find(opt => opt.type === 'action') : null;
    
    // Memory processes
    if (processes && processes.length > 0) {
        html += '<h4>Top Memory Processes:</h4>';
        processes.forEach((proc, idx) => {
            html += `
                <div class="option-item">
                    <input type="checkbox" id="mem-proc-${idx}" value="${proc.pid}">
                    <label for="mem-proc-${idx}">
                        <strong>PID ${proc.pid}:</strong> ${proc.command} 
                        <span class="badge">${proc.mem} MEM</span>
                        <span class="badge">${proc.cpu} CPU</span>
                    </label>
                </div>
            `;
        });
    }
    
    // Cache cleanup option
    if (cacheAction) {
        html += `
            <h4>Cache Cleanup:</h4>
            <div class="option-item">
                <input type="checkbox" id="clear-cache" value="cache">
                <label for="clear-cache">
                    <strong>${cacheAction.name}</strong>
                    <span class="badge">Safe</span>
                </label>
            </div>
        `;
    }
    
    html += `
        </div>
        <button class="action-btn auto" onclick="executeManualSelection('memory')">
            ✅ Execute Selected Actions
        </button>
        <button class="action-btn" onclick="closeManualModal()">Cancel</button>
    `;
    
    return html;
}

function renderDiskOptions(data) {
    // Separate files and actions from options
    const files = data.options ? data.options.filter(opt => opt.path) : [];
    const actions = data.options ? data.options.filter(opt => opt.type === 'action') : [];
    
    if (files.length === 0 && actions.length === 0) {
        return '<p>No large files found</p>';
    }
    
    let html = '<h3>💾 Large Files & Cleanup</h3><div class="options-list">';
    
    // Add cache cleanup actions first
    if (actions.length > 0) {
        html += '<h4>Safe Cleanup Actions:</h4>';
        actions.forEach((action, idx) => {
            html += `
                <div class="option-item">
                    <input type="checkbox" id="disk-action-${idx}" value="${action.action}">
                    <label for="disk-action-${idx}">
                        <strong>${action.name}</strong> - ${action.size}
                        <span class="badge">Safe</span>
                    </label>
                </div>
            `;
        });
    }
    
    // Add files
    if (files.length > 0) {
        html += '<h4>Large Files:</h4>';
        html += '<p class="info">⚠️ Select files to delete (use caution!)</p>';
        files.forEach((file, idx) => {
            const safeLabel = file.safe ? '<span class="badge">Safe</span>' : '<span class="badge" style="background:#ef4444">Caution</span>';
            html += `
                <div class="option-item">
                    <input type="checkbox" id="disk-file-${idx}" value="${file.path}">
                    <label for="disk-file-${idx}">
                        <strong>${file.size}</strong> - ${file.path}
                        ${safeLabel}
                    </label>
                </div>
            `;
        });
    }
    
    html += `
        </div>
        <button class="action-btn auto" onclick="executeManualSelection('disk')">
            🗑️ Delete Selected Items
        </button>
        <button class="action-btn" onclick="closeManualModal()">Cancel</button>
    `;
    
    return html;
}

function executeManualSelection(resource) {
    const checkboxes = document.querySelectorAll('.option-item input[type="checkbox"]:checked');
    const selected = Array.from(checkboxes).map(cb => cb.value);
    
    if (selected.length === 0) {
        alert('Please select at least one option');
        return;
    }
    
    if (!confirm(`Execute manual ${resource} cleanup on ${selected.length} item(s)?`)) {
        return;
    }
    
    fetch('/api/manual-execute', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json'
        },
        body: JSON.stringify({ 
            resource: resource,
            selections: selected 
        })
    })
    .then(res => res.json())
    .then(data => {
        alert(`✅ ${data.message}`);
        closeManualModal();
        hideAlert();
        updateStatus();
        updateHistory();
    })
    .catch(err => {
        console.error('Error executing manual action:', err);
        alert('❌ Error executing action');
    });
}

function closeManualModal() {
    const modal = document.getElementById('manual-modal');
    if (modal) {
        modal.remove();
    }
}

function dismissAlert() {
    if (!confirm('Dismiss this alert without taking action?')) {
        return;
    }
    
    fetch('/api/dismiss', {
        method: 'POST'
    })
    .then(res => res.json())
    .then(data => {
        alert('Alert dismissed');
        hideAlert();
        updateStatus();
        updateHistory();
    })
    .catch(err => {
        console.error('Error dismissing alert:', err);
    });
}

function updateHistory() {
    fetch('/api/history')
        .then(res => res.json())
        .then(data => {
            const historyList = document.getElementById('history-list');
            
            if (!data.history || data.history.length === 0) {
                historyList.innerHTML = '<div class="loading">No actions yet</div>';
                return;
            }
            
            const historyHtml = data.history.slice(0, 10).map(item => {
                const time = new Date(item.timestamp).toLocaleString();
                const type = item.type.toLowerCase();
                const icon = getActionIcon(type);
                const className = getActionClass(type);
                
                return `
                    <div class="history-item ${className}">
                        <span class="history-icon">${icon}</span>
                        <div class="history-content">
                            <strong>${item.type}</strong>
                            <div class="history-time">${time}</div>
                        </div>
                    </div>
                `;
            }).join('');
            
            historyList.innerHTML = historyHtml;
        })
        .catch(err => console.error('Error fetching history:', err));
}

function getActionIcon(type) {
    if (type.includes('cpu')) return '💻';
    if (type.includes('memory')) return '🧠';
    if (type.includes('disk')) return '💾';
    if (type.includes('dismiss')) return '✖️';
    return '✅';
}

function getActionClass(type) {
    if (type.includes('dismiss')) return 'warning';
    if (type.includes('error')) return 'error';
    return '';
}

// Initialize
document.addEventListener('DOMContentLoaded', () => {
    updateStatus();
    updateHistory();
    
    // Update every 5 seconds
    setInterval(updateStatus, 5000);
    
    // Update history every 30 seconds
    setInterval(updateHistory, 30000);
});
