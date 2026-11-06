/**
 * report-version-store.ts — the DB-backed store for the versioned run report
 * (Task #22 / L5). It gives the pure model in `report-version.ts` a single,
 * restart-surviving home and a single writer.
 *
 * Persistence mirrors `runs-outputs-service.ts` / the outputs-manifest pattern:
 * everything lives under `execution.reportVersions` inside `execution_runs.executionJson`
 * (written via `storage.updateExecutionRun(runId, { execution: {...exec, reportVersions } })`).
 * That column is JSON-stringified verbatim and spread back on read, so arbitrary
 * keys survive without a schema migration.
 *
 * The report is a *versioned object*, not a transient view:
 *   - version 0 is the IMMUTABLE run original, seeded from the current report
 *     markdown the first time anything is saved;
 *   - every later version is append-only and INHERITS the runId back-link
 *     (an edit can never orphan the report from its run — enforced by the pure
 *     `appendReportVersion`).
 *
 * Content is stored alongside the metadata (the pure model only carries the
 * SHA-256), keyed by version number, so a listed version can be fetched back.
 */

import { storage } from "./storage";
import {
  type ReportVersion,
  makeRunOriginal,
  appendReportVersion,
} from "./report-version";

/** The shape persisted under `execution.reportVersions`. */
export interface ReportVersionsRecord {
  /** Append-only version metadata (index 0 is the immutable run original). */
  versions: ReportVersion[];
  /** version number → markdown content. Version 0 = the run original body. */
  contents: Record<string, string>;
}

/** A version with its content, as returned to the API/UI. */
export interface ReportVersionWithContent extends ReportVersion {
  content: string;
}

function emptyRecord(): ReportVersionsRecord {
  return { versions: [], contents: {} };
}

/** Read the raw persisted record for a run (never throws; empty when unset). */
function readRecord(exec: any): ReportVersionsRecord {
  const raw = exec?.reportVersions;
  if (!raw || !Array.isArray(raw.versions)) return emptyRecord();
  return {
    versions: raw.versions as ReportVersion[],
    contents: (raw.contents && typeof raw.contents === "object" ? raw.contents : {}) as Record<string, string>,
  };
}

/**
 * Single writer. Loads the run, mutates its `execution.reportVersions`, and
 * persists via `storage.updateExecutionRun` (DB-backed, survives restart).
 * Serialized per-run through `_locks` so two concurrent saves can't both read
 * v0-absent and each seed a competing original.
 */
export class ReportVersionStore {
  private _locks = new Map<string, Promise<unknown>>();

  /** Resolve any id (runId / galaxyInvocationId) to a run, or null. */
  private async resolveRun(anyId: string) {
    if (!anyId) return null;
    return (
      (await storage.getExecutionRun(anyId)) ||
      (await storage.getExecutionRunByGalaxyId(anyId)) ||
      null
    );
  }

  /** Serialize a mutation against a run id so appends stay single-writer. */
  private async withLock<T>(runId: string, fn: () => Promise<T>): Promise<T> {
    const prev = this._locks.get(runId) ?? Promise.resolve();
    const next = prev.then(fn, fn);
    this._locks.set(runId, next.catch(() => {}));
    try {
      return await next;
    } finally {
      if (this._locks.get(runId) === next.catch(() => {})) this._locks.delete(runId);
    }
  }

  /** List all versions (metadata + content) for a run, oldest → newest. */
  async list(anyId: string): Promise<ReportVersionWithContent[] | null> {
    const run = await this.resolveRun(anyId);
    if (!run) return null;
    const rec = readRecord(run.execution);
    return rec.versions
      .slice()
      .sort((a, b) => a.version - b.version)
      .map((v) => ({ ...v, content: rec.contents[String(v.version)] ?? "" }));
  }

  /** Fetch one version (metadata + content) by number, or null. */
  async get(anyId: string, version: number): Promise<ReportVersionWithContent | null> {
    const run = await this.resolveRun(anyId);
    if (!run) return null;
    const rec = readRecord(run.execution);
    const v = rec.versions.find((x) => x.version === version);
    if (!v) return null;
    return { ...v, content: rec.contents[String(version)] ?? "" };
  }

  /**
   * Ensure the immutable run original (v0) exists, seeded from `currentMarkdown`
   * if the report has never been saved. Idempotent: a no-op once v0 exists.
   * Returns the run original with its content, or null if the run is unknown.
   */
  async ensureOriginal(
    anyId: string,
    currentMarkdown: string,
  ): Promise<ReportVersionWithContent | null> {
    const run = await this.resolveRun(anyId);
    if (!run) return null;
    const runId = run.id;
    return this.withLock(runId, async () => {
      const fresh = (await storage.getExecutionRun(runId))!;
      const rec = readRecord(fresh.execution);
      const existing = rec.versions.find((v) => v.version === 0);
      if (existing) {
        return { ...existing, content: rec.contents["0"] ?? "" };
      }
      const original = makeRunOriginal(runId, currentMarkdown ?? "", new Date());
      const nextRec: ReportVersionsRecord = {
        versions: [original],
        contents: { "0": currentMarkdown ?? "" },
      };
      await storage.updateExecutionRun(runId, {
        execution: { ...fresh.execution, reportVersions: nextRec } as any,
      });
      return { ...original, content: currentMarkdown ?? "" };
    });
  }

  /**
   * Append a new version. Seeds the immutable run original from
   * `currentMarkdown` on first save (so an edit always forks from a real v0),
   * then appends `content` as the next version. Single-writer via the per-run
   * lock. Returns the newly-appended version with its content, or null if the
   * run is unknown.
   */
  async append(
    anyId: string,
    content: string,
    opts: { note?: string; currentMarkdown?: string } = {},
  ): Promise<ReportVersionWithContent | null> {
    const run = await this.resolveRun(anyId);
    if (!run) return null;
    const runId = run.id;
    return this.withLock(runId, async () => {
      const fresh = (await storage.getExecutionRun(runId))!;
      const rec = readRecord(fresh.execution);

      // Seed the immutable run original if it doesn't exist yet. The original's
      // body is the report as it stood BEFORE this edit (currentMarkdown), so v0
      // is a faithful snapshot of what the run produced.
      if (!rec.versions.some((v) => v.version === 0)) {
        const originalBody = opts.currentMarkdown ?? "";
        const original = makeRunOriginal(runId, originalBody, new Date());
        rec.versions = [original];
        rec.contents = { "0": originalBody };
      }

      const appended = appendReportVersion(rec.versions, content ?? "", {
        note: opts.note,
        createdAt: new Date(),
      });
      const nextRec: ReportVersionsRecord = {
        versions: [...rec.versions, appended],
        contents: { ...rec.contents, [String(appended.version)]: content ?? "" },
      };
      await storage.updateExecutionRun(runId, {
        execution: { ...fresh.execution, reportVersions: nextRec } as any,
      });
      return { ...appended, content: content ?? "" };
    });
  }
}

export const reportVersionStore = new ReportVersionStore();
