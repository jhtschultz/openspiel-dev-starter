# OpenSpiel Development Workflow
#
# Quick start:
#   make setup      # First time setup
#   make dev        # Start development environment
#   make build      # Build OpenSpiel (incremental)
#   make test       # Run tests
#
# GCP:
#   make gcp-create # Create a GCP VM
#   make gcp-ssh    # SSH into it
#   make gcp-delete # Tear it down

# ============================================
# Configuration - loaded from .env file
# ============================================
-include .env
export

PROJECT_ID ?= your-gcp-project-id
REGION ?= us-central1
ZONE ?= us-central1-a
REGISTRY := gcr.io/$(PROJECT_ID)

# GCP VM settings
VM_NAME := openspiel-dev
MACHINE_TYPE := n1-standard-8  # 8 vCPU, 30GB RAM - good for builds
# MACHINE_TYPE := n1-highmem-4  # Alternative: 4 vCPU, 26GB RAM

# Image tags
BASE_TAG := dev-base:latest
OPENSPIEL_TAG := openspiel-dev:latest

# ============================================
# Local Development
# ============================================

.PHONY: setup
setup: ## First-time setup
	@echo "==> Cloning OpenSpiel..."
	@[ -d open_spiel ] || git clone https://github.com/google-deepmind/open_spiel.git open_spiel
	@echo "==> Building base image..."
	@$(MAKE) build-base
	@echo "==> Building OpenSpiel image..."
	@$(MAKE) build-image
	@echo "==> Done! Run 'make dev' to start."

.PHONY: dev
dev: ## Start development environment
	docker compose up -d
	docker compose exec dev bash

.PHONY: stop
stop: ## Stop development environment
	docker compose down

.PHONY: build
build: ## Build OpenSpiel (inside container, incremental)
	docker compose exec dev bash -c "cd /home/dev/open_spiel && ./open_spiel/scripts/build_and_run_tests.sh"

.PHONY: build-init
build-init: ## First-time build: fetch deps + compile (no tests)
	docker compose exec dev bash -c '\
		cd /home/dev/open_spiel && \
		./install.sh && \
		mkdir -p build && cd build && \
		cmake -DCMAKE_BUILD_TYPE=Release ../open_spiel && \
		make -j$$(nproc)'

.PHONY: build-fast
build-fast: ## Quick rebuild without tests (run build-init first)
	docker compose exec dev bash -c '\
		cd /home/dev/open_spiel/build && \
		cmake -DCMAKE_BUILD_TYPE=Release ../open_spiel && \
		make -j$$(nproc)'

.PHONY: test
test: ## Run tests
	docker compose exec dev bash -c "cd /home/dev/open_spiel && python3 -m pytest open_spiel/python/tests/"

# ============================================
# Docker Images
# ============================================

.PHONY: build-base
build-base: ## Build base dev image
	docker build -t $(REGISTRY)/$(BASE_TAG) -f docker/Dockerfile.base docker/

.PHONY: build-image
build-image: ## Build OpenSpiel dev image
	docker build -t $(REGISTRY)/$(OPENSPIEL_TAG) \
		--build-arg REGISTRY=$(REGISTRY) \
		-f docker/Dockerfile.openspiel docker/

.PHONY: push
push: ## Push images to registry
	docker push $(REGISTRY)/$(BASE_TAG)
	docker push $(REGISTRY)/$(OPENSPIEL_TAG)

.PHONY: pull
pull: ## Pull images from registry
	docker pull $(REGISTRY)/$(OPENSPIEL_TAG)

# ============================================
# GCP VM Management
# ============================================

.PHONY: gcp-create
gcp-create: ## Create GCP VM for development
	gcloud compute instances create $(VM_NAME) \
		--project=$(PROJECT_ID) \
		--zone=$(ZONE) \
		--machine-type=$(MACHINE_TYPE) \
		--image-family=ubuntu-2204-lts \
		--image-project=ubuntu-os-cloud \
		--boot-disk-size=100GB \
		--boot-disk-type=pd-ssd \
		--scopes=cloud-platform \
		--metadata-from-file=startup-script=scripts/gcp-startup.sh
	@echo "==> VM created. Wait ~2 min, then run 'make gcp-setup' and 'make gcp-dev'"

.PHONY: gcp-create-preemptible
gcp-create-preemptible: ## Create preemptible VM (cheaper, can be terminated)
	gcloud compute instances create $(VM_NAME) \
		--project=$(PROJECT_ID) \
		--zone=$(ZONE) \
		--machine-type=$(MACHINE_TYPE) \
		--image-family=ubuntu-2204-lts \
		--image-project=ubuntu-os-cloud \
		--boot-disk-size=100GB \
		--boot-disk-type=pd-ssd \
		--scopes=cloud-platform \
		--provisioning-model=SPOT \
		--metadata-from-file=startup-script=scripts/gcp-startup.sh

# GPU VM settings
GPU_MACHINE_TYPE := n1-standard-8
GPU_TYPE := nvidia-tesla-t4
GPU_COUNT := 1
GPU_ZONE := us-central1-a

