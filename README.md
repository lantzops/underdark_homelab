# Underdark Cluster Monitoring Stack

Kubernetes monitoring stack for a "the hard way" cluster. Deploys metrics-server,
Prometheus, Node Exporter, kube-state-metrics, and Grafana with pre-configured
datasources and a starter dashboard.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                      Grafana :30030                     │
│                  (Dashboards & Visualization)           │
│                           │                             │
│                     PromQL queries                      │
│                           │                             │
│                    Prometheus :30090                     │
│                  (Metrics Storage & Query)               │
│                    ┌──────┼──────┐                      │
│                    │      │      │                      │
│              ┌─────┴──┐ ┌─┴───┐ ┌┴──────────────┐      │
│              │  Node   │ │kube-│ │  K8s API /     │     │
│              │Exporter │ │state│ │  cAdvisor /    │     │
│              │(per     │ │     │ │  Kubelet       │     │
│              │ node)   │ │     │ │  metrics       │     │
│              └─────────┘ └─────┘ └───────────────┘      │
│                                                         │
│         metrics-server (enables kubectl top)            │
└─────────────────────────────────────────────────────────┘
```

## Components

| Component | Purpose | Port |
|-----------|---------|------|
| **metrics-server** | Enables `kubectl top`, feeds HPA | Internal only |
| **Prometheus** | Scrapes & stores time-series metrics | NodePort 30090 |
| **Node Exporter** | Host-level metrics (CPU, mem, disk, net) | 9100 per node |
| **kube-state-metrics** | K8s object state (pod status, replicas) | 8080 internal |
| **Grafana** | Dashboards and visualization | NodePort 30030 |

## Quick Deploy

```bash
chmod +x deploy.sh
./deploy.sh
```

Or manually in order:

```bash
kubectl apply -f metrics-server/metrics-server.yaml
kubectl apply -f monitoring/00-namespace.yaml
kubectl apply -f monitoring/01-prometheus.yaml
kubectl apply -f monitoring/02-node-exporter.yaml
kubectl apply -f monitoring/03-kube-state-metrics.yaml
kubectl apply -f monitoring/04-grafana.yaml
```

## Access

- **Prometheus**: `http://<node-ip>:30090`
- **Grafana**: `http://<node-ip>:30030` (admin / admin)

## Verify

```bash
# Check all monitoring pods
kubectl get pods -n monitoring -o wide

# Check metrics-server
kubectl top nodes
kubectl top pods -A

# Check Prometheus targets (should all be UP)
# Visit http://<node-ip>:30090/targets
```

## Recommended Grafana Dashboards

Import via: Dashboards → New → Import → Enter ID → Load

| ID | Dashboard | Shows |
|----|-----------|-------|
| **1860** | Node Exporter Full | Detailed per-node hardware metrics |
| **15760** | K8s Cluster Overview | Cluster-wide resource summary |
| **13332** | kube-state-metrics v2 | Pod/deployment/job state |

## Storage Notes

The PVCs for Prometheus (5Gi) and Grafana (2Gi) require either:

1. A **dynamic StorageClass** provisioner (like local-path-provisioner)
2. **Manually created PersistentVolumes**
3. **Switch to emptyDir** (data lost on restart — see comments in manifests)

If you don't have a storage provisioner yet, the easiest option is Rancher's
local-path-provisioner:

```bash
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.30/deploy/local-path-storage.yaml
```

## Troubleshooting

**metrics-server pod won't start / CrashLoopBackOff**
- Check logs: `kubectl logs -n kube-system -l k8s-app=metrics-server`
- Ensure `--kubelet-insecure-tls` is set (required for "the hard way" clusters)
- Verify kubelets are accessible on port 10250

**Prometheus targets showing DOWN**
- Check: `http://<node-ip>:30090/targets`
- API server target: ensure the Prometheus ServiceAccount token is valid
- Node/cAdvisor: check kubelet is serving metrics on 10250

**PVC stuck in Pending**
- `kubectl get pvc -n monitoring` — if Pending, no StorageClass/PV available
- Either install local-path-provisioner (see above) or switch to emptyDir

**Grafana shows "No data"**
- Wait 2-3 minutes for Prometheus to collect initial data
- Check Grafana datasource: Settings → Data Sources → Prometheus → Test
- Verify Prometheus URL: `http://prometheus.monitoring.svc.cluster.local:9090`

## Teardown

```bash
kubectl delete -f monitoring/04-grafana.yaml
kubectl delete -f monitoring/03-kube-state-metrics.yaml
kubectl delete -f monitoring/02-node-exporter.yaml
kubectl delete -f monitoring/01-prometheus.yaml
kubectl delete -f monitoring/00-namespace.yaml
kubectl delete -f metrics-server/metrics-server.yaml
```
