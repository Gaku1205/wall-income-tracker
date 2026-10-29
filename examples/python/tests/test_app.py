import pytest
from fastapi.testclient import TestClient

from app.greeting import greet
from app.main import app
from cli import main

client = TestClient(app)


def test_greet_uses_name() -> None:
    assert greet("Gaku") == "Hello, Gaku!"


def test_greet_falls_back_to_world() -> None:
    assert greet(None) == "Hello, world!"
    assert greet("   ") == "Hello, world!"


def test_health() -> None:
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_hello() -> None:
    assert client.get("/hello", params={"name": "Fukuoka"}).json() == {"message": "Hello, Fukuoka!"}
    assert client.get("/hello").json() == {"message": "Hello, world!"}


def test_cli(capsys: pytest.CaptureFixture[str]) -> None:
    assert main(["hello", "Hakata"]) == 0
    assert capsys.readouterr().out.strip() == "Hello, Hakata!"
