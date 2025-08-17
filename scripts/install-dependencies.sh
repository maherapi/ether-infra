#!/bin/bash

# Install Required Dependencies for Ethereum Infrastructure
# Installs kubectl, helm, helmfile, and other necessary tools

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Version configuration
HELM_VERSION="${HELM_VERSION:-v3.13.3}"
HELMFILE_VERSION="${HELMFILE_VERSION:-v0.158.1}"
KUBECTL_VERSION="${KUBECTL_VERSION:-v1.28.4}"
ISTIOCTL_VERSION="${ISTIOCTL_VERSION:-1.20.1}"

echo -e "${GREEN}=== Installing Dependencies for Ethereum Infrastructure ===${NC}"

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to get OS and architecture
get_os_arch() {
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)
    
    case $ARCH in
        x86_64)
            ARCH="amd64"
            ;;
        arm64|aarch64)
            ARCH="arm64"
            ;;
        *)
            echo -e "${RED}Unsupported architecture: $ARCH${NC}"
            exit 1
            ;;
    esac
    
    case $OS in
        darwin)
            OS="darwin"
            ;;
        linux)
            OS="linux"
            ;;
        *)
            echo -e "${RED}Unsupported OS: $OS${NC}"
            exit 1
            ;;
    esac
}

# Function to install kubectl
install_kubectl() {
    if command_exists kubectl; then
        local current_version
        current_version=$(kubectl version --client -o yaml | grep gitVersion | cut -d'"' -f4)
        echo -e "${GREEN}kubectl is already installed: $current_version${NC}"
        return 0
    fi
    
    echo -e "${YELLOW}Installing kubectl ${KUBECTL_VERSION}...${NC}"
    
    if [[ "$OS" == "darwin" ]] && command_exists brew; then
        brew install kubectl
    else
        curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/${OS}/${ARCH}/kubectl"
        chmod +x kubectl
        sudo mv kubectl /usr/local/bin/
    fi
    
    echo -e "${GREEN}✓ kubectl installed successfully${NC}"
}

# Function to install helm
install_helm() {
    if command_exists helm; then
        local current_version
        current_version=$(helm version --short | cut -d'+' -f1)
        echo -e "${GREEN}Helm is already installed: $current_version${NC}"
        return 0
    fi
    
    echo -e "${YELLOW}Installing Helm ${HELM_VERSION}...${NC}"
    
    if [[ "$OS" == "darwin" ]] && command_exists brew; then
        brew install helm
    else
        curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
        chmod 700 get_helm.sh
        DESIRED_VERSION="$HELM_VERSION" ./get_helm.sh
        rm get_helm.sh
    fi
    
    echo -e "${GREEN}✓ Helm installed successfully${NC}"
}

# Function to install helmfile
install_helmfile() {
    if command_exists helmfile; then
        local current_version
        current_version=$(helmfile version | grep Version | cut -d'"' -f4)
        echo -e "${GREEN}Helmfile is already installed: $current_version${NC}"
        return 0
    fi
    
    echo -e "${YELLOW}Installing Helmfile ${HELMFILE_VERSION}...${NC}"
    
    if [[ "$OS" == "darwin" ]] && command_exists brew; then
        brew install helmfile
    else
        curl -LO "https://github.com/helmfile/helmfile/releases/download/${HELMFILE_VERSION}/helmfile_${HELMFILE_VERSION#v}_${OS}_${ARCH}.tar.gz"
        tar -xzf "helmfile_${HELMFILE_VERSION#v}_${OS}_${ARCH}.tar.gz"
        chmod +x helmfile
        sudo mv helmfile /usr/local/bin/
        rm "helmfile_${HELMFILE_VERSION#v}_${OS}_${ARCH}.tar.gz"
    fi
    
    echo -e "${GREEN}✓ Helmfile installed successfully${NC}"
}

# Function to install istioctl
install_istioctl() {
    if command_exists istioctl; then
        local current_version
        current_version=$(istioctl version --remote=false | grep client | cut -d':' -f2 | tr -d ' ')
        echo -e "${GREEN}istioctl is already installed: $current_version${NC}"
        return 0
    fi
    
    echo -e "${YELLOW}Installing istioctl ${ISTIOCTL_VERSION}...${NC}"
    
    if [[ "$OS" == "darwin" ]] && command_exists brew; then
        brew install istioctl
    else
        curl -L https://istio.io/downloadIstio | ISTIO_VERSION="$ISTIOCTL_VERSION" sh -
        sudo mv "istio-${ISTIOCTL_VERSION}/bin/istioctl" /usr/local/bin/
        rm -rf "istio-${ISTIOCTL_VERSION}"
    fi
    
    echo -e "${GREEN}✓ istioctl installed successfully${NC}"
}

