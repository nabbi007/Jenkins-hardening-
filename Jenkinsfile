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

  // Feature flags only — these make sense as per-build toggles
  parameters {
    booleanParam(name: 'ENABLE_SONARQUBE',     defaultValue: true,  description: 'Run SonarQube SAST')
    booleanParam(name: 'ENABLE_NPM_AUDIT',     defaultValue: true,  description: 'Run npm audit SCA')
    booleanParam(name: 'ENABLE_GITLEAKS',      defaultValue: true,  description: 'Run Gitleaks secret scan')
    booleanParam(name: 'ENABLE_TRIVY',         defaultValue: true,  description: 'Run Trivy image scan')
    booleanParam(name: 'ENABLE_SBOM',          defaultValue: true,  description: 'Generate SBOM using Syft')
    booleanParam(name: 'DEPLOY_FROM_NON_MAIN', defaultValue: false, description: 'Allow deploy from non-main branches')
  }

  environment {
    // Loaded from Jenkins Global Env Vars — no values here
    REPORT_DIR             = 'reports/security'
    SBOM_DIR               = 'reports/sbom'
    ECS_REPORT_DIR         = 'reports/ecs'
    TASKDEF_TEMPLATE       = 'ecs/taskdef.template.json'
    BACKEND_CONTAINER_NAME = 'backend'
    FRONTEND_CONTAINER_NAME= 'frontend'

    // Secrets from Jenkins Credentials
    ECS_EXECUTION_ROLE_ARN = credentials('ecs-execution-role-arn')
    ECS_TASK_ROLE_ARN      = credentials('ecs-task-role-arn')
  }

  stages {
    stage('Checkout') {
      steps { checkout scm }
    }

    stage('Prepare Build Metadata') {
      steps {
        script {
          env.GIT_SHA     = sh(script: 'git rev-parse --short=8 HEAD', returnStdout: true).trim()
          env.SAFE_BRANCH = (env.BRANCH_NAME ?: 'detached').replaceAll('[^a-zA-Z0-9_.-]', '-')
          env.IMAGE_TAG   = "${env.SAFE_BRANCH}-${env.GIT_SHA}-${env.BUILD_NUMBER}"

          env.ECR_ACCOUNT_ID_EFFECTIVE = sh(
            script: 'aws sts get-caller-identity --query Account --output text',
            returnStdout: true
          ).trim()

          if (!env.ECR_ACCOUNT_ID_EFFECTIVE) {
            error('Unable to determine AWS account ID. Ensure Jenkins IAM role has sts:GetCallerIdentity permission.')
          }

          env.ECR_REGISTRY      = "${env.ECR_ACCOUNT_ID_EFFECTIVE}.dkr.ecr.${env.AWS_REGION}.amazonaws.com"
          env.BACKEND_IMAGE_URI = "${env.ECR_REGISTRY}/${env.BACKEND_ECR_REPO}:${env.IMAGE_TAG}"
          env.FRONTEND_IMAGE_URI= "${env.ECR_REGISTRY}/${env.FRONTEND_ECR_REPO}:${env.IMAGE_TAG}"

          sh 'mkdir -p reports/security reports/security/trivy reports/sbom reports/ecs .trivycache'
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

    stage('Security Scans') {
      parallel {
        stage('SAST - SonarQube') {
          when { expression { return params.ENABLE_SONARQUBE } }
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

        stage('SCA - npm audit') {
          when { expression { return params.ENABLE_NPM_AUDIT } }
          steps {
            sh '''
              set -euo pipefail
              cd backend
              npm audit --audit-level=high --json > ../reports/security/npm-audit-backend.json || true
              npm audit --audit-level=high
              cd ../frontend
              npm audit --audit-level=high --json > ../reports/security/npm-audit-frontend.json || true
              npm audit --audit-level=high
            '''
          }
        }

        stage('Secrets - Gitleaks') {
          when { expression { return params.ENABLE_GITLEAKS } }
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
      }
    }

    stage('Build Container Images') {
      steps {
        sh 'docker build -t "$BACKEND_IMAGE_URI" backend'
        sh 'docker build -t "$FRONTEND_IMAGE_URI" frontend'
      }
    }

    stage('Post-Build Scans') {
      parallel {
        stage('Container Scan - Trivy') {
          when { expression { return params.ENABLE_TRIVY } }
          steps {
            sh '''
              set -euo pipefail
              for IMAGE_URI in "$BACKEND_IMAGE_URI" "$FRONTEND_IMAGE_URI"; do
                NAME=$(echo "$IMAGE_URI" | awk -F/ '{print $NF}' | cut -d: -f1)
                docker run --rm \
                  -v /var/run/docker.sock:/var/run/docker.sock \
                  -v "$PWD/.trivycache:/root/.cache/trivy" \
                  -e TRIVY_CACHE_DIR=/root/.cache/trivy \
                  aquasec/trivy:0.58.1 image \
                  --scanners vuln \
                  --severity "${TRIVY_SEVERITIES}" \
                  --ignore-unfixed \
                  --exit-code 1 \
                  --format json \
                  --output "/work/reports/security/trivy/${NAME}.json" \
                  "$IMAGE_URI"
              done
            '''
          }
        }

        stage('SBOM - Syft') {
          when { expression { return params.ENABLE_SBOM } }
          steps {
            sh '''
              set -euo pipefail
              for IMAGE_URI in "$BACKEND_IMAGE_URI" "$FRONTEND_IMAGE_URI"; do
                NAME=$(echo "$IMAGE_URI" | awk -F/ '{print $NF}' | cut -d: -f1)
                docker run --rm \
                  -u "$(id -u):$(id -g)" \
                  -v /var/run/docker.sock:/var/run/docker.sock \
                  -v "$PWD:/work" \
                  anchore/syft:v1.20.0 "$IMAGE_URI" \
                  -o cyclonedx-json=/work/reports/sbom/${NAME}.cyclonedx.json
              done
            '''
          }
        }
      }
    }

    stage('Push to ECR') {
      steps {
        sh '''
          set -euo pipefail
          aws ecr get-login-password --region "$AWS_REGION" | \
            docker login --username AWS --password-stdin "$ECR_REGISTRY"
          docker push "$BACKEND_IMAGE_URI"
          docker push "$FRONTEND_IMAGE_URI"
        '''
      }
    }

    stage('Tag Latest') {
      when { branch 'main' }
      steps {
        sh '''
          set -euo pipefail
          docker tag "$BACKEND_IMAGE_URI"  "${ECR_REGISTRY}/${BACKEND_ECR_REPO}:latest"
          docker tag "$FRONTEND_IMAGE_URI" "${ECR_REGISTRY}/${FRONTEND_ECR_REPO}:latest"
          docker push "${ECR_REGISTRY}/${BACKEND_ECR_REPO}:latest"
          docker push "${ECR_REGISTRY}/${FRONTEND_ECR_REPO}:latest"
        '''
      }
    }

    stage('Render & Register ECS Task Definition') {
      steps {
        sh '''
          set -euo pipefail

          escape_for_sed() { printf '%s' "$1" | sed -e 's/[\\/&]/\\\\&/g'; }

          sed \
            -e "s/__TASK_FAMILY__/$(escape_for_sed "$ECS_TASK_FAMILY")/g" \
            -e "s/__TASK_CPU__/${ECS_TASK_CPU}/g" \
            -e "s/__TASK_MEMORY__/${ECS_TASK_MEMORY}/g" \
            -e "s/__AWS_REGION__/$(escape_for_sed "$AWS_REGION")/g" \
            -e "s/__EXECUTION_ROLE_ARN__/$(escape_for_sed "$ECS_EXECUTION_ROLE_ARN")/g" \
            -e "s/__TASK_ROLE_ARN__/$(escape_for_sed "$ECS_TASK_ROLE_ARN")/g" \
            -e "s/__BACKEND_IMAGE__/$(escape_for_sed "$BACKEND_IMAGE_URI")/g" \
            -e "s/__FRONTEND_IMAGE__/$(escape_for_sed "$FRONTEND_IMAGE_URI")/g" \
            -e "s#__BACKEND_LOG_GROUP__#${BACKEND_LOG_GROUP}#g" \
            -e "s#__FRONTEND_LOG_GROUP__#${FRONTEND_LOG_GROUP}#g" \
            -e "s/__BACKEND_CONTAINER_NAME__/${BACKEND_CONTAINER_NAME}/g" \
            -e "s/__FRONTEND_CONTAINER_NAME__/${FRONTEND_CONTAINER_NAME}/g" \
            "$TASKDEF_TEMPLATE" > "$ECS_REPORT_DIR/taskdef.rendered.json"
        '''
        script {
          env.NEW_TASK_DEF_ARN = sh(
            script: "aws ecs register-task-definition --cli-input-json file://${env.ECS_REPORT_DIR}/taskdef.rendered.json --query 'taskDefinition.taskDefinitionArn' --output text",
            returnStdout: true
          ).trim()
          sh "echo '${env.NEW_TASK_DEF_ARN}' > ${env.ECS_REPORT_DIR}/task-definition-arn.txt"
        }
      }
    }

    stage('Deploy to ECS') {
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

          POLICY=$(printf '{"rules":[{"rulePriority":1,"description":"Keep latest %s","selection":{"tagStatus":"any","countType":"imageCountMoreThan","countNumber":%s},"action":{"type":"expire"}}]}' \
            "$ECR_LIFECYCLE_MAX_IMAGES" "$ECR_LIFECYCLE_MAX_IMAGES")

          aws ecr put-lifecycle-policy --repository-name "$BACKEND_ECR_REPO"  --lifecycle-policy-text "$POLICY"
          aws ecr put-lifecycle-policy --repository-name "$FRONTEND_ECR_REPO" --lifecycle-policy-text "$POLICY"

          aws ecs list-task-definitions \
            --family-prefix "$ECS_TASK_FAMILY" \
            --sort DESC --query 'taskDefinitionArns[]' --output text \
            | tr '\t' '\n' \
            | tail -n +$((ECS_TASKDEF_KEEP_REVISIONS + 1)) \
            | while IFS= read -r arn; do
                [ -z "$arn" ] && continue
                aws ecs deregister-task-definition --task-definition "$arn"
              done
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
      echo "Backend:   ${env.BACKEND_IMAGE_URI}"
      echo "Frontend:  ${env.FRONTEND_IMAGE_URI}"
      echo "Task ARN:  ${env.NEW_TASK_DEF_ARN ?: 'N/A'}"
    }
  }
}