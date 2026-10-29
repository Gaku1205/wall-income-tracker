"""見本の API（FastAPI）。AWS App Runner で動かす。"""

from fastapi import FastAPI

from app.greeting import greet

app = FastAPI(title="hello-python")


@app.get("/health")
def health() -> dict[str, str]:
    """App Runner のヘルスチェック用。"""
    return {"status": "ok"}


@app.get("/hello")
def hello(name: str | None = None) -> dict[str, str]:
    """名前にあいさつする。"""
    return {"message": greet(name)}
