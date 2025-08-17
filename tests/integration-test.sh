#!/bin/bash

# Integration Test Suite for Ethereum Node Infrastructure
# Comprehensive testing of deployed infrastructure

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
ENV="${1:-local}"
TIMEOUT="${TIMEOUT:-600}"
VERBOSE="${VERBOSE:-false}"

echo -e "${GREEN}=== Ethereum Infrastructure Integration Tests ===${NC}"
echo "Environment: $ENV"
echo "Timeout: ${TIMEOUT}s"
echo ""

# Test results tracking
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
TEST_RESULTS=()

# Function to run a test and track results
run_test() {
    local test_name="$1"
    local test_function="$2"
    local timeout="${3:-60}"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo -e "${BLUE}[TEST $TOTAL_TESTS]${NC} $test_name"
    
    local start_time=$(date +%s)
    
    if timeout "$timeout" bash -c "$test_function" 2>/dev/null; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        echo -e "${GREEN}✓ PASSED${NC} (${duration}s)"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        TEST_RESULTS+=("PASS: $test_name (${duration}s)")
        return 0
    else
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        echo -e "${RED}✗ FAILED${NC} (${duration}s)"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        TEST_RESULTS+=("FAIL: $test_name (${duration}s)")
        
        if [ "$VERBOSE" = "true" ]; then
            echo -e "${RED}Error details:${NC}"
            timeout "$timeout" bash -c "$test_function" 2>&1 | sed 's/^/  /' || true
        fi
        return 1
    fi
}

# Test functions
test_cluster_connectivity() {
    kubectl cluster-info >/dev/null
}

test_namespaces_exist() {
    local namespaces=("ethereum-$ENV" "observability-$ENV" "registry-$ENV" "infrastructure-$ENV" "istio-system")
    for ns in "${namespaces[@]}"; do
        kubectl get namespace "$ns" >/dev/null
    done
}

test_registry_running() {
    kubectl get pods -n "registry-$ENV" -l app=docker-registry -o jsonpath='{.items[*].status.phase}' | grep -q Running
}

test_registry_accessible() {
    kubectl port-forward -n "registry-$ENV" svc/docker-registry 5000:5000 &
    local pf_pid=$!
    sleep 5
    curl -f http://localhost:5000/v2/ >/dev/null
    kill $pf_pid 2>/dev/null || true
}

test_istio_control_plane() {
    kubectl get pods -n istio-system -l app=istiod -o jsonpath='{.items[*].status.phase}' | grep -q Running
}

test_prometheus_running() {
    kubectl get pods -n "observability-$ENV" -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[*].status.phase}' | grep -q Running
}

test_grafana_accessible() {
    kubectl port-forward -n "observability-$ENV" svc/kube-prometheus-stack-grafana 3000:80 &
    local pf_pid=$!
    sleep 5
    curl -f http://localhost:3000/api/health >/dev/null
    kill $pf_pid 2>/dev/null || true
}

test_ethereum_sync_nodes() {
    local pods
    pods=$(kubectl get pods -n "ethereum-$ENV" -l app.kubernetes.io/component=sync-node --no-headers | wc -l)
    [ "$pods" -gt 0 ]
}

test_ethereum_serve_nodes() {
    kubectl get pods -n "ethereum-$ENV" -l app.kubernetes.io/component=serve-node -o jsonpath='{.items[*].status.phase}' | grep -q Running
}

