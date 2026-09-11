/**
 * DesignGenerate — the Spec 05 "Design & generate" surface.
 *
 * De-novo molecular design as ONE pipeline (Spec 05 §5.1):
 *   generate -> predict activity -> optimise properties -> rank candidates.
 *
 * It wraps the wave-1 backend (POST /api/generate, GET /api/generate/{id}) and
 * the wave-1 HitGrid viewer, and holds the line on the four Spec-05 design
 * commitments:
 *
 *   1. The constraints ARE the interface (§5.2) — target, scaffold policy,
 *      property envelope, exclusions, count+cost are the composer, resolved
 *      before the run and shown as parameters.
 *
 *   2. NO composite score (§5.4 rule) — the multi-objective view shows each
 *      objective in ITS OWN UNITS against its own target; there is no single
 *      blended number. HitGrid's `score` is a ranking key only, and it is
 *      labelled as such next to the per-objective breakdown.
 *
 *   3. Safety is a GATE, not an objective (§5.4) — a rejected candidate stays
 *      VISIBLE with the gate that rejected it. Rejected candidates are NEVER
 *      filtered out: they appear in HitGrid (verdict "rejected") and in a
 *      dedicated, collapsible rejected-set panel naming each gate reason.
 *
 *   4. Honest failure profile (§5.8/§5.9) — when the run produces no
 *      candidates, the backend's reason/notes are shown rather than an empty
 *      pane; "held" (out-of-domain) candidates carry no confident number.
 *
 * Pure/typed and presentational: data comes from the backend; the component
 * owns only form state and the poll loop. No science is fabricated here.
 */

import React, { useState, useCallback, useRef, useEffect, useMemo } from "react"
import { useLocation } from "wouter"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import {
  Collapsible,
  CollapsibleContent,
  CollapsibleTrigger,
} from "@/components/ui/collapsible"
import { HitGrid, type ChemHit, type HitVerdict } from "@/components/viewers/hit-grid"
import {
  Play,
  ChevronDown,
  ShieldAlert,
  Target,
  GitCompare,
  SlidersHorizontal,
  Info,
  Download,
  Boxes,
  Search as SearchIcon,
  FlaskConical,
} from "lucide-react"

// ---------------------------------------------------------------------------
// Backend data contract (mirrors backend/.../api/generation.py schemas)
// ---------------------------------------------------------------------------

export interface ObjectiveValue {
  name: string
  value: number
  unit: string
  target?: number | null
  direction: string // 'maximize' | 'minimize'
}

export interface GenCandidate {
  id: string
  smiles: string
  score: number // ranking key ONLY — never "the one number"
  confidence: string
  herg: string
  drugLike: string
  verdict: string // 'accepted' | 'flagged' | 'rejected' | 'held'
  objectives: ObjectiveValue[]
}

export interface RejectedCandidate {
  id: string
  smiles: string
  reason: string
  objectives: ObjectiveValue[]
}

export interface GenObjectiveMeta {
  name: string
  unit: string
  direction: string
}

export interface GenerationRun {
  run_id: string
  status: string // 'running' | 'completed' | 'failed'
  candidates?: GenCandidate[]
  rejected?: RejectedCandidate[]
  pareto?: string[]
  generator?: string
  generator_is_learned?: boolean
  n_generated?: number
  n_scored?: number
  objectives?: GenObjectiveMeta[]
  notes?: string[]
}

/** A measured result returned from the bench for one candidate (§5.7). Supplied
 *  as an optional prop — this component renders it against the run's predictions;
 *  it does NOT run the wet-lab loop or the refit (that is Spec 03 §3.7). Values
 *  are per-objective, in the objective's own units. */
export interface MeasuredObjective {
  name: string
  value: number
  unit: string
}

export interface MeasuredResult {
  id: string // candidate id (must match a GenCandidate.id)
  registryId?: string // the lab's own registry id, if paired back on return
  measured: MeasuredObjective[]
}

export interface PropertyEnvelopeInput {
  mw_max?: number
  logp_max?: number
  tpsa_max?: number
  rot_bonds_max?: number
}

export interface GenerateRequestBody {
  generator: string
  // v2 §11: chemical modality the design run targets.
  modality?: string
  constraints: {
    seed_smiles?: string
    target_protein_pdb?: string
    scaffold_policy: string
    property_envelope: PropertyEnvelopeInput
    exclusions: string[]
  }
  objectives: string[]
  seed_series: string[]
  count: number
  n_generate: number
}

// The client is injectable so the component is testable without a network.
export type GenerateClient = {
  start: (body: GenerateRequestBody) => Promise<{ run_id: string; status: string }>
  poll: (runId: string) => Promise<GenerationRun>
}

const defaultClient: GenerateClient = {
  async start(body) {
    const r = await fetch("/api/generate", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    })
    if (!r.ok) throw new Error(`start failed: ${r.status}`)
    return r.json()
  },
  async poll(runId) {
    const r = await fetch(`/api/generate/${runId}`)
    if (!r.ok) throw new Error(`poll failed: ${r.status}`)
    return r.json()
  },
}

// ---------------------------------------------------------------------------
// Constraint form state
// ---------------------------------------------------------------------------

const SCAFFOLD_POLICIES = ["stay", "hop", "grow"] as const
type ScaffoldPolicy = (typeof SCAFFOLD_POLICIES)[number]

// A crude, TRANSPARENT compute-cost hint — count is stated with cost shown
// before the run (§5.2). This is a UI heuristic, not a billing figure.
function estimateCost(count: number, nGenerate: number): string {
  const units = Math.max(1, Math.round((nGenerate + count) / 50))
  return `~${units} compute unit${units === 1 ? "" : "s"}`
}

// ---------------------------------------------------------------------------
// Mapping backend candidates -> HitGrid hits (verdict-preserving)
// ---------------------------------------------------------------------------

const KNOWN_VERDICTS: HitVerdict[] = ["accepted", "flagged", "rejected", "held"]

function toHit(c: GenCandidate): ChemHit {
  const verdict: HitVerdict = KNOWN_VERDICTS.includes(c.verdict as HitVerdict)
    ? (c.verdict as HitVerdict)
    : "flagged"
  return {
    id: c.id,
    smiles: c.smiles,
    score: c.score,
    confidence: c.confidence,
    herg: c.herg,
    drugLike: c.drugLike,
    verdict,
  }
}

// ---------------------------------------------------------------------------
// Multi-objective view — each objective in its own units, NO composite score
// ---------------------------------------------------------------------------

function ObjectiveCell({ o }: { o: ObjectiveValue }) {
  const meetsTarget =
    o.target == null
      ? null
      : o.direction === "maximize"
        ? o.value >= o.target
        : o.value <= o.target
  const color = meetsTarget == null ? "#64748b" : meetsTarget ? "#22c55e" : "#f59e0b"
  return (
    <td className="px-2 py-1 font-mono whitespace-nowrap" data-testid={`obj-${o.name}`}>
      <span style={{ color }}>{o.value}</span>
      <span className="text-[10px] text-muted-foreground ml-1">{o.unit}</span>
      {o.target != null && (
        <span className="text-[10px] text-muted-foreground ml-1">
          ({o.direction === "maximize" ? "≥" : "≤"} {o.target})
        </span>
      )}
    </td>
  )
}

/** Per-row "why?" drill-in (§5.3/§5.5): the model + version + confidence behind
 *  the row, and the nearest-analogue rationale. Uses only data that actually
 *  arrives — where the backend carries no nearest measured analogue, it says so
 *  honestly rather than inventing one. */
