# Ethereum Node Infrastructure Architecture

## Overview

This document describes a production-ready Ethereum blockchain infrastructure designed for scalability, reliability, and operational efficiency. The architecture addresses the fundamental challenge in blockchain infrastructure: **separating stateful sync operations from stateless RPC serving** to enable fast horizontal scaling.

## Problem Statement

Traditional Ethereum node deployments face a critical scaling bottleneck:
- **Blockchain Sync**: Requires 3-7 days, persistent storage, and stateful operations
- **RPC Traffic**: Requires fast scaling, low latency, and stateless operations
- **Challenge**: Cannot quickly scale RPC capacity due to long sync times

## Solution Architecture

### High-Level Architecture

```mermaid
graph TB
    subgraph "External Traffic"
        Client[dApp/Wallet Clients]
        LB[Load Balancer/Istio Gateway]
    end
    
    subgraph "Kubernetes Cluster"
        subgraph "Sync Layer (StatefulSets)"
            SyncGeth[Geth Sync Node]
            SyncNeth[Nethermind Sync Node]
            SyncErigon[Erigon Sync Node]
        end
        
        subgraph "Snapshot Layer"
            SnapJob[Snapshot CronJob]
            Registry[Local Registry]
        end
        
        subgraph "Serve Layer (Deployments)"
            ServeNode1[RPC Node 1]
            ServeNode2[RPC Node 2]
            ServeNodeN[RPC Node N]
            HPA[HPA Controller]
        end
        
        subgraph "Storage"
            SyncPV[Sync Persistent Volumes]
            SnapPV[Snapshot Storage]
        end
        
        subgraph "Observability"
            Prometheus[Prometheus]
            Grafana[Grafana]
            Loki[Loki]
        end
    end
    
    Client --> LB
    LB --> ServeNode1
    LB --> ServeNode2
    LB --> ServeNodeN
    
    SyncGeth --> SyncPV
    SyncNeth --> SyncPV
    SyncErigon --> SyncPV
    
    SnapJob --> SyncGeth
    SnapJob --> Registry
    Registry --> ServeNode1
    Registry --> ServeNode2
    Registry --> ServeNodeN
    
    HPA --> ServeNode1
    HPA --> ServeNode2
    HPA --> ServeNodeN
    
    ServeNode1 --> Prometheus
    SyncGeth --> Prometheus
    Prometheus --> Grafana
```


### Data Flow Architecture

```mermaid
graph LR
    subgraph "P2P Network"
        EthNet[Ethereum Network]
    end
    
    subgraph "Sync Layer"
        SN[Sync Nodes<br/>StatefulSets]
    end
    
    subgraph "Snapshot Pipeline"
        SJ[Snapshot Job<br/>CronJob]
        CI[Container Image<br/>Registry]
    end
    
    subgraph "Serve Layer"
        RN[RPC Nodes<br/>Deployments + HPA]
    end
    
    subgraph "Clients"
        DAPP[dApps]
        WALLET[Wallets]
    end
    
    EthNet -->|P2P Sync<br/>Full Blockchain| SN
    SN -->|Chaindata<br/>Every 6h| SJ
    SJ -->|Snapshot Image<br/>~2TB| CI
    CI -->|Base Image<br/>Fast Startup| RN
    RN -->|Delta Sync<br/>3-5 minutes| RN
    
    DAPP -->|RPC Requests| RN
    WALLET -->|RPC Requests| RN
```

## Component Architecture

### 1. Sync Nodes (StatefulSets)

**Purpose**: Maintain full blockchain state synchronization

```mermaid
graph TB
    subgraph "Sync Node StatefulSet"
        Pod[Sync Node Pod]
        PV[Persistent Volume<br/>2TB NVMe SSD]
        Svc[ClusterIP Service]
    end
    
    subgraph "External"
        P2P[P2P Network<br/>Port 30303]
        Mon[Monitoring<br/>Port 6060]
    end
    
    Pod --> PV
    Pod <--> P2P
    Pod --> Mon
    Svc --> Pod
    
    subgraph "Pod Spec"
        Container[Geth/Nethermind/Erigon]
        Vol[Volume Mount<br/>/data]
        Probes[Health Probes]
    end
```

**Key Characteristics:**
- **Single replica** per client type
- **Persistent storage** with high IOPS requirements
- **Long-running** with continuous P2P synchronization
- **Resource intensive** during initial sync
- **Stable network identity** for peer discovery

### 2. Serve Nodes (Deployments + HPA)

**Purpose**: Handle RPC traffic with horizontal scaling

```mermaid
graph TB
    subgraph "Serve Nodes Deployment"
        HPA[HorizontalPodAutoscaler<br/>2-20 replicas]
        Deploy[Deployment]
        Pod1[RPC Pod 1]
        Pod2[RPC Pod 2]
        PodN[RPC Pod N]
    end
    
    subgraph "Startup Process"
        Init[InitContainer<br/>Delta Sync]
        Main[Main Container<br/>RPC Server]
        Ready[Readiness Probe<br/>Sync Validation]
    end
    
    HPA --> Deploy
    Deploy --> Pod1
    Deploy --> Pod2
    Deploy --> PodN
    
    Pod1 --> Init
    Init --> Main
    Main --> Ready
```

