import logging

from fastapi import APIRouter
from fastapi.responses import JSONResponse
from pydantic import ValidationError
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError

from demo_api.db import get_engine

router = APIRouter(prefix="/health", tags=["health"])
logger = logging.getLogger(__name__)


@router.get("")
def liveness() -> dict[str, str]:
    """Liveness probe: never touches the database."""
    return {"status": "ok"}


@router.get("/db")
def database() -> JSONResponse:
    """Readiness of the database connection."""
    try:
        with get_engine().connect() as conn:
            conn.execute(text("SELECT 1"))
    except ValidationError:
        logger.warning("database settings are missing")
        return JSONResponse(status_code=503, content={"status": "unavailable"})
    except SQLAlchemyError:
        logger.warning("database health check failed", exc_info=True)
        return JSONResponse(status_code=503, content={"status": "unavailable"})
    return JSONResponse(status_code=200, content={"status": "ok"})
