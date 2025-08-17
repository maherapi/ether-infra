#!/bin/bash

# Setup Local Kubernetes Cluster for Ethereum Infrastructure
# Supports kind, k3d, and Docker Desktop

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
CLUSTER_NAME="${CLUSTER_NAME:-ethereum-local}"
K8S_VERSION="${K8S_VERSION:-v1.28.0}"
CLUSTER_PROVIDER="${CLUSTER_PROVIDER:-kind}"  # kind, k3d, docker-desktop

echo -e "${GREEN}=== Setting up Local Kubernetes Cluster ===${NC}"
echo "Cluster: $CLUSTER_NAME"
echo "Provider: $CLUSTER_PROVIDER"
echo "Kubernetes Version: $K8S_VERSION"

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install kind
install_kind() {
    echo -e "${YELLOW}Installing kind...${NC}"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        if command_exists brew; then
            brew install kind
        else
            echo "Please install Homebrew first: https://brew.sh/"
            exit 1
        fi
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
        chmod +x ./kind
        sudo mv ./kind /usr/local/bin/kind
    else
        echo "Unsupported OS: $OSTYPE"
        exit 1
    fi
}

# Function to install k3d
install_k3d() {
    echo -e "${YELLOW}Installing k3d...${NC}"
    curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
}

# Function to setup kind cluster
setup_kind_cluster() {
    echo -e "${YELLOW}Setting up kind cluster...${NC}"
    
    # Check if cluster already exists
    if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
        echo "Cluster $CLUSTER_NAME already exists"
        read -p "Do you want to recreate it? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            kind delete cluster --name "$CLUSTER_NAME"
        else
            echo "Using existing cluster"
            return 0
        fi
    fi
    
    # Create kind configuration
    cat <<EOF > /tmp/kind-config.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: ${CLUSTER_NAME}
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
  - containerPort: 30303
    hostPort: 30303
    protocol: TCP
  - containerPort: 30303
    hostPort: 30303
    protocol: UDP
- role: worker
- role: worker
networking:
  apiServerAddress: "127.0.0.1"
  apiServerPort: 6443
  podSubnet: "10.244.0.0/16"
  serviceSubnet: "10.96.0.0/16"
EOF

    # Create cluster
    kind create cluster --config /tmp/kind-config.yaml --image "kindest/node:${K8S_VERSION}"
    
    # Set kubeconfig context
    kubectl config use-context "kind-${CLUSTER_NAME}"
    
    # Install local-path-provisioner for dynamic storage
    kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.24/deploy/local-path-storage.yaml
    
    # Wait for local-path-provisioner to be ready
    kubectl wait --for=condition=ready pod -l app=local-path-provisioner -n local-path-storage --timeout=300s
    
    # Set local-path as default storage class
    kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
    
    echo -e "${GREEN}✓ Kind cluster created successfully${NC}"
}

# Function to setup k3d cluster
setup_k3d_cluster() {
    echo -e "${YELLOW}Setting up k3d cluster...${NC}"
    
    # Check if cluster already exists
    if k3d cluster list | grep -q "$CLUSTER_NAME"; then
        echo "Cluster $CLUSTER_NAME already exists"
        read -p "Do you want to recreate it? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            k3d cluster delete "$CLUSTER_NAME"
        else
            echo "Using existing cluster"
            return 0
        fi
    fi
    
    # Create k3d cluster
    k3d cluster create "$CLUSTER_NAME" \
        --agents 2 \
        --port "80:80@loadbalancer" \
        --port "443:443@loadbalancer" \
        --port "30303:30303@loadbalancer" \
        --port "30303:30303/udp@loadbalancer" \
        --k3s-arg "--disable=traefik@server:0" \
        --image "rancher/k3s:v${K8S_VERSION#v}-k3s1"
    
    # Set kubeconfig context
    kubectl config use-context "k3d-${CLUSTER_NAME}"
    
    echo -e "${GREEN}✓ K3d cluster created successfully${NC}"
}

