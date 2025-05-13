const socket = io();
let messageChart;
let network;
let nodes;
let edges;
let topicFilter = 'all';

function initChart() {
    const ctx = document.getElementById('messageChart').getContext('2d');
    messageChart = new Chart(ctx, {
        type: 'line',
        data: {
            labels: [],
            datasets: [{
                label: 'Messages per second',
                data: [],
                borderColor: 'rgb(59, 130, 246)',
                tension: 0.1
            }]
        },
        options: {
            responsive: true,
            scales: {
                y: {
                    beginAtZero: true,
                    ticks: {
                        color: 'rgb(209, 213, 219)'
                    }
                },
                x: {
                    ticks: {
                        color: 'rgb(209, 213, 219)'
                    }
                }
            },
            plugins: {
                legend: {
                    labels: {
                        color: 'rgb(209, 213, 219)'
                    }
                }
            }
        }
    });
}

function updateMessageList(message) {
    if (topicFilter === 'all' || message.topic === topicFilter) {
        const messageList = document.getElementById('message-list');
        const messageElement = document.createElement('div');
        messageElement.className = 'mb-2 p-2 bg-gray-700 rounded';
        messageElement.innerHTML = `<strong class="text-blue-400">${message.topic}:</strong> ${message.payload}`;
        messageList.insertBefore(messageElement, messageList.firstChild);

        if (messageList.childElementCount > 100) {
            messageList.removeChild(messageList.lastChild);
        }
    }
}

function updateChart() {
    const now = new Date();
    messageChart.data.labels.push(now.toLocaleTimeString());
    messageChart.data.datasets[0].data.push(messageCount);

    if (messageChart.data.labels.length > 10) {
        messageChart.data.labels.shift();
        messageChart.data.datasets[0].data.shift();
    }

    messageChart.update();
    messageCount = 0;
}

let messageCount = 0;

function initNetwork() {
    nodes = new vis.DataSet([
        { id: 'broker', label: 'MQTT Broker', shape: 'hexagon', color: '#FFA500', size: 30 }
    ]);
    edges = new vis.DataSet();

    const container = document.getElementById('network-visualization');
    const data = { nodes, edges };
    const options = {
        physics: {
            stabilization: false,
            barnesHut: {
                gravitationalConstant: -2000,
                springLength: 150,
                springConstant: 0.04,
            }
        },
        nodes: {
            font: {
                color: '#FFFFFF'
            }
        },
        edges: {
            width: 2,
            color: { inherit: 'from' },
            smooth: {
                type: 'continuous'
            },
            arrows: {
                to: { enabled: true, scaleFactor: 0.5 }
            }
        }
    };

    network = new vis.Network(container, data, options);
}

function updateNetwork(message) {
    if (!nodes || !edges || !network) {
        console.error('Network not initialized');
        return;
    }

    const topicParts = message.topic.split('/');
    let parentId = 'broker';

    topicParts.forEach((part, index) => {
        const nodeId = topicParts.slice(0, index + 1).join('/');
        if (!nodes.get(nodeId)) {
            nodes.add({
                id: nodeId,
                label: part,
                color: getRandomColor(),
                shape: 'dot',
                size: 20 - index * 2
            });
        }
        if (parentId !== nodeId) {
            const edgeId = `${parentId}-${nodeId}`;
            if (!edges.get(edgeId)) {
                edges.add({ id: edgeId, from: parentId, to: nodeId });
            }
        }
        parentId = nodeId;
    });

    // Animate message flow
    const edgeIds = edges.getIds();
    edgeIds.forEach(edgeId => {
        edges.update({ id: edgeId, color: { color: '#00ff00' }, width: 4 });
        setTimeout(() => {
            edges.update({ id: edgeId, color: { inherit: 'from' }, width: 2 });
        }, 1000);
    });

    // Update the size of the final topic node to indicate message received
    const finalNodeId = topicParts.join('/');
    const finalNode = nodes.get(finalNodeId);
    nodes.update({ id: finalNodeId, size: finalNode.size + 5 });
    setTimeout(() => {
        nodes.update({ id: finalNodeId, size: finalNode.size });
    }, 1000);
}

