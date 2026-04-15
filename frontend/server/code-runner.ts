/**
 * code-runner.ts — Lightweight inline code executor for the BioMate agent.
 *
 * Runs Python / R / bash in a restricted subprocess with:
 *  - Hard timeout (default 15s, max 60s)
 *  - Working directory isolated to /tmp/biomate_code/<session_id>/output/
 *  - Input datasets pre-staged at /tmp/biomate_code/<session_id>/input/<dataset_id>/
 *  - stdout + stderr captured and returned
 *  - Output files scanned and summarised
 */

import { execFile, spawn } from 'child_process';
import * as fs from 'fs/promises';
import * as path from 'path';
import { randomUUID } from 'crypto';

// ─── Types ────────────────────────────────────────────────────────────────────

export interface CodeRunRequest {
  language: 'python' | 'r' | 'bash';
  code: string;
  /** Galaxy dataset IDs whose files are staged at /data/<id>/ inside the run. */
  input_datasets?: string[];
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
  const timeoutMs = Math.min((req.timeout_seconds ?? 15), 60) * 1000;
  const baseDir = path.join('/tmp', 'biomate_code', sessionId);
  const inputDir = path.join(baseDir, 'input');
  const outputDir = path.join(baseDir, 'output');

  await fs.mkdir(outputDir, { recursive: true });
  await fs.mkdir(inputDir, { recursive: true });

  const start = Date.now();

  try {
    // Stage input datasets
    if (req.input_datasets?.length && req.downloadDataset) {
      await Promise.all(
        req.input_datasets.map(async (datasetId) => {
          const datasetDir = path.join(inputDir, datasetId);
          await fs.mkdir(datasetDir, { recursive: true });
          try {
            const stream = await req.downloadDataset!(datasetId);
            const chunks: Buffer[] = [];
            for await (const chunk of stream) chunks.push(chunk);
            // Save with a generic filename; real filename unknown without metadata
            await fs.writeFile(path.join(datasetDir, 'dataset'), Buffer.concat(chunks));
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

    if (req.language === 'python') {
      const preamble = [
        `import os, sys`,
        `os.environ['DATA_DIR'] = ${JSON.stringify(dataDir)}`,
        `os.environ['OUTPUT_DIR'] = ${JSON.stringify(outputDir)}`,
        `sys.path.insert(0, '/usr/local/lib/python3/dist-packages')`,
        `os.chdir(${JSON.stringify(outputDir)})`,
      ].join('\n');
      scriptPath = path.join(baseDir, 'script.py');
      await fs.writeFile(scriptPath, `${preamble}\n\n${req.code}`);
      interpreter = 'python3';
      args = [scriptPath];
    } else if (req.language === 'r') {
      const preamble = [
        `Sys.setenv(DATA_DIR = ${JSON.stringify(dataDir)})`,
        `Sys.setenv(OUTPUT_DIR = ${JSON.stringify(outputDir)})`,
        `setwd(${JSON.stringify(outputDir)})`,
      ].join('\n');
      scriptPath = path.join(baseDir, 'script.R');
      await fs.writeFile(scriptPath, `${preamble}\n\n${req.code}`);
      interpreter = 'Rscript';
      args = [scriptPath];
    } else {
      // bash
      const preamble = [
        `export DATA_DIR=${JSON.stringify(dataDir)}`,
        `export OUTPUT_DIR=${JSON.stringify(outputDir)}`,
        `cd ${JSON.stringify(outputDir)}`,
      ].join('\n');
      scriptPath = path.join(baseDir, 'script.sh');
      await fs.writeFile(scriptPath, `#!/bin/bash\n${preamble}\n\n${req.code}`);
      interpreter = 'bash';
      args = [scriptPath];
    }

    // Execute
    const result = await new Promise<{ stdout: string; stderr: string; exitCode: number }>(
      (resolve) => {
        let stdout = '';
        let stderr = '';
        const child = spawn(interpreter, args, {
          timeout: timeoutMs,
          env: {
            ...process.env,
            DATA_DIR: dataDir,
            OUTPUT_DIR: outputDir,
            HOME: '/tmp',
            PATH: '/usr/local/bin:/usr/bin:/bin',
          },
        });
        child.stdout.on('data', (d: Buffer) => { stdout += d.toString(); });
        child.stderr.on('data', (d: Buffer) => { stderr += d.toString(); });
        child.on('close', (code: number | null) => {
          resolve({ stdout: stdout.slice(0, 8000), stderr: stderr.slice(0, 4000), exitCode: code ?? 1 });
        });
        child.on('error', (err: Error) => {
          resolve({ stdout, stderr: stderr + `\n[Process error: ${err.message}]`, exitCode: 1 });
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
