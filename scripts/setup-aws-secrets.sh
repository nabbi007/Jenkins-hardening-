#!/bin/bash
set -euo pipefail

# Configuration
AWS_REGION="${AWS_REGION:-eu-west-1}"
SECRET_NAME="jenkins/voting-app"
IAM_ROLE_NAME="jenkins-ec2-role"
IAM_POLICY_NAME="JenkinsECSDeployPolicy"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== AWS Secrets Manager + IAM Setup for Jenkins ===${NC}\n"

# Step 1: Create IAM policy
echo -e "${GREEN}[1/5] Creating IAM policy...${NC}"
POLICY_ARN=$(aws iam create-policy \
  --policy-name "$IAM_POLICY_NAME" \
  --policy-document file://iam-policy-jenkins-ec2.json \
  --query 'Policy.Arn' \
  --output text 2>/dev/null || \
  aws iam list-policies --query "Policies[?PolicyName=='$IAM_POLICY_NAME'].Arn" --output text)

echo "Policy ARN: $POLICY_ARN"

# Step 2: Create IAM role for EC2
echo -e "\n${GREEN}[2/5] Creating IAM role for EC2...${NC}"
cat > /tmp/trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "ec2.amazonaws.com" },
    "Action": "sts:AssumeRole"
  }]
}
EOF

aws iam create-role \
  --role-name "$IAM_ROLE_NAME" \
  --assume-role-policy-document file:///tmp/trust-policy.json \
  --description "Jenkins EC2 role for ECS deployment" 2>/dev/null || echo "Role already exists"

# Step 3: Attach policy to role
echo -e "\n${GREEN}[3/5] Attaching policy to role...${NC}"
aws iam attach-role-policy \
  --role-name "$IAM_ROLE_NAME" \
  --policy-arn "$POLICY_ARN"

# Step 4: Create instance profile
echo -e "\n${GREEN}[4/5] Creating instance profile...${NC}"
aws iam create-instance-profile \
  --instance-profile-name "$IAM_ROLE_NAME" 2>/dev/null || echo "Instance profile already exists"

aws iam add-role-to-instance-profile \
  --instance-profile-name "$IAM_ROLE_NAME" \
  --role-name "$IAM_ROLE_NAME" 2>/dev/null || echo "Role already in instance profile"

# Step 5: Create secret in AWS Secrets Manager
echo -e "\n${GREEN}[5/5] Creating secret in AWS Secrets Manager...${NC}"

# Prompt for ARNs
read -p "Enter ECS Execution Role ARN: " EXEC_ROLE_ARN
read -p "Enter ECS Task Role ARN: " TASK_ROLE_ARN

aws secretsmanager create-secret \
  --name "$SECRET_NAME" \
  --description "Jenkins ECS deployment credentials" \
  --secret-string "{
    \"ecs-execution-role-arn\": \"$EXEC_ROLE_ARN\",
    \"ecs-task-role-arn\": \"$TASK_ROLE_ARN\"
  }" \
  --tags Key=jenkins:credentials:type,Value=string \
  --region "$AWS_REGION" 2>/dev/null || \
  aws secretsmanager update-secret \
    --secret-id "$SECRET_NAME" \
    --secret-string "{
      \"ecs-execution-role-arn\": \"$EXEC_ROLE_ARN\",
      \"ecs-task-role-arn\": \"$TASK_ROLE_ARN\"
    }" \
    --region "$AWS_REGION"

echo -e "\n${BLUE}=== Setup Complete ===${NC}"
echo -e "\nNext steps:"
echo "1. Attach instance profile '$IAM_ROLE_NAME' to your Jenkins EC2 instance"
echo "2. Restart Jenkins to load the new IAM role"
echo "3. Verify credentials appear in Jenkins UI under Manage Credentials"
echo ""
echo "Secret ARN: arn:aws:secretsmanager:$AWS_REGION:$(aws sts get-caller-identity --query Account --output text):secret:$SECRET_NAME"
echo "Instance Profile ARN: arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):instance-profile/$IAM_ROLE_NAME"
