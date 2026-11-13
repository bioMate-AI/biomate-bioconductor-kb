/**
 * code-runner.ts — Lightweight inline code executor for the BioMate agent.
 *
 * Runs Python / R / bash in a restricted subprocess with:
 *  - Hard timeout (default 30s, max 300s)
 *  - Working directory isolated to /tmp/biomate_code/<session_id>/output/
 *  - Input datasets pre-staged at /tmp/biomate_code/<session_id>/input/<dataset_id>/<original_filename>
 *  - stdout + stderr captured and returned
 *  - Output files scanned and summarised
 *
 * File staging: datasets are saved with their original filename (e.g. scogs_fungi.zip),
 * not a generic "dataset". Code can reference them as:
 *   os.path.join(os.environ['DATA_DIR'], '<galaxy_dataset_id>', '<filename>')
 */

import { execFile, spawn } from 'child_process';
import * as fs from 'fs/promises';
import { constants as fsConstants } from 'fs';
import * as path from 'path';
import { randomUUID, createHash } from 'crypto';

/** run_code sandbox image. RUN_CODE_IMAGE wins; otherwise the CJK-font layer
 *  `biomate-runcode:3` (frontend/Dockerfile.runcode — plot labels in Chinese rendered as tofu
 *  boxes on biotools:1, founder 2026-11-12) when the host has it, else `biomate-biotools:1`.
 *  Checked once per process. */
export const RUN_CODE_PREFERRED_IMAGE = 'biomate-runcode:3';
export const RUN_CODE_BASE_IMAGE = 'biomate-biotools:1';
let _sandboxImage: Promise<string> | null = null;
export function resolveSandboxImage(
  inspect: (image: string) => Promise<boolean> = (image) => new Promise((resolve) => {
    execFile('docker', ['image', 'inspect', image], { timeout: 15000 }, (err) => resolve(!err));
  }),
): Promise<string> {
  if (process.env.RUN_CODE_IMAGE) return Promise.resolve(process.env.RUN_CODE_IMAGE);
  if (!_sandboxImage) {
    _sandboxImage = inspect(RUN_CODE_PREFERRED_IMAGE).then((ok) => {
      if (!ok) console.warn(`[code-runner] ${RUN_CODE_PREFERRED_IMAGE} not found — using ${RUN_CODE_BASE_IMAGE} (no CJK fonts in plots)`);
      return ok ? RUN_CODE_PREFERRED_IMAGE : RUN_CODE_BASE_IMAGE;
    });
  }
  return _sandboxImage;
}
/** Test helper. */
export function _resetSandboxImage(): void { _sandboxImage = null; }

// ─── Types ────────────────────────────────────────────────────────────────────

export interface DatasetRef {
  /** galaxy_dataset_id used for download */
  id: string;
  /** original filename (e.g. "scogs_fungi.zip") — used to name the staged file */
  filename?: string;
}

export interface CodeRunRequest {
  language: 'python' | 'r' | 'bash';
  code: string;
  /** Galaxy dataset IDs (or DatasetRef objects) whose files are staged for the run. */
  input_datasets?: (string | DatasetRef)[];
  timeout_seconds?: number;
  /** Optional download function for Galaxy datasets. Signature matches galaxyAPIProxy. */
  downloadDataset?: (id: string) => Promise<AsyncIterable<Buffer>>;
  /** Python only: code of this turn's earlier successful calls, re-run silently before `code` so its
   *  variables, imports and loaded data exist (notebook-cell semantics; see pythonReplay). */
  prior_code?: string[];
  /** Chat session key: calls with the same key share ONE workspace (/work), so a file written to
   *  $OUTPUT_DIR in one call is still there in the next call and the next turn — the pattern every
   *  reference harness uses (Biomni process cwd, ScienceBuddy per-episode container). Without a key
   *  the run gets a throwaway workspace, removed after the call (previous behaviour). */
  workspaceKey?: string;
  /** Called for each output file this call created or changed, BEFORE any cleanup, so the caller
   *  can copy it to durable storage (download link, later turns, survives restarts). Its result is
   *  merged into that file's OutputFile entry. Failures are logged, never fail the run. */
  persistOutputFile?: (file: { hostPath: string; name: string; size: number }) => Promise<Partial<OutputFile> | undefined>;
}

export interface OutputFile {
  name: string;
  path: string;
  size: number;
  preview: string; // first 10 lines if text-like
  /** For image outputs (plots) below IMAGE_MAX_BYTES: a `data:<mime>;base64,…` URI
   *  so the chat UI can render the generated figure inline. The sandbox output dir
   *  is deleted right after the run, so the bytes must be captured here or lost. */
  image_data_uri?: string;
  /** Set when the file was saved to durable storage (see CodeRunRequest.persistOutputFile). */
  dataset_id?: string;
  galaxy_dataset_id?: string;
  /** Set when saved into the chat's project (project chats save there automatically). */
  project_file_id?: string;
  project_id?: string;
  download_url?: string;
}

