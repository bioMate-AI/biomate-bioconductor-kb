/**
 * QC Evidence Tooltip — surfaces per-gate evidence (paper_ref, DOI,
 * provenance grade, what-the-paper-actually-says) on hover over a gate row.
 *
 * Data source: embedded at build time from frontend/client/src/data/
 * qc-evidence.ts (generated from backend/config/qc_evidence.yaml).
 * No API round-trip; no /api route needed.
 *
 * Provenance badges:
 *   GOLD   — verbatim from cited source
 *   SILVER — community convention; concept supported, exact cutoff not
 *   BRONZE — operational heuristic; cited paper is related context only
 *
 * Built as a standalone wrapping component so it can be opt-in adopted by
 * auto-loop-panel.tsx (or any future gate-display surface) without
 * touching protected files.
 */

import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from "@/components/ui/tooltip"
import { getEvidenceForGate, type QCEvidenceEntry } from "@/data/qc-evidence"

export type { QCEvidenceEntry }

interface ProvenanceBadgeProps {
  grade: "GOLD" | "SILVER" | "BRONZE"
}

function ProvenanceBadge({ grade }: ProvenanceBadgeProps) {
  const color =
    grade === "GOLD"
      ? "bg-yellow-100 text-yellow-900 border-yellow-300"
      : grade === "SILVER"
      ? "bg-gray-100 text-gray-800 border-gray-300"
      : "bg-orange-100 text-orange-900 border-orange-300"
  return (
    <span
      className={`inline-block rounded border px-1.5 py-0.5 text-[10px] font-semibold uppercase tracking-wide ${color}`}
      title={
        grade === "GOLD"
          ? "Verbatim from cited source or trivially derived"
          : grade === "SILVER"
          ? "Community convention; paper supports concept, not exact cutoff"
          : "Operational heuristic; cited paper is related context only — verify before use"
      }
    >
      {grade}
    </span>
  )
}

export interface QCEvidenceTooltipProps {
  /** Auto-loop domain (admet, docking, cyp_ddi, nca_pk, pbpk, structure_prediction) */
  domain: string
  /** Gate name from the autoloop_gate_results SSE event */
  gate: string
  /** The child wrapped — typically the gate row or label */
  children: React.ReactNode
}

/**
 * QCEvidenceTooltip — wrap any gate label/row to surface evidence on hover.
 *
 * Lazy-fetches on first hover (uses module-level cache after that).
 * Gracefully renders nothing extra when no evidence is registered for
 * the (domain, gate) pair.
 */
export function QCEvidenceTooltip({
  domain,
  gate,
  children,
}: QCEvidenceTooltipProps) {
  // Build-time embedded — no fetch, no loading state.
  const entries = getEvidenceForGate(domain, gate)

  return (
    <TooltipProvider>
      <Tooltip>
        <TooltipTrigger asChild>
          <span className="inline-flex cursor-help items-center gap-1 underline decoration-dotted underline-offset-2">
            {children}
          </span>
        </TooltipTrigger>
        <TooltipContent
          side="top"
          align="start"
          className="max-w-md whitespace-normal break-words bg-white p-3 text-left text-sm shadow-lg ring-1 ring-gray-200"
        >
          {entries.length === 0 ? (
            <div className="text-gray-500">
              No evidence registered for this gate.
            </div>
          ) : (
            <div className="space-y-3">
              {entries.map((e, idx) => (
                <div key={idx} className="space-y-1.5">
                  <div className="flex items-center gap-2">
                    <ProvenanceBadge grade={e.provenance} />
                    <a
                      href={e.paper_doi.startsWith("http") ? e.paper_doi : `https://doi.org/${e.paper_doi}`}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="text-xs font-medium text-blue-700 hover:underline"
                      onClick={(ev) => ev.stopPropagation()}
                    >
                      {e.paper_ref}
                    </a>
                  </div>
                  <div className="text-xs text-gray-800">
                    <span className="font-semibold text-gray-600">Rule applied:</span>{" "}
                    {e.rule_text}
                  </div>
                  <details className="text-xs text-gray-700">
                    <summary className="cursor-pointer text-gray-500 hover:text-gray-700">
                      What the source actually contains
                    </summary>
                    <div className="mt-1 border-l-2 border-gray-200 pl-2 text-gray-600">
                      {e.paper_supports}
                    </div>
                  </details>
                  {e.finding && (
                    <div className="text-xs italic text-gray-500">{e.finding}</div>
                  )}
                </div>
              ))}
              <div className="border-t border-gray-200 pt-2 text-[10px] text-gray-400">
                GOLD = verbatim from source · SILVER = community convention ·
                BRONZE = operational heuristic (verify before regulatory use)
              </div>
            </div>
          )}
        </TooltipContent>
      </Tooltip>
    </TooltipProvider>
  )
}
