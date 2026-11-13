/**
 * Materialize deferred Galaxy HDAs before Confirm & Run / Batch launch.
 *
 * Deferred URL import registers a URL without bytes (`POST /api/datasets/deferred`).
 * Galaxy tools may auto-fetch on access; BioMate's Nextflow path needs a local/S3
 * file before `stageLocalFilesForBatch`. This module is the single place that:
 *   1) finds candidate dataset ids in launch params + workflow inputs
 *   2) materializes any still-deferred HDA
 *   3) waits until Galaxy reports `ok`
 *   4) returns local file paths for staging
 *
 * Keep logic here (not inline in routes.ts) so unit tests can cover the class
 * without spinning up Express.
 */

import * as path from "path";
import { waitForDatasetReady } from "./interactive-session-readiness";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
/** Galaxy encoded ids are typically 16 hex chars; allow a bit of range. */
const GALAXY_HEX_RE = /^[0-9a-f]{16,32}$/i;

export type SessionDatasetHint = {
  dataset_id?: string;
  galaxy_dataset_id?: string;
  deferred?: boolean;
  file_path?: string | null;
  s3_uri?: string | null;
  name?: string;
  source_url?: string | null;
};

export type DeferredMaterializeDeps = {
  getMetadata: (id: string) => Promise<{
    id?: string;
    state?: string;
    deferred?: boolean;
    name?: string;
    extension?: string;
    file_size?: number;
  } | null>;
  materialize: (id: string) => Promise<{ id: string; state: string }>;
  downloadToFile: (id: string, localPath: string) => Promise<void>;
  /** Optional clock/sleep for tests (forwarded to waitForDatasetReady). */
  now?: () => number;
  sleep?: (ms: number) => Promise<void>;
};

export type MaterializeResult = {
  /** id → local file for Nextflow staging */
  filePaths: Record<string, { filePath: string; name: string }>;
  materializedIds: string[];
  skippedIds: string[];
  failures: Array<{ id: string; reason: string }>;
};

export function looksLikeDatasetId(value: string): boolean {
  const v = value.trim();
  if (!v || v.includes("/") || v.includes(":") || v.includes(" ")) return false;
  return UUID_RE.test(v) || GALAXY_HEX_RE.test(v);
}

/** Collect dataset-like ids from params, workflow inputs, and deferred session hints. */
export function collectCandidateDatasetIds(
  params: Record<string, unknown> | null | undefined,
  inputs: Array<{ id?: string } | null | undefined> | null | undefined,
  session: SessionDatasetHint[] | null | undefined,
): string[] {
  const out = new Set<string>();

  if (params && typeof params === "object") {
    for (const val of Object.values(params)) {
      if (typeof val === "string" && looksLikeDatasetId(val)) out.add(val.trim());
    }
  }

  if (Array.isArray(inputs)) {
    for (const inp of inputs) {
      const id = inp?.id;
      if (typeof id === "string" && looksLikeDatasetId(id)) out.add(id.trim());
    }
  }

  if (Array.isArray(session)) {
    for (const d of session) {
      if (!d?.deferred) continue;
      for (const id of [d.galaxy_dataset_id, d.dataset_id]) {
        if (typeof id === "string" && id.trim()) out.add(id.trim());
      }
    }
  }

  return [...out];
}

function isDeferredMeta(meta: { state?: string; deferred?: boolean } | null | undefined): boolean {
  if (!meta) return false;
  if (meta.deferred === true) return true;
  const state = String(meta.state || "").toLowerCase();
  return state === "deferred";
}

/**
 * Ensure every deferred candidate is materialized + downloadable locally.
 * Non-deferred ids that already have bytes are skipped (caller may still resolve).
 * Failures are collected; callers decide whether to hard-fail the execute.
 */
export async function ensureDeferredDatasetsMaterialized(
  ids: string[],
  deps: DeferredMaterializeDeps,
  options: {
    uploadDir: string;
    /** Already-staged ids (have local path / s3) — skip. */
    alreadyResolved?: Set<string> | string[];
    timeoutMs?: number;
    intervalMs?: number;
  },
): Promise<MaterializeResult> {
  const already = new Set(
    Array.isArray(options.alreadyResolved)
      ? options.alreadyResolved
      : [...(options.alreadyResolved || [])],
  );
  const filePaths: Record<string, { filePath: string; name: string }> = {};
  const materializedIds: string[] = [];
  const skippedIds: string[] = [];
  const failures: Array<{ id: string; reason: string }> = [];

  const unique = [...new Set(ids.filter(Boolean))];

  for (const id of unique) {
    if (already.has(id)) {
      skippedIds.push(id);
      continue;
    }

    let meta: Awaited<ReturnType<DeferredMaterializeDeps["getMetadata"]>> = null;
    try {
      meta = await deps.getMetadata(id);
    } catch (e: any) {
      // Not every UUID param is a Galaxy HDA (project file ids, etc.) — skip quietly.
      skippedIds.push(id);
      continue;
    }
    if (!meta) {
      skippedIds.push(id);
      continue;
    }

    if (!isDeferredMeta(meta)) {
      skippedIds.push(id);
      continue;
    }

    try {
      await deps.materialize(id);
    } catch (e: any) {
      failures.push({ id, reason: e?.message || "materialize_failed" });
      continue;
    }

    const ready = await waitForDatasetReady(
      id,
      {
        getState: async (datasetId) => {
          const m = await deps.getMetadata(datasetId);
          return String(m?.state || "");
        },
        now: deps.now,
        sleep: deps.sleep,
      },
      {
        timeoutMs: options.timeoutMs ?? 300_000,
        intervalMs: options.intervalMs ?? 2_000,
      },
    );

    if (!ready.ready) {
      failures.push({
        id,
        reason: ready.reason === "failed" ? "materialize_error_state" : "materialize_timeout",
      });
      continue;
    }

    const ext = meta.extension ? `.${meta.extension}` : "";
    const localName = `${id}${ext}`;
    const localPath = path.join(options.uploadDir, localName);
    try {
      await deps.downloadToFile(id, localPath);
    } catch (e: any) {
      failures.push({ id, reason: e?.message || "download_failed" });
      continue;
    }

    filePaths[id] = { filePath: localPath, name: meta.name || localName };
    materializedIds.push(id);
  }

  return { filePaths, materializedIds, skippedIds, failures };
}
