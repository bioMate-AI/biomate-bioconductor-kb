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
import { projectInputPath, projectInputKey, decodeMultipartFilename } from "./project-file-paths";
import multer from "multer";
import { randomUUID, randomBytes, createHash } from "crypto";
import path from "path";
import fs from "fs";

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
  await pool.query(`ALTER TABLE project_files ADD COLUMN IF NOT EXISTS workflow_name TEXT`).catch(() => {});
  await pool.query(`ALTER TABLE project_files ADD COLUMN IF NOT EXISTS step_name TEXT`).catch(() => {});
  await pool.query(`ALTER TABLE project_files ADD COLUMN IF NOT EXISTS input_context JSONB`).catch(() => {});
  // Content hash for dedup (design §4.5.1 — the same file added twice links to one
  // entry rather than creating two). sha256 hex, computed at ingest.
  await pool.query(`ALTER TABLE project_files ADD COLUMN IF NOT EXISTS content_hash TEXT`).catch(() => {});
  await pool.query(`CREATE INDEX IF NOT EXISTS project_files_hash_idx ON project_files(project_id, content_hash)`).catch(() => {});
  // App-level content versioning (design §4.4 — "saving an edit writes a new
  // version; it never overwrites"). The project_files row is the CURRENT version
  // (version_no); every SUPERSEDED version is archived as its own S3 object +
  // a project_file_versions row. No S3 bucket-versioning required — each version
  // is a distinct object, so a completed run always keeps the exact bytes it read.
  await pool.query(`ALTER TABLE project_files ADD COLUMN IF NOT EXISTS version_no INTEGER NOT NULL DEFAULT 1`).catch(() => {});
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
  `).catch(() => {});
  await pool.query(`CREATE INDEX IF NOT EXISTS project_file_versions_file_idx ON project_file_versions(file_id, version_no)`).catch(() => {});
}
// Run once on startup — idempotent
ensureProjectFilesTable().catch(e => console.error("[project_files] table init failed:", e?.message ?? e));

/** Content-hash dedup lookup (§4.5.1): the existing project file with these exact
 *  bytes, or null. Returns the same column shape the ingest endpoints respond with. */
async function _findProjectFileByHash(projectId: string, hash: string): Promise<any | null> {
  try {
    const r = await pool.query(
      `SELECT id, name, s3_key, size, content_type, source, run_id, content_hash, created_at
       FROM project_files WHERE project_id = $1 AND content_hash = $2 LIMIT 1`,
      [projectId, hash]
    );
    return r.rows[0] || null;
  } catch { return null; }  // never let a dedup lookup break ingest
}

/** The current user-ingested file with this name in the project (upload/url only —
 *  run outputs are immutable results, never versioned by a re-upload). */
async function _findProjectFileByName(projectId: string, name: string, sources: string[] = ['upload', 'url']): Promise<any | null> {
  try {
    const r = await pool.query(
      `SELECT id, name, s3_key, size, content_type, content_hash, version_no
       FROM project_files
       WHERE project_id = $1 AND name = $2 AND source = ANY($3::text[]) LIMIT 1`,
      [projectId, name, sources]
    );
    return r.rows[0] || null;
  } catch { return null; }
}

/** Append-only: archive a project file's CURRENT content as a project_file_versions
 *  row (design §4.4 — nothing a finished run read can change underneath it). The
 *  current bytes stay at their existing s3_key; this just records them as a past
 *  version so the new content can take over the project_files row. */
/** Parse tabular text into headers + rows (capped). Delimiter from the extension,
 *  else sniffed. Used by the version Compare/diff (design §4.4). */
function _parseTabular(text: string, ext: string): { headers: string[]; rows: string[][] } {
  const e = (ext || "").toLowerCase();
  const delim = (e === "tsv" || e === "tab") ? "\t" : (e === "csv") ? "," : (text.indexOf("\t") >= 0 ? "\t" : ",");
  const lines = text.split(/\r?\n/).filter((l) => l.length > 0).slice(0, 500);
  const rows = lines.map((l) => l.split(delim));
  return { headers: rows[0] || [], rows: rows.slice(1) };
}

async function _archiveCurrentAsVersion(cur: any, projectId: string, note: string, author: string): Promise<void> {
  await pool.query(
    `INSERT INTO project_file_versions
       (file_id, project_id, version_no, s3_key, size, content_type, content_hash, note, author)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
    [cur.id, projectId, cur.version_no, cur.s3_key, cur.size,
     cur.content_type, cur.content_hash ?? null, note, author]
  );
}

