/**
 * Project CRUD routes.
 *
 * Surfaces ltm projects to the client so users can create, list, rename,
 * archive, and delete them. The chat-stream endpoint reads
 * context.projectId; this is the path by which that projectId comes to
 * exist in the first place.
 *
 * Policy (docs/20260612_DATASET_STORAGE_AND_SESSION_BOUNDARIES.md):
 *   - Projects are user-owned. Endpoints scope every query to req.user.id.
 *     A user cannot read or mutate another user's project. Verified at
 *     row-fetch time (404 if not owned, NOT 403, so we don't leak existence).
 *   - Archiving is soft (status='archived'). Deletion is hard and CASCADEs
 *     to episodes/procedures/knowledge; chat_sessions.project_id becomes
 *     NULL (ON DELETE SET NULL) — sessions survive without a project.
 */

import type { Express, Request, Response } from "express";
import { registerProjectInstructionSettings } from "./project-instruction-settings";
import { authenticateToken } from "./auth-middleware";
import { memoryService } from "./memory-repository";
import { pool } from "./db";
import { canonicalTier, canCollaborate, FREE_PROJECT_LIMIT, tierEnforcementEnabled } from "./tier";
import { s3Service } from "./s3-client";
import { checkTabularCompatibility, parseHeaderColumns, formatFromName, isTabularFormat } from "./input-compatibility";
import { validateRemoteFileUrl } from "./remote-source-validation";
import { emailService } from "./email-service";
import {
  projectInputPath, projectInputKey, decodeMultipartFilename,
  planFileRename, planFolderRename, objectKeyCandidates, pickFreeObjectKey,
  decideIngest, ancestorNames,
} from "./project-file-paths";
import { downloadName } from "./content-disposition";
import multer from "multer";
import { randomUUID, randomBytes, createHash } from "crypto";
import { applyCellEdits, isReaderDelimiter, pickDelimiter, tableRows, READER_DELIMITERS, type CellEdit } from "./delimited-text";
import path from "path";
import fs from "fs";
import {
  likePrefix, loadFolderContext, loadFolderFiles, normalizeFolderPath, samplesheetFilename,
  samplesheetStoredName, pickFolderSamplesheetCsv,
} from "./project-folders";
import { PROFILE_TABLE_DDL, withProfileSummaries } from "./project-file-profiles";

/** pool.query as the plain query function the helper modules take (resolved at call time). */
const _q = (text: string, params?: unknown[]) => pool.query(text, params as any[]);

async function ensureProjectMembersTable(): Promise<void> {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS project_members (
      id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      project_id  UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
      user_id     TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      role        TEXT NOT NULL DEFAULT 'viewer' CHECK (role IN ('viewer', 'editor')),
      invited_by  TEXT REFERENCES users(id) ON DELETE SET NULL,
      created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      UNIQUE(project_id, user_id)
    )
  `);
  await pool.query(`CREATE INDEX IF NOT EXISTS project_members_project_idx ON project_members(project_id)`);
  await pool.query(`CREATE INDEX IF NOT EXISTS project_members_user_idx    ON project_members(user_id)`);
}
ensureProjectMembersTable().catch(e => console.error("[project_members] table init failed:", e?.message ?? e));

async function ensureProjectShareTokensTable(): Promise<void> {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS project_share_tokens (
      id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      project_id  UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
      token       TEXT UNIQUE NOT NULL,
      role        TEXT NOT NULL DEFAULT 'viewer' CHECK (role IN ('viewer', 'editor')),
      created_by  TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      expires_at  TIMESTAMPTZ,
      -- NULL = the owner's generic /share-link token (one per project; the
      -- /share-link GET/POST/DELETE endpoints scope to invited_email IS NULL).
      -- Set = a per-email invite token carrying THAT invite's own role, minted
      -- by POST /members for an unregistered email. Keeping them distinct is
      -- what stops a later invite from escalating a still-pending lower-role one.
      invited_email TEXT
    )
  `);
  // Idempotent migration for pre-existing single-row installs (their one row is
  // the generic link → invited_email stays NULL, preserving backward behavior).
  await pool.query(`ALTER TABLE project_share_tokens ADD COLUMN IF NOT EXISTS invited_email TEXT`);
  await pool.query(`CREATE INDEX IF NOT EXISTS pst_project_idx ON project_share_tokens(project_id)`);
  await pool.query(`CREATE INDEX IF NOT EXISTS pst_token_idx   ON project_share_tokens(token)`);
  // Lookups for "the generic link" and "a pending invite to this email" both
  // filter on (project_id, invited_email); index the pair.
  await pool.query(`CREATE INDEX IF NOT EXISTS pst_project_email_idx ON project_share_tokens(project_id, invited_email)`);
}
ensureProjectShareTokensTable().catch(e => console.error("[project_share_tokens] table init failed:", e?.message ?? e));

// Read just enough of an S3 object to capture its header line (first newline).
// Ranged GET avoids downloading large files to compare a schema.
async function _readS3Header(bucket: string, key: string): Promise<string> {
  const { S3Client, GetObjectCommand } = await import("@aws-sdk/client-s3");
  const s3 = new S3Client({
    region: process.env.AWS_DEFAULT_REGION || process.env.AWS_REGION || "us-east-1",
    followRegionRedirects: true,
  });
  const obj = await s3.send(new GetObjectCommand({ Bucket: bucket, Key: key, Range: "bytes=0-65535" }));
  const chunks: Buffer[] = [];
  for await (const chunk of obj.Body as any) {
    chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
    if (Buffer.concat(chunks).toString("utf8").includes("\n")) break;
  }
  return Buffer.concat(chunks).toString("utf8");
}

export async function _isOwnerOrMember(projectId: string, uid: string): Promise<boolean> {
  const project = await memoryService.projects.getProject(projectId);
  if (!project) return false;
  if (project.userId === uid) return true;
  const r = await pool.query(
    `SELECT 1 FROM project_members WHERE project_id = $1 AND user_id::text = $2`,
    [projectId, uid]
  );
  return r.rows.length > 0;
}

// The caller's role on a project: 'owner' | 'editor' | 'viewer' | null (no access).
// Content edits (instructions, tags, files) require owner OR editor; project
// lifecycle (status/archive/delete), member management and share links stay owner-only.
async function _getUserRole(
  projectId: string, uid: string
): Promise<'owner' | 'editor' | 'viewer' | null> {
  const project = await memoryService.projects.getProject(projectId);
  if (!project) return null;
  if (project.userId === uid) return 'owner';
  const r = await pool.query(
    `SELECT role FROM project_members WHERE project_id = $1 AND user_id::text = $2`,
    [projectId, uid]
  );
  if (!r.rows.length) return null;
  return r.rows[0].role === 'editor' ? 'editor' : 'viewer';
}

export async function _isOwnerOrEditor(projectId: string, uid: string): Promise<boolean> {
  const role = await _getUserRole(projectId, uid);
  return role === 'owner' || role === 'editor';
}

// Multer: temp disk for project file uploads (max 500 MB)
const _projectUploadDir = path.join(process.cwd(), "data", "project-uploads");
if (!fs.existsSync(_projectUploadDir)) fs.mkdirSync(_projectUploadDir, { recursive: true });
const projectUpload = multer({
  dest: _projectUploadDir,
  limits: { fileSize: 500 * 1024 * 1024 },
});

/** A failed schema step must be visible: later queries on a missing column fail with a confusing
 *  error far from the cause (audit: these were silently swallowed). */
const _ddlFailed = (e: any) => console.error("[project_files] schema step failed:", e?.message ?? e);

async function ensureProjectFilesTable(): Promise<void> {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS project_files (
      id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      project_id  UUID NOT NULL,
      user_id     TEXT NOT NULL,
      name        TEXT NOT NULL,
      s3_key      TEXT NOT NULL,
      size        BIGINT NOT NULL DEFAULT 0,
      content_type TEXT NOT NULL DEFAULT 'application/octet-stream',
      source      TEXT NOT NULL DEFAULT 'upload',
      run_id      TEXT,
      created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
    )
  `);
  await pool.query(`CREATE INDEX IF NOT EXISTS project_files_project_idx ON project_files(project_id)`);
  // Idempotent column additions for run_output support.
  await pool.query(`ALTER TABLE project_files ADD COLUMN IF NOT EXISTS workflow_name TEXT`).catch(_ddlFailed);
  await pool.query(`ALTER TABLE project_files ADD COLUMN IF NOT EXISTS step_name TEXT`).catch(_ddlFailed);
  await pool.query(`ALTER TABLE project_files ADD COLUMN IF NOT EXISTS input_context JSONB`).catch(_ddlFailed);
  // Content hash for dedup (design §4.5.1 — the same file added twice links to one
  // entry rather than creating two). sha256 hex, computed at ingest.
  await pool.query(`ALTER TABLE project_files ADD COLUMN IF NOT EXISTS content_hash TEXT`).catch(_ddlFailed);
  await pool.query(`CREATE INDEX IF NOT EXISTS project_files_hash_idx ON project_files(project_id, content_hash)`).catch(_ddlFailed);
  // App-level content versioning (design §4.4 — "saving an edit writes a new
  // version; it never overwrites"). The project_files row is the CURRENT version
  // (version_no); every SUPERSEDED version is archived as its own S3 object +
  // a project_file_versions row. No S3 bucket-versioning required — each version
  // is a distinct object, so a completed run always keeps the exact bytes it read.
  await pool.query(`ALTER TABLE project_files ADD COLUMN IF NOT EXISTS version_no INTEGER NOT NULL DEFAULT 1`).catch(_ddlFailed);
  await pool.query(`
    CREATE TABLE IF NOT EXISTS project_file_versions (
      id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      file_id      UUID NOT NULL,
      project_id   UUID NOT NULL,
      version_no   INTEGER NOT NULL,
      s3_key       TEXT NOT NULL,
      size         BIGINT NOT NULL DEFAULT 0,
      content_type TEXT NOT NULL DEFAULT 'application/octet-stream',
      content_hash TEXT,
      note         TEXT,
      author       TEXT,
      created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
    )
  `).catch(_ddlFailed);
  await pool.query(`CREATE INDEX IF NOT EXISTS project_file_versions_file_idx ON project_file_versions(file_id, version_no)`).catch(_ddlFailed);
  // When/by whom each version was WRITTEN (2026-11-12). project_files carries it for the current
  // version; an archived row copies it, so the Versions tab shows each version's own time and
  // author (archived rows' created_at/author are the archive event — when the NEXT version was
  // written — which is what the tab used to show, one version off).
  await pool.query(`ALTER TABLE project_files ADD COLUMN IF NOT EXISTS version_created_at TIMESTAMPTZ`).catch(_ddlFailed);
  await pool.query(`ALTER TABLE project_files ADD COLUMN IF NOT EXISTS version_author TEXT`).catch(_ddlFailed);
  await pool.query(`ALTER TABLE project_file_versions ADD COLUMN IF NOT EXISTS version_created_at TIMESTAMPTZ`).catch(_ddlFailed);
  await pool.query(`ALTER TABLE project_file_versions ADD COLUMN IF NOT EXISTS version_author TEXT`).catch(_ddlFailed);
  // S3 keys handed to an in-flight write (upload/import/generated file) before its bytes are put
  // and its row inserted — so key allocation under the project lock sees keys whose rows do not
  // exist yet (see _storeProjectInput). Rows are deleted when the key becomes a file's s3_key.
  await pool.query(`
    CREATE TABLE IF NOT EXISTS project_object_key_reservations (
      s3_key      TEXT PRIMARY KEY,
      project_id  TEXT NOT NULL,
      created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
    )
  `).catch(_ddlFailed);
  // The dataset gate resolves a profile / rows / datasets ref by its object key — the current key
  // or an archived version's (dataset-reference-access.ts) — on every panel request.
  await pool.query(`CREATE INDEX IF NOT EXISTS project_files_s3_key_idx ON project_files(s3_key)`).catch(_ddlFailed);
  await pool.query(`CREATE INDEX IF NOT EXISTS project_file_versions_s3_key_idx ON project_file_versions(s3_key)`).catch(_ddlFailed);
  // The profiler's verdict per object key (project-file-profiles.ts): the tree's quality dot.
  await pool.query(PROFILE_TABLE_DDL).catch(_ddlFailed);
}
// Run once on startup — idempotent
ensureProjectFilesTable().catch(e => console.error("[project_files] table init failed:", e?.message ?? e));

/** A cleanup step failed: say so (an orphaned object / reservation / index must be findable in
 *  the logs) and carry on — the caller is already on its error or cleanup path. */
function _logCleanupFailure(what: string): (e: unknown) => void {
  return (e: unknown) => console.warn(`[project_files] cleanup failed (${what}):`, (e as any)?.message ?? e);
}

/** Anything with pg's query() — the pool, or a transaction client holding the project lock. */
type Querier = { query: (text: string, params?: any[]) => Promise<any> };

const _UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export function _isUuid(v: unknown): boolean {
  return typeof v === "string" && _UUID_RE.test(v);
}

/** Project file routes: project and file ids are UUIDs. Anything else names nothing → 404 (it
 *  used to reach a uuid-typed comparison and come back as a 500/502 cast error). */
/** Stored bytes a TIFF preview may send to the renderer (the backend checks it again). */
export const MAX_PREVIEW_INPUT_BYTES = 256 * 1024 * 1024;
/** Bumped when the renderer's picture for the same bytes changes (invalidates ETags). */
const PREVIEW_RENDER_VERSION = 1;
/** Renderer statuses forwarded as-is (with its code + reason). 403 (a refused ref) is not one:
 *  the route only sends this project's keys, so a refusal there is a server fault (502). */
const PREVIEW_PASSTHROUGH = new Set([400, 404, 413, 415, 422, 503]);

/** ?series=&page= of a preview: non-negative integers (default 0), else null. */
export function parsePreviewSelection(q: Record<string, unknown>): { series: number; page: number } | null {
  const one = (v: unknown): number | null => {
    if (v === undefined || v === "") return 0;
    if (typeof v !== "string" || !/^\d{1,6}$/.test(v)) return null;
    return Number(v);
  };
  const series = one(q.series), page = one(q.page);
  return series === null || page === null ? null : { series, page };
}

export function _projectFileIds(req: Request, res: Response, next: () => void): void {
  const { id, fileId } = req.params as Record<string, string | undefined>;
  if (!_isUuid(id)) { res.status(404).json({ error: "Project not found" }); return; }
  if (fileId !== undefined && !_isUuid(fileId)) { res.status(404).json({ error: "File not found" }); return; }
  next();
}

/**
 * Run `fn` in one transaction holding the project's file lock — the advisory lock every
 * read-modify-write of a project's files takes (renames, folder moves, uploads, URL imports,
 * generated files, edits, restores, deletes), so two writers can never both pass a check that
 * only one of them may pass. Commits on return, rolls back on throw.
 */
async function _withProjectLock<T>(projectId: string, fn: (c: Querier) => Promise<T>): Promise<T> {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    await client.query("SELECT pg_advisory_xact_lock(hashtext($1))", [`project_files:${projectId}`]);
    const out = await fn(client);
    await client.query("COMMIT");
    return out;
  } catch (e) {
    await client.query("ROLLBACK").catch(_logCleanupFailure(`ROLLBACK for project ${projectId}`));
    throw e;
  } finally {
    client.release();
  }
}

/** Every column of a project_files row the write paths need (internal; never sent as-is). */
const _ROW_COLUMNS =
  "id::text AS id, project_id::text AS project_id, user_id, name, s3_key, size, content_type, source, run_id, " +
  "content_hash, version_no, created_at, version_created_at, version_author";

const _FILE_COLUMNS =
  "id, name, s3_key, size, content_type, source, run_id, workflow_name, step_name, input_context, content_hash, version_no, created_at";
const _FILE_KEYS = _FILE_COLUMNS.split(", ");

/**
 * Derive the durable s3:// URI for a project_files row. The DB stores only
 * s3_key; clients (cold-start remasure, chat attach, generate_workflow) need
 * s3_uri to bind training datasets. Not an error/sanitization path — the key
 * was always written; the public shape previously omitted the URI.
 */
function _withS3Uri<T extends { s3_key?: unknown }>(row: T): T & { s3_uri?: string } {
  if (!row || typeof row !== "object") return row;
  const key = typeof row.s3_key === "string" ? row.s3_key : "";
  const bucket = process.env.S3_BUCKET_NAME || "";
  if (!key || !bucket) return { ...row };
  return { ...row, s3_uri: `s3://${bucket}/${key}` };
}

/** The client-facing shape of a file row (the columns every ingest endpoint responds with). */
function _publicFile(row: any): any {
  if (!row) return row;
  const out: Record<string, unknown> = {};
  for (const k of _FILE_KEYS) if (k in row) out[k] = row[k];
  return _withS3Uri(out);
}

/** Key reservations live 24 h: long enough for any upload's put, short enough that a crashed
 *  request's reservation (whose object, if any, nothing references) is eventually reused. */
const _RESERVATION_TTL = "24 hours";

/**
 * The S3 key a NEW object (upload, URL import, generated file, or a new version) is written
 * to: the name-derived key when no project file, archived version or in-flight reservation
 * references it, else the same key with a numeric suffix. Keys are derived from names, and a
 * rename never moves the object, so after "a.csv" is renamed to "b.csv" its bytes still live at
 * …/a.csv — without this, uploading a new "a.csv" would overwrite them. Call it with the
 * project lock held (`q` = the locked client) and reserve/occupy the key before releasing it:
 * a check-then-put without the lock let two uploads of one new name write the same key.
 */
