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
import { authenticateToken } from "./auth-middleware";
import { memoryService } from "./memory-repository";
import { pool } from "./db";
import { s3Service } from "./s3-client";
import multer from "multer";
import { randomUUID } from "crypto";
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

async function _isOwnerOrMember(projectId: string, uid: string): Promise<boolean> {
  const project = await memoryService.projects.getProject(projectId);
  if (!project) return false;
  if (project.userId === uid) return true;
  const r = await pool.query(
    `SELECT 1 FROM project_members WHERE project_id = $1 AND user_id = $2`,
    [projectId, uid]
  );
  return r.rows.length > 0;
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
}
// Run once on startup — idempotent
ensureProjectFilesTable().catch(e => console.error("[project_files] table init failed:", e?.message ?? e));

function userId(req: Request): string | null {
  const u = (req as any).user;
  return u?.id ? String(u.id) : null;
}

export function registerProjectRoutes(app: Express): void {
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
      if (project.userId !== uid) {
        const memberCheck = await pool.query(
          `SELECT 1 FROM project_members WHERE project_id = $1 AND user_id = $2`,
          [id, uid]
        );
        if (!memberCheck.rows.length) return res.status(404).json({ error: "Project not found" });
      }
      const context = await memoryService.projects.loadProjectContext(id);
      const isOwner = project.userId === uid;
      res.json({ project, context, isOwner });
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
      if (!existing || existing.userId !== uid) {
        return res.status(404).json({ error: "Project not found" });
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
      const existing = await memoryService.projects.getProject(id);
      if (!existing || existing.userId !== uid) {
        return res.status(404).json({ error: "Project not found" });
      }
      const result = await pool.query(
        `SELECT id, name, s3_key, size, content_type, source, run_id, workflow_name, step_name, input_context, created_at
         FROM project_files WHERE project_id = $1 ORDER BY created_at DESC`,
        [id]
      );
      res.json({ files: result.rows });
    } catch (e: any) {
      console.error("[project_files] list failed:", e?.message ?? e);
      res.status(500).json({ error: "Failed to list files" });
    }
  });

  // ─── GET /api/projects/:id/sessions ──────────────────────────────────
  // List chat sessions linked to a project, newest first (max 50).
  app.get("/api/projects/:id/sessions", authenticateToken, async (req: Request, res: Response) => {
    const uid = userId(req);
    if (!uid) return res.status(401).json({ error: "Unauthorized" });
    const id = req.params.id;
    try {
      const existing = await memoryService.projects.getProject(id);
      if (!existing || existing.userId !== uid) {
        return res.status(404).json({ error: "Project not found" });
      }
      const result = await pool.query(
        `SELECT session_id, title, status, created_at, last_activity,
                jsonb_array_length(messages) AS message_count
         FROM chat_sessions
         WHERE project_id = $1 AND user_id = $2
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
  // Multipart upload: saves to S3 under projects/<projectId>/inputs/<filename>,
  // then records metadata in project_files.
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
        if (!existing || existing.userId !== uid) {
          fs.unlink(req.file.path, () => {});
          return res.status(404).json({ error: "Project not found" });
        }
        const originalName = req.file.originalname || req.file.filename;
        const safeExt = path.extname(originalName).toLowerCase().replace(/[^a-z0-9.]/g, "");
        const safeName = path.basename(originalName, path.extname(originalName))
          .replace(/[^a-zA-Z0-9._-]/g, "_")
          .slice(0, 200);
        const key = `projects/${id}/inputs/${safeName}${safeExt}`;
        const buf = fs.readFileSync(req.file.path);
        fs.unlink(req.file.path, () => {});
        await s3Service.putObject(key, buf, req.file.mimetype || "application/octet-stream", uid);
        const ins = await pool.query(
          `INSERT INTO project_files (project_id, user_id, name, s3_key, size, content_type, source)
           VALUES ($1, $2, $3, $4, $5, $6, 'upload')
           RETURNING id, name, s3_key, size, content_type, source, run_id, created_at`,
          [id, uid, originalName, key, req.file.size, req.file.mimetype || "application/octet-stream"]
        );
        res.status(201).json({ file: ins.rows[0] });
      } catch (e: any) {
        if (req.file?.path) fs.unlink(req.file.path, () => {});
        console.error("[project_files] upload failed:", e?.message ?? e);
        res.status(500).json({ error: "Upload failed" });
      }
    }
  );

  // ─── DELETE /api/projects/:id/files/:fileId ───────────────────────────
  app.delete("/api/projects/:id/files/:fileId", authenticateToken, async (req: Request, res: Response) => {
    const uid = userId(req);
    if (!uid) return res.status(401).json({ error: "Unauthorized" });
    const { id, fileId } = req.params;
    try {
      const existing = await memoryService.projects.getProject(id);
      if (!existing || existing.userId !== uid) {
        return res.status(404).json({ error: "Project not found" });
      }
      const fileRow = await pool.query(
        `SELECT s3_key FROM project_files WHERE id = $1 AND project_id = $2 AND user_id = $3`,
        [fileId, id, uid]
      );
      if (!fileRow.rows.length) return res.status(404).json({ error: "File not found" });
      await s3Service.deleteFile(fileRow.rows[0].s3_key);
      await pool.query(`DELETE FROM project_files WHERE id = $1`, [fileId]);
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
      const existing = await memoryService.projects.getProject(id);
      if (!existing || existing.userId !== uid) {
        return res.status(404).json({ error: "Project not found" });
      }
      const fileRow = await pool.query(
        `SELECT s3_key, name FROM project_files WHERE id = $1 AND project_id = $2 AND user_id = $3`,
        [fileId, id, uid]
      );
      if (!fileRow.rows.length) return res.status(404).json({ error: "File not found" });
      const url = await s3Service.generatePresignedDownloadUrl(fileRow.rows[0].s3_key, 900);
      res.json({ url, name: fileRow.rows[0].name });
    } catch (e: any) {
      console.error("[project_files] url failed:", e?.message ?? e);
      res.status(500).json({ error: "Failed to generate download URL" });
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
      const result = await pool.query(
        `SELECT pm.user_id, pm.role, pm.created_at,
                u.email, u.full_name AS "fullName"
         FROM project_members pm
         JOIN users u ON u.id = pm.user_id
         WHERE pm.project_id = $1
         ORDER BY pm.created_at ASC`,
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
    try {
      const existing = await memoryService.projects.getProject(id);
      if (!existing || existing.userId !== uid) return res.status(404).json({ error: "Project not found" });
      const invitee = await pool.query(`SELECT id, email, full_name AS "fullName" FROM users WHERE email = $1`, [email.toLowerCase().trim()]);
      if (!invitee.rows.length) return res.status(404).json({ error: "No user found with that email" });
      const inviteeId = invitee.rows[0].id;
      if (inviteeId === uid) return res.status(400).json({ error: "Cannot invite yourself" });
      await pool.query(
        `INSERT INTO project_members (project_id, user_id, role, invited_by)
         VALUES ($1, $2, $3, $4)
         ON CONFLICT (project_id, user_id) DO UPDATE SET role = EXCLUDED.role`,
        [id, inviteeId, role, uid]
      );
      res.status(201).json({ member: { user_id: inviteeId, ...invitee.rows[0], role } });
    } catch (e: any) {
      console.error("[project_members] invite failed:", e?.message ?? e);
      res.status(500).json({ error: "Failed to invite member" });
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
        `DELETE FROM project_members WHERE project_id = $1 AND user_id = $2`,
        [id, memberId]
      );
      if ((del.rowCount ?? 0) === 0) return res.status(404).json({ error: "Member not found" });
      res.json({ ok: true });
    } catch (e: any) {
      console.error("[project_members] remove failed:", e?.message ?? e);
      res.status(500).json({ error: "Failed to remove member" });
    }
  });
}

// ─── Exported helper ──────────────────────────────────────────────────────────
// Called by routes.ts from the save-to-project endpoint (and optionally the
// output_files auto-register path). Inserts each file as source='run_output'
// using an ON CONFLICT DO NOTHING upsert on (project_id, s3_key) so repeated
// calls are idempotent.
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
