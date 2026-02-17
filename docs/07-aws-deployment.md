# AWS ECS Deployment Guide

Deploy Pathfinder to AWS using Elastic Container Service (ECS) with Fargate.

---

## Prerequisites

- AWS CLI configured
- AWS account with appropriate permissions
- Docker images built and pushed to ECR
- VPC with public/private subnets

---

## 1. Create ECR Repositories

```bash
# Create repositories
aws ecr create-repository --repository-name pathfinder-api --region us-east-1
aws ecr create-repository --repository-name pathfinder-ui --region us-east-1

# Login to ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin <account-id>.dkr.ecr.us-east-1.amazonaws.com

# Tag and push images
docker tag pathfinder-api:latest <account-id>.dkr.ecr.us-east-1.amazonaws.com/pathfinder-api:latest
docker tag pathfinder-ui:latest <account-id>.dkr.ecr.us-east-1.amazonaws.com/pathfinder-ui:latest

docker push <account-id>.dkr.ecr.us-east-1.amazonaws.com/pathfinder-api:latest
docker push <account-id>.dkr.ecr.us-east-1.amazonaws.com/pathfinder-ui:latest
```

---

## 2. Create IAM Roles

### Task Execution Role

```bash
aws iam create-role --role-name ecsTaskExecutionRole \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"Service": "ecs-tasks.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }]
  }'

aws iam attach-role-policy --role-name ecsTaskExecutionRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
```

### Task Role (for CloudWatch, X-Ray)

```bash
aws iam create-role --role-name pathfinderTaskRole \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"Service": "ecs-tasks.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }]
  }'

aws iam attach-role-policy --role-name pathfinderTaskRole \
  --policy-arn arn:aws:iam::aws:policy/CloudWatchLogsFullAccess
```

---

## 3. Create CloudWatch Log Groups

```bash
aws logs create-log-group --log-group-name /ecs/pathfinder-api
aws logs create-log-group --log-group-name /ecs/pathfinder-ui
aws logs create-log-group --log-group-name /ecs/pathfinder-jaeger
```

---

## 4. Register Task Definitions

Update the task definition files (`aws/ecs-task-*.json`) with your account ID and region, then:

```bash
# Register API task
aws ecs register-task-definition --cli-input-json file://aws/ecs-task-api.json

# Register UI task
aws ecs register-task-definition --cli-input-json file://aws/ecs-task-ui.json

# Register Jaeger task
aws ecs register-task-definition --cli-input-json file://aws/ecs-task-jaeger.json
```

---

## 5. Create ECS Cluster

```bash
aws ecs create-cluster --cluster-name pathfinder-cluster
```

---

## 6. Create Application Load Balancer

```bash
# Create ALB
aws elbv2 create-load-balancer \
  --name pathfinder-alb \
  --subnets subnet-xxxxx subnet-yyyyy \
  --security-groups sg-xxxxx \
  --scheme internet-facing \
  --type application

# Create target groups
aws elbv2 create-target-group \
  --name pathfinder-api-tg \
  --protocol HTTP \
  --port 8080 \
  --vpc-id vpc-xxxxx \
  --target-type ip \
  --health-check-path /api/health

aws elbv2 create-target-group \
  --name pathfinder-ui-tg \
  --protocol HTTP \
  --port 80 \
  --vpc-id vpc-xxxxx \
  --target-type ip \
  --health-check-path /

# Create listeners
aws elbv2 create-listener \
  --load-balancer-arn <alb-arn> \
  --protocol HTTP \
  --port 80 \
  --default-actions Type=forward,TargetGroupArn=<ui-tg-arn>
```

---

## 7. Create ECS Services

```bash
# Create API service
aws ecs create-service \
  --cluster pathfinder-cluster \
  --service-name api-service \
  --task-definition pathfinder-api \
  --desired-count 2 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[subnet-xxxxx],securityGroups=[sg-xxxxx],assignPublicIp=ENABLED}" \
  --load-balancers "targetGroupArn=<api-tg-arn>,containerName=pathfinder-api,containerPort=8080"

# Create UI service
aws ecs create-service \
  --cluster pathfinder-cluster \
  --service-name ui-service \
  --task-definition pathfinder-ui \
  --desired-count 2 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[subnet-xxxxx],securityGroups=[sg-xxxxx],assignPublicIp=ENABLED}" \
  --load-balancers "targetGroupArn=<ui-tg-arn>,containerName=pathfinder-ui,containerPort=80"

# Create Jaeger service
aws ecs create-service \
  --cluster pathfinder-cluster \
  --service-name jaeger-service \
  --task-definition pathfinder-jaeger \
  --desired-count 1 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[subnet-xxxxx],securityGroups=[sg-xxxxx],assignPublicIp=ENABLED}"
```