socket.on('mqtt_message', function (data) {
    updateMessageList(data);
    messageCount++;
    updateNetwork(data);
    updateTopicFilter(data.topic);

    // Update system info if this is a system stats message
    if (data.topic.includes('devices/') && data.payload) {
        try {
            const payload = JSON.parse(data.payload);
            let deviceId = null;

            // Extract device ID from topic or payload
            if (data.topic.startsWith('devices/')) {
                const parts = data.topic.split('/');
                if (parts.length >= 2) {
                    deviceId = parts[1];
                }
            }
            if (!deviceId && payload.device_id) {
                deviceId = payload.device_id;
            }

            // Check if this is a combined data message
            if (payload.modules) {
                // Update CPU info if available
                if (payload.modules.cpu) {
                    updateCpuInfo(payload.modules.cpu, deviceId);
                }

                // Update GPU info if available
                if (payload.modules.gpu) {
                    updateGpuInfo(payload.modules.gpu, deviceId);
                }
            }
            // Check if this is a module-specific message
            else if (payload.module) {
                if (payload.module === 'cpu') {
                    updateCpuInfo(payload, deviceId);
                } else if (payload.module === 'gpu') {
                    updateGpuInfo(payload, deviceId);
                }
            }
        } catch (e) {
            console.error('Error parsing message payload:', e);
        }
    }
});

function getRandomColor() {
    const letters = '0123456789ABCDEF';
    let color = '#';
    for (let i = 0; i < 6; i++) {
        color += letters[Math.floor(Math.random() * 16)];
    }
    return color;
}

document.getElementById('publish-form').addEventListener('submit', function (e) {
    e.preventDefault();
    const topic = document.getElementById('topic').value;
    const message = document.getElementById('message').value;

    fetch('/publish', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: `topic=${encodeURIComponent(topic)}&message=${encodeURIComponent(message)}`
    });

    document.getElementById('topic').value = '';
    document.getElementById('message').value = '';
});

function updateStats() {
    fetch('/stats')
        .then(response => response.json())
        .then(data => {
            document.getElementById('connection-count').textContent = data.connection_count;
            document.getElementById('topic-count').textContent = data.topic_count;
            document.getElementById('message-count').textContent = data.message_count;
        });
}

function updateTopicFilter(newTopic) {
    const topicFilter = document.getElementById('topic-filter');
    if (!Array.from(topicFilter.options).some(option => option.value === newTopic)) {
        const option = document.createElement('option');
        option.value = newTopic;
        option.textContent = newTopic;
        topicFilter.appendChild(option);
    }
}

document.getElementById('topic-filter').addEventListener('change', function (e) {
    topicFilter = e.target.value;
    document.getElementById('message-list').innerHTML = '';
});

// Debug bar functionality
let debugBar;
let debugBarToggle;

function initDebugBar() {
    debugBar = document.createElement('div');
    debugBar.id = 'debug-bar';
    debugBar.style.display = 'none';
    document.body.appendChild(debugBar);

    debugBarToggle = document.createElement('button');
    debugBarToggle.id = 'debug-bar-toggle';
    debugBarToggle.innerHTML = '🐞 Debug';
    debugBarToggle.onclick = toggleDebugBar;
    document.body.appendChild(debugBarToggle);

    const closeButton = document.createElement('button');
    closeButton.id = 'debug-bar-close';
    closeButton.innerHTML = '&times;';
    closeButton.onclick = closeDebugBar;
    debugBar.appendChild(closeButton);

    updateDebugBar();
    setInterval(updateDebugBar, 1000);  // Update every second
}

function toggleDebugBar() {
    fetch('/toggle-debug-bar', { method: 'POST' })
        .then(response => response.json())
        .then(data => {
            debugBar.style.display = data.enabled ? 'block' : 'none';
            debugBarToggle.classList.toggle('active', data.enabled);
        });
}

function closeDebugBar() {
    debugBar.style.display = 'none';
    fetch('/toggle-debug-bar', { method: 'POST' });
    debugBarToggle.classList.remove('active');
}

function trackClientPerformance() {
    const perfData = window.performance.timing;
    const pageLoadTime = perfData.loadEventEnd - perfData.navigationStart;
    const domReadyTime = perfData.domContentLoadedEventEnd - perfData.navigationStart;

    fetch('/record-client-performance', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
        },
        body: JSON.stringify({
            pageLoadTime,
            domReadyTime,
        }),
    });
}

