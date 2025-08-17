#!/bin/bash

# Snapshot Builder Entrypoint
# Handles different snapshot operations

set -e

echo "=== Ethereum Snapshot Builder ==="
echo "Time: $(date)"
echo "User: $(whoami)"
echo "Working directory: $(pwd)"
echo "Command: $*"

# Start metrics server in background
echo "Starting metrics server on port 8080..."
python3 /usr/local/bin/metrics-server.py &
METRICS_PID=$!

# Function to cleanup on exit
cleanup() {
    echo "Cleaning up..."
    if [ -n "$METRICS_PID" ]; then
        kill $METRICS_PID 2>/dev/null || true
    fi
    exit $1
}

# Set up signal handlers
trap 'cleanup 130' INT
trap 'cleanup 143' TERM

# Default action
ACTION="${1:-create-snapshot}"

case "$ACTION" in
    "create-snapshot")
        echo "Starting snapshot creation process..."
        exec /scripts/create-snapshot.sh
        ;;
    "cleanup-snapshots")
        echo "Starting snapshot cleanup process..."
        exec /scripts/cleanup-snapshots.sh
        ;;
    "verify-snapshot")
        echo "Starting snapshot verification process..."
        exec /scripts/verify-snapshot.sh "$2"
        ;;
    "list-snapshots")
        echo "Listing available snapshots..."
        exec /scripts/list-snapshots.sh
        ;;
    "health-check")
        echo "Running health check..."
        exec /usr/local/bin/healthcheck.sh
        ;;
    *)
        echo "Unknown action: $ACTION"
        echo "Available actions:"
        echo "  create-snapshot   - Create a new blockchain snapshot"
        echo "  cleanup-snapshots - Clean up old snapshots"
        echo "  verify-snapshot   - Verify a snapshot file"
        echo "  list-snapshots    - List available snapshots"
        echo "  health-check      - Run health check"
        cleanup 1
        ;;
esac
