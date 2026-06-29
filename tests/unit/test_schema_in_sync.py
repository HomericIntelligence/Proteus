import json
import pytest
from pathlib import Path
from proteus.models import Pipeline


def test_schema_matches_committed():
    """Committed schema.json matches the Pydantic-generated schema (semantic equality)."""
    schema_path = Path("configs/pipelines/schema.json")
    if not schema_path.exists():
        pytest.skip(
            "schema.json not yet generated. Run:\n"
            "  pixi run python -m proteus dump-schema > configs/pipelines/schema.json"
        )

    committed = json.loads(schema_path.read_text())
    generated = Pipeline.model_json_schema()

    assert committed == generated, (
        "schema.json is out of sync. To regenerate:\n"
        "  pixi run python -m proteus dump-schema > configs/pipelines/schema.json"
    )
