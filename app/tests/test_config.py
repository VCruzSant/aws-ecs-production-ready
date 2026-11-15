import pytest
from pydantic import ValidationError

from demo_api.config import DatabaseSettings

BASE = {"db_host": "db", "db_name": "demo", "db_user": "demo", "db_password": "secret"}


def test_sslmode_defaults_to_prefer(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("DB_SSLMODE", raising=False)
    assert DatabaseSettings(**BASE).database_url.query["sslmode"] == "prefer"


def test_sslmode_from_environment(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("DB_SSLMODE", "require")
    assert DatabaseSettings(**BASE).database_url.query["sslmode"] == "require"


def test_sslmode_rejects_unknown_value(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("DB_SSLMODE", "always")
    with pytest.raises(ValidationError):
        DatabaseSettings(**BASE)