async function _allocateObjectKey(q: Querier, projectId: string, desired: string): Promise<string> {
  const candidates = objectKeyCandidates(desired);
  const r = await q.query(
    `SELECT s3_key FROM project_files WHERE project_id::text = $1 AND s3_key = ANY($2::text[])
     UNION SELECT s3_key FROM project_file_versions WHERE project_id::text = $1 AND s3_key = ANY($2::text[])
     UNION SELECT s3_key FROM project_object_key_reservations
       WHERE project_id = $1 AND s3_key = ANY($2::text[]) AND created_at > now() - interval '${_RESERVATION_TTL}'`,
    [projectId, candidates]
  );
  const taken = new Set<string>(r.rows.map((x: any) => String(x.s3_key)));
  return pickFreeObjectKey(candidates, taken) ?? `${desired}.${randomBytes(4).toString("hex")}`;
}

async function _reserveObjectKey(q: Querier, projectId: string, key: string): Promise<void> {
  await q.query(
    `INSERT INTO project_object_key_reservations (s3_key, project_id) VALUES ($1, $2)
     ON CONFLICT (s3_key) DO UPDATE SET project_id = EXCLUDED.project_id, created_at = now()`,
    [key, projectId]
  );
}

async function _releaseObjectKey(key: string): Promise<void> {
  await pool.query(`DELETE FROM project_object_key_reservations WHERE s3_key = $1`, [key]);
}

/** galaxy-user-fetch, loaded lazily ONCE (one shared import promise — the diff asks for two
 *  layouts concurrently). */
let _galaxyUserFetchMod: Promise<typeof import("./galaxy-user-fetch")> | null = null;
function _galaxyUserFetch(): Promise<typeof import("./galaxy-user-fetch")> {
  return (_galaxyUserFetchMod ??= import("./galaxy-user-fetch"));
}

/** POST the Python rows reader (/api/perception/rows) for one stored object, as the caller —
 *  the same call the rows route makes. Returns the parsed body, or null when the backend did
 *  not answer with one (the caller turns that into an explicit error, never into "no rows"). */
async function _postReaderRows(
  req: Request, datasetRef: string, name: string, offset: number, limit: number,
  folderContext: { name: string; siblings: string[] } | null,
): Promise<{ status: number; body: any | null }> {
  const { fetchGalaxyAsUser, galaxyBaseUrl } = await _galaxyUserFetch();
  const resp = await fetchGalaxyAsUser(req, `${galaxyBaseUrl()}/api/perception/rows`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ datasetRef, name, offset, limit, ...(folderContext ? { folderContext } : {}) }),
    signal: AbortSignal.timeout(120_000),
  });
  const body: any = await resp.json().catch(() => null);
  return { status: resp.status, body: resp.ok ? body : null };
}

/** How the rows reader lays out one stored version: whether it is a table, its column names,
 *  header records, leading skipped lines and delimiter — the numbering the Preview shows and
 *  the edit route uses. `delimiter` is null when the reader does not report one (older
 *  backend); callers then fall back to pickDelimiter, as the edit route does. */
type ReaderLayout =
  | { tabular: true; columns: string[]; headerRows: 0 | 1; skipLines: number; delimiter: string | null }
  | { tabular: false; reason: string };

async function _readerLayout(
  req: Request, datasetRef: string, name: string, folderContext: { name: string; siblings: string[] } | null,
): Promise<ReaderLayout> {
  const { status, body } = await _postReaderRows(req, datasetRef, name, 0, 1, folderContext);
  if (!body) throw new Error(`rows reader answered ${status}`);
  if (body.error === "unresolvable_ref") throw new Error("rows reader could not resolve the object");
  if (body.error) return { tabular: false, reason: "parse_failed" };
  if (body.tabular === false || body.kind !== "table") return { tabular: false, reason: String(body.reason || body.kind || "not_tabular") };
  return {
    tabular: true,
    columns: Array.isArray(body.columns) ? body.columns.map(String) : [],
    headerRows: body.headerRow === false ? 0 : 1,
    skipLines: Number.isInteger(body.skipLines) && body.skipLines >= 0 ? body.skipLines : 0,
    delimiter: isReaderDelimiter(body.delimiter) ? body.delimiter : null,
  };
}

/** One version's data rows (capped), numbered with that version's reader layout. */
function _layoutRows(text: string, ext: string, lay: Extract<ReaderLayout, { tabular: true }>, maxRows: number) {
  const delim = lay.delimiter ?? pickDelimiter(text, ext);
  const t = tableRows(text, delim, { headerRows: lay.headerRows, skipLines: lay.skipLines }, maxRows);
  return { headers: lay.columns.length ? lay.columns : (t.header ?? []), rows: t.rows };
}

/**
 * When and by whom a file's CURRENT version was written. Rows written since 2026-11-12 carry it
 * (version_created_at / version_author). Older rows did not, and their archived versions were
 * stamped with the ARCHIVE event (created_at/author = when/who wrote the NEXT version) — so for
 * those, version n was written when version n-1 was archived, and v1 when the file was created.
 */
async function _currentVersionOrigin(q: Querier, cur: any): Promise<{ at: any; by: string | null }> {
  if (cur.version_created_at) return { at: cur.version_created_at, by: cur.version_author ?? null };
  if (Number(cur.version_no) > 1) {
    const prev = await q.query(
      `SELECT created_at, author FROM project_file_versions WHERE file_id::text = $1 AND version_no = $2
       ORDER BY created_at ASC LIMIT 1`,
      [String(cur.id), Number(cur.version_no) - 1]
    );
    if (prev.rows[0]) return { at: prev.rows[0].created_at, by: prev.rows[0].author ?? null };
  }
  return { at: cur.created_at, by: cur.user_id ?? null };
}

/** Append-only: archive a project file's CURRENT content as a project_file_versions row
 *  (design §4.4 — nothing a finished run read can change underneath it). The current bytes stay
 *  at their s3_key; the row records them as a past version — with the time and author of THAT
 *  version (version_created_at / version_author) — so the new content can take over the
 *  project_files row. `created_at` / `author` record the archive event itself. */
async function _archiveCurrentAsVersion(q: Querier, cur: any, projectId: string, archivedBy: string): Promise<void> {
  const origin = await _currentVersionOrigin(q, cur);
  await q.query(
    `INSERT INTO project_file_versions
       (file_id, project_id, version_no, s3_key, size, content_type, content_hash, note, author, version_created_at, version_author)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)`,
    [String(cur.id), projectId, Number(cur.version_no), cur.s3_key, cur.size, cur.content_type,
     cur.content_hash ?? null, `v${cur.version_no}`, archivedBy, origin.at, origin.by]
  );
}

/** The project rows an ingest of `name` (bytes hashing to `hash`) must consider: the same
 *  bytes (dedup), the same name (version / clash), a file under `name/` (a folder of that name)
 *  or a FILE named like one of `name`'s folders. */
async function _ingestRows(q: Querier, projectId: string, name: string, hash: string): Promise<any[]> {
  const r = await q.query(
    `SELECT ${_ROW_COLUMNS} FROM project_files
     WHERE project_id::text = $1
       AND (content_hash = $2 OR name = $3 OR name LIKE $4 ESCAPE '\\' OR name = ANY($5::text[]))`,
    [projectId, hash, name, `${likePrefix(name)}/%`, ancestorNames(name)]
  );
  return r.rows;
}

type StoreResult =
  | { status: 201; file: any; versioned: false }
  | { status: 200; file: any; versioned: true }
  | { status: 200; file: any; deduplicated: true }
  | { status: 409; code: "name_conflict"; error: string; conflicts: Array<{ name: string; existing: string }> };

/** The HTTP body for a StoreResult (upload / URL import). */
function _storeResponse(r: StoreResult): any {
  if (r.status === 409) return { error: r.error, code: r.code, conflicts: r.conflicts };
  if ("deduplicated" in r) return { file: r.file, deduplicated: true };
  return r.versioned ? { file: r.file, versioned: true } : { file: r.file };
}

/**
 * Store a project file from bytes (browser upload, URL import, generated file). One decision
 * (decideIngest — the shared name rule) made twice under the project lock:
 *   1. before the put: dedup / 409 return at once (nothing written); otherwise allocate the key
 *      and RESERVE it, so no concurrent writer can be handed the same key;
 *   2. the put runs without the lock (a 500 MB upload must not hold a DB connection + the
 *      project's lock);
 *   3. after the put: decide again on the rows as they are NOW. A concurrent upload of the same
 *      name that landed first turns this one into its next version (or a dedup / 409, after
 *      which this request's object is deleted). The version UPDATE carries the version_no it was
 *      decided on, so the row and the bytes always describe the same object.
 */
async function _storeProjectInput(o: {
  id: string; uid: string; name: string; key: string; buf: Buffer;
  contentType: string; contentHash: string; source: "upload" | "url" | "run_code";
}): Promise<StoreResult> {
  const plan = await _withProjectLock(o.id, async (c) => {
    const d = decideIngest(await _ingestRows(c, o.id, o.name, o.contentHash), o.name, o.source, o.contentHash);
    if (d.kind === "dedup" || d.kind === "conflict") return { d, key: null as string | null };
    const desired = d.kind === "version" ? `${o.key}.v${Number(d.row.version_no) + 1}` : o.key;
    const key = await _allocateObjectKey(c, o.id, desired);
    await _reserveObjectKey(c, o.id, key);
    return { d, key };
  });
  if (plan.d.kind === "dedup") return { status: 200, file: _publicFile(plan.d.row), deduplicated: true };
  if (plan.d.kind === "conflict") return { status: 409, code: "name_conflict", error: plan.d.error, conflicts: plan.d.conflicts };
  const key = plan.key as string;

  // The object is deleted BEFORE its reservation is released, so a key is never handed to a new
  // writer while bytes this request wrote may still land on it.
  const discard = async () => {
    await s3Service.deleteFile(key);
    await _releaseObjectKey(key).catch(_logCleanupFailure(`release key reservation ${key}`));
  };
  try {
    await s3Service.putObject(key, o.buf, o.contentType, o.uid);
  } catch (e) {
    await discard().catch(_logCleanupFailure(`discard object ${key} after a failed put`));
    throw e;
  }

  let out: StoreResult & { orphan?: boolean; activity?: () => Promise<void> };
  try {
    out = await _withProjectLock(o.id, async (c) => {
      const d = decideIngest(await _ingestRows(c, o.id, o.name, o.contentHash), o.name, o.source, o.contentHash);
      if (d.kind === "dedup") return { status: 200 as const, file: _publicFile(d.row), deduplicated: true as const, orphan: true };
      if (d.kind === "conflict") return { status: 409 as const, code: "name_conflict" as const, error: d.error, conflicts: d.conflicts, orphan: true };
      if (d.kind === "version") {
        await _archiveCurrentAsVersion(c, d.row, o.id, o.uid);
        const upd = await c.query(
          `UPDATE project_files SET s3_key = $1, size = $2, content_type = $3, content_hash = $4,
             version_no = version_no + 1, version_created_at = now(), version_author = $5
           WHERE id::text = $6 AND version_no = $7
           RETURNING ${_FILE_COLUMNS}`,
          [key, o.buf.length, o.contentType, o.contentHash, o.uid, d.row.id, Number(d.row.version_no)]
        );
        if (!upd.rows[0]) throw new Error(`version precondition failed for file ${d.row.id} under the project lock`);
        await c.query(`DELETE FROM project_object_key_reservations WHERE s3_key = $1`, [key]);
        const file = upd.rows[0];
        return { status: 200 as const, file, versioned: true as const,
          activity: () => recordProjectActivity(o.id, o.uid, "file_versioned", { fileId: d.row.id, name: o.name, version: file.version_no }) };
      }
      const ins = await c.query(
        `INSERT INTO project_files
           (project_id, user_id, name, s3_key, size, content_type, source, content_hash, version_created_at, version_author)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, now(), $2)
         RETURNING ${_FILE_COLUMNS}`,
        [o.id, o.uid, o.name, key, o.buf.length, o.contentType, o.source, o.contentHash]
      );
      await c.query(`DELETE FROM project_object_key_reservations WHERE s3_key = $1`, [key]);
      const file = ins.rows[0];
      return { status: 201 as const, file, versioned: false as const,
        activity: () => recordProjectActivity(o.id, o.uid, "file_added", { fileId: file.id, name: o.name, source: o.source }) };
    });
  } catch (e) {
    await discard().catch(_logCleanupFailure(`discard object ${key} after a failed register`));
    throw e;
  }
  if (out.orphan) await discard();
  if (out.activity) await out.activity();
  const { orphan: _o, activity: _a, ...result } = out as any;
  return result as StoreResult;
}

/**
 * Apply a rename plan atomically under the project lock: the plan is computed from the rows
 * read INSIDE the lock (so two concurrent renames can't both pass the collision check), then
 * every move is one UPDATE — all files move or none do.
 */
async function _applyRenamePlan(
  projectId: string,
  plan: (rows: Array<{ id: string; name: string; source: string }>) => ReturnType<typeof planFileRename>,
): Promise<ReturnType<typeof planFileRename>> {
  return _withProjectLock(projectId, async (c) => {
    const rows = await c.query(
      `SELECT id::text AS id, name, source FROM project_files WHERE project_id::text = $1`,
      [projectId]
    );
    const out = plan(rows.rows);
    if (!out.ok || out.moves.length === 0) return out;
    const upd = await c.query(
      `UPDATE project_files f SET name = v.new_name
       FROM unnest($1::text[], $2::text[]) AS v(id, new_name)
       WHERE f.id::text = v.id AND f.project_id::text = $3`,
      [out.moves.map((m) => m.id), out.moves.map((m) => m.to), projectId]
    );
    if ((upd.rowCount ?? 0) !== out.moves.length) {
      throw new Error(`rename updated ${upd.rowCount} of ${out.moves.length} rows`);
    }
    return out;
  });
}

function userId(req: Request): string | null {
  const u = (req as any).user;
  return u?.id ? String(u.id) : null;
}

// Collaboration (share links, member invites, roles) is Team-only per
// docs/20260727_TIER_MODEL_DECISION.md. When enforcement is on and the caller's
// plan can't collaborate, sends 402 and returns true. No-op when enforcement is off.
function blockedByCollaborationTier(req: Request, res: Response): boolean {
  if (!tierEnforcementEnabled()) return false;
  if (canCollaborate((req as any).user?.subscriptionTier)) return false;
  res.status(402).json({
    error: "TEAM_REQUIRED",
    message: "Collaboration (sharing, inviting members, roles) requires a Team plan.",
    upgrade: "team",
  });
  return true;
}

// #24 (L2): a proposal/plan is a first-class object a run can cite (basedOnPlanId),
// not just chat metadata. Lazy migration mirrors the project_members pattern.
async function ensureProjectPlansTable(): Promise<void> {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS project_plans (
      id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      project_id    UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
      goal          TEXT NOT NULL,
      hypothesis    TEXT,
      referenced_dataset_ids  JSONB NOT NULL DEFAULT '[]',
      referenced_evidence_ids JSONB NOT NULL DEFAULT '[]',
      created_by    TEXT REFERENCES users(id) ON DELETE SET NULL,
      created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);
  await pool.query(`CREATE INDEX IF NOT EXISTS project_plans_project_idx ON project_plans(project_id)`);
}
ensureProjectPlansTable().catch(e => console.error("[project_plans] table init failed:", e?.message ?? e));

// Team workspace Phase 1: immutable project activity ledger
// (docs/20261003_TEAM_WORKSPACE_IMPLEMENTATION_PLAN.md §Phase 1). Append-only
// provenance of who changed what in a shared project. Lazy migration mirrors
// the project_members/project_files/project_plans pattern; the canonical schema
// is migrations/0022_project_activity.sql.
async function ensureProjectActivityTable(): Promise<void> {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS project_activity (
      id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      project_id     UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
      actor_user_id  TEXT REFERENCES users(id) ON DELETE SET NULL,
      event_type     TEXT NOT NULL,
      payload        JSONB NOT NULL DEFAULT '{}'::jsonb,
      created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);
  await pool.query(
    `CREATE INDEX IF NOT EXISTS project_activity_project_created_idx ON project_activity (project_id, created_at DESC)`
  );
  await pool.query(`CREATE INDEX IF NOT EXISTS project_activity_project_idx ON project_activity (project_id)`);
}
ensureProjectActivityTable().catch(e => console.error("[project_activity] table init failed:", e?.message ?? e));

// Closed, server-side set of activity event types. Clients NEVER submit
// event_type or payload — both are rendered server-side from known entities.
export type ProjectActivityEvent =
  | "member_added"
  | "member_invited"
  | "member_removed"
  | "role_changed"
  | "ownership_transferred"
  | "file_added"
  | "file_removed"
  | "file_versioned"
  | "file_restored"
  | "file_renamed"
  | "folder_renamed"
  | "plan_created";

/**
 * Append one immutable activity row. Call ONLY after the primary mutation has
 * succeeded (plan §3: "Route handlers … call it only after their primary
 * transaction succeeds").
 *
 * Best-effort by design: a ledger write failure is logged but never thrown, so
 * it can never convert a successful membership/file/plan mutation into an
 * unknown state (plan §3 "A failed activity insert must not silently convert a
 * successful … mutation into an unknown state"). Phase 1 accepts at-most-once
 * ledger semantics after commit; an outbox/transactional upgrade is a
 * documented follow-up.
 *
 * payload must contain only allowlisted, server-rendered references (target
 * user id, role, file id, plan id) — never raw file content, secrets, signed
 * URLs, prompt text, or model/worker logs.
 */