function updateDebugBar() {
    fetch('/debug-bar')
        .then(response => response.json())
        .then(data => {
            let content = '<div class="debug-content">';
            for (const [panelName, panelData] of Object.entries(data)) {
                content += `<div class="debug-panel"><h3>${panelName}</h3><ul>`;
                for (const [key, value] of Object.entries(panelData)) {
                    let displayValue = value;
                    if (typeof value === 'object' && value !== null) {
                        displayValue = '<pre>' + JSON.stringify(value, null, 2) + '</pre>';
                    }
                    content += `<li><strong>${key}:</strong> ${displayValue}</li>`;
                }
                content += '</ul></div>';
            }
            content += '</div>';
            debugBar.innerHTML = content;

            // Create and append the close button again since we just overwrote the innerHTML
            const closeButton = document.createElement('button');
            closeButton.id = 'debug-bar-close';
            closeButton.innerHTML = '&times;';
            closeButton.onclick = closeDebugBar;
            debugBar.appendChild(closeButton);
        })
        .catch(error => {
            console.error('Error fetching debug bar data:', error);
        });
}

// Store the current device ID
let currentDeviceId = null;

// Function to get the current device ID from the server
function getCurrentDeviceId() {
    fetch('/device-info')
        .then(response => response.json())
        .then(data => {
            currentDeviceId = data.device_id;
            console.log(`Current device ID: ${currentDeviceId}`);
        })
        .catch(error => {
            console.error('Error fetching device ID:', error);
        });
}

// Function to update CPU information in the UI
function updateCpuInfo(cpuData, deviceId) {
    if (!cpuData) return;

    // Only update the UI if this is the current device or no device ID is specified
    if (deviceId && currentDeviceId && deviceId !== currentDeviceId) {
        return;
    }

    // Update CPU model if available
    if (cpuData.model) {
        document.getElementById('cpu-model').textContent = cpuData.model;
    }

    // Update CPU cores if available
    if (cpuData.physical_cores && cpuData.logical_cores) {
        document.getElementById('cpu-cores').textContent =
            `${cpuData.physical_cores} physical / ${cpuData.logical_cores} logical`;
    }

    // Update CPU utilization
    if (cpuData.cpu_util !== undefined) {
        const utilValue = typeof cpuData.cpu_util === 'number' ? cpuData.cpu_util : 0;
        document.getElementById('cpu-util').textContent = `${utilValue.toFixed(1)}%`;
        document.getElementById('cpu-util-bar').style.width = `${utilValue}%`;
    }

    // Update CPU temperature
    if (cpuData.temp !== undefined) {
        document.getElementById('cpu-temp').textContent = `${cpuData.temp.toFixed(1)}°C`;
    }
}

// Function to update GPU information in the UI
function updateGpuInfo(gpuData, deviceId) {
    if (!gpuData) return;

    // Only update the UI if this is the current device or no device ID is specified
    if (deviceId && currentDeviceId && deviceId !== currentDeviceId) {
        return;
    }

    // Update GPU model if available
    if (gpuData.model) {
        let modelText = gpuData.model;
        if (gpuData.vendor && !modelText.includes(gpuData.vendor)) {
            modelText = `${gpuData.vendor} ${modelText}`;
        }
        document.getElementById('gpu-model').textContent = modelText;
    }

    // Update GPU utilization
    if (gpuData.gpu_util !== undefined) {
        const utilValue = typeof gpuData.gpu_util === 'number' ? gpuData.gpu_util : 0;
        document.getElementById('gpu-util').textContent = `${utilValue.toFixed(1)}%`;
        document.getElementById('gpu-util-bar').style.width = `${utilValue}%`;
    }

    // Update GPU memory
    if (gpuData.mem_used !== undefined && gpuData.mem_total !== undefined) {
        const usedMB = Math.round(gpuData.mem_used);
        const totalMB = Math.round(gpuData.mem_total);
        const usedGB = (usedMB / 1024).toFixed(1);
        const totalGB = (totalMB / 1024).toFixed(1);

        if (totalMB >= 1024) {
            // Show in GB if total memory is >= 1GB
            document.getElementById('gpu-mem').textContent = `${usedGB} GB / ${totalGB} GB`;
        } else {
            // Show in MB otherwise
            document.getElementById('gpu-mem').textContent = `${usedMB} MB / ${totalMB} MB`;
        }

        const memPercent = (gpuData.mem_used / gpuData.mem_total) * 100;
        document.getElementById('gpu-mem-bar').style.width = `${memPercent}%`;
    }

    // Update GPU temperature
    if (gpuData.temp !== undefined) {
        document.getElementById('gpu-temp').textContent = `${gpuData.temp.toFixed(1)}°C`;
    }
}

document.addEventListener('DOMContentLoaded', function () {
    initChart();
    initNetwork();
    setInterval(updateChart, 1000);
    setInterval(updateStats, 5000);
    initDebugBar();
    trackClientPerformance();

    // Get the current device ID
    getCurrentDeviceId();
});