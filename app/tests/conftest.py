"""Tests run against the Postgres from docker compose, in a separate database.

The test database (`<DB_NAME>_test` unless TEST_DB_NAME is set) is created if needed and
migrated with Alembic. Each test runs inside a transaction that is rolled back afterwards.
"""

import os
from collections.abc import Iterator
from pathlib import Path

import pytest
from alembic import command
from alembic.config import Config
from fastapi.testclient import TestClient
from sqlalchemy import Connection, create_engine, text
from sqlalchemy.orm import Session

APP_DIR = Path(__file__).resolve().parent.parent

_admin_db = os.environ.get("DB_NAME", "postgres")
os.environ["DB_NAME"] = os.environ.get("TEST_DB_NAME", f"{_admin_db}_test")

from demo_api.config import get_database_settings  # noqa: E402
from demo_api.db import get_engine, get_session  # noqa: E402
from demo_api.main import app  # noqa: E402


def _ensure_database() -> None:
    settings = get_database_settings()
    admin_url = settings.database_url.set(database=_admin_db)
    admin_engine = create_engine(admin_url, isolation_level="AUTOCOMMIT")
    with admin_engine.connect() as conn:
        exists = conn.scalar(
            text("SELECT 1 FROM pg_database WHERE datname = :name"), {"name": settings.db_name}
        )
        if not exists:
            conn.execute(text(f'CREATE DATABASE "{settings.db_name}"'))
    admin_engine.dispose()


@pytest.fixture(scope="session")
def db_connection() -> Iterator[Connection]:
    _ensure_database()
    engine = get_engine()
    with engine.connect() as conn:
        cfg = Config(str(APP_DIR / "alembic.ini"))
        cfg.attributes["connection"] = conn
        cfg.attributes["configure_logger"] = False
        command.upgrade(cfg, "head")
        conn.commit()
        yield conn


@pytest.fixture
def session(db_connection: Connection) -> Iterator[Session]:
    transaction = db_connection.begin()
    session = Session(bind=db_connection, join_transaction_mode="create_savepoint")
    try:
        yield session
    finally:
        session.close()
        transaction.rollback()


@pytest.fixture
def client(session: Session) -> Iterator[TestClient]:
    app.dependency_overrides[get_session] = lambda: session
    with TestClient(app) as test_client:
        yield test_client
    app.dependency_overrides.clear()