function WhyRow({
  candidate,
  colSpan,
  provenance,
}: {
  candidate: GenCandidate
  colSpan: number
  provenance: WhyProvenance
}) {
  return (
    <tr data-testid={`why-detail-${candidate.id}`} className="bg-muted/30">
      <td colSpan={colSpan} className="px-3 py-2">
        <div className="space-y-1 text-[11px]">
          <div className="flex items-center gap-2 flex-wrap">
            <span className="font-semibold">Model</span>
            <span className="font-mono">{provenance.model}</span>
            <span className="text-muted-foreground">·</span>
            <span className="font-semibold">Version</span>
            <span className="font-mono" data-testid={`why-version-${candidate.id}`}>
              {provenance.version}
            </span>
            <span className="text-muted-foreground">·</span>
            <span className="font-semibold">Confidence</span>
            <span className="font-mono capitalize" data-testid={`why-confidence-${candidate.id}`}>
              {candidate.confidence}
            </span>
          </div>
          <div>
            <span className="font-semibold">What drove it: </span>
            <span className="text-muted-foreground">
              {candidate.objectives.length > 0
                ? candidate.objectives
                    .map((o) => `${o.name} ${o.value} ${o.unit}${o.target != null ? ` (${o.direction === "maximize" ? "≥" : "≤"} ${o.target})` : ""}`)
                    .join("; ")
                : "no per-objective values available"}
            </span>
          </div>
          <div data-testid={`why-analogue-${candidate.id}`}>
            <span className="font-semibold">Nearest measured analogue: </span>
            <span className="text-muted-foreground italic">{provenance.nearestAnalogue}</span>
          </div>
          {candidate.verdict === "held" && (
            <div className="text-amber-600">
              Held — outside the model&apos;s applicability region; ranked nowhere and offered no
              confident number.
            </div>
          )}
        </div>
      </td>
    </tr>
  )
}

interface WhyProvenance {
  model: string
  version: string
  nearestAnalogue: string
}

function MultiObjectiveView({
  candidates,
  objectiveMeta,
  provenance,
}: {
  candidates: GenCandidate[]
  objectiveMeta: GenObjectiveMeta[]
  provenance: WhyProvenance
}) {
  const [openWhy, setOpenWhy] = useState<Record<string, boolean>>({})
  const names = objectiveMeta.map((m) => m.name)
  const colCount = 1 + objectiveMeta.length + 3 // candidate + objectives + score + verdict + why
  return (
    <Card data-testid="multi-objective-view">
      <CardHeader className="pb-2">
        <CardTitle className="text-sm flex items-center gap-2">
          <Target className="h-4 w-4" />
          Multi-objective view
        </CardTitle>
        <p className="text-[10px] text-muted-foreground">
          Each objective keeps its own units and its own target — no single blended
          number. The <span className="font-mono">score</span> column ranks only.
        </p>
      </CardHeader>
      <CardContent>
        <div className="overflow-auto rounded border text-xs">
          <table className="min-w-full">
            <thead className="bg-muted">
              <tr>
                <th className="px-2 py-1 text-left font-semibold">Candidate</th>
                {objectiveMeta.map((m) => (
                  <th key={m.name} className="px-2 py-1 text-left font-semibold whitespace-nowrap">
                    {m.name}
                    <span className="text-[10px] text-muted-foreground ml-1">/{m.unit}</span>
                  </th>
                ))}
                <th className="px-2 py-1 text-left font-semibold" title="Ranking key only">
                  score*
                </th>
                <th className="px-2 py-1 text-left font-semibold">Verdict</th>
                <th className="px-2 py-1 text-left font-semibold">why?</th>
              </tr>
            </thead>
            <tbody>
              {candidates.map((c) => {
                const byName = new Map(c.objectives.map((o) => [o.name, o]))
                const isOpen = !!openWhy[c.id]
                return (
                  <React.Fragment key={c.id}>
                    <tr
                      data-testid={`mobj-row-${c.id}`}
                      className={`border-b last:border-0 ${c.verdict === "rejected" ? "opacity-70" : ""}`}
                    >
                      <td className="px-2 py-1 font-mono font-semibold">{c.id}</td>
                      {names.map((n) => {
                        const o = byName.get(n)
                        return o ? (
                          <ObjectiveCell key={n} o={o} />
                        ) : (
                          <td key={n} className="px-2 py-1 text-muted-foreground italic">
                            n/a
                          </td>
                        )
                      })}
                      <td className="px-2 py-1 font-mono text-muted-foreground">{c.score}</td>
                      <td className="px-2 py-1">
                        <span
                          className="text-[10px] capitalize"
                          style={{
                            color:
                              c.verdict === "accepted"
                                ? "#22c55e"
                                : c.verdict === "rejected"
                                  ? "#ef4444"
                                  : c.verdict === "held"
                                    ? "#94a3b8"
                                    : "#f59e0b",
                          }}
                        >
                          {c.verdict}
                        </span>
                      </td>
                      <td className="px-2 py-1">
                        <button
                          type="button"
                          data-testid={`why-toggle-${c.id}`}
                          aria-expanded={isOpen}
                          className="inline-flex items-center gap-0.5 text-[10px] text-primary hover:underline"
                          onClick={() => setOpenWhy((s) => ({ ...s, [c.id]: !s[c.id] }))}
                        >
                          <Info className="h-3 w-3" />
                          why?
                        </button>
                      </td>
                    </tr>
                    {isOpen && <WhyRow candidate={c} colSpan={colCount} provenance={provenance} />}
                  </React.Fragment>
                )
              })}
            </tbody>
          </table>
        </div>
        <p className="text-[10px] text-muted-foreground mt-1">
          *score is a ranking key (mean of normalised per-objective scores), not a
          composite the pipeline optimises — the objectives above are optimised
          together.
        </p>
      </CardContent>
    </Card>
  )
}

// ---------------------------------------------------------------------------
// Safety gate — rejected candidates stay VISIBLE with their reason
// ---------------------------------------------------------------------------

function RejectedSet({ rejected }: { rejected: RejectedCandidate[] }) {
  const [open, setOpen] = useState(false)
  if (rejected.length === 0) return null
  return (
    <Card data-testid="rejected-set">
      <Collapsible open={open} onOpenChange={setOpen}>
        <CollapsibleTrigger asChild>
          <CardHeader className="pb-2 cursor-pointer">
            <CardTitle className="text-sm flex items-center gap-2">
              <ShieldAlert className="h-4 w-4 text-red-500" />
              Rejected by a gate
              <Badge variant="outline" className="text-[10px]" style={{ color: "#ef4444" }}>
                {rejected.length}
              </Badge>
              <ChevronDown
                className={`h-4 w-4 ml-auto transition-transform ${open ? "rotate-180" : ""}`}
              />
            </CardTitle>
            <p className="text-[10px] text-muted-foreground">
              Rejections stay visible with the gate that rejected them — safety is a
              gate, never traded away. Collapsed but present.
            </p>
          </CardHeader>
        </CollapsibleTrigger>
        <CollapsibleContent>
          <CardContent className="space-y-1">
            {rejected.map((r) => (
              <div
                key={r.id}
                data-testid={`rejected-row-${r.id}`}
                className="rounded border border-l-4 border-l-red-500 p-2 text-xs"
              >
                <div className="flex items-center justify-between gap-2">
                  <span className="font-mono font-semibold">{r.id}</span>
                  <span className="text-red-500 text-[11px]" data-testid={`rejected-reason-${r.id}`}>
                    {r.reason}
                  </span>
                </div>
                <div className="font-mono text-[10px] text-muted-foreground break-all mt-0.5">
                  {r.smiles}
                </div>
              </div>
            ))}
          </CardContent>
        </CollapsibleContent>
      </Collapsible>
    </Card>
  )
}