export async function recordProjectActivity(
  projectId: string,
  actorUserId: string | null,
  eventType: ProjectActivityEvent,
  payload: Record<string, unknown> = {},
): Promise<void> {
  try {
    await pool.query(
      `INSERT INTO project_activity (project_id, actor_user_id, event_type, payload)
       VALUES ($1, $2, $3, $4::jsonb)`,
      [projectId, actorUserId || null, eventType, JSON.stringify(payload ?? {})],
    );
  } catch (e: any) {
    console.error(`[project_activity] record failed (${eventType} on ${projectId}):`, e?.message ?? e);
  }
}

/** Browsers send no / a generic type for scientific formats (.jsonl arrived as
 *  application/octet-stream and was then shown as such in the dataset panel). Fill it from the
 *  extension when the client didn't provide a specific one. */
const EXT_CONTENT_TYPES: Record<string, string> = {
  ".jsonl": "application/x-ndjson", ".ndjson": "application/x-ndjson", ".json": "application/json",
  ".csv": "text/csv", ".tsv": "text/tab-separated-values", ".tab": "text/tab-separated-values",
  ".txt": "text/plain", ".vcf": "text/x-vcf", ".fasta": "text/x-fasta", ".fa": "text/x-fasta",
  ".fastq": "text/x-fastq", ".fq": "text/x-fastq", ".yaml": "application/yaml", ".yml": "application/yaml",
  ".parquet": "application/vnd.apache.parquet", ".h5ad": "application/x-hdf5", ".gz": "application/gzip",
};
export function uploadContentType(fileName: string, clientType?: string | null): string {
  if (clientType && clientType !== "application/octet-stream") return clientType;
  return EXT_CONTENT_TYPES[path.extname(fileName || "").toLowerCase()] || "application/octet-stream";
}

