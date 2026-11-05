/**
 * Reproducibility record (Phase 2) — one structured provenance object per run.
 *
 * Phase 2 requires a single, unified record of *what actually ran*: the workflow
 * identity, the resolved parameters, the exact inputs that were bound, and the
 * outputs it produced. Today that information is scattered across the
 * AfterRunReport tabs (Parameters / Outputs / …) with no single source of truth.
 * This module is the pure assembler — no I/O, so it is fully unit-testable; the
 * route supplies the run record and its outputs.
 *
 * Per-output SHA-256 checksums are carried when available (populated by a later
 * increment that hashes outputs); the shape reserves the field so consumers can
 * bind to it now. Raw S3 URIs are deliberately NOT exposed — an output is
 * addressed by its opaque id (download via /api/outputs/:id/download).
 */

import { createHash } from "crypto";

export interface ReproOutput {
  id?: string;
  name: string;
  fileType?: string;
  sizeBytes?: number;
  sha256?: string | null;
}

/** SHA-256 of the given bytes/string as a lowercase hex digest. */
export function sha256Hex(data: Buffer | string): string {
  return createHash("sha256").update(data).digest("hex");
}

/**
 * Populate per-output SHA-256 by fetching each output's bytes — the "verifiable"
 * half of a reproducibility record. BOUNDED so a record read can never become an
 * unbounded download: outputs over `maxBytes` are skipped, at most `maxFiles` are
 * hashed, an already-hashed output is left as-is, and a fetch failure degrades to
 * sha256=null rather than throwing. `fetchBytes` is injected so this is fully
 * unit-testable without network/S3.
 */
export async function enrichOutputsWithChecksums(
  outputs: ReproOutput[],
  fetchBytes: (o: ReproOutput) => Promise<Buffer | null>,
  opts: { maxBytes?: number; maxFiles?: number } = {},
): Promise<ReproOutput[]> {
  const maxBytes = opts.maxBytes ?? 25 * 1024 * 1024;
  const maxFiles = opts.maxFiles ?? 25;
  let hashed = 0;
  const out: ReproOutput[] = [];
  for (const o of outputs) {
    const tooBig = typeof o.sizeBytes === "number" && o.sizeBytes > maxBytes;
    if (o.sha256 || hashed >= maxFiles || tooBig) {
      out.push(o);
      continue;
    }
    try {
      const buf = await fetchBytes(o);
      if (buf) {
        out.push({ ...o, sha256: sha256Hex(buf) });
        hashed++;
      } else {
        out.push(o);
      }
    } catch {
      out.push(o);
    }
  }
  return out;
}

export interface ReproducibilityRecord {
  recordVersion: string;
  runId: string;
  workflowName: string;
  status: string;
  createdAt: string | null;
  completedAt: string | null;
  parameters: Record<string, unknown>;
  inputBindings: unknown[];
  outputs: ReproOutput[];
  outputCount: number;
}

const RECORD_VERSION = "1.0";

function toIso(v: unknown): string | null {
  if (!v) return null;
  if (v instanceof Date) return isNaN(v.getTime()) ? null : v.toISOString();
  if (typeof v === "string" || typeof v === "number") {
    const d = new Date(v);
    return isNaN(d.getTime()) ? null : d.toISOString();
  }
  return null;
}

/** Best-effort per-output shape, tolerating the several output records in use. */
function mapOutput(o: any): ReproOutput {
  const md = (o && typeof o === "object" ? o.metadata : undefined) ?? {};
  const size = o?.fileSize ?? o?.sizeBytes ?? o?.size ?? md.size ?? md.sizeBytes;
  return {
    id: typeof o?.id === "string" ? o.id : undefined,
    name: String(o?.name ?? o?.filename ?? md.name ?? "unnamed"),
    fileType: o?.fileType ?? o?.datatype ?? o?.extension ?? md.fileType ?? md.datatype ?? undefined,
    sizeBytes: typeof size === "number" ? size : undefined,
    // Carried when a later increment has hashed the output; null (not omitted)
    // signals "not yet hashed" rather than "no such field".
    sha256: o?.sha256 ?? md.sha256 ?? md.checksum ?? null,
  };
}

/**
 * Normalize an input binding for the record: keep the identifiers needed to
 * reproduce (which dataset was bound to which step) but drop the raw s3Uri so the
 * record never exposes internal storage paths — inputs are addressed by
 * datasetId / projectFileId, consistent with how outputs are addressed by id.
 */
function mapBinding(b: any): Record<string, unknown> {
  if (!b || typeof b !== "object") return {};
  const out: Record<string, unknown> = {};
  for (const k of ["stepId", "datasetId", "src", "name", "projectFileId"]) {
    if (b[k] !== undefined && b[k] !== null) out[k] = b[k];
  }
  return out;
}

/**
 * Assemble the reproducibility record from a run and its outputs. Defensive:
 * missing/absent fields degrade to empty rather than throwing, so a partially
 * complete run still yields a valid (if sparse) record.
 */
export function assembleReproducibilityRecord(run: any, outputs: any[] = []): ReproducibilityRecord {
  const params = run?.parameters && typeof run.parameters === "object" ? run.parameters : {};
  const bindings = (Array.isArray(run?.inputBindings) ? run.inputBindings : []).map(mapBinding);
  const outs = Array.isArray(outputs) ? outputs.map(mapOutput) : [];
  return {
    recordVersion: RECORD_VERSION,
    runId: String(run?.id ?? ""),
    // Workflow name lives on different fields across run shapes — check the
    // common ones before falling back, so the record isn't "Untitled Workflow"
    // when the name is actually available.
    workflowName: String(
      run?.workflowName ??
      run?.workflowDefinition?.name ??
      run?.execution?.workflowName ??
      run?.workflow?.name ??
      run?.name ??
      "Untitled Workflow",
    ),
    status: String(run?.status ?? run?.execution?.status ?? "unknown"),
    createdAt: toIso(run?.createdAt ?? run?.execution?.createdAt ?? run?.startedAt),
    // Completion timestamp likewise varies; fall back to updatedAt only when the
    // run is actually in a terminal state (so we don't imply a completion that
    // didn't happen).
    completedAt: toIso(
      run?.completedAt ??
      run?.execution?.completedAt ??
      run?.finishedAt ??
      (/^(completed|success|succeeded|failed|error|cancelled)$/i.test(String(run?.execution?.status ?? run?.status ?? "")) ? run?.updatedAt : null),
    ),
    parameters: params,
    inputBindings: bindings,
    outputs: outs,
    outputCount: outs.length,
  };
}
