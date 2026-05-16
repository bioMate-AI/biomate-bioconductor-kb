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

export interface CodeRunResult {
  stdout: string;
  stderr: string;
  exit_code: number;
  output_files: OutputFile[];
  duration_ms: number;
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
    const content = await fs.readFile(filePath, 'utf8');
    return content.split('\n').slice(0, 10).join('\n');
  } catch {
    return '(binary or unreadable)';
  }
}

async function scanOutputDir(dir: string): Promise<OutputFile[]> {
  const results: OutputFile[] = [];
  try {
    const entries = await fs.readdir(dir, { withFileTypes: true });
    for (const entry of entries) {
      if (!entry.isFile()) continue;
      const filePath = path.join(dir, entry.name);
      const stat = await fs.stat(filePath);
      const preview = isTextFile(entry.name) ? await previewFile(filePath) : '(binary)';
      results.push({ name: entry.name, path: filePath, size: stat.size, preview });
    }
  } catch { /* dir may not exist */ }
  return results;
}

// ─── Main executor ────────────────────────────────────────────────────────────

export async function runCode(req: CodeRunRequest): Promise<CodeRunResult> {
  const sessionId = randomUUID();
  // Allow up to 300s for complex analysis (e.g. parsing large ZIP files, running R stats)
  const timeoutMs = Math.min((req.timeout_seconds ?? 30), 300) * 1000;
  const baseDir = path.join('/tmp', 'biomate_code', sessionId);
  const inputDir = path.join(baseDir, 'input');
  const outputDir = path.join(baseDir, 'output');

  await fs.mkdir(outputDir, { recursive: true });
  await fs.mkdir(inputDir, { recursive: true });

  const start = Date.now();

  // Track staged file info for the preamble comment
  const stagedFiles: { id: string; filename: string; dir: string }[] = [];

  try {
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

    // Generate a comment block listing staged files so the AI's code knows exact paths
    const stagedComment = stagedFiles.length > 0
      ? '# Staged input files:\n' + stagedFiles.map(
          f => `#   ${f.id}/${f.filename}  →  ${path.join(f.dir, f.filename)}`
        ).join('\n') + '\n'
      : '';

    let scriptPath: string;
    let interpreter: string;
    let args: string[];

    // Inside the sandbox container the host baseDir is bind-mounted at /work.
    // All script env vars must reference container paths, not host paths.
    const containerData = '/work/input';
    const containerOutput = '/work/output';
    let scriptName: string;

    if (req.language === 'python') {
      const preamble = [
        `import os`,
        `os.environ['DATA_DIR'] = ${JSON.stringify(containerData)}`,
        `os.environ['OUTPUT_DIR'] = ${JSON.stringify(containerOutput)}`,
        `os.chdir(${JSON.stringify(containerOutput)})`,
      ].join('\n');
      scriptName = 'script.py';
      scriptPath = path.join(baseDir, scriptName);
      await fs.writeFile(scriptPath, `${preamble}\n\n${stagedComment}${req.code}`);
      interpreter = 'python3';
      args = [`/work/${scriptName}`];
    } else if (req.language === 'r') {
      const preamble = [
        `Sys.setenv(DATA_DIR = ${JSON.stringify(containerData)})`,
        `Sys.setenv(OUTPUT_DIR = ${JSON.stringify(containerOutput)})`,
        `setwd(${JSON.stringify(containerOutput)})`,
      ].join('\n');
      const rStagedComment = stagedFiles.length > 0
        ? '# Staged input files:\n' + stagedFiles.map(
            f => `#   ${f.id}/${f.filename}  ->  ${path.posix.join(containerData, f.id, f.filename)}`
          ).join('\n') + '\n'
        : '';
      scriptName = 'script.R';
      scriptPath = path.join(baseDir, scriptName);
      await fs.writeFile(scriptPath, `${preamble}\n\n${rStagedComment}${req.code}`);
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

    // Execute inside an ephemeral biomate-biotools container.
    // baseDir is bind-mounted at /work so input/, output/ and the script are visible.
    // --network=none isolates the sandbox; --memory/--cpus cap resource usage.
    // --user matches host UID so output files are owned by the frontend node user.
    const uid = (process.getuid?.() ?? 1000);
    const gid = (process.getgid?.() ?? 1000);
    const sandboxImage = process.env.RUN_CODE_IMAGE || 'biomate-biotools:1';
    const dockerArgs = [
      'run', '--rm',
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

    const result = await new Promise<{ stdout: string; stderr: string; exitCode: number }>(
      (resolve) => {
        let stdout = '';
        let stderr = '';
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

    const output_files = await scanOutputDir(outputDir);
    const duration_ms = Date.now() - start;

    return {
      stdout: result.stdout,
      stderr: result.stderr,
      exit_code: result.exitCode,
      output_files,
      duration_ms,
    };
  } finally {
    // Async cleanup — don't block the response
    fs.rm(baseDir, { recursive: true, force: true }).catch(() => {});
  }
}
