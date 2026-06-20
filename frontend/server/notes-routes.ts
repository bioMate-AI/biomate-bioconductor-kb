/**
 * Project Notes (synthesis) routes — Stream-A platform.
 *
 * Notes is an on-demand LLM synthesis of everything that has happened in
 * a project: completed runs (findings / errors / output dataset refs)
 * plus recent chat episodes. ONE LLM call per refresh. No cron, no
 * background polling — the user clicks "Refresh" in the UI to trigger.
 *
 * Storage: rows are written to `project_knowledge` with
 * `knowledgeType='notes_synthesis'` and `source='claude_inferred'`. This
 * reuses the existing project-scoped, ownership-cascading, per-project
 * indexed table instead of introducing a new `project_documents` table.
 * Frontend renders `content` (markdown) via the AfterRunReport renderer.
 *
 * Ownership: every endpoint scopes by req.user.id and returns 404 (NOT
 * 403) on cross-user access — matches project-routes.ts policy from
 * docs/20260612_DATASET_STORAGE_AND_SESSION_BOUNDARIES.md.
 *
 * LLM: gemini-3.5-flash, maxTokens=4096, thinking disabled (~$0.05/call).
 */

import type { Express, Request, Response } from "express";
import { authenticateToken } from "./auth-middleware";
import { memoryService } from "./memory-repository";
import { callGeminiFlash } from "./gemini-flash";

const NOTES_TYPE = "notes_synthesis";
const CHAT_LOOKBACK_DAYS = 30;
const LLM_MAX_TOKENS = 4096;

function userId(req: Request): string | null {
  const u = (req as any).user;
  return u?.id ? String(u.id) : null;
}

function truncate(s: string | null | undefined, n: number): string {
  if (!s) return "";
  return s.length > n ? s.slice(0, n) + "…" : s;
}

/**
 * Build the LLM context block from a project's completed runs + recent
 * episodes. Kept small (each section truncated) so the call stays
 * cheap and within Flash's input budget.
 */
function buildSynthesisPrompt(args: {
  projectName: string;
  projectDescription: string | null;
  recentWorkflows: Array<any>;
  recentEpisodes: Array<any>;
}): { system: string; user: string } {
  const { projectName, projectDescription, recentWorkflows, recentEpisodes } = args;

  const runsBlock = recentWorkflows.length === 0
    ? "(no completed runs yet)"
    : recentWorkflows
        .filter((w) => w.status === "completed" || w.status === "failed")
        .slice(0, 20)
        .map((w, i) => {
          const lines = [
            `Run ${i + 1}: ${w.name ?? "(unnamed)"} — status=${w.status}`,
            w.domain ? `  domain: ${w.domain}` : "",
            w.analysisGoal ? `  goal: ${truncate(w.analysisGoal, 200)}` : "",
            w.errorMessage ? `  error: ${truncate(w.errorMessage, 200)}` : "",
            w.executionCompletedAt ? `  completed_at: ${w.executionCompletedAt}` : "",
          ].filter(Boolean);
          return lines.join("\n");
        })
        .join("\n\n");

  // Filter to chat in lookback window
  const cutoff = Date.now() - CHAT_LOOKBACK_DAYS * 24 * 60 * 60 * 1000;
  const episodesBlock = recentEpisodes.length === 0
    ? "(no recent chat episodes)"
    : recentEpisodes
        .filter((e) => {
          if (!e.createdAt) return true;
          const ts = new Date(e.createdAt).getTime();
          return ts >= cutoff;
        })
        .slice(0, 30)
        .map((e, i) => {
          return [
            `Episode ${i + 1}:`,
            `  user: ${truncate(e.userQuery, 300)}`,
            `  assistant: ${truncate(e.assistantResponse, 400)}`,
          ].join("\n");
        })
        .join("\n\n");

  const system =
    "You are a scientific project synthesiser. Given the run history and " +
    "chat record from a single bioinformatics / drug-discovery project, " +
    "produce a concise markdown brief that captures: (1) what the project " +
    "is investigating, (2) what has been run and what the results showed, " +
    "(3) open questions or next steps suggested by the work so far. " +
    "Write in plain markdown — no preamble, no apologies, no boilerplate. " +
    "Cite specific run names when relevant. Keep it under 800 words.";

  const user = [
    `# Project: ${projectName}`,
    projectDescription ? `\n${projectDescription}` : "",
    "\n## Completed runs\n",
    runsBlock,
    "\n## Recent chat\n",
    episodesBlock,
    "\n---\nSynthesise.",
  ].join("\n");

  return { system, user };
}

