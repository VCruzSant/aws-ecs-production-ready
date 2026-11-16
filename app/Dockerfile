# syntax=docker/dockerfile:1

FROM python:3.12-slim AS builder

COPY --from=ghcr.io/astral-sh/uv:0.12.5 /uv /bin/uv

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=0

WORKDIR /app

# Dependencies first, so this layer is cached until the lockfile changes.
COPY pyproject.toml uv.lock ./
RUN uv sync --locked --no-dev --no-install-project

COPY src ./src
RUN uv sync --locked --no-dev --no-editable

FROM python:3.12-slim

# Debian security fixes land before the base tag is rebuilt; the app runs from the venv, so pip goes.
RUN apt-get update \
    && apt-get upgrade -y --no-install-recommends \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /usr/local/bin/pip* /usr/local/lib/python3.12/site-packages/pip* \
    && groupadd --system --gid 10001 app \
    && useradd --system --uid 10001 --gid app --no-create-home --shell /usr/sbin/nologin app

# Root CAs of RDS for sslmode=verify-full; the build fails if AWS changes the file.
ARG RDS_CA_REGION=us-east-2
ARG RDS_CA_SHA256=d46e1bdfda05c8e7644e50930806a19b139a222542bf0348082fb59ece2b5fa5
ADD --checksum=sha256:${RDS_CA_SHA256} --chmod=644 \
    https://truststore.pki.rds.amazonaws.com/${RDS_CA_REGION}/${RDS_CA_REGION}-bundle.pem /etc/ssl/certs/rds-ca.pem

WORKDIR /app

COPY --from=builder --chown=app:app /app/.venv /app/.venv
COPY --chown=app:app alembic.ini ./
COPY --chown=app:app migrations ./migrations

ENV PATH="/app/.venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

# Last, so a new commit only rebuilds this layer.
ARG APP_VERSION=dev
ENV APP_VERSION=${APP_VERSION}

USER app

EXPOSE 8000

CMD ["python", "-m", "demo_api"]
