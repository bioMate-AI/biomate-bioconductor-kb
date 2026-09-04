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

import { useState, useCallback, useRef, useEffect } from "react"
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
import { Play, ChevronDown, ShieldAlert, Target } from "lucide-react"

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

export interface PropertyEnvelopeInput {
  mw_max?: number
  logp_max?: number
  tpsa_max?: number
  rot_bonds_max?: number
}

export interface GenerateRequestBody {
  generator: string
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

function MultiObjectiveView({
  candidates,
  objectiveMeta,
}: {
  candidates: GenCandidate[]
  objectiveMeta: GenObjectiveMeta[]
}) {
  const names = objectiveMeta.map((m) => m.name)
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
              </tr>
            </thead>
            <tbody>
              {candidates.map((c) => {
                const byName = new Map(c.objectives.map((o) => [o.name, o]))
                return (
                  <tr
                    key={c.id}
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
                  </tr>
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
// Main component
// ---------------------------------------------------------------------------

export interface DesignGenerateProps {
  client?: GenerateClient
  /** Fired when a HitGrid model link is clicked. */
  onOpenModel?: (modelId: string) => void
  className?: string
}

export function DesignGenerate({ client = defaultClient, onOpenModel, className }: DesignGenerateProps) {
  // --- constraint state (the interface) ------------------------------------
  const [seedSmiles, setSeedSmiles] = useState("")
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
  }, [seedSmiles, scaffoldPolicy, mwMax, logpMax, tpsaMax, exclusionsText, seedSeriesText, count, nGenerate])

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
  const candidates = run?.candidates ?? []
  const rejected = run?.rejected ?? []
  const objectiveMeta = run?.objectives ?? []
  const hits = candidates.map(toHit)

  return (
    <div className={`space-y-3 ${className ?? ""}`} data-testid="design-generate">
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
            <Label htmlFor="dg-seed" className="text-xs">
              Target / seed (SMILES)
            </Label>
            <Input
              id="dg-seed"
              data-testid="dg-seed-smiles"
              value={seedSmiles}
              onChange={(e) => setSeedSmiles(e.target.value)}
              placeholder="e.g. CC(=O)Oc1ccccc1C(=O)O"
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
        <Card data-testid="dg-empty">
          <CardContent className="text-xs text-muted-foreground py-4">
            No candidates cleared the pipeline. The failure profile is above — the
            constraints or seed are the most likely cause. Nothing was fabricated to
            fill a shortlist.
          </CardContent>
        </Card>
      )}

      {candidates.length > 0 && (
        <>
          {/* Ranked candidates via the wave-1 HitGrid (rejected stay visible) */}
          <HitGrid
            hits={hits}
            modelName="drug-like (QED) + property envelope"
            modelId="dg-objectives"
            onOpenModel={onOpenModel}
          />

          {/* Multi-objective view — own units, no composite score */}
          <MultiObjectiveView candidates={candidates} objectiveMeta={objectiveMeta} />

          {/* Safety-as-a-gate — rejected candidates kept with reason */}
          <RejectedSet rejected={rejected} />
        </>
      )}
    </div>
  )
}

export default DesignGenerate
