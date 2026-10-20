/**
 * Structured user corrections (B1).
 *
 * BioMate already has the correction backend AND a LIVE prompt injection:
 *   - POST /api/memory/user/corrections  -> correction_log (memory-repository.ts)
 *   - galaxy-assistant.ts::_buildCorrectionContextBlock reads getUserCorrections(userId, 5)
 *     and injects "Prefer <to> over <from>" into the next-turn system prompt.
 * The missing wire was that NO UI ever POSTed a correction. This module is that wire.
 *
 * The cleanest NON-FABRICATED correction signal in the UI is the workflow
 * disambiguation card: the backend presents scored candidates because it could not
 * confidently pick one, and marks its own best guess as the highest-`score`
 * candidate. When the user chooses a DIFFERENT candidate than that best guess, that
 * is a genuine routing correction (suggested = top-scored, corrected = chosen) —
 * no value is invented. Choosing the top-scored candidate is NOT a correction.
 *
 * Payload fields mirror correction_log (frontend/shared/ltm-schema.ts) and the
 * `{ workflow }` shape `_buildCorrectionContextBlock` reads, so the injection
 * renders "Prefer <chosen> over <top>".
 */

export interface CorrectionApproach {
  /** workflow/tool name — the field _buildCorrectionContextBlock prefers */
  workflow?: string;
  tool?: string;
  [k: string]: unknown;
}

export interface CorrectionPayload {
  sessionId?: string;
  projectId?: string;
  suggestedApproach: CorrectionApproach;
  correctedApproach: CorrectionApproach;
  workflowContext?: Record<string, unknown>;
  userExplanation?: string;
}

export interface CorrectionResponse {
  success: boolean;
  error?: string;
}

interface DisambigCandidateLike {
  name: string;
  display_name?: string;
  score?: number;
  source?: string;
}

/**
 * Build a correction from a disambiguation selection, or null when it is not a
 * correction (chose the top-scored candidate, or no usable baseline exists).
 * Pure + deterministic so it is unit-testable without a DOM or network.
 */
export function buildDisambiguationCorrection(
  candidates: DisambigCandidateLike[] | undefined,
  chosen: DisambigCandidateLike,
  opts: { sessionId?: string; projectId?: string } = {},
): CorrectionPayload | null {
  if (!chosen?.name || !Array.isArray(candidates) || candidates.length < 2) return null;
  // the system's own best guess = highest score (ties broken by first occurrence)
  const top = candidates.reduce((best, c) =>
    (c.score ?? -Infinity) > (best.score ?? -Infinity) ? c : best, candidates[0]);
  if (!top?.name || top.name === chosen.name) return null;  // chose the suggestion => no correction

  return {
    sessionId: opts.sessionId,
    projectId: opts.projectId,
    suggestedApproach: { workflow: top.display_name || top.name, source: top.source },
    correctedApproach: { workflow: chosen.display_name || chosen.name, source: chosen.source },
    workflowContext: {
      origin: 'disambiguation',
      candidates: candidates.map(c => ({ name: c.name, score: c.score })),
    },
    userExplanation: 'Chose a different workflow than the highest-ranked suggestion',
  };
}

/** POST a structured correction. Error-tolerant: never throws into the UI path. */
export async function submitCorrection(payload: CorrectionPayload): Promise<CorrectionResponse> {
  try {
    const response = await fetch('/api/memory/user/corrections', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      credentials: 'include',
      body: JSON.stringify(payload),
    });
    if (!response.ok) {
      const err = await response.json().catch(() => ({ message: response.statusText }));
      return { success: false, error: err.message || err.error || 'Failed to submit correction' };
    }
    return { success: true };
  } catch (e) {
    return { success: false, error: e instanceof Error ? e.message : 'network error' };
  }
}
