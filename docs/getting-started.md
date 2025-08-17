# Getting Started with Ethereum Node Infrastructure

This guide will help you deploy and manage the Ethereum node infrastructure on Kubernetes using Helmfile.

## Prerequisites

Before you begin, ensure you have the following tools installed:

- **Docker** (for building images and local registry)
- **kubectl** (Kubernetes command-line tool)
- **helm** (Kubernetes package manager)
- **helmfile** (Declarative Helm deployment tool)
- **jq** (JSON processor for scripts)

You can install all dependencies by running:

```bash
make setup-dependencies
```

## Quick Start

### 1. Setup Local Environment

For local development, create a local Kubernetes cluster:

```bash
# Create a local cluster (using kind by default)
make setup-local

# Verify cluster is ready
kubectl cluster-info
kubectl get nodes
```

### 2. Build Docker Images

Build the custom Docker images for Ethereum clients:

```bash
# Build all images and push to local registry
make build-images

# Verify images are built
docker images | grep ethereum
```

### 3. Deploy Infrastructure

Deploy the complete infrastructure stack:

```bash
# Deploy infrastructure components (storage, networking, observability)
make deploy-infrastructure

# Deploy Ethereum nodes
make deploy-ethereum

# Verify deployment
make validate
```

### 4. Access Services

Once deployed, you can access various services:

```bash
# Open Grafana dashboard
make dashboard

# Open registry UI
make registry-ui

# Port-forward to RPC endpoint
kubectl port-forward -n ethereum-local svc/ethereum-infrastructure-serve 8545:8545
```

## Environment Management

The infrastructure supports three environments:

### Local Development
- Single node setup
- Minimal resources
- Sepolia testnet
- Local storage
- Simplified monitoring

```bash
# Deploy to local environment
make deploy-all ENV=local
```

### Staging
- Multi-node setup
- Moderate resources
- Multiple Ethereum clients
- Full observability stack
- Network policies enabled

```bash
# Deploy to staging environment
make deploy-all ENV=staging
```

### Production
- High-availability setup
- Full resources
- All Ethereum clients
- Comprehensive security
- Advanced monitoring

```bash
# Deploy to production environment
make deploy-all ENV=production
```

## Architecture Overview

### Components

1. **Infrastructure Layer**
   - Storage classes and persistent volumes
   - Network policies and RBAC
   - Istio service mesh
   - Local container registry

2. **Observability Stack**
   - Prometheus (metrics collection)
   - Grafana (visualization)
   - Loki (log aggregation)
   - Mimir (long-term storage)

3. **Ethereum Infrastructure**
   - **Sync Nodes**: Full blockchain synchronization (StatefulSets)
   - **Serve Nodes**: RPC endpoint serving (Deployments with HPA)
   - **Snapshot Jobs**: Automated blockchain state capture (CronJobs)

### Ethereum Clients

The infrastructure supports multiple Ethereum clients:

- **Geth**: Go Ethereum implementation (default)
- **Nethermind**: .NET Ethereum client
- **Erigon**: Efficient Ethereum client
- **Besu**: Java-based Ethereum client

### Networking

- **Istio Service Mesh**: Advanced traffic management and security
- **Load Balancing**: Intelligent routing to healthy nodes
- **Circuit Breaking**: Automatic failure handling
- **Observability**: Distributed tracing and metrics

## Configuration

### Environment Variables

Key environment variables you can set:

```bash
# Cluster configuration
export CLUSTER_NAME="ethereum-local"
export K8S_VERSION="v1.28.0"

# Registry configuration
export REGISTRY_URL="localhost:5000"

# Build configuration
export BUILD_PARALLEL="true"
export FORCE_REBUILD="false"
```

### Customizing Values

You can customize the deployment by editing values files:

- `environments/local.yaml` - Local environment configuration
- `environments/staging.yaml` - Staging environment configuration
- `environments/production.yaml` - Production environment configuration
- `values/ethereum/local.yaml` - Ethereum-specific local configuration
- `values/networks/sepolia.yaml` - Sepolia network configuration

### Client Configuration

Enable/disable specific Ethereum clients:

```yaml
# In environments/{env}.yaml
ethereum:
  clients:
    geth:
      enabled: true
      replicas: 2
    nethermind:
      enabled: true
      replicas: 1
    erigon:
      enabled: false
    besu:
      enabled: false
```

## Operations

### Monitoring

Access monitoring dashboards:

```bash
# Grafana dashboard
kubectl port-forward -n observability-local svc/kube-prometheus-stack-grafana 3000:80
# Open http://localhost:3000 (admin/admin)

# Prometheus
kubectl port-forward -n observability-local svc/kube-prometheus-stack-prometheus 9090:9090
# Open http://localhost:9090
```

### Logs

View logs from different components:

```bash
# Ethereum node logs
kubectl logs -n ethereum-local -l app.kubernetes.io/component=sync-node

# Serve node logs
kubectl logs -n ethereum-local -l app.kubernetes.io/component=serve-node

# Snapshot job logs
kubectl logs -n ethereum-local -l app.kubernetes.io/component=snapshot-job
```

### Scaling

Scale serve nodes manually or via HPA:

```bash
# Manual scaling
kubectl scale deployment -n ethereum-local ethereum-infrastructure-serve --replicas=5

# Check HPA status
kubectl get hpa -n ethereum-local
```

### Testing RPC Endpoints

Test Ethereum RPC functionality:

```bash
# Test basic connectivity
make test-rpc

# Manual RPC calls
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  http://localhost:8545

# Test WebSocket endpoint
wscat -c ws://localhost:8546
```

## Troubleshooting

### Common Issues

1. **Pods stuck in Pending state**
   ```bash
   kubectl describe pods -n ethereum-local
   # Check for resource constraints or storage issues
   ```

2. **Sync nodes not syncing**
   ```bash
   # Check peer connectivity
   kubectl logs -n ethereum-local -l client=geth
   
   # Verify network policies aren't blocking P2P traffic
   kubectl get networkpolicy -n ethereum-local
   ```

3. **RPC endpoints returning errors**
   ```bash
   # Check serve node status
   kubectl get pods -n ethereum-local -l app.kubernetes.io/component=serve-node
   
   # Verify load balancer configuration
   kubectl describe svc -n ethereum-local ethereum-infrastructure-serve
   ```

4. **Monitoring not working**
   ```bash
   # Check Prometheus targets
   kubectl port-forward -n observability-local svc/kube-prometheus-stack-prometheus 9090:9090
   # Visit http://localhost:9090/targets
   ```

### Debug Commands

Useful commands for debugging:

```bash
# Check overall cluster health
make debug

# Validate deployment
make validate ENV=local

# Check resource usage
kubectl top nodes
kubectl top pods -A

# Inspect Istio configuration
istioctl proxy-config cluster -n ethereum-local ethereum-infrastructure-serve-xxx
```

### Getting Help

- **Documentation**: Check the `docs/` directory for detailed guides
- **Runbooks**: See `docs/runbooks/` for operational procedures
- **Issues**: Create GitHub issues for bugs or feature requests
- **Logs**: Always include relevant logs when reporting issues

## Next Steps

1. **Explore Monitoring**: Set up custom dashboards in Grafana
2. **Performance Tuning**: Optimize resource allocation for your workload
3. **Security**: Review and enhance security policies
4. **Backup**: Set up automated backup procedures
5. **CI/CD**: Integrate with your deployment pipeline

For more detailed information, see the documentation in the `docs/` directory.
