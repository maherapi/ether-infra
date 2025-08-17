# Ethereum Node Infrastructure

A comprehensive Kubernetes-native Ethereum node infrastructure using Helmfile for orchestration and Istio for service mesh capabilities.

## Architecture Overview

This project provides a production-ready Ethereum node infrastructure with:

- **Multiple Client Support**: Geth, Nethermind, Erigon, and Besu
- **Dual Node Types**: Sync nodes (full blockchain data) and Serve nodes (RPC endpoints)
- **Snapshot System**: Automated blockchain state snapshots for faster deployments
- **Service Mesh**: Istio integration for advanced networking and observability
- **Full Observability**: Prometheus, Grafana, Loki, and Mimir stack
- **Environment Management**: Local, staging, and production configurations

## Quick Start

```bash
# Setup local Kubernetes cluster and dependencies
make setup-local

# Deploy infrastructure components
make deploy-infrastructure

# Deploy Ethereum nodes
make deploy-ethereum

# Validate deployment
make validate
```

## Project Structure

```
ethereum-node-infra/
├── README.md
├── Makefile                           # Main orchestration commands
├── helmfile.yaml                      # Root helmfile orchestrator
├── environments/                      # Environment-specific configurations
│   ├── local.yaml
│   ├── staging.yaml
│   └── production.yaml
├── helmfiles/                         # Component-specific helmfiles
│   ├── infrastructure.helmfile.yaml
│   ├── istio.helmfile.yaml
│   ├── local-registry.helmfile.yaml
│   ├── observability.helmfile.yaml
│   └── ethereum.helmfile.yaml
├── values/                           # Value files for different components
│   ├── ethereum/
│   ├── clients/
│   └── networks/
├── charts/                           # Custom Helm charts
│   └── ethereum-infrastructure/
├── scripts/                          # Automation and setup scripts
├── docker/                           # Docker images and build files
│   ├── clients/
│   └── snapshot-builder/
├── monitoring/                       # Monitoring configurations
│   ├── dashboards/
│   └── alerts/
├── docs/                            # Documentation
└── tests/                           # Testing suite
```

## Environments

- **Local**: Single-node setup for development with minimal resources
- **Staging**: Multi-node setup for testing with moderate resources  
- **Production**: High-availability setup with full resources and security

## Components

### Infrastructure Layer
- Storage classes and persistent volumes
- Network policies and RBAC
- Istio service mesh
- Local container registry

### Observability Stack
- **Loki**: Log aggregation and querying
- **Mimir**: Long-term metrics storage
- **Grafana**: Visualization and dashboards
- **Prometheus**: Metrics collection and alerting

### Ethereum Infrastructure
- **Sync Nodes**: Full blockchain synchronization (StatefulSets)
- **Serve Nodes**: RPC endpoint serving (Deployments with HPA)
- **Snapshot Jobs**: Automated blockchain state capture (CronJobs)

## Getting Started

See [docs/getting-started.md](docs/getting-started.md) for detailed setup instructions.

## License

MIT License
