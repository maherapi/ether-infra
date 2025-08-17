#!/bin/bash

# Validate Ethereum Infrastructure Deployment
# Comprehensive validation of all deployed components

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
ENV="${1:-local}"
TIMEOUT="${TIMEOUT:-300}"
VERBOSE="${VERBOSE:-false}"

echo -e "${GREEN}=== Validating Ethereum Infrastructure Deployment ===${NC}"
echo "Environment: $ENV"
echo "Timeout: ${TIMEOUT}s"
echo ""

# Test results tracking
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Function to run a test and track results
run_test() {
    local test_name="$1"
    local test_command="$2"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo -n "Testing $test_name... "
    
    if eval "$test_command" >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        return 0
    else
        echo -e "${RED}✗${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        if [ "$VERBOSE" = "true" ]; then
            echo -e "${RED}Error details:${NC}"
            eval "$test_command" 2>&1 | sed 's/^/  /'
        fi
        return 1
    fi
}

# Function to wait for resource to be ready
wait_for_resource() {
    local resource="$1"
    local namespace="$2"
    local condition="${3:-ready}"
    local timeout="${4:-$TIMEOUT}"
    
    kubectl wait --for=condition="$condition" "$resource" -n "$namespace" --timeout="${timeout}s" >/dev/null 2>&1
}

# Function to check namespace exists and has resources
check_namespace() {
    local namespace="$1"
    local expected_resources="$2"
    
    echo -e "${BLUE}Checking namespace: $namespace${NC}"
    
    # Check namespace exists
    run_test "namespace $namespace exists" \
        "kubectl get namespace $namespace"
    
    # Check for expected resources
    if [ -n "$expected_resources" ]; then
        for resource in $expected_resources; do
            run_test "$resource in $namespace" \
                "kubectl get $resource -n $namespace --no-headers | grep -v 'No resources found'"
        done
    fi
    
    echo ""
}

# Function to check pod health
check_pod_health() {
    local namespace="$1"
    local label_selector="$2"
    local description="$3"
    
    echo -e "${BLUE}Checking pod health: $description${NC}"
    
    # Check pods exist
    run_test "pods exist ($description)" \
        "kubectl get pods -n $namespace -l $label_selector --no-headers | grep -v 'No resources found'"
    
    # Check pods are running
    run_test "pods are running ($description)" \
        "kubectl get pods -n $namespace -l $label_selector -o jsonpath='{.items[*].status.phase}' | grep -v 'Pending\|Failed\|Unknown'"
    
    # Check pods are ready
    run_test "pods are ready ($description)" \
        "kubectl wait --for=condition=ready pod -l $label_selector -n $namespace --timeout=60s"
    
    echo ""
}

# Function to check service endpoints
check_service_endpoints() {
    local namespace="$1"
    local service="$2"
    local port="$3"
    local description="$4"
    
    echo -e "${BLUE}Checking service: $description${NC}"
    
    # Check service exists
    run_test "service $service exists" \
        "kubectl get service $service -n $namespace"
    
    # Check service has endpoints
    run_test "service $service has endpoints" \
        "kubectl get endpoints $service -n $namespace -o jsonpath='{.subsets[*].addresses[*].ip}' | grep -v '^$'"
    
    # Test service connectivity (port-forward)
    if [ -n "$port" ]; then
        run_test "service $service is accessible" \
            "timeout 10s kubectl port-forward -n $namespace svc/$service $port:$port & sleep 2 && curl -f http://localhost:$port/health >/dev/null 2>&1 || curl -f http://localhost:$port >/dev/null 2>&1; kill %1 2>/dev/null || true"
    fi
    
    echo ""
}

# Function to check Ethereum RPC functionality
check_ethereum_rpc() {
    local namespace="$1"
    local service="$2"
    
    echo -e "${BLUE}Checking Ethereum RPC functionality${NC}"
    
    # Port forward to RPC service
    kubectl port-forward -n "$namespace" "svc/$service" 8545:8545 &
    local pf_pid=$!
    sleep 5
    
    # Test basic RPC calls
    run_test "RPC endpoint responds" \
        "curl -f -X POST -H 'Content-Type: application/json' --data '{\"jsonrpc\":\"2.0\",\"method\":\"web3_clientVersion\",\"params\":[],\"id\":1}' http://localhost:8545"
    
    run_test "can get network version" \
        "curl -s -X POST -H 'Content-Type: application/json' --data '{\"jsonrpc\":\"2.0\",\"method\":\"net_version\",\"params\":[],\"id\":1}' http://localhost:8545 | jq -r '.result' | grep -v null"
    
    run_test "can get block number" \
        "curl -s -X POST -H 'Content-Type: application/json' --data '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}' http://localhost:8545 | jq -r '.result' | grep -v null"
    
    run_test "can get peer count" \
        "curl -s -X POST -H 'Content-Type: application/json' --data '{\"jsonrpc\":\"2.0\",\"method\":\"net_peerCount\",\"params\":[],\"id\":1}' http://localhost:8545 | jq -r '.result' | grep -v null"
    
    # Cleanup port forward
    kill $pf_pid 2>/dev/null || true
    
    echo ""
}

