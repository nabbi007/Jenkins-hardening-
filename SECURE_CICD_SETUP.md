# Jenkins CI/CD with AWS Secrets Manager + JCasC

Complete production-ready Jenkins setup with Configuration as Code (JCasC) and AWS Secrets Manager integration for secure ECS deployments.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Jenkins EC2 Instance                     │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  Jenkins (JCasC)                                       │ │
│  │  - No secrets on disk                                  │ │
│  │  - Config via jenkins.yaml                             │ │
│  │  - Credentials from AWS Secrets Manager                │ │
│  └────────────────────────────────────────────────────────┘ │
│                           ↓                                  │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  IAM Instance Role                                     │ │
│  │  - Secrets Manager read                                │ │
│  │  - ECR push                                            │ │
│  │  - ECS deploy                                          │ │
│  │  - STS GetCallerIdentity                               │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│              AWS Secrets Manager (eu-west-1)                 │
│  jenkins/voting-app:                                         │
│    - ecs-execution-role-arn                                  │
│    - ecs-task-role-arn                                       │
│  Tagged: jenkins:credentials:type=string                     │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│                    Pipeline Flow                             │
│  Checkout → Test → Security Scans → Build → Push ECR        │
│  → Render Task Def → Register → Deploy ECS → Cleanup        │
└─────────────────────────────────────────────────────────────┘
```

## Features

✅ **Zero secrets on disk** — All credentials from AWS Secrets Manager  
✅ **Configuration as Code** — jenkins.yaml defines all non-sensitive config  
✅ **Auto-detect AWS account** — No hardcoded account IDs  
✅ **Full audit trail** — CloudTrail logs every secret access  
✅ **Rotatable secrets** — Update in Secrets Manager, no Jenkins restart needed  
✅ **Security scans** — SonarQube, npm audit, Gitleaks, Trivy, SBOM  
✅ **ECS Fargate deployment** — Blue/green with health checks  
✅ **Sub-15 minute builds** — Parallel stages, cached Trivy DB  

## Quick Start

### Prerequisites

- AWS account with admin access
- EC2 instance (t3.medium or larger, Amazon Linux 2023)
- ECS cluster and service already created
- ECS execution and task IAM roles already created

### Step 1: Clone and Setup AWS

```bash
git clone <your-repo>
cd jenkins-hardening

# Make scripts executable
chmod +x scripts/*.sh

# Configure AWS Secrets Manager + IAM
./scripts/setup-aws-secrets.sh
# Enter your ECS execution role ARN when prompted
# Enter your ECS task role ARN when prompted
```

This creates:
- IAM policy `JenkinsECSDeployPolicy`
- IAM role `jenkins-ec2-role`
- IAM instance profile `jenkins-ec2-role`
- Secret `jenkins/voting-app` in Secrets Manager

### Step 2: Attach IAM Role to EC2

```bash
# Get instance ID
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)

# Attach instance profile
aws ec2 associate-iam-instance-profile \
  --instance-id "$INSTANCE_ID" \
  --iam-instance-profile Name=jenkins-ec2-role
```

### Step 3: Install Jenkins

```bash
# Run as root
sudo ./scripts/install-jenkins.sh
```

This installs:
- Java 17
- Jenkins with JCasC plugin
- Docker
- AWS CLI
- All required Jenkins plugins
- Configures systemd service

### Step 4: Verify Setup

Wait 60 seconds for Jenkins to start, then:

```bash
# Check Jenkins status
sudo systemctl status jenkins

# Get Jenkins URL
echo "http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8080"

# Get initial admin password (if needed)
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
```

### Step 5: Verify Credentials in Jenkins

1. Navigate to **Manage Jenkins → Credentials → System → Global credentials**
2. You should see two credentials automatically loaded from Secrets Manager:
   - `ecs-execution-role-arn`
   - `ecs-task-role-arn`

If credentials don't appear:
```bash
# Restart Jenkins to reload IAM role
sudo systemctl restart jenkins
```

### Step 6: Create Pipeline

1. In Jenkins, click **New Item**
2. Enter name: `voting-app-pipeline`
3. Select **Pipeline**
4. Under **Pipeline**, select **Pipeline script from SCM**
5. SCM: **Git**
6. Repository URL: `<your-git-repo>`
7. Branch: `*/main`
8. Script Path: `Jenkinsfile`
9. Save

### Step 7: Run First Build

Click **Build Now**. The pipeline will:
- Auto-detect AWS account ID
- Run tests and security scans in parallel
- Build and push Docker images to ECR
- Deploy to ECS Fargate
- Complete in under 15 minutes

## Configuration

### jenkins.yaml (JCasC)

All non-sensitive configuration is in `/var/lib/jenkins/jenkins.yaml`:

```yaml
jenkins:
  globalNodeProperties:
    - envVars:
        env:
          - key: AWS_REGION
            value: "eu-west-1"
          - key: BACKEND_ECR_REPO
            value: "backend-service"
          # ... etc