/** Where run_code stages input datasets inside the sandbox: SANDBOX_INPUT_DIR/<dataset id>/<filename>.
 *  Exported so the chat prompt can tell the model the exact INPUT_FILES paths before its first call. */
/** Imports for the conventional data-science aliases a script USES but never imports. Each call is a
 *  fresh process, and the model often drops `import numpy as np` from a follow-up call (dev 2026-11-04:
 *  `NameError: name 'np' is not defined` / `'plt'` cost a retry in 4 of 6 ad-hoc answers). Only aliases
 *  the code references are imported (no start-up cost otherwise); a missing package is ignored. */
const PY_ALIASES: Array<[string, string]> = [
  ['np', 'import numpy as np'],
  ['pd', 'import pandas as pd'],
  ['plt', "import matplotlib\nmatplotlib.use('Agg')\nimport matplotlib.pyplot as plt"],
  ['sns', 'import seaborn as sns'],
];
export function pythonAliasImports(code: string): string {
  return PY_ALIASES
    .filter(([alias]) => new RegExp(`\\b${alias}\\.`).test(code) && !new RegExp(`\\bas\\s+${alias}\\b`).test(code))
    .map(([, stmt]) => `try:\n${stmt.split('\n').map(l => `    ${l}`).join('\n')}\nexcept ImportError:\n    pass`)
    .join('\n');
}

/** Re-runs earlier successful cells of this turn with their output suppressed, so a follow-up call
 *  can use what they defined. Code-interpreter tools are conventionally stateful and the model writes
 *  for that: even with "each call is a fresh process" in the tool description, follow-up calls used
 *  `df` / `np` from the previous call (NameError in 3 of 6 ad-hoc answers on dev, 2026-11-04).
 *  A cell that fails on replay is skipped. */
export function pythonReplay(prior: string[] = []): string {
  if (!prior.length) return '';
  return [
    'import contextlib as _bm_ctx, io as _bm_io',
    `for _bm_src in ${JSON.stringify(prior)}:`,
    '    try:',
    '        with _bm_ctx.redirect_stdout(_bm_io.StringIO()), _bm_ctx.redirect_stderr(_bm_io.StringIO()):',
    "            exec(compile(_bm_src, '<earlier run_code call>', 'exec'), globals())",
    '    except BaseException:',
    '        pass',
  ].join('\n');
}

export const SANDBOX_INPUT_DIR = '/work/input';
export function stagedInputPath(datasetId: string, filename: string): string {
  return `${SANDBOX_INPUT_DIR}/${datasetId}/${filename}`;
}

