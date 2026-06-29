import shlex
import subprocess
from .handlers import HANDLERS
from .loader import Pipeline
from .topology import topo_sort
from .errors import PipelineConfigError


def run(pipeline: Pipeline, *, dry_run: bool = False) -> int:
    for stage in topo_sort(pipeline.stages):
        handler = HANDLERS.get(stage.type)
        if handler is None:
            raise PipelineConfigError(f"no handler for stage type {stage.type!r}")
        argv = handler(stage)
        print(f"[{stage.name}] " + " ".join(shlex.quote(a) for a in argv))
        if dry_run:
            continue
        subprocess.run(argv, check=True)
    return 0
