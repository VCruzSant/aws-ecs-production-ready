.DEFAULT_GOAL := help
APP_DIR := app
TF_DEV_DIR := infra/envs/dev

# Load .env (if present) so local commands use the same credentials as docker compose.
ifneq (,$(wildcard .env))
include .env
export
endif

.PHONY: help up down logs migrate test lint fmt tf-fmt tf-validate tf-plan tf-destroy

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

tf-plan: ## Plan the dev environment into infra/envs/dev/tfplan (needs backend.hcl)
	terraform -chdir=$(TF_DEV_DIR) init -backend-config=backend.hcl -input=false
	terraform -chdir=$(TF_DEV_DIR) plan -input=false -out=tfplan

tf-destroy: ## Destroy everything in the dev environment
	terraform -chdir=$(TF_DEV_DIR) init -backend-config=backend.hcl -input=false
	terraform -chdir=$(TF_DEV_DIR) destroy
