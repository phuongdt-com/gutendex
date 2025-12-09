Usage
Build & Run Docker Image
```bash
# Build the all-in-one image (takes ~5-10 minutes to populate catalog)
docker build -t gutendex:1.0.0 .

# Run locally
docker run -p 8000:8000 gutendex:1.0.0

# Visit http://localhost:8000
```

Deploy to Kubernetes with Helm
```bash
# Push image to your registry
docker tag gutendex:1.0.0 your-registry/gutendex:1.0.0
docker push your-registry/gutendex:1.0.0

# Deploy with Helm
helm install gutendex ./helm/gutendex \
  --namespace gutendex \
  --create-namespace \
  --set image.repository=your-registry/gutendex \
  --set image.tag=1.0.0
```

Quick Test
```bash
# Port forward
kubectl port-forward svc/gutendex 8080:80 -n gutendex

# Test API
curl http://localhost:8080/books
curl "http://localhost:8080/books?search=shakespeare"
```


