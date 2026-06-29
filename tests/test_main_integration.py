import subprocess
import sys


def test_dry_run_emits_expected_lines():
    """Test dry-run output matches expected format."""
    result = subprocess.run(
        [sys.executable, "-m", "proteus.pipeline", "run", "--dry-run",
         "configs/pipelines/achaean-fleet.yaml"],
        capture_output=True,
        text=True,
    )

    assert result.returncode == 0, f"stderr: {result.stderr}"

    lines = result.stdout.strip().split("\n")
    assert len(lines) == 4

    assert lines[0] == "[build] dagger call build --context . --tag staging"
    assert lines[1] == "[test] dagger call test --command 'just test'"
    assert lines[2] == "[promote] scripts/promote-image.sh ghcr.io/homeric-intelligence/achaean-fleet:staging ghcr.io/homeric-intelligence/achaean-fleet:latest"
    assert lines[3] == "[dispatch-apply] scripts/dispatch-apply.sh hermes"


def test_validate_globs_real_configs():
    """Test validate command succeeds on real configs."""
    result = subprocess.run(
        [sys.executable, "-m", "proteus.pipeline", "validate",
         "configs/pipelines/*.yaml"],
        capture_output=True,
        text=True,
    )

    assert result.returncode == 0, f"stderr: {result.stderr}"
    assert "OK" in result.stdout
    assert "achaean-fleet.yaml" in result.stdout
