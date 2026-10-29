"""あいさつの文を作る。API（app/main.py）と CLI（cli.py）の両方が使う。"""

DEFAULT_NAME = "world"


def greet(name: str | None = None) -> str:
    """名前にあいさつする。空や空白だけなら world にあいさつする。"""
    cleaned = (name or "").strip()
    return f"Hello, {cleaned or DEFAULT_NAME}!"
