import pytest
from proteus.pipeline.loader import Stage
from proteus.pipeline.handlers import cmd_dagger, cmd_skopeo, cmd_dispatch, HANDLERS
from proteus.pipeline.errors import PipelineConfigError
from proteus.pipeline.runner import run


def test_cmd_dagger_build_argv():
    """Test dagger build stage emits correct argv."""
    stage = Stage(
        name="build",
        type="dagger",
        function="build",
        script=None,
        args={"context": ".", "tag": "staging"},
        depends_on=(),
    )

    argv = cmd_dagger(stage)
    assert argv == ["dagger", "call", "build", "--context", ".", "--tag", "staging"]


def test_cmd_dagger_test_argv():
    """Test dagger test stage emits correct argv."""
    stage = Stage(
        name="test",
        type="dagger",
        function="test",
        script=None,
        args={"command": "just test"},
        depends_on=(),
    )

    argv = cmd_dagger(stage)
    assert argv == ["dagger", "call", "test", "--command", "just test"]


def test_cmd_skopeo_argv():
    """Test skopeo stage emits correct argv."""
    stage = Stage(
        name="promote",
        type="skopeo",
        function=None,
        script="scripts/promote-image.sh",
        args=["ghcr.io/homeric-intelligence/achaean-fleet:staging",
              "ghcr.io/homeric-intelligence/achaean-fleet:latest"],
        depends_on=(),
    )

    argv = cmd_skopeo(stage)
    assert argv == [
        "scripts/promote-image.sh",
        "ghcr.io/homeric-intelligence/achaean-fleet:staging",
        "ghcr.io/homeric-intelligence/achaean-fleet:latest",
    ]


def test_cmd_dispatch_argv():
    """Test dispatch stage emits correct argv."""
    stage = Stage(
        name="dispatch-apply",
        type="dispatch",
        function=None,
        script="scripts/dispatch-apply.sh",
        args=["hermes"],
        depends_on=(),
    )

    argv = cmd_dispatch(stage)
    assert argv == ["scripts/dispatch-apply.sh", "hermes"]


def test_runner_rejects_unknown_type():
    """Test runner raises PipelineConfigError for unknown stage type."""
    from proteus.pipeline.loader import Pipeline

    pipeline = Pipeline(
        name="test",
        description="",
        on_events=(),
        registry={},
        stages=(
            Stage(
                name="bogus",
                type="bogus",
                function=None,
                script=None,
                args={},
                depends_on=(),
            ),
        ),
        notifications_on_failure=(),
        notifications_on_success=(),
    )

    with pytest.raises(PipelineConfigError, match="no handler for stage type"):
        run(pipeline, dry_run=True)


def test_cmd_dagger_missing_function_raises():
    """Test dagger handler raises when function is None."""
    stage = Stage(
        name="build",
        type="dagger",
        function=None,
        script=None,
        args={},
        depends_on=(),
    )

    with pytest.raises(PipelineConfigError, match="missing function"):
        cmd_dagger(stage)


def test_cmd_skopeo_missing_script_raises():
    """Test skopeo handler raises when script is None."""
    stage = Stage(
        name="promote",
        type="skopeo",
        function=None,
        script=None,
        args=["a", "b"],
        depends_on=(),
    )

    with pytest.raises(PipelineConfigError, match="missing script"):
        cmd_skopeo(stage)


def test_cmd_skopeo_too_few_args_raises():
    """Test skopeo handler raises when fewer than 2 positional args given."""
    stage = Stage(
        name="promote",
        type="skopeo",
        function=None,
        script="scripts/promote-image.sh",
        args=["a"],
        depends_on=(),
    )

    with pytest.raises(PipelineConfigError, match="2 positional"):
        cmd_skopeo(stage)


def test_cmd_dispatch_missing_script_raises():
    """Test dispatch handler raises when script is None."""
    stage = Stage(
        name="dispatch-apply",
        type="dispatch",
        function=None,
        script=None,
        args=["hermes"],
        depends_on=(),
    )

    with pytest.raises(PipelineConfigError, match="missing script"):
        cmd_dispatch(stage)


def test_cmd_dispatch_missing_host_raises():
    """Test dispatch handler raises when no positional host arg given."""
    stage = Stage(
        name="dispatch-apply",
        type="dispatch",
        function=None,
        script="scripts/dispatch-apply.sh",
        args=[],
        depends_on=(),
    )

    with pytest.raises(PipelineConfigError, match="1 positional"):
        cmd_dispatch(stage)
