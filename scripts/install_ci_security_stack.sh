#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo bash $0" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PLUGINS_FILE="${PLUGINS_FILE:-${REPO_ROOT}/jenkins/plugins.txt}"

AWS_REGION="${AWS_REGION:-eu-west-1}"
NODE_MAJOR="${NODE_MAJOR:-20}"
JENKINS_XMS="${JENKINS_XMS:-256m}"
JENKINS_XMX="${JENKINS_XMX:-512m}"

INSTALL_SONARQUBE="${INSTALL_SONARQUBE:-true}"
FORCE_LOW_MEM_SONARQUBE="${FORCE_LOW_MEM_SONARQUBE:-false}"
SONARQUBE_VERSION="${SONARQUBE_VERSION:-lts-community}"
SONARQUBE_PORT="${SONARQUBE_PORT:-9000}"
MIN_SONAR_MEM_KIB="${MIN_SONAR_MEM_KIB:-3500000}"

GITLEAKS_VERSION="${GITLEAKS_VERSION:-8.24.2}"
SYFT_VERSION="${SYFT_VERSION:-1.20.0}"
TRIVY_VERSION="${TRIVY_VERSION:-0.58.1}"
JENKINS_RPM_REPO_URL="${JENKINS_RPM_REPO_URL:-https://pkg.jenkins.io/rpm-stable}"
JENKINS_RPM_KEY_URL_PRIMARY="${JENKINS_RPM_KEY_URL_PRIMARY:-https://pkg.jenkins.io/rpm-stable/jenkins.io-2026.key}"
JENKINS_RPM_KEY_URL_LEGACY="${JENKINS_RPM_KEY_URL_LEGACY:-https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key}"

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Required command not found: ${cmd}" >&2
    exit 1
  fi
}

arch_name() {
  local machine
  machine="$(uname -m)"
  case "$machine" in
    x86_64) echo "amd64" ;;
    aarch64) echo "arm64" ;;
    *)
      echo "Unsupported architecture: ${machine}" >&2
      exit 1
      ;;
  esac
}

install_core_packages() {
  log "Updating OS packages"
  dnf -y update

  log "Installing core packages"
  dnf install -y \
    git \
    jq \
    unzip \
    tar \
    wget \
    docker \
    awscli \
    java-21-amazon-corretto-headless \
    dnf-plugins-core
}

install_node() {
  if command -v node >/dev/null 2>&1; then
    local major
    major="$(node -v | sed -E 's/^v([0-9]+).*/\1/')"
    if [[ "$major" == "$NODE_MAJOR" ]]; then
      log "Node.js ${NODE_MAJOR} already installed"
      return
    fi
  fi

  log "Installing Node.js ${NODE_MAJOR}"
  curl -fsSL "https://rpm.nodesource.com/setup_${NODE_MAJOR}.x" | bash -
  dnf install -y nodejs
}

install_terraform() {
  if command -v terraform >/dev/null 2>&1; then
    log "Terraform already installed: $(terraform version | head -n1)"
    return
  fi

  log "Installing Terraform"
  if [[ ! -f /etc/yum.repos.d/hashicorp.repo ]]; then
    dnf config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
  fi
  dnf install -y terraform
}

install_jenkins() {
  if ! rpm -q jenkins >/dev/null 2>&1; then
    log "Installing Jenkins LTS"
    rpm --import "${JENKINS_RPM_KEY_URL_PRIMARY}"
    rpm --import "${JENKINS_RPM_KEY_URL_LEGACY}" || true

    cat >/etc/yum.repos.d/jenkins.repo <<JENKINS_REPO
[jenkins]
name=Jenkins-stable
baseurl=${JENKINS_RPM_REPO_URL}
gpgcheck=1
repo_gpgcheck=0
enabled=1
gpgkey=${JENKINS_RPM_KEY_URL_PRIMARY} ${JENKINS_RPM_KEY_URL_LEGACY}
JENKINS_REPO

    dnf clean all
    rm -rf /var/cache/dnf
    dnf makecache --refresh || true
    dnf install -y --refresh jenkins
  else
    log "Jenkins already installed"
  fi

  mkdir -p /etc/systemd/system/jenkins.service.d
  cat >/etc/systemd/system/jenkins.service.d/override.conf <<JENKINS_OVERRIDE
[Service]
Environment="JENKINS_JAVA_OPTIONS=-Djava.awt.headless=true -Xms${JENKINS_XMS} -Xmx${JENKINS_XMX}"
JENKINS_OVERRIDE

  systemctl daemon-reload
  systemctl enable --now jenkins

  mkdir -p /var/lib/jenkins/workspace
  chown -R jenkins:jenkins /var/lib/jenkins

  if [[ -f "$PLUGINS_FILE" ]] && command -v jenkins-plugin-cli >/dev/null 2>&1; then
    log "Installing Jenkins plugins from ${PLUGINS_FILE}"
    jenkins-plugin-cli --plugin-file "$PLUGINS_FILE"
    systemctl restart jenkins
  fi
}

configure_docker() {
  log "Configuring Docker"
  systemctl enable --now docker
  usermod -aG docker ec2-user || true
  usermod -aG docker jenkins || true
}

