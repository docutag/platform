# Flagger Setup Guide

Complete guide for setting up Flagger progressive delivery for DocuTag production deployments.

## What is Flagger?

Flagger is a progressive delivery tool that automates the promotion of canary deployments using:
- **Traffic routing** via Traefik (already integrated)
- **Metrics analysis** from Prometheus (already deployed)
- **Automated rollback** on failure
- **Webhook support** for Helm tests

## Prerequisites

### Required (Already Have)
- ✅ Kubernetes cluster with admin access
- ✅ Traefik ingress controller installed
- ✅ Prometheus collecting metrics from services
- ✅ Services exposing `/metrics` endpoints

### Required (Need to Install)
- Flagger controller
- Flagger loadtester (for Helm test webhooks)

## Installation

### Automated Installation via Pulumi (Recommended)

Flagger is automatically deployed when creating the cluster via Pulumi:

```bash
# Enable Flagger in production stack
cd infra
pulumi config set enableFlagger true --stack production

# Deploy cluster with Flagger included
pulumi up

# Verify Flagger is running
kubectl -n flagger-system get pods
```

**Features**:
- ✅ Declarative infrastructure-as-code
- ✅ Automatic deployment on cluster creation
- ✅ Version controlled configuration
- ✅ Integrated with cluster lifecycle
- ✅ Consistent across all environments
- ✅ State managed by Pulumi

**Configuration**:

Flagger deployment is configured in `infra/main.go` and can be customized via Pulumi config:

```bash
# Enable/disable Flagger
pulumi config set enableFlagger true

# Custom Prometheus address (optional)
pulumi config set prometheusAddress "http://custom-prometheus:9090"
```

**Default values**:
- Namespace: `flagger-system`
- Prometheus: `http://docutag-prometheus.docutag:9090`
- Mesh provider: `traefik`
- Controller version: `1.37.0`
- Loadtester version: `0.32.0`

---

### Manual Installation

For adding Flagger to existing clusters or custom configurations:

#### 1. Install Flagger Controller

```bash
# Add Flagger Helm repository
helm repo add flagger https://flagger.app
helm repo update

# Install Flagger with Traefik provider
helm upgrade -i flagger flagger/flagger \
  --namespace flagger-system \
  --create-namespace \
  --set prometheus.install=false \
  --set meshProvider=traefik \
  --set metricsServer=http://docutag-prometheus.docutag:9090

# Verify installation
kubectl -n flagger-system rollout status deployment/flagger
kubectl -n flagger-system get pods
```

**Expected output**:
```
NAME                       READY   STATUS    RESTARTS   AGE
flagger-xxx-yyy            1/1     Running   0          30s
```

#### 2. Install Flagger Loadtester

The loadtester provides webhook support for running Helm tests:

```bash
helm upgrade -i flagger-loadtester flagger/loadtester \
  --namespace flagger-system

# Verify
kubectl -n flagger-system get pods
```

**Expected output**:
```
NAME                                 READY   STATUS    RESTARTS   AGE
flagger-xxx-yyy                      1/1     Running   0          2m
flagger-loadtester-zzz-www           1/1     Running   0          30s
```

#### 3. Install kubectl Plugin (Optional)

The kubectl plugin provides CLI control over canaries:

```bash
# Linux
curl -LO https://github.com/fluxcd/flagger/releases/latest/download/flagger_linux_amd64
chmod +x flagger_linux_amd64
sudo mv flagger_linux_amd64 /usr/local/bin/kubectl-flagger

# macOS (Intel)
curl -LO https://github.com/fluxcd/flagger/releases/latest/download/flagger_darwin_amd64
chmod +x flagger_darwin_amd64
sudo mv flagger_darwin_amd64 /usr/local/bin/kubectl-flagger

# macOS (Apple Silicon)
curl -LO https://github.com/fluxcd/flagger/releases/latest/download/flagger_darwin_arm64
chmod +x flagger_darwin_arm64
sudo mv flagger_darwin_arm64 /usr/local/bin/kubectl-flagger

# Verify
kubectl flagger version
```

## Configuration

Flagger is already configured in the Helm chart! Just enable it:

