from functools import lru_cache
from typing import Literal

from pydantic import SecretStr
from pydantic_settings import BaseSettings
from sqlalchemy import URL

SslMode = Literal["disable", "allow", "prefer", "require", "verify-ca", "verify-full"]


class Settings(BaseSettings):
    """Settings the API needs to start, read from environment variables."""

    log_level: str = "INFO"


class DatabaseSettings(BaseSettings):
    """Database settings, loaded only when a route needs the database."""

    db_host: str
    db_port: int = 5432
    db_name: str
    db_user: str
    db_password: SecretStr
    # "prefer" keeps the local compose Postgres (no TLS) working; AWS sets "require".
    db_sslmode: SslMode = "prefer"

    @property
    def database_url(self) -> URL:
        return URL.create(
            drivername="postgresql+psycopg",
            username=self.db_user,
            password=self.db_password.get_secret_value(),
            host=self.db_host,
            port=self.db_port,
            database=self.db_name,
            query={"sslmode": self.db_sslmode},
        )


@lru_cache
def get_settings() -> Settings:
    return Settings()


@lru_cache
def get_database_settings() -> DatabaseSettings:
    return DatabaseSettings()  # type: ignore[call-arg]
