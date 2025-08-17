# Ethereum Node Infrastructure Makefile
# Provides simple commands for managing the complete infrastructure stack

.PHONY: help setup-local setup-dependencies deploy-all deploy-infrastructure deploy-ethereum validate clean test

# Default environment (can be overridden)
ENV ?= local

# Color codes for output
GREEN := \033[32m
YELLOW := \033[33m
RED := \033[31m
RESET := \033[0m

help: ## Show this help message
	@echo "$(GREEN)Ethereum Node Infrastructure Management$(RESET)"
	@echo ""
	@echo "$(YELLOW)Available commands:$(RESET)"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  $(GREEN)%-20s$(RESET) %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo ""
	@echo "$(YELLOW)Environment Variables:$(RESET)"
	@echo "  ENV=local|staging|production  (default: local)"
	@echo ""
	@echo "$(YELLOW)Examples:$(RESET)"
	@echo "  make setup-local              # Setup local K8s cluster"
	@echo "  make deploy-all ENV=staging   # Deploy to staging environment"
	@echo "  make validate ENV=production  # Validate production deployment"

setup-local: ## Setup local Kubernetes cluster and dependencies
	@echo "$(GREEN)Setting up local Kubernetes cluster...$(RESET)"
	@chmod +x scripts/setup-local-k8s.sh && ./scripts/setup-local-k8s.sh
	@chmod +x scripts/install-dependencies.sh && ./scripts/install-dependencies.sh
	@echo "$(GREEN)Local setup complete!$(RESET)"

setup-dependencies: ## Install required tools (helm, helmfile, kubectl)
	@echo "$(GREEN)Installing dependencies...$(RESET)"
	@chmod +x scripts/install-dependencies.sh && ./scripts/install-dependencies.sh

configure-environment: ## Configure environment-specific settings
	@echo "$(GREEN)Configuring environment: $(ENV)$(RESET)"
	@chmod +x scripts/configure-environment.sh && ./scripts/configure-environment.sh $(ENV)

deploy-infrastructure: ## Deploy infrastructure components (storage, networking, observability)
	@echo "$(GREEN)Deploying infrastructure components for $(ENV)...$(RESET)"
	helmfile -e $(ENV) -l name=infrastructure apply
	helmfile -e $(ENV) -l name=local-registry apply
	helmfile -e $(ENV) -l name=istio apply
	helmfile -e $(ENV) -l name=observability apply
	@echo "$(GREEN)Infrastructure deployment complete!$(RESET)"

deploy-ethereum: ## Deploy Ethereum nodes and services
	@echo "$(GREEN)Deploying Ethereum infrastructure for $(ENV)...$(RESET)"
	helmfile -e $(ENV) -l name=ethereum apply
	@echo "$(GREEN)Ethereum deployment complete!$(RESET)"

deploy-all: ## Deploy complete infrastructure stack
	@echo "$(GREEN)Deploying complete stack for $(ENV)...$(RESET)"
	helmfile -e $(ENV) apply
	@echo "$(GREEN)Complete deployment finished!$(RESET)"

build-images: ## Build and push Docker images to local registry
	@echo "$(GREEN)Building Docker images...$(RESET)"
	@chmod +x scripts/build-images.sh && ./scripts/build-images.sh $(ENV)

validate: ## Validate deployment and run health checks
	@echo "$(GREEN)Validating deployment for $(ENV)...$(RESET)"
	@chmod +x scripts/validate-deployment.sh && ./scripts/validate-deployment.sh $(ENV)

test-rpc: ## Test RPC endpoints functionality
	@echo "$(GREEN)Testing RPC endpoints...$(RESET)"
	@chmod +x scripts/test-rpc-endpoints.sh && ./scripts/test-rpc-endpoints.sh $(ENV)

test-scaling: ## Test autoscaling functionality
	@echo "$(GREEN)Testing scaling capabilities...$(RESET)"
	@chmod +x scripts/test-scaling.sh && ./scripts/test-scaling.sh $(ENV)

load-test: ## Run performance and load tests
	@echo "$(GREEN)Running load tests...$(RESET)"
	@chmod +x scripts/load-test.sh && ./scripts/load-test.sh $(ENV)

test: test-rpc test-scaling ## Run all tests

status: ## Show deployment status
	@echo "$(GREEN)Deployment status for $(ENV):$(RESET)"
	@helmfile -e $(ENV) status || true
	@echo ""
	@kubectl get pods -A -l app.kubernetes.io/part-of=ethereum-infrastructure || true

logs: ## Show logs for Ethereum nodes
	@echo "$(GREEN)Recent logs for $(ENV):$(RESET)"
	@kubectl logs -n ethereum-$(ENV) -l app=ethereum-node --tail=50 || true

clean: ## Clean up deployment
	@echo "$(YELLOW)Cleaning up $(ENV) environment...$(RESET)"
	@read -p "Are you sure you want to delete all resources in $(ENV)? [y/N] " confirm && [ "$$confirm" = "y" ]
	helmfile -e $(ENV) destroy
	@chmod +x scripts/cleanup.sh && ./scripts/cleanup.sh $(ENV)
	@echo "$(RED)Environment $(ENV) cleaned up!$(RESET)"

reset: clean deploy-all ## Reset environment (clean + deploy)

upgrade: ## Upgrade existing deployment
	@echo "$(GREEN)Upgrading $(ENV) deployment...$(RESET)"
	helmfile -e $(ENV) diff
	helmfile -e $(ENV) apply

# Development helpers
dev-setup: setup-local build-images deploy-all validate ## Complete development setup

dashboard: ## Open Grafana dashboard
	@echo "$(GREEN)Opening Grafana dashboard...$(RESET)"
	@kubectl port-forward -n observability-$(ENV) svc/grafana 3000:80 &
	@sleep 2
	@open http://localhost:3000 || echo "Open http://localhost:3000 in your browser"

registry-ui: ## Open local registry UI
	@echo "$(GREEN)Opening registry UI...$(RESET)"
	@kubectl port-forward -n registry-$(ENV) svc/registry-ui 8080:80 &
	@sleep 2
	@open http://localhost:8080 || echo "Open http://localhost:8080 in your browser"

# Monitoring and debugging
debug: ## Debug deployment issues
	@echo "$(GREEN)Debug information for $(ENV):$(RESET)"
	@echo "$(YELLOW)Namespaces:$(RESET)"
	@kubectl get namespaces
	@echo "$(YELLOW)Pods:$(RESET)"
	@kubectl get pods -A
	@echo "$(YELLOW)Services:$(RESET)"
	@kubectl get services -A
	@echo "$(YELLOW)PVCs:$(RESET)"
	@kubectl get pvc -A

check-prerequisites: ## Check if all prerequisites are installed
	@echo "$(GREEN)Checking prerequisites...$(RESET)"
	@command -v kubectl >/dev/null 2>&1 || { echo "$(RED)kubectl is required but not installed$(RESET)"; exit 1; }
	@command -v helm >/dev/null 2>&1 || { echo "$(RED)helm is required but not installed$(RESET)"; exit 1; }
	@command -v helmfile >/dev/null 2>&1 || { echo "$(RED)helmfile is required but not installed$(RESET)"; exit 1; }
	@command -v docker >/dev/null 2>&1 || { echo "$(RED)docker is required but not installed$(RESET)"; exit 1; }
	@echo "$(GREEN)All prerequisites are installed!$(RESET)"
