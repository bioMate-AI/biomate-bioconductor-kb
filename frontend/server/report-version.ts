/**
 * Report version model (Phase-2 / L5) — a run report is a *versioned object*,
 * not a transient view. The audit found that editing a run report today saves a
 * local download and SEVERS the link back to the run; and there is no immutable
 * "run original". This module is the pure, unit-testable core of the fix,
 * mirroring the IND report-version contract (`/api/ind-report/.../snapshot`,
 * `listVersions`, immutable `original`) and generalizing it to any run report.
 *
 * Invariants encoded here (enforced by construction, so any store/endpoint that
 * builds on this cannot violate them):
 *   1. Version 0 is the IMMUTABLE run original — appending never replaces it.
 *   2. Versions are APPEND-ONLY and monotonically numbered.
 *   3. Every version carries the owning `runId` back-link (edits never orphan
 *      the report from its run) and a content SHA-256, so any version is
 *      verifiable and traceable to the run that produced the original.
 */

import { sha256Hex } from "./reproducibility-record";

export interface ReportVersion {
  version: number;
  /** The run this report belongs to — carried on EVERY version, never dropped. */
  runId: string;
  createdAt: string | null;
  /** SHA-256 of this version's content — makes the version verifiable. */
  sha256: string;
  /** Human note on what changed (edit-by-hand or accepted AI diff). */
  note?: string;
  /** The version this one was edited from (null for the run original). */
  editedFromVersion: number | null;
  /** True only for version 0, the run original. */
  immutable: boolean;
}

function toIso(v: unknown): string | null {
  if (!v) return null;
  if (v instanceof Date) return isNaN(v.getTime()) ? null : v.toISOString();
  if (typeof v === "string" || typeof v === "number") {
    const d = new Date(v);
    return isNaN(d.getTime()) ? null : d.toISOString();
  }
  return null;
}

/**
 * The immutable run original (version 0). Content-hashed and bound to its run.
 * This is the artifact a report/manuscript cites; edits fork from it, never
 * overwrite it.
 */
export function makeRunOriginal(runId: string, content: string, createdAt?: unknown): ReportVersion {
  if (!runId) throw new Error("makeRunOriginal: runId is required (a report must belong to a run)");
  return {
    version: 0,
    runId: String(runId),
    createdAt: toIso(createdAt) ?? null,
    sha256: sha256Hex(content ?? ""),
    editedFromVersion: null,
    immutable: true,
  };
}

/**
 * Append a new version to a report's history. Pure: does NOT mutate `history`.
 * The new version is numbered max+1, carries the same runId, records which
 * version it was edited from, and is content-hashed. Throws if the history is
 * malformed (missing a version 0) so a store can never append onto nothing.
 */
export function appendReportVersion(
  history: readonly ReportVersion[],
  content: string,
  opts: { note?: string; createdAt?: unknown } = {},
): ReportVersion {
  if (!Array.isArray(history) || history.length === 0) {
    throw new Error("appendReportVersion: history must start with a run original (version 0)");
  }
  const original = history.find(v => v.version === 0);
  if (!original) throw new Error("appendReportVersion: history has no immutable run original (version 0)");
  const latest = history.reduce((a, b) => (b.version > a.version ? b : a));
  return {
    version: latest.version + 1,
    runId: original.runId, // back-link is inherited from the original — never dropped
    createdAt: toIso(opts.createdAt) ?? null,
    sha256: sha256Hex(content ?? ""),
    note: opts.note,
    editedFromVersion: latest.version,
    immutable: false,
  };
}

/** The current (latest) version of a report history. */
export function currentReportVersion(history: readonly ReportVersion[]): ReportVersion | null {
  if (!Array.isArray(history) || history.length === 0) return null;
  return history.reduce((a, b) => (b.version > a.version ? b : a));
}
