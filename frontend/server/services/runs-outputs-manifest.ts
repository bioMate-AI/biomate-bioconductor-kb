/**
 * Output manifest (L1a of the output-resolution unification, docs/20260916).
 *
 * `RunsOutputsService.list()` derives outputs from a LIVE S3 listing every call,
 * keyed off a prefix reconstructed from the run. When that prefix is wrong or the
 * run's in-memory status was wiped by a container restart, the listing comes back
 * empty — the "0 outputs / could-not-be-read" bug class.
 *
 * The fix: once a terminal run's outputs are successfully listed, persist a
 * MANIFEST of the stable output facts into the run's (DB-backed) executionJson.
 * Subsequent reads — on any surface, after any restart — rebuild the outputs from
 * the manifest and never depend on re-deriving the S3 prefix again.
 *
 * A manifest entry stores only STABLE fields. The ephemeral ones are re-derived
 * on read: `id` (= `${runId}:${s3Key}`), `downloadUrl` (freshly presigned, since
 * presigned URLs expire), and `metadata` (mirror of `s3Uri`). This module is pure
 * (no I/O) so the serialization round-trip is unit-testable; the service supplies
 * the presigner.
 */

import type { CanonicalOutput } from "./runs-outputs-service";

/** Persisted, stable subset of a CanonicalOutput (no presigned/derived fields). */
export interface ManifestEntry {
  name: string;
  extension: string;
  size: number;
  fileType: string;
  s3Uri: string;
  s3Bucket: string;
  s3Key: string;
  step: string | null;
  previewable: boolean;
}

/** What we persist into execution.outputManifest. */
export interface OutputManifest {
  registeredAt: string;
  entries: ManifestEntry[];
}

/** Strip a CanonicalOutput down to the stable fields worth persisting. */
export function toManifestEntry(o: CanonicalOutput): ManifestEntry {
  return {
    name: o.name,
    extension: o.extension,
    size: o.size,
    fileType: o.fileType,
    s3Uri: o.s3Uri,
    s3Bucket: o.s3Bucket,
    s3Key: o.s3Key,
    step: o.step ?? null,
    previewable: o.previewable,
  };
}

/**
 * Rebuild a CanonicalOutput from a manifest entry. `runId` re-derives the stable
 * id; `downloadUrl` is a freshly presigned URL (presigned URLs expire, so it is
 * NEVER persisted). Everything else is carried verbatim from the entry.
 */
export function entryToCanonical(
  entry: ManifestEntry,
  runId: string,
  downloadUrl: string,
): CanonicalOutput {
  return {
    id: `${runId}:${entry.s3Key}`,
    name: entry.name,
    extension: entry.extension,
    size: entry.size,
    fileType: entry.fileType,
    downloadUrl,
    s3Uri: entry.s3Uri,
    s3Bucket: entry.s3Bucket,
    s3Key: entry.s3Key,
    step: entry.step ?? null,
    previewable: entry.previewable,
    metadata: { s3Uri: entry.s3Uri },
  };
}

/** Read a persisted manifest off a run's execution object (defensive). */
export function readManifest(execution: any): OutputManifest | null {
  const m = execution?.outputManifest;
  if (!m || !Array.isArray(m.entries) || m.entries.length === 0) return null;
  return m as OutputManifest;
}

/** Build the manifest object to persist from a list of resolved outputs. */
export function buildManifest(outputs: CanonicalOutput[], registeredAt: string): OutputManifest {
  return { registeredAt, entries: outputs.map(toManifestEntry) };
}

/** Terminal run states — only these may register a manifest (never persist a
 *  partial listing of a still-running run). */
const TERMINAL_STATUSES = new Set(["completed", "complete", "ok", "success", "succeeded", "failed", "error", "cancelled", "canceled"]);

export function isTerminalStatus(status: string | null | undefined): boolean {
  return !!status && TERMINAL_STATUSES.has(String(status).toLowerCase());
}
