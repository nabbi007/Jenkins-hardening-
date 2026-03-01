pipeline {
  agent any

  options {
    timestamps()
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '30', artifactNumToKeepStr: '30'))
    timeout(time: 90, unit: 'MINUTES')
  }

  triggers {
    githubPush()
  }

  parameters {
    string(name: 'AWS_REGION', defaultValue: 'eu-west-1', description: 'AWS region containing ECR/ECS resources')
    string(name: 'ECR_ACCOUNT_ID', defaultValue: '', description: 'AWS account ID for ECR. Blank = auto-detect from Jenkins IAM role')
    string(name: 'BACKEND_ECR_REPO', defaultValue: 'backend-service', description: 'ECR repository for backend image')
    string(name: 'FRONTEND_ECR_REPO', defaultValue: 'frontend-web', description: 'ECR repository for frontend image')

    string(name: 'ECS_CLUSTER_NAME', defaultValue: 'voting-cluster', description: 'Target ECS cluster name')
    string(name: 'ECS_SERVICE_NAME', defaultValue: 'voting-app', description: 'Target ECS service name')
    string(name: 'ECS_TASK_FAMILY', defaultValue: 'voting-app', description: 'ECS task definition family')
    string(name: 'ECS_EXECUTION_ROLE_ARN', defaultValue: '', description: 'Execution role ARN. Blank = reuse current service task definition role')
    string(name: 'ECS_TASK_ROLE_ARN', defaultValue: '', description: 'Task role ARN. Blank = reuse current service task definition role')
    string(name: 'ECS_TASK_CPU', defaultValue: '512', description: 'Task-level CPU units for ECS task definition')
    string(name: 'ECS_TASK_MEMORY', defaultValue: '1024', description: 'Task-level memory (MiB) for ECS task definition')
    string(name: 'BACKEND_LOG_GROUP', defaultValue: '/ecs/voting-app/backend', description: 'CloudWatch log group for backend container')
    string(name: 'FRONTEND_LOG_GROUP', defaultValue: '/ecs/voting-app/frontend', description: 'CloudWatch log group for frontend container')

    booleanParam(name: 'ENABLE_SONARQUBE', defaultValue: true, description: 'Run SonarQube SAST + quality gate')
    booleanParam(name: 'ENABLE_OWASP_DC', defaultValue: true, description: 'Run OWASP Dependency-Check (SCA)')
    booleanParam(name: 'ENABLE_GITLEAKS', defaultValue: true, description: 'Run Gitleaks secret scan')
    booleanParam(name: 'ENABLE_TRIVY', defaultValue: true, description: 'Run Trivy image vulnerability scan')
    booleanParam(name: 'ENABLE_SBOM', defaultValue: true, description: 'Generate SBOM using Syft')

    string(name: 'FAIL_ON_CVSS', defaultValue: '7', description: 'OWASP Dependency-Check fail threshold (7 = High/Critical)')
    string(name: 'TRIVY_SEVERITIES', defaultValue: 'HIGH,CRITICAL', description: 'Trivy severity gate')
    string(name: 'ECR_LIFECYCLE_MAX_IMAGES', defaultValue: '30', description: 'Retain only latest N images in each ECR repo')
    string(name: 'ECS_TASKDEF_KEEP_REVISIONS', defaultValue: '15', description: 'Retain only latest N task definition revisions after successful deploy')
    booleanParam(name: 'DEPLOY_FROM_NON_MAIN', defaultValue: false, description: 'Allow ECS deployment for non-main branches')
  }

  environment {
    REPORT_DIR = 'reports/security'
    SBOM_DIR = 'reports/sbom'
    ECS_REPORT_DIR = 'reports/ecs'
    TASKDEF_TEMPLATE = 'ecs/taskdef.template.json'

    BACKEND_CONTAINER_NAME = 'backend'
    FRONTEND_CONTAINER_NAME = 'frontend'
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Prepare Build Metadata') {
      steps {
        script {
          env.GIT_SHA = sh(script: 'git rev-parse --short=8 HEAD', returnStdout: true).trim()
          env.SAFE_BRANCH = (env.BRANCH_NAME ?: 'detached').replaceAll('[^a-zA-Z0-9_.-]', '-')
          env.IMAGE_TAG = "${env.SAFE_BRANCH}-${env.GIT_SHA}-${env.BUILD_NUMBER}"

          if (!params.ECR_ACCOUNT_ID?.trim()) {
            env.ECR_ACCOUNT_ID_EFFECTIVE = sh(
              script: 'aws sts get-caller-identity --query Account --output text',
              returnStdout: true
            ).trim()
          } else {
            env.ECR_ACCOUNT_ID_EFFECTIVE = params.ECR_ACCOUNT_ID.trim()
          }

          if (!env.ECR_ACCOUNT_ID_EFFECTIVE) {
            error('Unable to determine AWS account ID. Set ECR_ACCOUNT_ID or ensure Jenkins IAM role has sts:GetCallerIdentity permission.')
          }

          env.ECR_REGISTRY = "${env.ECR_ACCOUNT_ID_EFFECTIVE}.dkr.ecr.${params.AWS_REGION}.amazonaws.com"
          env.BACKEND_IMAGE_URI = "${env.ECR_REGISTRY}/${params.BACKEND_ECR_REPO}:${env.IMAGE_TAG}"
          env.FRONTEND_IMAGE_URI = "${env.ECR_REGISTRY}/${params.FRONTEND_ECR_REPO}:${env.IMAGE_TAG}"

          sh 'mkdir -p reports/security reports/security/dependency-check/backend reports/security/dependency-check/frontend reports/security/trivy reports/sbom reports/ecs .trivycache'
          sh 'test -f ecs/taskdef.template.json'
        }
      }
    }

    stage('Unit + Lint') {
      parallel {
        stage('Backend') {
          steps {
            dir('backend') {
              sh 'npm ci --no-audit --no-fund'
              sh 'npm run lint'
              sh 'npm run test:ci'
            }
          }
        }
        stage('Frontend') {
          steps {
            dir('frontend') {
              sh 'npm ci --no-audit --no-fund'
              sh 'npm run lint'
              sh 'npm run test:ci'
              sh 'npm run build'
            }
          }
        }
      }
    }

    stage('SAST - SonarQube Quality Gate') {
      when {
        expression { return params.ENABLE_SONARQUBE }
      }
      steps {
        withSonarQubeEnv('sonar-qube-server') {
          sh '''
            set -euo pipefail
            docker run --rm \
              --network host \
              -v "$PWD:/usr/src" \
              -e SONAR_HOST_URL="${SONAR_HOST_URL}" \
              -e SONAR_TOKEN="${SONAR_AUTH_TOKEN}" \
              sonarsource/sonar-scanner-cli:5.0.1 \
              -Dsonar.login="${SONAR_AUTH_TOKEN}" \
              -Dsonar.projectVersion="${IMAGE_TAG}" \
              -Dsonar.qualitygate.wait=true \
              -Dsonar.qualitygate.timeout=600
          '''
        }
      }
    }

    stage('Dependency Scanning - npm audit') {
      when {
        expression { return params.ENABLE_OWASP_DC }
      }
      parallel {
        stage('Backend Dependencies') {
          steps {
            dir('backend') {
              sh '''
                set -euo pipefail
                npm audit --audit-level=high --json > ../reports/security/npm-audit-backend.json || true
                npm audit --audit-level=high
              '''
            }
          }
        }
        stage('Frontend Dependencies') {
          steps {
            dir('frontend') {
              sh '''
                set -euo pipefail
                npm audit --audit-level=high --json > ../reports/security/npm-audit-frontend.json || true
                npm audit --audit-level=high
              '''
            }
          }
        }
      }
    }

    stage('Secret Scan - Gitleaks') {
      when {
        expression { return params.ENABLE_GITLEAKS }
      }
      steps {
        sh '''
          set -euo pipefail
          docker run --rm \
            -u "$(id -u):$(id -g)" \
            -v "$PWD:/repo" \
            zricethezav/gitleaks:v8.24.2 detect \
            --source /repo \
            --no-git \
            --gitleaks-ignore-path /repo/.gitleaksignore \
            --redact \
            --no-banner \
            --report-format sarif \
            --report-path /repo/reports/security/gitleaks.sarif \
            --exit-code 1
        '''
      }
    }

    stage('Build Container Images') {
      steps {
        sh 'docker build -t "$BACKEND_IMAGE_URI" backend'
        sh 'docker build -t "$FRONTEND_IMAGE_URI" frontend'
      }
    }

    stage('Container Scan - Trivy') {
      when {
        expression { return params.ENABLE_TRIVY }
      }
      steps {
        sh '''
          set -euo pipefail

          docker run --rm \
            -v /var/run/docker.sock:/var/run/docker.sock \
            -v "$PWD:/work" \
            -v "$PWD/.trivycache:/root/.cache/trivy" \
            aquasec/trivy:0.58.1 image \
            --scanners vuln \
            --severity "${TRIVY_SEVERITIES}" \
            --ignore-unfixed \
            --exit-code 1 \
            --format json \
            --output /work/reports/security/trivy/backend-image.json \
            "${BACKEND_IMAGE_URI}"

          docker run --rm \
            -v /var/run/docker.sock:/var/run/docker.sock \
            -v "$PWD:/work" \
            -v "$PWD/.trivycache:/root/.cache/trivy" \
            aquasec/trivy:0.58.1 image \
            --scanners vuln \
            --severity "${TRIVY_SEVERITIES}" \
            --ignore-unfixed \
            --exit-code 1 \
            --format json \
            --output /work/reports/security/trivy/frontend-image.json \
            "${FRONTEND_IMAGE_URI}"
        '''
      }
    }

    stage('Generate SBOM - Syft') {
      when {
        expression { return params.ENABLE_SBOM }
      }
      steps {
        sh '''
          set -euo pipefail

          docker run --rm \
            -u "$(id -u):$(id -g)" \
            -v /var/run/docker.sock:/var/run/docker.sock \
            -v "$PWD:/work" \
            anchore/syft:v1.20.0 "${BACKEND_IMAGE_URI}" \
            -o cyclonedx-json=/work/reports/sbom/backend.cyclonedx.json

          docker run --rm \
            -u "$(id -u):$(id -g)" \
            -v /var/run/docker.sock:/var/run/docker.sock \
            -v "$PWD:/work" \
            anchore/syft:v1.20.0 "${FRONTEND_IMAGE_URI}" \
            -o cyclonedx-json=/work/reports/sbom/frontend.cyclonedx.json
        '''
      }
    }

    stage('Push Versioned Images to ECR') {
      steps {
        sh '''
          set -euo pipefail
          aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$ECR_REGISTRY"
          docker push "$BACKEND_IMAGE_URI"
          docker push "$FRONTEND_IMAGE_URI"
        '''
      }
    }

    stage('Tag Latest (main only)') {
      when {
        branch 'main'
      }
      steps {
        sh '''
          set -euo pipefail
          BACKEND_LATEST="${ECR_REGISTRY}/${BACKEND_ECR_REPO}:latest"
          FRONTEND_LATEST="${ECR_REGISTRY}/${FRONTEND_ECR_REPO}:latest"

          docker tag "$BACKEND_IMAGE_URI" "$BACKEND_LATEST"
          docker tag "$FRONTEND_IMAGE_URI" "$FRONTEND_LATEST"

          docker push "$BACKEND_LATEST"
          docker push "$FRONTEND_LATEST"
        '''
      }
    }

    stage('Render ECS Task Definition') {
      steps {
        script {
          def execRole = params.ECS_EXECUTION_ROLE_ARN?.trim()
          def taskRole = params.ECS_TASK_ROLE_ARN?.trim()

          if (!execRole || !taskRole) {
            def existingTaskDef = sh(
              script: "aws ecs describe-services --cluster '${params.ECS_CLUSTER_NAME}' --services '${params.ECS_SERVICE_NAME}' --query 'services[0].taskDefinition' --output text",
              returnStdout: true
            ).trim()

            if (existingTaskDef && existingTaskDef != 'None') {
              if (!execRole) {
                execRole = sh(
                  script: "aws ecs describe-task-definition --task-definition '${existingTaskDef}' --query 'taskDefinition.executionRoleArn' --output text",
                  returnStdout: true
                ).trim()
              }
              if (!taskRole) {
                taskRole = sh(
                  script: "aws ecs describe-task-definition --task-definition '${existingTaskDef}' --query 'taskDefinition.taskRoleArn' --output text",
                  returnStdout: true
                ).trim()
              }
            }
          }

          if (!execRole || execRole == 'None') {
            error('ECS execution role ARN is required. Set ECS_EXECUTION_ROLE_ARN or make sure the service already exists with a valid role.')
          }
          if (!taskRole || taskRole == 'None') {
            error('ECS task role ARN is required. Set ECS_TASK_ROLE_ARN or make sure the service already exists with a valid role.')
          }

          env.ECS_EXEC_ROLE_EFFECTIVE = execRole
          env.ECS_TASK_ROLE_EFFECTIVE = taskRole
        }

        sh '''
          set -euo pipefail

          escape_for_sed() {
            printf '%s' "$1" | sed -e 's/[\\/&]/\\\\&/g'
          }

          BACKEND_IMAGE_ESCAPED="$(escape_for_sed "$BACKEND_IMAGE_URI")"
          FRONTEND_IMAGE_ESCAPED="$(escape_for_sed "$FRONTEND_IMAGE_URI")"
          EXEC_ROLE_ESCAPED="$(escape_for_sed "$ECS_EXEC_ROLE_EFFECTIVE")"
          TASK_ROLE_ESCAPED="$(escape_for_sed "$ECS_TASK_ROLE_EFFECTIVE")"
          REGION_ESCAPED="$(escape_for_sed "$AWS_REGION")"
          FAMILY_ESCAPED="$(escape_for_sed "$ECS_TASK_FAMILY")"

          sed \
            -e "s/__TASK_FAMILY__/${FAMILY_ESCAPED}/g" \
            -e "s/__TASK_CPU__/${ECS_TASK_CPU}/g" \
            -e "s/__TASK_MEMORY__/${ECS_TASK_MEMORY}/g" \
            -e "s/__AWS_REGION__/${REGION_ESCAPED}/g" \
            -e "s/__EXECUTION_ROLE_ARN__/${EXEC_ROLE_ESCAPED}/g" \
            -e "s/__TASK_ROLE_ARN__/${TASK_ROLE_ESCAPED}/g" \
            -e "s/__BACKEND_IMAGE__/${BACKEND_IMAGE_ESCAPED}/g" \
            -e "s/__FRONTEND_IMAGE__/${FRONTEND_IMAGE_ESCAPED}/g" \
            -e "s#__BACKEND_LOG_GROUP__#${BACKEND_LOG_GROUP}#g" \
            -e "s#__FRONTEND_LOG_GROUP__#${FRONTEND_LOG_GROUP}#g" \
            -e "s/__BACKEND_CONTAINER_NAME__/${BACKEND_CONTAINER_NAME}/g" \
            -e "s/__FRONTEND_CONTAINER_NAME__/${FRONTEND_CONTAINER_NAME}/g" \
            "$TASKDEF_TEMPLATE" > "$ECS_REPORT_DIR/taskdef.rendered.json"

          cp "$ECS_REPORT_DIR/taskdef.rendered.json" ecs/taskdef.revision.json
        '''
      }
    }

    stage('Register ECS Task Definition Revision') {
      steps {
        script {
          env.NEW_TASK_DEF_ARN = sh(
            script: "aws ecs register-task-definition --cli-input-json file://${env.ECS_REPORT_DIR}/taskdef.rendered.json --query 'taskDefinition.taskDefinitionArn' --output text",
            returnStdout: true
          ).trim()
        }

        sh '''
          set -euo pipefail
          printf '%s\n' "$NEW_TASK_DEF_ARN" > "$ECS_REPORT_DIR/task-definition-arn.txt"
          aws ecs describe-task-definition --task-definition "$NEW_TASK_DEF_ARN" > "$ECS_REPORT_DIR/task-definition.revision.json"
        '''
      }
    }

    stage('Deploy to ECS Service') {
      when {
        anyOf {
          branch 'main'
          expression { return params.DEPLOY_FROM_NON_MAIN }
        }
      }
      steps {
        sh '''
          set -euo pipefail

          aws ecs update-service \
            --cluster "$ECS_CLUSTER_NAME" \
            --service "$ECS_SERVICE_NAME" \
            --task-definition "$NEW_TASK_DEF_ARN" \
            --force-new-deployment > "$ECS_REPORT_DIR/service-update.json"

          aws ecs wait services-stable \
            --cluster "$ECS_CLUSTER_NAME" \
            --services "$ECS_SERVICE_NAME"

          aws ecs describe-services \
            --cluster "$ECS_CLUSTER_NAME" \
            --services "$ECS_SERVICE_NAME" > "$ECS_REPORT_DIR/service-after-update.json"
        '''
      }
    }

    stage('Post-Deploy Cleanup') {
      when {
        anyOf {
          branch 'main'
          expression { return params.DEPLOY_FROM_NON_MAIN }
        }
      }
      steps {
        sh '''
          set -euo pipefail

          cat > "$ECS_REPORT_DIR/ecr-lifecycle-policy.json" <<POLICY
{
  "rules": [
    {
      "rulePriority": 1,
      "description": "Keep only the latest ${ECR_LIFECYCLE_MAX_IMAGES} images",
      "selection": {
        "tagStatus": "any",
        "countType": "imageCountMoreThan",
        "countNumber": ${ECR_LIFECYCLE_MAX_IMAGES}
      },
      "action": {
        "type": "expire"
      }
    }
  ]
}
POLICY

          aws ecr put-lifecycle-policy \
            --repository-name "$BACKEND_ECR_REPO" \
            --lifecycle-policy-text "$(cat "$ECS_REPORT_DIR/ecr-lifecycle-policy.json")" > "$ECS_REPORT_DIR/ecr-lifecycle-backend.json"

          aws ecr put-lifecycle-policy \
            --repository-name "$FRONTEND_ECR_REPO" \
            --lifecycle-policy-text "$(cat "$ECS_REPORT_DIR/ecr-lifecycle-policy.json")" > "$ECS_REPORT_DIR/ecr-lifecycle-frontend.json"

          KEEP="${ECS_TASKDEF_KEEP_REVISIONS}"
          aws ecs list-task-definitions \
            --family-prefix "$ECS_TASK_FAMILY" \
            --sort DESC \
            --query 'taskDefinitionArns[]' \
            --output text | tr '\t' '\n' > "$ECS_REPORT_DIR/task-definition-list.txt"

          tail -n +$((KEEP + 1)) "$ECS_REPORT_DIR/task-definition-list.txt" > "$ECS_REPORT_DIR/task-definition-prune-list.txt" || true

          if [ -s "$ECS_REPORT_DIR/task-definition-prune-list.txt" ]; then
            while IFS= read -r task_def_arn; do
              [ -z "$task_def_arn" ] && continue
              aws ecs deregister-task-definition --task-definition "$task_def_arn" >> "$ECS_REPORT_DIR/task-definition-pruned.jsonl"
            done < "$ECS_REPORT_DIR/task-definition-prune-list.txt"
          fi
        '''
      }
    }

    stage('Docker Cleanup') {
      steps {
        sh 'docker image prune -f --filter "dangling=true" || true'
      }
    }
  }

  post {
    always {
      archiveArtifacts artifacts: 'reports/**/*', fingerprint: true, allowEmptyArchive: true
      echo "Build result: ${currentBuild.currentResult}"
    }
    success {
      echo "Image tag: ${env.IMAGE_TAG}"
      echo "Backend image: ${env.BACKEND_IMAGE_URI}"
      echo "Frontend image: ${env.FRONTEND_IMAGE_URI}"
      echo "Task definition ARN: ${env.NEW_TASK_DEF_ARN ?: 'N/A'}"
      echo "ECS evidence file: reports/ecs/service-after-update.json"
    }
  }
}
