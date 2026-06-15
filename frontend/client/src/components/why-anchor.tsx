/**
 * <WhyAnchor> — the "(why?)" hover anchor on bioc chain chat lines.
 *
 * Plan reference: docs/20260614_RATIONALE_ANCHOR_PLAN.md §4.
 *
 * Behaviour:
 *   - Renders nothing visually until a workflowName + phaseId are both supplied.
 *   - Fetches GET /api/workflows/:name/phases/:phaseId/rationale lazily on
 *     first hover (not on mount — keeps cold render cheap).
 *   - Endpoint returns {} when no curated row exists; in that case the
 *     anchor renders nothing (no broken `(why?)` link with empty popover).
 *   - Popover content: rationale_text + a footer with citation (doi → link
 *     if present, plain text otherwise).
 *
 * The (why?) text is the canonical design label from the bioc handoff
 * prototype. Reuses ui/popover.tsx, no new primitives authored.
 */
import { useState, useCallback } from "react"
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover"

export interface Rationale {
  workflow_id: number
  phase_id: string
  rationale_text: string
  citation: { doi?: string | null; title?: string | null } | null
  qc_gate_name?: string | null
  last_curated_at?: number | null
}

interface Props {
  /** Design-faithful path: explicit per-event id (e.g. 'bulk_rnaseq:B'). */
  rationaleId?: string | null
  /** Legacy path: derive from chain + phase. Used only if rationaleId absent. */
  workflowName?: string | null
  phaseId?: string | null
  /** Optional override for testing — skip fetch + use this rationale directly. */
  rationale?: Rationale | null
  /** Optional fetch override for testing. */
  fetchFn?: (workflowName: string, phaseId: string) => Promise<Rationale | null>
}

/** Default fetcher: chooses the right URL per id type, returns null on empty / error. */
async function defaultFetchRationale(
  workflowName: string,
  phaseId: string,
): Promise<Rationale | null> {
  // Sentinel "rationaleId" is passed as workflowName when rationaleId path
  // is taken (see handleOpenChange below); detect by leading colon-prefix
  // marker the caller stamps in.
  const isRationaleId = workflowName.startsWith("__rid__:")
  const url = isRationaleId
    ? `/api/rationale/${encodeURIComponent(workflowName.slice("__rid__:".length))}`
    : `/api/workflows/${encodeURIComponent(workflowName)}/phases/${encodeURIComponent(phaseId)}/rationale`
  try {
    const r = await fetch(url, { credentials: "include" })
    if (!r.ok) return null
    const body = (await r.json()) as Partial<Rationale>
    if (!body || !body.rationale_text) return null
    return body as Rationale
  } catch {
    return null
  }
}

export function WhyAnchor({ rationaleId, workflowName, phaseId, rationale: rationaleProp, fetchFn }: Props) {
  const [rationale, setRationale] = useState<Rationale | null | undefined>(
    rationaleProp ?? undefined,
  )
  // undefined = not loaded yet, null = loaded-but-empty (hide anchor),
  // object = loaded with content

  // Resolve fetch args: explicit rationaleId (Phase 2 design-faithful path)
  // takes precedence over legacy workflowName + phaseId.
  const fetchKey1 = rationaleId ? `__rid__:${rationaleId}` : workflowName ?? ""
  const fetchKey2 = rationaleId ? "" : phaseId ?? ""
  const hasContext = Boolean(rationaleId) || Boolean(workflowName && phaseId)

  const handleOpenChange = useCallback(
    async (open: boolean) => {
      if (!open) return
      if (rationale !== undefined) return // already loaded
      if (!hasContext) return
      const fetcher = fetchFn ?? defaultFetchRationale
      const result = await fetcher(fetchKey1, fetchKey2)
      setRationale(result ?? null)
    },
    [rationale, hasContext, fetchKey1, fetchKey2, fetchFn],
  )

  // No context → no anchor at all.
  if (!hasContext) return null
  // Loaded and empty → hide the anchor (don't show a broken popover).
  if (rationale === null) return null

  // Stable testid that's a valid CSS selector value (no colons).
  const labelId = rationaleId ?? phaseId ?? "unknown"
  const safeTestId = labelId.replace(/:/g, "-")

  return (
    <Popover onOpenChange={handleOpenChange}>
      <PopoverTrigger asChild>
        <button
          type="button"
          className="ml-1 text-xs text-muted-foreground underline-offset-2 hover:underline focus:outline-none focus-visible:ring-1"
          aria-label={`Show rationale for ${labelId}`}
          data-testid={`why-anchor-${safeTestId}`}
        >
          (why?)
        </button>
      </PopoverTrigger>
      <PopoverContent className="w-80 text-sm" align="start">
        {rationale === undefined ? (
          <div className="text-muted-foreground">Loading rationale…</div>
        ) : (
          <div className="space-y-2">
            <div className="text-foreground leading-relaxed">{rationale.rationale_text}</div>
            {rationale.citation ? (
              <div className="border-t pt-2 text-xs text-muted-foreground">
                {rationale.citation.doi ? (
                  <a
                    href={
                      rationale.citation.doi.startsWith("http")
                        ? rationale.citation.doi
                        : `https://doi.org/${rationale.citation.doi}`
                    }
                    target="_blank"
                    rel="noopener noreferrer"
                    className="underline hover:no-underline"
                  >
                    {rationale.citation.title || rationale.citation.doi}
                  </a>
                ) : (
                  <span>{rationale.citation.title}</span>
                )}
              </div>
            ) : null}
          </div>
        )}
      </PopoverContent>
    </Popover>
  )
}
