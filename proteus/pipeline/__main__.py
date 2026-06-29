import argparse
import glob
import sys
from pathlib import Path

from .loader import load_pipeline
from .runner import run
from .errors import PipelineConfigError


def _validate(pattern: str) -> int:
    paths = [Path(p) for p in sorted(glob.glob(pattern))]
    if not paths:
        print(f"error: no files matched {pattern!r}", file=sys.stderr)
        return 1
    failures = 0
    for p in paths:
        try:
            load_pipeline(p)
            print(f"  OK: {p}")
        except PipelineConfigError as e:
            print(f"  FAIL: {e}", file=sys.stderr)
            failures += 1
    return 1 if failures else 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="python -m proteus.pipeline")
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("validate").add_argument("pattern")
    p_run = sub.add_parser("run")
    p_run.add_argument("path")
    p_run.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)
    if args.cmd == "validate":
        return _validate(args.pattern)
    path = Path(args.path)
    if not path.exists():
        print(f"error: {path} not found", file=sys.stderr)
        return 2
    return run(load_pipeline(path), dry_run=args.dry_run)


if __name__ == "__main__":
    sys.exit(main())