install_trivy() {
  if command -v trivy >/dev/null 2>&1; then
    log "Trivy already installed: $(trivy --version | head -n1)"
    return
  fi

  log "Installing Trivy from rpm repository"
  cat >/etc/yum.repos.d/trivy.repo <<'TRIVY_REPO'
[trivy]
name=Trivy repository
baseurl=https://aquasecurity.github.io/trivy-repo/rpm/releases/$basearch/
gpgcheck=1
enabled=1
gpgkey=https://aquasecurity.github.io/trivy-repo/rpm/public.key
TRIVY_REPO
  rpm --import https://aquasecurity.github.io/trivy-repo/rpm/public.key

  if dnf install -y trivy; then
    return
  fi

  log "Trivy rpm install failed, falling back to binary install"
  local machine file url
  machine="$(uname -m)"
  case "$machine" in
    x86_64) file="trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz" ;;
    aarch64) file="trivy_${TRIVY_VERSION}_Linux-ARM64.tar.gz" ;;
    *)
      echo "Unsupported architecture for Trivy fallback: ${machine}" >&2
      exit 1
      ;;
  esac
  url="https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/${file}"
  curl -fsSL "$url" -o "/tmp/${file}"
  tar -xzf "/tmp/${file}" -C /tmp trivy
  install -m 0755 /tmp/trivy /usr/local/bin/trivy
  rm -f "/tmp/${file}" /tmp/trivy
}

install_gitleaks() {
  if command -v gitleaks >/dev/null 2>&1; then
    log "Gitleaks already installed: $(gitleaks version | head -n1)"
    return
  fi

  local arch file url
  arch="$(arch_name)"
  if [[ "$arch" == "amd64" ]]; then
    file="gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz"
  else
    file="gitleaks_${GITLEAKS_VERSION}_linux_arm64.tar.gz"
  fi
  url="https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/${file}"

  log "Installing Gitleaks v${GITLEAKS_VERSION}"
  curl -fsSL "$url" -o "/tmp/${file}"
  tar -xzf "/tmp/${file}" -C /tmp gitleaks
  install -m 0755 /tmp/gitleaks /usr/local/bin/gitleaks
  rm -f "/tmp/${file}" /tmp/gitleaks
}

install_syft() {
  if command -v syft >/dev/null 2>&1; then
    log "Syft already installed: $(syft version | head -n1)"
    return
  fi

  local arch file url
  arch="$(arch_name)"
  file="syft_${SYFT_VERSION}_linux_${arch}.tar.gz"
  url="https://github.com/anchore/syft/releases/download/v${SYFT_VERSION}/${file}"

  log "Installing Syft v${SYFT_VERSION}"
  curl -fsSL "$url" -o "/tmp/${file}"
  tar -xzf "/tmp/${file}" -C /tmp syft
  install -m 0755 /tmp/syft /usr/local/bin/syft
  rm -f "/tmp/${file}" /tmp/syft
}

install_sonarqube() {
  if [[ "${INSTALL_SONARQUBE}" != "true" ]]; then
    log "Skipping SonarQube installation (INSTALL_SONARQUBE=${INSTALL_SONARQUBE})"
    return
  fi

  local mem_kib
  mem_kib="$(awk '/MemTotal/ {print $2}' /proc/meminfo)"
  if (( mem_kib < MIN_SONAR_MEM_KIB )) && [[ "${FORCE_LOW_MEM_SONARQUBE}" != "true" ]]; then
    log "Skipping SonarQube: low memory detected (${mem_kib} KiB)."
    log "Set FORCE_LOW_MEM_SONARQUBE=true to force install, or use your existing external SonarQube instance."
    return
  fi

  log "Installing SonarQube (${SONARQUBE_VERSION}) via Docker"

  mkdir -p /opt/sonarqube/{data,extensions,logs}
  chown -R 1000:1000 /opt/sonarqube || true

  docker rm -f sonarqube >/dev/null 2>&1 || true
  docker run -d \
    --name sonarqube \
    --restart unless-stopped \
    -p "${SONARQUBE_PORT}:9000" \
    -e SONAR_ES_BOOTSTRAP_CHECKS_DISABLE=true \
    -e SONAR_WEB_JAVAOPTS="-Xms256m -Xmx512m" \
    -e SONAR_CE_JAVAOPTS="-Xms256m -Xmx512m" \
    -e SONAR_SEARCH_JAVAOPTS="-Xms256m -Xmx256m" \
    -v /opt/sonarqube/data:/opt/sonarqube/data \
    -v /opt/sonarqube/extensions:/opt/sonarqube/extensions \
    -v /opt/sonarqube/logs:/opt/sonarqube/logs \
    "sonarqube:${SONARQUBE_VERSION}"
}

write_motd() {
  cat >/etc/motd <<MOTD
CI/CD host bootstrap complete.
- Jenkins:    http://<this-instance-public-ip>:8080
- SonarQube:  http://<this-instance-public-ip>:${SONARQUBE_PORT} (if installed)
- Jenkins initial admin password:
  sudo cat /var/lib/jenkins/secrets/initialAdminPassword
MOTD
}

health_summary() {
  log "Health summary"
  systemctl is-active jenkins docker || true
  docker --version || true
  java -version || true
  node --version || true
  npm --version || true
  aws --version || true
  terraform version | head -n1 || true
  trivy --version || true
  gitleaks version || true
  syft version || true

  if docker ps --format '{{.Names}}' | grep -qx sonarqube; then
    log "SonarQube container is running"
  else
    log "SonarQube container is not running"
  fi

  log "Jenkins initial admin password command: sudo cat /var/lib/jenkins/secrets/initialAdminPassword"
}

main() {
  require_cmd dnf
  require_cmd systemctl
  require_cmd curl

  log "Starting CI/security stack setup in region ${AWS_REGION}"

  install_core_packages
  configure_docker
  install_node
  install_terraform
  install_jenkins
  install_trivy
  install_gitleaks
  install_syft
  install_sonarqube
  write_motd
  health_summary

  log "Setup complete"
}

main "$@"
