import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import * as fs from 'fs/promises';
import * as os from 'os';
import * as path from 'path';
import {
  resolveSandboxIdentity,
  prepareSandboxOutputDir,
  scanOutputDir,
} from './code-runner';

const realUid = process.getuid!();
const realGid = process.getgid!();
const isRoot = realUid === 0;

let baseDir: string;

beforeEach(async () => {
  baseDir = await fs.mkdtemp(path.join(os.tmpdir(), 'code-runner-test-'));
});

afterEach(async () => {
  await fs.rm(baseDir, { recursive: true, force: true });
});

describe('resolveSandboxIdentity', () => {
  it('never resolves to root when the server is root', () => {
    expect(resolveSandboxIdentity(0, 0, {})).toEqual({ uid: 1000, gid: 1000 });
  });

  it('inherits a non-root server identity', () => {
    expect(resolveSandboxIdentity(1234, 5678, {})).toEqual({ uid: 1234, gid: 5678 });
  });

  it('honours RUN_CODE_UID/GID overrides but rejects 0', () => {
    expect(resolveSandboxIdentity(0, 0, { RUN_CODE_UID: '2000', RUN_CODE_GID: '2001' }))
      .toEqual({ uid: 2000, gid: 2001 });
    expect(resolveSandboxIdentity(0, 0, { RUN_CODE_UID: '0', RUN_CODE_GID: '0' }))
      .toEqual({ uid: 1000, gid: 1000 });
  });
});

describe('prepareSandboxOutputDir', () => {
  it('creates a 0755 dir owned by the sandbox identity when it equals the server identity', async () => {
    const out = path.join(baseDir, 'output');
    await prepareSandboxOutputDir(out, { uid: realUid, gid: realGid }, realUid, realGid);
    const st = await fs.stat(out);
    expect(st.isDirectory()).toBe(true);
    expect(st.mode & 0o777).toBe(0o755);
    expect(st.uid).toBe(realUid);
    expect(st.gid).toBe(realGid);
  });

  it('chowns only the output dir when the server identity differs (root server → uid 1000 case)', async () => {
    const out = path.join(baseDir, 'output');
    const sandbox = { uid: realUid, gid: realGid };
    // Server reported as root: the helper must hand the dir to the sandbox identity.
    await prepareSandboxOutputDir(out, sandbox, 0, 0);
    const st = await fs.stat(out);
    expect(st.uid).toBe(sandbox.uid);
    expect(st.gid).toBe(sandbox.gid);
    expect(st.mode & 0o777).toBe(0o755);
    // Parent run dir is untouched and not world-writable.
    const parent = await fs.stat(baseDir);
    expect(parent.uid).toBe(realUid);
    expect(parent.mode & 0o002).toBe(0);
  });

  it('refuses a pre-existing path (e.g. a planted symlink) instead of chowning through it', async () => {
    const target = path.join(baseDir, 'elsewhere');
    await fs.mkdir(target, { mode: 0o700 });
    const out = path.join(baseDir, 'output');
    await fs.symlink(target, out);
    await expect(prepareSandboxOutputDir(out, { uid: realUid, gid: realGid }, 0, 0))
      .rejects.toMatchObject({ code: 'EEXIST' });
    expect((await fs.stat(target)).mode & 0o777).toBe(0o700);
  });

  it.skipIf(isRoot)('throws an explicit error when a non-root server cannot chown', async () => {
    const out = path.join(baseDir, 'output');
    const foreign = { uid: realUid + 4242, gid: realGid + 4242 };
    await expect(prepareSandboxOutputDir(out, foreign, realUid, realGid))
      .rejects.toThrow(/cannot chown run output dir .* to sandbox identity \d+:\d+.*RUN_CODE_UID/);
  });

  it.runIf(isRoot)('as root, hands the dir to a different uid:gid', async () => {
    const out = path.join(baseDir, 'output');
    await prepareSandboxOutputDir(out, { uid: 1000, gid: 1000 }, 0, 0);
    const st = await fs.stat(out);
    expect(st.uid).toBe(1000);
    expect(st.gid).toBe(1000);
  });
});

describe('scanOutputDir', () => {
  it('collects regular files and ignores symlinks pointing outside the run dir', async () => {
    const out = path.join(baseDir, 'output');
    await fs.mkdir(out);
    const secret = path.join(baseDir, 'secret.txt');
    await fs.writeFile(secret, 'TOP SECRET\n');
    await fs.writeFile(path.join(out, 'candidate_comparison.csv'), 'a,b\n1,2\n');
    await fs.symlink(secret, path.join(out, 'leak.csv'));
    await fs.mkdir(path.join(out, 'subdir'));

    const files = await scanOutputDir(out);
    expect(files.map(f => f.name)).toEqual(['candidate_comparison.csv']);
    expect(files[0].size).toBe(8);
    expect(files[0].preview).toBe('a,b\n1,2\n');
    expect(JSON.stringify(files)).not.toContain('TOP SECRET');
  });

  it('returns [] for a missing dir', async () => {
    expect(await scanOutputDir(path.join(baseDir, 'nope'))).toEqual([]);
  });
});
