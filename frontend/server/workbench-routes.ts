/**
 * Project Workbench (pinboard) routes — Stream-A platform.
 *
 * Workbench lets a user pin output files from any completed run in a
 * project, then open multiple pinned files side-by-side in the right
 * panel (tabs + optional 2-pane split). Cheap version per
 * docs/20260619_AI_GLASSES_AND_AUDIO_BIOMATE_PROTOTYPES.md companion +
 * the Mira-comparison doc — no infinite canvas, no Y.js, just tabs +
 * existing step-output-preview renderers.
 *
 * Storage: pin rows live in `project_knowledge` with
 * `knowledgeType='workbench_pin'` and `content` set to a JSON-stringified
 * pin payload (`{ runId, filePath, fileName, fileSize? }`). Reuses the
 * project-scoped, cascade-deleting, per-project-indexed table the same
 * way Notes does — no new table, no PG migration.
 *
 * Endpoints:
 *   GET    /api/projects/:projectId/workbench/pins      → list
 *   POST   /api/projects/:projectId/workbench/pins      → add
 *   DELETE /api/projects/:projectId/workbench/pins/:id  → remove
 *
 * Ownership: 404 (NOT 403) on cross-user access. Matches notes-routes
 * and project-routes policy.
 */

import type { Express, Request, Response } from "express";
import { authenticateToken } from "./auth-middleware";
import { memoryService } from "./memory-repository";

const WORKBENCH_PIN_TYPE = "workbench_pin";

interface PinPayload {
  runId: string;
  filePath: string;
  fileName: string;
  fileSize?: number;
}

function userId(req: Request): string | null {
  const u = (req as any).user;
  return u?.id ? String(u.id) : null;
}

/**
 * Parse the JSON content of a workbench_pin row into a structured pin.
 * Returns null on malformed JSON so callers can skip bad rows without
 * crashing the whole list.
 */
function parsePin(row: any): (PinPayload & { id: number; createdAt: any }) | null {
  if (!row?.content) return null;
  try {
    const payload = JSON.parse(row.content) as PinPayload;
    if (!payload?.filePath || !payload?.runId) return null;
    return {
      id: row.id,
      createdAt: row.createdAt,
      runId: payload.runId,
      filePath: payload.filePath,
      fileName: payload.fileName,
      fileSize: payload.fileSize,
    };
  } catch {
    return null;
  }
}

export function registerWorkbenchRoutes(app: Express): void {
  // ─── GET /api/projects/:projectId/workbench/pins ─────────────────────
  // List all pins for the project (newest first).
  app.get(
    "/api/projects/:projectId/workbench/pins",
    authenticateToken,
    async (req: Request, res: Response) => {
      const uid = userId(req);
      if (!uid) return res.status(401).json({ error: "Unauthorized" });
      const projectId = req.params.projectId;

      try {
        const project = await memoryService.projects.getProject(projectId);
        if (!project || project.userId !== uid) {
          return res.status(404).json({ error: "Project not found" });
        }

        const rows = await memoryService.projects.getProjectKnowledge(
          projectId,
          WORKBENCH_PIN_TYPE,
        );
        const pins = (rows ?? [])
          .map(parsePin)
          .filter((p): p is NonNullable<ReturnType<typeof parsePin>> => p !== null)
          .sort((a, b) => {
            const at = a.createdAt ? new Date(a.createdAt).getTime() : 0;
            const bt = b.createdAt ? new Date(b.createdAt).getTime() : 0;
            return bt - at;
          });

        return res.json({ pins });
      } catch (e: any) {
        console.error("[workbench] list failed:", e?.message ?? e);
        return res.status(500).json({ error: "Failed to list pins" });
      }
    },
  );

  // ─── POST /api/projects/:projectId/workbench/pins ────────────────────
  // Body: { runId, filePath, fileName, fileSize? }. Stores as
  // project_knowledge of type workbench_pin. Returns the saved row.
  app.post(
    "/api/projects/:projectId/workbench/pins",
    authenticateToken,
    async (req: Request, res: Response) => {
      const uid = userId(req);
      if (!uid) return res.status(401).json({ error: "Unauthorized" });
      const projectId = req.params.projectId;

      try {
        const project = await memoryService.projects.getProject(projectId);
        if (!project || project.userId !== uid) {
          return res.status(404).json({ error: "Project not found" });
        }

        const { runId, filePath, fileName, fileSize } = req.body ?? {};
        if (!runId || !filePath || !fileName) {
          return res.status(400).json({
            error: "runId, filePath, and fileName are required",
          });
        }

        const payload: PinPayload = {
          runId: String(runId),
          filePath: String(filePath),
          fileName: String(fileName),
          ...(typeof fileSize === "number" ? { fileSize } : {}),
        };

        const saved = await memoryService.projects.addProjectKnowledge({
          projectId,
          knowledgeType: WORKBENCH_PIN_TYPE,
          title: payload.fileName,
          content: JSON.stringify(payload),
          source: "user_provided",
          relevanceScore: 1.0,
        } as any);

        const pin = parsePin(saved);
        if (!pin) {
          console.error("[workbench] saved row did not parse:", saved);
          return res.status(500).json({ error: "Failed to save pin" });
        }
        return res.status(201).json({ pin });
      } catch (e: any) {
        console.error("[workbench] add failed:", e?.message ?? e);
        return res.status(500).json({ error: "Failed to add pin" });
      }
    },
  );

  // ─── DELETE /api/projects/:projectId/workbench/pins/:pinId ───────────
  // Removes a pin row. Scoped by project so cross-project deletes are
  // impossible even with a guessed id.
  app.delete(
    "/api/projects/:projectId/workbench/pins/:pinId",
    authenticateToken,
    async (req: Request, res: Response) => {
      const uid = userId(req);
      if (!uid) return res.status(401).json({ error: "Unauthorized" });
      const projectId = req.params.projectId;
      const pinIdRaw = req.params.pinId;
      const pinId = Number.parseInt(pinIdRaw, 10);
      if (!Number.isFinite(pinId) || pinId <= 0) {
        return res.status(400).json({ error: "Invalid pin id" });
      }

      try {
        const project = await memoryService.projects.getProject(projectId);
        if (!project || project.userId !== uid) {
          return res.status(404).json({ error: "Project not found" });
        }

        const ok = await memoryService.projects.deleteProjectKnowledgeRow(
          projectId,
          pinId,
        );
        if (!ok) {
          return res.status(404).json({ error: "Pin not found" });
        }
        return res.status(204).end();
      } catch (e: any) {
        console.error("[workbench] delete failed:", e?.message ?? e);
        return res.status(500).json({ error: "Failed to delete pin" });
      }
    },
  );
}