// ---------------------------------------------------------------------------
// Editable criteria / weights strip (§5.5) + client-side re-rank (§5.4 rule)
//
// "A single blended number is never shown … weights are the user's to set, are
//  stated on every ranking, and changing them re-ranks WITHOUT re-running the
//  predictions." The strip edits an in-place target + weight per objective; the
//  re-rank is a pure client-side re-sort over the candidates already returned.
// ---------------------------------------------------------------------------

export interface CriterionSetting {
  target: number | null // the objective's target (own units) — null = none stated
  weight: number // relative weight (>= 0); the criteria are STATED on the ranking
}

export type CriteriaMap = Record<string, CriterionSetting>

/** Seed the criteria from the run's objective meta + the values on candidate 1
 *  (so a stated target like property_envelope's 1.0 pre-fills honestly). */
function seedCriteria(
  objectiveMeta: GenObjectiveMeta[],
  candidates: GenCandidate[],
): CriteriaMap {
  const first = candidates[0]
  const byName = new Map((first?.objectives ?? []).map((o) => [o.name, o]))
  const out: CriteriaMap = {}
  for (const m of objectiveMeta) {
    const seededTarget = byName.get(m.name)?.target ?? null
    out[m.name] = { target: seededTarget ?? null, weight: 1 }
  }
  return out
}

/** Per-objective desirability in [0,1] under the user's target + direction.
 *  Uses only values already returned — no re-prediction. When no target is
 *  stated the raw value is used directly (already normalised 0-1 for the
 *  molecule-derived objectives we back). */
function desirability(o: ObjectiveValue, target: number | null): number {
  const v = o.value
  if (target == null) {
    // No target stated — direction still orders it; clamp to [0,1] softly.
    return o.direction === "minimize" ? 1 - clamp01(v) : clamp01(v)
  }
  if (target === 0) return o.direction === "minimize" ? (v <= 0 ? 1 : 0) : clamp01(v)
  const ratio = v / target
  // maximize: meeting/exceeding target => 1; minimize: at/below target => 1.
  return o.direction === "minimize" ? clamp01(1 / Math.max(ratio, 1e-9)) : clamp01(ratio)
}

function clamp01(x: number): number {
  return Math.max(0, Math.min(1, x))
}

/** The user's weighted desirability for a candidate — a RE-SORT KEY ONLY, shown
 *  next to the per-objective values, never presented as "the one number". */
export function rankKey(c: GenCandidate, criteria: CriteriaMap): number {
  let num = 0
  let den = 0
  for (const o of c.objectives) {
    const crit = criteria[o.name]
    const w = crit ? Math.max(0, crit.weight) : 1
    if (w === 0) continue
    num += w * desirability(o, crit ? crit.target : o.target ?? null)
    den += w
  }
  return den > 0 ? num / den : c.score
}

/** Re-rank the candidates under the user's criteria WITHOUT re-running. Held
 *  (out-of-domain) candidates carry no confident number, so they sort to the
 *  end and keep their place-nowhere status (§5.5.1). */
export function reRank(candidates: GenCandidate[], criteria: CriteriaMap): GenCandidate[] {
  return [...candidates].sort((a, b) => {
    const aHeld = a.verdict === "held"
    const bHeld = b.verdict === "held"
    if (aHeld && bHeld) return 0
    if (aHeld) return 1
    if (bHeld) return -1
    return rankKey(b, criteria) - rankKey(a, criteria)
  })
}

