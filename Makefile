# Halo.OS Performance Harness - Makefile
# Convenience wrapper for common commands

.PHONY: help setup build test clean docker-build docker-run docker-shell lint format

# Default target
.DEFAULT_GOAL := help

# ==============================================================================
# Help
# ==============================================================================
help: ## Show this help message
	@echo "Halo.OS Performance Harness - Available Commands:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
	@echo ""

# ==============================================================================
# Setup and Build
# ==============================================================================
setup: ## Install dependencies and setup environment
	@echo "Setting up environment..."
	@chmod +x ci/setup_env.sh
	@./ci/setup_env.sh

build: ## Build Halo.OS
	@echo "Building Halo.OS..."
	@chmod +x ci/build_halo.sh
	@source .env && ./ci/build_halo.sh

build-clean: ## Clean build and rebuild from scratch
	@echo "Clean building Halo.OS..."
	@chmod +x ci/build_halo.sh
	@source .env && ./ci/build_halo.sh --clean

# ==============================================================================
# Testing
# ==============================================================================
test: ## Run a quick test experiment (2 minutes)
	@echo "Running test experiment..."
	@chmod +x ci/run_experiment.sh
	@source .env && ./ci/run_experiment.sh test_$(shell date +%Y%m%d_%H%M%S) 120

test-quick: ## Run ultra-quick test (30 seconds)
	@echo "Running quick test..."
	@chmod +x ci/run_experiment.sh
	@source .env && ./ci/run_experiment.sh quick_$(shell date +%Y%m%d_%H%M%S) 30

experiment: ## Run full experiment (5 minutes, specify RUN_ID)
	@test -n "$(RUN_ID)" || (echo "ERROR: RUN_ID not set. Usage: make experiment RUN_ID=run001" && exit 1)
	@chmod +x ci/run_experiment.sh
	@source .env && ./ci/run_experiment.sh $(RUN_ID) ${DURATION:-300} ${ARGS}

analyze: ## Analyze latest results
	@chmod +x ci/analyze_vbs.py
	@LATEST=$$(ls -t results/*/events.jsonl 2>/dev/null | head -1); \
	if [ -z "$$LATEST" ]; then \
		echo "No results found. Run 'make test' first."; \
		exit 1; \
	fi; \
	echo "Analyzing: $$LATEST"; \
	python3 ci/analyze_vbs.py "$$LATEST"

# ==============================================================================
# Docker
# ==============================================================================
docker-build: ## Build Docker image
	@echo "Building Docker image..."
	@docker-compose build

docker-run: ## Run experiment in Docker
	@echo "Running in Docker..."
	@docker-compose run --rm halo-dev make test

docker-shell: ## Open shell in Docker container
	@echo "Starting Docker shell..."
	@docker-compose run --rm halo-dev /bin/bash

docker-up: ## Start Docker container in background
	@docker-compose up -d

docker-down: ## Stop Docker container
	@docker-compose down

docker-logs: ## Show Docker logs
	@docker-compose logs -f

# ==============================================================================
# Code Quality
# ==============================================================================
lint: ## Run linters on all code
	@echo "Running linters..."
	@echo "Checking Python..."
	@find ci -name "*.py" -exec pylint {} + || true
	@echo "Checking Bash..."
	@find ci -name "*.sh" -exec shellcheck -e SC1090,SC1091 {} + || true

format: ## Format Python code
	@echo "Formatting Python code..."
	@black ci/*.py
	@echo "Formatting complete"

typecheck: ## Run mypy type checking
	@echo "Running type checker..."
	@mypy ci/*.py --ignore-missing-imports

# ==============================================================================
# Cleanup
# ==============================================================================
clean: ## Clean build artifacts
	@echo "Cleaning build artifacts..."
	@rm -rf build/*
	@rm -rf .ccache/*
	@echo "Build cleaned"

clean-results: ## Clean all experiment results
	@echo "WARNING: This will delete all results!"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		rm -rf results/*; \
		echo "Results cleaned"; \
	else \
		echo "Cancelled"; \
	fi

clean-all: clean clean-results ## Clean everything
	@echo "Cleaning logs and cache..."
	@rm -rf logs/*
	@rm -rf cache/*
	@echo "All cleaned"

# ==============================================================================
# Validation
# ==============================================================================
validate: ## Validate repository integrity
	@echo "Validating manifests..."
	@xmllint --noout manifests/*.xml
	@echo "Validating Python syntax..."
	@python3 -m py_compile ci/*.py
	@echo "Validating Bash syntax..."
	@for script in ci/*.sh; do shellcheck -e SC1090,SC1091 "$$script"; done
	@echo "Validation complete"

# ==============================================================================
# CI Simulation
# ==============================================================================
ci-local: ## Simulate CI pipeline locally
	@echo "Simulating CI pipeline..."
	@make validate
	@make setup
	@make build
	@make test
	@make analyze
	@echo "CI simulation complete"

# ==============================================================================
# Documentation
# ==============================================================================
docs: ## Generate documentation
	@echo "Generating documentation..."
	@cd docs && make html
	@echo "Documentation built: docs/_build/html/index.html"

# ==============================================================================
# Variables
# ==============================================================================
# Set default values
DURATION ?= 300
RUN_ID ?= default_run
ARGS ?=