export function registerProjectRoutes(app: Express): void {
  registerProjectInstructionSettings(app, _getUserRole);
  // ─── GET /api/projects ────────────────────────────────────────────────
  // List the authenticated user's projects. Optional ?status=active|archived|completed.
  app.get("/api/projects", authenticateToken, async (req: Request, res: Response) => {
    const uid = userId(req);
    if (!uid) return res.status(401).json({ error: "Unauthorized" });
    const status = (req.query.status as string | undefined) as any;
    try {
      // The chat path always upserts ltm_users for the auth user; this
      // GET predates that upsert when the user has never chatted. Make
      // it idempotent here too so the API works on day 1.
      await memoryService.ensureLtmUser(
        uid,
        (req as any).user?.email,
        (req as any).user?.fullName ?? (req as any).user?.name
      );
      const projects = await memoryService.projects.getUserProjects(uid, status);
      res.json({ projects });
    } catch (e: any) {
      console.error("[projects] list failed:", e?.message ?? e);
      res.status(500).json({ error: "Failed to list projects" });
    }
  });

  // ─── POST /api/projects ───────────────────────────────────────────────
  // Create a new project. Required: name. Optional: description, research_goal,
  // primary_domain, organisms[], data_modalities[], etc.
  app.post("/api/projects", authenticateToken, async (req: Request, res: Response) => {
    const uid = userId(req);
    if (!uid) return res.status(401).json({ error: "Unauthorized" });
    const { name, description, researchGoal, primaryDomain, organisms, dataModalities } = req.body ?? {};
    if (!name || typeof name !== "string" || name.trim().length === 0) {
      return res.status(400).json({ error: "name is required" });
    }
    if (name.length > 255) {
      return res.status(400).json({ error: "name too long (max 255 chars)" });
    }
    try {
      await memoryService.ensureLtmUser(
        uid,
        (req as any).user?.email,
        (req as any).user?.fullName ?? (req as any).user?.name
      );
      // Free-tier project cap (docs/20260727_TIER_MODEL_DECISION.md). Off unless
      // TIER_ENFORCEMENT=on. Counts OWNED active projects only.
      if (tierEnforcementEnabled() && canonicalTier((req as any).user?.subscriptionTier) === "free") {
        const owned = await pool.query(
          `SELECT count(*)::int AS n FROM projects WHERE user_id::text = $1 AND status = 'active'`,
          [uid]
        );
        if ((owned.rows[0]?.n ?? 0) >= FREE_PROJECT_LIMIT) {
          return res.status(402).json({
            error: "PROJECT_LIMIT_REACHED",
            message: `Free plan is limited to ${FREE_PROJECT_LIMIT} active projects. Upgrade to Premium for unlimited.`,
            limit: FREE_PROJECT_LIMIT,
            upgrade: "premium",
          });
        }
      }
      const project = await memoryService.projects.createProject({
        userId: uid,
        name: name.trim(),
        description: description ?? null,
        researchGoal: researchGoal ?? null,
        primaryDomain: primaryDomain ?? null,
        organisms: Array.isArray(organisms) ? organisms : undefined,
        dataModalities: Array.isArray(dataModalities) ? dataModalities : undefined,
        status: "active",
      } as any);
      res.status(201).json({ project });
    } catch (e: any) {
      console.error("[projects] create failed:", e?.message ?? e);
      res.status(500).json({ error: "Failed to create project" });
    }
  });

  // ─── GET /api/projects/:id ────────────────────────────────────────────
  // Fetch a single project the user owns or is a member of. 404 if not found
  // or not accessible (we never leak existence of another user's project).
  app.get("/api/projects/:id", authenticateToken, async (req: Request, res: Response) => {
    const uid = userId(req);
    if (!uid) return res.status(401).json({ error: "Unauthorized" });
    const id = req.params.id;
    try {
      const project = await memoryService.projects.getProject(id);
      if (!project) return res.status(404).json({ error: "Project not found" });
      let role: 'owner' | 'editor' | 'viewer';
      if (project.userId === uid) {
        role = 'owner';
      } else {
        const memberCheck = await pool.query(
          `SELECT role FROM project_members WHERE project_id = $1 AND user_id::text = $2`,
          [id, uid]
        );
        if (!memberCheck.rows.length) return res.status(404).json({ error: "Project not found" });
        role = memberCheck.rows[0].role === 'editor' ? 'editor' : 'viewer';
      }
      const context = await memoryService.projects.loadProjectContext(id);
      const isOwner = role === 'owner';
      // role + canEdit let the client gate edit controls (viewer = read-only).
      res.json({ project, context, isOwner, role, canEdit: isOwner || role === 'editor' });
    } catch (e: any) {
      console.error("[projects] get failed:", e?.message ?? e);
      res.status(500).json({ error: "Failed to fetch project" });
    }
  });

  // ─── PATCH /api/projects/:id ──────────────────────────────────────────
  // Update mutable fields. Ownership-checked before any write.
  app.patch("/api/projects/:id", authenticateToken, async (req: Request, res: Response) => {
    const uid = userId(req);
    if (!uid) return res.status(401).json({ error: "Unauthorized" });
    const id = req.params.id;
    const { name, description, researchGoal, primaryDomain, organisms, dataModalities, status } = req.body ?? {};
    try {
      const existing = await memoryService.projects.getProject(id);
      if (!existing) return res.status(404).json({ error: "Project not found" });
      // Owner OR editor may edit content; non-members get 404 (no enumeration).
      const role = await _getUserRole(id, uid);
      if (role !== "owner" && role !== "editor") {
        return res.status(404).json({ error: "Project not found" });
      }
      // Lifecycle (status → active/archived/completed) stays owner-only.
      if (status !== undefined && role !== "owner") {
        return res.status(403).json({ error: "Only the project owner can change project status" });
      }
      if (status && !["active", "archived", "completed"].includes(status)) {
        return res.status(400).json({ error: "invalid status" });
      }
      const updates: any = {};
      if (typeof name === "string" && name.trim()) updates.name = name.trim();
      if (description !== undefined) updates.description = description;
      if (researchGoal !== undefined) updates.researchGoal = researchGoal;
      if (primaryDomain !== undefined) updates.primaryDomain = primaryDomain;
      if (Array.isArray(organisms)) updates.organisms = organisms;
      if (Array.isArray(dataModalities)) updates.dataModalities = dataModalities;
      if (status) updates.status = status;
      if (status === "archived" && !existing.archivedAt) updates.archivedAt = new Date();
      const project = await memoryService.projects.updateProject(id, updates);
      res.json({ project });
    } catch (e: any) {
      console.error("[projects] update failed:", e?.message ?? e);
      res.status(500).json({ error: "Failed to update project" });
    }
  });

  // ─── POST /api/projects/:id/archive ───────────────────────────────────
  // Soft-delete shortcut. Equivalent to PATCH with status='archived'.
  app.post("/api/projects/:id/archive", authenticateToken, async (req: Request, res: Response) => {
    const uid = userId(req);
    if (!uid) return res.status(401).json({ error: "Unauthorized" });
    const id = req.params.id;
    try {
      const existing = await memoryService.projects.getProject(id);
      if (!existing || existing.userId !== uid) {
        return res.status(404).json({ error: "Project not found" });
      }
      const project = await memoryService.projects.archiveProject(id);
      res.json({ project });
    } catch (e: any) {
      console.error("[projects] archive failed:", e?.message ?? e);
      res.status(500).json({ error: "Failed to archive project" });
    }
  });

  // ─── DELETE /api/projects/:id ─────────────────────────────────────────
  // Hard-delete. CASCADEs to episodes/procedures/knowledge.
  // chat_sessions.project_id → NULL (ON DELETE SET NULL).
  app.delete("/api/projects/:id", authenticateToken, async (req: Request, res: Response) => {
    const uid = userId(req);
    if (!uid) return res.status(401).json({ error: "Unauthorized" });
    const id = req.params.id;
    try {
      const existing = await memoryService.projects.getProject(id);
      if (!existing || existing.userId !== uid) {
        return res.status(404).json({ error: "Project not found" });
      }
      const ok = await memoryService.projects.deleteProject(id);
      res.json({ ok });
    } catch (e: any) {
      console.error("[projects] delete failed:", e?.message ?? e);
      res.status(500).json({ error: "Failed to delete project" });
    }
  });

  // ─── GET /api/projects/:id/files ──────────────────────────────────────
  // List all files for a project (from DB metadata + optional S3 live scan for outputs).
  app.get("/api/projects/:id/files", authenticateToken, _projectFileIds, async (req: Request, res: Response) => {
    const uid = userId(req);
    if (!uid) return res.status(401).json({ error: "Unauthorized" });
    const id = req.params.id;
    try {
      const allowed = await _isOwnerOrMember(id, uid);
      if (!allowed) {
        return res.status(404).json({ error: "Project not found" });
      }
      const result = await pool.query(
        `SELECT ${_FILE_COLUMNS} FROM project_files WHERE project_id = $1 ORDER BY created_at DESC`,
        [id]
      );
      // profileSummary: the profiler's stored verdict for each file's CURRENT version (or null).
      // s3_uri: derived from s3_key + S3_BUCKET_NAME so clients can attach without re-deriving.
      res.json({ files: await withProfileSummaries(_q, result.rows.map((r: any) => _withS3Uri(r))) });
    } catch (e: any) {
      console.error("[project_files] list failed:", e?.message ?? e);
      res.status(500).json({ error: "Failed to list files" });
    }
  });

  // ─── POST /api/projects/:id/files/compatibility ───────────────────────
  // Validate that 2+ project files can be compared (same schema). Reads each
  // file's header from S3 (owner/member scoped, exact-id) and returns
  // compatibility plus a suggested typed column mapping when names differ —
  // "comparisons validate compatibility and request a typed mapping only when
  // needed". No compute is launched.
  app.post("/api/projects/:id/files/compatibility", authenticateToken, _projectFileIds, async (req: Request, res: Response) => {
    const uid = userId(req);
    if (!uid) return res.status(401).json({ error: "Unauthorized" });
    const id = req.params.id;
    const rawIds = Array.isArray(req.body?.fileIds) ? req.body.fileIds : [];
    const uniqueIds = Array.from(new Set(
      rawIds.filter((x: any) => typeof x === "string" && x.trim()).map((x: string) => x.trim()),
    )) as string[];
    if (uniqueIds.length < 2) {
      return res.status(400).json({
        error: "at_least_two_files_required",
        message: "Provide at least two distinct project file ids to compare.",
      });
    }
    try {
      if (!(await _isOwnerOrMember(id, uid))) {
        return res.status(404).json({ error: "Project not found" });
      }
      const rows = await pool.query(
        `SELECT id, name, s3_key FROM project_files WHERE project_id = $1 AND id = ANY($2::uuid[])`,
        [id, uniqueIds],
      );
      const byId = new Map(rows.rows.map((r: any) => [String(r.id), r]));
      const missing = uniqueIds.filter((fid) => !byId.has(fid));
      if (missing.length) {
        return res.status(404).json({
          error: "file_not_found",
          message: "One or more files were not found in this project.",
          missing,
        });
      }
      const bucket = process.env.S3_BUCKET_NAME || "";
      const schemas = [];
      for (const fid of uniqueIds) {
        const row = byId.get(fid)!;
        const format = formatFromName(row.name);
        let columns: string[] = [];
        if (bucket && isTabularFormat(format)) {
          try {
            columns = parseHeaderColumns(await _readS3Header(bucket, row.s3_key), format);
          } catch (e: any) {
            console.warn(`[compatibility] header read failed for ${row.s3_key}: ${e?.message}`);
          }
        }
        schemas.push({ id: fid, name: row.name, format, columns });
      }
      const result = checkTabularCompatibility(schemas);
      res.json({
        ...result,
        files: schemas.map((s) => ({ id: s.id, name: s.name, format: s.format, columns: s.columns })),
      });
    } catch (e: any) {
      console.error("[project_files] compatibility check failed:", e?.message ?? e);
      res.status(500).json({ error: "Failed to check compatibility" });
    }
  });

  // ─── GET /api/data/search ─────────────────────────────────────────────
  // Unified dataset catalog: search ALL of a user's datasets across every
  // project (uploads + run outputs), so the assistant can discover the
  // client's OWN data — not just external literature (RFC unified data plane).
  // Scoped strictly to the caller (user_id::text = $1). Tokenized ILIKE match over
  // filename, workflow, step, source, and captured input context.
  app.get("/api/data/search", authenticateToken, async (req: Request, res: Response) => {
    const uid = userId(req);
    if (!uid) return res.status(401).json({ error: "Unauthorized" });
    const q = (req.query.q ?? "").toString().trim();
    const type = (req.query.type ?? "").toString().trim();
    const source = (req.query.source ?? "").toString().trim();
    let limit = parseInt((req.query.limit ?? "25").toString(), 10);
    if (!Number.isFinite(limit) || limit < 1) limit = 25;
    if (limit > 100) limit = 100;
    try {
      const params: any[] = [uid];
      const clauses: string[] = ["user_id::text = $1"];
      // Tokenize the query — every token must match somewhere (AND of ORs),
      // so "rnaseq counts" finds files matching both terms, not the literal phrase.
      const tokens = q.split(/\s+/).filter(Boolean).slice(0, 6);
      for (const tok of tokens) {
        params.push(`%${tok}%`);
        const i = params.length;
        clauses.push(
          `(name ILIKE $${i} OR COALESCE(workflow_name,'') ILIKE $${i} OR ` +
          `COALESCE(step_name,'') ILIKE $${i} OR source ILIKE $${i} OR ` +
          `COALESCE(input_context::text,'') ILIKE $${i})`
        );
      }
      if (type) { params.push(`%${type}%`); clauses.push(`content_type ILIKE $${params.length}`); }
      if (source) { params.push(source); clauses.push(`source = $${params.length}`); }
      params.push(limit);
      const sql =
        `SELECT id, project_id, name, s3_key, size, content_type, source, run_id, ` +
        `workflow_name, step_name, created_at FROM project_files ` +
        `WHERE ${clauses.join(" AND ")} ORDER BY created_at DESC LIMIT $${params.length}`;
      const result = await pool.query(sql, params);
      // Enrich with project names (bounded: dedupe project_ids, best-effort lookup).
      const names: Record<string, string> = {};
      const uniqueProjects = Array.from(new Set(result.rows.map((r: any) => r.project_id))).slice(0, 25);
      await Promise.all(uniqueProjects.map(async (pid: any) => {
        try {
          const p = await memoryService.projects.getProject(String(pid));
          if (p?.name) names[String(pid)] = p.name;
        } catch { /* best-effort */ }
      }));
      const files = result.rows.map((r: any) => ({ ...r, project_name: names[String(r.project_id)] ?? null }));
      res.json({ query: q, total: files.length, files });
    } catch (e: any) {
      console.error("[data_search] failed:", e?.message ?? e);
      res.status(500).json({ error: "Failed to search datasets" });
    }
  });

  // ─── GET /api/projects/:id/sessions ──────────────────────────────────
  // List chat sessions linked to a project, newest first (max 50).
  app.get("/api/projects/:id/sessions", authenticateToken, async (req: Request, res: Response) => {
    const uid = userId(req);
    if (!uid) return res.status(401).json({ error: "Unauthorized" });
    const id = req.params.id;
    try {
      const allowed = await _isOwnerOrMember(id, uid);
      if (!allowed) {
        return res.status(404).json({ error: "Project not found" });
      }
      const result = await pool.query(
        `SELECT session_id, title, status, created_at, last_activity,
                jsonb_array_length(messages) AS message_count
         FROM chat_sessions
         WHERE project_id = $1 AND user_id::text = $2
         ORDER BY last_activity DESC LIMIT 50`,
        [id, uid]
      );
      res.json({ sessions: result.rows });
    } catch (e: any) {
      console.error("[project_sessions] list failed:", e?.message ?? e);
      res.status(500).json({ error: "Failed to list project sessions" });
    }
  });

  // ─── POST /api/projects/:id/files/upload ──────────────────────────────
  // Multipart upload: saves to S3 under projects/<projectId>/inputs/<relative path>,
  // then records metadata in project_files. A folder upload sends one request per
  // file with a `relativePath` field (before the file part); the stored name keeps
  // the folders ("run1/fastq/S1.fastq.gz") — see project-file-paths.ts.
  app.post(
    "/api/projects/:id/files/upload",
    authenticateToken,
    _projectFileIds,
    projectUpload.single("file"),
    async (req: Request, res: Response) => {
      const uid = userId(req);
      if (!uid) return res.status(401).json({ error: "Unauthorized" });
      const id = req.params.id;
      if (!req.file) return res.status(400).json({ error: "No file uploaded" });
      try {
        const existing = await memoryService.projects.getProject(id);
        // Owner OR editor may upload; viewers/non-members get 404.
        if (!existing || !(await _isOwnerOrEditor(id, uid))) {
          fs.unlink(req.file.path, () => {});
          return res.status(404).json({ error: "Project not found" });
        }
        // Folder uploads send the browser's folder-relative path (webkitRelativePath) as a
        // UTF-8 text field; it is the stored name, so the tree can rebuild the folders.
        const relativePath = typeof req.body?.relativePath === "string" ? req.body.relativePath : null;
        const { name: originalName, keyPath } = projectInputPath(
          decodeMultipartFilename(req.file.originalname || req.file.filename),
          relativePath,
        );
        const key = `projects/${id}/inputs/${keyPath}`;
        const buf = fs.readFileSync(req.file.path);
        fs.unlink(req.file.path, () => {});
        // Content-hash dedup (§4.5.1), same-name versioning and the name rule are decided under
        // the project lock by _storeProjectInput: 201 new, 200 versioned / deduplicated, 409 clash.
        const contentHash = createHash("sha256").update(buf).digest("hex");
        const ctype = uploadContentType(originalName, req.file.mimetype);
        const stored = await _storeProjectInput({ id, uid, name: originalName, key, buf, contentType: ctype, contentHash, source: "upload" });
        res.status(stored.status).json(_storeResponse(stored));
      } catch (e: any) {
        if (req.file?.path) fs.unlink(req.file.path, () => {});
        console.error("[project_files] upload failed:", e?.message ?? e);
        res.status(500).json({ error: "Upload failed" });
      }
    }
  );

  // ─── POST /api/projects/:id/files/import-url ──────────────────────────
  // Paste-a-URL ingest (design spec 04 §4.6): fetch a remote file into the
  // project's S3 prefix and record it in project_files (source='url'), so it
  // appears in the hub tree exactly like an upload — unlike the Galaxy-session
  // /api/datasets/import-url, which never reaches the project. Size-capped
  // (512 MiB); larger files should use upload or a storage connector (a
  // streaming multipart import is a documented follow-up). SSRF-safe via
  // validateRemoteFileUrl (blocks credentials, private hosts, bad protocols).
  app.post("/api/projects/:id/files/import-url", authenticateToken, _projectFileIds, async (req: Request, res: Response) => {
    const uid = userId(req);
    if (!uid) return res.status(401).json({ error: "Unauthorized" });
    const id = req.params.id;
    const validated = validateRemoteFileUrl(req.body?.url);
    if (!validated.ok) return res.status(400).json({ error: validated.error });
    const proto = validated.url.protocol;
    if (proto !== "http:" && proto !== "https:") {
      return res.status(400).json({ error: "Only HTTP(S) URLs can be imported into a project. Use a storage connector for S3/FTP sources." });
    }
    try {
      const existing = await memoryService.projects.getProject(id);
      if (!existing || !(await _isOwnerOrEditor(id, uid))) {
        return res.status(404).json({ error: "Project not found" });
      }
      const CAP = 512 * 1024 * 1024; // 512 MiB
      const resp = await fetch(validated.url.toString(), { signal: AbortSignal.timeout(120_000), redirect: "follow" });
      if (!resp.ok || !resp.body) return res.status(502).json({ error: `Could not fetch the URL (HTTP ${resp.status}).` });
      const declaredLen = Number(resp.headers.get("content-length") || 0);
      if (declaredLen && declaredLen > CAP) {
        return res.status(413).json({ error: "File exceeds the 512 MiB URL-import limit. Upload it directly or connect a storage source." });
      }
      // Stream with a hard byte cap so a mis-declared Content-Length can't OOM us.
      const reader = (resp.body as any).getReader();
      const chunks: Buffer[] = [];
      let total = 0;
      for (;;) {
        const { done, value } = await reader.read();
        if (done) break;
        total += value.length;
        if (total > CAP) {
          try { await reader.cancel(); } catch { /* ignore */ }
          return res.status(413).json({ error: "File exceeds the 512 MiB URL-import limit. Upload it directly or connect a storage source." });
        }
        chunks.push(Buffer.from(value));
      }
      const buf = Buffer.concat(chunks);
      const contentHash = createHash("sha256").update(buf).digest("hex");
      // Same name/key rules as a browser upload: the original name is kept for display
      // and the S3 key is collision-safe (a lossy basename let "数据.csv" and "样本.csv"
      // share one object), and the same name with new bytes becomes a new version
      // instead of overwriting bytes a completed run used.
      const rawName = String(req.body?.filename || validated.filename || "download");
      const { name: filename, keyPath } = projectInputPath(rawName);
      const key = `projects/${id}/inputs/${keyPath}`;
      const contentType = (resp.headers.get("content-type") || "").split(";")[0].trim() || "application/octet-stream";
      const stored = await _storeProjectInput({ id, uid, name: filename, key, buf, contentType, contentHash, source: "url" });
      res.status(stored.status).json(_storeResponse(stored));
    } catch (e: any) {
      const msg = e?.name === "TimeoutError" ? "The URL took too long to fetch (120s limit)." : (e?.message ?? "Import failed");
      console.error("[project_files] url import failed:", msg);
      res.status(500).json({ error: msg });
    }
  });

  // ─── GET /api/projects/:id/files/:fileId/versions ─────────────────────
  // App-level version history (design §4.4): the current project_files row + the
  // archived project_file_versions, newest first. Each is a real byte-version at
  // its own S3 key (no bucket versioning). The dataset object renders these for a
  // project file in place of the Galaxy note-log.
  // Each entry: {version, label, current, size, createdAt, authorName?, author, authorId, note} —
  // createdAt and the author are when / by whom THAT version was written (not when it was
  // superseded); authorName is the display name (full name, else email), omitted when unknown
  // (author is then null), authorId the user id.
  app.get("/api/projects/:id/files/:fileId/versions", authenticateToken, _projectFileIds, async (req: Request, res: Response) => {
    const uid = userId(req);
    if (!uid) return res.status(401).json({ error: "Unauthorized" });
    const { id, fileId } = req.params;
    try {
      if (!(await _isOwnerOrMember(id, uid))) return res.status(404).json({ error: "Project not found" });
      const cur = await pool.query(
        `SELECT ${_ROW_COLUMNS} FROM project_files WHERE id::text = $1 AND project_id::text = $2`,
        [fileId, id]
      );
      if (!cur.rows[0]) return res.status(404).json({ error: "File not found" });
      const past = await pool.query(
        `SELECT version_no, size, note, author, created_at, version_created_at, version_author
         FROM project_file_versions WHERE file_id::text = $1 ORDER BY version_no DESC, created_at ASC`,
        [fileId]
      );
      const current = cur.rows[0];
      const rows = past.rows as any[];
      // The archive event of version k-1 (its created_at/author) is when/by whom version k was
      // written: the origin of rows archived before version_created_at/version_author existed.
      const archiveOf = new Map<number, any>();
      for (const r of rows) if (!archiveOf.has(Number(r.version_no))) archiveOf.set(Number(r.version_no), r);
      const originOf = (k: number, explicitAt: any, explicitBy: any): { at: any; by: string | null } => {
        if (explicitAt) return { at: explicitAt, by: explicitBy ?? null };
        const prev = k > 1 ? archiveOf.get(k - 1) : undefined;
        if (prev) return { at: prev.created_at, by: prev.author ?? null };
        return { at: current.created_at, by: current.user_id ?? null };
      };
      const entries = [
        { k: Number(current.version_no), current: true, size: current.size, note: null,
          ...originOf(Number(current.version_no), current.version_created_at, current.version_author) },
        ...[...archiveOf.values()].map((r) => ({
          k: Number(r.version_no), current: false, size: r.size, note: r.note ?? null,
          ...originOf(Number(r.version_no), r.version_created_at, r.version_author),
        })),
      ];
      const ids = [...new Set(entries.map((e) => e.by).filter((x): x is string => Boolean(x)))];
      const names = new Map<string, string>();
      if (ids.length) {
        const users = await pool.query(
          `SELECT id::text AS id, full_name, email FROM users WHERE id::text = ANY($1::text[])`,
          [ids]
        );
        for (const u of users.rows) {
          const display = String(u.full_name || "").trim() || String(u.email || "").trim();
          if (display) names.set(String(u.id), display);
        }
      }
      const versions = entries.map((e) => ({
        version: String(e.k), label: `v${e.k}`, current: e.current,
        size: Number(e.size), createdAt: e.at, note: e.note,
        // authorName only when the user is known (never an id in its place); author = same, or null.
        ...(e.by && names.has(e.by) ? { authorName: names.get(e.by) } : {}),
        author: e.by ? (names.get(e.by) ?? null) : null, authorId: e.by,
      }));
      res.json({ versions });
    } catch (e: any) {
      console.error("[project_files] versions failed:", e?.message ?? e);
      res.status(500).json({ error: "Failed to list versions" });
    }
  });

  /** Body `baseVersion`: the file version_no the client last saw. Edits require it (400 when
   *  missing); restore honours it when sent. */
  const parseBaseVersion = (raw: unknown): number | null => {
    const n = typeof raw === "string" && /^\d+$/.test(raw) ? Number(raw) : raw;
    return typeof n === "number" && Number.isInteger(n) && n >= 1 ? n : null;
  };
  const versionConflict = (currentVersion: number) => ({
    error: "version_conflict",
    message: "The file has a newer version than the one you edited; nothing was saved. Reload and edit again.",
    currentVersion,
  });

  // ─── POST /api/projects/:id/files/:fileId/versions/:versionNo/restore ──
  // Append-only restore (design §4.4 — "restoring writes a new version; history
  // never rewinds"). Archives the current content as a version, then points the
  // file at the chosen version's (retained) bytes as a new current version. Runs under the
  // project lock; body {baseVersion} (optional): 409 version_conflict when the file moved on.
  app.post("/api/projects/:id/files/:fileId/versions/:versionNo/restore", authenticateToken, _projectFileIds, async (req: Request, res: Response) => {
    const uid = userId(req);
    if (!uid) return res.status(401).json({ error: "Unauthorized" });
    const { id, fileId, versionNo } = req.params;
    const target = Number(versionNo);
    if (!Number.isInteger(target) || target < 1) return res.status(404).json({ error: "Version not found" });
    const baseRaw = req.body?.baseVersion;
    const base = baseRaw === undefined || baseRaw === null ? null : parseBaseVersion(baseRaw);
    if (baseRaw !== undefined && baseRaw !== null && base === null) {
      return res.status(400).json({ error: "baseVersion must be a positive integer (the file version you saw)." });
    }
    try {
      if (!(await _isOwnerOrEditor(id, uid))) return res.status(404).json({ error: "Project not found" });
      const out = await _withProjectLock(id, async (c) => {
        const cur = await c.query(
          `SELECT ${_ROW_COLUMNS} FROM project_files WHERE id::text = $1 AND project_id::text = $2 FOR UPDATE`,
          [fileId, id]
        );
        const f = cur.rows[0];
        if (!f) return { status: 404, body: { error: "File not found" } };
        if (base !== null && Number(f.version_no) !== base) return { status: 409, body: versionConflict(Number(f.version_no)) };
        const t = await c.query(
          `SELECT s3_key, size, content_type, content_hash FROM project_file_versions
           WHERE file_id::text = $1 AND version_no = $2 ORDER BY created_at ASC LIMIT 1`,
          [fileId, target]
        );
        if (!t.rows[0]) return { status: 404, body: { error: "Version not found" } };
        await _archiveCurrentAsVersion(c, f, id, uid);
        const v = t.rows[0];
        const upd = await c.query(
          `UPDATE project_files SET s3_key = $1, size = $2, content_type = $3, content_hash = $4,
             version_no = version_no + 1, version_created_at = now(), version_author = $5
           WHERE id::text = $6 AND version_no = $7
           RETURNING ${_FILE_COLUMNS}`,
          [v.s3_key, v.size, v.content_type, v.content_hash, uid, fileId, Number(f.version_no)]
        );
        if (!upd.rows[0]) throw new Error("restore: version precondition failed under the project lock");
        return { status: 200, body: { file: upd.rows[0], restoredFrom: target } };
      });
      // The restored row in the files-list shape: its new current s3_key (the ref to profile) and
      // the profile summary that version already has, if any.
      if (out.status === 200) (out.body as any).file = (await withProfileSummaries(_q, [(out.body as any).file]))[0];
      if (out.status === 200) {
        await recordProjectActivity(id, uid, "file_restored", { fileId, restoredFrom: target, newVersion: (out.body as any).file.version_no });
      }
      res.status(out.status).json(out.body);
    } catch (e: any) {
      console.error("[project_files] restore failed:", e?.message ?? e);
      res.status(500).json({ error: "Restore failed" });
    }
  });

  // ─── GET /api/projects/:id/files/:fileId/versions/:versionNo/diff ─────
  // Compare a past version against the CURRENT one (design §4.4 — "cell-level and
  // column-level diff against the current version, side by side"). Reads both
  // versions' bytes (readTextPrefix, capped), parses tabular, and returns the
  // column set diff + position-aligned changed cells (capped). Non-tabular files
  // report a metadata-only diff (size/hash differ) honestly. changedCells[].row is the 0-based
  // data-row index, rowNumber the 1-based number shown to users (first row after the header = 1).
  //
  // Rows are numbered with the ROWS READER's layout of each version (header records, leading
  // comment/blank lines, delimiter — one 1-row /api/perception/rows call per version), so a
  // rowNumber is the row the user sees in the Preview and edits (a featureCounts file's
  // "# Program:" line, a blank first line, a header-less table, a semicolon CSV). The layout is
  // asked for, not stored: it is a function of the bytes and the reader, so a stored copy could
  // only go stale (reader fixes, rows written before the column existed). A failed read or
  // layout call is an explicit 502 — never an empty text that would diff as "no changes".
  app.get("/api/projects/:id/files/:fileId/versions/:versionNo/diff", authenticateToken, _projectFileIds, async (req: Request, res: Response) => {
    const uid = userId(req);
    if (!uid) return res.status(401).json({ error: "Unauthorized" });
    const { id, fileId, versionNo } = req.params;
    try {
      if (!(await _isOwnerOrMember(id, uid))) return res.status(404).json({ error: "Project not found" });
      const cur = await pool.query(
        `SELECT name, s3_key, size, content_type, content_hash, version_no, source FROM project_files WHERE id::text = $1 AND project_id::text = $2`,
        [fileId, id]
      );
      if (!cur.rows[0]) return res.status(404).json({ error: "File not found" });
      const tgt = await pool.query(
        `SELECT s3_key, size, content_hash FROM project_file_versions WHERE file_id::text = $1 AND version_no = $2
         ORDER BY created_at ASC LIMIT 1`,
        [fileId, Number(versionNo)]
      );
      if (!tgt.rows[0]) return res.status(404).json({ error: "Version not found" });
      const c = cur.rows[0], t = tgt.rows[0];
      const identical = Boolean(c.content_hash && t.content_hash && c.content_hash === t.content_hash);
      const ext = (String(c.name).split(".").pop() || "").toLowerCase();
      const tabular = ["csv", "tsv", "tab", "txt"].includes(ext);
      const base = {
        current: { version: c.version_no, size: Number(c.size) },
        target: { version: Number(versionNo), size: Number(t.size) },
        identical,
        tabular,
      };
      if (identical || !tabular) return res.json(base);
      const CAP = 256 * 1024;
      const folderContext = await loadFolderContext((q, p) => pool.query(q, p), id, c);
      let curText: string, tgtText: string, curLay: ReaderLayout, tgtLay: ReaderLayout;
      try {
        [curText, tgtText, curLay, tgtLay] = await Promise.all([
          s3Service.readTextPrefix(c.s3_key, CAP),
          s3Service.readTextPrefix(t.s3_key, CAP),
          _readerLayout(req, c.s3_key, String(c.name), folderContext),
          _readerLayout(req, t.s3_key, String(c.name), folderContext),
        ]);
      } catch (e: any) {
        console.error(`[project_files] diff read failed for file ${fileId} v${versionNo}:`, e?.message ?? e);
        return res.status(502).json({ error: "diff_unavailable", message: "Could not read both versions to compare them." });
      }
      if (!curLay.tabular || !tgtLay.tabular) {
        // Not a table to the reader (e.g. one version is not delimited text): no cell diff.
        return res.json({ ...base, tabular: false, reason: !curLay.tabular ? curLay.reason : (tgtLay as any).reason });
      }
      const A = _layoutRows(curText, ext, curLay, 500);  // current — the rows the user sees
      const B = _layoutRows(tgtText, ext, tgtLay, 500);  // target (older), with ITS layout
      const added = A.headers.filter((h) => !B.headers.includes(h));
      const removed = B.headers.filter((h) => !A.headers.includes(h));
      // changedCells lists at most 100 cells; changedCellCount counts EVERY changed cell in the rows
      // compared (the count to show — never changedCells.length), exact unless the compared window
      // was truncated (changedCellCountExact false: "at least N").
      const CELL_CAP = 100;
      const changedCells: Array<{ row: number; rowNumber: number; col: string; from: string; to: string }> = [];
      let changedCellCount = 0;
      const nRows = Math.min(A.rows.length, B.rows.length);
      const nCols = Math.min(A.headers.length, B.headers.length);
      for (let i = 0; i < nRows; i++) {
        for (let j = 0; j < nCols; j++) {
          const av = A.rows[i]?.[j] ?? "", bv = B.rows[i]?.[j] ?? "";
          if (av === bv) continue;
          changedCellCount++;
          if (changedCells.length < CELL_CAP) changedCells.push({ row: i, rowNumber: i + 1, col: A.headers[j] ?? String(j), from: bv, to: av });
        }
      }
      const truncated = (A.rows.length >= 500 || B.rows.length >= 500);
      res.json({
        ...base,
        columns: { added, removed },
        rowsCompared: nRows,
        changedCells,
        changedCellCount,
        changedCellCountExact: !truncated,
        changedCellsTruncated: changedCellCount > changedCells.length,
        truncated,
      });
    } catch (e: any) {
      console.error("[project_files] diff failed:", e?.message ?? e);
      res.status(500).json({ error: "Diff failed" });
    }
  });

  // ─── POST /api/projects/:id/files/:fileId/edit ────────────────────────
  // Edit-in-place → write a new version (design §4.3/§4.4 — "saving an edit writes
  // a new version; it never overwrites"). The preview is only a SAMPLE, so the
  // client sends cell EDITS {row, col, from, value[, rowFrom]} (row = data-row index as the rows
  // reader numbers them); we apply them to the FULL file server-side and version it. Tabular
  // only, size-capped (10 MiB) — larger files edit in Jupyter/RStudio.
  //
  // Body: {edits, baseVersion, headerRows?, skipLines?, delimiter?}. baseVersion (REQUIRED) is the
  // version_no the client read (rows route `version`); headerRows / skipLines / delimiter are the
  // rows route's `headerRow` / `skipLines` / `delimiter` sent back, so edits are applied with the
  // SAME layout the reader used. Outcomes:
  //   200 {file, versioned, editedCells}  — a new version was written;
  //   400 — malformed body / missing baseVersion;
  //   409 {error:"version_conflict", currentVersion} — the file has moved on (nothing written);
  //   409 {error:"cell_conflict", conflicts}       — a cell no longer holds `from` (nothing written);
  //   413 — over 10 MiB; 422 — the bytes are not valid UTF-8 (rewriting would change them).
  // The version check and the write run under the project lock and the UPDATE carries
  // `version_no = baseVersion`, so two edits of one version can never both land.
  app.post("/api/projects/:id/files/:fileId/edit", authenticateToken, _projectFileIds, async (req: Request, res: Response) => {
    const uid = userId(req);
    if (!uid) return res.status(401).json({ error: "Unauthorized" });
    const { id, fileId } = req.params;
    const edits = Array.isArray(req.body?.edits) ? req.body.edits : null;
    if (!edits || edits.length === 0) return res.status(400).json({ error: "No edits provided" });
    const baseVersion = parseBaseVersion(req.body?.baseVersion);
    if (baseVersion === null) {
      return res.status(400).json({ error: "baseVersion is required: the file version the edits were made on (the rows response `version`)." });
    }
    // Header records before the data rows, as the rows reader reported (headerRow): 1 (default)
    // or 0 for a header-less file. A wrong value is caught by the `from` check below (409).
    const headerRowsRaw = req.body?.headerRows;
    if (headerRowsRaw !== undefined && headerRowsRaw !== 0 && headerRowsRaw !== 1) {
      return res.status(400).json({ error: "headerRows must be 0 or 1." });
    }
    const headerRows: 0 | 1 = headerRowsRaw === 0 ? 0 : 1;
    // Leading comment/blank lines the rows reader skipped (its `skipLines`), so edit row numbers
    // match the rows the user saw on files like featureCounts output.
    const skipLinesRaw = req.body?.skipLines;
    if (skipLinesRaw !== undefined && !(Number.isInteger(skipLinesRaw) && skipLinesRaw >= 0 && skipLinesRaw <= 10_000)) {
      return res.status(400).json({ error: "skipLines must be an integer between 0 and 10000." });
    }
    const skipLines: number = skipLinesRaw ?? 0;
    // The delimiter the rows reader split this file on (rows route `delimiter`): a featureCounts
    // .txt whose first line is a comment is tab-separated, a .csv may be semicolon-separated —
    // guessing from the extension / first line edits the wrong fields. Only the reader's set is
    // accepted; absent (older backend / client) → pickDelimiter.
    const delimiterRaw = req.body?.delimiter;
    if (delimiterRaw !== undefined && !isReaderDelimiter(delimiterRaw)) {
      return res.status(400).json({ error: `delimiter must be one of ${READER_DELIMITERS.map((d) => JSON.stringify(d)).join(", ")}.` });
    }
    // Each edit names the cell by data-row index + column index (as the Preview's rows reader
    // numbers them) and carries the value the user saw (`from`) and optionally the whole row
    // (`rowFrom`), so a mis-numbered edit cannot land on a different row that happens to hold
    // the same value.
    const parsed: CellEdit[] = [];
    for (const e of edits) {
      const r = Number(e?.row), c = Number(e?.col);
      if (!Number.isInteger(r) || r < 0 || !Number.isInteger(c) || c < 0 || typeof e?.from !== "string") {
        return res.status(400).json({ error: "Each edit needs row, col (column index) and from (the value shown)." });
      }
      if (e?.rowFrom !== undefined && !(Array.isArray(e.rowFrom) && e.rowFrom.every((v: unknown) => typeof v === "string"))) {
        return res.status(400).json({ error: "rowFrom must be the row's values as strings." });
      }
      parsed.push({ row: r, col: c, from: e.from, value: String(e?.value ?? ""), ...(e?.rowFrom ? { rowFrom: e.rowFrom } : {}) });
    }
    try {
      if (!(await _isOwnerOrEditor(id, uid))) return res.status(404).json({ error: "Project not found" });
      const row = await pool.query(
        `SELECT ${_ROW_COLUMNS} FROM project_files WHERE id::text = $1 AND project_id::text = $2`,
        [fileId, id]
      );
      if (!row.rows[0]) return res.status(404).json({ error: "File not found" });
      const cur = row.rows[0];
      const ext = (String(cur.name).split(".").pop() || "").toLowerCase();
      if (!["csv", "tsv", "tab", "txt"].includes(ext)) {
        return res.status(400).json({ code: "not_tabular", error: "Only tabular files (csv/tsv) can be edited in place. Open it in Jupyter/RStudio for other formats." });
      }
      // Stale before any read: nothing is read, written or archived.
      if (Number(cur.version_no) !== baseVersion) return res.status(409).json(versionConflict(Number(cur.version_no)));
      const CAP = 10 * 1024 * 1024;
      const size = await s3Service.getFileSize(cur.s3_key);
      if (size > CAP) return res.status(413).json({ code: "too_large", error: "File exceeds the 10 MiB in-place-edit limit. Open it in Jupyter/RStudio to edit larger files." });
      // The WHOLE file (≤ 10 MiB). An object key is never rewritten (new bytes always get a new
      // key), so these are exactly the bytes of baseVersion as long as s3_key is unchanged below.
      const bytes = size > 0 ? await s3Service.readBuffer(cur.s3_key, size) : Buffer.alloc(0);
      if (bytes.length !== size) throw new Error(`edit: read ${bytes.length} of ${size} bytes`);
      // The file is rewritten from decoded text: refuse unless decoding is lossless (strict UTF-8,
      // BOM kept) — otherwise saving would replace every invalid byte with U+FFFD.
      let text: string;
      try {
        text = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(bytes);
      } catch {
        return res.status(422).json({ code: "not_utf8", error: "This file is not plain UTF-8 text, so it cannot be edited in place without changing other bytes. Open it in Jupyter/RStudio to edit it." });
      }
      const delim = delimiterRaw ?? pickDelimiter(text, ext);
      // Only the edited fields are rewritten (quoting, line endings and every other byte kept);
      // if any cell no longer holds the value the user saw, nothing is written (409).
      const result = applyCellEdits(text, delim, parsed, { headerRows, skipLines });
      if (result.conflicts.length) {
        return res.status(409).json({
          error: "cell_conflict",
          message: "A cell no longer holds the value shown; nothing was saved. Reload and edit again.",
          conflicts: result.conflicts.slice(0, 20),
        });
      }
      const applied = result.applied;
      if (applied === 0) return res.status(400).json({ error: "None of the edits matched a cell." });
      const buf = Buffer.from(result.text, "utf-8");
      const contentHash = createHash("sha256").update(buf).digest("hex");
      const out = await _withProjectLock(id, async (c) => {
        const now = await c.query(
          `SELECT ${_ROW_COLUMNS} FROM project_files WHERE id::text = $1 AND project_id::text = $2 FOR UPDATE`,
          [fileId, id]
        );
        const f = now.rows[0];
        if (!f) return { status: 404, body: { error: "File not found" } as any };
        // Another edit / restore / upload landed since the read: nothing is put or archived.
        if (Number(f.version_no) !== baseVersion || f.s3_key !== cur.s3_key) {
          return { status: 409, body: versionConflict(Number(f.version_no)) };
        }
        // Keyed by the CURRENT name (after a rename, new versions live under the new name);
        // never onto a key another file/version/in-flight upload references.
        const vkey = await _allocateObjectKey(c, id, `${projectInputKey(id, String(f.name), String(f.name))}.v${baseVersion + 1}`);
        await s3Service.putObject(vkey, buf, f.content_type, uid);
        try {
          await _archiveCurrentAsVersion(c, { ...f, size }, id, uid);
          const upd = await c.query(
            `UPDATE project_files SET s3_key = $1, size = $2, content_hash = $3,
               version_no = version_no + 1, version_created_at = now(), version_author = $4
             WHERE id::text = $5 AND version_no = $6
             RETURNING ${_FILE_COLUMNS}`,
            [vkey, buf.length, contentHash, uid, fileId, baseVersion]
          );
          if (!upd.rows[0]) throw new Error("edit: version precondition failed under the project lock");
          return { status: 200, body: { file: upd.rows[0], versioned: true, editedCells: applied } };
        } catch (e) {
          await s3Service.deleteFile(vkey).catch(_logCleanupFailure(`delete edit object ${vkey} after a failed version write`));
          throw e;
        }
      });
      if (out.status === 200) {
        // The new version in the files-list shape: its new s3_key is the ref to profile next.
        (out.body as any).file = (await withProfileSummaries(_q, [(out.body as any).file]))[0];
        await recordProjectActivity(id, uid, "file_versioned", { fileId, name: cur.name, version: baseVersion + 1, editedCells: applied });
      }
      res.status(out.status).json(out.body);
    } catch (e: any) {
      console.error("[project_files] edit failed:", e?.message ?? e);
      res.status(500).json({ error: "Edit failed" });
    }
  });

  // ─── PATCH /api/projects/:id/files/:fileId ────────────────────────────
  // Rename and/or move a project file: body {name}; the new name may include folders
  // ("y/b.csv"). Only the stored name changes — the S3 object stays at its key (its storage
  // identity: versions, restore, diff, lineage and completed runs all reference the key or the
  // file id, never the name). New versions after a rename are keyed by the new name
  // (projectInputKey(cur.name)) via _allocateObjectKey. Owner/editor only (404 otherwise);
  // 400 on an invalid name or a run output; 409 when another file/folder already has the name.
  app.patch("/api/projects/:id/files/:fileId", authenticateToken, _projectFileIds, async (req: Request, res: Response) => {
    const uid = userId(req);
    if (!uid) return res.status(401).json({ error: "Unauthorized" });
    const { id, fileId } = req.params;
    try {
      if (!(await _isOwnerOrEditor(id, uid))) return res.status(404).json({ error: "Project not found" });
      const out = await _applyRenamePlan(id, (rows) => planFileRename(rows, fileId, req.body?.name));
      if (!out.ok) return res.status(out.status).json({ error: out.error, ...(out.code ? { code: out.code } : {}), conflicts: out.conflicts });
      const m = out.moves[0];
      if (m) await recordProjectActivity(id, uid, "file_renamed", { fileId: m.id, from: m.from, to: m.to });
      const row = await pool.query(
        `SELECT ${_FILE_COLUMNS} FROM project_files WHERE id::text = $1 AND project_id::text = $2`,
        [fileId, id]
      );
      res.json({ file: row.rows[0] ? (await withProfileSummaries(_q, [row.rows[0]]))[0] : row.rows[0], renamed: Boolean(m) });
    } catch (e: any) {
      console.error("[project_files] rename failed:", e?.message ?? e);
      res.status(500).json({ error: "Rename failed" });
    }
  });

  // ─── POST /api/projects/:id/files/rename-folder ───────────────────────
  // Rename/move a folder: body {from, to} (folder paths as they appear in file names, e.g.
  // "run1/fastq" → "archive/run1"). Every user-managed file under `from/` is renamed in ONE
  // transaction; any clash refuses the whole move (409, nothing changed). Same rules as PATCH.
  app.post("/api/projects/:id/files/rename-folder", authenticateToken, _projectFileIds, async (req: Request, res: Response) => {
    const uid = userId(req);
    if (!uid) return res.status(401).json({ error: "Unauthorized" });
    const { id } = req.params;
    try {
      if (!(await _isOwnerOrEditor(id, uid))) return res.status(404).json({ error: "Project not found" });
      const out = await _applyRenamePlan(id, (rows) => planFolderRename(rows, req.body?.from, req.body?.to));
      if (!out.ok) return res.status(out.status).json({ error: out.error, ...(out.code ? { code: out.code } : {}), conflicts: out.conflicts });
      const ids = out.moves.map((m) => m.id);
      const from = out.from ?? String(req.body.from), to = out.to ?? String(req.body.to);
      await recordProjectActivity(id, uid, "folder_renamed", { from, to, count: ids.length, fileIds: ids.slice(0, 200) });
      const rows = await pool.query(
        `SELECT ${_FILE_COLUMNS} FROM project_files WHERE project_id::text = $1 AND id::text = ANY($2::text[])`,
        [id, ids]
      );
      res.json({ files: await withProfileSummaries(_q, rows.rows), renamed: ids.length });
    } catch (e: any) {
      console.error("[project_files] folder rename failed:", e?.message ?? e);
      res.status(500).json({ error: "Folder rename failed" });
    }
  });

  // ─── DELETE /api/projects/:id/files/:fileId ───────────────────────────
  // Removes the file, ALL its archived versions (rows and their S3 objects) under the project
  // lock. Objects are deleted after the rows commit, and only those no remaining row references
  // (a restore points the current row at an archived version's key; a run output's key may be
  // shared by another registration). A failed object delete leaves an unreferenced object, never
  // a row pointing at missing bytes.
  app.delete("/api/projects/:id/files/:fileId", authenticateToken, _projectFileIds, async (req: Request, res: Response) => {
    const uid = userId(req);
    if (!uid) return res.status(401).json({ error: "Unauthorized" });
    const { id, fileId } = req.params;
    try {
      const existing = await memoryService.projects.getProject(id);
      // Owner OR editor may delete project files; scope by project, not uploader,
      // so collaborators can manage the shared file set (not just their own uploads).
      if (!existing || !(await _isOwnerOrEditor(id, uid))) {
        return res.status(404).json({ error: "Project not found" });
      }
      const out = await _withProjectLock(id, async (c) => {
        const f = await c.query(
          `SELECT s3_key, name FROM project_files WHERE id::text = $1 AND project_id::text = $2`,
          [fileId, id]
        );
        if (!f.rows.length) return null;
        const v = await c.query(
          `DELETE FROM project_file_versions WHERE file_id::text = $1 AND project_id::text = $2 RETURNING s3_key`,
          [fileId, id]
        );
        await c.query(`DELETE FROM project_files WHERE id::text = $1 AND project_id::text = $2`, [fileId, id]);
        const keys = [...new Set<string>([f.rows[0].s3_key, ...v.rows.map((r: any) => r.s3_key)].map(String))];
        const still = await c.query(
          `SELECT s3_key FROM project_files WHERE s3_key = ANY($1::text[])
           UNION SELECT s3_key FROM project_file_versions WHERE s3_key = ANY($1::text[])`,
          [keys]
        );
        const kept = new Set<string>(still.rows.map((r: any) => String(r.s3_key)));
        return { keys: keys.filter((k) => !kept.has(k)), versions: v.rows.length, name: f.rows[0].name };
      });
      if (!out) return res.status(404).json({ error: "File not found" });
      const results = await Promise.all(out.keys.map((k) => s3Service.deleteFile(k)));
      const failed = out.keys.filter((_, i) => !results[i]);
      if (failed.length) console.error(`[project_files] delete ${fileId}: ${failed.length} object(s) not removed:`, failed);
      await recordProjectActivity(id, uid, "file_removed", { fileId });
      res.json({ ok: true, versionsRemoved: out.versions });
    } catch (e: any) {
      console.error("[project_files] delete failed:", e?.message ?? e);
      res.status(500).json({ error: "Failed to delete file" });
    }
  });

  /** A download URL for one stored object, named by the file's DISPLAY name (its basename), never
   *  the S3 key: presigned with Content-Disposition attachment (cloud), or the on-prem proxy with
   *  the name (MinIO). Used by the file URL and the version URL routes. */
  const downloadUrlFor = async (key: string, displayName: string): Promise<string> => {
    const name = downloadName(displayName);
    if (process.env.S3_ENDPOINT_URL) {
      // On-prem (MinIO): presigned URLs embed the internal minio:9000 host the browser cannot reach.
      return `/api/s3/proxy-download?key=${encodeURIComponent(key)}&name=${encodeURIComponent(name)}`;
    }
    return s3Service.generatePresignedDownloadUrl(key, 900, name);
  };

  // ─── GET /api/projects/:id/files/:fileId/url ─────────────────────────
  // A short-lived download URL for a project file: JSON {url, name}, or ?redirect=1 for a plain
  // <a href> download (chat file chips) — same authorization. Both carry Content-Disposition:
  // attachment with the display name, so the browser saves "counts.csv" (not the object key
  // "counts-2.csv.v2") and a text/image file is downloaded instead of opened in the tab.
  app.get("/api/projects/:id/files/:fileId/url", authenticateToken, _projectFileIds, async (req: Request, res: Response) => {
    const uid = userId(req);
    if (!uid) return res.status(401).json({ error: "Unauthorized" });
    const { id, fileId } = req.params;
    try {
      if (!(await _isOwnerOrMember(id, uid))) return res.status(404).json({ error: "Project not found" });
      const fileRow = await pool.query(
        `SELECT s3_key, name FROM project_files WHERE id::text = $1 AND project_id::text = $2`,
        [fileId, id]
      );
      if (!fileRow.rows.length) return res.status(404).json({ error: "File not found" });
      const url = await downloadUrlFor(fileRow.rows[0].s3_key, String(fileRow.rows[0].name));
      if (req.query.redirect === "1") return res.redirect(302, url);
      res.json({ url, name: fileRow.rows[0].name });
    } catch (e: any) {
      console.error("[project_files] url failed:", e?.message ?? e);
      res.status(500).json({ error: "Failed to generate download URL" });
    }
  });

  // ─── GET /api/projects/:id/files/:fileId/versions/:versionNo/url ─────
  // Download an archived version (same contract as /url). Named like the file ("counts.csv") —
  // the version is in the Versions tab, not in a ".vN" suffix the user's tools don't recognise.
  app.get("/api/projects/:id/files/:fileId/versions/:versionNo/url", authenticateToken, _projectFileIds, async (req: Request, res: Response) => {
    const uid = userId(req);
    if (!uid) return res.status(401).json({ error: "Unauthorized" });
    const { id, fileId, versionNo } = req.params;
    const k = Number(versionNo);
    if (!Number.isInteger(k) || k < 1) return res.status(404).json({ error: "Version not found" });
    try {
      if (!(await _isOwnerOrMember(id, uid))) return res.status(404).json({ error: "Project not found" });
      const f = await pool.query(
        `SELECT s3_key, name, version_no FROM project_files WHERE id::text = $1 AND project_id::text = $2`,
        [fileId, id]
      );
      if (!f.rows.length) return res.status(404).json({ error: "File not found" });
      let key: string | null = Number(f.rows[0].version_no) === k ? f.rows[0].s3_key : null;
      if (!key) {
        const v = await pool.query(
          `SELECT s3_key FROM project_file_versions WHERE file_id::text = $1 AND version_no = $2 ORDER BY created_at ASC LIMIT 1`,
          [fileId, k]
        );
        key = v.rows[0]?.s3_key ?? null;
      }
      if (!key) return res.status(404).json({ error: "Version not found" });
      const url = await downloadUrlFor(key, String(f.rows[0].name));
      if (req.query.redirect === "1") return res.redirect(302, url);
      res.json({ url, name: downloadName(String(f.rows[0].name)), version: k });
    } catch (e: any) {
      console.error("[project_files] version url failed:", e?.message ?? e);
      res.status(500).json({ error: "Failed to generate download URL" });
    }
  });

  // ─── GET /api/projects/:id/files/:fileId/rows?offset=&limit= ─────────
  // One page of a table-like project file's FULL rows (csv/tsv/jsonl), for the
  // dataset Preview table. Parsed in the Python backend by the SAME readers the
  // perception profiler uses (data_perception.read_rows), so the table, the stat
  // grid and the QC card describe the same rows (JSONL → one row per record,
  // top-level keys as columns, nested values as compact JSON). Owner/member scoped
  // exactly like /url; the S3 key never leaves the server.
  app.get("/api/projects/:id/files/:fileId/rows", authenticateToken, _projectFileIds, async (req: Request, res: Response) => {
    const uid = userId(req);
    if (!uid) return res.status(401).json({ error: "Unauthorized" });
    const { id, fileId } = req.params;
    const offset = parseInt(String(req.query.offset ?? "0"), 10);
    const limit = parseInt(String(req.query.limit ?? "200"), 10);
    if (!Number.isFinite(offset) || offset < 0 || !Number.isFinite(limit) || limit < 1) {
      return res.status(400).json({ error: "invalid_range" });
    }
    try {
      if (!(await _isOwnerOrMember(id, uid))) return res.status(404).json({ error: "Project not found" });
      const fileRow = await pool.query(
        `SELECT s3_key, name, source, version_no FROM project_files WHERE id::text = $1 AND project_id::text = $2`,
        [fileId, id]
      );
      if (!fileRow.rows.length) return res.status(404).json({ error: "File not found" });
      // Folder facts the rows reader needs (a 10x features.tsv beside its matrix is header-less).
      const folderContext = await loadFolderContext((q, p) => pool.query(q, p), id, fileRow.rows[0]);
      const { status, body } = await _postReaderRows(
        req, fileRow.rows[0].s3_key, fileRow.rows[0].name, offset, Math.min(limit, 1000), folderContext,
      );
      if (!body) {
        console.error(`[project_files] rows backend ${status} for file ${fileId}`);
        return res.status(502).json({ error: "rows_unavailable" });
      }
      if (body.error === "unresolvable_ref") return res.status(404).json({ error: "file_unreadable" });
      if (body.error) return res.status(422).json({ error: "parse_failed" });
      // Not served as rows: say why (empty/blank file, spec mismatch, unreadable, not a table) so the
      // panel can show the right state (an empty file is not a rows error).
      if (body.tabular === false) return res.status(415).json({
        error: "not_tabular", kind: body.kind ?? null,
        ...(typeof body.reason === "string" ? { reason: body.reason } : {}),
        ...(typeof body.code === "string" ? { code: body.code } : {}),
        ...(typeof body.viewKind === "string" ? { viewKind: body.viewKind } : {}),
      });
      res.json({
        // The file version these rows were read from — the client sends it back as the edit's
        // `baseVersion`, so an edit made on a stale page is refused (409) instead of landing on
        // whichever row now has that index.
        version: Number(fileRow.rows[0].version_no),
        kind: body.kind,
        columns: Array.isArray(body.columns) ? body.columns : [],
        rows: Array.isArray(body.rows) ? body.rows : [],
        offset: body.offset ?? offset,
        limit: body.limit ?? limit,
        totalRows: typeof body.totalRows === "number" ? body.totalRows : null,
        // Whether line 1 is a header record (inferred from the content) — the client sends it back
        // as `headerRows` when saving edits so data rows are numbered the same way.
        // Only when the reader reports them (tables); JSONL pages keep their original shape.
        ...(typeof body.headerRow === "boolean" ? { headerRow: body.headerRow } : {}),
        ...(typeof body.namesSource === "string" ? { namesSource: body.namesSource } : {}),
        // The reader's leading comment/blank physical lines: the client sends it back with edits
        // so row numbers match (featureCounts "# Program:" line); and the content-first kind.
        ...(Number.isInteger(body.skipLines) ? { skipLines: body.skipLines } : {}),
        // The delimiter the reader split the table on — sent back with edits so the edit route
        // splits the file the same way (only the reader's delimiter set is forwarded).
        ...(isReaderDelimiter(body.delimiter) ? { delimiter: body.delimiter } : {}),
        ...(typeof body.viewKind === "string" ? { viewKind: body.viewKind } : {}),
      });
    } catch (e: any) {
      console.error("[project_files] rows failed:", e?.message ?? e);
      res.status(502).json({ error: "rows_unavailable" });
    }
  });

  // ─── GET /api/projects/:id/files/:fileId/preview.png?series=&page= ──
  // A TIFF / OME-TIFF drawn as PNG (browsers cannot decode TIFF): one plane, ≤1024 px, rendered
  // by the Python backend (galaxy/ai/tiff_preview.py via POST /api/perception/preview_image).
  // Owner/member scoped like /rows; the object is the project_files row's s3_key — a client names
  // only a file id of a project it may read, never a path or key — and the backend reads it only
  // inside projects/<id>/ (audit S5). `X-Preview-Info` (JSON) says what was drawn.
  app.get("/api/projects/:id/files/:fileId/preview.png", authenticateToken, _projectFileIds, async (req: Request, res: Response) => {
    const uid = userId(req);
    if (!uid) return res.status(401).json({ error: "Unauthorized" });
    const { id, fileId } = req.params;
    const sel = parsePreviewSelection(req.query);
    if (!sel) return res.status(400).json({ error: "invalid_selection" });
    const refuse = (status: number, error: string, reason?: string) => {
      res.removeHeader("ETag");
      res.setHeader("Cache-Control", "private, no-store");
      return res.status(status).json({ error, ...(reason ? { reason } : {}) });
    };
    try {
      if (!(await _isOwnerOrMember(id, uid))) return refuse(404, "Project not found");
      const fileRow = await pool.query(
        `SELECT s3_key, size, content_hash FROM project_files WHERE id::text = $1 AND project_id::text = $2`,
        [fileId, id]
      );
      if (!fileRow.rows.length) return refuse(404, "File not found");
      const { s3_key, size, content_hash } = fileRow.rows[0];
      // The backend reads only objects inside projects/<id>/ (S5); a run output registered under
      // another prefix is said to be not previewable instead of being sent to be refused.
      if (typeof s3_key !== "string" || !s3_key.startsWith(`projects/${id}/`)) {
        return refuse(422, "not_previewable", "this file is stored outside the project's storage");
      }
      if (Number(size) > MAX_PREVIEW_INPUT_BYTES) {
        return refuse(413, "too_large", `previews read files of at most ${MAX_PREVIEW_INPUT_BYTES / 2 ** 20} MiB`);
      }
      // The picture is a function of the bytes (content_hash) and the selection: revalidated every
      // time (a new version keeps the file id), 304 while the bytes are the same.
      const etag = content_hash ? `"tiffprev-${PREVIEW_RENDER_VERSION}-${content_hash}-${sel.series}-${sel.page}"` : null;
      if (etag && String(req.headers["if-none-match"] ?? "").split(/\s*,\s*/).includes(etag)) {
        res.setHeader("ETag", etag);
        res.setHeader("Cache-Control", "private, no-cache");
        return res.status(304).end();
      }
      const { fetchGalaxyAsUser, galaxyBaseUrl } = await _galaxyUserFetch();
      const resp = await fetchGalaxyAsUser(req, `${galaxyBaseUrl()}/api/perception/preview_image`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ projectId: id, datasetRef: s3_key, series: sel.series, page: sel.page }),
        signal: AbortSignal.timeout(120_000),
      });
      if (resp.ok && (resp.headers.get("content-type") || "").startsWith("image/png")) {
        const png = Buffer.from(await resp.arrayBuffer());
        const info = resp.headers.get("x-preview-info");
        res.setHeader("Content-Type", "image/png");
        res.setHeader("X-Content-Type-Options", "nosniff");
        res.setHeader("Cache-Control", etag ? "private, no-cache" : "private, no-store");
        if (etag) res.setHeader("ETag", etag);
        if (info) res.setHeader("X-Preview-Info", info);
        return res.send(png);
      }
      const body: any = await resp.json().catch(() => null);
      // The renderer's refusals (not a TIFF, too large, empty, out-of-range page, renderer not
      // installed) carry a code + reason the panel shows; anything else is a 502.
      if (PREVIEW_PASSTHROUGH.has(resp.status) && body && typeof body.error === "string") {
        return refuse(resp.status, body.error, typeof body.reason === "string" ? body.reason : undefined);
      }
      console.error(`[project_files] preview backend ${resp.status} (${body?.error ?? "?"}) for file ${fileId}`);
      return refuse(502, "preview_unavailable");
    } catch (e: any) {
      console.error("[project_files] preview failed:", e?.message ?? e);
      if (!res.headersSent) refuse(502, "preview_unavailable");
    }
  });

  // ─── GET /api/projects/:id/folders/files?path=<folder> ───────────────────
  // Every input file under a project folder (recursive path prefix), with ids.
  // Used by Analysis "Ask in chat" / Models folder pick so a folder becomes the
  // full file set — not a samplesheet-only stand-in and not one fake file id.
  const MAX_FOLDER_FILES = 10_000;
  app.get("/api/projects/:id/folders/files", authenticateToken, async (req: Request, res: Response) => {
    const uid = userId(req);
    if (!uid) return res.status(401).json({ error: "Unauthorized" });
    const { id } = req.params;
    const folder = normalizeFolderPath(req.query.path);
    if (folder === null) return res.status(400).json({ error: "invalid_path" });
    try {
      if (!(await _isOwnerOrMember(id, uid))) return res.status(404).json({ error: "Project not found" });
      const files = await loadFolderFiles((q, p) => pool.query(q, p), id, folder);
      if (folder && !files.length) return res.status(404).json({ error: "folder_not_found" });
      if (files.length > MAX_FOLDER_FILES) return res.status(413).json({ error: "folder_too_large", max: MAX_FOLDER_FILES });
      return res.json({
        path: folder,
        files: files.map((f) => ({ id: f.id, name: f.name })).filter((f) => typeof f.id === "string" && f.id),
      });
    } catch (e: any) {
      console.error("[project_files] folder files list failed:", e?.message ?? e);
      return res.status(500).json({ error: "Failed to list folder files" });
    }
  });

  // ─── GET /api/projects/:id/folders/profile?path=<folder>[&download=samplesheet] ──
  // What an input folder holds AS A WHOLE: FASTQ pairs / orphans + an nf-core samplesheet
  // (Galaxy's auto_pairing), 10x matrix sets with cells × genes, or a format roll-up.
  // `path` is relative to the inputs root ("" = root; a leading "inputs/" is accepted).
  // Node selects the folder's files (owner/member scoped, like /rows); the Python
  // folder_profile decides what they are (backend galaxy/ai/folder_profile.py). The S3 keys
  // go to the backend only — the response carries project paths, never keys.
  // ?download=samplesheet returns the samplesheet CSV as an attachment.
  app.get("/api/projects/:id/folders/profile", authenticateToken, _projectFileIds, async (req: Request, res: Response) => {
    const uid = userId(req);
    if (!uid) return res.status(401).json({ error: "Unauthorized" });
    const { id } = req.params;
    const folder = normalizeFolderPath(req.query.path);
    if (folder === null) return res.status(400).json({ error: "invalid_path" });
    try {
      if (!(await _isOwnerOrMember(id, uid))) return res.status(404).json({ error: "Project not found" });
      const files = await loadFolderFiles((q, p) => pool.query(q, p), id, folder);
      if (folder && !files.length) return res.status(404).json({ error: "folder_not_found" });
      if (files.length > MAX_FOLDER_FILES) return res.status(413).json({ error: "folder_too_large", max: MAX_FOLDER_FILES });
      const { fetchGalaxyAsUser, galaxyBaseUrl } = await _galaxyUserFetch();
      const resp = await fetchGalaxyAsUser(req, `${galaxyBaseUrl()}/api/perception/folder_profile`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        // projectId: the backend reads only keys inside this project's prefix (audit S5).
        body: JSON.stringify({ projectId: id, path: folder, files: files.map((f) => ({ name: f.name, datasetRef: f.s3_key })) }),
        signal: AbortSignal.timeout(60_000),
      });
      const body: any = await resp.json().catch(() => null);
      if (!resp.ok || !body || typeof body.kind !== "string") {
        console.error(`[project_files] folder profile backend ${resp.status} for ${id}:${folder}`);
        return res.status(502).json({ error: "folder_profile_unavailable" });
      }
      if (req.query.download === "samplesheet") {
        const csv = body.samplesheet?.csv;
        if (typeof csv !== "string") return res.status(404).json({ error: "no_samplesheet" });
        res.setHeader("Content-Type", "text/csv; charset=utf-8");
        res.setHeader("Content-Disposition", `attachment; filename="${samplesheetFilename(folder)}"`);
        return res.send(csv);
      }
      res.json(body);
    } catch (e: any) {
      console.error("[project_files] folder profile failed:", e?.message ?? e);
      res.status(502).json({ error: "folder_profile_unavailable" });
    }
  });

  // ─── POST /api/projects/:id/folders/samplesheet ─────────────────────────
  // Persist the folder profiler’s nf-core samplesheet CSV as ONE project input
  // file (source=upload) and return its file id for Analysis attachFile. Complements
  // Ask-in-chat / folders/files (all files) — does not replace it. Owner/editor only.
  // Body: { path: string, layout?: "paired" | "single_end" }
  app.post("/api/projects/:id/folders/samplesheet", authenticateToken, _projectFileIds, async (req: Request, res: Response) => {
    const uid = userId(req);
    if (!uid) return res.status(401).json({ error: "Unauthorized" });
    const { id } = req.params;
    const folder = normalizeFolderPath(req.body?.path ?? req.query.path);
    if (folder === null) return res.status(400).json({ error: "invalid_path" });
    const layoutRaw = typeof req.body?.layout === "string" ? req.body.layout.trim() : "";
    const layout = layoutRaw === "single_end" ? "single_end" : layoutRaw === "paired" ? "paired" : null;
    try {
      if (!(await _isOwnerOrEditor(id, uid))) return res.status(404).json({ error: "Project not found" });
      const files = await loadFolderFiles((q, p) => pool.query(q, p), id, folder);
      if (folder && !files.length) return res.status(404).json({ error: "folder_not_found" });
      if (files.length > MAX_FOLDER_FILES) return res.status(413).json({ error: "folder_too_large", max: MAX_FOLDER_FILES });
      const { fetchGalaxyAsUser, galaxyBaseUrl } = await _galaxyUserFetch();
      const resp = await fetchGalaxyAsUser(req, `${galaxyBaseUrl()}/api/perception/folder_profile`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ projectId: id, path: folder, files: files.map((f) => ({ name: f.name, datasetRef: f.s3_key })) }),
        signal: AbortSignal.timeout(60_000),
      });
      const body: any = await resp.json().catch(() => null);
      if (!resp.ok || !body || typeof body.kind !== "string") {
        console.error(`[project_files] folder samplesheet persist: profile backend ${resp.status} for ${id}:${folder}`);
        return res.status(502).json({ error: "folder_profile_unavailable" });
      }
      const picked = pickFolderSamplesheetCsv(body.samplesheet, layout);
      if (!picked) return res.status(404).json({ error: "no_samplesheet" });
      const storedName = samplesheetStoredName(folder, picked.filename);
      const { name: originalName, keyPath } = projectInputPath(picked.filename, storedName);
      const key = `projects/${id}/inputs/${keyPath}`;
      const buf = Buffer.from(picked.csv, "utf8");
      const contentHash = createHash("sha256").update(buf).digest("hex");
      const stored = await _storeProjectInput({
        id, uid, name: originalName, key, buf,
        contentType: "text/csv", contentHash, source: "upload",
      });
      return res.status(stored.status).json(_storeResponse(stored));
    } catch (e: any) {
      console.error("[project_files] folder samplesheet persist failed:", e?.message ?? e);
      return res.status(500).json({ error: "Failed to persist samplesheet" });
    }
  });

  // ─── GET /api/projects/:id/members ───────────────────────────────────────
  // List all members of a project (owner can view, invited members can too).
  app.get("/api/projects/:id/members", authenticateToken, async (req: Request, res: Response) => {
    const uid = userId(req);
    if (!uid) return res.status(401).json({ error: "Unauthorized" });
    const id = req.params.id;
    try {
      const allowed = await _isOwnerOrMember(id, uid);
      if (!allowed) return res.status(404).json({ error: "Project not found" });
      // Include owner as first row (synthetic role='owner') so the full team is visible.
      // projects.user_id is UUID; users.id is varchar — cast to text for comparison.
      const result = await pool.query(
        `SELECT u.id AS user_id, 'owner' AS role, p.created_at,
                u.email, u.full_name AS "fullName"
         FROM projects p JOIN users u ON u.id = p.user_id::text
         WHERE p.id = $1
         UNION ALL
         SELECT pm.user_id, pm.role, pm.created_at,
                u.email, u.full_name AS "fullName"
         FROM project_members pm
         JOIN users u ON u.id = pm.user_id
         WHERE pm.project_id = $1
         ORDER BY created_at ASC`,
        [id]
      );
      res.json({ members: result.rows });
    } catch (e: any) {
      console.error("[project_members] list failed:", e?.message ?? e);
      res.status(500).json({ error: "Failed to list members" });
    }
  });

  // ─── POST /api/projects/:id/members ──────────────────────────────────────
  // Invite a user by email. Body: { email, role? }. Only the owner can invite.
  app.post("/api/projects/:id/members", authenticateToken, async (req: Request, res: Response) => {
    const uid = userId(req);
    if (!uid) return res.status(401).json({ error: "Unauthorized" });
    const id = req.params.id;
    const { email, role = "viewer" } = req.body ?? {};
    if (!email || typeof email !== "string") return res.status(400).json({ error: "email is required" });
    if (!["viewer", "editor"].includes(role)) return res.status(400).json({ error: "role must be viewer or editor" });
    if (blockedByCollaborationTier(req, res)) return;
    try {
      const existing = await memoryService.projects.getProject(id);
      if (!existing || existing.userId !== uid) return res.status(404).json({ error: "Project not found" });
      const normEmail = email.toLowerCase().trim();
      const invitee = await pool.query(`SELECT id, email, full_name AS "fullName" FROM users WHERE email = $1`, [normEmail]);
      if (!invitee.rows.length) {
        // New (not-yet-registered) email: mint a PER-INVITE share token that
        // carries THIS invite's role + the target email, and email it. One
        // invite box serves both existing members and new people — no separate
        // "generate link" step, and no 404.
        //
        // PROPER FIX (committee review 2026-11-10 — per-invite tokens): we never
        // reuse or mutate the owner's generic /share-link row (invited_email IS
        // NULL). Each invite gets its own token keyed on invited_email, so
        // inviting A as viewer then B as editor leaves A's token at viewer —
        // the earlier shared-token escalation is gone. If a pending invite to
        // the SAME email already exists we update THAT row's role in place
        // (so re-inviting adjusts the pending role) rather than minting a
        // duplicate; otherwise we insert a fresh per-email token. The
        // /share-link GET/POST/DELETE endpoints are scoped to invited_email IS
        // NULL and never touch these per-invite rows.
        const prior = await pool.query(
          `SELECT token FROM project_share_tokens WHERE project_id = $1 AND invited_email = $2 LIMIT 1`,
          [id, normEmail]
        );
        let token: string;
        if (prior.rows.length) {
          token = prior.rows[0].token;
          await pool.query(
            `UPDATE project_share_tokens SET role = $1, created_by = $2 WHERE project_id = $3 AND invited_email = $4`,
            [role, uid, id, normEmail]
          );
        } else {
          token = randomBytes(18).toString('base64url');
          await pool.query(
            `INSERT INTO project_share_tokens (project_id, token, role, created_by, invited_email) VALUES ($1, $2, $3, $4, $5)`,
            [id, token, role, uid, normEmail]
          );
        }
        const inviter = await pool.query(`SELECT full_name AS "fullName", email FROM users WHERE id::text = $1`, [String(uid)]);
        const inviterName = inviter.rows[0]?.fullName || inviter.rows[0]?.email || "A BioMate user";
        const projectName = (existing as any)?.name || "a project";
        const emailed = await emailService.sendProjectInviteEmail(normEmail, token, projectName, inviterName, role).catch((e: any) => {
          console.warn("[project_members] invite email failed:", e?.message ?? e);
          return false;
        });
        await recordProjectActivity(id, uid, "member_invited", { email: normEmail, role, emailed });
        return res.status(200).json({ invited: true, pending: true, email: normEmail, emailed });
      }
      const inviteeId = invitee.rows[0].id;
      if (inviteeId === uid) return res.status(400).json({ error: "Cannot invite yourself" });
      await pool.query(
        `INSERT INTO project_members (project_id, user_id, role, invited_by)
         VALUES ($1, $2, $3, $4)
         ON CONFLICT (project_id, user_id) DO UPDATE SET role = EXCLUDED.role`,
        [id, inviteeId, role, uid]
      );
      await recordProjectActivity(id, uid, "member_added", { targetUserId: inviteeId, role });
      res.status(201).json({ member: { user_id: inviteeId, ...invitee.rows[0], role } });
    } catch (e: any) {
      console.error("[project_members] invite failed:", e?.message ?? e);
      res.status(500).json({ error: "Failed to invite member" });
    }
  });

  // ─── DELETE /api/projects/:id/members/me ─────────────────────────────────────
  // Leave a project. Any member can remove themselves. Must be registered BEFORE
  // the /:memberId wildcard so "me" isn't swallowed as a memberId.
  app.delete("/api/projects/:id/members/me", authenticateToken, async (req: Request, res: Response) => {
    const uid = userId(req);
    if (!uid) return res.status(401).json({ error: "Unauthorized" });
    const { id } = req.params;
    try {
      const proj = await memoryService.projects.getProject(id);
      if (proj?.userId === uid) return res.status(400).json({ error: "Owner cannot leave — transfer or delete the project" });
      const del = await pool.query(
        `DELETE FROM project_members WHERE project_id = $1 AND user_id::text = $2`,
        [id, uid]
      );
      if ((del.rowCount ?? 0) === 0) return res.status(404).json({ error: "Not a member of this project" });
      await recordProjectActivity(id, uid, "member_removed", { targetUserId: uid, self: true });
      res.json({ ok: true });
    } catch (e: any) {
      console.error("[project_members] leave failed:", e?.message ?? e);
      res.status(500).json({ error: "Failed to leave project" });
    }
  });

  // ─── PATCH /api/projects/:id/members/:memberId ───────────────────────────────
  // Change a member's role. Only the project owner can do this.
  app.patch("/api/projects/:id/members/:memberId", authenticateToken, async (req: Request, res: Response) => {
    const uid = userId(req);
    if (!uid) return res.status(401).json({ error: "Unauthorized" });
    const { id, memberId } = req.params;
    const { role } = req.body ?? {};
    if (!["viewer", "editor"].includes(role)) return res.status(400).json({ error: "role must be viewer or editor" });
    if (blockedByCollaborationTier(req, res)) return;
    try {
      const existing = await memoryService.projects.getProject(id);
      if (!existing || existing.userId !== uid) return res.status(404).json({ error: "Project not found" });
      const upd = await pool.query(
        `UPDATE project_members SET role = $1 WHERE project_id = $2 AND user_id::text = $3`,
        [role, id, memberId]
      );
      if ((upd.rowCount ?? 0) === 0) return res.status(404).json({ error: "Member not found" });
      await recordProjectActivity(id, uid, "role_changed", { targetUserId: memberId, role });
      res.json({ ok: true, role });
    } catch (e: any) {
      console.error("[project_members] role change failed:", e?.message ?? e);
      res.status(500).json({ error: "Failed to update role" });
    }
  });

  // ─── DELETE /api/projects/:id/members/:memberId ───────────────────────────
  // Remove a member. Only the project owner can remove members.
  app.delete("/api/projects/:id/members/:memberId", authenticateToken, async (req: Request, res: Response) => {
    const uid = userId(req);
    if (!uid) return res.status(401).json({ error: "Unauthorized" });
    const { id, memberId } = req.params;
    try {
      const existing = await memoryService.projects.getProject(id);
      if (!existing || existing.userId !== uid) return res.status(404).json({ error: "Project not found" });
      const del = await pool.query(
        `DELETE FROM project_members WHERE project_id = $1 AND user_id::text = $2`,
        [id, memberId]
      );
      if ((del.rowCount ?? 0) === 0) return res.status(404).json({ error: "Member not found" });
      await recordProjectActivity(id, uid, "member_removed", { targetUserId: memberId });
      res.json({ ok: true });
    } catch (e: any) {
      console.error("[project_members] remove failed:", e?.message ?? e);
      res.status(500).json({ error: "Failed to remove member" });
    }
  });

  // ─── PATCH /api/projects/:id/owner ────────────────────────────────────────
  // Transfer ownership (#31 gap). Only the current owner can transfer, and only
  // to a current project member. The old owner is demoted to editor; the new
  // owner is removed from the members list (they are now the owner).
  app.patch("/api/projects/:id/owner", authenticateToken, async (req: Request, res: Response) => {
    const uid = userId(req);
    if (!uid) return res.status(401).json({ error: "Unauthorized" });
    const { id } = req.params;
    const newOwnerId = typeof req.body?.newOwnerId === "string" ? req.body.newOwnerId : "";
    if (!newOwnerId) return res.status(400).json({ error: "newOwnerId is required" });
    if (blockedByCollaborationTier(req, res)) return;
    try {
      const existing = await memoryService.projects.getProject(id);
      if (!existing || existing.userId !== uid) return res.status(404).json({ error: "Project not found" });
      if (newOwnerId === uid) return res.status(400).json({ error: "Already the owner" });
      const m = await pool.query(
        `SELECT 1 FROM project_members WHERE project_id = $1 AND user_id::text = $2`,
        [id, newOwnerId]
      );
      if (!m.rows.length) return res.status(400).json({ error: "New owner must be a current project member" });
      // Transfer: set new owner, demote old owner to editor, drop new owner from members.
      await memoryService.projects.updateProject(id, { userId: newOwnerId } as any);
      await pool.query(`DELETE FROM project_members WHERE project_id = $1 AND user_id::text = $2`, [id, newOwnerId]);
      await pool.query(
        `INSERT INTO project_members (project_id, user_id, role, invited_by) VALUES ($1, $2, 'editor', $3)
         ON CONFLICT (project_id, user_id) DO UPDATE SET role = 'editor'`,
        [id, uid, newOwnerId]
      );
      // Attributed to the outgoing owner (the only actor authorized to transfer).
      await recordProjectActivity(id, uid, "ownership_transferred", { newOwnerId, previousOwnerId: uid });
      res.json({ ok: true, newOwnerId });
    } catch (e: any) {
      console.error("[project_members] ownership transfer failed:", e?.message ?? e);
      res.status(500).json({ error: "Failed to transfer ownership" });
    }
  });

  // ─── GET /api/projects/:id/share-link ────────────────────────────────────────
  // Owner only — returns the existing share token, or { token: null } if none.
  app.get("/api/projects/:id/share-link", authenticateToken, async (req: Request, res: Response) => {
    const uid = userId(req);
    if (!uid) return res.status(401).json({ error: "Unauthorized" });
    const id = req.params.id;
    try {
      const proj = await memoryService.projects.getProject(id);
      if (!proj || proj.userId !== uid) return res.status(404).json({ error: "Project not found" });
      // Scope to the generic share link only (invited_email IS NULL); per-invite
      // tokens are addressed individually and must never surface here.
      const row = await pool.query(
        `SELECT token, role, created_at, expires_at FROM project_share_tokens WHERE project_id = $1 AND invited_email IS NULL LIMIT 1`,
        [id]
      );
      if (!row.rows.length) return res.json({ token: null });
      const { token, role, created_at, expires_at } = row.rows[0];
      res.json({ token, role, createdAt: created_at, expiresAt: expires_at });
    } catch (e: any) {
      console.error("[project_share] get failed:", e?.message ?? e);
      res.status(500).json({ error: "Failed to get share link" });
    }
  });

  // ─── POST /api/projects/:id/share-link ───────────────────────────────────────
  // Owner only — generates a token (idempotent: returns existing if one exists).
  app.post("/api/projects/:id/share-link", authenticateToken, async (req: Request, res: Response) => {
    const uid = userId(req);
    if (!uid) return res.status(401).json({ error: "Unauthorized" });
    const id = req.params.id;
    const { role = "viewer" } = req.body ?? {};
    if (!["viewer", "editor"].includes(role)) return res.status(400).json({ error: "role must be viewer or editor" });
    if (blockedByCollaborationTier(req, res)) return;
    try {
      const proj = await memoryService.projects.getProject(id);
      if (!proj || proj.userId !== uid) return res.status(404).json({ error: "Project not found" });
      // Operate ONLY on the generic link row (invited_email IS NULL). Setting
      // the share-link role must never mutate a pending per-invite token.
      const existing = await pool.query(
        `SELECT token, role FROM project_share_tokens WHERE project_id = $1 AND invited_email IS NULL LIMIT 1`, [id]
      );
      if (existing.rows.length) {
        // Idempotent on the token, but allow CHANGING the role of the existing
        // link without revoke+regenerate (closes the create-time-only gap).
        if (existing.rows[0].role !== role) {
          await pool.query(`UPDATE project_share_tokens SET role = $1 WHERE project_id = $2 AND invited_email IS NULL`, [role, id]);
        }
        return res.json({ token: existing.rows[0].token, role });
      }
      const token = randomBytes(18).toString('base64url'); // 24-char URL-safe token
      // invited_email omitted → NULL → this is the generic link.
      await pool.query(
        `INSERT INTO project_share_tokens (project_id, token, role, created_by) VALUES ($1, $2, $3, $4)`,
        [id, token, role, uid]
      );
      res.status(201).json({ token, role });
    } catch (e: any) {
      console.error("[project_share] create failed:", e?.message ?? e);
      res.status(500).json({ error: "Failed to create share link" });
    }
  });

  // ─── DELETE /api/projects/:id/share-link ─────────────────────────────────────
  // Owner only — revokes the GENERIC share link so that link stops working.
  // Pending per-invite tokens (invited_email IS NOT NULL) are intentionally left
  // intact: revoking the public link must not silently cancel individual invites.
  app.delete("/api/projects/:id/share-link", authenticateToken, async (req: Request, res: Response) => {
    const uid = userId(req);
    if (!uid) return res.status(401).json({ error: "Unauthorized" });
    const id = req.params.id;
    try {
      const proj = await memoryService.projects.getProject(id);
      if (!proj || proj.userId !== uid) return res.status(404).json({ error: "Project not found" });
      await pool.query(`DELETE FROM project_share_tokens WHERE project_id = $1 AND invited_email IS NULL`, [id]);
      res.json({ ok: true });
    } catch (e: any) {
      console.error("[project_share] revoke failed:", e?.message ?? e);
      res.status(500).json({ error: "Failed to revoke share link" });
    }
  });

  // ─── #24 (L2): plan/proposal objects ─────────────────────────────────────────
  // Persist a plan so a run can cite the hypothesis that motivated it (execution
  // .basedOnPlanId), instead of the plan living only in chat metadata.
  app.post("/api/projects/:id/plans", authenticateToken, async (req: Request, res: Response) => {
    try {
      const { id } = req.params;
      const uid = (req as any).user?.id ? String((req as any).user.id) : "";
      if (!(await _isOwnerOrEditor(id, uid))) return res.status(403).json({ error: "Editor or owner role required" });
      const goal = typeof req.body?.goal === "string" ? req.body.goal.trim() : "";
      if (!goal) return res.status(400).json({ error: "goal is required" });
      const hypothesis = typeof req.body?.hypothesis === "string" ? req.body.hypothesis : null;
      const dsIds = Array.isArray(req.body?.referencedDatasetIds) ? req.body.referencedDatasetIds : [];
      const evIds = Array.isArray(req.body?.referencedEvidenceIds) ? req.body.referencedEvidenceIds : [];
      const r = await pool.query(
        `INSERT INTO project_plans (project_id, goal, hypothesis, referenced_dataset_ids, referenced_evidence_ids, created_by)
         VALUES ($1,$2,$3,$4::jsonb,$5::jsonb,$6) RETURNING id, project_id, goal, hypothesis, referenced_dataset_ids, referenced_evidence_ids, created_at`,
        [id, goal, hypothesis, JSON.stringify(dsIds), JSON.stringify(evIds), uid || null]
      );
      await recordProjectActivity(id, uid || null, "plan_created", { planId: r.rows[0].id });
      res.status(201).json({ plan: r.rows[0] });
    } catch (e: any) {
      console.error("[project_plans] create failed:", e?.message ?? e);
      res.status(500).json({ error: "Failed to create plan" });
    }
  });

  // ─── GET /api/projects/:id/plans ──────────────────────────────────────────────
  // List all plans for a project, newest-first. Same ownership/auth contract as
  // the sibling plan endpoints: authenticateToken + _isOwnerOrMember, 404 on
  // cross-user access (never leak existence).
  app.get("/api/projects/:id/plans", authenticateToken, async (req: Request, res: Response) => {
    try {
      const { id } = req.params;
      const uid = (req as any).user?.id ? String((req as any).user.id) : "";
      if (!(await _isOwnerOrMember(id, uid))) return res.status(404).json({ error: "Not found" });
      const r = await pool.query(
        `SELECT id, project_id, goal, hypothesis, referenced_dataset_ids, referenced_evidence_ids, created_at
         FROM project_plans WHERE project_id = $1 ORDER BY created_at DESC`,
        [id]
      );
      res.json({ plans: r.rows });
    } catch (e: any) {
      console.error("[project_plans] list failed:", e?.message ?? e);
      res.status(500).json({ error: "Failed to list plans" });
    }
  });

  app.get("/api/projects/:id/plans/:planId", authenticateToken, async (req: Request, res: Response) => {
    try {
      const { id, planId } = req.params;
      const uid = (req as any).user?.id ? String((req as any).user.id) : "";
      if (!(await _isOwnerOrMember(id, uid))) return res.status(404).json({ error: "Not found" });
      const r = await pool.query(
        `SELECT id, project_id, goal, hypothesis, referenced_dataset_ids, referenced_evidence_ids, created_at
         FROM project_plans WHERE id = $1 AND project_id = $2`,
        [planId, id]
      );
      if (!r.rows.length) return res.status(404).json({ error: "Plan not found" });
      res.json({ plan: r.rows[0] });
    } catch (e: any) {
      console.error("[project_plans] get failed:", e?.message ?? e);
      res.status(500).json({ error: "Failed to fetch plan" });
    }
  });

  // ─── GET /api/projects/:id/activity ────────────────────────────────────────────
  // Immutable project activity ledger (Team workspace Phase 1). Owner-or-member
  // readable, newest-first, paginated (limit ≤ 100, offset). A non-member gets
  // the same 404 no-disclosure response used for every other project resource —
  // outsiders cannot enumerate the feed. Rows are append-only and server-rendered;
  // the handler never accepts a client-supplied event or summary.
  app.get("/api/projects/:id/activity", authenticateToken, async (req: Request, res: Response) => {
    const uid = userId(req);
    if (!uid) return res.status(401).json({ error: "Unauthorized" });
    const id = req.params.id;
    let limit = parseInt(String(req.query.limit ?? "50"), 10);
    if (!Number.isFinite(limit) || limit < 1) limit = 50;
    if (limit > 100) limit = 100;
    let offset = parseInt(String(req.query.offset ?? "0"), 10);
    if (!Number.isFinite(offset) || offset < 0) offset = 0;
    try {
      if (!(await _isOwnerOrMember(id, uid))) return res.status(404).json({ error: "Project not found" });
      // Over-fetch one row to report whether another page exists, without a COUNT.
      const r = await pool.query(
        `SELECT a.id, a.project_id, a.actor_user_id, a.event_type, a.payload, a.created_at,
                u.email AS actor_email, u.full_name AS "actorName"
         FROM project_activity a
         LEFT JOIN users u ON u.id = a.actor_user_id
         WHERE a.project_id = $1
         ORDER BY a.created_at DESC, a.id DESC
         LIMIT $2 OFFSET $3`,
        [id, limit + 1, offset]
      );
      const hasMore = r.rows.length > limit;
      const activity = hasMore ? r.rows.slice(0, limit) : r.rows;
      res.json({ activity, limit, offset, hasMore });
    } catch (e: any) {
      console.error("[project_activity] list failed:", e?.message ?? e);
      res.status(500).json({ error: "Failed to list activity" });
    }
  });

  // ─── Human-only project notes ─────────────────────────────────────────────────
  // "Notes" (spec Tier 2 B) are free text the human keeps — explicitly NOT read
  // by the assistant. They persist as project_knowledge rows with
  // knowledgeType='user_notes' / source='user_provided' (distinct from the
  // LLM-generated 'notes_synthesis' rows in notes-routes.ts). This reuses the
  // existing project-scoped, ownership-cascading table rather than adding a
  // schema. The assistant's directives live in projects.researchGoal
  // ("Standing instructions"); these rows are never injected into prompts.
  const USER_NOTES_TYPE = "user_notes";

  // GET /api/projects/:id/notes-list — list human notes, newest-first.
  app.get("/api/projects/:id/notes-list", authenticateToken, async (req: Request, res: Response) => {
    const uid = userId(req);
    if (!uid) return res.status(401).json({ error: "Unauthorized" });
    const id = req.params.id;
    try {
      if (!(await _isOwnerOrMember(id, uid))) return res.status(404).json({ error: "Project not found" });
      const rows = await memoryService.projects.getProjectKnowledge(id, USER_NOTES_TYPE);
      const notes = [...rows].sort((a, b) => {
        const at = a.createdAt ? new Date(a.createdAt).getTime() : 0;
        const bt = b.createdAt ? new Date(b.createdAt).getTime() : 0;
        return bt - at;
      });
      res.json({ notes });
    } catch (e: any) {
      console.error("[user_notes] list failed:", e?.message ?? e);
      res.status(500).json({ error: "Failed to list notes" });
    }
  });

  // POST /api/projects/:id/notes-list — add a human note. Owner or editor.
  app.post("/api/projects/:id/notes-list", authenticateToken, async (req: Request, res: Response) => {
    const uid = userId(req);
    if (!uid) return res.status(401).json({ error: "Unauthorized" });
    const id = req.params.id;
    const content = typeof req.body?.content === "string" ? req.body.content.trim() : "";
    if (!content) return res.status(400).json({ error: "content is required" });
    try {
      if (!(await _isOwnerOrEditor(id, uid))) return res.status(404).json({ error: "Project not found" });
      const saved = await memoryService.projects.addProjectKnowledge({
        projectId: id,
        knowledgeType: USER_NOTES_TYPE,
        title: null,
        content,
        source: "user_provided",
        relevanceScore: 1.0,
      } as any);
      res.status(201).json({ note: saved });
    } catch (e: any) {
      console.error("[user_notes] create failed:", e?.message ?? e);
      res.status(500).json({ error: "Failed to save note" });
    }
  });

  // Human notes only: never delete synthesized knowledge or another project's row.
  app.delete("/api/projects/:id/notes-list/:noteId", authenticateToken, async (req: Request, res: Response) => {
    const uid = userId(req);
    if (!uid) return res.status(401).json({ error: "Unauthorized" });
    const { id, noteId } = req.params;
    if (!/^[1-9]\d*$/.test(noteId) || !Number.isSafeInteger(Number(noteId))) return res.status(400).json({ error: "Invalid note ID" });
    try {
      if (!(await _isOwnerOrEditor(id, uid))) return res.status(404).json({ error: "Project not found" });
      const deleted = await pool.query(
        `DELETE FROM project_knowledge WHERE id = $1 AND project_id = $2 AND knowledge_type = $3 RETURNING id`,
        [Number(noteId), id, USER_NOTES_TYPE]
      );
      if (!deleted.rows.length) return res.status(404).json({ error: "Note not found" });
      return res.json({ deleted: true });
    } catch (e: any) {
      console.error("[user_notes] delete failed:", e?.message ?? e);
      return res.status(500).json({ error: "Failed to delete note" });
    }
  });

  // ─── GET /api/join/:token ────────────────────────────────────────────────────
  // PUBLIC — no auth required. Returns project preview for the join landing page.
  app.get("/api/join/:token", async (req: Request, res: Response) => {
    const { token } = req.params;
    try {
      const row = await pool.query(
        `SELECT pst.project_id, pst.role, pst.expires_at, p.name AS project_name, p.description
         FROM project_share_tokens pst
         JOIN projects p ON p.id = pst.project_id
         WHERE pst.token = $1`,
        [token]
      );
      if (!row.rows.length) return res.status(404).json({ error: "Invalid or expired share link" });
      const { project_id, role, expires_at, project_name, description } = row.rows[0];
      if (expires_at && new Date(expires_at) < new Date()) {
        return res.status(410).json({ error: "This share link has expired" });
      }
      res.json({ projectId: project_id, projectName: project_name, description, role });
    } catch (e: any) {
      console.error("[project_join] preview failed:", e?.message ?? e);
      res.status(500).json({ error: "Failed to look up share link" });
    }
  });

  // ─── POST /api/join/:token/accept ────────────────────────────────────────────
  // AUTHENTICATED — adds the calling user as a project member and returns projectId.
  app.post("/api/join/:token/accept", authenticateToken, async (req: Request, res: Response) => {
    const uid = userId(req);
    if (!uid) return res.status(401).json({ error: "Unauthorized" });
    const { token } = req.params;
    try {
      const row = await pool.query(
        `SELECT pst.project_id, pst.role, pst.expires_at, p.user_id AS owner_id
         FROM project_share_tokens pst
         JOIN projects p ON p.id = pst.project_id
         WHERE pst.token = $1`,
        [token]
      );
      if (!row.rows.length) return res.status(404).json({ error: "Invalid or expired share link" });
      const { project_id, role, expires_at, owner_id } = row.rows[0];
      if (expires_at && new Date(expires_at) < new Date()) {
        return res.status(410).json({ error: "This share link has expired" });
      }
      if (owner_id === uid) {
        return res.json({ projectId: project_id, alreadyMember: true });
      }
      await pool.query(
        `INSERT INTO project_members (project_id, user_id, role, invited_by)
         VALUES ($1, $2, $3, $4)
         ON CONFLICT (project_id, user_id) DO UPDATE SET role = EXCLUDED.role`,
        [project_id, uid, role, owner_id]
      );
      res.json({ projectId: project_id, role });
    } catch (e: any) {
      console.error("[project_join] accept failed:", e?.message ?? e);
      res.status(500).json({ error: "Failed to join project" });
    }
  });
}

