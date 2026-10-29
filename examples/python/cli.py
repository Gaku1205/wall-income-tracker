"""見本の CLI。GitHub Releases に exe として置く（pyinstaller で1つのファイルにする）。

使い方：hello [名前]
"""

import sys

from app.greeting import greet


def main(argv: list[str]) -> int:
    print(greet(argv[1] if len(argv) > 1 else None))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
