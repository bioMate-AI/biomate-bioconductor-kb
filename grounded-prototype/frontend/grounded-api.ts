// Typed API client for the Grounded Standards Assistant.
// Style matches frontend/client/src/lib/ai-assistant-api.ts: a base-path const
// plus thin fetch wrappers with an ok-check. Drop into client/src/lib/.

const API_BASE = "/api/grounded";

export interface GroundedSource {
  id: string;
  tier: "A" | "B" | "C" | "D";
  tier_label: string;
  title: string;
  citation: string;
  verified: boolean;
  locator: string | null;
}

export interface GroundedClaim {
  text: string;
  grounded: boolean;
  best_tier: string | null;
  sources: GroundedSource[];
}

export interface GroundedBoundary {
  question_fragment: string;
  reason: string;
  escalate_to: string[];
  suggested_questions: string[];
}

export interface GroundedIsolation {
  requesting_user: string;
  shared_sources_used: number;
  own_personal_sources_used: number;
  other_tenant_personal_blocked: number;
  unverified_demoted: number;
}

export interface GroundedAnswer {
  question: string;
  question_type: "rationale" | "normative" | "investigation" | "definition" | "unknown";
  grade: "high" | "moderate" | "low" | "not_established";
  summary: string;
  claims: GroundedClaim[];
  boundaries: GroundedBoundary[];
  isolation: GroundedIsolation | null;
}

/**
 * Ask a regulated-domain question. The requesting user/tenant is resolved
 * server-side from the auth session (never passed from the client) so the
 * isolation guarantee cannot be spoofed by the caller.
 */
export async function askGrounded(question: string): Promise<GroundedAnswer> {
  const res = await fetch(`${API_BASE}/answer`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    credentials: "include",
    body: JSON.stringify({ question }),
  });
  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(err.error || err.message || `Request failed (${res.status})`);
  }
  return res.json();
}
