import { test } from "node:test"
import assert from "node:assert/strict"
import { spawnSync } from "node:child_process"

// As of #82 the `just pipeline NAME` recipe no longer inlines the
// build→test→promote→dispatch commands. Instead it delegates to the
// proteus runner, which reads `configs/pipelines/<NAME>.yaml` and executes
// the declared stages (including the staging→production promote stage).
// The staging-ref contract itself is unit-tested in tag.test.ts and the
// stage wiring in the Python runner tests (tests/unit/test_runner.py).
test("just pipeline delegates to the proteus config runner", () => {
  const repoRoot = new URL("../..", import.meta.url).pathname
  const result = spawnSync("just", ["--dry-run", "pipeline", "achaean-fleet"], {
    cwd: repoRoot,
    encoding: "utf8",
  })
  const out = result.stderr // just --dry-run outputs to stderr

  assert.match(
    out,
    /proteus run configs\/pipelines\/achaean-fleet\.yaml/,
    `pipeline must drive the proteus runner against the named config, got:\n${out}`,
  )
  assert.match(
    out,
    /--service achaean-fleet/,
    `pipeline must pass the service name through to the runner, got:\n${out}`,
  )
  assert.match(
    out,
    /--host hermes/,
    `pipeline must pass the default host through to the runner, got:\n${out}`,
  )
})
