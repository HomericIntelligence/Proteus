import { dag, Container, Directory, object, func } from "@dagger.io/dagger"

@object()
export class Proteus {
  /**
   * Build an OCI image from a Dockerfile in the given context directory.
   * Returns the image digest.
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
    const ref = `${registry}/${name}:${tag}`
    const image = context
      .dockerBuild()

    if (publish) {
      const published = await image.publish(ref)
      return published
    } else {
      const digest = await image.id()
      return digest
    }
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
    const output = await dag
      .container()
      .from(baseImage)
      .withMountedDirectory("/src", source)
      .withWorkdir("/src")
      .withExec(["bash", "-c", command])
      .stdout()

    return output
  }

  /**
   * Run shellcheck against all shell scripts in the source directory.
   * Returns shellcheck output.
   */
  @func()
  async lintShellcheck(source: Directory): Promise<string> {
    return dag
      .container()
      .from("koalaman/shellcheck-alpine:stable")
      .withMountedDirectory("/src", source)
      .withWorkdir("/src")
      .withExec(["sh", "-c", "find scripts/ -name '*.sh' | xargs shellcheck"])
      .stdout()
  }

  /**
   * Run tsc type-check against the Dagger TypeScript sources.
   * Returns tsc output.
   */
  @func()
  async lintTsc(source: Directory): Promise<string> {
    return dag
      .container()
      .from("node:20-alpine")
      .withMountedDirectory("/src", source)
      .withWorkdir("/src/dagger")
      .withExec(["sh", "-c", "npm ci && npx tsc --noEmit"])
      .stdout()
  }

  /**
   * Run all lint checks against the source directory (shellcheck + tsc).
   * Returns combined lint output.
   */
  @func()
  async lint(source: Directory): Promise<string> {
    const shellcheck = await this.lintShellcheck(source)
    const tsc = await this.lintTsc(source)
    return `=== shellcheck ===\n${shellcheck}\n=== tsc ===\n${tsc}`
  }
}
