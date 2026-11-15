.DEFAULT_GOAL := help
APP_DIR := app
ENV ?= dev
# Some shells export ENV for their own use; only a value given on the command line counts.
ifeq ($(origin ENV),environment)
ENV := dev
endif
TF_DIR := infra/envs/$(ENV)
TF_ENV_VAR := -var environment=$(ENV)

# Short SHA of the last commit that changed app/, so infra-only commits reuse the pushed image.
ifndef IMAGE_TAG
IMAGE_TAG := $(shell git log -1 --format=%h -- $(APP_DIR))$(if $(shell git status --porcelain -- $(APP_DIR)),-dirty)
endif

MIGRATE_CMD ?= alembic upgrade head
empty :=
space := $(empty) $(empty)
comma := ,
MIGRATE_CMD_JSON := [$(subst $(space),$(comma),$(foreach w,$(MIGRATE_CMD),\"$(w)\"))]

TRIVY_VERSION := 0.76.2
CHECKOV_VERSION := 3.4.5
SCAN_IMAGE := aws-ecs-production-ready-app:scan
TRIVY := docker run --rm -v trivy-cache:/root/.cache/ -v $(CURDIR):/src:ro -w /src aquasec/trivy:$(TRIVY_VERSION)
TRIVY_IMAGE := docker run --rm -v trivy-cache:/root/.cache/ -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy:$(TRIVY_VERSION)
CHECKOV := docker run --rm -v $(CURDIR):/src:ro -w /src bridgecrew/checkov:$(CHECKOV_VERSION)

.PHONY: diagram help up down logs migrate test lint fmt scan tf-fmt tf-validate tf-init tf-plan tf-destroy image-push db-migrate infra-up

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

# Only this recipe reads .env, so Terraform and AWS commands never see the local credentials.
test: ## Run the test suite against the compose Postgres (separate test database)
	docker compose up -d --wait db
	cd $(APP_DIR) && DB_HOST=localhost uv run $(if $(wildcard .env),--env-file ../.env) pytest

lint: ## Lint and check formatting
	cd $(APP_DIR) && uv run ruff check . && uv run ruff format --check .

fmt: ## Auto-fix lint issues and format the code
	cd $(APP_DIR) && uv run ruff check --fix . && uv run ruff format .

scan: ## Static analysis: trivy and checkov on infra/, trivy on the app image (HIGH/CRITICAL with a fix)
	@rc=0; \
	echo "== trivy config infra"; $(TRIVY) config --quiet --exit-code 1 infra || rc=1; \
	echo "== checkov infra"; $(CHECKOV) -d infra --quiet --compact || rc=1; \
	echo "== trivy image"; \
	if docker build -q --platform linux/amd64 -t $(SCAN_IMAGE) $(APP_DIR) >/dev/null; then \
		$(TRIVY_IMAGE) image --quiet --exit-code 1 --severity HIGH,CRITICAL --ignore-unfixed $(SCAN_IMAGE) || rc=1; \
	else \
		echo "docker build failed, so the image was not scanned"; exit 2; \
	fi; \
	if [ $$rc -ne 0 ]; then echo "scan failed: fix each finding above or suppress it inline with a reason"; fi; \
	exit $$rc

# Terraform targets need AWS credentials, e.g. `export AWS_PROFILE=<profile>`, and take ENV=<name> to pick infra/envs/<name>.

tf-fmt: ## Check Terraform formatting
	terraform fmt -recursive -check infra

tf-validate: ## Validate the bootstrap and dev stacks (no backend, no credentials)
	@# Separate data dir so an already-initialized S3 backend is never touched.
	cd infra/bootstrap && TF_DATA_DIR=.terraform/validate terraform init -backend=false -input=false >/dev/null && TF_DATA_DIR=.terraform/validate terraform validate
	cd $(TF_DIR) && TF_DATA_DIR=.terraform/validate terraform init -backend=false -input=false >/dev/null && TF_DATA_DIR=.terraform/validate terraform validate

tf-init: ## Init ENV (default dev) against the remote state in backend.hcl
	terraform -chdir=$(TF_DIR) init -backend-config=backend.hcl -input=false

tf-plan: tf-init ## Plan ENV (default dev) with IMAGE_TAG (default: current git SHA) into infra/envs/<ENV>/tfplan
	terraform -chdir=$(TF_DIR) plan -input=false $(TF_ENV_VAR) -var image_tag=$(IMAGE_TAG) -out=tfplan

tf-destroy: tf-init ## Destroy everything in ENV (default dev), ECR images included
	terraform -chdir=$(TF_DIR) destroy $(TF_ENV_VAR)

# Without provenance the push is a single image manifest, which ECR basic scanning supports.
image-push: ## Build the app image for linux/amd64 and push it to ECR as IMAGE_TAG (outside us-east-2 also set RDS_CA_SHA256)
	@set -e; \
	repo=$$(terraform -chdir=$(TF_DIR) output -raw ecr_repository_url); \
	region=$$(echo $$repo | cut -d. -f4); \
	if aws ecr describe-images --region $$region --repository-name $${repo#*/} --image-ids imageTag=$(IMAGE_TAG) >/dev/null 2>&1; then \
		echo "$$repo:$(IMAGE_TAG) is already in ECR, skipping the build"; exit 0; \
	fi; \
	aws ecr get-login-password --region $$region | docker login --username AWS --password-stdin $${repo%%/*}; \
	docker build --platform linux/amd64 --provenance=false --build-arg RDS_CA_REGION=$$region $(if $(RDS_CA_SHA256),--build-arg RDS_CA_SHA256=$(RDS_CA_SHA256)) -t $$repo:$(IMAGE_TAG) $(APP_DIR); \
	docker push $$repo:$(IMAGE_TAG); \
	echo "Pushed $$repo:$(IMAGE_TAG)"

# A one-off task per deploy, so app tasks starting together never race on the same migration.
db-migrate: ## Run MIGRATE_CMD (default: alembic upgrade head) as a one-off ECS task; fails unless it exits 0
	$(if $(findstring ',$(MIGRATE_CMD))$(findstring ",$(MIGRATE_CMD))$(findstring \,$(MIGRATE_CMD))$(findstring $$,$(MIGRATE_CMD)),$(error MIGRATE_CMD takes plain words only, without quotes, backslashes or $$))
	@set -e; \
	out() { terraform -chdir=$(TF_DIR) output -raw $$1; }; \
	cluster=$$(out cluster_name); service=$$(out service_name); container=$$(out container_name); \
	sg=$$(out task_security_group_id); logs=$$(out log_group_name); \
	subnets=$$(terraform -chdir=$(TF_DIR) output -json private_subnet_ids | tr -d '[]" \n'); \
	region=$$(out task_definition_arn | cut -d: -f4); \
	taskdef=$$(aws ecs describe-services --region $$region --cluster $$cluster --services $$service --query 'services[0].taskDefinition' --output text); \
	task=$$(aws ecs run-task --region $$region --cluster $$cluster --task-definition $$taskdef \
		--launch-type FARGATE --started-by db-migrate \
		--network-configuration "awsvpcConfiguration={subnets=[$$subnets],securityGroups=[$$sg],assignPublicIp=DISABLED}" \
		--overrides "{\"containerOverrides\":[{\"name\":\"$$container\",\"command\":$(MIGRATE_CMD_JSON)}]}" \
		--query 'tasks[0].taskArn' --output text); \
	if [ -z "$$task" ] || [ "$$task" = "None" ]; then echo "run-task did not start a task"; exit 1; fi; \
	echo "Started $$task ($${taskdef##*/}) running '$(MIGRATE_CMD)', waiting for it to stop"; \
	if ! aws ecs wait tasks-stopped --region $$region --cluster $$cluster --tasks $$task; then \
		echo "Still running after 10 minutes; do not start another migration until it stops."; \
		echo "Check it: aws ecs describe-tasks --region $$region --cluster $$cluster --tasks $$task"; \
		exit 1; \
	fi; \
	code=$$(aws ecs describe-tasks --region $$region --cluster $$cluster --tasks $$task --query 'tasks[0].containers[0].exitCode' --output text); \
	stream="$$container/$$container/$${task##*/}"; \
	aws logs get-log-events --region $$region --log-group-name $$logs --log-stream-name $$stream --query 'events[].message' --output text 2>/dev/null | tr '\t' '\n' || true; \
	if [ "$$code" != "0" ]; then \
		echo "Migration failed (exit code $$code): $$(aws ecs describe-tasks --region $$region --cluster $$cluster --tasks $$task --query 'tasks[0].[stoppedReason,containers[0].reason]' --output text | tr '\t' ' ' | sed 's/ None$$//')"; \
		echo "Logs: aws logs tail $$logs --region $$region --log-stream-names $$stream"; \
		exit 1; \
	fi; \
	echo "Migration finished (exit code 0)"

# The service needs an image that only exists after the repository does, so ECR goes first.
infra-up: tf-init ## First deploy: create ECR, push the image, apply the rest, run the migration
	terraform -chdir=$(TF_DIR) apply -input=false $(TF_ENV_VAR) -target=module.ecr
	$(MAKE) image-push ENV=$(ENV) IMAGE_TAG=$(IMAGE_TAG)
	terraform -chdir=$(TF_DIR) apply -input=false $(TF_ENV_VAR) -var image_tag=$(IMAGE_TAG)
	$(MAKE) db-migrate ENV=$(ENV)

# Graphviz and the diagrams library run in a throwaway container, so nothing is installed on the host.
diagram: ## Regenerate docs/architecture.png from docs/architecture.py (needs Docker)
	docker run --rm -e OWNER=$$(id -u):$$(id -g) -v $(CURDIR)/docs:/docs -w /docs python:3.12-slim \
		sh -c 'apt-get update -qq && apt-get install -y -qq graphviz >/dev/null && pip install -q diagrams==0.24.4 && python architecture.py && chown $$OWNER architecture.png'
