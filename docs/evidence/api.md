# API through the load balancer

Requests against the ALB DNS name (replaced here, it stops resolving after destroy), then the JSON log lines the same requests produced in CloudWatch Logs.

## Requests

```
$ curl -i $URL/health
HTTP/1.1 200 OK
Content-Type: application/json
Content-Length: 15
Connection: keep-alive
server: uvicorn

{"status":"ok"}

$ curl -i $URL/health/db
HTTP/1.1 200 OK
Content-Type: application/json
Content-Length: 15
Connection: keep-alive
server: uvicorn

{"status":"ok"}

$ curl -X POST $URL/tasks -d {"title":"Ship it"}
{"id":1,"title":"Ship it","done":false,"created_at":"2026-11-15T20:08:14.884977Z"}
$ curl $URL/tasks
[{"id":1,"title":"Ship it","done":false,"created_at":"2026-11-15T20:08:14.884977Z"}]
$ curl -X PATCH $URL/tasks/1 -d {"done":true}
{"id":1,"title":"Ship it","done":true,"created_at":"2026-11-15T20:08:14.884977Z"}
$ curl -X DELETE $URL/tasks/1
HTTP 204
$ curl $URL/tasks
[]
```

## Logs

`aws logs tail <log-group> --since 15m`, last lines:

```
2026-11-15T20:08:13.807000+00:00 app/app/<task-id> {"timestamp": "2026-11-15T20:08:13.807263+00:00", "level": "INFO", "logger": "demo_api.request", "message": "request", "method": "GET", "route": "/health", "status": 200, "duration_ms": 0.69}
2026-11-15T20:08:14.558000+00:00 app/app/<task-id> {"timestamp": "2026-11-15T20:08:14.558794+00:00", "level": "INFO", "logger": "demo_api.request", "message": "request", "method": "GET", "route": "/health/db", "status": 200, "duration_ms": 436.6}
2026-11-15T20:08:14.892000+00:00 app/app/<task-id> {"timestamp": "2026-11-15T20:08:14.892200+00:00", "level": "INFO", "logger": "demo_api.request", "message": "request", "method": "POST", "route": "/tasks", "status": 201, "duration_ms": 15.44}
2026-11-15T20:08:15.210000+00:00 app/app/<task-id> {"timestamp": "2026-11-15T20:08:15.210382+00:00", "level": "INFO", "logger": "demo_api.request", "message": "request", "method": "GET", "route": "/tasks", "status": 200, "duration_ms": 3.96}
2026-11-15T20:08:15.534000+00:00 app/app/<task-id> {"timestamp": "2026-11-15T20:08:15.534766+00:00", "level": "INFO", "logger": "demo_api.request", "message": "request", "method": "PATCH", "route": "/tasks/{task_id}", "status": 200, "duration_ms": 10.35}
2026-11-15T20:08:15.854000+00:00 app/app/<task-id> {"timestamp": "2026-11-15T20:08:15.854813+00:00", "level": "INFO", "logger": "demo_api.request", "message": "request", "method": "DELETE", "route": "/tasks/{task_id}", "status": 204, "duration_ms": 5.34}
2026-11-15T20:08:16.169000+00:00 app/app/<task-id> {"timestamp": "2026-11-15T20:08:16.169490+00:00", "level": "INFO", "logger": "demo_api.request", "message": "request", "method": "GET", "route": "/tasks", "status": 200, "duration_ms": 2.65}
```
