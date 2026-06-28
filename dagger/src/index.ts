import { dag, Container, Directory, object, func, ExecError } from "@dagger.io/dagger"
import { stagingRef } from "./tag"

class ProteusPipelineError extends Error {
  constructor(message: string, options?: { cause?: unknown }) {
    super(message)
    this.name = "ProteusPipelineError"
    if (options?.cause !== undefined) {
      ;(this as Error & { cause?: unknown }).cause = options.cause
    }
  }
}

async function runStep<T>(
  step: string,
  context: Record<string, string>,
  fn: () => Promise<T>
): Promise<T> {
  try {
    return await fn()
  } catch (err) {
    const ctx = Object.entries(context)
      .map(([k, v]) => `${k}=${v}`)
      .join(" ")
    let detail: string
    if (err instanceof ExecError) {
      const stderr = (err.stderr ?? "").trim().split("\n").slice(-5).join("\n")
      detail = `exit ${err.exitCode}${stderr ? `: ${stderr}` : ""}`
    } else if (err instanceof Error) {
      detail = err.message
    } else {
      detail = String(err)
    }
    throw new ProteusPipelineError(
      `proteus: ${step} failed (${ctx}): ${detail}`,
      { cause: err }
    )
  }
}

@object()
export class Proteus {
  /**
   * Build an OCI image from a Dockerfile in the given context directory.
   * Returns the image digest (or the published staging ref when `publish=true`).
   *
   * Tagging contract (fixes #2 / #83): when `publish=true`, the image is pushed
   * to `${registry}/${name}:${tag}-staging`. `scripts/promote-image.sh` then
   * copies that staging ref to `${registry}/${name}:${tag}` as a separate step.
   * This matches the staging→production flow documented in CLAUDE.md and
   * encoded by `just pipeline`.
   *
   * @param publish - Whether to push the image to the registry (default: false; opt-in to avoid surprising local pushes — see #91)
   */
  @func()
  async build(
    context: Directory,
    name: string,
    tag: string = "latest",
    registry: string = "ghcr.io/homeric-intelligence",
    publish: boolean = false
  ): Promise<string> {
    const ref = stagingRef(registry, name, tag)
    const image = context.dockerBuild()

    if (publish) {
      return runStep("build.publish", { ref }, () => image.publish(ref))
    }
    return runStep("build.id", { ref }, () => image.id())
  }

  /**
   * Run a test command inside a container built from the source directory.
   * Returns the combined stdout/stderr output.
   *
   * Defaults are aligned so they work out of the box: the default command
   * (`echo ...`) is available on any image, including the default
   * `ubuntu:22.04` which does NOT ship `just`. Callers that want `just`
   * MUST pass an image that has it installed AND override `command`
   * accordingly. See #90.
   *
   * @param baseImage - Base image to use for the test container (default: ubuntu:22.04)
   * @param command   - Shell command to execute (default: a no-op echo so the defaults are self-consistent)
   */
  @func()
  async test(
    source: Directory,
    command: string = "echo 'proteus test: override `command` with your test entrypoint'",
    baseImage: string = "ubuntu:22.04"
  ): Promise<string> {
    return runStep(
      "test",
      { baseImage, command: command.length > 80 ? command.slice(0, 77) + "..." : command },
      () =>
        dag
          .container()
          .from(baseImage)
          .withMountedDirectory("/src", source)
          .withWorkdir("/src")
          .withExec(["bash", "-c", command])
          .stdout()
    )
  }

  /**
   * Run shellcheck against all shell scripts in the source directory.
   * Returns shellcheck output.
   */
  @func()
  async lintShellcheck(source: Directory): Promise<string> {
    return runStep("lint.shellcheck", { scope: "scripts/*.sh" }, () =>
      dag
        .container()
        .from("koalaman/shellcheck-alpine:stable")
        .withMountedDirectory("/src", source)
        .withWorkdir("/src")
        .withExec(["sh", "-c", "find scripts/ -name '*.sh' | xargs shellcheck"])
        .stdout()
    )
  }

  /**
   * Run tsc type-check against the Dagger TypeScript sources.
   * Mounts only the dagger/ subdirectory (not the full repo) and caches the
   * npm download cache across invocations via a Dagger cache volume.
   * node_modules is recreated each run by npm ci (by design). Fixes #92.
   */
  @func()
  async lintTsc(source: Directory): Promise<string> {
    const daggerDir = source.directory("dagger")
    return runStep("lint.tsc", { scope: "dagger/src" }, () =>
      dag
        .container()
        .from("node:20-alpine")
        .withMountedCache("/root/.npm", dag.cacheVolume("proteus-npm-cache"))
        .withWorkdir("/work")
        .withFile("/work/package.json", daggerDir.file("package.json"))
        .withFile("/work/package-lock.json", daggerDir.file("package-lock.json"))
        .withExec(["npm", "ci", "--prefer-offline", "--no-audit"])
        .withMountedDirectory("/work/src", daggerDir.directory("src"))
        .withFile("/work/tsconfig.json", daggerDir.file("tsconfig.json"))
        .withExec(["npx", "tsc", "--noEmit"])
        .stdout()
    )
  }

  /**
   * Run all lint checks against the source directory (shellcheck + tsc).
   * Returns a JSON object with keys 'shellcheck' and 'tsc', each containing
   * the respective linter output. Callers wanting a single linter should call
   * lintShellcheck() or lintTsc() directly. Fixes #92.
   */
  @func()
  async lint(source: Directory): Promise<string> {
    const shellcheck = await this.lintShellcheck(source)
    const tsc = await this.lintTsc(source)
    return JSON.stringify({ shellcheck, tsc }, null, 2)
  }
}
