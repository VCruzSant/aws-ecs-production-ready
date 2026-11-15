.DEFAULT_GOAL := help
APP_DIR := app
TF_DEV_DIR := infra/envs/dev

# Short SHA of the last commit that changed app/, so infra-only commits reuse the pushed image.
ifndef IMAGE_TAG
IMAGE_TAG := $(shell git log -1 --format=%h -- $(APP_DIR))$(if $(shell git status --porcelain -- $(APP_DIR)),-dirty)
endif

# Load .env (if present) so local commands use the same credentials as docker compose.
ifneq (,$(wildcard .env))
include .env
export
endif

.PHONY: help up down logs migrate test lint fmt tf-fmt tf-validate tf-init tf-plan tf-destroy image-push infra-up

help: ## Show available targets
	@grep -hE '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  %-12s %s\n", $$1, $$2}'

up: ## Build and start the app and Postgres
	docker compose up -d --build

down: ## Stop everything (keeps the database volume)
	docker compose down

logs: ## Follow the app logs
	docker compose logs -f app

migrate: ## Run database migrations inside the app container
	docker compose exec app alembic upgrade head

test: ## Run the test suite against the compose Postgres (separate test database)
	docker compose up -d --wait db
	cd $(APP_DIR) && DB_HOST=localhost uv run pytest

lint: ## Lint and check formatting
	cd $(APP_DIR) && uv run ruff check . && uv run ruff format --check .

fmt: ## Auto-fix lint issues and format the code
	cd $(APP_DIR) && uv run ruff check --fix . && uv run ruff format .

# Terraform targets need AWS credentials, e.g. `export AWS_PROFILE=<profile>`.

tf-fmt: ## Check Terraform formatting
	terraform fmt -recursive -check infra

tf-validate: ## Validate the bootstrap and dev stacks (no backend, no credentials)
	@# Separate data dir so an already-initialized S3 backend is never touched.
	cd infra/bootstrap && TF_DATA_DIR=.terraform/validate terraform init -backend=false -input=false >/dev/null && TF_DATA_DIR=.terraform/validate terraform validate
	cd $(TF_DEV_DIR) && TF_DATA_DIR=.terraform/validate terraform init -backend=false -input=false >/dev/null && TF_DATA_DIR=.terraform/validate terraform validate

tf-init:
	terraform -chdir=$(TF_DEV_DIR) init -backend-config=backend.hcl -input=false

tf-plan: tf-init ## Plan dev with IMAGE_TAG (default: current git SHA) into infra/envs/dev/tfplan
	terraform -chdir=$(TF_DEV_DIR) plan -input=false -var image_tag=$(IMAGE_TAG) -out=tfplan

tf-destroy: tf-init ## Destroy everything in the dev environment, ECR images included
	terraform -chdir=$(TF_DEV_DIR) destroy

# Without provenance the push is a single image manifest, which ECR basic scanning supports.
image-push: ## Build the app image for linux/amd64 and push it to ECR as IMAGE_TAG
	@set -e; \
	repo=$$(terraform -chdir=$(TF_DEV_DIR) output -raw ecr_repository_url); \
	region=$$(echo $$repo | cut -d. -f4); \
	if aws ecr describe-images --region $$region --repository-name $${repo#*/} --image-ids imageTag=$(IMAGE_TAG) >/dev/null 2>&1; then \
		echo "$$repo:$(IMAGE_TAG) is already in ECR, skipping the build"; exit 0; \
	fi; \
	aws ecr get-login-password --region $$region | docker login --username AWS --password-stdin $${repo%%/*}; \
	docker build --platform linux/amd64 --provenance=false -t $$repo:$(IMAGE_TAG) $(APP_DIR); \
	docker push $$repo:$(IMAGE_TAG); \
	echo "Pushed $$repo:$(IMAGE_TAG)"

# The service needs an image that only exists after the repository does, so ECR goes first.
infra-up: tf-init ## First deploy: create ECR, push the image, plan the rest into tfplan
	terraform -chdir=$(TF_DEV_DIR) apply -input=false -target=module.ecr
	$(MAKE) image-push IMAGE_TAG=$(IMAGE_TAG)
	terraform -chdir=$(TF_DEV_DIR) plan -input=false -var image_tag=$(IMAGE_TAG) -out=tfplan
	@echo "Review the plan above, then run: terraform -chdir=$(TF_DEV_DIR) apply tfplan"
