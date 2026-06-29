from collections import deque
from .loader import Stage
from .errors import PipelineConfigError


def topo_sort(stages: tuple[Stage, ...]) -> list[Stage]:
    names = {s.name for s in stages}

    for s in stages:
        if s.name in s.depends_on:
            raise PipelineConfigError(f"stage {s.name!r} depends on itself")

        unknown = [d for d in s.depends_on if d not in names]
        if unknown:
            raise PipelineConfigError(
                f"stage {s.name!r} depends_on references unknown stage(s): {unknown}")

    indeg = {s.name: len(s.depends_on) for s in stages}
    by_name = {s.name: s for s in stages}
    ready = deque(sorted(n for n, d in indeg.items() if d == 0))
    order: list[Stage] = []

    while ready:
        n = ready.popleft()
        order.append(by_name[n])
        for s in stages:
            if n in s.depends_on:
                indeg[s.name] -= 1
                if indeg[s.name] == 0:
                    ready.append(s.name)

    if len(order) != len(stages):
        remaining = sorted(set(names) - {s.name for s in order})
        raise PipelineConfigError(f"cycle in depends_on among: {remaining}")

    return order
