# Gutendex Helm Chart (All-in-One SQLite Version)

This Helm chart deploys the Gutendex application - a web API for serving book catalog information from Project Gutenberg.

## Features

✅ **All-in-One Image** - Database, catalog data, and static files are all pre-built into the Docker image  
✅ **Zero Configuration** - Just run and it works  
✅ **~70,000 Books** - Full Project Gutenberg catalog pre-loaded  
✅ **SQLite Database** - No external database required  

## Prerequisites

- Kubernetes 1.23+
- Helm 3.0+

## Quick Start

### 1. Build the Docker Image

```bash
# Build the all-in-one image (this takes several minutes to populate the catalog)
docker build -t gutendex:1.0.0 .

# Push to your registry
docker tag gutendex:1.0.0 your-registry/gutendex:1.0.0
docker push your-registry/gutendex:1.0.0
```

### 2. Install the Chart

```bash
# Install with default settings
helm install gutendex ./helm/gutendex \
  --namespace gutendex \
  --create-namespace \
  --set image.repository=your-registry/gutendex \
  --set image.tag=1.0.0

# Or with a custom secret key (recommended for production)
helm install gutendex ./helm/gutendex \
  --namespace gutendex \
  --create-namespace \
  --set image.repository=your-registry/gutendex \
  --set image.tag=1.0.0 \
  --set django.secretKey="$(openssl rand -base64 50)"
```

### 3. Access the API

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
| `django.workers` | Gunicorn workers | `4` |
| `service.type` | Service type | `ClusterIP` |
| `ingress.enabled` | Enable ingress | `false` |

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

### Use NodePort for Local Testing

```bash
helm install gutendex ./helm/gutendex \
  --set service.type=NodePort \
  --set image.repository=gutendex \
  --set image.tag=1.0.0
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

## Limitations

- **Single Replica Only**: SQLite doesn't support concurrent writes, so keep `replicaCount: 1`
- **Read-Only Data**: The book catalog is baked into the image; to update, rebuild the image
- **No Persistence**: If the pod restarts, the database resets to the image state

## Updating the Book Catalog

To update the catalog with the latest books from Project Gutenberg:

```bash
# Rebuild the Docker image (this will download fresh catalog data)
docker build -t gutendex:1.1.0 .
docker push your-registry/gutendex:1.1.0

# Update the deployment
helm upgrade gutendex ./helm/gutendex \
  --namespace gutendex \
  --set image.tag=1.1.0
```

## Troubleshooting

### Check Pod Status
```bash
kubectl get pods -n gutendex
kubectl describe pod <pod-name> -n gutendex
```

### View Logs
```bash
kubectl logs -f deployment/gutendex -n gutendex
```

### Access Django Shell
```bash
kubectl exec -it deployment/gutendex -n gutendex -- python manage.py shell
```

## License

This project is licensed under the same license as the Gutendex project.
