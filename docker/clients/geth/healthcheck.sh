#!/bin/bash

# Geth Health Check Script
# Checks if Geth is running and responding to RPC calls

set -e

# Default RPC endpoint
RPC_ENDPOINT="${RPC_ENDPOINT:-http://localhost:8545}"

# Timeout for RPC calls
TIMEOUT="${TIMEOUT:-10}"

# Function to make RPC call
rpc_call() {
    local method="$1"
    local params="$2"
    
    curl -s -f --max-time "$TIMEOUT" \
        -X POST \
        -H "Content-Type: application/json" \
        --data "{\"jsonrpc\":\"2.0\",\"method\":\"$method\",\"params\":$params,\"id\":1}" \
        "$RPC_ENDPOINT"
}

# Check if RPC endpoint is responding
echo "Checking Geth RPC endpoint: $RPC_ENDPOINT"

# Test basic connectivity
if ! rpc_call "web3_clientVersion" "[]" >/dev/null; then
    echo "ERROR: Geth RPC endpoint is not responding"
    exit 1
fi

# Get client version
CLIENT_VERSION=$(rpc_call "web3_clientVersion" "[]" | jq -r '.result // "unknown"')
echo "Client version: $CLIENT_VERSION"

# Check if we're getting block numbers
BLOCK_NUMBER=$(rpc_call "eth_blockNumber" "[]" | jq -r '.result // "0x0"')
BLOCK_DECIMAL=$(printf "%d" "$BLOCK_NUMBER" 2>/dev/null || echo "0")

echo "Current block: $BLOCK_DECIMAL"

# Check if we have a reasonable block number (not stuck at 0)
if [ "$BLOCK_DECIMAL" -eq 0 ]; then
    echo "WARNING: Block number is 0, node might be starting up"
    # Allow some time for initial sync, but don't fail immediately
    exit 0
fi

# Check sync status
SYNC_STATUS=$(rpc_call "eth_syncing" "[]" | jq -r '.result')

if [ "$SYNC_STATUS" = "false" ]; then
    echo "Node is fully synced"
elif [ "$SYNC_STATUS" = "null" ] || [ "$SYNC_STATUS" = "" ]; then
    echo "Could not determine sync status"
else
    # Extract sync info if available
    CURRENT_BLOCK=$(echo "$SYNC_STATUS" | jq -r '.currentBlock // "0x0"' | xargs printf "%d")
    HIGHEST_BLOCK=$(echo "$SYNC_STATUS" | jq -r '.highestBlock // "0x0"' | xargs printf "%d")
    
    if [ "$HIGHEST_BLOCK" -gt 0 ] && [ "$CURRENT_BLOCK" -gt 0 ]; then
        SYNC_PERCENT=$((CURRENT_BLOCK * 100 / HIGHEST_BLOCK))
        echo "Node is syncing: $SYNC_PERCENT% ($CURRENT_BLOCK/$HIGHEST_BLOCK)"
        
        # If we're very far behind, that might indicate a problem
        if [ "$SYNC_PERCENT" -lt 50 ] && [ "$CURRENT_BLOCK" -gt 1000 ]; then
            echo "WARNING: Node appears to be significantly behind"
        fi
    else
        echo "Node is syncing (details unavailable)"
    fi
fi

# Check peer count
PEER_COUNT=$(rpc_call "net_peerCount" "[]" | jq -r '.result // "0x0"' | xargs printf "%d")
echo "Peer count: $PEER_COUNT"

# Warn if we have very few peers
if [ "$PEER_COUNT" -lt 3 ]; then
    echo "WARNING: Low peer count ($PEER_COUNT), network connectivity might be limited"
fi

# Check if we can get network ID
NETWORK_ID=$(rpc_call "net_version" "[]" | jq -r '.result // "unknown"')
echo "Network ID: $NETWORK_ID"

echo "Health check passed"
exit 0
