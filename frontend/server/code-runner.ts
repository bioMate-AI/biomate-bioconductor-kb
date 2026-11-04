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
import { randomUUID } from 'crypto';

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
}

export interface OutputFile {
  name: string;
  path: string;
  size: number;
  preview: string; // first 10 lines if text-like
}

/** Where run_code stages input datasets inside the sandbox: SANDBOX_INPUT_DIR/<dataset id>/<filename>.
 *  Exported so the chat prompt can tell the model the exact INPUT_FILES paths before its first call. */
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
  try {
    const entries = await fs.readdir(dir, { withFileTypes: true });
    for (const entry of entries) {
      if (!entry.isFile()) continue;
      const filePath = path.join(dir, entry.name);
      const stat = await fs.lstat(filePath);
      if (!stat.isFile()) continue;
      const preview = isTextFile(entry.name) ? await previewFile(filePath) : '(binary)';
      results.push({ name: entry.name, path: filePath, size: stat.size, preview });
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

// ─── Main executor ────────────────────────────────────────────────────────────

export async function runCode(req: CodeRunRequest): Promise<CodeRunResult> {
  const sessionId = randomUUID();
  // Allow up to 300s for complex analysis (e.g. parsing large ZIP files, running R stats)
  const timeoutMs = Math.min((req.timeout_seconds ?? 30), 300) * 1000;
  const baseDir = path.join('/tmp', 'biomate_code', sessionId);
  const inputDir = path.join(baseDir, 'input');
  const outputDir = path.join(baseDir, 'output');

  await fs.mkdir(inputDir, { recursive: true });

  const start = Date.now();

  // Track staged file info for the preamble comment
  const stagedFiles: { id: string; filename: string; dir: string }[] = [];

  const { uid, gid } = resolveSandboxIdentity();

  try {
    await prepareSandboxOutputDir(outputDir, { uid, gid });

    // Stage input datasets — preserve original filename so code can reference by name
    if (req.input_datasets?.length && req.downloadDataset) {
      await Promise.all(
        req.input_datasets.map(async (ref) => {
          const datasetId = typeof ref === 'string' ? ref : ref.id;
          const filename = (typeof ref === 'object' && ref.filename) ? ref.filename : 'dataset';
          const datasetDir = path.join(inputDir, datasetId);
          await fs.mkdir(datasetDir, { recursive: true });
          try {
            const stream = await req.downloadDataset!(datasetId);
            const chunks: Buffer[] = [];
            for await (const chunk of stream) chunks.push(chunk);
            // Save with the original filename so file-type-aware code works (e.g. zipfile, pandas)
            await fs.writeFile(path.join(datasetDir, filename), Buffer.concat(chunks));
            // Also write a generic 'dataset' symlink for backwards compat
            if (filename !== 'dataset') {
              try {
                await fs.symlink(filename, path.join(datasetDir, 'dataset'));
              } catch { /* ignore if symlink already exists */ }
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
      ].join('\n');
      scriptName = 'script.py';
      scriptPath = path.join(baseDir, scriptName);
      await fs.writeFile(scriptPath, `${preamble}\n\n${stagedComment}${req.code}`);
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
      scriptName = 'script.R';
      scriptPath = path.join(baseDir, scriptName);
      await fs.writeFile(scriptPath, `${preamble}\n\n${stagedComment}${req.code}`);
      interpreter = 'Rscript';
      args = [`/work/${scriptName}`];
    } else {
      // bash
      const preamble = [
        `export DATA_DIR=${JSON.stringify(containerData)}`,
        `export OUTPUT_DIR=${JSON.stringify(containerOutput)}`,
        `cd ${JSON.stringify(containerOutput)}`,
      ].join('\n');
      scriptName = 'script.sh';
      scriptPath = path.join(baseDir, scriptName);
      await fs.writeFile(scriptPath, `#!/bin/bash\n${preamble}\n\n${req.code}`);
      interpreter = 'bash';
      args = [`/work/${scriptName}`];
    }

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
    const sandboxImage = process.env.RUN_CODE_IMAGE || 'biomate-biotools:1';

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

    const output_files = await scanOutputDir(outputDir);
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
    // Async cleanup — don't block the response
    fs.rm(baseDir, { recursive: true, force: true }).catch(() => {});
  }
}
