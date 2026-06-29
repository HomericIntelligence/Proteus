import pytest
from pathlib import Path
from proteus.pipeline import load_pipeline, Pipeline, Stage, PipelineConfigError


def test_load_real_config_succeeds():
    """Verify achaean-fleet.yaml loads successfully with correct structure."""
    pipeline = load_pipeline(Path("configs/pipelines/achaean-fleet.yaml"))

    assert isinstance(pipeline, Pipeline)
    assert pipeline.name == "achaean-fleet"
    assert len(pipeline.stages) == 4
    assert pipeline.stages[0].name == "build"
    assert pipeline.stages[1].name == "test"
    assert pipeline.stages[2].name == "promote"
    assert pipeline.stages[3].name == "dispatch-apply"

    # Verify notifications are parsed correctly
    assert pipeline.notifications_on_failure == ("#ci-alerts",)
    assert pipeline.notifications_on_success == ("#deployments",)


def test_missing_required_top_level_raises(tmp_path):
    """YAML lacking required 'stages' field should raise PipelineConfigError."""
    yaml_file = tmp_path / "invalid.yaml"
    yaml_file.write_text("name: test\n")

    with pytest.raises(PipelineConfigError, match="stages"):
        load_pipeline(yaml_file)


def test_unknown_top_level_key_raises(tmp_path):
    """YAML with invalid stage structure should raise PipelineConfigError."""
    yaml_file = tmp_path / "invalid.yaml"
    yaml_file.write_text("name: test\nstages:\n  - name: build\n    type: dagger\n")

    with pytest.raises(PipelineConfigError):
        load_pipeline(yaml_file)


def test_dagger_build_missing_context_raises(tmp_path):
    """Dagger build stage missing 'context' in args should raise."""
    yaml_file = tmp_path / "invalid.yaml"
    yaml_file.write_text("""
name: test
stages:
  - name: build
    type: dagger
    function: build
    args:
      tag: staging
""")

    with pytest.raises(PipelineConfigError):
        load_pipeline(yaml_file)


def test_dagger_test_missing_command_raises(tmp_path):
    """Dagger test stage missing 'command' in args should raise."""
    yaml_file = tmp_path / "invalid.yaml"
    yaml_file.write_text("""
name: test
stages:
  - name: test
    type: dagger
    function: test
    args: {}
""")

    with pytest.raises(PipelineConfigError):
        load_pipeline(yaml_file)


def test_skopeo_too_few_args_raises(tmp_path):
    """Skopeo stage with fewer than 2 positional args should raise."""
    yaml_file = tmp_path / "invalid.yaml"
    yaml_file.write_text("""
name: test
stages:
  - name: promote
    type: skopeo
    script: scripts/promote-image.sh
    args:
      - ghcr.io/test:src
""")

    with pytest.raises(PipelineConfigError, match="not valid|minItems"):
        load_pipeline(yaml_file)


def test_dispatch_missing_host_raises(tmp_path):
    """Dispatch stage with no positional args should raise."""
    yaml_file = tmp_path / "invalid.yaml"
    yaml_file.write_text("""
name: test
stages:
  - name: dispatch
    type: dispatch
    script: scripts/dispatch-apply.sh
    args: []
""")

    with pytest.raises(PipelineConfigError, match="not valid|minItems"):
        load_pipeline(yaml_file)


def test_iter_errors_reports_multiple(tmp_path):
    """Multiple validation errors should all be reported."""
    yaml_file = tmp_path / "invalid.yaml"
    yaml_file.write_text("name: test\nstages: []\n")

    with pytest.raises(PipelineConfigError) as exc_info:
        load_pipeline(yaml_file)

    error_msg = str(exc_info.value)
    assert "non-empty" in error_msg
