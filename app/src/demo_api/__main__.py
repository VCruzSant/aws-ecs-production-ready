import uvicorn

from demo_api.config import get_settings
from demo_api.logging_config import build_logging_config


def main() -> None:
    settings = get_settings()
    uvicorn.run(
        "demo_api.main:app",
        host="0.0.0.0",  # noqa: S104 - must listen on all interfaces inside the container
        port=8000,
        log_config=build_logging_config(settings.log_level),
        access_log=False,
        proxy_headers=True,
    )


if __name__ == "__main__":
    main()