# Function to install additional tools
install_additional_tools() {
    echo -e "${YELLOW}Installing additional tools...${NC}"
    
    # jq for JSON processing
    if ! command_exists jq; then
        echo "Installing jq..."
        if [[ "$OS" == "darwin" ]] && command_exists brew; then
            brew install jq
        elif [[ "$OS" == "linux" ]]; then
            sudo apt-get update && sudo apt-get install -y jq || \
            sudo yum install -y jq || \
            sudo dnf install -y jq
        fi
    fi
    
    # yq for YAML processing
    if ! command_exists yq; then
        echo "Installing yq..."
        if [[ "$OS" == "darwin" ]] && command_exists brew; then
            brew install yq
        else
            curl -LO "https://github.com/mikefarah/yq/releases/latest/download/yq_${OS}_${ARCH}"
            chmod +x "yq_${OS}_${ARCH}"
            sudo mv "yq_${OS}_${ARCH}" /usr/local/bin/yq
        fi
    fi
    
    # curl (usually pre-installed)
    if ! command_exists curl; then
        echo "Installing curl..."
        if [[ "$OS" == "darwin" ]] && command_exists brew; then
            brew install curl
        elif [[ "$OS" == "linux" ]]; then
            sudo apt-get update && sudo apt-get install -y curl || \
            sudo yum install -y curl || \
            sudo dnf install -y curl
        fi
    fi
    
    echo -e "${GREEN}✓ Additional tools installed${NC}"
}

# Function to add Helm repositories
add_helm_repositories() {
    echo -e "${YELLOW}Adding Helm repositories...${NC}"
    
    # Add essential repositories
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true
    helm repo add grafana https://grafana.github.io/helm-charts || true
    helm repo add istio https://istio-release.storage.googleapis.com/charts || true
    helm repo add rancher https://charts.rancher.io || true
    helm repo add twuni https://helm.twun.io || true
    helm repo add bitnami https://charts.bitnami.com/bitnami || true
    
    # Update repositories
    helm repo update
    
    echo -e "${GREEN}✓ Helm repositories added and updated${NC}"
}

# Function to install Helm plugins
install_helm_plugins() {
    echo -e "${YELLOW}Installing Helm plugins...${NC}"
    
    # Helm diff plugin (useful for helmfile)
    if ! helm plugin list | grep -q "diff"; then
        helm plugin install https://github.com/databus23/helm-diff
    fi
    
    # Helm secrets plugin (for managing secrets)
    if ! helm plugin list | grep -q "secrets"; then
        helm plugin install https://github.com/jkroepke/helm-secrets
    fi
    
    echo -e "${GREEN}✓ Helm plugins installed${NC}"
}

# Function to verify installations
verify_installations() {
    echo -e "${YELLOW}Verifying installations...${NC}"
    
    # Check kubectl
    if command_exists kubectl; then
        echo -e "kubectl: ${GREEN}$(kubectl version --client --short)${NC}"
    else
        echo -e "kubectl: ${RED}NOT INSTALLED${NC}"
    fi
    
    # Check helm
    if command_exists helm; then
        echo -e "helm: ${GREEN}$(helm version --short)${NC}"
    else
        echo -e "helm: ${RED}NOT INSTALLED${NC}"
    fi
    
    # Check helmfile
    if command_exists helmfile; then
        echo -e "helmfile: ${GREEN}$(helmfile version | head -n1)${NC}"
    else
        echo -e "helmfile: ${RED}NOT INSTALLED${NC}"
    fi
    
    # Check istioctl
    if command_exists istioctl; then
        echo -e "istioctl: ${GREEN}$(istioctl version --remote=false 2>/dev/null | head -n1)${NC}"
    else
        echo -e "istioctl: ${RED}NOT INSTALLED${NC}"
    fi
    
    # Check additional tools
    for tool in jq yq curl; do
        if command_exists "$tool"; then
            echo -e "$tool: ${GREEN}✓${NC}"
        else
            echo -e "$tool: ${RED}✗${NC}"
        fi
    done
    
    echo -e "${GREEN}✓ Installation verification completed${NC}"
}

# Main installation function
main() {
    echo "OS: $OS"
    echo "Architecture: $ARCH"
    echo ""
    
    # Install core tools
    install_kubectl
    install_helm
    install_helmfile
    install_istioctl
    install_additional_tools
    
    # Configure Helm
    add_helm_repositories
    install_helm_plugins
    
    # Verify everything
    verify_installations
    
    echo ""
    echo -e "${GREEN}=== Dependencies installation completed! ===${NC}"
    echo ""
    echo "Installed tools:"
    echo "  • kubectl - Kubernetes command-line tool"
    echo "  • helm - Kubernetes package manager"
    echo "  • helmfile - Declarative Helm deployment tool"
    echo "  • istioctl - Istio service mesh CLI"
    echo "  • jq - JSON processor"
    echo "  • yq - YAML processor"
    echo ""
    echo "Next steps:"
    echo "1. Run 'make setup-local' to create a local Kubernetes cluster"
    echo "2. Run 'make deploy-all' to deploy the complete infrastructure"
}

# Get OS and architecture
get_os_arch

# Run main function
main "$@"