export interface CodeRunResult {
  stdout: string;
  stderr: string;
  exit_code: number;
  output_files: OutputFile[];
  duration_ms: number;
  /** filename -> container path of each input that was actually staged (what INPUT_FILES holds). */
  staged_inputs?: Record<string, string>;
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

const TEXT_EXTS = new Set([
  'txt', 'csv', 'tsv', 'json', 'log', 'fasta', 'fa', 'fastq', 'fq',
  'vcf', 'bed', 'gff', 'gtf', 'sam', 'r', 'py', 'sh', 'md', 'html',
]);

function isTextFile(name: string): boolean {
  const ext = name.split('.').pop()?.toLowerCase() ?? '';
  return TEXT_EXTS.has(ext);
}

/** Image outputs we inline as data URIs so generated plots render in chat. */
const IMAGE_MEDIA: Record<string, string> = {
  png: 'image/png', jpg: 'image/jpeg', jpeg: 'image/jpeg',
  gif: 'image/gif', webp: 'image/webp', svg: 'image/svg+xml',
};
// Cap the per-image base64 we push through the SSE stream. A 300-dpi matplotlib
// figure is ~0.1–0.5 MB; 4 MB covers large plots while keeping the event sane.
const IMAGE_MAX_BYTES = 4_000_000;
// Total preview bytes per run: the SSE event and the persisted message carry these.
const IMAGE_TOTAL_MAX_BYTES = 8_000_000;

function imageMediaType(name: string): string | undefined {
  return IMAGE_MEDIA[name.split('.').pop()?.toLowerCase() ?? ''];
}

/** Read an image output file and return a `data:` URI, or undefined if too large
 *  or unreadable. O_NOFOLLOW: the output dir is written by untrusted sandbox code. */
async function imageDataUri(filePath: string, mediaType: string): Promise<string | undefined> {
  try {
    const fh = await fs.open(filePath, fsConstants.O_RDONLY | fsConstants.O_NOFOLLOW);
    try {
      const buf = await fh.readFile();
      if (buf.length > IMAGE_MAX_BYTES) return undefined;
      return `data:${mediaType};base64,${buf.toString('base64')}`;
    } finally {
      await fh.close();
    }
  } catch {
    return undefined;
  }
}

async function previewFile(filePath: string): Promise<string> {
  try {
    // O_NOFOLLOW: the output dir is written by untrusted sandbox code.
    const fh = await fs.open(filePath, fsConstants.O_RDONLY | fsConstants.O_NOFOLLOW);
    try {
      const content = await fh.readFile('utf8');
      return content.split('\n').slice(0, 10).join('\n');
    } finally {
      await fh.close();
    }
  } catch {
    return '(binary or unreadable)';
  }
}

export async function scanOutputDir(dir: string): Promise<OutputFile[]> {
  const results: OutputFile[] = [];
  let imageBytes = 0;
  try {
    const entries = await fs.readdir(dir, { withFileTypes: true });
    for (const entry of entries) {
      if (!entry.isFile()) continue;
      const filePath = path.join(dir, entry.name);
      const stat = await fs.lstat(filePath);
      if (!stat.isFile()) continue;
      const mediaType = imageMediaType(entry.name);
      const preview = isTextFile(entry.name) ? await previewFile(filePath) : '(binary)';
      const image_data_uri = mediaType && stat.size <= IMAGE_MAX_BYTES && imageBytes + stat.size <= IMAGE_TOTAL_MAX_BYTES
        ? await imageDataUri(filePath, mediaType)
        : undefined;
      if (image_data_uri) imageBytes += stat.size;
      results.push({ name: entry.name, path: filePath, size: stat.size, preview, image_data_uri, _sig: await fileSignature(filePath, stat) } as OutputFile);
    }
  } catch { /* dir may not exist */ }
  return results;
}

export interface SandboxIdentity {
  uid: number;
  gid: number;
}

/**
 * Identity the sandbox container runs user code as. Never root: RUN_CODE_UID/GID
 * override explicitly; otherwise inherit the server identity but coerce 0 → 1000
 * so a root frontend still drops privileges. Number('0')||x and Number(undefined)||x
 * both fall through to the coerced default (0 is never valid).
 * With RUN_CODE_BACKEND_URL the sandbox-launcher enforces LAUNCHER_UID/GID
 * (default 1000:1000); RUN_CODE_UID/GID must match it.
 */
export function resolveSandboxIdentity(
  hostUid: number = process.getuid?.() ?? 1000,
  hostGid: number = process.getgid?.() ?? 1000,
  env: NodeJS.ProcessEnv = process.env,
): SandboxIdentity {
  return {
    uid: Number(env.RUN_CODE_UID) || (hostUid === 0 ? 1000 : hostUid),
    gid: Number(env.RUN_CODE_GID) || (hostGid === 0 ? 1000 : hostGid),
  };
}

/**
 * Create the per-run output directory and make it writable by the sandbox
 * identity only. The rest of the run tree (baseDir, input/, script) stays owned
 * by the server, so sandbox code can write outputs but not tamper with inputs.
 * Throws (rather than letting the run fail later with a PermissionError inside
 * the sandbox) when the server cannot hand the directory over, e.g. a non-root
 * server configured with a different RUN_CODE_UID/GID.
 */
export async function prepareSandboxOutputDir(
  outputDir: string,
  sandbox: SandboxIdentity,
  hostUid: number = process.getuid?.() ?? sandbox.uid,
  hostGid: number = process.getgid?.() ?? sandbox.gid,
): Promise<void> {
  await fs.mkdir(outputDir, { mode: 0o755 });
  await fs.chmod(outputDir, 0o755);
  if (hostUid === sandbox.uid && hostGid === sandbox.gid) return;
  try {
    await fs.chown(outputDir, sandbox.uid, sandbox.gid);
  } catch (err: any) {
    const msg = `[CodeRunner] cannot chown run output dir ${outputDir} to sandbox identity `
      + `${sandbox.uid}:${sandbox.gid} (server is ${hostUid}:${hostGid}): ${err?.code || err?.message || err}. `
      + `Run the server as root/with CAP_CHOWN, or set RUN_CODE_UID/RUN_CODE_GID to the server identity.`;
    console.error(msg);
    throw new Error(msg);
  }
}

// ─── Session workspaces ───────────────────────────────────────────────────────

const CODE_ROOT = path.join('/tmp', 'biomate_code');
/** A session workspace idle this long is removed (its outputs were persisted after each call). */
export const WORKSPACE_IDLE_MS = Number(process.env.RUN_CODE_WORKSPACE_IDLE_HOURS || 24) * 3600_000;
/** Per call: at most this many output files are persisted, each at most this size. */
export const PERSIST_MAX_FILES = 50;
export const PERSIST_MAX_BYTES = 200 * 1024 * 1024;

/** Stable, path-safe workspace dir for a chat session key. */
export function workspaceDirFor(key: string): string {
  return path.join(CODE_ROOT, `ws-${createHash('sha256').update(key).digest('hex').slice(0, 32)}`);
}

/** The workspace key of one user's chat session. The session id alone is client-supplied, so the key
 *  is bound to the AUTHENTICATED user id: another user sending the same session id gets a different
 *  workspace. Without both ids there is no session workspace (the run is throwaway). */
export function sessionWorkspaceKey(userId: unknown, sessionId: unknown): string | undefined {
  const u = userId == null ? '' : String(userId);
  const s = sessionId == null ? '' : String(sessionId);
  if (!u || !s) return undefined;
  // JSON array: unambiguous, so no (user, session) pair can collide with another by concatenation.
  return JSON.stringify(['chat-ws-v2', u, s]);
}

/** Calls on one session workspace run one at a time. The workspace (/work/output, staged inputs) is
 *  shared state, and a call's outputs are what changed in $OUTPUT_DIR between its start and its end —
 *  only well defined when no other call of the workspace runs meanwhile. The assistant runs a turn's
 *  tool calls with Promise.all, so without this two parallel run_code calls credited each other's
 *  files (and, with a fixed script path, ran each other's code). */
const _workspaceLocks = new Map<string, Promise<void>>();
async function withWorkspaceLock<T>(dir: string, fn: () => Promise<T>): Promise<T> {
  const prev = _workspaceLocks.get(dir) ?? Promise.resolve();
  let release!: () => void;
  const mine = new Promise<void>(r => { release = r; });
  const tail = prev.then(() => mine);
  _workspaceLocks.set(dir, tail);
  await prev;
  try {
    return await fn();
  } finally {
    release();
    if (_workspaceLocks.get(dir) === tail) _workspaceLocks.delete(dir);
  }
}

/** One path component for a staged input (dataset id / filename): never a separator, `.`/`..` or NUL,
 *  so the staged path cannot leave input/<id>/. */
export function safePathComponent(name: string, fallback: string): string {
  const s = String(name ?? '').replace(/[\/\\\0]/g, '_');
  return !s || s === '.' || s === '..' ? fallback : s;
}

/** Make `dir` a plain directory created by this server. Anything else at that path — a symlink a
 *  previous run planted (sandbox code can write /work when it runs as the server identity), a file —
 *  is removed first (rm removes a symlink itself, never its target), so nothing written below it can
 *  be redirected outside the workspace. Its parent must already be checked. */
async function ensurePlainDir(dir: string): Promise<void> {
  const st = await fs.lstat(dir).catch(() => null);
  if (st && st.isDirectory() && !st.isSymbolicLink()) return;
  if (st) await fs.rm(dir, { recursive: true, force: true });
  // EEXIST: a concurrent staging of the same dataset id created it — verified just below.
  await fs.mkdir(dir, { mode: 0o755 }).catch((e: any) => { if (e?.code !== 'EEXIST') throw e; });
  const now = await fs.lstat(dir);
  if (!now.isDirectory() || now.isSymbolicLink()) throw new Error(`[CodeRunner] ${dir} is not a plain directory`);
}

/** Create `file` with `data`; fails rather than following or reusing anything already at the path. */
async function writeNewFile(file: string, data: string | Buffer): Promise<void> {
  const fh = await fs.open(file, fsConstants.O_WRONLY | fsConstants.O_CREAT | fsConstants.O_EXCL | fsConstants.O_NOFOLLOW, 0o644);
  try { await fh.writeFile(data); } finally { await fh.close(); }
}

/** Stage `data` at dir/name without following a symlink at that path: write a fresh temp file, then
 *  rename it over the target (rename replaces a symlink/file entry, it never writes through it). */
async function stageFileAt(dir: string, name: string, data: Buffer): Promise<void> {
  const target = path.join(dir, name);
  const tmp = path.join(dir, `.staging-${randomUUID()}`);
  try {
    await writeNewFile(tmp, data);
    const st = await fs.lstat(target).catch(() => null);
    if (st && st.isDirectory() && !st.isSymbolicLink()) await fs.rm(target, { recursive: true, force: true });
    await fs.rename(tmp, target);
  } catch (err) {
    await fs.rm(tmp, { force: true }).catch(() => {});
    throw err;
  }
}

let _lastSweep = 0;
/** Remove session workspaces idle longer than WORKSPACE_IDLE_MS (at most once per 10 min). */
export async function sweepIdleWorkspaces(now = Date.now(), force = false): Promise<string[]> {
  if (!force && now - _lastSweep < 600_000) return [];
  _lastSweep = now;
  const removed: string[] = [];
  let entries: string[] = [];
  try { entries = await fs.readdir(CODE_ROOT); } catch { return removed; }
  for (const name of entries) {
    if (!name.startsWith('ws-')) continue;
    const dir = path.join(CODE_ROOT, name);
    if (_workspaceLocks.has(dir)) continue; // a call is using it right now
    try {
      const st = await fs.stat(dir);
      if (now - st.mtimeMs > WORKSPACE_IDLE_MS) { await fs.rm(dir, { recursive: true, force: true }); removed.push(dir); }
    } catch { /* raced with another sweep */ }
  }
  return removed;
}

/** Identity of a file's CONTENT (size + sha256). Content, not mtime/inode: the silent replay of a
 *  turn's earlier cells rewrites their files with the same bytes, and a metadata signature counted
 *  each rewrite as a new output — more files were saved to the project than the chat listed
 *  (founder 2026-11-12). Files over the hash cap fall back to the metadata signature. */
const SIGNATURE_HASH_MAX_BYTES = 64 * 1024 * 1024;
async function fileSignature(filePath: string, st: { size: number; mtimeMs: number; ctimeMs: number; ino: number }): Promise<string> {
  if (st.size > SIGNATURE_HASH_MAX_BYTES) return `${st.size}:${st.mtimeMs}:${st.ctimeMs}:${st.ino}`;
  try {
    return `${st.size}:${createHash('sha256').update(await fs.readFile(filePath)).digest('hex')}`;
  } catch {
    return `${st.size}:${st.mtimeMs}:${st.ctimeMs}:${st.ino}`;
  }
}

type DirSnapshot = Map<string, string>;
export async function snapshotDir(dir: string): Promise<DirSnapshot> {
  const snap: DirSnapshot = new Map();
  try {
    for (const e of await fs.readdir(dir, { withFileTypes: true })) {
      if (!e.isFile()) continue;
      const p = path.join(dir, e.name);
      const st = await fs.lstat(p);
      if (st.isFile()) snap.set(e.name, await fileSignature(p, st));
    }
  } catch { /* new workspace */ }
  return snap;
}

// ─── Main executor ────────────────────────────────────────────────────────────

export async function runCode(req: CodeRunRequest): Promise<CodeRunResult> {
  if (!req.workspaceKey) return runCodeIn(req, path.join(CODE_ROOT, randomUUID()), false);
  const baseDir = workspaceDirFor(req.workspaceKey);
  return withWorkspaceLock(baseDir, () => runCodeIn(req, baseDir, true));
}

async function runCodeIn(req: CodeRunRequest, baseDir: string, persistent: boolean): Promise<CodeRunResult> {
  // Allow up to 300s for complex analysis (e.g. parsing large ZIP files, running R stats)
  const timeoutMs = Math.min((req.timeout_seconds ?? 30), 300) * 1000;
  const inputDir = path.join(baseDir, 'input');
  const outputDir = path.join(baseDir, 'output');

  // The root must be a real directory (not a symlink planted in the shared /tmp).
  await fs.mkdir(CODE_ROOT, { recursive: true, mode: 0o755 });
  const rootSt = await fs.lstat(CODE_ROOT);
  if (rootSt.isSymbolicLink() || !rootSt.isDirectory()) throw new Error(`[CodeRunner] refusing ${CODE_ROOT}: not a plain directory`);
  if (persistent) {
    sweepIdleWorkspaces().catch(() => {});
    // A reused workspace must be the real directories this server created — never a planted
    // symlink (prepareSandboxOutputDir's no-pre-existing-path rule, applied to reuse).
    for (const d of [baseDir, outputDir]) {
      const st = await fs.lstat(d).catch(() => null);
      if (st && (st.isSymbolicLink() || !st.isDirectory())) throw new Error(`[CodeRunner] refusing workspace path ${d}: not a plain directory`);
    }
  }
  await ensurePlainDir(baseDir);
  // input/ and input/<id>/ are re-checked on every call: sandbox code of an earlier call may have
  // replaced them with symlinks (see ensurePlainDir).
  await ensurePlainDir(inputDir);
  // Files already in the session workspace before this call: only NEW or CHANGED files are this
  // call's outputs (the workspace keeps earlier calls' files).
  const before = await snapshotDir(outputDir);

  const start = Date.now();

  // Track staged file info for the preamble comment
  const stagedFiles: { id: string; filename: string; dir: string }[] = [];

  const { uid, gid } = resolveSandboxIdentity();
  let scriptPathForCleanup: string | undefined;

  try {
    // A reused session workspace already has its output dir (created + handed over on first use).
    const reusedOutput = persistent && !!(await fs.lstat(outputDir).catch(() => null));
    if (!reusedOutput) await prepareSandboxOutputDir(outputDir, { uid, gid });

    // Stage input datasets — preserve original filename so code can reference by name
    if (req.input_datasets?.length && req.downloadDataset) {
      await Promise.all(
        req.input_datasets.map(async (ref) => {
          const rawId = typeof ref === 'string' ? ref : ref.id;
          const datasetId = safePathComponent(rawId, 'dataset');
          const filename = safePathComponent((typeof ref === 'object' && ref.filename) ? ref.filename : 'dataset', 'dataset');
          const datasetDir = path.join(inputDir, datasetId);
          try {
            await ensurePlainDir(datasetDir);
            const stream = await req.downloadDataset!(rawId);
            const chunks: Buffer[] = [];
            for await (const chunk of stream) chunks.push(chunk);
            // Save with the original filename so file-type-aware code works (e.g. zipfile, pandas)
            await stageFileAt(datasetDir, filename, Buffer.concat(chunks));
            // Also write a generic 'dataset' symlink for backwards compat (replacing whatever is there).
            if (filename !== 'dataset') {
              const alias = path.join(datasetDir, 'dataset');
              await fs.rm(alias, { recursive: true, force: true }).catch(() => {});
              try {
                await fs.symlink(filename, alias);
              } catch { /* a concurrent staging of the same dataset created it */ }
            }
            stagedFiles.push({ id: datasetId, filename, dir: datasetDir });
          } catch (err: any) {
            console.warn(`[CodeRunner] Failed to stage dataset ${datasetId}:`, err.message);
          }
        })
      );
    }

    // Build the wrapper script that sets DATA_DIR, OUTPUT_DIR, then runs user code
    const dataDir = inputDir;

    let scriptPath: string;
    let interpreter: string;
    let args: string[];

    // Inside the sandbox container the host baseDir is bind-mounted at /work.
    // All script env vars must reference container paths, not host paths.
    const containerData = SANDBOX_INPUT_DIR;
    const containerOutput = '/work/output';
    let scriptName: string;
    // Unique per call: a fixed name let a parallel call of the same workspace overwrite the script
    // before the sandbox read it (dataset-panel audit S4).
    const callId = randomUUID();

    // Absolute CONTAINER path of each staged file (not the host f.dir — that was a latent bug in
    // the Python comment, which printed the host path the sandbox can't see).
    const containerPathOf = (f: { id: string; filename: string }) =>
      path.posix.join(containerData, f.id, f.filename);
    // Comment block listing staged files (human-readable).
    const stagedComment = stagedFiles.length > 0
      ? '# Staged input files:\n' + stagedFiles.map(
          f => `#   ${f.id}/${f.filename}  ->  ${containerPathOf(f)}`
        ).join('\n') + '\n'
      : '';

    if (req.language === 'python') {
      // Pre-define every staged input's absolute path as a ready-to-use variable, so the model
      // NEVER has to explore the filesystem (the multi-file-capsule failure: it ran `find /galaxy`,
      // listed empty dirs, and burned its turn instead of reading the known path).
      const pyInputFiles = stagedFiles.length > 0
        ? 'INPUT_FILES = {\n' + stagedFiles.map(
            f => `    ${JSON.stringify(f.filename)}: ${JSON.stringify(containerPathOf(f))},`
          ).join('\n') + '\n}'
        : 'INPUT_FILES = {}';
      const preamble = [
        `import os`,
        `os.environ['DATA_DIR'] = ${JSON.stringify(containerData)}`,
        `os.environ['OUTPUT_DIR'] = ${JSON.stringify(containerOutput)}`,
        `os.chdir(${JSON.stringify(containerOutput)})`,
        pyInputFiles,
        `INPUT_PATHS = list(INPUT_FILES.values())`,
        pythonAliasImports(req.code),
        pythonReplay(req.prior_code),
      ].filter(Boolean).join('\n');
      scriptName = `script-${callId}.py`;
      scriptPath = path.join(baseDir, scriptName);
      await writeNewFile(scriptPath, `${preamble}\n\n${stagedComment}${req.code}`);
      interpreter = 'python3';
      args = [`/work/${scriptName}`];
    } else if (req.language === 'r') {
      const rInputFiles = stagedFiles.length > 0
        ? 'INPUT_FILES <- list(\n' + stagedFiles.map(
            f => `  ${JSON.stringify(f.filename)} = ${JSON.stringify(containerPathOf(f))}`
          ).join(',\n') + '\n)'
        : 'INPUT_FILES <- list()';
      const preamble = [
        `Sys.setenv(DATA_DIR = ${JSON.stringify(containerData)})`,
        `Sys.setenv(OUTPUT_DIR = ${JSON.stringify(containerOutput)})`,
        `setwd(${JSON.stringify(containerOutput)})`,
        rInputFiles,
        `INPUT_PATHS <- unlist(INPUT_FILES, use.names = FALSE)`,
      ].join('\n');
      scriptName = `script-${callId}.R`;
      scriptPath = path.join(baseDir, scriptName);
      await writeNewFile(scriptPath, `${preamble}\n\n${stagedComment}${req.code}`);
      interpreter = 'Rscript';
      args = [`/work/${scriptName}`];
    } else {
      // bash
      const preamble = [
        `export DATA_DIR=${JSON.stringify(containerData)}`,
        `export OUTPUT_DIR=${JSON.stringify(containerOutput)}`,
        `cd ${JSON.stringify(containerOutput)}`,
      ].join('\n');
      scriptName = `script-${callId}.sh`;
      scriptPath = path.join(baseDir, scriptName);
      await writeNewFile(scriptPath, `#!/bin/bash\n${preamble}\n\n${req.code}`);
      interpreter = 'bash';
      args = [`/work/${scriptName}`];
    }

    scriptPathForCleanup = scriptPath;

    // Sandbox backend selection:
    //   - RUN_CODE_BACKEND_URL set → POST script+baseDir to a sidecar HTTP service
    //     (production: no docker socket in the frontend container)
    //   - else → spawn ephemeral `docker run` against the host socket (dev only)
    const sidecarUrl = process.env.RUN_CODE_BACKEND_URL;
    // Canonical sandbox image. Override with RUN_CODE_IMAGE for custom builds.
    // The image is published to ECR (399683337364.dkr.ecr.us-west-2.amazonaws.com/
    // biomate/biotools:1) — `docker pull` it on a fresh machine after running
    // `aws ecr get-login-password ... | docker login ...`. The bare
    // `biomate-biotools:1` tag works once the image is pulled and re-tagged,
    // or built locally from frontend/Dockerfile.biotools (slower path).
    const sandboxImage = await resolveSandboxImage();

    // Container hardening — parity with the Nextflow sandbox
    // (backend/lib/galaxy/ai/compute/sandbox/command.py). Low-risk flags
    // default ON (they don't affect normal compute code): drop all Linux
    // capabilities, block privilege escalation, cap process count. Read-only
    // rootfs + gVisor are OPT-IN, since some libraries write outside /work and
    // /tmp; enable per deployment via env once verified.
    const pidsLimit = process.env.RUN_CODE_PIDS_LIMIT || '512';
    const readOnly = /^(1|true|yes)$/i.test(process.env.RUN_CODE_READONLY || '');
    const tmpfsMb = process.env.RUN_CODE_TMPFS_MB || '512';
    const gvisorRuntime = (process.env.RUN_CODE_RUNTIME
      || (Number(process.env.SANDBOX_TIER) >= 3 ? 'runsc' : '')).trim();
    const hardeningArgs: string[] = [
      '--cap-drop', 'ALL',
      '--security-opt', 'no-new-privileges',
      '--pids-limit', pidsLimit,
    ];
    if (gvisorRuntime) hardeningArgs.unshift('--runtime', gvisorRuntime);
    if (readOnly) {
      hardeningArgs.push('--read-only', '--tmpfs', `/tmp:rw,nosuid,nodev,size=${tmpfsMb}m`);
    }

    const runViaDocker = () => new Promise<{ stdout: string; stderr: string; exitCode: number }>(
      (resolve) => {
        let stdout = '';
        let stderr = '';
        const dockerArgs = [
          'run', '--rm',
          ...hardeningArgs,
          '--network=none',
          '--memory=2g', '--cpus=2',
          '--user', `${uid}:${gid}`,
          '-v', `${baseDir}:/work`,
          '-w', '/work/output',
          '-e', `DATA_DIR=${containerData}`,
          '-e', `OUTPUT_DIR=${containerOutput}`,
          '-e', 'HOME=/tmp',
          sandboxImage,
          interpreter,
          ...args,
        ];
        const child = spawn('docker', dockerArgs, { timeout: timeoutMs });
        child.stdout.on('data', (d: Buffer) => { stdout += d.toString(); });
        child.stderr.on('data', (d: Buffer) => { stderr += d.toString(); });
        child.on('close', (code: number | null) => {
          resolve({ stdout: stdout.slice(0, 8000), stderr: stderr.slice(0, 4000), exitCode: code ?? 1 });
        });
        child.on('error', (err: Error) => {
          resolve({ stdout, stderr: stderr + `\n[docker run error: ${err.message}]`, exitCode: 1 });
        });
      }
    );

    const runViaSidecar = async (url: string) => {
      // Sidecar contract: POST <url>/run with JSON body
      // { baseDir, interpreter, scriptPath: <container path>, image, timeoutSeconds,
      //   env: { DATA_DIR, OUTPUT_DIR, HOME }, network: 'none', memory: '2g', cpus: 2,
      //   user: 'uid:gid' }
      // Returns { stdout, stderr, exitCode }
      const controller = new AbortController();
      const t = setTimeout(() => controller.abort(), timeoutMs + 5_000);
      try {
        const resp = await fetch(`${url.replace(/\/$/, '')}/run`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            ...(process.env.RUN_CODE_BACKEND_TOKEN ? { 'Authorization': `Bearer ${process.env.RUN_CODE_BACKEND_TOKEN}` } : {}),
          },
          body: JSON.stringify({
            baseDir,
            interpreter,
            scriptPath: args[0],
            image: sandboxImage,
            timeoutSeconds: Math.floor(timeoutMs / 1000),
            network: 'none',
            memory: '2g',
            cpus: 2,
            user: `${uid}:${gid}`,
            env: { DATA_DIR: containerData, OUTPUT_DIR: containerOutput, HOME: '/tmp' },
            // Hardening knobs (parity with the Nextflow sandbox). The sidecar
            // applies these as docker flags; older sidecars ignore unknown keys.
            capDrop: 'ALL',
            noNewPrivileges: true,
            pidsLimit: Number(pidsLimit),
            readOnly,
            tmpfsMb: Number(tmpfsMb),
            runtime: gvisorRuntime || undefined,
          }),
          signal: controller.signal,
        });
        if (!resp.ok) {
          // Include the response body — a bare "HTTP 500" hides the real cause
          // (bad image, OOM, gVisor runtime missing, auth rejected).
          const detail = await resp.text().catch(() => '');
          return {
            stdout: '',
            stderr: `[sidecar error: HTTP ${resp.status} ${resp.statusText}]${detail ? ' ' + detail.slice(0, 4000) : ''}`,
            exitCode: 1,
          };
        }
        const body: any = await resp.json();
        return {
          stdout: String(body.stdout ?? '').slice(0, 8000),
          stderr: String(body.stderr ?? '').slice(0, 4000),
          exitCode: Number(body.exitCode ?? 1),
        };
      } catch (err: any) {
        return { stdout: '', stderr: `[sidecar fetch error: ${err?.message || err}]`, exitCode: 1 };
      } finally {
        clearTimeout(t);
      }
    };

