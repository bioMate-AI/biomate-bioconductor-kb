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
  // Fetch a single project the user owns. 404 if not found OR not owned
  // (we never leak existence of another user's project).
  app.get("/api/projects/:id", authenticateToken, async (req: Request, res: Response) => {
    const uid = userId(req);
    if (!uid) return res.status(401).json({ error: "Unauthorized" });
    const id = req.params.id;
    try {
      const project = await memoryService.projects.getProject(id);
      if (!project || project.userId !== uid) {
        return res.status(404).json({ error: "Project not found" });
      }
      const context = await memoryService.projects.loadProjectContext(id);
      res.json({ project, context });
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
        `SELECT id, name, s3_key, size, content_type, source, run_id, created_at
         FROM project_files WHERE project_id = $1 ORDER BY created_at DESC`,
        [id]
      );
      res.json({ files: result.rows });
    } catch (e: any) {
      console.error("[project_files] list failed:", e?.message ?? e);
      res.status(500).json({ error: "Failed to list files" });
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
}