# Function to check monitoring stack
check_monitoring() {
    local namespace="observability-$ENV"
    
    echo -e "${BLUE}Checking monitoring stack${NC}"
    
    # Check Prometheus
    check_service_endpoints "$namespace" "kube-prometheus-stack-prometheus" "9090" "Prometheus"
    
    # Check Grafana
    check_service_endpoints "$namespace" "kube-prometheus-stack-grafana" "80" "Grafana"
    
    # Check Loki
    check_service_endpoints "$namespace" "loki" "3100" "Loki"
    
    # Check AlertManager
    run_test "AlertManager is running" \
        "kubectl get pods -n $namespace -l app.kubernetes.io/name=alertmanager -o jsonpath='{.items[*].status.phase}' | grep Running"
    
    echo ""
}

# Function to check Istio service mesh
check_istio() {
    local namespace="istio-system"
    
    echo -e "${BLUE}Checking Istio service mesh${NC}"
    
    # Check Istio control plane
    check_pod_health "$namespace" "app=istiod" "Istio control plane"
    
    # Check Istio gateways
    check_pod_health "$namespace" "app=istio-ingressgateway" "Istio ingress gateway"
    
    # Check if Istio injection is working
    run_test "Istio sidecar injection enabled" \
        "kubectl get namespace ethereum-$ENV -o jsonpath='{.metadata.labels.istio-injection}' | grep enabled"
    
    echo ""
}

# Function to check storage
check_storage() {
    echo -e "${BLUE}Checking storage configuration${NC}"
    
    # Check storage classes
    run_test "storage classes exist" \
        "kubectl get storageclass --no-headers | wc -l | awk '{print \$1 > 0}'"
    
    # Check PVCs
    run_test "PVCs are bound" \
        "kubectl get pvc -A --no-headers | grep -v Bound | wc -l | awk '{print \$1 == 0}'"
    
    echo ""
}

# Function to check network connectivity
check_network() {
    echo -e "${BLUE}Checking network connectivity${NC}"
    
    # Create test pod for network testing
    kubectl run network-test --image=nicolaka/netshoot --rm -it --restart=Never --command -- sleep 300 &
    local test_pod_pid=$!
    
    sleep 10
    
    # Test DNS resolution
    run_test "DNS resolution works" \
        "kubectl exec network-test -- nslookup kubernetes.default.svc.cluster.local"
    
    # Test external connectivity
    run_test "external connectivity works" \
        "kubectl exec network-test -- curl -f https://httpbin.org/get"
    
    # Cleanup test pod
    kubectl delete pod network-test --ignore-not-found=true
    kill $test_pod_pid 2>/dev/null || true
    
    echo ""
}

# Function to check autoscaling
check_autoscaling() {
    local namespace="ethereum-$ENV"
    
    echo -e "${BLUE}Checking autoscaling configuration${NC}"
    
    # Check HPA exists
    run_test "HPA for serve nodes exists" \
        "kubectl get hpa -n $namespace --no-headers | grep -v 'No resources found'"
    
    # Check metrics server is running
    run_test "metrics server is running" \
        "kubectl get pods -n kube-system -l k8s-app=metrics-server -o jsonpath='{.items[*].status.phase}' | grep Running"
    
    echo ""
}

# Function to generate summary report
generate_summary() {
    echo -e "${GREEN}=== Validation Summary ===${NC}"
    echo "Environment: $ENV"
    echo "Total tests: $TOTAL_TESTS"
    echo -e "Passed: ${GREEN}$PASSED_TESTS${NC}"
    echo -e "Failed: ${RED}$FAILED_TESTS${NC}"
    
    if [ $FAILED_TESTS -eq 0 ]; then
        echo -e "${GREEN}✓ All tests passed! Deployment is healthy.${NC}"
        return 0
    else
        echo -e "${RED}✗ Some tests failed. Please check the issues above.${NC}"
        return 1
    fi
}

# Main validation function
main() {
    # Check prerequisites
    if ! command -v kubectl >/dev/null 2>&1; then
        echo -e "${RED}kubectl is required but not installed${NC}"
        exit 1
    fi
    
    # Check if we can connect to the cluster
    if ! kubectl cluster-info >/dev/null 2>&1; then
        echo -e "${RED}Cannot connect to Kubernetes cluster${NC}"
        exit 1
    fi
    
    echo "Current context: $(kubectl config current-context)"
    echo ""
    
    # Infrastructure validation
    check_namespace "infrastructure-$ENV" "configmap secret"
    check_namespace "registry-$ENV" "deployment service"
    check_namespace "istio-system" "deployment service"
    check_namespace "observability-$ENV" "deployment service statefulset"
    check_namespace "ethereum-$ENV" "deployment statefulset service"
    
    # Component health checks
    check_pod_health "registry-$ENV" "app=docker-registry" "Docker registry"
    check_pod_health "ethereum-$ENV" "app.kubernetes.io/component=sync-node" "Ethereum sync nodes"
    check_pod_health "ethereum-$ENV" "app.kubernetes.io/component=serve-node" "Ethereum serve nodes"
    
    # Service endpoint checks
    check_service_endpoints "registry-$ENV" "docker-registry" "5000" "Docker registry"
    
    # Ethereum RPC functionality
    if kubectl get service -n "ethereum-$ENV" --no-headers | grep -q serve; then
        SERVE_SERVICE=$(kubectl get service -n "ethereum-$ENV" -l app.kubernetes.io/component=serve-node -o jsonpath='{.items[0].metadata.name}')
        check_ethereum_rpc "ethereum-$ENV" "$SERVE_SERVICE"
    fi
    
    # Infrastructure components
    check_monitoring
    check_istio
    check_storage
    check_network
    check_autoscaling
    
    # Generate final summary
    generate_summary
}

# Run main function
main "$@"