.PHONY: gcp-create-gpu
gcp-create-gpu: ## Create GPU VM for JAX/ML work
	gcloud compute instances create $(VM_NAME)-gpu \
		--project=$(PROJECT_ID) \
		--zone=$(GPU_ZONE) \
		--machine-type=$(GPU_MACHINE_TYPE) \
		--accelerator=type=$(GPU_TYPE),count=$(GPU_COUNT) \
		--image-family=ubuntu-2204-lts \
		--image-project=ubuntu-os-cloud \
		--boot-disk-size=150GB \
		--boot-disk-type=pd-ssd \
		--scopes=cloud-platform \
		--maintenance-policy=TERMINATE \
		--metadata-from-file=startup-script=scripts/gcp-startup-gpu.sh
	@echo "==> GPU VM created. Wait ~5 min for NVIDIA drivers, then 'make gcp-ssh-gpu'"

.PHONY: gcp-create-gpu-spot
gcp-create-gpu-spot: ## Create spot GPU VM (much cheaper, can be preempted)
	gcloud compute instances create $(VM_NAME)-gpu \
		--project=$(PROJECT_ID) \
		--zone=$(GPU_ZONE) \
		--machine-type=$(GPU_MACHINE_TYPE) \
		--accelerator=type=$(GPU_TYPE),count=$(GPU_COUNT) \
		--image-family=ubuntu-2204-lts \
		--image-project=ubuntu-os-cloud \
		--boot-disk-size=150GB \
		--boot-disk-type=pd-ssd \
		--scopes=cloud-platform \
		--maintenance-policy=TERMINATE \
		--provisioning-model=SPOT \
		--metadata-from-file=startup-script=scripts/gcp-startup-gpu.sh
	@echo "==> Spot GPU VM created. Wait ~5 min for NVIDIA drivers, then 'make gcp-ssh-gpu'"

.PHONY: gcp-ssh-gpu
gcp-ssh-gpu: ## SSH into GPU VM
	gcloud compute ssh $(VM_NAME)-gpu --project=$(PROJECT_ID) --zone=$(GPU_ZONE)

.PHONY: gcp-stop-gpu
gcp-stop-gpu: ## Stop GPU VM
	gcloud compute instances stop $(VM_NAME)-gpu --project=$(PROJECT_ID) --zone=$(GPU_ZONE)

.PHONY: gcp-start-gpu
gcp-start-gpu: ## Start GPU VM
	gcloud compute instances start $(VM_NAME)-gpu --project=$(PROJECT_ID) --zone=$(GPU_ZONE)

.PHONY: gcp-delete-gpu
gcp-delete-gpu: ## Delete GPU VM
	gcloud compute instances delete $(VM_NAME)-gpu --project=$(PROJECT_ID) --zone=$(GPU_ZONE)

.PHONY: gcp-ssh
gcp-ssh: ## SSH into GCP VM
	gcloud compute ssh $(VM_NAME) --project=$(PROJECT_ID) --zone=$(ZONE)

.PHONY: gcp-stop
gcp-stop: ## Stop GCP VM (preserves disk, stops billing for compute)
	gcloud compute instances stop $(VM_NAME) --project=$(PROJECT_ID) --zone=$(ZONE)

.PHONY: gcp-start
gcp-start: ## Start stopped GCP VM
	gcloud compute instances start $(VM_NAME) --project=$(PROJECT_ID) --zone=$(ZONE)

.PHONY: gcp-delete
gcp-delete: ## Delete GCP VM completely
	gcloud compute instances delete $(VM_NAME) --project=$(PROJECT_ID) --zone=$(ZONE)

.PHONY: gcp-status
gcp-status: ## Check VM status
	gcloud compute instances describe $(VM_NAME) --project=$(PROJECT_ID) --zone=$(ZONE) --format='get(status)'

.PHONY: gcp-setup
gcp-setup: ## Copy config files to VM (run after gcp-create)
	@echo "==> Copying docker-compose.yml and .env to VM..."
	gcloud compute scp docker-compose.yml .env \
		$(VM_NAME):~/workspace/ \
		--project=$(PROJECT_ID) --zone=$(ZONE)
	@echo "==> Done! Run 'make gcp-dev' to start developing."

.PHONY: gcp-dev
gcp-dev: ## SSH into VM and start dev container
	gcloud compute ssh $(VM_NAME) --project=$(PROJECT_ID) --zone=$(ZONE) \
		--command="cd ~/workspace && docker compose up -d && docker compose exec dev bash"

.PHONY: gcp-logs
gcp-logs: ## Check VM startup script logs
	gcloud compute ssh $(VM_NAME) --project=$(PROJECT_ID) --zone=$(ZONE) \
		--command="sudo tail -50 /var/log/startup-script.log"

# ============================================
# Experiments (parallel runs on GCP)
# ============================================

.PHONY: run-experiment
run-experiment: ## Run experiment on Cloud Run Jobs (usage: make run-experiment SCRIPT=my_exp.py)
ifndef SCRIPT
	$(error SCRIPT is required. Usage: make run-experiment SCRIPT=experiments/my_exp.py)
endif
	gcloud run jobs create exp-$$(date +%s) \
		--project=$(PROJECT_ID) \
		--region=$(REGION) \
		--image=$(REGISTRY)/$(OPENSPIEL_TAG) \
		--command="python3" \
		--args="$(SCRIPT)" \
		--execute-now

# ============================================
# Utilities
# ============================================

.PHONY: clean
clean: ## Clean up build artifacts
	docker compose down -v
	rm -rf open_spiel/build/*

.PHONY: shell
shell: ## Quick shell into running container
	docker compose exec dev bash

.PHONY: logs
logs: ## Show container logs
	docker compose logs -f

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help
