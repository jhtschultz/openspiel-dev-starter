#!/bin/bash
# GCP VM Startup Script
# This runs automatically when the VM boots
# Installs Docker and pulls your dev image

set -e

# Log everything
exec > >(tee /var/log/startup-script.log) 2>&1
echo "==> Startup script beginning at $(date)"

# Install Docker
if ! command -v docker &> /dev/null; then
    echo "==> Installing Docker..."
    apt-get update
    apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
    
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
fi

# Configure Docker for current user
MAIN_USER=$(getent passwd 1000 | cut -d: -f1)
if [ -n "$MAIN_USER" ]; then
    usermod -aG docker "$MAIN_USER"
fi

# Authenticate with GCR
echo "==> Configuring Docker for GCR..."
gcloud auth configure-docker --quiet

# Pull dev image (project ID passed via VM metadata)
PROJECT_ID=$(curl -s "http://metadata.google.internal/computeMetadata/v1/project/project-id" -H "Metadata-Flavor: Google")
echo "==> Pulling dev image for project: $PROJECT_ID"
docker pull gcr.io/$PROJECT_ID/openspiel-dev:latest || echo "Image not found - run 'make push' locally first"

# Install common tools
echo "==> Installing development tools..."
apt-get install -y \
    vim \
    tmux \
    htop \
    git \
    make

# Create workspace directory and clone OpenSpiel
echo "==> Setting up workspace..."
mkdir -p /home/$MAIN_USER/workspace
cd /home/$MAIN_USER/workspace

if [ ! -d "open_spiel" ]; then
    echo "==> Cloning OpenSpiel..."
    sudo -u $MAIN_USER git clone https://github.com/google-deepmind/open_spiel.git open_spiel
fi

chown -R $MAIN_USER:$MAIN_USER /home/$MAIN_USER/workspace

echo "==> Startup script completed at $(date)"
echo "==> Run 'make gcp-setup' locally to finish setup, then 'make gcp-dev' to start working"