**Scaling Behavior:**
- **Fast startup**: 3-5 minutes vs. 3-7 days
- **Stateless**: No persistent storage required
- **Auto-scaling**: Based on CPU/memory metrics
- **Delta sync**: Only catch up recent blocks on startup

### 3. Snapshot Pipeline

**Purpose**: Enable fast RPC node provisioning

```mermaid
graph LR
    subgraph "Snapshot Creation"
        Cron[CronJob<br/>Every 6 hours]
        Job[Job Pod]
        Extract[Extract Chaindata]
        Build[Build Container Image]
        Push[Push to Registry]
    end
    
    subgraph "Image Consumption"
        Pull[Pull Base Image]
        Start[Start Container]
        Delta[Delta Sync<br/>3-5 minutes]
        Serve[Ready to Serve]
    end
    
    Cron --> Job
    Job --> Extract
    Extract --> Build
    Build --> Push
    
    Push --> Pull
    Pull --> Start
    Start --> Delta
    Delta --> Serve
```

## Infrastructure as Code Structure

```mermaid
graph TB
    subgraph "Helmfile Orchestration"
        Root[helmfile.yaml<br/>Root Orchestrator]
        Infra[infrastructure.helmfile.yaml]
        Obs[observability.helmfile.yaml]
        Eth[ethereum.helmfile.yaml]
    end
    
    subgraph "Custom Charts"
        EthChart[ethereum-infrastructure/<br/>Custom Chart]
        MonChart[Third-party Charts<br/>Prometheus, Grafana, Loki]
    end
    
    subgraph "Configuration"
        Values[values/<br/>Environment Configs]
        Envs[environments/<br/>local.yaml, staging.yaml]
    end
    
    Root --> Infra
    Root --> Obs
    Root --> Eth
    
    Infra --> MonChart
    Obs --> MonChart
    Eth --> EthChart
    
    EthChart --> Values
    MonChart --> Values
    Values --> Envs
```

## Deployment Strategy

### Phase 1: Infrastructure Bootstrap
1. **Kind cluster** with 3 worker nodes
2. **MetalLB** for LoadBalancer services
3. **Local registry** for container images
4. **Storage classes** and persistent volumes

### Phase 2: Observability Stack
1. **Prometheus** for metrics collection
2. **Grafana** for dashboards and visualization
3. **Loki** for log aggregation
4. **Service monitors** for Ethereum-specific metrics

### Phase 3: Ethereum Infrastructure
1. **Sync nodes** deployment (StatefulSets)
2. **Initial sync** (3-7 days for full sync)
3. **Snapshot jobs** setup and first execution
4. **Serve nodes** deployment with HPA

### Phase 4: Production Optimization
1. **Performance tuning** based on metrics
2. **Alert rules** for operational monitoring
3. **Backup strategies** for disaster recovery
4. **Security hardening** and network policies

## Scaling Characteristics

### Sync Node Scaling
- **Vertical scaling**: Increase CPU/memory for faster sync
- **Client diversity**: Multiple implementations for resilience
- **Storage scaling**: Automatic volume expansion capabilities

### RPC Node Scaling
- **Horizontal scaling**: 2-20 replicas based on traffic
- **Fast provisioning**: 3-5 minute startup time
- **Load distribution**: Even traffic distribution across pods
- **Auto-scaling metrics**: CPU (70%) and Memory (80%) thresholds

## Operational Considerations

### Monitoring Strategy
- **Node health**: Sync status, peer count, block height
- **Performance**: RPC latency, throughput, error rates
- **Infrastructure**: Resource utilization, storage growth
- **Business**: Request patterns, client diversity

### Backup and Recovery
- **Snapshot strategy**: Container images for fast recovery
- **Persistent volume backups**: Daily snapshots to object storage
- **Multi-region**: Geographic distribution for disaster recovery

### Security Considerations
- **Network policies**: Segmented network access
- **RBAC**: Least privilege access controls  
- **TLS encryption**: All inter-service communication
- **Resource limits**: Prevent resource exhaustion attacks

## Production Readiness Checklist

- [ ] **Multi-client deployment** for network resilience
- [ ] **Monitoring and alerting** for all components
- [ ] **Backup and disaster recovery** procedures
- [ ] **Security hardening** and network segmentation
- [ ] **Performance testing** and capacity planning
- [ ] **Runbook documentation** for operations team
- [ ] **Incident response** procedures
- [ ] **Cost optimization** strategies

## Conclusion

This architecture addresses the fundamental scalability challenges of blockchain infrastructure by:

1. **Separating concerns** between sync and serve operations
2. **Enabling fast scaling** through snapshot-based provisioning
3. **Maintaining reliability** through client diversity and monitoring
4. **Supporting operations** with comprehensive observability

The design reflects production patterns used by major blockchain infrastructure providers while remaining deployable on local Kubernetes clusters for development and testing.