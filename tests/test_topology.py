import pytest
from pathlib import Path
from proteus.pipeline import load_pipeline, PipelineConfigError
from proteus.pipeline.topology import topo_sort


def test_topo_sort_achaean_fleet_order():
    """Verify topological sort orders achaean-fleet.yaml stages correctly."""
    pipeline = load_pipeline(Path("configs/pipelines/achaean-fleet.yaml"))
    ordered = topo_sort(pipeline.stages)

    names = [s.name for s in ordered]
    assert names == ["build", "test", "promote", "dispatch-apply"]


def test_self_loop_raises(tmp_path):
    """Stage depending on itself should raise PipelineConfigError."""
    yaml_file = tmp_path / "self_loop.yaml"
    yaml_file.write_text("""
name: test
stages:
  - name: build
    type: dagger
    function: build
    args:
      context: "."
      tag: staging
    depends_on: [build]
""")

    pipeline = load_pipeline(yaml_file)
    with pytest.raises(PipelineConfigError, match="depends on itself"):
        topo_sort(pipeline.stages)


def test_unknown_dependency_raises(tmp_path):
    """Stage depending on unknown stage should raise PipelineConfigError."""
    yaml_file = tmp_path / "unknown_dep.yaml"
    yaml_file.write_text("""
name: test
stages:
  - name: build
    type: dagger
    function: build
    args:
      context: "."
      tag: staging
    depends_on: [nonexistent]
""")

    pipeline = load_pipeline(yaml_file)
    with pytest.raises(PipelineConfigError, match="unknown stage"):
        topo_sort(pipeline.stages)


def test_cycle_raises(tmp_path):
    """Cycle in dependencies should raise PipelineConfigError."""
    yaml_file = tmp_path / "cycle.yaml"
    yaml_file.write_text("""
name: test
stages:
  - name: a
    type: dagger
    function: build
    args:
      context: "."
      tag: staging
    depends_on: [b]
  - name: b
    type: dagger
    function: build
    args:
      context: "."
      tag: staging
    depends_on: [a]
""")

    pipeline = load_pipeline(yaml_file)
    with pytest.raises(PipelineConfigError, match="cycle"):
        topo_sort(pipeline.stages)
