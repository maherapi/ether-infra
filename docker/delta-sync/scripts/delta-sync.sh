#!/bin/bash

# Delta Sync Script
# Performs fast synchronization using snapshots and incremental updates

set -e

echo "=== Ethereum Delta Sync ==="
echo "Time: $(date)"
echo "Data directory: /data"
echo "Registry: ${REGISTRY_URL:-localhost:5000}"
echo "Network: ${ETHEREUM_NETWORK:-sepolia}"

# Configuration
REGISTRY_URL="${REGISTRY_URL:-localhost:5000}"
ETHEREUM_NETWORK="${ETHEREUM_NETWORK:-sepolia}"
SNAPSHOT_REPOSITORY="${SNAPSHOT_REPOSITORY:-ethereum/snapshots}"
SYNC_TIMEOUT="${SYNC_TIMEOUT:-1800}"  # 30 minutes
MAX_PEERS="${MAX_PEERS:-10}"

# Function to update progress
update_progress() {
    local message="$1"
    local percent="${2:-0}"
    echo "[$(date)] $message (${percent}%)"
}

# Function to check if we have sync nodes available
check_sync_nodes() {
    local nodes_found=0
    
    # Check for available sync node services
    for client in geth nethermind erigon besu; do
        local url_var="${client^^}_SYNC_NODE_URL"
        local url="${!url_var}"
        
        if [ -n "$url" ]; then
            echo "Checking sync node: $client at $url"
            if curl -s -f --max-time 10 "$url" >/dev/null 2>&1; then
                echo "✓ Found working sync node: $client"
                echo "$url"
                return 0
            else
                echo "✗ Sync node not available: $client"
            fi
        fi
    done
    
    return 1
}

# Function to get latest snapshot
get_latest_snapshot() {
    echo "Checking for latest snapshot in registry..."
    
    # Get list of snapshots from registry
    local snapshots_json
    if snapshots_json=$(curl -s "http://${REGISTRY_URL}/v2/${SNAPSHOT_REPOSITORY}/tags/list" 2>/dev/null); then
        local latest_snapshot
        latest_snapshot=$(echo "$snapshots_json" | jq -r ".tags[]? | select(startswith(\"${ETHEREUM_NETWORK}_snapshot_\"))" | sort -r | head -n1)
        
        if [ -n "$latest_snapshot" ] && [ "$latest_snapshot" != "null" ]; then
            echo "Found latest snapshot: $latest_snapshot"
            echo "$latest_snapshot"
            return 0
        fi
    fi
    
    echo "No snapshots found in registry"
    return 1
}

# Function to download and extract snapshot
download_snapshot() {
    local snapshot_tag="$1"
    
    update_progress "Downloading snapshot: $snapshot_tag" 10
    
    # Create temporary directory for download
    local temp_dir="/tmp/snapshot_download"
    mkdir -p "$temp_dir"
    
    # Get manifest to find the blob
    local manifest_url="http://${REGISTRY_URL}/v2/${SNAPSHOT_REPOSITORY}/manifests/${snapshot_tag}"
    local manifest
    
    if ! manifest=$(curl -s -H "Accept: application/vnd.docker.distribution.manifest.v2+json" "$manifest_url"); then
        echo "ERROR: Failed to get snapshot manifest"
        return 1
    fi
    
    # Extract blob digest (simplified - in reality you'd parse the manifest properly)
    local blob_digest
    blob_digest=$(echo "$manifest" | jq -r '.layers[0].digest // .config.digest' 2>/dev/null || echo "")
    
    if [ -z "$blob_digest" ]; then
        echo "ERROR: Could not extract blob digest from manifest"
        return 1
    fi
    
    # Download the blob
    local blob_url="http://${REGISTRY_URL}/v2/${SNAPSHOT_REPOSITORY}/blobs/${blob_digest}"
    
    update_progress "Downloading snapshot data" 30
    
    if ! curl -L "$blob_url" -o "${temp_dir}/snapshot.tar.gz"; then
        echo "ERROR: Failed to download snapshot blob"
        return 1
    fi
    
    update_progress "Extracting snapshot" 60
    
    # Extract snapshot to data directory
    if ! tar -xzf "${temp_dir}/snapshot.tar.gz" -C /data --strip-components=1; then
        echo "ERROR: Failed to extract snapshot"
        return 1
    fi
    
    # Cleanup
    rm -rf "$temp_dir"
    
    update_progress "Snapshot extraction completed" 80
    return 0
}