// ─── Exported helper ──────────────────────────────────────────────────────────
// Called by routes.ts from the save-to-project endpoint (and optionally the
// output_files auto-register path). Inserts each file as source='run_output'
// using an ON CONFLICT DO NOTHING upsert on (project_id, s3_key) so repeated
// calls are idempotent.
/**
 * Save a file BioMate generated in a project chat (a run_code report, table or plot) as a project
 * file: S3 under projects/<id>/generated/, the same content-hash dedup and by-name versioning as
 * uploads (a regenerated QC_Report.txt becomes v2), activity log. Owner/editor only; null otherwise.
 */
export async function storeGeneratedFileInProject(o: {
  projectId: string; uid: string; hostPath: string; name: string;
  /** Per-chat folder (chat-output-folder.ts) — outputs of different chats stay apart. */
  folder?: string;
}): Promise<{ file: any; versioned: boolean; deduplicated?: boolean } | null> {
  if (!(await _isOwnerOrEditor(o.projectId, o.uid))) return null;
  const base = String(o.name || "").replace(/\\/g, "/").split("/").filter(Boolean).pop() || "file";
  const { name, keyPath } = o.folder ? projectInputPath(base, `${o.folder}/${base}`) : projectInputPath(o.name);
  const key = `projects/${o.projectId}/generated/${keyPath}`;
  const buf = fs.readFileSync(o.hostPath);
  const contentHash = createHash("sha256").update(buf).digest("hex");
  const stored = await _storeProjectInput({ id: o.projectId, uid: o.uid, name, key, buf,
    contentType: uploadContentType(name), contentHash, source: "run_code" });
  // Same name rule as uploads and renames; the run_code caller logs the failure (never fails the run).
  if (stored.status === 409) throw new Error(stored.error);
  if ("deduplicated" in stored) return { file: stored.file, versioned: false, deduplicated: true };
  return { file: stored.file, versioned: stored.versioned };
}

