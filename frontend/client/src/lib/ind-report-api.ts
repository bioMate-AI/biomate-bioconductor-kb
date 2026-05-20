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
