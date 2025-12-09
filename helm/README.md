# Gutendex Helm Chart

This Helm chart deploys the Gutendex application - a web API for serving book catalog information from Project Gutenberg.

## Features

✅ **SQLite Database** - No external database required  
✅ **Persistent Storage** - Data survives pod restarts  
✅ **Daily Sync** - CronJob updates catalog from Project Gutenberg daily  
✅ **~70,000 Books** - Full Project Gutenberg catalog  
✅ **Auto-Initialize** - First deployment automatically populates the database  

## Prerequisites

- Kubernetes 1.23+
- Helm 3.0+
- PV provisioner support (for persistence)

## Quick Start

### 1. Build the Docker Image

```bash
# Build the image (lightweight, data initialized on first run)
docker build -t gutendex:1.0.0 .

# OR build with catalog pre-populated (larger image, faster first startup)
docker build --build-arg BUILD_CATALOG=true -t gutendex:1.0.0 .

# Push to your registry
docker tag gutendex:1.0.0 your-registry/gutendex:1.0.0
docker push your-registry/gutendex:1.0.0
```

### 2. Install the Chart

```bash
# Install with daily catalog updates enabled (default)
helm install gutendex ./helm/gutendex \
  --namespace gutendex \
  --create-namespace \
  --set image.repository=your-registry/gutendex \
  --set image.tag=1.0.0 \
  --set django.secretKey="$(openssl rand -base64 50)"
```

### 3. Wait for Initialization

On first deployment, the init container will populate the database (~5-10 minutes):

```bash
# Watch initialization progress
kubectl logs -f deployment/gutendex -c init-database -n gutendex

# Check pod status
kubectl get pods -n gutendex -w
```

### 4. Access the API

```bash
# Port forward to access locally
kubectl port-forward svc/gutendex 8080:80 -n gutendex

# Visit http://localhost:8080
```

## Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of replicas (keep at 1 for SQLite) | `1` |
| `image.repository` | Image repository | `gutendex` |
| `image.tag` | Image tag | `Chart.appVersion` |
| `django.secretKey` | Django secret key | `change-me...` |
| `django.debug` | Enable debug mode | `false` |
| `django.allowedHosts` | Allowed hosts | `*` |
| `persistence.enabled` | Enable persistent storage | `true` |
| `persistence.size` | Storage size | `10Gi` |
| `catalogUpdate.enabled` | Enable daily catalog sync | `true` |
| `catalogUpdate.schedule` | Cron schedule | `0 2 * * *` |
| `ingress.enabled` | Enable ingress | `false` |

### Daily Catalog Updates

By default, the chart creates a CronJob that syncs with Project Gutenberg daily at 2am UTC:

```yaml
catalogUpdate:
  enabled: true
  schedule: "0 2 * * *"  # Daily at 2am UTC
```

To change the schedule:

```bash
helm upgrade gutendex ./helm/gutendex \
  --set catalogUpdate.schedule="0 4 * * *"  # Daily at 4am UTC
```

To manually trigger an update:

```bash
kubectl create job --from=cronjob/gutendex-catalog-update manual-update -n gutendex
```

### Persistence

Persistence is enabled by default to store the SQLite database:

```yaml
persistence:
  enabled: true
  storageClass: ""  # Use default storage class
  size: 10Gi
```

### Enable Ingress

```yaml
ingress:
  enabled: true
  className: "nginx"
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
  hosts:
    - host: gutendex.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: gutendex-tls
      hosts:
        - gutendex.example.com
```

## API Usage

Once deployed, you can access:

- **Home page**: `http://<host>/`
- **Books list**: `http://<host>/books`
- **Book detail**: `http://<host>/books/<id>`
- **Search**: `http://<host>/books?search=dickens%20great`

### Query Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `search` | Search titles and authors | `?search=shakespeare` |
| `languages` | Filter by language codes | `?languages=en,fr` |
| `topic` | Search subjects/bookshelves | `?topic=children` |
| `ids` | Get specific book IDs | `?ids=11,12,13` |
| `sort` | Sort order | `?sort=ascending` |

## Monitoring Catalog Updates

### Check CronJob Status

```bash
kubectl get cronjobs -n gutendex
kubectl get jobs -n gutendex
```

### View Update Logs

```bash
# Get the latest job
kubectl logs job/$(kubectl get jobs -n gutendex -o jsonpath='{.items[-1].metadata.name}') -n gutendex
```

### Check Last Successful Update

```bash
kubectl get cronjob gutendex-catalog-update -n gutendex -o jsonpath='{.status.lastSuccessfulTime}'
```

## Upgrading

```bash
helm upgrade gutendex ./helm/gutendex \
  --namespace gutendex \
  --set image.tag=1.1.0
```

## Uninstalling

```bash
helm uninstall gutendex --namespace gutendex
```

**Note:** This will not delete PVCs. To delete data:

```bash
kubectl delete pvc gutendex-data -n gutendex
```

## Troubleshooting

### Check Pod Status
```bash
kubectl get pods -n gutendex
kubectl describe pod <pod-name> -n gutendex
```

### View Application Logs
```bash
kubectl logs -f deployment/gutendex -n gutendex
```

### View Init Container Logs
```bash
kubectl logs deployment/gutendex -c init-database -n gutendex
```

### Access Django Shell
```bash
kubectl exec -it deployment/gutendex -n gutendex -- python manage.py shell
```

### Force Re-initialize Database
```bash
# Delete the PVC and reinstall
kubectl delete pvc gutendex-data -n gutendex
helm upgrade gutendex ./helm/gutendex --namespace gutendex
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Kubernetes Cluster                       │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────┐     ┌──────────────────────────────────┐ │
│  │   Ingress    │────▶│          Service                 │ │
│  └──────────────┘     └──────────────────────────────────┘ │
│                                    │                        │
│                                    ▼                        │
│  ┌──────────────────────────────────────────────────────┐  │
│  │                   Deployment                          │  │
│  │  ┌────────────────┐    ┌────────────────────────┐   │  │
│  │  │ Init Container │───▶│   Gutendex Container   │   │  │
│  │  │ (first run)    │    │   (gunicorn + Django)  │   │  │
│  │  └────────────────┘    └────────────────────────┘   │  │
│  └──────────────────────────────────────────────────────┘  │
│                                    │                        │
│                                    ▼                        │
│  ┌──────────────────────────────────────────────────────┐  │
│  │              PersistentVolumeClaim                    │  │
│  │  ┌─────────────────┐  ┌─────────────────────────┐   │  │
│  │  │  gutendex.db    │  │  staticfiles/           │   │  │
│  │  │  (SQLite)       │  │  catalog_files/         │   │  │
│  │  └─────────────────┘  └─────────────────────────┘   │  │
│  └──────────────────────────────────────────────────────┘  │
│                                    ▲                        │
│  ┌──────────────────────────────────────────────────────┐  │
│  │              CronJob (Daily at 2am)                   │  │
│  │  • python manage.py updatecatalog                    │  │
│  │  • python manage.py collectstatic                    │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## License

This project is licensed under the same license as the Gutendex project.
