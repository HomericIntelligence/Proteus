import { Proteus } from '../../src';

jest.mock('@dagger.io/dagger', () => {
  const exec = jest.fn().mockReturnThis();
  const stdout = jest.fn().mockResolvedValue('mock-stdout');
  const container = {
    from: jest.fn().mockReturnThis(),
    withMountedDirectory: jest.fn().mockReturnThis(),
    withWorkdir: jest.fn().mockReturnThis(),
    withMountedCache: jest.fn().mockReturnThis(),
    withFile: jest.fn().mockReturnThis(),
    withExec: exec,
    stdout,
  };
  return {
    dag: {
      container: () => container,
      cacheVolume: jest.fn(() => ({ _cache: true })),
    },
    object: () => (target: any) => target,
    func: () => (_t: any, _k: any, _d: any) => undefined,
    Directory: class {},
    Container: class {},
    __mocks__: { container, exec, stdout },
  };
});

const dagger = require('@dagger.io/dagger');

describe('Proteus.build', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('returns digest when publish=false (default)', async () => {
    const dockerBuild = jest.fn(() => ({
      publish: jest.fn().mockResolvedValue('ghcr.io/x@sha256:abc'),
      id: jest.fn().mockResolvedValue('sha256:local-id'),
    }));
    const ctx: any = { dockerBuild };
    const out = await new Proteus().build(ctx, 'myapp');
    expect(dockerBuild).toHaveBeenCalledTimes(1);
    expect(out).toBe('sha256:local-id');
  });

  it('returns published ref when publish=true', async () => {
    const publish = jest.fn().mockResolvedValue('ghcr.io/x@sha256:pub');
    const ctx: any = { dockerBuild: () => ({ publish, id: jest.fn() }) };
    const out = await new Proteus().build(ctx, 'myapp', 'v1', 'ghcr.io/y', true);
    expect(publish).toHaveBeenCalledWith('ghcr.io/y/myapp:v1');
    expect(out).toBe('ghcr.io/x@sha256:pub');
  });

  it('uses default registry and tag when omitted', async () => {
    const dockerBuild = jest.fn(() => ({
      publish: jest.fn().mockResolvedValue('published'),
      id: jest.fn().mockResolvedValue('sha256:default'),
    }));
    const ctx: any = { dockerBuild };
    const out = await new Proteus().build(ctx, 'myapp');
    expect(out).toBe('sha256:default');
  });
});

describe('Proteus.test', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('passes command via bash -c on the configured base image', async () => {
    const { container, exec, stdout } = dagger.__mocks__;
    stdout.mockResolvedValueOnce('hello');
    const out = await new Proteus().test({} as any, 'echo hello', 'alpine:3.20');
    expect(container.from).toHaveBeenCalledWith('alpine:3.20');
    expect(exec).toHaveBeenCalledWith(['bash', '-c', 'echo hello']);
    expect(out).toBe('hello');
  });

  it('uses default ubuntu:22.04 + echo when args omitted (regression for #90)', async () => {
    const { container, exec, stdout } = dagger.__mocks__;
    stdout.mockResolvedValueOnce('mock output');
    await new Proteus().test({} as any);
    expect(container.from).toHaveBeenCalledWith('ubuntu:22.04');
    const lastCall = exec.mock.calls.at(-1);
    expect(lastCall).toBeDefined();
    expect(lastCall[0]).toEqual(['bash', '-c', expect.stringContaining('echo')]);
  });

  it('mounts source directory at /src', async () => {
    const { container } = dagger.__mocks__;
    await new Proteus().test({} as any, 'true', 'ubuntu:22.04');
    expect(container.withMountedDirectory).toHaveBeenCalledWith('/src', expect.anything());
  });

  it('sets workdir to /src', async () => {
    const { container } = dagger.__mocks__;
    await new Proteus().test({} as any, 'true', 'ubuntu:22.04');
    expect(container.withWorkdir).toHaveBeenCalledWith('/src');
  });
});

describe('Proteus.lintShellcheck', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('runs shellcheck on scripts/ directory', async () => {
    const { container, exec, stdout } = dagger.__mocks__;
    stdout.mockResolvedValueOnce('shellcheck ok');
    await new Proteus().lintShellcheck({} as any);
    expect(container.from).toHaveBeenCalledWith('koalaman/shellcheck-alpine:stable');
    const lastCall = exec.mock.calls.at(-1);
    expect(lastCall[0]).toEqual(['sh', '-c', expect.stringContaining('shellcheck')]);
  });
});

describe('Proteus.lintTsc', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('runs tsc type-check in dagger subdirectory', async () => {
    const { container, exec, stdout } = dagger.__mocks__;
    stdout.mockResolvedValueOnce('tsc ok');
    await new Proteus().lintTsc({} as any);
    expect(container.from).toHaveBeenCalledWith('node:20-alpine');
    expect(container.withWorkdir).toHaveBeenCalledWith('/src/dagger');
    const lastCall = exec.mock.calls.at(-1);
    expect(lastCall[0]).toEqual(['sh', '-c', expect.stringContaining('tsc')]);
  });
});

describe('Proteus.lint', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('returns combined output with both shellcheck and tsc sections', async () => {
    const p = new Proteus();
    jest.spyOn(p, 'lintShellcheck').mockResolvedValue('sc-ok');
    jest.spyOn(p, 'lintTsc').mockResolvedValue('tsc-ok');
    const out = await p.lint({} as any);
    expect(out).toContain('=== shellcheck ===');
    expect(out).toContain('sc-ok');
    expect(out).toContain('=== tsc ===');
    expect(out).toContain('tsc-ok');
  });

  it('calls both lintShellcheck and lintTsc', async () => {
    const p = new Proteus();
    const scSpy = jest.spyOn(p, 'lintShellcheck').mockResolvedValue('sc');
    const tscSpy = jest.spyOn(p, 'lintTsc').mockResolvedValue('tsc');
    await p.lint({} as any);
    expect(scSpy).toHaveBeenCalledTimes(1);
    expect(tscSpy).toHaveBeenCalledTimes(1);
  });
});