### Production Configuration

**File: `chart/values-production.yaml`**

```yaml
flagger:
  enabled: true  # ← Set to true
  strategy: canary  # or "blueGreen"

  analysis:
    interval: 1m       # Check metrics every minute
    threshold: 5       # Rollback after 5 failed checks
    stepWeight: 10     # Increase traffic by 10% per step
    iterations: 10     # Total rollout time: 10 minutes

  metrics:
    requestSuccessRate:
      enabled: true
      threshold: 99    # 99% success rate required

    requestDuration:
      enabled: true
      threshold: 500   # p99 latency < 500ms

  webhooks:
    helmTests:
      enabled: true
      timeout: 3m
```

## Deployment Workflow

### With Flagger Enabled

```bash
# 1. Create release (existing workflow)
# Merging staging → main triggers release workflow
# Builds: ghcr.io/docutag/docutag-*:1.1.0

# 2. Update Pulumi with new version
cd infra
pulumi config set imageVersion 1.1.0 --stack production
pulumi up --stack production

# 3. Flagger automatically handles progressive rollout
# No manual intervention needed!

# 4. Monitor rollout progress
kubectl get canaries -n docutag -w

# Output:
# NAME                 STATUS      WEIGHT   LASTTRANSITIONTIME
# docutag-controller   Progressing 30       2025-11-01T22:30:00Z
# docutag-web          Progressing 30       2025-11-01T22:30:00Z
# docutag-scraper      Progressing 30       2025-11-01T22:30:00Z
```

### Rollout Timeline (Canary Strategy)

```
Time    Traffic Distribution                 Action
----    --------------------                 ------
T+0     Old: 100%, New: 0%                  Deploy new version
T+1     Old: 100%, New: 0%                  Run Helm tests
T+2     Old:  90%, New: 10%                 Check metrics
T+3     Old:  80%, New: 20%                 Check metrics
T+4     Old:  70%, New: 30%                 Check metrics
T+5     Old:  60%, New: 40%                 Check metrics
T+6     Old:  50%, New: 50%                 Check metrics
T+7     Old:  40%, New: 60%                 Check metrics
T+8     Old:  30%, New: 70%                 Check metrics
T+9     Old:  20%, New: 80%                 Check metrics
T+10    Old:  10%, New: 90%                 Check metrics
T+11    Old:   0%, New: 100%                Promote (complete)
T+12    Old scaled down                     Cleanup

Total: ~12 minutes from deployment to completion
```

### Blue-Green Strategy

Change to instant switch:

```yaml
flagger:
  strategy: blueGreen
```

```
Time    Traffic Distribution                 Action
----    --------------------                 ------
T+0     Old: 100%, New: 0%                  Deploy new version
T+1     Old: 100%, New: 0%                  Run Helm tests + metrics
T+2     Old: 100%, New: 0%                  Final validation
T+3     Old:   0%, New: 100%                Instant switch!
T+4     Old scaled down                     Cleanup

Total: ~4 minutes from deployment to completion
```

## Monitoring Deployments

### Watch Canary Status

```bash
# List all canaries
kubectl get canaries -n docutag

# Watch specific canary in real-time
kubectl get canary docutag-controller -n docutag -w

# Detailed status
kubectl describe canary docutag-controller -n docutag
```

### Canary Status Values

| Status | Meaning |
|--------|---------|
| `Initializing` | Creating canary resources |
| `Initialized` | Ready for deployment |
| `Progressing` | Traffic shifting in progress |
| `Promoting` | Finalizing promotion to primary |
| `Finalising` | Cleaning up old version |
| `Succeeded` | Deployment successful |
| `Failed` | Rolled back due to failures |

### View Events

```bash
kubectl describe canary docutag-controller -n docutag | grep Events -A 20
```

