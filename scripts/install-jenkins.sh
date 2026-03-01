#!/bin/bash
set -euo pipefail

# Jenkins installation and configuration script with JCasC + AWS Secrets Manager
# Run as root on Amazon Linux 2023 or RHEL-based systems

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}=== Jenkins Installation with JCasC + AWS Secrets Manager ===${NC}\n"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root${NC}"
   exit 1
fi

# Step 1: Install Java
echo -e "${GREEN}[1/8] Installing Java 17...${NC}"
dnf install -y java-17-amazon-corretto-headless

# Step 2: Add Jenkins repository
echo -e "\n${GREEN}[2/8] Adding Jenkins repository...${NC}"
wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key

# Step 3: Install Jenkins
echo -e "\n${GREEN}[3/8] Installing Jenkins...${NC}"
dnf install -y jenkins

# Step 4: Install Docker
echo -e "\n${GREEN}[4/8] Installing Docker...${NC}"
dnf install -y docker
systemctl enable docker
systemctl start docker
usermod -aG docker jenkins

# Step 5: Install AWS CLI
echo -e "\n${GREEN}[5/8] Installing AWS CLI...${NC}"
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
unzip -q /tmp/awscliv2.zip -d /tmp
/tmp/aws/install
rm -rf /tmp/aws /tmp/awscliv2.zip

# Step 6: Copy JCasC configuration
echo -e "\n${GREEN}[6/8] Setting up JCasC configuration...${NC}"
mkdir -p /var/lib/jenkins
cp jenkins.yaml /var/lib/jenkins/jenkins.yaml
chown jenkins:jenkins /var/lib/jenkins/jenkins.yaml
chmod 600 /var/lib/jenkins/jenkins.yaml

# Step 7: Install Jenkins plugins
echo -e "\n${GREEN}[7/8] Installing Jenkins plugins...${NC}"
mkdir -p /var/lib/jenkins/plugins
while IFS= read -r plugin; do
  [[ -z "$plugin" || "$plugin" =~ ^# ]] && continue
  PLUGIN_NAME=$(echo "$plugin" | cut -d: -f1)
  PLUGIN_VERSION=$(echo "$plugin" | cut -d: -f2)
  echo "Installing $PLUGIN_NAME:$PLUGIN_VERSION"
  curl -sL "https://updates.jenkins.io/download/plugins/$PLUGIN_NAME/$PLUGIN_VERSION/$PLUGIN_NAME.hpi" \
    -o "/var/lib/jenkins/plugins/$PLUGIN_NAME.jpi"
done < jenkins-plugins.txt
chown -R jenkins:jenkins /var/lib/jenkins/plugins

# Step 8: Configure and start Jenkins
echo -e "\n${GREEN}[8/8] Configuring Jenkins service...${NC}"
cp jenkins.service /etc/systemd/system/jenkins.service
systemctl daemon-reload
systemctl enable jenkins
systemctl start jenkins

echo -e "\n${BLUE}=== Installation Complete ===${NC}"
echo -e "\nJenkins is starting up..."
echo "Wait 60 seconds, then access Jenkins at: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8080"
echo ""
echo "Initial admin password (if needed):"
echo "  sudo cat /var/lib/jenkins/secrets/initialAdminPassword"
echo ""
echo "Next steps:"
echo "1. Run ./setup-aws-secrets.sh to configure AWS Secrets Manager"
echo "2. Attach the IAM instance profile to this EC2 instance"
echo "3. Restart Jenkins: sudo systemctl restart jenkins"
echo "4. Verify credentials appear in Jenkins UI"