/**
 * Store a project input file (browser upload or URL import): the same name with
 * different bytes becomes a new version (append-only, §4.4) — never an overwrite of
 * bytes a completed run used; otherwise a new file row. Caller has already done
 * content-hash dedup and resolved `key` through projectInputPath.
 */
async function _storeProjectInput(o: {
  id: string; uid: string; name: string; key: string; buf: Buffer;
  contentType: string; contentHash: string; source: "upload" | "url" | "run_code";
}): Promise<{ file: any; versioned: boolean }> {
  // A regenerated analysis file versions the earlier generated one; an upload versions an upload.
  const prior = await _findProjectFileByName(o.id, o.name, o.source === "run_code" ? ["run_code"] : ["upload", "url"]);
  if (prior && prior.content_hash && prior.content_hash !== o.contentHash) {
    const vkey = `${o.key}.v${prior.version_no + 1}`;
    await s3Service.putObject(vkey, o.buf, o.contentType, o.uid);
    await _archiveCurrentAsVersion(prior, o.id, `v${prior.version_no}`, o.uid);
    const upd = await pool.query(
      `UPDATE project_files SET s3_key = $1, size = $2, content_type = $3, content_hash = $4,
         version_no = version_no + 1 WHERE id = $5
       RETURNING id, name, s3_key, size, content_type, source, run_id, content_hash, version_no, created_at`,
      [vkey, o.buf.length, o.contentType, o.contentHash, prior.id]
    );
    await recordProjectActivity(o.id, o.uid, "file_versioned", { fileId: prior.id, name: o.name, version: prior.version_no + 1 });
    return { file: upd.rows[0], versioned: true };
  }
  await s3Service.putObject(o.key, o.buf, o.contentType, o.uid);
  const ins = await pool.query(
    `INSERT INTO project_files (project_id, user_id, name, s3_key, size, content_type, source, content_hash)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
     RETURNING id, name, s3_key, size, content_type, source, run_id, content_hash, created_at`,
    [o.id, o.uid, o.name, o.key, o.buf.length, o.contentType, o.source, o.contentHash]
  );
  await recordProjectActivity(o.id, o.uid, "file_added", { fileId: ins.rows[0].id, name: o.name, source: o.source });
  return { file: ins.rows[0], versioned: false };
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
  app.get("/api/projects/:id/files", authenticateToken, async (req: Request, res: Response) => {
    const uid = userId(req);
    if (!uid) return res.status(401).json({ error: "Unauthorized" });
    const id = req.params.id;
    try {
      const allowed = await _isOwnerOrMember(id, uid);
      if (!allowed) {
        return res.status(404).json({ error: "Project not found" });
      }
      const result = await pool.query(
        `SELECT id, name, s3_key, size, content_type, source, run_id, workflow_name, step_name, input_context, content_hash, created_at
         FROM project_files WHERE project_id = $1 ORDER BY created_at DESC`,
        [id]
      );
      res.json({ files: result.rows });
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
  app.post("/api/projects/:id/files/compatibility", authenticateToken, async (req: Request, res: Response) => {
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
        // Content-hash dedup (§4.5.1): the same bytes already in this project link
        // to the one entry rather than creating two.
        const contentHash = createHash("sha256").update(buf).digest("hex");
        const dup = await _findProjectFileByHash(id, contentHash);
        if (dup) return res.status(200).json({ file: dup, deduplicated: true });
        const ctype = uploadContentType(originalName, req.file.mimetype);
        const stored = await _storeProjectInput({ id, uid, name: originalName, key, buf, contentType: ctype, contentHash, source: "upload" });
        res.status(stored.versioned ? 200 : 201).json(stored.versioned ? { file: stored.file, versioned: true } : { file: stored.file });
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
  app.post("/api/projects/:id/files/import-url", authenticateToken, async (req: Request, res: Response) => {
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
      const dup = await _findProjectFileByHash(id, contentHash);
      if (dup) return res.status(200).json({ file: dup, deduplicated: true });
      // Same name/key rules as a browser upload: the original name is kept for display
      // and the S3 key is collision-safe (a lossy basename let "数据.csv" and "样本.csv"
      // share one object), and the same name with new bytes becomes a new version
      // instead of overwriting bytes a completed run used.
      const rawName = String(req.body?.filename || validated.filename || "download");
      const { name: filename, keyPath } = projectInputPath(rawName);
      const key = `projects/${id}/inputs/${keyPath}`;
      const contentType = (resp.headers.get("content-type") || "").split(";")[0].trim() || "application/octet-stream";
      const stored = await _storeProjectInput({ id, uid, name: filename, key, buf, contentType, contentHash, source: "url" });
      res.status(stored.versioned ? 200 : 201).json(stored.versioned ? { file: stored.file, versioned: true } : { file: stored.file });
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
  app.get("/api/projects/:id/files/:fileId/versions", authenticateToken, async (req: Request, res: Response) => {
    const uid = userId(req);
    if (!uid) return res.status(401).json({ error: "Unauthorized" });
    const { id, fileId } = req.params;
    try {
      if (!(await _isOwnerOrMember(id, uid))) return res.status(404).json({ error: "Project not found" });
      const cur = await pool.query(
        `SELECT version_no, size, created_at FROM project_files WHERE id = $1 AND project_id = $2`,
        [fileId, id]
      );
      if (!cur.rows[0]) return res.status(404).json({ error: "File not found" });
      const past = await pool.query(
        `SELECT version_no, size, note, author, created_at FROM project_file_versions
         WHERE file_id = $1 ORDER BY version_no DESC`,
        [fileId]
      );
      const current = cur.rows[0];
      const versions = [
        { version: String(current.version_no), label: `v${current.version_no}`, current: true,
          size: Number(current.size), createdAt: current.created_at, note: null, author: null },
        ...past.rows.map((r: any) => ({
          version: String(r.version_no), label: `v${r.version_no}`, current: false,
          size: Number(r.size), createdAt: r.created_at, note: r.note, author: r.author,
        })),
      ];
      res.json({ versions });
    } catch (e: any) {
      console.error("[project_files] versions failed:", e?.message ?? e);
      res.status(500).json({ error: "Failed to list versions" });
    }
  });

  // ─── POST /api/projects/:id/files/:fileId/versions/:versionNo/restore ──
  // Append-only restore (design §4.4 — "restoring writes a new version; history
  // never rewinds"). Archives the current content as a version, then points the
  // file at the chosen version's (retained) bytes as a new current version.
  app.post("/api/projects/:id/files/:fileId/versions/:versionNo/restore", authenticateToken, async (req: Request, res: Response) => {
    const uid = userId(req);
    if (!uid) return res.status(401).json({ error: "Unauthorized" });
    const { id, fileId, versionNo } = req.params;
    try {
      if (!(await _isOwnerOrEditor(id, uid))) return res.status(404).json({ error: "Project not found" });
      const cur = await pool.query(
        `SELECT id, name, s3_key, size, content_type, content_hash, version_no FROM project_files WHERE id = $1 AND project_id = $2`,
        [fileId, id]
      );
      if (!cur.rows[0]) return res.status(404).json({ error: "File not found" });
      const target = await pool.query(
        `SELECT s3_key, size, content_type, content_hash FROM project_file_versions WHERE file_id = $1 AND version_no = $2`,
        [fileId, Number(versionNo)]
      );
      if (!target.rows[0]) return res.status(404).json({ error: "Version not found" });
      await _archiveCurrentAsVersion(cur.rows[0], id, `v${cur.rows[0].version_no}`, uid);
      const t = target.rows[0];
      const upd = await pool.query(
        `UPDATE project_files SET s3_key = $1, size = $2, content_type = $3, content_hash = $4,
           version_no = version_no + 1 WHERE id = $5
         RETURNING id, name, s3_key, size, content_type, source, run_id, content_hash, version_no, created_at`,
        [t.s3_key, t.size, t.content_type, t.content_hash, fileId]
      );
      await recordProjectActivity(id, uid, "file_restored", { fileId, restoredFrom: Number(versionNo), newVersion: upd.rows[0].version_no });
      res.json({ file: upd.rows[0], restoredFrom: Number(versionNo) });
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
  // report a metadata-only diff (size/hash differ) honestly.
  app.get("/api/projects/:id/files/:fileId/versions/:versionNo/diff", authenticateToken, async (req: Request, res: Response) => {
    const uid = userId(req);
    if (!uid) return res.status(401).json({ error: "Unauthorized" });
    const { id, fileId, versionNo } = req.params;
    try {
      if (!(await _isOwnerOrMember(id, uid))) return res.status(404).json({ error: "Project not found" });
      const cur = await pool.query(
        `SELECT name, s3_key, size, content_type, content_hash, version_no FROM project_files WHERE id = $1 AND project_id = $2`,
        [fileId, id]
      );
      if (!cur.rows[0]) return res.status(404).json({ error: "File not found" });
      const tgt = await pool.query(
        `SELECT s3_key, size, content_hash FROM project_file_versions WHERE file_id = $1 AND version_no = $2`,
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
      const [curText, tgtText] = await Promise.all([
        s3Service.readTextPrefix(c.s3_key, CAP).catch(() => ""),
        s3Service.readTextPrefix(t.s3_key, CAP).catch(() => ""),
      ]);
      const A = _parseTabular(curText, ext);  // current
      const B = _parseTabular(tgtText, ext);  // target (older)
      const added = A.headers.filter((h) => !B.headers.includes(h));
      const removed = B.headers.filter((h) => !A.headers.includes(h));
      const changedCells: Array<{ row: number; col: string; from: string; to: string }> = [];
      const nRows = Math.min(A.rows.length, B.rows.length);
      const nCols = Math.min(A.headers.length, B.headers.length);
      for (let i = 0; i < nRows && changedCells.length < 100; i++) {
        for (let j = 0; j < nCols; j++) {
          const av = A.rows[i]?.[j] ?? "", bv = B.rows[i]?.[j] ?? "";
          if (av !== bv) changedCells.push({ row: i, col: A.headers[j] ?? String(j), from: bv, to: av });
        }
      }
      res.json({
        ...base,
        columns: { added, removed },
        rowsCompared: nRows,
        changedCells,
        truncated: (A.rows.length >= 500 || B.rows.length >= 500),
      });
    } catch (e: any) {
      console.error("[project_files] diff failed:", e?.message ?? e);
      res.status(500).json({ error: "Diff failed" });
    }
  });

  // ─── POST /api/projects/:id/files/:fileId/edit ────────────────────────
  // Edit-in-place → write a new version (design §4.3/§4.4 — "saving an edit writes
  // a new version; it never overwrites"). The preview is only a SAMPLE, so the
  // client sends cell EDITS {row,col,value} (row = index among the first rows the
  // user saw); we apply them to the FULL file server-side and version it. Tabular
  // only, size-capped (10 MiB) — larger files edit in Jupyter/RStudio.
  app.post("/api/projects/:id/files/:fileId/edit", authenticateToken, async (req: Request, res: Response) => {
    const uid = userId(req);
    if (!uid) return res.status(401).json({ error: "Unauthorized" });
    const { id, fileId } = req.params;
    const edits = Array.isArray(req.body?.edits) ? req.body.edits : null;
    if (!edits || edits.length === 0) return res.status(400).json({ error: "No edits provided" });
    try {
      if (!(await _isOwnerOrEditor(id, uid))) return res.status(404).json({ error: "Project not found" });
      const row = await pool.query(
        `SELECT name, s3_key, content_type, content_hash, version_no FROM project_files WHERE id = $1 AND project_id = $2`,
        [fileId, id]
      );
      if (!row.rows[0]) return res.status(404).json({ error: "File not found" });
      const cur = row.rows[0];
      const ext = (String(cur.name).split(".").pop() || "").toLowerCase();
      if (!["csv", "tsv", "tab", "txt"].includes(ext)) {
        return res.status(400).json({ error: "Only tabular files (csv/tsv) can be edited in place. Open it in Jupyter/RStudio for other formats." });
      }
      const CAP = 10 * 1024 * 1024;
      const size = await s3Service.getFileSize(cur.s3_key).catch(() => 0);
      if (size > CAP) return res.status(413).json({ error: "File exceeds the 10 MiB in-place-edit limit. Open it in Jupyter/RStudio to edit larger files." });
      const text = await s3Service.readTextPrefix(cur.s3_key, CAP);
      const delim = (ext === "tsv" || ext === "tab") ? "\t" : (ext === "csv") ? "," : (text.indexOf("\t") >= 0 ? "\t" : ",");
      const keepTrailingNL = /\n$/.test(text);
      const lines = text.replace(/\n$/, "").split(/\r?\n/);
      const header = (lines[0] || "").split(delim);
      let applied = 0;
      for (const e of edits) {
        const r = Number(e?.row);               // 0-based DATA row (header excluded)
        const colName = String(e?.col ?? "");
        const value = String(e?.value ?? "");
        const lineIdx = r + 1;                   // +1 for the header line
        if (!Number.isInteger(r) || r < 0 || lineIdx >= lines.length) continue;
        const cols = lines[lineIdx].split(delim);
        let j = header.indexOf(colName);
        if (j < 0) { const n = Number(colName); j = Number.isInteger(n) ? n : -1; }
        if (j < 0 || j >= Math.max(cols.length, header.length)) continue;
        while (cols.length <= j) cols.push("");
        cols[j] = value;
        lines[lineIdx] = cols.join(delim);
        applied++;
      }
      if (applied === 0) return res.status(400).json({ error: "None of the edits matched a cell." });
      const newText = lines.join("\n") + (keepTrailingNL ? "\n" : "");
      const buf = Buffer.from(newText, "utf-8");
      const contentHash = createHash("sha256").update(buf).digest("hex");
      const vkey = `${projectInputKey(id, String(cur.name), String(cur.name))}.v${cur.version_no + 1}`;
      await s3Service.putObject(vkey, buf, cur.content_type, uid);
      await _archiveCurrentAsVersion({ ...cur, id: fileId, size }, id, `v${cur.version_no}`, uid);
      const upd = await pool.query(
        `UPDATE project_files SET s3_key = $1, size = $2, content_hash = $3, version_no = version_no + 1 WHERE id = $4
         RETURNING id, name, s3_key, size, content_type, source, run_id, content_hash, version_no, created_at`,
        [vkey, buf.length, contentHash, fileId]
      );
      await recordProjectActivity(id, uid, "file_versioned", { fileId, name: cur.name, version: cur.version_no + 1, editedCells: applied });
      res.json({ file: upd.rows[0], versioned: true, editedCells: applied });
    } catch (e: any) {
      console.error("[project_files] edit failed:", e?.message ?? e);
      res.status(500).json({ error: "Edit failed" });
    }
  });

  // ─── DELETE /api/projects/:id/files/:fileId ───────────────────────────
  app.delete("/api/projects/:id/files/:fileId", authenticateToken, async (req: Request, res: Response) => {
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
      const fileRow = await pool.query(
        `SELECT s3_key FROM project_files WHERE id = $1 AND project_id = $2`,
        [fileId, id]
      );
      if (!fileRow.rows.length) return res.status(404).json({ error: "File not found" });
      await s3Service.deleteFile(fileRow.rows[0].s3_key);
      await pool.query(`DELETE FROM project_files WHERE id = $1`, [fileId]);
      await recordProjectActivity(id, uid, "file_removed", { fileId });
      res.json({ ok: true });
    } catch (e: any) {
      console.error("[project_files] delete failed:", e?.message ?? e);
      res.status(500).json({ error: "Failed to delete file" });
    }
  });

  // ─── GET /api/projects/:id/files/:fileId/url ─────────────────────────
  // Returns a short-lived presigned download URL for a project file.
  app.get("/api/projects/:id/files/:fileId/url", authenticateToken, async (req: Request, res: Response) => {
    const uid = userId(req);
    if (!uid) return res.status(401).json({ error: "Unauthorized" });
    const { id, fileId } = req.params;
    try {
      const allowed = await _isOwnerOrMember(id, uid);
      if (!allowed) {
        return res.status(404).json({ error: "Project not found" });
      }
      const fileRow = await pool.query(
        `SELECT s3_key, name FROM project_files WHERE id = $1 AND project_id = $2`,
        [fileId, id]
      );
      if (!fileRow.rows.length) return res.status(404).json({ error: "File not found" });
      // On-prem (MinIO): presigned URLs embed internal minio:9000 hostname
      // unreachable from the browser — return a Node.js proxy URL instead.
      let url: string;
      if (process.env.S3_ENDPOINT_URL) {
        url = `/api/s3/proxy-download?key=${encodeURIComponent(fileRow.rows[0].s3_key)}`;
      } else {
        url = await s3Service.generatePresignedDownloadUrl(fileRow.rows[0].s3_key, 900);
      }
      // ?redirect=1: a plain <a href> download (chat file chips) — same authorization as the JSON form.
      if (req.query.redirect === "1") return res.redirect(302, url);
      res.json({ url, name: fileRow.rows[0].name });
    } catch (e: any) {
      console.error("[project_files] url failed:", e?.message ?? e);
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
  app.get("/api/projects/:id/files/:fileId/rows", authenticateToken, async (req: Request, res: Response) => {
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
        `SELECT s3_key, name FROM project_files WHERE id = $1 AND project_id = $2`,
        [fileId, id]
      );
      if (!fileRow.rows.length) return res.status(404).json({ error: "File not found" });
      const { fetchGalaxyAsUser, galaxyBaseUrl } = await import("./galaxy-user-fetch");
      const resp = await fetchGalaxyAsUser(req, `${galaxyBaseUrl()}/api/perception/rows`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          datasetRef: fileRow.rows[0].s3_key,
          name: fileRow.rows[0].name,
          offset,
          limit: Math.min(limit, 1000),
        }),
        signal: AbortSignal.timeout(120_000),
      });
      const body: any = await resp.json().catch(() => null);
      if (!resp.ok || !body) {
        console.error(`[project_files] rows backend ${resp.status} for file ${fileId}`);
        return res.status(502).json({ error: "rows_unavailable" });
      }
      if (body.error === "unresolvable_ref") return res.status(404).json({ error: "file_unreadable" });
      if (body.error) return res.status(422).json({ error: "parse_failed" });
      if (body.tabular === false) return res.status(415).json({ error: "not_tabular", kind: body.kind ?? null });
      res.json({
        kind: body.kind,
        columns: Array.isArray(body.columns) ? body.columns : [],
        rows: Array.isArray(body.rows) ? body.rows : [],
        offset: body.offset ?? offset,
        limit: body.limit ?? limit,
        totalRows: typeof body.totalRows === "number" ? body.totalRows : null,
      });
    } catch (e: any) {
      console.error("[project_files] rows failed:", e?.message ?? e);
      res.status(502).json({ error: "rows_unavailable" });
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
        const emailed = await emailService.sendProjectInviteEmail(normEmail, token, projectName, inviterName, role).catch(() => false);
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
}): Promise<{ file: any; versioned: boolean; deduplicated?: boolean } | null> {
  if (!(await _isOwnerOrEditor(o.projectId, o.uid))) return null;
  const { name, keyPath } = projectInputPath(o.name);
  const key = `projects/${o.projectId}/generated/${keyPath}`;
  const buf = fs.readFileSync(o.hostPath);
  const contentHash = createHash("sha256").update(buf).digest("hex");
  const dup = await _findProjectFileByHash(o.projectId, contentHash);
  if (dup) return { file: dup, versioned: false, deduplicated: true };
  return _storeProjectInput({ id: o.projectId, uid: o.uid, name, key, buf,
    contentType: uploadContentType(name), contentHash, source: "run_code" });
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
  `).catch(() => { /* already exists */ });

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
