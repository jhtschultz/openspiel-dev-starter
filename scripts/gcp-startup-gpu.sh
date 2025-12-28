#!/bin/bash
# GCP GPU VM Startup Script
# Installs NVIDIA drivers, CUDA, JAX, and Claude Code

set -e

exec > >(tee /var/log/startup-script.log) 2>&1
echo "==> GPU startup script beginning at $(date)"

# Get the main user (first non-root user with a home directory, or ubuntu as fallback)
MAIN_USER=$(ls /home | grep -v '^lost+found$' | head -1)
[ -z "$MAIN_USER" ] && MAIN_USER="ubuntu"
WORKSPACE="/home/$MAIN_USER/workspace"

# Install NVIDIA drivers
echo "==> Installing NVIDIA drivers..."
apt-get update
apt-get install -y linux-headers-$(uname -r)

# Add NVIDIA package repository
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

apt-get update
apt-get install -y nvidia-driver-535 nvidia-utils-535

# Install CUDA toolkit
echo "==> Installing CUDA..."
apt-get install -y nvidia-cuda-toolkit

# Install Docker
echo "==> Installing Docker..."
apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Install NVIDIA Container Toolkit (for Docker GPU access)
apt-get install -y nvidia-container-toolkit
nvidia-ctk runtime configure --runtime=docker
systemctl restart docker

# Add user to docker group
usermod -aG docker "$MAIN_USER"

# Install Node.js (for Claude Code)
echo "==> Installing Node.js..."
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs

# Install Claude Code
echo "==> Installing Claude Code..."
npm install -g @anthropic-ai/claude-code

# Install Python and JAX
echo "==> Installing Python and JAX..."
apt-get install -y python3-pip python3-venv

# Create workspace and install JAX with GPU
mkdir -p "$WORKSPACE"
chown $MAIN_USER:$MAIN_USER "$WORKSPACE"

sudo -u $MAIN_USER bash << 'USERSCRIPT'
cd ~/workspace
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install jax[cuda12] jaxlib
pip install numpy matplotlib ipython
USERSCRIPT

# Install dev tools
echo "==> Installing dev tools..."
apt-get install -y vim tmux htop git make

# Configure git (user will need to set their own name/email)
sudo -u $MAIN_USER git config --global init.defaultBranch main

echo "==> GPU startup script completed at $(date)"
echo ""
echo "==> Next steps:"
echo "    1. SSH in: make gcp-ssh-gpu"
echo "    2. Verify GPU: nvidia-smi"
echo "    3. Activate venv: source ~/workspace/venv/bin/activate"
echo "    4. Run Claude: claude"
echo ""
