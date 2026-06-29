from __future__ import annotations
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Mapping, Sequence, Union
import yaml
from jsonschema import Draft7Validator

from .errors import PipelineConfigError


SCHEMA_PATH = Path(__file__).resolve().parents[2] / "schemas" / "pipeline.schema.json"
_schema_cache: dict[Path, dict] = {}


@dataclass(frozen=True)
class Stage:
    name: str
    type: str
    function: str | None
    script: str | None
    # dagger stages carry named args (Mapping); skopeo/dispatch stages carry
    # positional args (Sequence) per the canonical config schema.
    args: Union[Mapping[str, str], Sequence[str]]
    depends_on: tuple[str, ...]


@dataclass(frozen=True)
class Pipeline:
    name: str
    description: str
    on_events: tuple[Mapping[str, str], ...]
    registry: Mapping[str, str]
    stages: tuple[Stage, ...]
    notifications_on_failure: tuple[str, ...]
    notifications_on_success: tuple[str, ...]


def _load_schema(path: Path = SCHEMA_PATH) -> dict:
    if path not in _schema_cache:
        _schema_cache[path] = json.loads(path.read_text())
    return _schema_cache[path]


def _load_yaml(path: Path) -> dict:
    with path.open() as f:
        return yaml.safe_load(f)


def load_pipeline(path: Path) -> Pipeline:
    data = _load_yaml(path)
    errors = list(Draft7Validator(_load_schema()).iter_errors(data))
    if errors:
        msg = "; ".join(f"{'/'.join(map(str, e.absolute_path))}: {e.message}" for e in errors)
        raise PipelineConfigError(f"{path}: {msg}")

    def _coerce_args(raw):
        # Named args (dagger) stay a dict; positional args (skopeo/dispatch)
        # stay a list, matching the canonical pipeline schema.
        if isinstance(raw, list):
            return list(raw)
        return dict(raw or {})

    stages = tuple(
        Stage(
            name=s["name"],
            type=s["type"],
            function=s.get("function"),
            script=s.get("script"),
            args=_coerce_args(s.get("args")),
            depends_on=tuple(s.get("depends_on", [])),
        )
        for s in data["stages"]
    )

    notif = data.get("notifications") or {}
    return Pipeline(
        name=data["name"],
        description=data.get("description", ""),
        on_events=tuple(data.get("triggers", [])),
        registry=dict(data.get("registry", {})),
        stages=stages,
        notifications_on_failure=tuple(c["channel"] for c in notif.get("on_failure", [])),
        notifications_on_success=tuple(c["channel"] for c in notif.get("on_success", [])),
    )