---

## 8. Configure Service Discovery (Optional)

For inter-service communication:

```bash
# Create namespace
aws servicediscovery create-private-dns-namespace \
  --name pathfinder.local \
  --vpc vpc-xxxxx

# Create services
aws servicediscovery create-service \
  --name jaeger \
  --dns-config "NamespaceId=ns-xxxxx,DnsRecords=[{Type=A,TTL=60}]" \
  --health-check-custom-config FailureThreshold=1
```

Update ECS services to use service discovery.

---

## 9. Enable Auto Scaling

```bash
# Register scalable target
aws application-autoscaling register-scalable-target \
  --service-namespace ecs \
  --resource-id service/pathfinder-cluster/api-service \
  --scalable-dimension ecs:service:DesiredCount \
  --min-capacity 2 \
  --max-capacity 10

# Create scaling policy
aws application-autoscaling put-scaling-policy \
  --service-namespace ecs \
  --resource-id service/pathfinder-cluster/api-service \
  --scalable-dimension ecs:service:DesiredCount \
  --policy-name cpu-scaling \
  --policy-type TargetTrackingScaling \
  --target-tracking-scaling-policy-configuration '{
    "TargetValue": 70.0,
    "PredefinedMetricSpecification": {
      "PredefinedMetricType": "ECSServiceAverageCPUUtilization"
    }
  }'
```

---

## 10. CloudWatch Integration

Traces are already sent to CloudWatch Logs. To view:

```bash
# View API logs
aws logs tail /ecs/pathfinder-api --follow

# View UI logs
aws logs tail /ecs/pathfinder-ui --follow
```

---

## 11. Update Service

```bash
# Push new image
docker push <account-id>.dkr.ecr.us-east-1.amazonaws.com/pathfinder-api:v2

# Update task definition (increment revision)
aws ecs register-task-definition --cli-input-json file://aws/ecs-task-api.json

# Update service
aws ecs update-service \
  --cluster pathfinder-cluster \
  --service api-service \
  --task-definition pathfinder-api:2
```

---

## 12. Monitoring

```bash
# View service status
aws ecs describe-services --cluster pathfinder-cluster --services api-service

# View tasks
aws ecs list-tasks --cluster pathfinder-cluster --service-name api-service

# View task details
aws ecs describe-tasks --cluster pathfinder-cluster --tasks <task-arn>
```

---

## 13. Clean Up

```bash
# Delete services
aws ecs delete-service --cluster pathfinder-cluster --service api-service --force
aws ecs delete-service --cluster pathfinder-cluster --service ui-service --force

# Delete cluster
aws ecs delete-cluster --cluster pathfinder-cluster

# Delete ALB
aws elbv2 delete-load-balancer --load-balancer-arn <alb-arn>

# Delete target groups
aws elbv2 delete-target-group --target-group-arn <tg-arn>

# Delete ECR repositories
aws ecr delete-repository --repository-name pathfinder-api --force
aws ecr delete-repository --repository-name pathfinder-ui --force
```

---

## Troubleshooting

### Task fails to start

```bash
# View task logs
aws logs tail /ecs/pathfinder-api --follow

# Describe task
aws ecs describe-tasks --cluster pathfinder-cluster --tasks <task-arn>
```

### Health check failures

- Verify security group allows traffic on health check port
- Check target group health check settings
- Review CloudWatch logs for errors

---

## Cost Optimization

- Use Fargate Spot for non-production workloads
- Enable auto-scaling to match demand
- Use Application Load Balancer listeners rules for path-based routing (single ALB)

---

## Next Steps

- **Docker:** [Local Docker deployment](./05-docker-deployment.md)
- **Kubernetes:** [Deploy to K8s](./06-kubernetes-deployment.md)
- **Azure:** [Deploy to Container Apps](./08-azure-deployment.md)