# Function to perform incremental sync
incremental_sync() {
    local sync_node_url="$1"
    
    update_progress "Starting incremental sync from $sync_node_url" 85
    
    # Get current block from sync node
    local target_block
    target_block=$(curl -s -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        "$sync_node_url" | jq -r '.result // "0x0"')
    
    local target_decimal
    target_decimal=$(printf "%d" "$target_block" 2>/dev/null || echo "0")
    
    echo "Target block: $target_decimal"
    
    # Check our current block
    local current_block="0"
    if [ -f "/data/geth/chaindata/CURRENT" ]; then
        # Start geth briefly to check current state
        timeout 30 geth --datadir=/data \
            --${ETHEREUM_NETWORK} \
            --syncmode=snap \
            --maxpeers=0 \
            --nodiscover \
            console --exec "eth.blockNumber" 2>/dev/null | tail -n1 || echo "0"
    fi
    
    echo "Current block: $current_block"
    
    # If we're significantly behind, do a fast sync
    local block_diff=$((target_decimal - current_block))
    
    if [ "$block_diff" -gt 100 ]; then
        echo "Performing fast sync (behind by $block_diff blocks)"
        
        # Run geth with snap sync for catch-up
        timeout "$SYNC_TIMEOUT" geth --datadir=/data \
            --${ETHEREUM_NETWORK} \
            --syncmode=snap \
            --snapshot=false \
            --maxpeers="$MAX_PEERS" \
            --bootnodes="" \
            --http --http.addr=127.0.0.1 --http.port=8545 \
            --verbosity=3 &
        
        local geth_pid=$!
        
        # Monitor sync progress
        local timeout_count=0
        local max_timeout=$((SYNC_TIMEOUT / 30))
        
        while [ $timeout_count -lt $max_timeout ]; do
            sleep 30
            timeout_count=$((timeout_count + 1))
            
            # Check if geth is still running
            if ! kill -0 $geth_pid 2>/dev/null; then
                echo "Geth process has stopped"
                break
            fi
            
            # Check sync progress
            local sync_status
            sync_status=$(curl -s -X POST -H "Content-Type: application/json" \
                --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
                "http://127.0.0.1:8545" | jq -r '.result' 2>/dev/null || echo "true")
            
            if [ "$sync_status" = "false" ]; then
                echo "Sync completed!"
                break
            elif [ "$sync_status" != "true" ] && [ "$sync_status" != "null" ]; then
                # Extract sync progress
                local current_sync
                current_sync=$(echo "$sync_status" | jq -r '.currentBlock // "0x0"' | xargs printf "%d" 2>/dev/null || echo "0")
                local highest_sync
                highest_sync=$(echo "$sync_status" | jq -r '.highestBlock // "0x0"' | xargs printf "%d" 2>/dev/null || echo "0")
                
                if [ "$highest_sync" -gt 0 ]; then
                    local sync_percent=$((current_sync * 100 / highest_sync))
                    echo "Sync progress: $sync_percent% ($current_sync/$highest_sync)"
                fi
            fi
        done
        
        # Stop geth gracefully
        if kill -0 $geth_pid 2>/dev/null; then
            echo "Stopping geth..."
            kill -TERM $geth_pid
            wait $geth_pid || true
        fi
    else
        echo "Already close to target block (behind by $block_diff blocks)"
    fi
    
    update_progress "Incremental sync completed" 95
}

# Main delta sync process
main() {
    update_progress "Starting delta sync process" 0
    
    # Ensure data directory exists and is writable
    if [ ! -d "/data" ]; then
        echo "ERROR: Data directory /data does not exist"
        exit 1
    fi
    
    if [ ! -w "/data" ]; then
        echo "ERROR: Data directory /data is not writable"
        exit 1
    fi
    
    # Check if we already have blockchain data
    if [ -f "/data/geth/chaindata/CURRENT" ]; then
        echo "Found existing blockchain data, checking if update is needed..."
        
        # Check if sync nodes are available for incremental update
        if sync_node_url=$(check_sync_nodes); then
            incremental_sync "$sync_node_url"
        else
            echo "No sync nodes available for incremental update"
        fi
    else
        echo "No existing blockchain data found, attempting full initialization..."
        
        # Try to get a snapshot first
        if latest_snapshot=$(get_latest_snapshot); then
            if download_snapshot "$latest_snapshot"; then
                echo "Successfully initialized from snapshot"
                
                # Then do incremental sync if possible
                if sync_node_url=$(check_sync_nodes); then
                    incremental_sync "$sync_node_url"
                fi
            else
                echo "Failed to download snapshot, will perform full sync"
            fi
        else
            echo "No snapshot available, will perform full sync"
        fi
    fi
    
    update_progress "Delta sync process completed" 100
    
    # Verify the final state
    if [ -f "/data/geth/chaindata/CURRENT" ]; then
        echo "✓ Delta sync completed successfully"
        echo "Data directory ready for Ethereum client"
        
        # Create a marker file to indicate delta sync completion
        echo "$(date -Iseconds)" > /data/.delta-sync-completed
    else
        echo "✗ Delta sync failed - no blockchain data available"
        exit 1
    fi
}

# Run main function
main "$@"
