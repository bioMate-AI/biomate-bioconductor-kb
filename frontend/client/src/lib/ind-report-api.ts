/**
 * Typed client for the IND Report feedback endpoints implemented in
 * backend/lib/galaxy/ai/drug_discovery/feedback_router.py.
 *
 * Auth: Bearer JWT (managed by the existing auth-context).
 * Per-org isolation: pass orgId — wrapper adds X-BioMate-Org-Id header.
 */

const API_BASE = ""; // same-origin (relative URLs)

function jwtHeader(): Record<string, string> {
  // The existing BioMate auth flow stores the JWT in localStorage
  const token = typeof window !== "undefined"
    ? localStorage.getItem("biomate-jwt") ?? ""
    : "";
  return token ? { Authorization: `Bearer ${token}` } : {};
}

function orgHeader(orgId?: string | null): Record<string, string> {
  return orgId ? { "X-BioMate-Org-Id": orgId } : {};
}

async function postJson<T>(
  path: string,
  body: unknown,
  orgId?: string | null,
): Promise<T> {
  const resp = await fetch(`${API_BASE}${path}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      ...jwtHeader(),
      ...orgHeader(orgId),
    },
    body: JSON.stringify(body),
  });
  if (!resp.ok) {
    const text = await resp.text().catch(() => "");
    throw new Error(`POST ${path} ${resp.status}: ${text}`);
  }
  return resp.json() as Promise<T>;
}

async function getJson<T>(path: string, orgId?: string | null): Promise<T> {
  const resp = await fetch(`${API_BASE}${path}`, {
    headers: { ...jwtHeader(), ...orgHeader(orgId) },
  });
  if (!resp.ok) {
    const text = await resp.text().catch(() => "");
    throw new Error(`GET ${path} ${resp.status}: ${text}`);
  }
  return resp.json() as Promise<T>;
}

// ---------------------------------------------------------------------------
// Customer-facing feedback endpoints (Appendix B)
// ---------------------------------------------------------------------------

export type RecordedResponse = {
  recorded: boolean;
  id?: string;
  reason?: string;
};

export type EditCapture = {
  paragraph_id: string;
  original: string;
  edited: string;
  section_type: string;
  structured_input?: string;
};

export function captureEdit(
  projectId: string,
  body: EditCapture,
  orgId?: string | null,
): Promise<RecordedResponse> {
  return postJson(
    `/api/ind-report/projects/${encodeURIComponent(projectId)}/edit`,
    body,
    orgId,
  );
}

export type DismissalReason =
  | "not_applicable"
  | "already_addressed"
  | "acceptable_risk"
  | "disagree";

export type DismissalCapture = {
  rule_id: string;
  section_type: string;
  reason: DismissalReason;
  free_text?: string;
  document_state_hash?: string;
};

export function captureDismissal(
  findingId: string,
  body: DismissalCapture,
  orgId?: string | null,
): Promise<RecordedResponse> {
  return postJson(
    `/api/ind-report/audit/${encodeURIComponent(findingId)}/dismiss`,
    body,
    orgId,
  );
}

export type CitationSuggestion = {
  guideline_id: string;
  rationale: string;
  document_only?: boolean;
};

export function suggestCitation(
  body: CitationSuggestion,
  orgId?: string | null,
): Promise<RecordedResponse & { queued_for_review?: boolean }> {
  return postJson("/api/ind-report/citations/suggest", body, orgId);
}

export type RegenerateRequest = {
  instruction?: string;
  before?: string;
  after?: string;
};

export function regenerateSection(
  sectionId: string,
  body: RegenerateRequest,
  orgId?: string | null,
): Promise<RecordedResponse> {
  return postJson(
    `/api/ind-report/sections/${encodeURIComponent(sectionId)}/regenerate`,
    body,
    orgId,
  );
}

// ---------------------------------------------------------------------------
// LLM streaming — for the Regenerate flow
//
// Backend emits phase + token SSE events while the local Qwen3-8B+LoRA
// produces a §2.6 paragraph. Callers should render the phase message in a
// progress banner ("Loading model…", "Drafting…", "Validating…") and append
// each token's text into the paragraph as it arrives.
// ---------------------------------------------------------------------------

export type LlmPhase =
  | "model_loading"
  | "model_ready"
  | "generating"
  | "validating"
  | "complete"
  | "error";

export type LlmStreamEvent =
  | { kind: "phase"; phase: LlmPhase; message?: string; load_seconds?: number; reason?: string; text?: string; length?: number }
  | { kind: "token"; text: string; total: number };

export type LlmStreamOptions = {
  section_type?: string;
  user_prompt?: string;
  system_prompt?: string;
  orgId?: string | null;
  signal?: AbortSignal;
};

/**
 * Stream LLM generation events from /api/regulatory/generate_stream.
 * Calls `onEvent` for each phase/token event; resolves when the stream closes.
 *
 * Usage:
 *   await streamGenerate({}, (e) => {
 *     if (e.kind === "phase") setStatus(e.message ?? e.phase);
 *     else if (e.kind === "token") appendToParagraph(e.text);
 *   });
 */
export async function streamGenerate(
  options: LlmStreamOptions,
  onEvent: (e: LlmStreamEvent) => void,
): Promise<void> {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (options.orgId) headers["X-BioMate-Org-Id"] = options.orgId;
  const resp = await fetch("/api/regulatory/generate_stream", {
    method: "POST",
    headers,
    body: JSON.stringify({
      section_type: options.section_type,
      user_prompt: options.user_prompt,
      system_prompt: options.system_prompt,
    }),
    signal: options.signal,
  });
  if (!resp.ok || !resp.body) {
    throw new Error(`generate_stream HTTP ${resp.status}`);
  }
  const reader = resp.body.getReader();
  const decoder = new TextDecoder();
  let buf = "";
  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    buf += decoder.decode(value, { stream: true });
    // SSE events are separated by blank line; each event has "event:" + "data:" lines
    let idx;
    while ((idx = buf.indexOf("\n\n")) !== -1) {
      const raw = buf.slice(0, idx);
      buf = buf.slice(idx + 2);
      let evt = "";
      let dat = "";
      for (const line of raw.split("\n")) {
        if (line.startsWith("event:")) evt = line.slice(6).trim();
        else if (line.startsWith("data:")) dat = line.slice(5).trim();
      }
      if (!evt || !dat) continue;
      try {
        const data = JSON.parse(dat);
        if (evt === "phase") {
          onEvent({ kind: "phase", phase: data.phase, ...data });
        } else if (evt === "token") {
          onEvent({ kind: "token", text: data.text ?? "", total: data.total ?? 0 });
        }
      } catch {
        // skip malformed event
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Active-adapter (for the "Active model" badge)
// ---------------------------------------------------------------------------

export type ActiveAdapter = {
  adapter_name: string;
  adapter_path: string;
  exists: boolean;
  customized_for: string | null;
  entitled: boolean;
};

export function getActiveAdapter(orgId?: string | null): Promise<ActiveAdapter> {
  return getJson("/api/regulatory/active_adapter", orgId);
}

// ---------------------------------------------------------------------------
// IND project registry — CRUD
// ---------------------------------------------------------------------------

export type IndProjectRow = {
  id: string;
  molecule: string;
  target: string;
  indication: string;
  sponsor: string;
  sponsor_id?: string;
  regions: string[];
  status: "draft" | "in_progress" | "signed" | "blocked";
  statusText?: string;
  created_at?: string;
};

export function listProjects(): Promise<{ projects: IndProjectRow[] }> {
  return getJson("/api/ind-report/projects");
}

export function createProject(
  body: Omit<IndProjectRow, "id" | "created_at" | "statusText"> & { id?: string; statusText?: string },
  orgId?: string | null,
): Promise<IndProjectRow> {
  return postJson("/api/ind-report/projects", body, orgId);
}

// ---------------------------------------------------------------------------
// Sign — 21 CFR Part 11 two-factor e-signature
// ---------------------------------------------------------------------------

export type SignRequest = {
  totp_code: string;
  signer_title: string;
  signer_creds: string;
  signature_scope: string;
  document_sha256: string;
  adapter_versions: Record<string, string>;
};

export type SignResponse = {
  signed: boolean;
  signature_id: string;
  signed_at: string;
  document_sha256_short: string;
};

export function signDocument(
  projectId: string,
  body: SignRequest,
  orgId?: string | null,
): Promise<SignResponse> {
  return postJson(
    `/api/ind-report/projects/${encodeURIComponent(projectId)}/sign`,
    body,
    orgId,
  );
}

/** Compute SHA-256 of a string (used to bind the signature to the doc body). */
export async function sha256Hex(input: string): Promise<string> {
  const enc = new TextEncoder().encode(input);
  const buf = await crypto.subtle.digest("SHA-256", enc);
  return Array.from(new Uint8Array(buf))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

// ---------------------------------------------------------------------------
// Markdown export
// ---------------------------------------------------------------------------

export type DocumentSection = {
  id: string;       // "2.6.1"
  title: string;
  body: string;
};

// ---------------------------------------------------------------------------
// Version history — P2-6 backend wiring
// ---------------------------------------------------------------------------

export type VersionRow = {
  version: number;
  created_at: string;
  document_sha256: string;
  document_sha256_short: string;
  adapter_versions: Record<string, string>;
  section_count: number;
  author: string;
  note?: string | null;
  org_id?: string;
};

export function listVersions(projectId: string): Promise<{
  project_id: string;
  count: number;
  versions: VersionRow[];
}> {
  return getJson(`/api/ind-report/projects/${encodeURIComponent(projectId)}/versions`);
}

export type SnapshotRequest = {
  document_sha256: string;
  adapter_versions: Record<string, string>;
  section_count: number;
  note?: string;
};

export function createSnapshot(
  projectId: string,
  body: SnapshotRequest,
  orgId?: string | null,
): Promise<VersionRow> {
  return postJson(
    `/api/ind-report/projects/${encodeURIComponent(projectId)}/snapshot`,
    body,
    orgId,
  );
}

/** Trigger a Markdown download of the IND module. */
export async function downloadMarkdown(
  projectId: string,
  sections: DocumentSection[],
): Promise<void> {
  const resp = await fetch(
    `/api/ind-report/projects/${encodeURIComponent(projectId)}/document.md`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ sections }),
    },
  );
  if (!resp.ok) throw new Error(`download HTTP ${resp.status}`);
  const blob = await resp.blob();
  const cd = resp.headers.get("content-disposition") || "";
  const m = cd.match(/filename="([^"]+)"/);
  const filename = m ? m[1] : `${projectId}_2.6.md`;
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}