**Example output**:
```
Events:
  Type    Reason  Age   Message
  ----    ------  ----  -------
  Normal  Synced  5m    New revision detected! Scaling up docutag-controller.docutag
  Normal  Synced  4m    Starting canary analysis for docutag-controller.docutag
  Normal  Synced  4m    Pre-rollout check acceptance-test passed
  Normal  Synced  3m    Advance docutag-controller.docutag canary weight 10
  Normal  Synced  2m    Advance docutag-controller.docutag canary weight 20
  Normal  Synced  1m    Advance docutag-controller.docutag canary weight 30
  Normal  Synced  30s   Copying docutag-controller.docutag template spec to docutag-controller-primary.docutag
  Normal  Synced  20s   Promotion completed! Scaling down docutag-controller.docutag
```

### Check Flagger Logs

```bash
# Stream Flagger controller logs
kubectl -n flagger-system logs deployment/flagger -f

# Filter for specific canary
kubectl -n flagger-system logs deployment/flagger -f | grep docutag-controller
```

## Manual Control

### Pause Rollout

```bash
# Pause canary analysis
kubectl -n docutag patch canary/docutag-controller -p '{"spec":{"skipAnalysis":true}}'
```

### Resume Rollout

```bash
# Resume canary analysis
kubectl -n docutag patch canary/docutag-controller -p '{"spec":{"skipAnalysis":false}}'
```

### Manual Promotion

```bash
# Promote canary immediately (skip remaining iterations)
kubectl flagger promote docutag-controller -n docutag
```

### Manual Rollback

```bash
# Abort canary and rollback to primary
kubectl flagger rollback docutag-controller -n docutag
```

## Troubleshooting

### Canary Stuck in Initializing

**Problem**: Canary stays in "Initializing" status

**Check**:
```bash
kubectl describe canary docutag-controller -n docutag
kubectl -n flagger-system logs deployment/flagger | grep docutag-controller
```

**Common causes**:
- Deployment not found (check targetRef)
- Service misconfigured
- Flagger controller not running

### Automatic Rollback Occurs

**Problem**: Canary automatically rolls back

**Check events**:
```bash
kubectl describe canary docutag-controller -n docutag | grep -A 5 "Rolling back"
```

**Common causes**:
1. **Metrics below threshold**
   ```
   Message: Halt advancement request-success-rate 97.5% < 99%
   ```
   - Check Prometheus for actual metrics
   - Lower threshold if too strict

2. **Prometheus unreachable**
   ```
   Message: metrics server http://prometheus:9090 unreachable
   ```
   - Verify Prometheus is running
   - Check prometheus.address in values.yaml

3. **Helm tests failed**
   ```
   Message: Pre-rollout check helm-test failed
   ```
   - Run tests manually: `helm test docutag -n docutag --logs`
   - Fix failing tests

### Metrics Not Available

**Problem**: Flagger reports no metrics

**Check**:
```bash
# Test Prometheus query
kubectl run -it --rm prometheus-test --image=curlimages/curl --restart=Never -- \
  curl -s 'http://docutag-prometheus.docutag:9090/api/v1/query?query=up'

# Check service metrics
kubectl run -it --rm metrics-test --image=curlimages/curl --restart=Never -- \
  curl -s http://docutag-controller.docutag:8080/metrics
```

**Common causes**:
- Prometheus not scraping services
- Metrics not matching label selectors
- Services not exposing metrics

### Loadtester Webhook Fails

**Problem**: Helm tests webhook doesn't work

**Check loadtester**:
```bash
kubectl -n flagger-system logs deployment/flagger-loadtester
kubectl -n flagger-system get svc flagger-loadtester
```

**Test webhook manually**:
```bash
kubectl run -it --rm webhook-test --image=curlimages/curl --restart=Never -- \
  curl -X POST http://flagger-loadtester.flagger-system/ \
  -d '{"type":"bash","cmd":"echo test"}'
```

## Best Practices

### 1. Start with Canary Strategy

Gradual rollout catches issues early:
- 10% traffic sees issues first
- Automatic rollback limits impact
- More confidence before full rollout

### 2. Tune Thresholds for Your SLOs

Adjust based on actual service performance:

```yaml
metrics:
  requestSuccessRate:
    threshold: 99.5  # If normally > 99.9%

  requestDuration:
    threshold: 200   # If normally < 100ms
```

### 3. Longer Intervals for Critical Services

Give more time to detect issues:

