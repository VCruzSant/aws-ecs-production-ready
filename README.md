# aws-ecs-production-ready

Production-ready AWS infrastructure (ECS Fargate, RDS, ALB, CI/CD and monitoring, all in Terraform) for a containerized Python API.

## What's inside

| Path | Contents |
|---|---|
| `app/` | Demo API: FastAPI + PostgreSQL (SQLAlchemy 2, Alembic), managed with `uv` |
| `infra/` | Terraform: state bootstrap, network module, `dev` environment ([details](infra/README.md)) |
| `docs/` | Diagrams and notes (coming soon) |

## Run locally

Requirements: Docker with Compose v2, GNU Make, and [uv](https://docs.astral.sh/uv/) (only for tests and lint).

```bash
cp .env.example .env
make up                         # docker compose up -d --build
curl localhost:8000/health      # {"status":"ok"}
curl localhost:8000/health/db   # {"status":"ok"}, or 503 if the database is down
```

The `app` container waits for Postgres to be healthy, runs `alembic upgrade head` and then starts the API on port 8000. Interactive API docs: <http://localhost:8000/docs>.

Try the API:

```bash
curl -X POST localhost:8000/tasks -H 'Content-Type: application/json' -d '{"title":"Ship it"}'
curl localhost:8000/tasks
curl -X PATCH localhost:8000/tasks/1 -H 'Content-Type: application/json' -d '{"done":true}'
curl -X DELETE localhost:8000/tasks/1
```

| Endpoint | Description |
|---|---|
| `GET /health` | Liveness, does not touch the database |
| `GET /health/db` | Runs `SELECT 1`; 200 or 503 |
| `POST /tasks` | Create a task (`title` required, max 200 chars) |
| `GET /tasks` | List tasks |
| `GET /tasks/{id}` | Get a task |
| `PATCH /tasks/{id}` | Update `title` and/or `done` |
| `DELETE /tasks/{id}` | Delete a task |

Other commands:

```bash
make test      # pytest against the compose Postgres, in a separate test database
make lint      # ruff check + format check
make fmt       # ruff autofix + format
make migrate   # alembic upgrade head inside the app container
make logs      # follow the app logs (JSON lines)
make down      # stop everything
```

### Configuration

The app is configured only through environment variables: `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD` (no default) and `LOG_LEVEL`. Logs are written to stdout as JSON, one line per request with method, route, status and duration.

## Architecture

_Coming soon._

## Infrastructure

Terraform lives in [`infra/`](infra/README.md): a bootstrap for the remote state (S3 with native locking) and a cost budget, a VPC module written from scratch, and the `dev` environment. So far the `dev` environment creates the network (public and private subnets across 2 AZs, NAT Gateway); ECS, ALB and RDS are next.

## CI/CD

_Coming soon._

## Monitoring

_Coming soon._

## Cost

_Coming soon._
