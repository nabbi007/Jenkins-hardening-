#!/bin/bash
# Verify Jenkins global environment variables are configured

set -euo pipefail

JENKINS_CONFIG="/var/lib/jenkins/config.xml"

echo "=== Checking Jenkins config.xml for global environment variables ==="

if ! sudo test -f "$JENKINS_CONFIG"; then
  echo "ERROR: $JENKINS_CONFIG not found"
  exit 1
fi

echo ""
echo "Looking for <envVars> section in config.xml:"
if sudo grep -q "<envVars>" "$JENKINS_CONFIG"; then
  echo "✓ Found <envVars> section"
  echo ""
  echo "Environment variables configured:"
  sudo grep -A 2 "<string>" "$JENKINS_CONFIG" | grep -E "(AWS_REGION|BACKEND_ECR_REPO|FRONTEND_ECR_REPO|ECS_)" || echo "  (none found)"
else
  echo "✗ No <envVars> section found in config.xml"
  echo ""
  echo "This means environment variables were NOT saved to disk."
  echo ""
  echo "To fix:"
  echo "1. Go to Jenkins UI → Manage Jenkins → System"
  echo "2. Scroll to 'Global properties'"
  echo "3. Check 'Environment variables'"
  echo "4. Add all 13 variables"
  echo "5. Click 'Save' at the bottom"
  echo "6. Run: sudo systemctl reload jenkins"
fi

echo ""
echo "=== Jenkins service status ==="
sudo systemctl status jenkins --no-pager | head -10