export async function registerRunOutputsInProject(opts: {
  projectId: string;
  userId: string;
  runId: string;
  workflowName: string;
  inputContext?: Record<string, unknown>; // run parameters + input file names
  files: Array<{ name: string; s3Key: string; size?: number; contentType?: string; stepName?: string }>;
}): Promise<number> {
  const { projectId, userId, runId, workflowName, inputContext, files } = opts;
  if (!files.length) return 0;

  // Ensure the unique constraint exists — idempotent DDL.
  await pool.query(`
    CREATE UNIQUE INDEX IF NOT EXISTS project_files_project_s3key_idx
      ON project_files(project_id, s3_key)
  `).catch((e: any) => {
    // IF NOT EXISTS never fails for an existing index: a failure is real (e.g. duplicate
    // (project_id, s3_key) rows block the unique index) and the ON CONFLICT below depends on it.
    console.warn("[project_files] run-output unique index could not be ensured:", e?.message ?? e);
  });

  const inputCtxJson = inputContext ? JSON.stringify(inputContext) : null;

  let inserted = 0;
  for (const f of files) {
    // Infer step name from S3 path when not explicitly provided.
    // nf-core publishDir paths: .../output/<step_name>/filename
    // We take the directory component immediately before the filename.
    const stepName = f.stepName ?? (() => {
      const parts = f.s3Key.split("/");
      if (parts.length >= 2) {
        const dir = parts[parts.length - 2];
        // Skip generic dirs like 'output', 'results', 'work', UUIDs
        if (dir && !/^(output|results|work|publish|[0-9a-f]{8,})$/i.test(dir)) return dir;
      }
      return null;
    })();

    try {
      const res = await pool.query(
        `INSERT INTO project_files
           (project_id, user_id, name, s3_key, size, content_type, source, run_id, workflow_name, step_name, input_context)
         VALUES ($1, $2, $3, $4, $5, $6, 'run_output', $7, $8, $9, $10)
         ON CONFLICT (project_id, s3_key) DO NOTHING`,
        [
          projectId,
          userId,
          f.name || f.s3Key.split("/").pop() || "file",
          f.s3Key,
          f.size ?? 0,
          f.contentType || "application/octet-stream",
          runId,
          workflowName,
          stepName ?? null,
          inputCtxJson,
        ]
      );
      if ((res.rowCount ?? 0) > 0) inserted++;
    } catch (e: any) {
      console.warn(`[registerRunOutputs] skipped ${f.s3Key}:`, e?.message);
    }
  }
  console.log(`[registerRunOutputs] registered ${inserted}/${files.length} files for run ${runId} → project ${projectId}`);
  return inserted;
}
