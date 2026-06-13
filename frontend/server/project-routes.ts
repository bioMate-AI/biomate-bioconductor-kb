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
}
