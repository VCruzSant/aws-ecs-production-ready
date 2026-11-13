from fastapi.testclient import TestClient


def _create(client: TestClient, title: str = "Write the README") -> dict:
    response = client.post("/tasks", json={"title": title})
    assert response.status_code == 201
    return response.json()


def test_create_task(client: TestClient) -> None:
    task = _create(client)
    assert task["id"] > 0
    assert task["title"] == "Write the README"
    assert task["done"] is False
    assert task["created_at"]


def test_create_task_requires_title(client: TestClient) -> None:
    assert client.post("/tasks", json={}).status_code == 422
    assert client.post("/tasks", json={"title": ""}).status_code == 422
    assert client.post("/tasks", json={"title": "x" * 201}).status_code == 422


def test_list_tasks(client: TestClient) -> None:
    first = _create(client, "first")
    second = _create(client, "second")
    response = client.get("/tasks")
    assert response.status_code == 200
    ids = [task["id"] for task in response.json()]
    assert ids == [first["id"], second["id"]]


def test_get_task_not_found(client: TestClient) -> None:
    response = client.get("/tasks/999999")
    assert response.status_code == 404
    assert response.json() == {"detail": "Task not found"}


def test_update_task_done(client: TestClient) -> None:
    task = _create(client)
    response = client.patch(f"/tasks/{task['id']}", json={"done": True})
    assert response.status_code == 200
    assert response.json()["done"] is True
    assert response.json()["title"] == task["title"]
    assert client.get(f"/tasks/{task['id']}").json()["done"] is True


def test_delete_task(client: TestClient) -> None:
    task = _create(client)
    response = client.delete(f"/tasks/{task['id']}")
    assert response.status_code == 204
    assert response.content == b""
    assert client.get(f"/tasks/{task['id']}").status_code == 404
