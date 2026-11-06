/**
 * HitGrid — ranked chemical hits from a scoring / ADMET model.
 *
 * Two views over the same hit list:
 *   table — sortable columns (score, hERG, confidence, verdict)
 *   grid  — a 2D-depiction card grid. No client-side SMILES renderer exists in
 *           the app, so the depiction slot is a placeholder box keyed to the
 *           SMILES (the honest slot names what goes there rather than faking a
 *           drawing).
 *
 * Verdict colour: accepted (green) / flagged (amber) / rejected (red) /
 * held (grey). A "held" hit is outside the model's applicability region, so it
 * shows NO confident number — the score is suppressed and the row is greyed.
 *
 * Every score names the model behind it (a link stub, wired via onOpenModel).
 *
 * Pure presentational — all data via props.
 */

import { useState } from "react"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { ChevronsUpDown, FlaskConical } from "lucide-react"

// ---------------------------------------------------------------------------
// Types (data contract)
// ---------------------------------------------------------------------------

export type HitVerdict = "accepted" | "flagged" | "rejected" | "held"

export interface ChemHit {
  id: string
  smiles: string
  /** Null for a held / out-of-domain hit: no confident number. Never coerce to
   * 0 — that would silently rank an unscored compound as the worst real score. */
  score: number | null
  /** e.g. "high" | "medium" | "low" | "out-of-domain". */
  confidence: string
  herg: string
  drugLike: string
  verdict: HitVerdict
}

export interface HitGridProps {
  hits: ChemHit[]
  /** Model that produced the scores, shown as a link stub. */
  modelName?: string
  /** Fired when the model link is clicked (opens the model object). */
  onOpenModel?: (modelId: string) => void
  modelId?: string
  className?: string
}

type SortKey = "id" | "score" | "confidence" | "verdict"

// ---------------------------------------------------------------------------
// Verdict styling
// ---------------------------------------------------------------------------

// Colours source the ported reference design tokens (styles/reference-design.css
// → --ok/--warn/--err/--text-dim) instead of hardcoded hex, so verdict styling
// stays 1:1 with the reference and tracks the theme (incl. dark mode).
const VERDICT_STYLE: Record<HitVerdict, { color: string; ring: string }> = {
  accepted: { color: "var(--ok)",       ring: "border-l-green-500" },
  flagged:  { color: "var(--warn)",     ring: "border-l-amber-500" },
  rejected: { color: "var(--err)",      ring: "border-l-red-500" },
  held:     { color: "var(--text-dim)", ring: "border-l-slate-400" },
}

/** A "held" hit is out-of-domain: no confident number is offered. */
function isHeld(h: ChemHit): boolean {
  return h.verdict === "held" || h.confidence === "out-of-domain"
}

function VerdictChip({ verdict }: { verdict: HitVerdict }) {
  const s = VERDICT_STYLE[verdict]
  return (
    <Badge variant="outline" className="text-[10px] gap-1" style={{ color: s.color }}>
      <span className="inline-block h-1.5 w-1.5 rounded-full" style={{ background: s.color }} />
      {verdict}
    </Badge>
  )
}

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

