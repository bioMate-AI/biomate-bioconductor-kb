/**
 * Fail-closed BAM/VCF index generation during Batch staging.
 *
 * Galaxy has ~98 datatype converters; BioMate's Nextflow path stages local/S3
 * bytes and never runs those converters. Before launch we ensure:
 *   - *.bam  → sibling *.bai   via `samtools index`
 *   - *.vcf.gz → sibling *.tbi via `tabix -p vcf`
 *
 * Missing tool or index failure → throw StagingIndexError (caller maps to 409).
 * Already-indexed files are no-ops. Non-genomics params are ignored.
 */

import { promises as fs } from "fs";
import * as path from "path";
import { execFile } from "child_process";
import { promisify } from "util";

const execFileAsync = promisify(execFile);

export class StagingIndexError extends Error {
  code = "staging_index_failed" as const;
  constructor(
    message: string,
    public readonly detail?: { param?: string; file?: string; reason?: string },
  ) {
    super(message);
    this.name = "StagingIndexError";
  }
}

export type IndexableKind = "bam" | "vcf_gz";

export function detectIndexableKind(filename: string): IndexableKind | null {
  const n = filename.toLowerCase();
  if (n.endsWith(".bam")) return "bam";
  if (n.endsWith(".vcf.gz")) return "vcf_gz";
  return null;
}

export function expectedIndexPath(localPath: string, kind: IndexableKind): string {
  if (kind === "bam") return `${localPath}.bai`;
  return `${localPath}.tbi`;
}

async function fileExists(p: string): Promise<boolean> {
  try {
    const st = await fs.stat(p);
    return st.isFile();
  } catch {
    return false;
  }
}

async function which(bin: string): Promise<string | null> {
  try {
    const { stdout } = await execFileAsync("which", [bin], { timeout: 5_000 });
    const p = stdout.trim().split("\n")[0];
    return p || null;
  } catch {
    return null;
  }
}

export type EnsureIndexResult = {
  param: string;
  kind: IndexableKind;
  dataPath: string;
  indexPath: string;
  created: boolean;
};

/**
 * For each param whose value is a local absolute path to BAM/VCF.gz,
 * ensure a sibling index exists (create if missing). Mutates nothing in
 * `params` — indexes are sidecar files next to the data.
 */
export async function ensureGenomicIndexesForParams(
  params: Record<string, unknown>,
  opts?: {
    execFile?: typeof execFileAsync;
    which?: (bin: string) => Promise<string | null>;
    exists?: (p: string) => Promise<boolean>;
  },
): Promise<EnsureIndexResult[]> {
  const run = opts?.execFile ?? execFileAsync;
  const findBin = opts?.which ?? which;
  const exists = opts?.exists ?? fileExists;
  const out: EnsureIndexResult[] = [];

  for (const [key, val] of Object.entries(params)) {
    if (typeof val !== "string" || !val.startsWith("/")) continue;
    if (val.startsWith("/proc") || val.startsWith("/sys") || val.startsWith("/dev")) continue;
    const kind = detectIndexableKind(path.basename(val));
    if (!kind) continue;
    if (!(await exists(val))) continue;

    const indexPath = expectedIndexPath(val, kind);
    if (await exists(indexPath)) {
      out.push({ param: key, kind, dataPath: val, indexPath, created: false });
      continue;
    }

    const bin = kind === "bam" ? "samtools" : "tabix";
    const binPath = await findBin(bin);
    if (!binPath) {
      throw new StagingIndexError(
        `${bin} is required to index ${kind === "bam" ? "BAM" : "VCF.gz"} before Batch launch, but was not found on PATH`,
        { param: key, file: val, reason: `${bin}_not_found` },
      );
    }

    try {
      if (kind === "bam") {
        await run(binPath, ["index", val], { timeout: 120_000, maxBuffer: 4 * 1024 * 1024 });
      } else {
        await run(binPath, ["-p", "vcf", val], { timeout: 120_000, maxBuffer: 4 * 1024 * 1024 });
      }
    } catch (e: any) {
      throw new StagingIndexError(
        `Failed to create ${kind === "bam" ? ".bai" : ".tbi"} for ${path.basename(val)}: ${e?.message || e}`,
        { param: key, file: val, reason: "index_command_failed" },
      );
    }

    if (!(await exists(indexPath))) {
      throw new StagingIndexError(
        `Index command reported success but ${path.basename(indexPath)} was not created`,
        { param: key, file: val, reason: "index_missing_after_create" },
      );
    }

    out.push({ param: key, kind, dataPath: val, indexPath, created: true });
  }

  return out;
}

/**
 * After staging data files to S3, also stage any sibling indexes that exist
 * next to the original local paths (keyed by the original local value before
 * rewrite). Returns a map of optional sidecar param names → s3 URI for
 * callers that want to expose them; primary behavior is uploading next to
 * the staged object as `{stagedKey}.bai` / `.tbi`.
 */
export function siblingIndexLocalPath(localDataPath: string): string | null {
  const kind = detectIndexableKind(path.basename(localDataPath));
  if (!kind) return null;
  return expectedIndexPath(localDataPath, kind);
}
