import pytest
from fastapi.testclient import TestClient
from sqlalchemy import text

from app.database import engine
from app.main import app

client = TestClient(app)
VALID = {
    "title": "  Product review  ",
    "starts_at": "2026-09-30T10:00:00+03:00",
    "ends_at": "2026-09-30T11:00:00+03:00",
    "attendee_count": 4,
}


@pytest.fixture(autouse=True)
def clean_database():
    # Only run against a dedicated test DB: CI creates spry_test.
    assert engine.url.database.endswith("_test"), "Refusing to clear a non-test database"
    with engine.begin() as connection:
        connection.execute(text("DELETE FROM meetings"))


def test_create_persist_and_list():
    assert client.get("/api/meetings").json() == []
    response = client.post("/api/meetings", json=VALID)
    assert response.status_code == 201
    meeting = response.json()
    assert meeting["title"] == "Product review"
    assert meeting["starts_at"] == "2026-09-30T07:00:00Z"
    assert client.get("/api/meetings").json() == [meeting]
    assert client.get("/health").status_code == 200


@pytest.mark.parametrize(
    "changes",
    [
        {"title": "  "},
        {"title": "x" * 201},
        {"attendee_count": -1},
        {"attendee_count": 2147483648},
        {"attendee_count": 1.5},
        {"attendee_count": True},
        {"starts_at": "2026-09-30T10:00:00"},
        {"starts_at": 123456},
        {"ends_at": "2026-09-30T10:00:00+03:00"},
        {"unexpected": True},
    ],
)
def test_invalid_input(changes):
    assert client.post("/api/meetings", json=VALID | changes).status_code == 422
    assert client.get("/api/meetings").json() == []


def test_sorting():
    client.post("/api/meetings", json=VALID)
    client.post(
        "/api/meetings",
        json=VALID
        | {
            "title": "Earlier",
            "starts_at": "2026-09-29T10:00:00Z",
            "ends_at": "2026-09-29T11:00:00Z",
        },
    )
    assert client.get("/api/meetings").json()[0]["title"] == "Earlier"
