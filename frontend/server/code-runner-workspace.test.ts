import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import http from 'http';
import fs from 'fs/promises';
import path from 'path';
import { runCode, workspaceDirFor, sweepIdleWorkspaces, WORKSPACE_IDLE_MS } from './code-runner';

// The real runCode against a stand-in sandbox sidecar (RUN_CODE_BACKEND_URL): the sidecar reads the
// script runCode wrote into the workspace and performs its "# WRITE <name> <text>" lines into
// /work/output — what the sandbox container does when user code saves files to $OUTPUT_DIR.
// Founder 2026-11-11: a QC_Report.txt written by run_code was deleted with the per-call temp dir, so
// it could not be downloaded or read in the next turn.

let server: http.Server;
const prevUrl = process.env.RUN_CODE_BACKEND_URL;

beforeAll(async () => {
  server = http.createServer(async (req, res) => {
    let raw = '';
    for await (const c of req) raw += c;
    const body = JSON.parse(raw);
    const script = await fs.readFile(path.join(body.baseDir, path.basename(body.scriptPath)), 'utf8');
    for (const m of script.matchAll(/^# WRITE (\S+) (.*)$/gm)) {
      await fs.writeFile(path.join(body.baseDir, 'output', m[1]), m[2]);
    }
    res.setHeader('Content-Type', 'application/json');
    res.end(JSON.stringify({ stdout: '', stderr: '', exitCode: 0 }));
  });
  await new Promise<void>(r => server.listen(0, '127.0.0.1', () => r()));
  process.env.RUN_CODE_BACKEND_URL = `http://127.0.0.1:${(server.address() as any).port}`;
});
afterAll(async () => {
  if (prevUrl === undefined) delete process.env.RUN_CODE_BACKEND_URL; else process.env.RUN_CODE_BACKEND_URL = prevUrl;
  await new Promise<void>(r => server.close(() => r()));
});

const run = (code: string, extra: Record<string, any> = {}) => runCode({ language: 'bash', code, ...extra });

describe('run_code session workspace', () => {
  it('keeps $OUTPUT_DIR across calls of one session and reports only new/changed files', async () => {
    const key = `test:${Date.now()}:${Math.random()}`;
    const dir = workspaceDirFor(key);
    try {
      const r1 = await run('# WRITE QC_Report.txt first report', { workspaceKey: key });
      expect(r1.output_files.map(f => f.name)).toEqual(['QC_Report.txt']);

      // Next call (e.g. the next turn): the earlier file is still there, and is not re-reported.
      const r2 = await run('# WRITE summary.csv a,b', { workspaceKey: key });
      expect(r2.output_files.map(f => f.name)).toEqual(['summary.csv']);
      expect(await fs.readFile(path.join(dir, 'output', 'QC_Report.txt'), 'utf8')).toBe('first report');

      // Rewriting a file with new content reports it again.
      const r3 = await run('# WRITE QC_Report.txt second, longer report', { workspaceKey: key });
      expect(r3.output_files.map(f => f.name)).toEqual(['QC_Report.txt']);

      // The per-call script is removed; the workspace dir is not.
      const left = (await fs.readdir(dir)).filter(n => /^(script|run|code)/i.test(n) || /\.(sh|py|R)$/.test(n));
      expect(left).toEqual([]);
    } finally {
      await fs.rm(dir, { recursive: true, force: true });
    }
  });

  it('hands each new file to persistOutputFile before cleanup and merges the result', async () => {
    const seen: Array<{ name: string; content: string }> = [];
    const r = await run('# WRITE plot.png PNGBYTES\n# WRITE report.txt hello', {
      persistOutputFile: async (f: any) => {
        seen.push({ name: f.name, content: await fs.readFile(f.hostPath, 'utf8') });
        return { dataset_id: `ds-${f.name}`, download_url: `/api/datasets/ds-${f.name}/download` };
      },
    });
    expect(seen.sort((a, b) => a.name.localeCompare(b.name))).toEqual([
      { name: 'plot.png', content: 'PNGBYTES' }, { name: 'report.txt', content: 'hello' }]);
    const rep = r.output_files.find(f => f.name === 'report.txt')!;
    expect(rep.dataset_id).toBe('ds-report.txt');
    expect(rep.download_url).toBe('/api/datasets/ds-report.txt/download');
  });

  it('a persistence failure never fails the run', async () => {
    const r = await run('# WRITE a.txt x', { persistOutputFile: async () => { throw new Error('S3 down'); } });
    expect(r.exit_code).toBe(0);
    expect(r.output_files.map(f => f.name)).toEqual(['a.txt']);
    expect(r.output_files[0].dataset_id).toBeUndefined();
  });

  it('without a session key the workspace is throwaway (previous behaviour)', async () => {
    const r = await run('# WRITE t.txt y');
    expect(r.output_files.map(f => f.name)).toEqual(['t.txt']);
    const base = path.dirname(path.dirname(r.output_files[0].path));
    await new Promise(res => setTimeout(res, 50));
    await expect(fs.access(base)).rejects.toThrow();
  });

  it('sweeps session workspaces idle longer than the limit, keeps recent ones', async () => {
    const oldDir = workspaceDirFor(`old:${Math.random()}`);
    const newDir = workspaceDirFor(`new:${Math.random()}`);
    try {
      await fs.mkdir(oldDir, { recursive: true }); await fs.mkdir(newDir, { recursive: true });
      const past = new Date(Date.now() - WORKSPACE_IDLE_MS - 60_000);
      await fs.utimes(oldDir, past, past);
      const removed = await sweepIdleWorkspaces(Date.now(), true);
      expect(removed).toContain(oldDir);
      await expect(fs.access(oldDir)).rejects.toThrow();
      await fs.access(newDir);
    } finally {
      await fs.rm(oldDir, { recursive: true, force: true }); await fs.rm(newDir, { recursive: true, force: true });
    }
  });
});