export function HitGrid({ hits, modelName = "admet-herg v3", modelId = "admet-herg", onOpenModel, className }: HitGridProps) {
  const [view, setView] = useState<"table" | "grid">("table")
  const [sortKey, setSortKey] = useState<SortKey>("score")
  const [asc, setAsc] = useState(false)

  const sorted = [...hits].sort((a, b) => {
    if (sortKey === "score") {
      // Unscored (held/out-of-domain) hits sort to the END regardless of
      // direction — they carry no number, so they are never "better" or "worse".
      const an = a.score === null
      const bn = b.score === null
      if (an && bn) return 0
      if (an) return 1
      if (bn) return -1
      const cmp = (a.score as number) - (b.score as number)
      return asc ? cmp : -cmp
    }
    const cmp = String(a[sortKey]).localeCompare(String(b[sortKey]))
    return asc ? cmp : -cmp
  })

  const toggleSort = (key: SortKey) => {
    if (key === sortKey) setAsc(a => !a)
    else { setSortKey(key); setAsc(false) }
  }

  const heldHits = hits.filter(isHeld)

  return (
    <Card className={className} data-testid="hit-grid">
      <CardHeader className="pb-2">
        <div className="flex items-center justify-between gap-2 flex-wrap">
          <CardTitle className="flex items-center gap-2 text-sm">
            <FlaskConical className="h-4 w-4" />
            Ranked hits
          </CardTitle>
          <div className="flex items-center gap-1">
            {(["table", "grid"] as const).map(v => (
              <Button
                key={v}
                variant={view === v ? "default" : "outline"}
                size="sm"
                className="h-7 text-xs px-2"
                data-testid={`hit-view-${v}`}
                onClick={() => setView(v)}
              >
                {v === "table" ? "Table" : "Depictions"}
              </Button>
            ))}
          </div>
        </div>
      </CardHeader>

      <CardContent className="space-y-2">
        {view === "table" ? (
          <div className="overflow-auto rounded border text-xs" data-testid="hit-table">
            <table className="min-w-full">
              <thead className="bg-muted">
                <tr>
                  {([
                    ["id", "Candidate"],
                    ["score", "Score"],
                    ["confidence", "Confidence"],
                  ] as [SortKey, string][]).map(([key, label]) => (
                    <th
                      key={key}
                      className="px-2 py-1 text-left font-semibold cursor-pointer select-none whitespace-nowrap"
                      onClick={() => toggleSort(key)}
                      data-testid={`hit-sort-${key}`}
                    >
                      <span className="inline-flex items-center gap-0.5">
                        {label}
                        <ChevronsUpDown className="h-3 w-3 opacity-50" />
                      </span>
                    </th>
                  ))}
                  <th className="px-2 py-1 text-left font-semibold whitespace-nowrap">hERG</th>
                  <th className="px-2 py-1 text-left font-semibold whitespace-nowrap">Drug-like</th>
                  <th
                    className="px-2 py-1 text-left font-semibold cursor-pointer select-none whitespace-nowrap"
                    onClick={() => toggleSort("verdict")}
                    data-testid="hit-sort-verdict"
                  >
                    Verdict
                  </th>
                </tr>
              </thead>
              <tbody>
                {sorted.map(h => {
                  const held = isHeld(h)
                  return (
                    <tr
                      key={h.id}
                      data-testid={`hit-row-${h.id}`}
                      className={`border-b last:border-0 hover:bg-muted/40 ${held ? "opacity-60" : ""}`}
                    >
                      <td className="px-2 py-1 font-mono font-semibold whitespace-nowrap">{h.id}</td>
                      <td className="px-2 py-1 font-mono" data-testid={`hit-score-${h.id}`}>
                        {held ? <span className="text-muted-foreground italic">held</span> : (h.score ?? "—")}
                      </td>
                      <td className="px-2 py-1">
                        <span className="capitalize">{h.confidence}</span>
                      </td>
                      <td className="px-2 py-1 font-mono">{h.herg}</td>
                      <td className="px-2 py-1">{h.drugLike}</td>
                      <td className="px-2 py-1"><VerdictChip verdict={h.verdict} /></td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
        ) : (
          <div className="grid grid-cols-2 sm:grid-cols-3 gap-2" data-testid="hit-depictions">
            {sorted.map(h => {
              const held = isHeld(h)
              return (
                <div
                  key={h.id}
                  data-testid={`hit-card-${h.id}`}
                  className={`rounded border border-l-4 ${VERDICT_STYLE[h.verdict].ring} p-2 space-y-1 ${held ? "opacity-60" : ""}`}
                >
                  {/* 2D depiction slot — keyed to SMILES, renders server-side */}
                  <div
                    className="rounded border bg-muted/40 aspect-square flex flex-col items-center justify-center p-1 text-center"
                    data-testid={`hit-depiction-${h.id}`}
                    title={h.smiles}
                  >
                    <span className="text-[9px] uppercase tracking-wide text-muted-foreground">2D depiction</span>
                    <span className="text-[9px] font-mono break-all leading-tight mt-0.5 line-clamp-3">{h.smiles}</span>
                  </div>
                  <div className="flex items-center justify-between gap-1">
                    <span className="text-[11px] font-mono font-semibold">{h.id}</span>
                    <span className="text-[11px] font-mono" data-testid={`hit-card-score-${h.id}`}>
                      {held ? <span className="text-muted-foreground italic">held</span> : (h.score ?? "—")}
                    </span>
                  </div>
                  <div className="flex items-center gap-1 flex-wrap">
                    <VerdictChip verdict={h.verdict} />
                    {h.confidence === "out-of-domain" && (
                      <Badge variant="outline" className="text-[10px]" style={{ color: "var(--warn)" }}>
                        out-of-domain
                      </Badge>
                    )}
                  </div>
                </div>
              )
            })}
          </div>
        )}

        {/* Model attribution + held explanation */}
        <div className="flex items-center gap-2 flex-wrap pt-1 border-t">
          <span className="text-[10px] text-muted-foreground">Every score names the model behind it.</span>
          <button
            type="button"
            className="text-[10px] text-primary hover:underline"
            data-testid="hit-model-link"
            onClick={() => onOpenModel?.(modelId)}
          >
            {modelName} →
          </button>
          {heldHits.length > 0 && (
            <span className="text-[10px] text-muted-foreground" data-testid="hit-held-note">
              {heldHits.map(h => h.id).join(", ")}{" "}
              {heldHits.length === 1 ? "is" : "are"} held: outside the model's applicability
              region, so no confident number is offered.
            </span>
          )}
        </div>
      </CardContent>
    </Card>
  )
}
