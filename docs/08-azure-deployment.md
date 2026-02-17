# Azure Container Apps Deployment Guide

Deploy Pathfinder to Azure using Container Apps (serverless containers).

---

## Prerequisites

- Azure CLI configured (`az login`)
- Docker images built
- Azure subscription
- Resource group created

---

## 1. Create Resource Group

```bash
az group create \
  --name pathfinder-rg \
  --location eastus
```

---

## 2. Create Azure Container Registry (ACR)

```bash
# Create ACR
az acr create \
  --resource-group pathfinder-rg \
  --name pathfinderacr \
  --sku Basic

# Login to ACR
az acr login --name pathfinderacr

# Tag and push images
docker tag pathfinder-api:latest pathfinderacr.azurecr.io/pathfinder-api:latest
docker tag pathfinder-ui:latest pathfinderacr.azurecr.io/pathfinder-ui:latest

docker push pathfinderacr.azurecr.io/pathfinder-api:latest
docker push pathfinderacr.azurecr.io/pathfinder-ui:latest
```

---

## 3. Create Container Apps Environment

```bash
# Install Container Apps extension
az extension add --name containerapp --upgrade

# Register providers
az provider register --namespace Microsoft.App
az provider register --namespace Microsoft.OperationalInsights

# Create environment
az containerapp env create \
  --name pathfinder-env \
  --resource-group pathfinder-rg \
  --location eastus
```

---

## 4. Deploy Jaeger

```bash
az containerapp create \
  --name jaeger \
  --resource-group pathfinder-rg \
  --environment pathfinder-env \
  --image jaegertracing/all-in-one:latest \
  --target-port 16686 \
  --ingress external \
  --env-vars \
    "COLLECTOR_OTLP_ENABLED=true" \
    "COLLECTOR_OTLP_HTTP_CORS_ALLOWED_ORIGINS=*" \
  --cpu 0.5 \
  --memory 1.0Gi
```

---

## 5. Deploy .NET API

Update `azure/container-app-api.yaml` with your ACR name and subscription ID, then:

```bash
az containerapp create \
  --name pathfinder-api \
  --resource-group pathfinder-rg \
  --environment pathfinder-env \
  --image pathfinderacr.azurecr.io/pathfinder-api:latest \
  --target-port 8080 \
  --ingress external \
  --registry-server pathfinderacr.azurecr.io \
  --registry-identity system \
  --env-vars \
    "ASPNETCORE_ENVIRONMENT=Production" \
    "ASPNETCORE_URLS=http://+:8080" \
    "OpenTelemetry__ServiceName=pathfinder-api" \
    "OpenTelemetry__OtlpEndpoint=http://jaeger:4317" \
  --cpu 0.25 \
  --memory 0.5Gi \
  --min-replicas 1 \
  --max-replicas 5
```

---

## 6. Deploy Angular UI

```bash
az containerapp create \
  --name pathfinder-ui \
  --resource-group pathfinder-rg \
  --environment pathfinder-env \
  --image pathfinderacr.azurecr.io/pathfinder-ui:latest \
  --target-port 80 \
  --ingress external \
  --registry-server pathfinderacr.azurecr.io \
  --registry-identity system \
  --env-vars \
    "API_URL=https://pathfinder-api.<your-env-suffix>.eastus.azurecontainerapps.io" \
    "JAEGER_URL=https://jaeger.<your-env-suffix>.eastus.azurecontainerapps.io:4318" \
  --cpu 0.25 \
  --memory 0.5Gi \
  --min-replicas 1 \
  --max-replicas 5
```

---

## 7. Enable Managed Identity for ACR Access

```bash
# Get ACR resource ID
ACR_ID=$(az acr show --name pathfinderacr --query id --output tsv)

# Assign AcrPull role to Container App identity
az role assignment create \
  --assignee <container-app-identity> \
  --role AcrPull \
  --scope $ACR_ID
```

---

## 8. Configure Custom Domain (Optional)