export function registerNotesRoutes(app: Express): void {
  // ─── POST /api/projects/:projectId/notes/refresh ─────────────────────
  // Triggers an LLM synthesis. Writes a new project_knowledge row of
  // type notes_synthesis. Returns the saved row.
  app.post(
    "/api/projects/:projectId/notes/refresh",
    authenticateToken,
    async (req: Request, res: Response) => {
      const uid = userId(req);
      if (!uid) return res.status(401).json({ error: "Unauthorized" });
      const projectId = req.params.projectId;

      try {
        // Ownership check — 404 not 403, never leak existence.
        const project = await memoryService.projects.getProject(projectId);
        if (!project || project.userId !== uid) {
          return res.status(404).json({ error: "Project not found" });
        }

        // Gather context. loadProjectContext already returns the
        // recentWorkflows + recentEpisodes we need.
        const ctx = await memoryService.projects.loadProjectContext(projectId);

        const { system, user } = buildSynthesisPrompt({
          projectName: project.name,
          projectDescription: project.description ?? null,
          recentWorkflows: ctx.recentWorkflows ?? [],
          recentEpisodes: ctx.recentEpisodes ?? [],
        });

        let markdown: string;
        try {
          markdown = await callGeminiFlash({
            system,
            messages: [{ role: "user", content: user }],
            maxTokens: LLM_MAX_TOKENS,
            temperature: 0.2,
          });
        } catch (e: any) {
          console.error("[notes] LLM call failed:", e?.message ?? e);
          return res.status(502).json({ error: "LLM synthesis failed" });
        }

        if (!markdown || markdown.trim().length === 0) {
          return res.status(502).json({ error: "LLM returned empty content" });
        }

        const saved = await memoryService.projects.addProjectKnowledge({
          projectId,
          knowledgeType: NOTES_TYPE,
          title: `Project synthesis — ${new Date().toISOString().slice(0, 10)}`,
          content: markdown,
          source: "claude_inferred",
          relevanceScore: 1.0,
        } as any);

        return res.status(201).json({ note: saved });
      } catch (e: any) {
        console.error("[notes] refresh failed:", e?.message ?? e);
        return res.status(500).json({ error: "Failed to refresh notes" });
      }
    },
  );

  // ─── GET /api/projects/:projectId/notes ──────────────────────────────
  // Returns the latest notes_synthesis row for the project, or 404 if
  // none has been generated yet.
  app.get(
    "/api/projects/:projectId/notes",
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
          NOTES_TYPE,
        );
        if (!rows || rows.length === 0) {
          return res.status(404).json({ error: "No synthesis yet" });
        }

        // getProjectKnowledge orders by relevanceScore desc; for notes
        // every row has score=1.0, so resort by createdAt to surface
        // the freshest synthesis.
        const latest = [...rows].sort((a, b) => {
          const at = a.createdAt ? new Date(a.createdAt).getTime() : 0;
          const bt = b.createdAt ? new Date(b.createdAt).getTime() : 0;
          return bt - at;
        })[0];

        return res.json({ note: latest });
      } catch (e: any) {
        console.error("[notes] get failed:", e?.message ?? e);
        return res.status(500).json({ error: "Failed to fetch notes" });
      }
    },
  );
}