    const result = sidecarUrl ? await runViaSidecar(sidecarUrl) : await runViaDocker();

    const all = await scanOutputDir(outputDir);
    const output_files = all.filter(f => before.get(f.name) !== (f as any)._sig);
    for (const f of all) delete (f as any)._sig;
    if (req.persistOutputFile) {
      let n = 0;
      for (const f of output_files) {
        if (n >= PERSIST_MAX_FILES || f.size > PERSIST_MAX_BYTES) continue;
        n++;
        try {
          const saved = await req.persistOutputFile({ hostPath: f.path, name: f.name, size: f.size });
          if (saved) Object.assign(f, saved);
        } catch (err: any) {
          console.warn(`[CodeRunner] could not persist output ${f.name}: ${err?.message || err}`);
        }
      }
    }
    const duration_ms = Date.now() - start;

    return {
      stdout: result.stdout,
      stderr: result.stderr,
      exit_code: result.exitCode,
      output_files,
      duration_ms,
      staged_inputs: Object.fromEntries(stagedFiles.map(f => [f.filename, stagedInputPath(f.id, f.filename)])),
    };
  } finally {
    // Throwaway workspace: remove it. Session workspace: keep it (later calls/turns read its files;
    // sweepIdleWorkspaces removes it once idle) — drop only this call's script, and touch the dir so
    // the idle clock restarts.
    if (!persistent) {
      fs.rm(baseDir, { recursive: true, force: true }).catch(() => {});
    } else {
      if (scriptPathForCleanup) await fs.rm(scriptPathForCleanup, { force: true }).catch(() => {});
      const now = new Date();
      await fs.utimes(baseDir, now, now).catch(() => {});
    }
  }
}
