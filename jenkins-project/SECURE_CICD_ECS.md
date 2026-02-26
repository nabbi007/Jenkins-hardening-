# Secure CI/CD to ECS (Fargate)

This repo now includes a hardened Jenkins pipeline and Terraform modules to deploy the existing backend + frontend app to ECS with enforced security gates.

## What was added

- `Jenkinsfile`:
  - SAST: SonarQube scan with quality gate wait/fail.
  - SCA: OWASP Dependency-Check for backend and frontend lockfiles.
  - Secret scan: Gitleaks (fails on findings).
  - Image scan: Trivy (fails on HIGH/CRITICAL).
  - SBOM: Syft CycloneDX JSON output for both images.
  - Versioned ECR image pushes (`<branch>-<sha>-<build>`), plus `latest` on `main`.
  - ECS task definition rendering/registration and ECS service rolling update.
  - Evidence + reports archived under `reports/**`.
  - ECR lifecycle policy enforcement and old ECS revision cleanup.

- `ecs/taskdef.template.json`:
  - Dual-container task definition (backend + frontend).
  - CloudWatch logs enabled via `awslogs` for both containers.

- `infra/terraform/` (module-based):
  - `modules/ecr`: repositories + lifecycle policy.
  - `modules/ecs_fargate`: cluster, roles, service, task definition, security group, log groups.
  - `modules/cloudwatch_alarms`: ECS CPU/memory alarms.
  - `modules/jenkins_ec2`: Jenkins instance + IAM profile + security group + bootstrap user data.

## Jenkins EC2 bootstrap (new)

- User data file: `infra/terraform/modules/jenkins_ec2/user_data.sh.tftpl`
- Installs and configures:
  - Jenkins LTS + Java 21
  - Docker (and adds `jenkins` user to docker group)
  - Node.js 20 + npm (for backend/frontend lint/test stages)
  - AWS CLI, Terraform, git, jq, curl, unzip
- Opens Jenkins host ports from `jenkins_ingress_ports` (default: `22`, `8080`, `9000`) to `jenkins_allowed_cidrs`.
- ECS service public ports are controlled by `ecs_public_ingress_ports` (default: `80`, `3000`).
- Creates EC2 IAM instance profile with ECR push + ECS deploy permissions used by this pipeline.

## What else you need

1. Jenkins credentials:
- `sonarqube_token` (Secret text)

2. Jenkins agent capabilities:
- Docker CLI access (`docker run`, Docker socket)
- AWS CLI configured through instance profile/IAM role

3. AWS IAM permissions for Jenkins role:
- `ecr:*` (at least login/push/lifecycle)
- `ecs:Describe*`, `ecs:RegisterTaskDefinition`, `ecs:UpdateService`, `ecs:DeregisterTaskDefinition`, `ecs:ListTaskDefinitions`
- `iam:PassRole` for ECS execution/task roles used in task definition
- `logs:CreateLogGroup`, `logs:CreateLogStream`, `logs:PutLogEvents` (task execution role)

4. SonarQube project and quality gate configured to fail on high-severity or gate breach.

## Terraform apply

```bash
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars
terraform init
terraform plan
terraform apply
```

Use outputs in Jenkins parameters:
- `ECS_CLUSTER_NAME`
- `ECS_SERVICE_NAME`
- `ECS_TASK_FAMILY`
- `ECS_EXECUTION_ROLE_ARN`
- `ECS_TASK_ROLE_ARN`

Jenkins access outputs:
- `jenkins_public_ip`
- `jenkins_public_dns`

After apply, get Jenkins initial admin password:

```bash
ssh -i <your-key>.pem ec2-user@<jenkins_public_ip> "sudo cat /var/lib/jenkins/secrets/initialAdminPassword"
```

## Validation test (required)

1. Intentionally add a vulnerable dependency to backend, for example:

```bash
cd backend
npm install lodash@4.17.15 --save
```

2. Run Jenkins pipeline:
- OWASP DC and/or Trivy should fail and block deployment.

3. Fix vulnerability (upgrade/remove), commit, rerun:
- Security stages pass.
- ECS service update succeeds.

## Evidence files after successful deploy

- Security reports:
  - `reports/security/dependency-check/backend/dependency-check-report.json`
  - `reports/security/dependency-check/frontend/dependency-check-report.json`
  - `reports/security/trivy/backend-image.json`
  - `reports/security/trivy/frontend-image.json`
  - `reports/security/gitleaks.sarif`

- SBOM:
  - `reports/sbom/backend.cyclonedx.json`
  - `reports/sbom/frontend.cyclonedx.json`

- ECS deployment evidence:
  - `reports/ecs/taskdef.rendered.json`
  - `reports/ecs/task-definition.revision.json`
  - `reports/ecs/service-update.json`
  - `reports/ecs/service-after-update.json`
