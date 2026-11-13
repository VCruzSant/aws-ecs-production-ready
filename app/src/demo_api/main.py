import logging
import time
from collections.abc import Awaitable, Callable

from fastapi import FastAPI, Request, Response

from demo_api.routes import health, tasks

logger = logging.getLogger("demo_api.request")

app = FastAPI(title="Demo Tasks API", version="0.1.0")
app.include_router(health.router)
app.include_router(tasks.router)


@app.middleware("http")
async def log_requests(
    request: Request, call_next: Callable[[Request], Awaitable[Response]]
) -> Response:
    start = time.perf_counter()
    status_code = 500
    try:
        response = await call_next(request)
        status_code = response.status_code
        return response
    finally:
        route = request.scope.get("route")
        logger.info(
            "request",
            extra={
                "method": request.method,
                "route": getattr(route, "path", request.url.path),
                "status": status_code,
                "duration_ms": round((time.perf_counter() - start) * 1000, 2),
            },
        )
