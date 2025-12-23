# OpenSpiel Development Environment

A portable, reproducible development setup for OpenSpiel that works locally and on GCP.

## Quick Start

```bash
# 1. Edit the Makefile - set your GCP project ID
vim Makefile  # Change YOUR_GCP_PROJECT

# 2. First-time setup (clones OpenSpiel, builds images)
make setup

# 3. Start developing
make dev
```

## What's in the Box

```
.
├── Makefile                 # All commands live here
├── docker-compose.yml       # Local dev orchestration
├── docker/
│   ├── Dockerfile.base      # Your personal tooling (vim, tmux, dotfiles)
│   └── Dockerfile.openspiel # OpenSpiel + dependencies
├── scripts/
│   └── gcp-startup.sh       # VM initialization script
├── open_spiel/              # OpenSpiel source (created by make setup)
└── experiments/             # Your experiment scripts
```

## Daily Workflow

### Local Development

```bash
# Start environment
make dev

# You're now in a container with OpenSpiel ready
# Build it (first time is slow, then incremental):
cd /home/dev/open_spiel
./open_spiel/scripts/build_and_run_tests.sh

# Or for faster iteration without tests:
make build-fast

# Exit and stop
exit
make stop
```

### On GCP

```bash
# Create a VM
make gcp-create

# SSH in (wait a minute for startup script)
make gcp-ssh

# On the VM - pull your image and work
docker pull gcr.io/YOUR_PROJECT/openspiel-dev:latest
docker run -it -v $(pwd):/workspace gcr.io/YOUR_PROJECT/openspiel-dev:latest

# When done - STOP (not delete) to save money but keep state
make gcp-stop

# Resume later
make gcp-start
make gcp-ssh

# Fully done? Delete it
make gcp-delete
```

### Running Experiments

```bash
# Run a one-off experiment on Cloud Run
make run-experiment SCRIPT=experiments/my_experiment.py
```

## Customization

### Your Dotfiles

Edit `docker/Dockerfile.base` to include your personal setup:

```dockerfile
# Option 1: Clone from your dotfiles repo
RUN git clone https://github.com/YOU/dotfiles.git ~/.dotfiles && \
    ~/.dotfiles/install.sh

# Option 2: Copy directly
COPY dotfiles/.vimrc /home/dev/.vimrc
COPY dotfiles/.tmux.conf /home/dev/.tmux.conf
```

Then rebuild:

```bash
make build-base
make build-image
make push  # So GCP VMs can pull it
```

### Build Cache

The docker-compose setup uses a named volume for `/home/dev/open_spiel/build`. 
This means:
- First build: ~20-30 minutes
- Subsequent builds: Only recompiles what changed
- Survives `docker compose down` 
- To force full rebuild: `make clean`

### Different Machine Types

Edit the Makefile:

```makefile
# For more CPU (faster builds)
MACHINE_TYPE := n1-standard-16

# For more RAM (large experiments)  
MACHINE_TYPE := n1-highmem-8

# For GPU work
MACHINE_TYPE := n1-standard-8-nvidia-tesla-t4
```

## Architecture Notes

If you switch between x86 (most GCP instances, Intel/AMD locally) and ARM (M-series Mac, GCP Tau T2A):

1. Rebuild images for the new architecture
2. Tag appropriately: `openspiel-dev:x86` vs `openspiel-dev:arm64`
3. The build cache volume is NOT portable across architectures

For now, recommend sticking to x86 for consistency.

## Troubleshooting

**Build fails with OOM**: Increase VM memory or add swap
```bash
sudo fallocate -l 8G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

**Container can't find built libraries**: Make sure PYTHONPATH is set
```bash
export PYTHONPATH=/home/dev/open_spiel/build/python:/home/dev/open_spiel:$PYTHONPATH
```

**GCP auth issues**: Re-authenticate
```bash
gcloud auth login
gcloud auth configure-docker
```

## Commands Reference

Run `make help` to see all available commands.
