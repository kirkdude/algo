# Algo Quantum VPN Makefile
# Enhanced with quantum-safe development workflow

.PHONY: help install clean lint test build docker-build docker-deploy docker-prune docker-all setup-dev release all check

# Default target
all: clean install lint-full test build ## Full pipeline - clean, install, lint, test, build
help: ## Show this help message
	@echo 'Usage: make [TARGET] [EXTRA_ARGUMENTS]'
	@echo 'Targets:'
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

# Variables
IMAGE          := trailofbits/algo
TAG	  	       := latest
DOCKERFILE     := Dockerfile
CONFIGURATIONS := $(shell pwd)
PYTHON         := python3
VENV_DIR       := .env

## Development Setup
install: ## Install dependencies and set up development environment
	@echo "Setting up Algo VPN development environment..."
	@echo "Installing Python dependencies..."
	$(PYTHON) -m pip install --user -r requirements.txt
	$(PYTHON) -m pip install --user -r requirements-dev.txt
	@echo "Installing pre-commit hooks..."
	pre-commit install
	@echo "Development environment ready!"

setup-dev: install ## Alias for install

clean: ## Clean up generated files
	rm -rf .pytest_cache
	rm -rf __pycache__
	rm -rf .coverage
	rm -rf releases/
	find . -type f -name "*.pyc" -delete
	find . -type d -name "__pycache__" -delete

## Linting and Code Quality
lint: ## Run pre-commit hooks on all files
	@echo "Running pre-commit hooks on all files..."
	pre-commit run --all-files