```bash
# Add custom domain
az containerapp hostname add \
  --name pathfinder-ui \
  --resource-group pathfinder-rg \
  --hostname pathfinder.yourdomain.com

# Bind certificate
az containerapp hostname bind \
  --name pathfinder-ui \
  --resource-group pathfinder-rg \
  --hostname pathfinder.yourdomain.com \
  --validation-method CNAME \
  --environment pathfinder-env
```

---

## 9. Enable Application Insights

```bash
# Create App Insights
az monitor app-insights component create \
  --app pathfinder-insights \
  --location eastus \
  --resource-group pathfinder-rg

# Get instrumentation key
INSTRUMENTATION_KEY=$(az monitor app-insights component show \
  --app pathfinder-insights \
  --resource-group pathfinder-rg \
  --query instrumentationKey \
  --output tsv)

# Update container app
az containerapp update \
  --name pathfinder-api \
  --resource-group pathfinder-rg \
  --set-env-vars "APPLICATIONINSIGHTS_CONNECTION_STRING=InstrumentationKey=$INSTRUMENTATION_KEY"
```

---

## 10. Configure Auto-Scaling

```bash
# HTTP-based scaling
az containerapp update \
  --name pathfinder-api \
  --resource-group pathfinder-rg \
  --min-replicas 1 \
  --max-replicas 10 \
  --scale-rule-name http-scaling \
  --scale-rule-type http \
  --scale-rule-http-concurrency 100
```

---

## 11. View Logs

```bash
# Stream logs
az containerapp logs show \
  --name pathfinder-api \
  --resource-group pathfinder-rg \
  --follow

# View recent logs
az containerapp logs show \
  --name pathfinder-api \
  --resource-group pathfinder-rg \
  --tail 100
```

---

## 12. Update Container App

```bash
# Push new image
docker push pathfinderacr.azurecr.io/pathfinder-api:v2

# Update container
az containerapp update \
  --name pathfinder-api \
  --resource-group pathfinder-rg \
  --image pathfinderacr.azurecr.io/pathfinder-api:v2
```

---

## 13. View Container App URLs

```bash
# Get API URL
az containerapp show \
  --name pathfinder-api \
  --resource-group pathfinder-rg \
  --query properties.configuration.ingress.fqdn \
  --output tsv

# Get UI URL
az containerapp show \
  --name pathfinder-ui \
  --resource-group pathfinder-rg \
  --query properties.configuration.ingress.fqdn \
  --output tsv
```

---

## 14. Monitoring

```bash
# View metrics
az monitor metrics list \
  --resource <container-app-id> \
  --metric "Requests"

# View revisions
az containerapp revision list \
  --name pathfinder-api \
  --resource-group pathfinder-rg
```

---

## 15. Clean Up

```bash
# Delete container apps
az containerapp delete --name pathfinder-api --resource-group pathfinder-rg --yes
az containerapp delete --name pathfinder-ui --resource-group pathfinder-rg --yes
az containerapp delete --name jaeger --resource-group pathfinder-rg --yes

# Delete environment
az containerapp env delete --name pathfinder-env --resource-group pathfinder-rg --yes

# Delete resource group
az group delete --name pathfinder-rg --yes
```

---

## Troubleshooting

### Container fails to start

```bash
# View execution history
az containerapp revision list \
  --name pathfinder-api \
  --resource-group pathfinder-rg

# View replica details
az containerapp replica list \
  --name pathfinder-api \
  --resource-group pathfinder-rg

# Stream logs
az containerapp logs show --name pathfinder-api --resource-group pathfinder-rg --follow
```

### ACR authentication fails

```bash
# Verify managed identity
az containerapp show \
  --name pathfinder-api \
  --resource-group pathfinder-rg \
  --query identity

# Check role assignments
az role assignment list --assignee <identity-id>
```

---

## Cost Optimization

- Container Apps automatically scale to zero when idle
- Use consumption plan (pay only for what you use)
- Set appropriate min/max replicas based on traffic

---

## Next Steps

- **Docker:** [Local Docker deployment](./05-docker-deployment.md)
- **Kubernetes:** [Deploy to K8s](./06-kubernetes-deployment.md)
- **AWS:** [Deploy to ECS](./07-aws-deployment.md)