```

**To update configuration:**
```bash
sudo vim /var/lib/jenkins/jenkins.yaml
sudo systemctl restart jenkins
```

### AWS Secrets Manager

Secrets are stored in `jenkins/voting-app`:

```json
{
  "ecs-execution-role-arn": "arn:aws:iam::123456789012:role/ecsTaskExecutionRole",
  "ecs-task-role-arn": "arn:aws:iam::123456789012:role/ecsTaskRole"
}
```

**To rotate secrets:**
```bash
aws secretsmanager update-secret \
  --secret-id jenkins/voting-app \
  --secret-string '{
    "ecs-execution-role-arn": "arn:aws:iam::123456789012:role/newRole",
    "ecs-task-role-arn": "arn:aws:iam::123456789012:role/newTaskRole"
  }'
```

No Jenkins restart needed — credentials refresh automatically.

### Pipeline Parameters

Only feature flags are exposed as build parameters:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `ENABLE_SONARQUBE` | `true` | Run SonarQube SAST |
| `ENABLE_NPM_AUDIT` | `true` | Run npm audit SCA |
| `ENABLE_GITLEAKS` | `true` | Run Gitleaks secret scan |
| `ENABLE_TRIVY` | `true` | Run Trivy container scan |
| `ENABLE_SBOM` | `true` | Generate SBOM with Syft |
| `DEPLOY_FROM_NON_MAIN` | `false` | Allow deploy from non-main branches |

## Security

### What's Secure

✅ No AWS access keys on disk  
✅ No secrets in Jenkinsfile or jenkins.yaml  
✅ IAM instance role for all AWS operations  
✅ Secrets Manager credentials auto-refresh  
✅ CloudTrail audit log for every secret access  
✅ Least-privilege IAM policy  
✅ Secrets tagged for automatic discovery  

### IAM Permissions

The `jenkins-ec2-role` has minimal permissions:

- **Secrets Manager**: Read `jenkins/*` secrets only
- **ECR**: Push images, manage lifecycle policies
- **ECS**: Deploy services, register task definitions
- **IAM**: PassRole only for ECS task roles
- **STS**: GetCallerIdentity for account ID detection
- **CloudWatch Logs**: Create log groups for ECS tasks

### Audit Trail

Every secret access is logged in CloudTrail:

```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=ResourceName,AttributeValue=jenkins/voting-app \
  --max-results 10
```

## Troubleshooting

### Credentials not appearing in Jenkins

```bash
# Check IAM instance profile is attached
aws ec2 describe-instances --instance-ids $(curl -s http://169.254.169.254/latest/meta-data/instance-id) \
  --query 'Reservations[0].Instances[0].IamInstanceProfile'

# Check Jenkins can access Secrets Manager
sudo -u jenkins aws secretsmanager get-secret-value --secret-id jenkins/voting-app

# Restart Jenkins
sudo systemctl restart jenkins
```

### Pipeline fails with "Unable to determine AWS account ID"

```bash
# Verify IAM role has STS permissions
aws sts get-caller-identity

# Check Jenkins can run AWS CLI
sudo -u jenkins aws sts get-caller-identity
```

### ECS deployment fails with "AccessDenied"

```bash
# Verify IAM role can pass ECS roles
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/jenkins-ec2-role \
  --action-names iam:PassRole \
  --resource-arns arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/ecsTaskExecutionRole
```

## Files

```
.
├── Jenkinsfile                      # Pipeline definition (no secrets)
├── jenkins.yaml                     # JCasC config (no secrets)
├── jenkins.service                  # Systemd service file
├── jenkins-plugins.txt              # Required plugins
├── iam-policy-jenkins-ec2.json      # IAM policy for EC2 role
├── ecs/
│   └── taskdef.template.json        # ECS task definition template
└── scripts/
    ├── install-jenkins.sh           # Complete Jenkins installation
    └── setup-aws-secrets.sh         # AWS Secrets Manager setup
```

## Pipeline Stages

1. **Checkout** — Clone repository
2. **Prepare Build Metadata** — Generate image tags, detect AWS account
3. **Unit + Lint** — Backend and frontend tests in parallel
4. **Security Scans** — SonarQube, npm audit, Gitleaks in parallel
5. **Build Container Images** — Docker build backend and frontend
6. **Post-Build Scans** — Trivy and Syft in parallel
7. **Push Versioned Images to ECR** — Tagged with git SHA + build number
8. **Tag Latest** — Only on main branch
9. **Render ECS Task Definition** — Inject secrets from Secrets Manager
10. **Register ECS Task Definition Revision** — Create new revision
11. **Deploy to ECS Service** — Update service, wait for stability
12. **Post-Deploy Cleanup** — ECR lifecycle policy, prune old task defs
13. **Docker Cleanup** — Remove dangling images

## Cost Optimization

- **Secrets Manager**: $0.40/month per secret + $0.05 per 10,000 API calls
- **CloudTrail**: Included in AWS Free Tier (first trail free)
- **ECR**: $0.10/GB/month storage
- **ECS Fargate**: Pay only for running tasks

Estimated monthly cost: **~$5-10** for this setup.

## License

MIT