lint-full: ## Run comprehensive linting (pre-commit + Ansible + shell checks)
	@echo "Running pre-commit hooks on all files..."
	pre-commit run --all-files
	@echo "Running Ansible syntax check..."
	ansible-playbook main.yml --syntax-check
	ansible-playbook users.yml --syntax-check
	@echo "Running shell script checks..."
	shellcheck algo install.sh scripts/*.sh
	find tests/ -name "*.sh" -exec shellcheck {} \;

lint-fix: ## Run linting with auto-fix where possible
	pre-commit run --all-files

## Testing
test: kitchen-test ## Run all tests using Test Kitchen

## Test Kitchen Operations
kitchen-setup: ## Install Test Kitchen dependencies
	@echo "Installing Test Kitchen dependencies..."
	@if [ ! -f Gemfile ]; then echo "Error: Gemfile not found. Run make install first."; exit 1; fi
	bundle install
	@echo "Test Kitchen dependencies installed!"

kitchen-test: ## Run all kitchen tests
	@echo "Running Test Kitchen tests..."
	kitchen test

kitchen-converge: ## Deploy VPN in test environment
	@echo "Converging Test Kitchen environments..."
	kitchen converge

kitchen-verify: ## Run verification tests only
	@echo "Running Test Kitchen verification..."
	kitchen verify

kitchen-destroy: ## Destroy test environments
	@echo "Destroying Test Kitchen environments..."
	kitchen destroy

kitchen-clean: ## Clean up kitchen artifacts
	@echo "Cleaning Test Kitchen artifacts..."
	kitchen destroy
	rm -rf .kitchen/


## Quantum-Safe Testing
quantum-dev: ## Setup quantum-safe development environment
	@echo "Setting up quantum-safe development environment..."
	ansible-playbook quantum-safe-dev.yml
	@echo "Quantum-safe development environment ready!"

quantum-test: ## Run quantum-safe algorithm tests
	@echo "Running quantum-safe cryptography tests..."
	/opt/quantum-safe/tests/run-all-tests.sh

quantum-benchmark: ## Run quantum-safe performance benchmarks
	@echo "Running quantum-safe performance benchmarks..."
	/opt/quantum-safe/tests/benchmark-quantum-safe.sh

quantum-ipsec-test: ## Test quantum-safe IPsec connectivity
	@echo "Testing quantum-safe IPsec connectivity..."
	tests/quantum-safe-ipsec.sh

quantum-performance: ## Run quantum-safe IPsec performance tests
	@echo "Running quantum-safe IPsec performance tests..."
	tests/quantum-safe-performance.sh

## Building
build: lint-full test ## Build and validate the project
	@echo "Project built and validated successfully!"

## Docker Operations
docker-build: ## Build and tag a docker image
	docker build \
	-t $(IMAGE):$(TAG) \
	-f $(DOCKERFILE) \
	.

docker-deploy: ## Mount config directory and deploy Algo
	# '--rm' flag removes the container when finished.
	docker run \
	--cap-drop=all \
	--rm \
	-it \
	-v $(CONFIGURATIONS):/data \
	$(IMAGE):$(TAG)

docker-prune: ## Remove images and containers
	docker images \
	$(IMAGE) |\
	awk '{if (NR>1) print $$3}' |\
	xargs docker rmi

docker-all: docker-build docker-deploy docker-prune ## Build, Deploy, Prune

## Release Management
release: ## Create a new release (usage: make release VERSION=1.0.0)
	@if [ -z "$(VERSION)" ]; then \
		echo "Error: VERSION is required. Usage: make release VERSION=1.0.0"; \
		exit 1; \
	fi
	./scripts/create_release.sh $(VERSION)

release-push: ## Create and push a new release (usage: make release-push VERSION=1.0.0)
	@if [ -z "$(VERSION)" ]; then \
		echo "Error: VERSION is required. Usage: make release-push VERSION=1.0.0"; \
		exit 1; \
	fi
	./scripts/create_release.sh --push $(VERSION)

## Algo VPN Operations
deploy: ## Deploy Algo VPN (interactive)
	./algo

update-users: ## Update VPN users
	./algo update-users

## Development Shortcuts
dev-setup: install ## Set up development environment with all tools (alias for install)

check: lint test ## Quick check - run linting and tests

ci-local: ## Run GitHub Actions checks locally (Main workflow lint job)
	@echo "=== Running GitHub Actions Main workflow checks locally ==="
	@echo "Note: This mimics the GitHub Actions Main workflow lint job"
	@echo "Python version: $(shell python --version)"
	@echo "Running shellcheck..."
	shellcheck algo install.sh
	@echo "Running Ansible syntax checks..."
	ansible-playbook -i inventory.syntax-check main.yml --syntax-check
	ansible-playbook -i inventory.syntax-check users.yml --syntax-check
	@echo "Running ansible-lint (compatibility may vary by Python version)..."
	ansible-lint -x experimental,package-latest,unnamed-task -v *.yml roles/{local,cloud-*}/*/*.yml
	@echo "=== GitHub Actions Main workflow lint checks complete ==="

ci-docker-local: docker-build ## Run GitHub Actions docker-deploy checks locally
	@echo "=== Running GitHub Actions docker-deploy workflow locally ==="
	@echo "Building Docker image..."
	@echo "Running local Docker deployment test..."
	./tests/local-deploy.sh
	./tests/update-users.sh
	@echo "=== Docker deployment checks complete ==="

ci-simple: ## Run basic checks equivalent to GitHub Actions (no dependency installs)
	@echo "=== Running basic GitHub Actions equivalent checks ==="
	@echo "1. Running shellcheck..."
	shellcheck algo install.sh
	@echo "2. Running Ansible syntax checks..."
	ansible-playbook -i inventory.syntax-check main.yml --syntax-check
	ansible-playbook -i inventory.syntax-check users.yml --syntax-check
	@echo "3. Running pre-commit hooks (recommended over ansible-lint)..."
	pre-commit run --all-files
	@echo "=== Basic GitHub Actions checks complete ==="
	@echo "Note: Use 'make lint' and 'make test' for comprehensive local validation"

ci-all-local: ci-local ci-docker-local ## Run all GitHub Actions workflows locally
	@echo "=== All GitHub Actions workflows completed locally ==="
