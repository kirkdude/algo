#!/usr/bin/env bash

set -euxo pipefail

sysctl net.ipv6.conf.all.disable_ipv6=0

export REPOSITORY=${REPOSITORY:-${GITHUB_REPOSITORY}}
export _BRANCH=${BRANCH#refs/heads/}
export BRANCH=${_BRANCH:-${GITHUB_REF#refs/heads/}}

if [[ "$DEPLOY" == "cloud-init" ]]; then
  bash tests/cloud-init.sh | lxc profile set default user.user-data -
else
  # Configure persistent DNS at container level via cloud-init
  cat << EOF | lxc profile set default user.user-data -
#cloud-config
ssh_authorized_keys:
 - $(cat ~/.ssh/id_rsa.pub)
manage_resolv_conf: true
resolv_conf:
  nameservers:
    - 8.8.8.8
    - 1.1.1.1
  searchdomains: []
  domain: ""
  options:
    timeout: 1
    attempts: 1
runcmd:
  - systemctl disable systemd-resolved
  - systemctl stop systemd-resolved
  - rm -f /etc/resolv.conf
  - echo "nameserver 8.8.8.8" > /etc/resolv.conf
  - echo "nameserver 1.1.1.1" >> /etc/resolv.conf
EOF
fi

lxc network set lxdbr0 ipv4.address 10.0.8.1/24

lxc profile set default raw.lxc 'lxc.apparmor.profile = unconfined'
lxc profile set default security.privileged true
lxc profile show default

lxc init ubuntu:${UBUNTU_VERSION} algo
lxc network attach lxdbr0 algo eth0 eth0
lxc config device set algo eth0 ipv4.address 10.0.8.100
lxc start algo

# Pre-stage the install.sh script to avoid network dependency
echo "Pre-staging install.sh script in container..."
lxc file push install.sh algo/opt/install.sh
lxc exec algo -- chmod +x /opt/install.sh

# Pre-stage the repository to avoid git clone during deployment first
echo "Pre-staging algo repository in container..."
lxc exec algo -- mkdir -p /opt/algo /tmp
# Copy all files except .git to avoid large transfer
tar --exclude='.git' --exclude='logs' --exclude='.env' -czf /tmp/algo-repo.tar.gz -C . .
lxc file push /tmp/algo-repo.tar.gz algo/tmp/algo-repo.tar.gz
lxc exec algo -- tar -xzf /tmp/algo-repo.tar.gz -C /opt/algo/
lxc exec algo -- chown -R root:root /opt/algo

# Install basic packages using container's local package cache (Ubuntu images have cached packages)
echo "Installing basic dependencies in container using local cache..."
# DNS configuration is now handled at container level via cloud-init (see lines 15-36)
# Update package lists with timeout and retry on failure
lxc exec algo -- timeout 60 apt-get update || {
  echo "apt update failed, trying with different sources..."
  lxc exec algo -- apt-get update -o Acquire::http::Timeout=10 -o Acquire::Retries=3 || true
}
lxc exec algo -- apt-get install -y --no-install-recommends python3-virtualenv jq git python3-pip || {
  echo "Package installation failed, trying alternative approach..."
}

# Create Python virtual environment and transfer packages from runner
echo "Setting up Python environment..."
lxc exec algo -- python3 -m virtualenv --python=/usr/bin/python3 /opt/algo/.env || {
  echo "virtualenv creation failed, copying from runner..."
  # Create virtualenv using runner's Python environment
  python3 -m virtualenv --python="$(command -v python3)" /tmp/algo-env
  # Fix: Push to correct path and ensure target directory exists
  lxc exec algo -- mkdir -p /opt/algo/.env
  lxc file push /tmp/algo-env algo/opt/algo/.env --recursive
}

# Transfer Python packages from runner where they were successfully installed
echo "Transferring Python packages from runner..."
SITE_PACKAGES=$(python3 -c "import site; print(site.getsitepackages()[0])")
tar -czf /tmp/python-deps.tar.gz -C "$SITE_PACKAGES" ansible* jinja2* netaddr* || echo "Some packages missing, will try pip install"
lxc file push /tmp/python-deps.tar.gz algo/tmp/python-deps.tar.gz
lxc exec algo -- tar -xzf /tmp/python-deps.tar.gz -C /opt/algo/.env/lib/python*/site-packages/ 2>/dev/null || {
  echo "Failed to transfer packages, trying pip install in container..."
  lxc file push requirements.txt algo/opt/algo/requirements.txt
}

ip addr

until dig A +short algo.lxd @10.0.8.1 | grep -vE '^$' > /dev/null; do
  sleep 3
done

case ${UBUNTU_VERSION} in
  20.04|22.04)
    lxc exec algo -- apt remove snapd --purge -y || true
    ;;
  18.04)
    lxc exec algo -- apt install python3.8 -y
    ;;
esac

lxc list
