# Makefile for Observability Stack on Mac
.PHONY: help check-deps install-deps setup-cluster install-crds deploy clean destroy

# Variables
CLUSTER_NAME := observability-demo
KIND_CONFIG := kubernetes/kind.yaml
HELMFILE_PATH := helm/helmfiles/monitoring/helmfile.yaml

# Colors
GREEN := \033[0;32m
YELLOW := \033[1;33m
RED := \033[0;31m
NC := \033[0m

help: ## Show available commands
	@echo "$(GREEN)Observability Stack for Mac$(NC)"
	@echo "Available commands:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-15s$(NC) %s\n", $$1, $$2}'

check-deps: ## Check if all dependencies are installed
	@echo "$(YELLOW)Checking dependencies...$(NC)"
	@command -v kubectl >/dev/null 2>&1 || { echo "$(RED)kubectl not found$(NC)"; exit 1; }
	@command -v docker >/dev/null 2>&1 || { echo "$(RED)docker not found$(NC)"; exit 1; }
	@command -v kind >/dev/null 2>&1 || { echo "$(RED)kind not found$(NC)"; exit 1; }
	@command -v k9s >/dev/null 2>&1 || { echo "$(RED)k9s not found$(NC)"; exit 1; }
	@command -v helm >/dev/null 2>&1 || { echo "$(RED)helm not found$(NC)"; exit 1; }
	@command -v helmfile >/dev/null 2>&1 || { echo "$(RED)helmfile not found$(NC)"; exit 1; }
	@echo "$(GREEN)All dependencies are installed!$(NC)"

install-deps: ## Install missing dependencies using Homebrew
	@echo "$(YELLOW)Installing dependencies with Homebrew...$(NC)"
	@if ! command -v brew >/dev/null 2>&1; then \
		echo "$(RED)Homebrew not found. Please install it first: https://brew.sh$(NC)"; \
		exit 1; \
	fi
	@command -v kubectl >/dev/null 2>&1 || brew install kubectl
	@command -v docker >/dev/null 2>&1 || brew install --cask docker
	@command -v kind >/dev/null 2>&1 || brew install kind
	@command -v k9s >/dev/null 2>&1 || brew install k9s
	@command -v helm >/dev/null 2>&1 || brew install helm
	@command -v helmfile >/dev/null 2>&1 || brew install helmfile
	@echo "$(GREEN)Dependencies installed!$(NC)"

setup-cluster: check-deps ## Create Kind cluster with custom config
	@echo "$(YELLOW)Setting up Kind cluster...$(NC)"
	@if kind get clusters | grep -q $(CLUSTER_NAME); then \
		echo "Cluster $(CLUSTER_NAME) already exists"; \
	else \
		if [ -f $(KIND_CONFIG) ]; then \
			kind create cluster --name $(CLUSTER_NAME) --config $(KIND_CONFIG); \
		else \
			kind create cluster --name $(CLUSTER_NAME); \
		fi; \
	fi
	@kubectl cluster-info --context kind-$(CLUSTER_NAME)
	@echo "$(GREEN)Kind cluster ready!$(NC)"

install-crds: setup-cluster ## Install Prometheus Operator CRDs
	@echo "$(YELLOW)Installing Prometheus Operator CRDs...$(NC)"
	@kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
	@curl -sL https://github.com/prometheus-operator/prometheus-operator/releases/download/v0.70.0/stripped-down-crds.yaml | kubectl apply -f -
	@kubectl wait --for=condition=established --timeout=120s crd/servicemonitors.monitoring.coreos.com
	@kubectl wait --for=condition=established --timeout=120s crd/prometheuses.monitoring.coreos.com
	@echo "$(GREEN)CRDs installed successfully!$(NC)"

deploy: install-crds ## Deploy observability stack
	@echo "$(YELLOW)Deploying with Helmfile...$(NC)"
	@cd helm/helmfiles && helmfile apply
	@echo "$(GREEN)Deployment completed!$(NC)"
	@echo ""
	@echo "$(YELLOW)Useful commands:$(NC)"
	@echo "  kubectl get pods -n monitoring"
	@echo "  kubectl port-forward -n monitoring svc/grafana 3000:80"
	@echo "  Access Grafana: http://localhost:3000"

status: ## Show cluster and deployment status
	@echo "$(YELLOW)Cluster Status:$(NC)"
	@kubectl get nodes
	@echo ""
	@echo "$(YELLOW)Monitoring Pods:$(NC)"
	@kubectl get pods -n monitoring
	@echo ""
	@echo "$(YELLOW)Services:$(NC)"
	@kubectl get svc -n monitoring

k9s: ## Launch k9s dashboard
	@k9s -n monitoring

clean: ## Clean up resources but keep cluster
	@echo "$(YELLOW)Cleaning up Helm releases...$(NC)"
	@cd helm/helmfiles && helmfile destroy || true
	@kubectl delete namespace monitoring --ignore-not-found=true
	@echo "$(GREEN)Cleanup completed!$(NC)"

cleanup: destroy ## Alias for destroy command

destroy: ## Delete the entire Kind cluster
	@echo "$(YELLOW)Destroying Kind cluster...$(NC)"
	@kind delete cluster --name $(CLUSTER_NAME)
	@echo "$(GREEN)Cluster destroyed!$(NC)"

# Quick setup command
all: deploy ## Complete setup from scratch