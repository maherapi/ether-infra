# Simple Makefile for Observability Stack
.PHONY: install-crds help

NAMESPACE := monitoring

help: ## Show available commands
	@echo "Available commands:"
	@echo "  install-crds  - Install Prometheus Operator CRDs"
	@echo "  help         - Show this help"

install-crds: ## Install Prometheus Operator CRDs
	@echo "Creating namespace..."
	@kubectl create namespace $(NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	@echo "Installing Prometheus Operator CRDs..."
	@curl -sL https://github.com/prometheus-operator/prometheus-operator/releases/download/v0.70.0/stripped-down-crds.yaml | kubectl apply -f -
	@echo "Waiting for CRDs to be ready..."
	@kubectl wait --for=condition=established --timeout=60s crd/servicemonitors.monitoring.coreos.com
	@kubectl wait --for=condition=established --timeout=60s crd/prometheuses.monitoring.coreos.com
	@echo "CRDs installed successfully!"
	@kubectl get crd | grep monitoring.coreos.com