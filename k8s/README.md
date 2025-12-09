# Gutendex Kubernetes Deployment

Deploy Gutendex to Kubernetes using ArgoCD with Longhorn persistent storage.

## Files

| File | Description |
|------|-------------|
| `namespace.yaml` | Creates `ocean` namespace |
| `secret.yaml` | Django SECRET_KEY |
| `pvc.yaml` | Longhorn PersistentVolumeClaim (10Gi) |
| `deployment.yaml` | Main application deployment |
| `service.yaml` | ClusterIP service |
| `cronjob.yaml` | Weekly catalog sync (Sunday 2am) |
| `ingress.yaml` | Optional ingress (edit hostname first) |

## ArgoCD Setup

Point ArgoCD to this `k8s/` folder:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: gutendex
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/your-repo/gutendex.git
    targetRevision: HEAD
    path: k8s
  destination:
    server: https://kubernetes.default.svc
    namespace: ocean
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

## Before Deploy

1. **Edit `secret.yaml`** - Change SECRET_KEY:
   ```bash
   # Generate secure key
   openssl rand -base64 50
   ```

2. **Edit `ingress.yaml`** (optional) - Set your hostname

3. **Push to Git** - ArgoCD will sync automatically

## First Run

On first deployment, the container will:
1. Run database migrations
2. Download catalog (~125MB)
3. Import 77,000+ books (~20-40 minutes)
4. Collect static files

Watch progress:
```bash
kubectl logs -f deployment/gutendex -n ocean
```

## Using Pre-built Database (FAST startup)

Build image with `data/gutendex.db.gz`:
```bash
docker build -t adamduongit/adam-gutendex:0.0.1 .
```
Container starts instantly with all 77k books!

## Verify Deployment

```bash
# Check pods
kubectl get pods -n ocean

# Check PVC (should be Bound)
kubectl get pvc -n ocean

# Check logs
kubectl logs -f deployment/gutendex -n ocean

# Port forward to test
kubectl port-forward svc/gutendex-service 8080:80 -n ocean
```

## Manual Catalog Update

```bash
kubectl create job --from=cronjob/gutendex-catalog-update manual-sync -n ocean
kubectl logs -f job/manual-sync -n ocean
```