```yaml
analysis:
  interval: 2m      # Check every 2 minutes
  iterations: 10    # 20 minutes total
```

### 4. Enable Slack Notifications

Stay informed of deployments:

```yaml
alerts:
  slack:
    enabled: true
    webhookUrl: "https://hooks.slack.com/services/..."
    channel: "#production-deploys"
```

### 5. Test in Non-Production First

Before enabling in production:
1. Install Flagger in dev cluster
2. Test with low-traffic service
3. Verify metrics collection
4. Practice rollback scenarios

### 6. Monitor First Deployments

Watch the first few deployments closely:
```bash
# Terminal 1: Watch canary status
watch -n 2 kubectl get canaries -n docutag

# Terminal 2: Stream Flagger logs
kubectl -n flagger-system logs deployment/flagger -f

# Terminal 3: Watch Prometheus metrics
kubectl -n docutag port-forward svc/docutag-prometheus 9090:9090
# Open: http://localhost:9090
```

## Configuration Examples

### Conservative (Low-Risk)

For critical production services:

```yaml
flagger:
  enabled: true
  strategy: canary
  analysis:
    interval: 2m      # Slower rollout
    threshold: 3      # Stricter (rollback after 3 failures)
    stepWeight: 5     # Smaller increments
    iterations: 20    # 40 minutes total
  metrics:
    requestSuccessRate:
      threshold: 99.9 # Very high bar
```

### Aggressive (Fast Feedback)

For less critical services:

```yaml
flagger:
  enabled: true
  strategy: canary
  analysis:
    interval: 30s     # Faster checks
    threshold: 10     # More tolerant
    stepWeight: 25    # Larger jumps
    iterations: 4     # 2 minutes total
  metrics:
    requestSuccessRate:
      threshold: 95   # Lower bar
```

### Blue-Green (Instant Switch)

For validated releases:

```yaml
flagger:
  enabled: true
  strategy: blueGreen
  analysis:
    interval: 1m
    threshold: 5
  # stepWeight/iterations ignored in blue-green
```

## Slack Integration

### Setup Slack Webhook

1. Go to https://api.slack.com/apps
2. Create New App → From Scratch
3. Add "Incoming Webhooks" feature
4. Create webhook for your channel
5. Copy webhook URL

### Configure in Helm

```yaml
flagger:
  alerts:
    slack:
      enabled: true
      webhookUrl: "https://hooks.slack.com/services/T00/B00/XXXX"
      channel: "#deployments"
```

### Notification Format

Flagger sends messages like:
```
🚀 Canary deployment docutag-controller.docutag initialized
⚠️ Canary deployment docutag-controller.docutag is waiting for approval
✅ Canary deployment docutag-controller.docutag promoted
❌ Canary deployment docutag-controller.docutag failed
```

## Uninstalling Flagger

If you need to remove Flagger:

```bash
# Disable in Helm chart first
# Set flagger.enabled: false in values-production.yaml
helm upgrade docutag ./chart -n docutag -f ./chart/values-production.yaml

# Wait for Canary resources to be removed
kubectl get canaries -n docutag

# Uninstall Flagger
helm uninstall flagger-loadtester -n flagger-system
helm uninstall flagger -n flagger-system

# Delete namespace
kubectl delete namespace flagger-system
```

Deployments revert to standard rolling updates.

## Next Steps

1. ✅ Install Flagger controller
2. ✅ Install loadtester
3. ✅ Enable `flagger.enabled: true` in values-production.yaml
4. ✅ Deploy with `pulumi up`
5. ✅ Monitor first canary deployment
6. ✅ Verify automatic rollback works (simulate failure)
7. ✅ Configure Slack notifications
8. ✅ Document team runbook

## Related Documentation

- [Blue-Green Deployment Strategy](./BLUE-GREEN-DEPLOYMENT.md)
- [Flagger Templates](../chart/templates/flagger/README.md)
- [Helm Chart Tests](../chart/templates/tests/README.md)
- [Official Flagger Docs](https://docs.flagger.app/)
- [Flagger + Traefik Guide](https://docs.flagger.app/tutorials/traefik-progressive-delivery)
