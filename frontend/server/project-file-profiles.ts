/**
 * The profiler's verdict per project-file VERSION, so the file tree's quality dot and the dataset
 * panel show the same result (dataset panel audit round 3, B4).
 *
 * The tree used to decide on its own which files to profile (a client extension allowlist that
 * predated FASTA / GTF / BED / BAM / JSONL support), so files the panel profiled as Good showed
 * "not profiled (unsupported file type)". Now every successful POST /api/perception/profile of a
 * project file stores the verdict it returned, keyed by the object key it profiled; the files list
 * (and the edit / restore / rename responses, which return list-shaped rows) carry it as
 * `profileSummary`. An object key is never rewritten — new bytes always get a new key — so a
 * summary always describes the bytes of the version it is attached to: an edit's new key has none
 * until it is profiled, a restore that makes an old version current again gets that version's,
 * a rename keeps its own.
 *
 * Only the profiler decides "not profilable": its `unprofilable` finding (verdict "unassessed").
 * Failures to REACH the bytes (unresolvable ref, missing object) say nothing about the file and
 * are never stored.
 */

type QueryFn = (text: string, params?: unknown[]) => Promise<{ rows: any[] }>;

export interface ProfileSummary {
  /** The profiler's verdict, verbatim (the client derives its shown verdict with effectiveQuality). */
  quality: "good" | "watch" | "blocked" | "unassessed";
  /** The findings' identity and level — what effectiveQuality and the "unsupported" state read. */
  findings: Array<{ code: string; level: string; section?: string }>;
  viewKind: string | null;
  profiledAt: string;
}

const VERDICTS = new Set(["good", "watch", "blocked", "unassessed"]);
/** Blocked findings that mean "the bytes could not be fetched", not "the bytes are bad". */
const UNREACHED = new Set(["no_ref", "unresolvable_ref", "file_not_found", "no_path"]);
const MAX_FINDINGS = 50;

export const PROFILE_TABLE_DDL = `
  CREATE TABLE IF NOT EXISTS project_file_profiles (
    s3_key      TEXT PRIMARY KEY,
    quality     TEXT NOT NULL,
    findings    JSONB NOT NULL DEFAULT '[]'::jsonb,
    view_kind   TEXT,
    profiled_at TIMESTAMPTZ NOT NULL DEFAULT now()
  )`;

/** The summary to store for a profile response body, or null when it must not be stored. */
export function summarizeProfile(body: unknown): Omit<ProfileSummary, "profiledAt"> | null {
  if (!body || typeof body !== "object") return null;
  const b = body as Record<string, any>;
  if (typeof b.quality !== "string" || !VERDICTS.has(b.quality)) return null;
  const findings = (Array.isArray(b.findings) ? b.findings : [])
    .filter((f: any) => f && typeof f.code === "string" && typeof f.level === "string")
    .slice(0, MAX_FINDINGS)
    .map((f: any) => ({ code: f.code, level: f.level, ...(typeof f.section === "string" ? { section: f.section } : {}) }));
  if (b.quality === "blocked" && findings.some((f: { code: string }) => UNREACHED.has(f.code))) return null;
  return { quality: b.quality as ProfileSummary["quality"], findings, viewKind: typeof b.viewKind === "string" ? b.viewKind : null };
}

export async function saveProfileSummary(query: QueryFn, key: string, s: Omit<ProfileSummary, "profiledAt">): Promise<void> {
  await query(
    `INSERT INTO project_file_profiles (s3_key, quality, findings, view_kind, profiled_at)
     VALUES ($1, $2, $3::jsonb, $4, now())
     ON CONFLICT (s3_key) DO UPDATE SET quality = EXCLUDED.quality, findings = EXCLUDED.findings,
       view_kind = EXCLUDED.view_kind, profiled_at = EXCLUDED.profiled_at`,
    [key, s.quality, JSON.stringify(s.findings), s.viewKind],
  );
}

export async function loadProfileSummaries(query: QueryFn, keys: string[]): Promise<Map<string, ProfileSummary>> {
  const out = new Map<string, ProfileSummary>();
  const uniq = [...new Set(keys.filter((k) => typeof k === "string" && k))];
  if (!uniq.length) return out;
  const r = await query(
    `SELECT s3_key, quality, findings, view_kind, profiled_at FROM project_file_profiles WHERE s3_key = ANY($1::text[])`,
    [uniq],
  );
  for (const row of r.rows) {
    const findings = typeof row.findings === "string" ? JSON.parse(row.findings) : row.findings;
    out.set(String(row.s3_key), {
      quality: row.quality,
      findings: Array.isArray(findings) ? findings : [],
      viewKind: row.view_kind ?? null,
      profiledAt: new Date(row.profiled_at).toISOString(),
    });
  }
  return out;
}

/**
 * File rows (list-shaped) with `profileSummary` attached: the stored verdict for the row's
 * CURRENT key, or null when that version has not been profiled. A failed lookup is logged and
 * yields null summaries (the client then profiles), never a failed file listing.
 */
export async function withProfileSummaries<T extends { s3_key?: unknown }>(query: QueryFn, rows: T[]): Promise<Array<T & { profileSummary: ProfileSummary | null }>> {
  let byKey = new Map<string, ProfileSummary>();
  try {
    byKey = await loadProfileSummaries(query, rows.map((r) => String(r?.s3_key ?? "")));
  } catch (e: any) {
    console.warn("[project_files] profile summaries unavailable:", e?.message ?? e);
  }
  return rows.map((r) => ({ ...r, profileSummary: byKey.get(String(r?.s3_key ?? "")) ?? null }));
}

/**
 * Middleware for POST /api/perception/profile, after the dataset gate (req.datasetKey) and before
 * the backend passthrough: when the backend answers 200 with a profile of a project file, store
 * its summary for that key. The response itself is relayed unchanged; a failed store is logged.
 */
export function recordProfileSummary(query: QueryFn) {
  return (req: any, res: any, next: () => void) => {
    const key: unknown = req.datasetKey;
    if (typeof key === "string" && key) {
      const json = res.json.bind(res);
      res.json = (body: unknown) => {
        const summary = res.statusCode === 200 ? summarizeProfile(body) : null;
        if (!summary) return json(body);
        // Stored BEFORE the response is sent, so a files list fetched after it carries this verdict.
        saveProfileSummary(query, key, summary)
          .catch((e: any) => console.warn("[perception] profile summary not stored:", e?.message ?? e))
          .finally(() => json(body));
        return res;
      };
    }
    next();
  };
}
