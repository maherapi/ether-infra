#!/usr/bin/env python3

"""
Simple metrics server for snapshot builder monitoring
Provides Prometheus-compatible metrics on port 8080
"""

import http.server
import socketserver
import time
import os
import json
import threading
from datetime import datetime

class SnapshotMetrics:
    def __init__(self):
        self.start_time = time.time()
        self.status = "running"
        self.current_operation = "initializing"
        self.progress_percent = 0
        self.bytes_processed = 0
        self.snapshots_created = 0
        self.snapshots_cleaned = 0
        self.last_error = ""
        self.lock = threading.Lock()
    
    def update_status(self, status, operation="", progress=None, bytes_processed=None):
        with self.lock:
            self.status = status
            if operation:
                self.current_operation = operation
            if progress is not None:
                self.progress_percent = progress
            if bytes_processed is not None:
                self.bytes_processed = bytes_processed
    
    def increment_snapshots_created(self):
        with self.lock:
            self.snapshots_created += 1
    
    def increment_snapshots_cleaned(self):
        with self.lock:
            self.snapshots_cleaned += 1
    
    def set_error(self, error):
        with self.lock:
            self.last_error = error
    
    def get_metrics(self):
        with self.lock:
            pod_name = os.environ.get('POD_NAME', 'unknown')
            namespace = os.environ.get('POD_NAMESPACE', 'unknown')
            network = os.environ.get('ETHEREUM_NETWORK', 'unknown')
            
            uptime = time.time() - self.start_time
            
            metrics = f"""# HELP snapshot_builder_info Information about the snapshot builder
# TYPE snapshot_builder_info gauge
snapshot_builder_info{{pod="{pod_name}",namespace="{namespace}",network="{network}"}} 1

# HELP snapshot_builder_uptime_seconds Uptime of the snapshot builder in seconds
# TYPE snapshot_builder_uptime_seconds counter
snapshot_builder_uptime_seconds {uptime}

# HELP snapshot_builder_status Current status of the builder (0=stopped, 1=running, 2=error)
# TYPE snapshot_builder_status gauge
snapshot_builder_status {{"running": 1, "stopped": 0, "error": 2}.get(self.status, 0)}

# HELP snapshot_builder_progress_percent Current operation progress percentage
# TYPE snapshot_builder_progress_percent gauge
snapshot_builder_progress_percent {self.progress_percent}

# HELP snapshot_builder_bytes_processed_total Total bytes processed
# TYPE snapshot_builder_bytes_processed_total counter
snapshot_builder_bytes_processed_total {self.bytes_processed}

# HELP snapshot_builder_snapshots_created_total Total snapshots created
# TYPE snapshot_builder_snapshots_created_total counter
snapshot_builder_snapshots_created_total {self.snapshots_created}

# HELP snapshot_builder_snapshots_cleaned_total Total snapshots cleaned up
# TYPE snapshot_builder_snapshots_cleaned_total counter
snapshot_builder_snapshots_cleaned_total {self.snapshots_cleaned}

# HELP snapshot_builder_last_operation_info Information about the current/last operation
# TYPE snapshot_builder_last_operation_info gauge
snapshot_builder_last_operation_info{{operation="{self.current_operation}"}} 1
"""
            
            if self.last_error:
                metrics += f"""
# HELP snapshot_builder_last_error_info Information about the last error
# TYPE snapshot_builder_last_error_info gauge
snapshot_builder_last_error_info{{error="{self.last_error}"}} 1
"""
            
            return metrics

# Global metrics instance
metrics = SnapshotMetrics()

class MetricsHandler(http.server.BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        # Suppress request logging
        pass
    
    def do_GET(self):
        if self.path == '/metrics':
            self.send_response(200)
            self.send_header('Content-type', 'text/plain; charset=utf-8')
            self.end_headers()
            self.wfile.write(metrics.get_metrics().encode('utf-8'))
        elif self.path == '/health':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            health_data = {
                "status": metrics.status,
                "uptime": time.time() - metrics.start_time,
                "current_operation": metrics.current_operation,
                "progress": metrics.progress_percent,
                "timestamp": datetime.utcnow().isoformat() + 'Z'
            }
            self.wfile.write(json.dumps(health_data, indent=2).encode('utf-8'))
        elif self.path == '/':
            self.send_response(200)
            self.send_header('Content-type', 'text/html')
            self.end_headers()
            html = """<!DOCTYPE html>
<html>
<head>
    <title>Snapshot Builder Metrics</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .metric { margin: 10px 0; }
        .status { font-weight: bold; }
        .running { color: green; }
        .error { color: red; }
        .stopped { color: orange; }
    </style>
</head>
<body>
    <h1>Ethereum Snapshot Builder</h1>
    <div class="metric">Status: <span class="status {status}">{status}</span></div>
    <div class="metric">Operation: {operation}</div>
    <div class="metric">Progress: {progress}%</div>
    <div class="metric">Uptime: {uptime:.1f}s</div>
    <div class="metric">Snapshots Created: {created}</div>
    <div class="metric">Snapshots Cleaned: {cleaned}</div>
    <p><a href="/metrics">Prometheus Metrics</a> | <a href="/health">Health Check</a></p>
</body>
</html>""".format(
                status=metrics.status,
                operation=metrics.current_operation,
                progress=metrics.progress_percent,
                uptime=time.time() - metrics.start_time,
                created=metrics.snapshots_created,
                cleaned=metrics.snapshots_cleaned
            )
            self.wfile.write(html.encode('utf-8'))
        else:
            self.send_response(404)
            self.end_headers()
    
    def do_POST(self):
        if self.path == '/update':
            content_length = int(self.headers.get('Content-Length', 0))
            post_data = self.rfile.read(content_length)
            try:
                data = json.loads(post_data.decode('utf-8'))
                metrics.update_status(
                    data.get('status', metrics.status),
                    data.get('operation', ''),
                    data.get('progress'),
                    data.get('bytes_processed')
                )
                if data.get('snapshots_created'):
                    metrics.increment_snapshots_created()
                if data.get('snapshots_cleaned'):
                    metrics.increment_snapshots_cleaned()
                if data.get('error'):
                    metrics.set_error(data['error'])
                
                self.send_response(200)
                self.send_header('Content-type', 'application/json')
                self.end_headers()
                self.wfile.write(b'{"status": "updated"}')
            except Exception as e:
                self.send_response(400)
                self.send_header('Content-type', 'application/json')
                self.end_headers()
                error_response = json.dumps({"error": str(e)})
                self.wfile.write(error_response.encode('utf-8'))
        else:
            self.send_response(404)
            self.end_headers()

def main():
    port = int(os.environ.get('METRICS_PORT', 8080))
    
    print(f"Starting metrics server on port {port}")
    print(f"Pod: {os.environ.get('POD_NAME', 'unknown')}")
    print(f"Network: {os.environ.get('ETHEREUM_NETWORK', 'unknown')}")
    
    with socketserver.TCPServer(("", port), MetricsHandler) as httpd:
        print(f"Metrics server started at http://0.0.0.0:{port}")
        print("Endpoints:")
        print("  /metrics - Prometheus metrics")
        print("  /health  - Health check")
        print("  /        - Status page")
        print("  POST /update - Update metrics")
        
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nShutting down metrics server...")
            metrics.update_status("stopped", "shutdown")

if __name__ == "__main__":
    main()
