/**
 * Pure helpers for coldstart deep runId extraction.
 * Kept free of Playwright so vitest can lock API/DOM key shapes.
 */

/** Normalize GET /api/workflows/runs — server returns a bare array (not {runs}). */
export function normalizeRunsListResponse(body: unknown): any[] {
  if (Array.isArray(body)) return body;
  if (body && typeof body === "object") {
    const o = body as Record<string, unknown>;
    if (Array.isArray(o.runs)) return o.runs;
    if (Array.isArray(o.items)) return o.items;
    if (Array.isArray(o.data)) return o.data;
  }
  return [];
}

/** First usable run id from a runs-list row. */
export function pickRunIdFromRunRow(row: any): string | undefined {
  if (!row || typeof row !== "object") return undefined;
  const id = row.id ?? row.runId ?? row.run_id ?? row.execution_run_id;
  if (id == null || id === "") return undefined;
  return String(id);
}

/**
 * Pull runId from GET /api/sessions/:id payload.
 * Prefers message metadata (post-Confirm sync), then session.workflows backfill
 * (server fills workflow_id from execution_runs when workflows column is empty).
 */
export function pickRunIdFromSessionPayload(session: any): string | undefined {
  if (!session || typeof session !== "object") return undefined;

  const msgs: any[] = Array.isArray(session.messages) ? session.messages : [];
  for (const msg of [...msgs].reverse()) {
    const id =
      msg?.metadata?.runId ||
      msg?.metadata?.run_id ||
      msg?.metadata?.workflow?.run_id ||
      msg?.metadata?.workflow?.runId ||
      msg?.metadata?.workflow?.chain_run_id ||
      msg?.invocationId ||
      msg?.invocation_id;
    if (id) return String(id);
  }

  const workflows: any[] = Array.isArray(session.workflows) ? session.workflows : [];
  for (const wf of workflows) {
    const id = wf?.workflow_id || wf?.runId || wf?.run_id || wf?.id;
    if (id) return String(id);
  }

  return undefined;
}

/** Execute / chain / pipeline POST JSON bodies. */
export function pickRunIdFromExecuteResponse(body: any): string | undefined {
  if (!body || typeof body !== "object") return undefined;
  const id =
    body.runId ||
    body.run_id ||
    body.chain_run_id ||
    body.execution_run_id ||
    body.id;
  if (id == null || id === "") return undefined;
  return String(id);
}

/** Statuses where the harness should stop waiting for a new terminal transition. */
export function isHarnessTerminalStatus(status: string | null | undefined): boolean {
  if (!status) return false;
  // paused = QC / approval gate — run exists and is measurable; do not soft-timeout.
  return /completed|succeeded|failed|error|cancelled|canceled|interrupted|paused/i.test(status);
}
