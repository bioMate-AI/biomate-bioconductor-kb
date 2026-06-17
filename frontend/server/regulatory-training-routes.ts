/**
 * Lane B3 — Node-side routes for the per-org adapter retrain queue.
 *
 * Kept in its own file because edits to the multi-thousand-line routes.ts
 * regularly get clobbered in this multi-agent shared-worktree setup. The
 * registrar is mounted from routes.ts:1239:
 *
 *     const { registerRegulatoryTrainingRoutes } =
 *       await import("./regulatory-training-routes.js");
 *     registerRegulatoryTrainingRoutes(app);
 *
 * All routes shell out to the Python CLI at
 *   backend/lib/galaxy/ai/drug_discovery/regulatory_training_jobs_cli.py
 * so JSONL persistence + org-id sanitisation stay single-sourced.
 *
 * Routes:
 *   POST /api/regulatory_llm/training_jobs        — submit, 201 + queued job
 *   GET  /api/regulatory_llm/training_jobs        — list, owner-scoped
 *   GET  /api/regulatory_llm/training_jobs/:jobId — fetch, owner-scoped
 *   GET  /api/regulatory_llm/edit_pairs/count     — count org pairs available
 *   POST /api/regulatory_llm/training_jobs/tick   — dev-only drive worker once
 */
import type { Express } from "express";
import { authenticateToken } from "./auth-middleware";
import * as path from "path";
import { execFile } from "child_process";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Resolve the repo root from `<repo>/frontend/server/*.ts`
const REPO_ROOT = path.resolve(__dirname, "..", "..");
const PY_BIN =
  process.env.PYTHON_BIN ||
  path.join(REPO_ROOT, "backend", ".venv", "bin", "python");
const PY_CWD = path.join(REPO_ROOT, "backend");
const PY_ENV = {
  ...process.env,
  PYTHONPATH: path.join(REPO_ROOT, "backend", "lib"),
};

type CliResult = { stdout: string; stderr: string; code: number };

function runCli(args: string[]): Promise<CliResult> {
  return new Promise((resolve) => {
    execFile(
      PY_BIN,
      ["-m", "galaxy.ai.drug_discovery.regulatory_training_jobs_cli", ...args],
      { cwd: PY_CWD, env: PY_ENV, timeout: 10_000 },
      (err: any, stdout: string, stderr: string) => {
        resolve({
          stdout: String(stdout || ""),
          stderr: String(stderr || ""),
          code: err?.code ?? 0,
        });
      }
    );
  });
}

function runCliWithStdin(args: string[], stdin: string): Promise<CliResult> {
  return new Promise((resolve) => {
    const child = execFile(
      PY_BIN,
      ["-m", "galaxy.ai.drug_discovery.regulatory_training_jobs_cli", ...args],
      { cwd: PY_CWD, env: PY_ENV, timeout: 10_000 },
      (err: any, stdout: string, stderr: string) => {
        resolve({
          stdout: String(stdout || ""),
          stderr: String(stderr || ""),
          code: err?.code ?? 0,
        });
      }
    );
    if (child.stdin) {
      child.stdin.end(stdin);
    }
  });
}

function orgFor(u: any): string {
  // Real organization claim wins; otherwise fall back to the user's own id
  // so single-tenant users still get a per-user adapter slot.
  if (u?.organization && String(u.organization).trim()) {
    return String(u.organization).trim();
  }
  return String(u?.id ?? "");
}

