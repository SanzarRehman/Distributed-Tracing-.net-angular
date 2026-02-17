# Docker Deployment Guide

Production deployment using Docker and Docker Compose.

---

## Prerequisites

- Docker 20.10+
- Docker Compose 2.0+
- Domain name (for production)
- SSL certificate (optional, for HTTPS)

---

## 1. Build Images

### Build .NET API

```bash
cd PathfinderApi
docker build -t pathfinder-api:latest .
```

### Build Angular UI

```bash
cd pathfinder-ui
docker build -t pathfinder-ui:latest .
```

---

## 2. Push to Registry (Optional)

If deploying to multiple hosts or using a registry:

```bash
# Tag images
docker tag pathfinder-api:latest <your-registry>/pathfinder-api:latest
docker tag pathfinder-ui:latest <your-registry>/pathfinder-ui:latest

# Push to registry (Docker Hub, ECR, ACR, etc.)
docker push <your-registry>/pathfinder-api:latest
docker push <your-registry>/pathfinder-ui:latest
```

---

## 3. Deploy with Docker Compose

```bash
# Start all services
docker compose -f docker-compose.prod.yml up -d

# View logs
docker compose -f docker-compose.prod.yml logs -f

# Check status
docker compose -f docker-compose.prod.yml ps

# Stop services
docker compose -f docker-compose.prod.yml down
```

---

## 4. Verify Deployment

| Service | URL | Expected Result |
|---------|-----|-----------------|
| **Angular UI** | http://localhost | Dashboard loads |
| **API Health** | http://localhost:8080/api/health | `{ "status": "healthy" }` |
| **Jaeger UI** | http://localhost:16686 | Jaeger dashboard |

---

## 5. Environment Variables

Update `docker-compose.prod.yml` for your environment:

```yaml
api:
  environment:
    - ASPNETCORE_ENVIRONMENT=Production
    - OpenTelemetry__OtlpEndpoint=http://jaeger:4317  # ⬅️ Update if using external collector
```

---

## 6. Production Considerations

### Enable HTTPS

Add nginx-proxy or Traefik for SSL termination:

```yaml
services:
  nginx-proxy:
    image: nginxproxy/nginx-proxy
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/tmp/docker.sock:ro
      - ./certs:/etc/nginx/certs
```

### Persist Jaeger Data

Mount a volume for Jaeger storage:

```yaml
jaeger:
  volumes:
    - jaeger-data:/tmp
volumes:
  jaeger-data:
```

### Resource Limits

Set memory/CPU limits:

```yaml
api:
  deploy:
    resources:
      limits:
        cpus: '0.5'
        memory: 512M
      reservations:
        cpus: '0.25'
        memory: 256M
```

---

## 7. Scaling

Scale specific services:

```bash
docker compose -f docker-compose.prod.yml up -d --scale api=3 --scale ui=2
```

---

## 8. Monitoring

View resource usage:

```bash
docker stats
```

---

## Troubleshooting

### Container won't start

```bash
# View logs
docker compose -f docker-compose.prod.yml logs <service-name>

# Check health
docker inspect pathfinder-api | grep -A 10 Health
```

### Port conflicts

Update `docker-compose.prod.yml` ports:

```yaml
ports:
  - "8081:8080"  # Changed from 8080:8080
```

---

## Next Steps

- **Kubernetes:** [Deploy to K8s](./06-kubernetes-deployment.md)
- **AWS:** [Deploy to ECS](./07-aws-deployment.md)
- **Azure:** [Deploy to Container Apps](./08-azure-deployment.md)
