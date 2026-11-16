from collections.abc import Iterator

import pytest
from fastapi.testclient import TestClient

from demo_api.config import get_database_settings, get_settings
from demo_api.db import get_engine
from demo_api.main import app


def test_health_ok(client: TestClient) -> None:
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok", "version": "dev"}


def test_health_shows_app_version(client: TestClient, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("APP_VERSION", "abc1234")
    get_settings.cache_clear()
    try:
        response = client.get("/health")
    finally:
        get_settings.cache_clear()
    assert response.json() == {"status": "ok", "version": "abc1234"}


def test_health_db_ok(client: TestClient) -> None:
    response = client.get("/health/db")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


@pytest.fixture
def no_database_config(monkeypatch: pytest.MonkeyPatch) -> Iterator[None]:
    for name in ("DB_HOST", "DB_PORT", "DB_NAME", "DB_USER", "DB_PASSWORD"):
        monkeypatch.delenv(name, raising=False)
    get_database_settings.cache_clear()
    get_engine.cache_clear()
    yield
    get_database_settings.cache_clear()
    get_engine.cache_clear()


@pytest.mark.usefixtures("no_database_config")
def test_starts_without_database_config() -> None:
    with TestClient(app) as client:
        assert client.get("/health").status_code == 200
        response = client.get("/health/db")
        assert response.status_code == 503
        assert response.json() == {"status": "unavailable"}
