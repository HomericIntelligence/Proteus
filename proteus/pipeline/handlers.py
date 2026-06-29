from typing import Callable
from .loader import Stage
from .errors import PipelineConfigError


_DAGGER_KEY_ORDER = ("context", "source", "name", "tag", "command", "registry")


def cmd_dagger(stage: Stage) -> list[str]:
    if stage.function is None:
        raise PipelineConfigError(f"dagger stage {stage.name!r} missing function")
    argv = ["dagger", "call", stage.function]
    for key in _DAGGER_KEY_ORDER:
        if key in stage.args:
            argv += [f"--{key}", str(stage.args[key])]
    return argv


def cmd_skopeo(stage: Stage) -> list[str]:
    if stage.script is None:
        raise PipelineConfigError(f"skopeo stage {stage.name!r} missing script")
    args = list(stage.args)
    if len(args) < 2:
        raise PipelineConfigError(
            f"skopeo stage {stage.name!r} requires 2 positional args (src, dest)"
        )
    return [stage.script, *map(str, args)]


def cmd_dispatch(stage: Stage) -> list[str]:
    if stage.script is None:
        raise PipelineConfigError(f"dispatch stage {stage.name!r} missing script")
    args = list(stage.args)
    if len(args) < 1:
        raise PipelineConfigError(
            f"dispatch stage {stage.name!r} requires 1 positional arg (host)"
        )
    return [stage.script, *map(str, args)]


HANDLERS: dict[str, Callable[[Stage], list[str]]] = {
    "dagger": cmd_dagger,
    "skopeo": cmd_skopeo,
    "dispatch": cmd_dispatch,
}