function CriteriaStrip({
  objectiveMeta,
  criteria,
  onChange,
}: {
  objectiveMeta: GenObjectiveMeta[]
  criteria: CriteriaMap
  onChange: (name: string, patch: Partial<CriterionSetting>) => void
}) {
  if (objectiveMeta.length === 0) return null
  const stated = objectiveMeta
    .map((m) => {
      const c = criteria[m.name]
      const t = c?.target
      return `${m.name} (${m.direction === "maximize" ? "↑" : "↓"}${
        t != null ? " " + (m.direction === "maximize" ? "≥" : "≤") + " " + t : ""
      }, w=${c?.weight ?? 1})`
    })
    .join(" · ")
  return (
    <Card data-testid="criteria-strip">
      <CardHeader className="pb-2">
        <CardTitle className="text-sm flex items-center gap-2">
          <SlidersHorizontal className="h-4 w-4" />
          Criteria &amp; weights
        </CardTitle>
        <p className="text-[10px] text-muted-foreground">
          Weights are the user&apos;s to set and are stated on every ranking. Changing a
          target or weight re-ranks the candidates below <strong>without re-running</strong>
          the predictions — no single blended number is optimised.
        </p>
      </CardHeader>
      <CardContent className="space-y-2">
        <div className="overflow-auto rounded border text-xs">
          <table className="min-w-full">
            <thead className="bg-muted">
              <tr>
                <th className="px-2 py-1 text-left font-semibold">Objective</th>
                <th className="px-2 py-1 text-left font-semibold">Direction</th>
                <th className="px-2 py-1 text-left font-semibold">Target</th>
                <th className="px-2 py-1 text-left font-semibold">Weight</th>
              </tr>
            </thead>
            <tbody>
              {objectiveMeta.map((m) => {
                const c = criteria[m.name] ?? { target: null, weight: 1 }
                return (
                  <tr key={m.name} data-testid={`criteria-row-${m.name}`} className="border-b last:border-0">
                    <td className="px-2 py-1 font-mono font-semibold whitespace-nowrap">
                      {m.name}
                      <span className="text-[10px] text-muted-foreground ml-1">/{m.unit}</span>
                    </td>
                    <td className="px-2 py-1 text-[10px] text-muted-foreground">
                      {m.direction === "maximize" ? "maximize ↑" : "minimize ↓"}
                    </td>
                    <td className="px-2 py-1">
                      <Input
                        data-testid={`criteria-target-${m.name}`}
                        value={c.target == null ? "" : String(c.target)}
                        placeholder="none"
                        onChange={(e) => {
                          const raw = e.target.value.trim()
                          const v = raw === "" ? null : parseFloat(raw)
                          onChange(m.name, { target: raw === "" ? null : Number.isFinite(v as number) ? (v as number) : null })
                        }}
                        className="h-6 w-20 text-xs font-mono"
                      />
                    </td>
                    <td className="px-2 py-1">
                      <Input
                        data-testid={`criteria-weight-${m.name}`}
                        type="number"
                        min={0}
                        step={0.5}
                        value={String(c.weight)}
                        onChange={(e) => {
                          const v = parseFloat(e.target.value)
                          onChange(m.name, { weight: Number.isFinite(v) ? Math.max(0, v) : 0 })
                        }}
                        className="h-6 w-20 text-xs font-mono"
                      />
                    </td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        </div>
        <p className="text-[10px] text-muted-foreground" data-testid="criteria-stated">
          Ranking criteria: {stated}
        </p>
      </CardContent>
    </Card>
  )
}

// ---------------------------------------------------------------------------
// Pareto / trade-off view (§5.4) — 2-objective front, front points highlighted
//
// "The trade-off is shown rather than collapsed." Candidates are plotted on two
// chosen objectives; the members of the backend's `pareto` front (matched by
// SMILES) are highlighted. Lightweight inline SVG (same pattern as PlddtChart /
// the other viewers) — no chart library.
// ---------------------------------------------------------------------------

function ParetoView({
  candidates,
  objectiveMeta,
  paretoSmiles,
}: {
  candidates: GenCandidate[]
  objectiveMeta: GenObjectiveMeta[]
  paretoSmiles: string[]
}) {
  // Default to the first two objectives; let the user re-pick either axis when
  // more than two exist (a 2-objective trade-off is what a chemist reads).
  const [xName, setXName] = useState(objectiveMeta[0]?.name ?? "")
  const [yName, setYName] = useState(objectiveMeta[1]?.name ?? objectiveMeta[0]?.name ?? "")

  if (objectiveMeta.length < 2) {
    return (
      <Card data-testid="pareto-view">
        <CardHeader className="pb-2">
          <CardTitle className="text-sm flex items-center gap-2">
            <GitCompare className="h-4 w-4" />
            Trade-off (Pareto) view
          </CardTitle>
        </CardHeader>
        <CardContent>
          <p className="text-xs text-muted-foreground" data-testid="pareto-empty">
            A trade-off needs two objectives. This run optimised{" "}
            {objectiveMeta.length === 1 ? "one objective" : "no objectives"} — nothing to
            trade off, so no front is drawn.
          </p>
        </CardContent>
      </Card>
    )
  }

  const xm = objectiveMeta.find((m) => m.name === xName) ?? objectiveMeta[0]
  const ym = objectiveMeta.find((m) => m.name === yName) ?? objectiveMeta[1]

  const paretoSet = new Set(paretoSmiles)
  const pts = candidates
    .map((c) => {
      const x = c.objectives.find((o) => o.name === xm.name)
      const y = c.objectives.find((o) => o.name === ym.name)
      if (!x || !y) return null
      return { id: c.id, smiles: c.smiles, x: x.value, y: y.value, verdict: c.verdict, onFront: paretoSet.has(c.smiles) }
    })
    .filter((p): p is NonNullable<typeof p> => p !== null)

  if (pts.length === 0) {
    return (
      <Card data-testid="pareto-view">
        <CardHeader className="pb-2">
          <CardTitle className="text-sm flex items-center gap-2">
            <GitCompare className="h-4 w-4" />
            Trade-off (Pareto) view
          </CardTitle>
        </CardHeader>
        <CardContent>
          <p className="text-xs text-muted-foreground" data-testid="pareto-empty">
            No candidate carries both selected objectives, so no trade-off can be plotted.
          </p>
        </CardContent>
      </Card>
    )
  }

  const W = 100
  const H = 70
  const PAD = 8
  const xs = pts.map((p) => p.x)
  const ys = pts.map((p) => p.y)
  const xmin = Math.min(...xs)
  const xmax = Math.max(...xs)
  const ymin = Math.min(...ys)
  const ymax = Math.max(...ys)
  const sx = (v: number) => PAD + ((v - xmin) / (xmax - xmin || 1)) * (W - 2 * PAD)
  const sy = (v: number) => H - PAD - ((v - ymin) / (ymax - ymin || 1)) * (H - 2 * PAD)

  // Order the front points for a connecting line: sort by x, then y.
  const frontPts = pts.filter((p) => p.onFront).sort((a, b) => a.x - b.x || a.y - b.y)
  const frontPath =
    frontPts.length >= 2
      ? frontPts.map((p, i) => `${i === 0 ? "M" : "L"} ${sx(p.x).toFixed(2)} ${sy(p.y).toFixed(2)}`).join(" ")
      : ""

  const AxisSelect = ({
    value,
    onChange,
    testid,
  }: {
    value: string
    onChange: (v: string) => void
    testid: string
  }) => (
    <select
      data-testid={testid}
      value={value}
      onChange={(e) => onChange(e.target.value)}
      className="h-6 rounded border bg-background px-1 text-[10px] font-mono"
    >
      {objectiveMeta.map((m) => (
        <option key={m.name} value={m.name}>
          {m.name} /{m.unit}
        </option>
      ))}
    </select>
  )

  return (
    <Card data-testid="pareto-view">
      <CardHeader className="pb-2">
        <CardTitle className="text-sm flex items-center gap-2">
          <GitCompare className="h-4 w-4" />
          Trade-off (Pareto) view
        </CardTitle>
        <p className="text-[10px] text-muted-foreground">
          The trade-off is shown, not collapsed. Each dot is a candidate on two objectives;
          highlighted dots are on the non-dominated (Pareto) front — no candidate beats them on
          both. {paretoSet.size === 0 && "No front members were returned for this run."}
        </p>
      </CardHeader>
      <CardContent className="space-y-2">
        <div className="flex items-center gap-2 flex-wrap text-[10px] text-muted-foreground">
          <span>Y:</span>
          <AxisSelect value={ym.name} onChange={setYName} testid="pareto-y-axis" />
          <span className="ml-2">X:</span>
          <AxisSelect value={xm.name} onChange={setXName} testid="pareto-x-axis" />
        </div>
        <svg
          viewBox={`0 0 ${W} ${H}`}
          className="w-full"
          style={{ height: 220 }}
          role="img"
          aria-label={`Trade-off of ${ym.name} against ${xm.name}`}
          data-testid="pareto-svg"
        >
          {/* axes */}
          <line x1={PAD} y1={H - PAD} x2={W - PAD} y2={H - PAD} stroke="var(--border)" strokeWidth={0.4} vectorEffect="non-scaling-stroke" />
          <line x1={PAD} y1={PAD} x2={PAD} y2={H - PAD} stroke="var(--border)" strokeWidth={0.4} vectorEffect="non-scaling-stroke" />
          {/* pareto front path */}
          {frontPath && (
            <path d={frontPath} fill="none" stroke="#6366f1" strokeWidth={0.6} strokeDasharray="1.5 1" vectorEffect="non-scaling-stroke" data-testid="pareto-front-path" />
          )}
          {/* points */}
          {pts.map((p) => (
            <circle
              key={p.id}
              data-testid={`pareto-point-${p.id}`}
              data-on-front={p.onFront ? "true" : "false"}
              cx={sx(p.x)}
              cy={sy(p.y)}
              r={p.onFront ? 1.6 : 1.0}
              fill={
                p.verdict === "rejected"
                  ? "#ef4444"
                  : p.onFront
                    ? "#6366f1"
                    : p.verdict === "held"
                      ? "#94a3b8"
                      : "#22c55e"
              }
              stroke={p.onFront ? "#312e81" : "none"}
              strokeWidth={p.onFront ? 0.4 : 0}
              vectorEffect="non-scaling-stroke"
            >
              <title>
                {p.id} — {xm.name} {p.x}, {ym.name} {p.y}
                {p.onFront ? " (on front)" : ""}
              </title>
            </circle>
          ))}
        </svg>
        <div className="flex items-center justify-between text-[10px] text-muted-foreground font-mono">
          <span>
            {xm.name} → ({xmin} … {xmax}) /{xm.unit}
          </span>
        </div>
        <div className="flex items-center gap-3 flex-wrap text-[10px] text-muted-foreground">
          <span className="inline-flex items-center gap-1">
            <span className="inline-block h-2 w-2 rounded-full" style={{ background: "#6366f1" }} /> on front (
            {pts.filter((p) => p.onFront).length})
          </span>
          <span className="inline-flex items-center gap-1">
            <span className="inline-block h-2 w-2 rounded-full" style={{ background: "#22c55e" }} /> dominated
          </span>
          <span className="inline-flex items-center gap-1">
            <span className="inline-block h-2 w-2 rounded-full" style={{ background: "#ef4444" }} /> gate-rejected
          </span>
        </div>
      </CardContent>
    </Card>
  )
}

// ---------------------------------------------------------------------------
// Rejection profile by cause (§5.2) — counted AND characterised, not just totals
//
// "412 of 500 passed; 61 failed synthetic accessibility, 27 hit a structural
//  alert" — a high rejection rate is the most useful early signal that the
//  constraints are wrong. We bucket the free-text gate reason into causes.
// ---------------------------------------------------------------------------

type RejectionCause = "structural_alert" | "banned_moiety" | "sa_floor" | "valence" | "other"

const CAUSE_LABEL: Record<RejectionCause, string> = {
  structural_alert: "structural alert",
  banned_moiety: "banned moiety",
  sa_floor: "synthetic-accessibility floor",
  valence: "invalid valence / unparseable",
  other: "other gate",
}

/** Classify a backend rejection reason string into a cause bucket. The backend
 *  emits e.g. "structural alert: nitro_group", "banned moiety: [N+]…",
 *  "invalid structure (unparseable)"; a synthetic-accessibility floor reason is
 *  bucketed if/when the gate emits it — no cause is fabricated. */
export function classifyRejection(reason: string): RejectionCause {
  const r = reason.toLowerCase()
  if (r.includes("structural alert")) return "structural_alert"
  if (r.includes("banned moiety")) return "banned_moiety"
  if (r.includes("synthetic accessibility") || r.includes("sa ") || r.includes("sa_") || r.includes("sascore")) return "sa_floor"
  if (r.includes("valence") || r.includes("unparseable") || r.includes("invalid structure")) return "valence"
  return "other"
}

function RejectionProfile({
  rejected,
  nGenerated,
  nScored,
}: {
  rejected: RejectedCandidate[]
  nGenerated?: number
  nScored?: number
}) {
  if (rejected.length === 0) return null
  const byCause = new Map<RejectionCause, RejectedCandidate[]>()
  for (const r of rejected) {
    const cause = classifyRejection(r.reason)
    const arr = byCause.get(cause) ?? []
    arr.push(r)
    byCause.set(cause, arr)
  }
  const order: RejectionCause[] = ["structural_alert", "banned_moiety", "sa_floor", "valence", "other"]
  const rows = order.filter((c) => byCause.has(c)).map((c) => ({ cause: c, items: byCause.get(c)! }))
  const total = rejected.length
  const passedNote =
    nScored != null && nGenerated != null
      ? `${nScored} scored of ${nGenerated} generated`
      : null
  return (
    <Card data-testid="rejection-profile">
      <CardHeader className="pb-2">
        <CardTitle className="text-sm flex items-center gap-2">
          <ShieldAlert className="h-4 w-4 text-red-500" />
          Rejection profile
          <Badge variant="outline" className="text-[10px]" style={{ color: "#ef4444" }}>
            {total}
          </Badge>
        </CardTitle>
        <p className="text-[10px] text-muted-foreground">
          Rejections are counted <em>and characterised</em> by cause — the failure profile is the
          diagnostic. {passedNote}
        </p>
      </CardHeader>
      <CardContent className="space-y-1">
        {rows.map(({ cause, items }) => (
          <div
            key={cause}
            data-testid={`rejection-cause-${cause}`}
            className="flex items-center gap-2 rounded border px-2 py-1 text-xs"
          >
            <span className="inline-block h-2 w-2 rounded-full shrink-0" style={{ background: "#ef4444" }} />
            <span className="font-semibold capitalize">{CAUSE_LABEL[cause]}</span>
            <Badge variant="outline" className="text-[10px] ml-auto" data-testid={`rejection-count-${cause}`}>
              {items.length}
            </Badge>
            <span className="text-[10px] text-muted-foreground font-mono truncate max-w-[40%]" title={items.map((i) => i.id).join(", ")}>
              {items.map((i) => i.id).join(", ")}
            </span>
          </div>
        ))}
      </CardContent>
    </Card>
  )
}

// ---------------------------------------------------------------------------
// Export — order sheet (§5.5 "export" / §5.7) — pairs platform candidate ids
// with the lab's registry ids and carries the per-objective values, so a
// shortlist can leave the platform as an order in the format the lab registers
// from. Pure client-side blob download; renders only on-screen candidate data —
// nothing is fabricated. A `registryId` prefix is applied for pairing.
// ---------------------------------------------------------------------------

/** RFC-4180-ish CSV field quoting: wrap in quotes and double inner quotes when
 *  the field carries a comma, quote or newline. */
function csvField(v: string | number | null | undefined): string {
  const s = v == null ? "" : String(v)
  return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s
}

/** Build an order-sheet CSV from the (already on-screen, re-ranked) candidates.
 *  Columns: rank, candidate_id, registry_id, smiles, verdict, score, then one
 *  column per objective ("<name> (<unit>)"). Registry ids are the platform id
 *  prefixed with `registryPrefix` so the lab can pair both ways (§5.5). */
export function buildOrderSheetCsv(
  candidates: GenCandidate[],
  objectiveMeta: GenObjectiveMeta[],
  registryPrefix = "REG-",
): string {
  const objNames = objectiveMeta.map((m) => m.name)
  const header = [
    "rank",
    "candidate_id",
    "registry_id",
    "smiles",
    "verdict",
    "score",
    ...objectiveMeta.map((m) => `${m.name} (${m.unit})`),
  ]
  const lines = [header.map(csvField).join(",")]
  candidates.forEach((c, i) => {
    const byName = new Map(c.objectives.map((o) => [o.name, o]))
    const row = [
      i + 1,
      c.id,
      `${registryPrefix}${c.id}`,
      c.smiles,
      c.verdict,
      c.score,
      ...objNames.map((n) => {
        const o = byName.get(n)
        return o ? o.value : ""
      }),
    ]
    lines.push(row.map(csvField).join(","))
  })
  return lines.join("\n")
}

function OrderSheetButton({
  candidates,
  objectiveMeta,
  runId,
}: {
  candidates: GenCandidate[]
  objectiveMeta: GenObjectiveMeta[]
  runId?: string
}) {
  const onExport = useCallback(() => {
    const csv = buildOrderSheetCsv(candidates, objectiveMeta)
    const blob = new Blob([csv], { type: "text/csv;charset=utf-8" })
    const url = URL.createObjectURL(blob)
    const a = document.createElement("a")
    a.href = url
    a.download = `order-sheet-${runId ?? "design"}.csv`
    document.body.appendChild(a)
    a.click()
    a.remove()
    URL.revokeObjectURL(url)
  }, [candidates, objectiveMeta, runId])
  return (
    <div className="flex items-center justify-between gap-2 rounded border px-2 py-1.5" data-testid="order-sheet">
      <span className="text-[10px] text-muted-foreground">
        Leave the platform as an <strong>order</strong> — candidate ids paired with the lab&apos;s
        registry ids, per-objective values in their own units (§5.7).
      </span>
      <Button
        type="button"
        size="sm"
        variant="outline"
        className="h-7 text-xs gap-1 shrink-0"
        data-testid="dg-export-order"
        disabled={candidates.length === 0}
        onClick={onExport}
      >
        <Download className="h-3 w-3" />
        Export order sheet
      </Button>
    </div>
  )
}

// ---------------------------------------------------------------------------
// Entry routes (§5.6) — "start from…" strip. Three routes into the module beyond
// a cold start: from a dataset (an assay table seeds the series), from Models
// (a newly gated model re-scores the set), from Search (a patent answer is
// promoted into an exclusion).
//
// Each chip performs a REAL, useful navigation using the app's router (wouter):
//   - "From a dataset" → /files   (the DataHub / dataset browser, Spec 04)
//   - "From Models"     → /models  (the model catalog / picker, Spec 03)
//   - "From Search"     → /        (the composer / evidence surface, Spec 01)
// The `?from=design` marker is carried so a future consumer on those surfaces
// can hand a selection back to the design run. Today those surfaces do not yet
// read the marker back, so this is navigate-only — no fake hand-off is
// fabricated. A host may still override any chip with a callback prop (which
// takes precedence over the default navigation), e.g. to open an in-place
// picker instead of routing away.
// ---------------------------------------------------------------------------

/** The real, in-app destinations for the three §5.6 entry routes. Exported so a
 *  test can assert against them without hard-coding strings twice. The
 *  `?from=design` marker signals provenance for a future selection hand-off. */
export const ENTRY_ROUTE_TARGETS = {
  dataset: "/files?from=design",
  model: "/models?from=design",
  search: "/?from=design",
} as const

function EntryRoutes({
  onStartFromDataset,
  onStartFromModel,
  onPromoteFromSearch,
}: {
  onStartFromDataset?: () => void
  onStartFromModel?: () => void
  onPromoteFromSearch?: () => void
}) {
  const [, navigate] = useLocation()
  const routes: {
    key: string
    testId: string
    label: string
    hint: string
    icon: React.ReactNode
    onClick: () => void
  }[] = [
    {
      key: "dataset",
      testId: "design-entry-dataset",
      label: "From a dataset",
      hint: "An assay table starts a design run directly — the measured compounds become the starting series. Opens the dataset browser.",
      icon: <Boxes className="h-3 w-3" />,
      // Host override wins; otherwise navigate to the real DataHub surface.
      onClick: onStartFromDataset ?? (() => navigate(ENTRY_ROUTE_TARGETS.dataset)),
    },
    {
      key: "model",
      testId: "design-entry-models",
      label: "From Models",
      hint: "A newly gated potency or safety model re-scores the current candidate set. Opens the model catalog.",
      icon: <Target className="h-3 w-3" />,
      onClick: onStartFromModel ?? (() => navigate(ENTRY_ROUTE_TARGETS.model)),
    },
    {
      key: "search",
      testId: "design-entry-search",
      label: "From Search",
      hint: "A patent answer is promoted into an exclusion constraint on the next generation run. Opens the search / evidence surface.",
      icon: <SearchIcon className="h-3 w-3" />,
      onClick: onPromoteFromSearch ?? (() => navigate(ENTRY_ROUTE_TARGETS.search)),
    },
  ]
  return (
    <div className="flex items-center gap-2 flex-wrap" data-testid="entry-routes">
      <span className="text-[10px] text-muted-foreground">Start from…</span>
      {routes.map((r) => (
        <Button
          key={r.key}
          type="button"
          size="sm"
          variant="outline"
          className="h-7 text-xs gap-1"
          // Spec-05 §5.6 canonical testid (design-entry-<key>); the legacy
          // `entry-<key>` alias is kept as a data attribute so older selectors
          // still resolve the element.
          data-testid={r.testId}
          data-legacy-testid={`entry-${r.key}`}
          title={r.hint}
          onClick={r.onClick}
        >
          {r.icon}
          {r.label}
        </Button>
      ))}
    </div>
  )
}

// ---------------------------------------------------------------------------
// Predicted-vs-measured (§5.7 / §5.8) — when the bench returns measurements they
// are shown against the predictions that preceded them, per candidate. The
// divergence is the only honest measure of whether the pipeline is working; a
// large per-objective gap is FLAGGED as a contradiction (the surrogate is not
// trusted silently after a bad round). No refit is run here — this is the
// design-side record only. When no measurements are supplied it says so plainly.
// ---------------------------------------------------------------------------

/** A per-objective predicted-vs-measured delta is a CONTRADICTION when the
 *  measured value diverges from the prediction by more than `tol` (relative to
 *  the prediction's magnitude, with an absolute floor so near-zero predictions
 *  don't over-flag). Pure + exported so it is directly testable. */
export function isContradiction(predicted: number, measured: number, tol = 0.5): boolean {
  const denom = Math.max(Math.abs(predicted), 1e-6)
  return Math.abs(measured - predicted) / denom > tol
}

function PredictedVsMeasured({
  candidates,
  objectiveMeta,
  measured,
}: {
  candidates: GenCandidate[]
  objectiveMeta: GenObjectiveMeta[]
  measured?: MeasuredResult[]
}) {
  const hasMeasured = (measured?.length ?? 0) > 0
  const byId = new Map(candidates.map((c) => [c.id, c]))
  // Rows are keyed off the measured results (only what came back from the bench).
  const rows = (measured ?? [])
    .map((m) => {
      const cand = byId.get(m.id)
      if (!cand) return null
      const predByName = new Map(cand.objectives.map((o) => [o.name, o]))
      const cells = objectiveMeta.map((meta) => {
        const pred = predByName.get(meta.name)
        const meas = m.measured.find((mm) => mm.name === meta.name)
        const contradiction =
          pred != null && meas != null ? isContradiction(pred.value, meas.value) : false
        return { meta, pred, meas, contradiction }
      })
      return { id: m.id, registryId: m.registryId, cells, anyContradiction: cells.some((c) => c.contradiction) }
    })
    .filter((r): r is NonNullable<typeof r> => r !== null)

  return (
    <Card data-testid="predicted-vs-measured">
      <CardHeader className="pb-2">
        <CardTitle className="text-sm flex items-center gap-2">
          <FlaskConical className="h-4 w-4" />
          Predicted vs measured
          {hasMeasured && (
            <Badge
              variant="outline"
              className="text-[10px]"
              style={{ color: rows.some((r) => r.anyContradiction) ? "#ef4444" : "#22c55e" }}
              data-testid="pvm-contradiction-count"
            >
              {rows.filter((r) => r.anyContradiction).length} flagged
            </Badge>
          )}
        </CardTitle>
        <p className="text-[10px] text-muted-foreground">
          Measurements returned from the bench, shown against the predictions that preceded them —
          the only honest measure of whether the design pipeline is working. A large divergence is
          flagged; the surrogate is not trusted silently after a bad round (§5.7).
        </p>
      </CardHeader>
      <CardContent>
        {!hasMeasured || rows.length === 0 ? (
          <p className="text-xs text-muted-foreground" data-testid="pvm-empty">
            No measured results yet. When the bench returns measurements for these candidates they
            will appear here against their predictions — nothing is shown until real data comes back.
          </p>
        ) : (
          <div className="overflow-auto rounded border text-xs">
            <table className="min-w-full">
              <thead className="bg-muted">
                <tr>
                  <th className="px-2 py-1 text-left font-semibold">Candidate</th>
                  {objectiveMeta.map((m) => (
                    <th key={m.name} className="px-2 py-1 text-left font-semibold whitespace-nowrap">
                      {m.name}
                      <span className="text-[10px] text-muted-foreground ml-1">/{m.unit}</span>
                      <div className="text-[9px] font-normal text-muted-foreground">pred → meas</div>
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {rows.map((r) => (
                  <tr key={r.id} data-testid={`pvm-row-${r.id}`} className="border-b last:border-0">
                    <td className="px-2 py-1 font-mono font-semibold whitespace-nowrap">
                      {r.id}
                      {r.registryId && (
                        <span className="text-[10px] text-muted-foreground ml-1">({r.registryId})</span>
                      )}
                    </td>
                    {r.cells.map(({ meta, pred, meas, contradiction }) => (
                      <td
                        key={meta.name}
                        className="px-2 py-1 font-mono whitespace-nowrap"
                        data-testid={`pvm-cell-${r.id}-${meta.name}`}
                        data-contradiction={contradiction ? "true" : "false"}
                      >
                        <span className="text-muted-foreground">{pred ? pred.value : "n/a"}</span>
                        <span className="text-muted-foreground mx-1">→</span>
                        <span style={{ color: contradiction ? "#ef4444" : "#22c55e" }}>
                          {meas ? meas.value : "—"}
                        </span>
                        {contradiction && (
                          <span
                            className="text-[9px] text-red-500 ml-1"
                            data-testid={`pvm-flag-${r.id}-${meta.name}`}
                          >
                            contradiction
                          </span>
                        )}
                      </td>
                    ))}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </CardContent>
    </Card>
  )
}

// ---------------------------------------------------------------------------
// Main component
// ---------------------------------------------------------------------------

export interface DesignGenerateProps {
  client?: GenerateClient
  /** Fired when a HitGrid model link is clicked. */
  onOpenModel?: (modelId: string) => void
  /** Entry route (§5.6): an assay table seeds the starting series. Default no-op. */
  onStartFromDataset?: () => void
  /** Entry route (§5.6): a newly gated model re-scores the candidate set. Default no-op. */
  onStartFromModel?: () => void
  /** Entry route (§5.6): a patent answer is promoted into an exclusion. Default no-op. */
  onPromoteFromSearch?: () => void
  /** Measured results returned from the bench (§5.7). When supplied, the
   *  predicted-vs-measured panel renders them against the predictions. */
  measuredResults?: MeasuredResult[]
  className?: string
}

export function DesignGenerate({
  client = defaultClient,
  onOpenModel,
  onStartFromDataset,
  onStartFromModel,
  onPromoteFromSearch,
  measuredResults,
  className,
}: DesignGenerateProps) {
  // --- constraint state (the interface) ------------------------------------
  const [seedSmiles, setSeedSmiles] = useState("")
  const [modality, setModality] = useState<"small_molecule" | "peptide" | "protein">("small_molecule")
  const [scaffoldPolicy, setScaffoldPolicy] = useState<ScaffoldPolicy>("stay")
  const [mwMax, setMwMax] = useState("500")
  const [logpMax, setLogpMax] = useState("5")
  const [tpsaMax, setTpsaMax] = useState("140")
  const [exclusionsText, setExclusionsText] = useState("")
  const [seedSeriesText, setSeedSeriesText] = useState("")
  const [count, setCount] = useState("20")
  const [nGenerate, setNGenerate] = useState("200")

  // --- run state -----------------------------------------------------------
  const [run, setRun] = useState<GenerationRun | null>(null)
  const [error, setError] = useState<string | null>(null)
  const pollTimer = useRef<ReturnType<typeof setTimeout> | null>(null)

  // --- editable criteria/weights (§5.5) — client-side re-rank, no re-run ----
  const [criteria, setCriteria] = useState<CriteriaMap>({})
  // Reset the criteria to the run's seeded defaults whenever a new completed
  // result arrives (keyed by run_id + objective names so a re-run reseeds).
  const objectiveKey = (run?.objectives ?? []).map((m) => m.name).join(",")
  useEffect(() => {
    if (run?.status === "completed" && (run.objectives?.length ?? 0) > 0) {
      setCriteria(seedCriteria(run.objectives ?? [], run.candidates ?? []))
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [run?.run_id, run?.status, objectiveKey])

  const updateCriterion = useCallback(
    (name: string, patch: Partial<CriterionSetting>) =>
      setCriteria((c) => {
        const prev: CriterionSetting = c[name] ?? { target: null, weight: 1 }
        return { ...c, [name]: { ...prev, ...patch } }
      }),
    [],
  )

  useEffect(
    () => () => {
      if (pollTimer.current) clearTimeout(pollTimer.current)
    },
    [],
  )

  const parseList = (t: string): string[] =>
    t
      .split(/[\n,]/)
      .map((s) => s.trim())
      .filter(Boolean)

  const buildBody = useCallback((): GenerateRequestBody => {
    const num = (s: string): number | undefined => {
      const v = parseFloat(s)
      return Number.isFinite(v) ? v : undefined
    }
    return {
      generator: "brics",
      modality,
      constraints: {
        seed_smiles: seedSmiles.trim() || undefined,
        scaffold_policy: scaffoldPolicy,
        property_envelope: {
          mw_max: num(mwMax),
          logp_max: num(logpMax),
          tpsa_max: num(tpsaMax),
        },
        exclusions: parseList(exclusionsText),
      },
      objectives: ["drug_like", "property_envelope"],
      seed_series: parseList(seedSeriesText),
      count: Math.max(1, parseInt(count, 10) || 20),
      n_generate: Math.max(1, parseInt(nGenerate, 10) || 200),
    }
  }, [seedSmiles, modality, scaffoldPolicy, mwMax, logpMax, tpsaMax, exclusionsText, seedSeriesText, count, nGenerate])

  const pollLoop = useCallback(
    async (runId: string) => {
      try {
        const r = await client.poll(runId)
        setRun(r)
        if (r.status === "running") {
          pollTimer.current = setTimeout(() => pollLoop(runId), 1500)
        }
      } catch (e) {
        setError(String(e))
      }
    },
    [client],
  )

  const onRun = useCallback(async () => {
    setError(null)
    try {
      const { run_id } = await client.start(buildBody())
      setRun({ run_id, status: "running" })
      pollLoop(run_id)
    } catch (e) {
      setError(String(e))
    }
  }, [client, buildBody, pollLoop])

  const running = run?.status === "running"
  const rawCandidates = run?.candidates ?? []
  const rejected = run?.rejected ?? []
  const objectiveMeta = run?.objectives ?? []
  // Client-side re-rank under the user's criteria/weights — WITHOUT re-running
  // the predictions (§5.4 "changing them re-ranks without re-running"). Falls
  // back to backend order when no criteria are set yet.
  const candidates = useMemo(
    () => (Object.keys(criteria).length > 0 ? reRank(rawCandidates, criteria) : rawCandidates),
    [rawCandidates, criteria],
  )
  const hits = candidates.map(toHit)

  // Honest provenance for the per-row "why?" (§5.3/§5.5): the model+version are
  // the run's generator + objective predictors; there is no per-candidate
  // nearest measured analogue in the backend contract, so we say so plainly
  // rather than inventing one.
  const whyProvenance: WhyProvenance = useMemo(() => {
    const objs = (run?.objectives ?? []).map((m) => `${m.name}/${m.unit}`).join(", ")
    return {
      model: run?.generator
        ? `${run.generator}${objs ? ` + objective predictors (${objs})` : ""}`
        : "objective predictors",
      version: run?.generator_is_learned === false ? "deterministic enumeration (unversioned)" : run?.generator ?? "n/a",
      nearestAnalogue: "not available — no measured assay series was returned with this run",
    }
  }, [run?.generator, run?.generator_is_learned, objectiveKey])

  return (
    <div className={`space-y-3 ${className ?? ""}`} data-testid="design-generate">
      {/* ---- entry routes (§5.6): start from a dataset / Models / Search ---- */}
      <EntryRoutes
        onStartFromDataset={onStartFromDataset}
        onStartFromModel={onStartFromModel}
        onPromoteFromSearch={onPromoteFromSearch}
      />

      {/* ---- constraints composer (the interface, §5.2) ---- */}
      <Card data-testid="constraints-composer">
        <CardHeader className="pb-2">
          <CardTitle className="text-sm">Design constraints</CardTitle>
          <p className="text-[10px] text-muted-foreground">
            Generation is only useful when constrained — these resolve to run
            parameters, shown before the run starts.
          </p>
        </CardHeader>
        <CardContent className="space-y-3">
          <div className="space-y-1">
            <Label className="text-xs">Modality</Label>
            <div className="flex gap-1" data-testid="dg-modality">
              {([
                { id: "small_molecule", label: "Small molecule" },
                { id: "peptide", label: "Peptide" },
                { id: "protein", label: "Protein / biologic" },
              ] as const).map((m) => (
                <Button
                  key={m.id}
                  type="button"
                  size="sm"
                  variant={modality === m.id ? "default" : "outline"}
                  className="h-7 text-xs px-2"
                  data-testid={`dg-modality-${m.id}`}
                  onClick={() => setModality(m.id)}
                >
                  {m.label}
                </Button>
              ))}
            </div>
            {modality !== "small_molecule" && (
              <p className="text-[10px] text-amber-600" data-testid="dg-modality-note">
                {modality === "peptide" ? "Peptide" : "Protein / biologic"} design uses a sequence
                seed; sequence-based property constraints are being added — the small-molecule
                scaffold/envelope controls below apply to small molecules only.
              </p>
            )}
          </div>
          <div className="space-y-1">
            <Label htmlFor="dg-seed" className="text-xs">
              {modality === "small_molecule"
                ? "Target / seed (SMILES)"
                : "Target / seed (sequence)"}
            </Label>
            <Input
              id="dg-seed"
              data-testid="dg-seed-smiles"
              value={seedSmiles}
              onChange={(e) => setSeedSmiles(e.target.value)}
              placeholder={
                modality === "small_molecule"
                  ? "e.g. CC(=O)Oc1ccccc1C(=O)O"
                  : "e.g. ACDEFGHIKLMNPQRSTVWY"
              }
              className="font-mono text-xs"
            />
          </div>

          <div className="space-y-1">
            <Label className="text-xs">Scaffold policy</Label>
            <div className="flex gap-1" data-testid="dg-scaffold-policy">
              {SCAFFOLD_POLICIES.map((p) => (
                <Button
                  key={p}
                  type="button"
                  size="sm"
                  variant={scaffoldPolicy === p ? "default" : "outline"}
                  className="h-7 text-xs px-2 capitalize"
                  data-testid={`dg-policy-${p}`}
                  onClick={() => setScaffoldPolicy(p)}
                >
                  {p}
                </Button>
              ))}
            </div>
          </div>

          <div className="space-y-1">
            <Label className="text-xs">Property envelope (a window, not a cut-off)</Label>
            <div className="grid grid-cols-3 gap-2" data-testid="dg-envelope">
              <div>
                <span className="text-[10px] text-muted-foreground">MW ≤</span>
                <Input
                  data-testid="dg-mw"
                  value={mwMax}
                  onChange={(e) => setMwMax(e.target.value)}
                  className="h-7 text-xs"
                />
              </div>
              <div>
                <span className="text-[10px] text-muted-foreground">logP ≤</span>
                <Input
                  data-testid="dg-logp"
                  value={logpMax}
                  onChange={(e) => setLogpMax(e.target.value)}
                  className="h-7 text-xs"
                />
              </div>
              <div>
                <span className="text-[10px] text-muted-foreground">TPSA ≤</span>
                <Input
                  data-testid="dg-tpsa"
                  value={tpsaMax}
                  onChange={(e) => setTpsaMax(e.target.value)}
                  className="h-7 text-xs"
                />
              </div>
            </div>
          </div>

          <div className="space-y-1">
            <Label htmlFor="dg-exclusions" className="text-xs">
              Exclusions (banned SMARTS moieties, one per line)
            </Label>
            <Textarea
              id="dg-exclusions"
              data-testid="dg-exclusions"
              value={exclusionsText}
              onChange={(e) => setExclusionsText(e.target.value)}
              placeholder="[N+](=O)[O-]"
              className="font-mono text-xs h-14"
            />
          </div>

          <div className="space-y-1">
            <Label htmlFor="dg-series" className="text-xs">
              Seed series — measured compounds the surrogate learns from (optional)
            </Label>
            <Textarea
              id="dg-series"
              data-testid="dg-seed-series"
              value={seedSeriesText}
              onChange={(e) => setSeedSeriesText(e.target.value)}
              placeholder="One SMILES per line"
              className="font-mono text-xs h-16"
            />
          </div>

          <div className="grid grid-cols-2 gap-2">
            <div>
              <Label htmlFor="dg-count" className="text-xs">
                Count (candidates to keep)
              </Label>
              <Input
                id="dg-count"
                data-testid="dg-count"
                value={count}
                onChange={(e) => setCount(e.target.value)}
                className="h-7 text-xs"
              />
            </div>
            <div>
              <Label htmlFor="dg-ngen" className="text-xs">
                Virtual library size
              </Label>
              <Input
                id="dg-ngen"
                data-testid="dg-ngenerate"
                value={nGenerate}
                onChange={(e) => setNGenerate(e.target.value)}
                className="h-7 text-xs"
              />
            </div>
          </div>

          <div className="flex items-center justify-between gap-2 pt-1 border-t">
            <span className="text-[10px] text-muted-foreground" data-testid="dg-cost">
              Compute cost before run:{" "}
              {estimateCost(parseInt(count, 10) || 0, parseInt(nGenerate, 10) || 0)}
            </span>
            <Button
              type="button"
              size="sm"
              className="h-7 text-xs gap-1"
              data-testid="dg-run"
              disabled={running}
              onClick={onRun}
            >
              <Play className="h-3 w-3" />
              {running ? "Running…" : "Generate & rank"}
            </Button>
          </div>
        </CardContent>
      </Card>

      {error && (
        <div className="text-xs text-red-500" data-testid="dg-error">
          {error}
        </div>
      )}

      {/* ---- run status / honest failure profile (§5.8) ---- */}
      {run && (
        <div className="text-[10px] text-muted-foreground flex items-center gap-2 flex-wrap" data-testid="dg-status">
          <Badge variant="outline" className="text-[10px]" data-status={run.status}>
            {run.status}
          </Badge>
          {run.generator && (
            <span>
              generator: {run.generator}
              {run.generator_is_learned === false && " (deterministic enumeration, not learned)"}
            </span>
          )}
          {run.n_generated != null && <span>generated: {run.n_generated}</span>}
          {run.n_scored != null && <span>scored: {run.n_scored}</span>}
        </div>
      )}

      {run?.notes && run.notes.length > 0 && (
        <ul className="text-[10px] text-muted-foreground list-disc pl-4" data-testid="dg-notes">
          {run.notes.map((n, i) => (
            <li key={i}>{n}</li>
          ))}
        </ul>
      )}

      {/* ---- results ---- */}
      {run?.status === "completed" && candidates.length === 0 && (
        <>
          <Card data-testid="dg-empty">
            <CardContent className="text-xs text-muted-foreground py-4">
              No candidates cleared the pipeline. The failure profile is above — the
              constraints or seed are the most likely cause. Nothing was fabricated to
              fill a shortlist.
            </CardContent>
          </Card>
          {/* §5.8 "Most generations rejected → reports the rejection profile" */}
          <RejectionProfile rejected={rejected} nGenerated={run.n_generated} nScored={run.n_scored} />
        </>
      )}

      {candidates.length > 0 && (
        <>
          {/* Editable criteria/weights strip — re-ranks below without re-running (§5.5) */}
          <CriteriaStrip
            objectiveMeta={objectiveMeta}
            criteria={criteria}
            onChange={updateCriterion}
          />

          {/* Export order sheet (§5.5/§5.7) — leaves the platform as an order */}
          <OrderSheetButton candidates={candidates} objectiveMeta={objectiveMeta} runId={run?.run_id} />

          {/* Ranked candidates via the wave-1 HitGrid (rejected stay visible) */}
          <HitGrid
            hits={hits}
            modelName="drug-like (QED) + property envelope"
            modelId="dg-objectives"
            onOpenModel={onOpenModel}
          />

          {/* Trade-off / Pareto view — the front is shown, not collapsed (§5.4) */}
          <ParetoView
            candidates={candidates}
            objectiveMeta={objectiveMeta}
            paretoSmiles={run?.pareto ?? []}
          />

          {/* Multi-objective view — own units, no composite score, per-row why? */}
          <MultiObjectiveView
            candidates={candidates}
            objectiveMeta={objectiveMeta}
            provenance={whyProvenance}
          />

          {/* Rejection profile by cause — counted AND characterised (§5.2) */}
          <RejectionProfile rejected={rejected} nGenerated={run?.n_generated} nScored={run?.n_scored} />

          {/* Safety-as-a-gate — rejected candidates kept with reason */}
          <RejectedSet rejected={rejected} />

          {/* Predicted-vs-measured (§5.7) — the wet-lab return record; empty until
              measurements come back. No refit is run here (Spec 03 §3.7). */}
          <PredictedVsMeasured
            candidates={candidates}
            objectiveMeta={objectiveMeta}
            measured={measuredResults}
          />
        </>
      )}
    </div>
  )
}

export default DesignGenerate