export function registerRegulatoryTrainingRoutes(app: Express): void {
  app.post(
    "/api/regulatory_llm/training_jobs",
    authenticateToken,
    async (req: any, res) => {
      const userId = String(req.user?.id ?? "");
      const orgId = orgFor(req.user);
      if (!userId || !orgId) {
        return res.status(400).json({ error: "missing user/org" });
      }
      const r = await runCli(["submit", userId, orgId]);
      if (r.code !== 0) {
        const detail = r.stderr.trim() || r.stdout.trim() || "cli_error";
        return res.status(400).json({ error: "submit_failed", detail });
      }
      try {
        return res.status(201).json(JSON.parse(r.stdout));
      } catch {
        return res
          .status(500)
          .json({ error: "bad_cli_output", raw: r.stdout.slice(0, 500) });
      }
    }
  );

  app.get(
    "/api/regulatory_llm/training_jobs",
    authenticateToken,
    async (req: any, res) => {
      const userId = String(req.user?.id ?? "");
      const r = await runCli(["list", userId]);
      if (r.code !== 0) {
        return res
          .status(500)
          .json({ error: "list_failed", detail: r.stderr.trim() });
      }
      try {
        return res.json(JSON.parse(r.stdout));
      } catch {
        return res.status(500).json({ error: "bad_cli_output" });
      }
    }
  );

  app.get(
    "/api/regulatory_llm/training_jobs/:jobId",
    authenticateToken,
    async (req: any, res) => {
      const r = await runCli(["get", String(req.params.jobId)]);
      if (r.code !== 0) {
        return res
          .status(500)
          .json({ error: "get_failed", detail: r.stderr.trim() });
      }
      const body = JSON.parse(r.stdout || "null");
      if (!body) return res.status(404).json({ error: "job_not_found" });
      // Owner-scope: don't leak other users' jobs
      if (String(body.user_id) !== String(req.user?.id ?? "")) {
        return res.status(404).json({ error: "job_not_found" });
      }
      return res.json(body);
    }
  );

  app.get(
    "/api/regulatory_llm/edit_pairs/count",
    authenticateToken,
    async (req: any, res) => {
      const orgId = orgFor(req.user);
      const r = await runCli(["count_pairs", orgId]);
      if (r.code !== 0) {
        return res
          .status(500)
          .json({ error: "count_failed", detail: r.stderr.trim() });
      }
      try {
        return res.json(JSON.parse(r.stdout));
      } catch {
        return res.status(500).json({ error: "bad_cli_output" });
      }
    }
  );

  // Dev-only: explicitly drive the stub worker for the current user's
  // queued jobs. Production runs `regulatory_training_worker.run_forever`
  // as a long-lived process; this route lets the UI demonstrate the queue
  // lifecycle without waiting for a polling loop. Owner-scoped.
  app.post(
    "/api/regulatory_llm/training_jobs/tick",
    authenticateToken,
    async (req: any, res) => {
      const userId = String(req.user?.id ?? "");
      if (!userId) return res.status(400).json({ error: "missing user" });
      const r = await runCli(["tick", "1"]);
      if (r.code !== 0) {
        return res
          .status(500)
          .json({ error: "tick_failed", detail: r.stderr.trim() });
      }
      let done: any[];
      try {
        done = JSON.parse(r.stdout);
      } catch {
        return res.status(500).json({ error: "bad_cli_output" });
      }
      return res.json(
        Array.isArray(done) ? done.filter((j: any) => j.user_id === userId) : []
      );
    }
  );

  // ─── B3 upstream: record a customer feedback pair ──────────────────────
  // POST /api/regulatory_llm/pairs
  // Body: {chosen, rejected, section_type?, task?, prompt?, meta?}
  // org_id is stamped server-side from req.user (Node never trusts a
  // client-supplied org_id here — the user can only record pairs for
  // their own org).
  app.post(
    "/api/regulatory_llm/pairs",
    authenticateToken,
    async (req: any, res) => {
      const userId = String(req.user?.id ?? "");
      const orgId = orgFor(req.user);
      if (!userId || !orgId) {
        return res.status(400).json({ error: "missing user/org" });
      }
      const body = req.body ?? {};
      const chosen = String(body.chosen ?? "");
      const rejected = String(body.rejected ?? "");
      if (!chosen && !rejected) {
        return res
          .status(400)
          .json({ error: "missing_chosen_or_rejected" });
      }
      const cliBody = {
        chosen,
        rejected,
        section_type: body.section_type ?? "",
        task: body.task ?? "",
        prompt: body.prompt ?? "",
        meta: body.meta && typeof body.meta === "object" ? body.meta : undefined,
      };
      const r = await runCliWithStdin(
        ["record_pair", userId, orgId],
        JSON.stringify(cliBody)
      );
      if (r.code !== 0) {
        const detail = r.stderr.trim() || r.stdout.trim() || "cli_error";
        return res.status(400).json({ error: "record_failed", detail });
      }
      try {
        return res.status(201).json(JSON.parse(r.stdout));
      } catch {
        return res
          .status(500)
          .json({ error: "bad_cli_output", raw: r.stdout.slice(0, 500) });
      }
    }
  );
}