# Function to verify Docker Desktop Kubernetes
verify_docker_desktop() {
    echo -e "${YELLOW}Verifying Docker Desktop Kubernetes...${NC}"
    
    if ! kubectl config current-context | grep -q "docker-desktop"; then
        echo -e "${RED}Docker Desktop Kubernetes is not enabled or not the current context${NC}"
        echo "Please enable Kubernetes in Docker Desktop settings and set it as current context"
        exit 1
    fi
    
    echo -e "${GREEN}✓ Docker Desktop Kubernetes is ready${NC}"
}

# Function to install MetalLB for LoadBalancer support (kind/k3d)
install_metallb() {
    echo -e "${YELLOW}Installing MetalLB for LoadBalancer support...${NC}"
    
    # Apply MetalLB manifest
    kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/config/manifests/metallb-native.yaml
    
    # Wait for MetalLB to be ready
    kubectl wait --namespace metallb-system \
        --for=condition=ready pod \
        --selector=app=metallb \
        --timeout=90s
    
    # Configure address pool
    if [[ "$CLUSTER_PROVIDER" == "kind" ]]; then
        # Get Docker network subnet for kind
        SUBNET=$(docker network inspect -f '{{.IPAM.Config}}' kind | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+' | head -1)
        if [ -z "$SUBNET" ]; then
            SUBNET="172.18.255.200-172.18.255.250"
        else
            # Extract network and create address range
            NETWORK=$(echo "$SUBNET" | cut -d'/' -f1 | cut -d'.' -f1-3)
            SUBNET="${NETWORK}.200-${NETWORK}.250"
        fi
    else
        # Default range for k3d
        SUBNET="172.20.255.200-172.20.255.250"
    fi
    
    cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: example
  namespace: metallb-system
spec:
  addresses:
  - ${SUBNET}
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: empty
  namespace: metallb-system
EOF

    echo -e "${GREEN}✓ MetalLB installed with address pool: $SUBNET${NC}"
}

# Function to verify cluster setup
verify_cluster() {
    echo -e "${YELLOW}Verifying cluster setup...${NC}"
    
    # Check nodes
    echo "Nodes:"
    kubectl get nodes -o wide
    
    # Check system pods
    echo -e "\nSystem pods:"
    kubectl get pods -n kube-system
    
    # Check storage classes
    echo -e "\nStorage classes:"
    kubectl get storageclass
    
    # Test pod creation
    echo -e "\nTesting pod creation..."
    kubectl run test-pod --image=nginx --rm -it --restart=Never -- echo "Cluster is working!"
    
    echo -e "${GREEN}✓ Cluster verification completed${NC}"
}

# Main setup function
main() {
    # Check prerequisites
    if ! command_exists docker; then
        echo -e "${RED}Docker is required but not installed${NC}"
        exit 1
    fi
    
    if ! command_exists kubectl; then
        echo -e "${RED}kubectl is required but not installed${NC}"
        echo "Please install kubectl: https://kubernetes.io/docs/tasks/tools/"
        exit 1
    fi
    
    # Setup based on provider
    case "$CLUSTER_PROVIDER" in
        "kind")
            if ! command_exists kind; then
                install_kind
            fi
            setup_kind_cluster
            install_metallb
            ;;
        "k3d")
            if ! command_exists k3d; then
                install_k3d
            fi
            setup_k3d_cluster
            install_metallb
            ;;
        "docker-desktop")
            verify_docker_desktop
            ;;
        *)
            echo -e "${RED}Unsupported cluster provider: $CLUSTER_PROVIDER${NC}"
            echo "Supported providers: kind, k3d, docker-desktop"
            exit 1
            ;;
    esac
    
    # Verify setup
    verify_cluster
    
    echo -e "${GREEN}=== Local Kubernetes cluster setup completed! ===${NC}"
    echo -e "Cluster: ${GREEN}$CLUSTER_NAME${NC}"
    echo -e "Provider: ${GREEN}$CLUSTER_PROVIDER${NC}"
    echo -e "Context: ${GREEN}$(kubectl config current-context)${NC}"
    echo ""
    echo "Next steps:"
    echo "1. Run 'make deploy-infrastructure' to deploy the infrastructure stack"
    echo "2. Run 'make deploy-ethereum' to deploy Ethereum nodes"
    echo "3. Run 'make validate' to verify the deployment"
}

# Run main function
main "$@"
