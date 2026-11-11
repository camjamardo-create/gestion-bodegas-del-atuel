"""Exporta el esquema OpenAPI a docs/api/openapi.json."""

from __future__ import annotations

import json
from pathlib import Path

from app.main import app


def main() -> None:
    destino = Path(__file__).resolve().parents[1] / "docs" / "api" / "openapi.json"
    destino.parent.mkdir(parents=True, exist_ok=True)
    destino.write_text(
        json.dumps(app.openapi(), ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"OpenAPI exportado en {destino}")


if __name__ == "__main__":
    main()