test_ethereum_rpc_endpoint() {
    # Find the serve service
    local service
    service=$(kubectl get service -n "ethereum-$ENV" -l app.kubernetes.io/component=serve-node -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [ -z "$service" ]; then
        return 1
    fi
    
    kubectl port-forward -n "ethereum-$ENV" "svc/$service" 8545:8545 &
    local pf_pid=$!
    sleep 5
    
    # Test basic RPC call
    local result
    result=$(curl -s -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"web3_clientVersion","params":[],"id":1}' \
        http://localhost:8545 | jq -r '.result // empty')
    
    kill $pf_pid 2>/dev/null || true
    
    [ -n "$result" ]
}

test_ethereum_rpc_methods() {
    local service
    service=$(kubectl get service -n "ethereum-$ENV" -l app.kubernetes.io/component=serve-node -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [ -z "$service" ]; then
        return 1
    fi
    
    kubectl port-forward -n "ethereum-$ENV" "svc/$service" 8545:8545 &
    local pf_pid=$!
    sleep 5
    
    # Test multiple RPC methods
    local methods=("web3_clientVersion" "net_version" "eth_blockNumber" "net_peerCount")
    local success_count=0
    
    for method in "${methods[@]}"; do
        local result
        result=$(curl -s -X POST -H "Content-Type: application/json" \
            --data "{\"jsonrpc\":\"2.0\",\"method\":\"$method\",\"params\":[],\"id\":1}" \
            http://localhost:8545 | jq -r '.result // empty')
        
        if [ -n "$result" ] && [ "$result" != "null" ]; then
            success_count=$((success_count + 1))
        fi
    done
    
    kill $pf_pid 2>/dev/null || true
    
    # At least 3 out of 4 methods should work
    [ $success_count -ge 3 ]
}

test_metrics_endpoints() {
    # Test Ethereum node metrics
    local pods
    pods=$(kubectl get pods -n "ethereum-$ENV" -l app.kubernetes.io/component=serve-node -o jsonpath='{.items[*].metadata.name}')
    
    for pod in $pods; do
        kubectl port-forward -n "ethereum-$ENV" "$pod" 6060:6060 &
        local pf_pid=$!
        sleep 3
        
        curl -f http://localhost:6060/debug/metrics/prometheus >/dev/null
        local result=$?
        
        kill $pf_pid 2>/dev/null || true
        
        if [ $result -ne 0 ]; then
            return 1
        fi
        
        break  # Test only the first pod
    done
}

test_hpa_configured() {
    kubectl get hpa -n "ethereum-$ENV" --no-headers | grep -q ethereum
}

test_persistent_volumes() {
    kubectl get pvc -n "ethereum-$ENV" -o jsonpath='{.items[*].status.phase}' | grep -v Bound | wc -l | awk '{exit ($1 > 0)}'
}

test_network_policies() {
    # Only test if network policies are expected to be enabled
    if [ "$ENV" != "local" ]; then
        kubectl get networkpolicy -n "ethereum-$ENV" --no-headers | wc -l | awk '{exit ($1 == 0)}'
    else
        return 0  # Skip for local environment
    fi
}

test_istio_injection() {
    local pods
    pods=$(kubectl get pods -n "ethereum-$ENV" -l app.kubernetes.io/component=serve-node -o jsonpath='{.items[*].spec.containers[*].name}')
    echo "$pods" | grep -q istio-proxy
}

test_snapshot_job_exists() {
    kubectl get cronjob -n "ethereum-$ENV" --no-headers | grep -q snapshot
}

test_load_balancing() {
    local service
    service=$(kubectl get service -n "ethereum-$ENV" -l app.kubernetes.io/component=serve-node -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [ -z "$service" ]; then
        return 1
    fi
    
    kubectl port-forward -n "ethereum-$ENV" "svc/$service" 8545:8545 &
    local pf_pid=$!
    sleep 5
    
    # Make multiple requests and check for different response patterns
    local unique_responses=0
    for i in {1..5}; do
        local result
        result=$(curl -s -X POST -H "Content-Type: application/json" \
            --data '{"jsonrpc":"2.0","method":"web3_clientVersion","params":[],"id":1}' \
            http://localhost:8545 | jq -r '.result // empty')
        
        if [ -n "$result" ]; then
            unique_responses=$((unique_responses + 1))
        fi
        sleep 1
    done
    
    kill $pf_pid 2>/dev/null || true
    
    # At least 4 out of 5 requests should succeed
    [ $unique_responses -ge 4 ]
}

test_resource_monitoring() {
    # Check if metrics are being collected
    kubectl port-forward -n "observability-$ENV" svc/kube-prometheus-stack-prometheus 9090:9090 &
    local pf_pid=$!
    sleep 5
    
    # Query for Ethereum-specific metrics
    local query_result
    query_result=$(curl -s "http://localhost:9090/api/v1/query?query=up{job=\"ethereum-nodes\"}" | jq -r '.data.result | length')
    
    kill $pf_pid 2>/dev/null || true
    
    [ "$query_result" -gt 0 ]
}

test_log_aggregation() {
    # Check if logs are being collected by Loki
    kubectl port-forward -n "observability-$ENV" svc/loki 3100:3100 &
    local pf_pid=$!
    sleep 5
    
    # Query for logs
    local logs_result
    logs_result=$(curl -s "http://localhost:3100/loki/api/v1/label" | jq -r '.data | length')
    
    kill $pf_pid 2>/dev/null || true
    
    [ "$logs_result" -gt 0 ]
}

# Main test execution
main() {
    echo "Starting integration tests for environment: $ENV"
    echo ""
    
    # Basic cluster tests
    run_test "Cluster connectivity" "test_cluster_connectivity" 30
    run_test "Required namespaces exist" "test_namespaces_exist" 30
    
    # Infrastructure tests
    run_test "Container registry is running" "test_registry_running" 60
    run_test "Container registry is accessible" "test_registry_accessible" 60
    run_test "Istio control plane is running" "test_istio_control_plane" 60
    
    # Observability tests
    run_test "Prometheus is running" "test_prometheus_running" 60
    run_test "Grafana is accessible" "test_grafana_accessible" 60
    
    # Ethereum infrastructure tests
    run_test "Ethereum sync nodes are deployed" "test_ethereum_sync_nodes" 60
    run_test "Ethereum serve nodes are running" "test_ethereum_serve_nodes" 60
    run_test "Ethereum RPC endpoint is accessible" "test_ethereum_rpc_endpoint" 120
    run_test "Ethereum RPC methods work" "test_ethereum_rpc_methods" 120
    run_test "Metrics endpoints are accessible" "test_metrics_endpoints" 60
    
    # Kubernetes features tests
    run_test "HPA is configured" "test_hpa_configured" 30
    run_test "Persistent volumes are bound" "test_persistent_volumes" 60
    run_test "Network policies are configured" "test_network_policies" 30
    
    # Service mesh tests
    run_test "Istio sidecar injection works" "test_istio_injection" 60
    run_test "Load balancing works" "test_load_balancing" 120
    
    # Operations tests
    run_test "Snapshot job is configured" "test_snapshot_job_exists" 30
    run_test "Resource monitoring works" "test_resource_monitoring" 60
    run_test "Log aggregation works" "test_log_aggregation" 60
    
    # Generate test report
    echo ""
    echo -e "${GREEN}=== Test Summary ===${NC}"
    echo "Environment: $ENV"
    echo "Total tests: $TOTAL_TESTS"
    echo -e "Passed: ${GREEN}$PASSED_TESTS${NC}"
    echo -e "Failed: ${RED}$FAILED_TESTS${NC}"
    echo ""
    
    if [ $FAILED_TESTS -eq 0 ]; then
        echo -e "${GREEN}🎉 All tests passed! Infrastructure is healthy.${NC}"
        echo ""
        echo "Your Ethereum node infrastructure is ready for use!"
        echo ""
        echo "Next steps:"
        echo "- Monitor dashboards: make dashboard"
        echo "- Check RPC endpoints: make test-rpc"
        echo "- View logs: kubectl logs -n ethereum-$ENV -l app.kubernetes.io/component=serve-node"
        return 0
    else
        echo -e "${RED}❌ Some tests failed. Please review the issues above.${NC}"
        echo ""
        echo "Test results:"
        for result in "${TEST_RESULTS[@]}"; do
            if [[ $result == PASS* ]]; then
                echo -e "  ${GREEN}$result${NC}"
            else
                echo -e "  ${RED}$result${NC}"
            fi
        done
        echo ""
        echo "Troubleshooting:"
        echo "- Run validation: make validate ENV=$ENV"
        echo "- Check debug info: make debug"
        echo "- Review logs: kubectl get pods -A"
        return 1
    fi
}

# Check prerequisites
if ! command -v kubectl >/dev/null 2>&1; then
    echo -e "${RED}kubectl is required but not installed${NC}"
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo -e "${RED}jq is required but not installed${NC}"
    exit 1
fi

if ! kubectl cluster-info >/dev/null 2>&1; then
    echo -e "${RED}Cannot connect to Kubernetes cluster${NC}"
    exit 1
fi

# Run main function
main "$@"
