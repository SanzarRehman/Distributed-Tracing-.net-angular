# Kubernetes Deployment Guide

Deploy Pathfinder to any Kubernetes cluster (EKS, AKS, GKE, on-prem).

---

## Prerequisites

- Kubernetes 1.24+
- `kubectl` configured
- Docker registry access (Docker Hub, ECR, ACR, GCR)
- Ingress controller (nginx, Traefik, or cloud LB)

---

## 1. Build and Push Images

```bash
# Build images
docker build -t <your-registry>/pathfinder-api:latest ./PathfinderApi
docker build -t <your-registry>/pathfinder-ui:latest ./pathfinder-ui

# Push to registry
docker push <your-registry>/pathfinder-api:latest
docker push <your-registry>/pathfinder-ui:latest
```

---

## 2. Update Image References

Edit `k8s/api.yaml` and `k8s/ui.yaml`:

```yaml
spec:
  containers:
  - name: api
    image: <your-registry>/pathfinder-api:latest  # ⬅️ Update this
```

---

## 3. Deploy to Kubernetes

```bash
# Create namespace
kubectl apply -f k8s/namespace.yaml

# Create ConfigMap
kubectl apply -f k8s/configmap.yaml

# Deploy Jaeger
kubectl apply -f k8s/jaeger.yaml

# Deploy API and UI
kubectl apply -f k8s/api.yaml
kubectl apply -f k8s/ui.yaml

# Create Ingress (optional)
kubectl apply -f k8s/ingress.yaml
```

---

## 4. Verify Deployment

```bash
# Check pods
kubectl get pods -n pathfinder

# Check services
kubectl get svc -n pathfinder

# View logs
kubectl logs -f deployment/api -n pathfinder
kubectl logs -f deployment/ui -n pathfinder

# Port-forward for local testing
kubectl port-forward svc/ui-service 8080:80 -n pathfinder
kubectl port-forward svc/jaeger 16686:16686 -n pathfinder
```

---

## 5. Ingress Configuration

### Update Ingress Hosts

Edit `k8s/ingress.yaml`:

```yaml
rules:
- host: pathfinder.yourdomain.com  # ⬅️ Update
- host: jaeger.yourdomain.com      # ⬅️ Update
```

### Install nginx Ingress Controller

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install nginx-ingress ingress-nginx/ingress-nginx
```

### Enable TLS with cert-manager

```bash
# Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# Create ClusterIssuer
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
EOF
```

---

## 6. Scaling

```bash
# Scale API replicas
kubectl scale deployment api --replicas=5 -n pathfinder

# Auto-scaling (HPA)
kubectl autoscale deployment api --cpu-percent=70 --min=2 --max=10 -n pathfinder
```

---

## 7. Update Deployment

```bash
# Update image
kubectl set image deployment/api api=<your-registry>/pathfinder-api:v2 -n pathfinder

# Rollout status
kubectl rollout status deployment/api -n pathfinder

# Rollback
kubectl rollout undo deployment/api -n pathfinder
```

---

## 8. Resource Monitoring

```bash
# View resource usage
kubectl top pods -n pathfinder
kubectl top nodes

# Describe pod
kubectl describe pod <pod-name> -n pathfinder
```

---

## 9. Persistent Storage (Optional)

For Jaeger data persistence:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: jaeger-pvc
  namespace: pathfinder
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
---
# Update jaeger.yaml deployment
spec:
  template:
    spec:
      containers:
      - name: jaeger
        volumeMounts:
        - name: jaeger-storage
          mountPath: /tmp
      volumes:
      - name: jaeger-storage
        persistentVolumeClaim:
          claimName: jaeger-pvc
```

---

## 10. Clean Up

```bash
# Delete all resources
kubectl delete namespace pathfinder
```

---

## Cloud-Specific Setup

### AWS EKS

```bash
# Create cluster
eksctl create cluster --name pathfinder --region us-east-1 --nodes 3

# Install AWS Load Balancer Controller
helm repo add eks https://aws.github.io/eks-charts
helm install aws-load-balancer-controller eks/aws-load-balancer-controller -n kube-system
```

### Azure AKS

```bash
# Create cluster
az aks create --resource-group pathfinder-rg --name pathfinder-aks --node-count 3

# Get credentials
az aks get-credentials --resource-group pathfinder-rg --name pathfinder-aks
```

### Google GKE

```bash
# Create cluster
gcloud container clusters create pathfinder --num-nodes=3 --zone=us-central1-a

# Get credentials
gcloud container clusters get-credentials pathfinder --zone=us-central1-a
```

---

## Troubleshooting

### Pods not starting

```bash
kubectl describe pod <pod-name> -n pathfinder
kubectl logs <pod-name> -n pathfinder
```

### ImagePullBackOff

- Verify image name and tag
- Check registry authentication:
  ```bash
  kubectl create secret docker-registry regcred \
    --docker-server=<your-registry> \
    --docker-username=<username> \
    --docker-password=<password> \
    -n pathfinder
  ```

### Service not accessible

```bash
# Check service endpoints
kubectl get endpoints -n pathfinder

# Test from within cluster
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -n pathfinder -- sh
curl http://api-service:8080/api/health
```

---

## Next Steps

- **Docker:** [Local Docker deployment](./05-docker-deployment.md)
- **AWS:** [Deploy to ECS](./07-aws-deployment.md)
- **Azure:** [Deploy to Container Apps](./08-azure-deployment.md)
