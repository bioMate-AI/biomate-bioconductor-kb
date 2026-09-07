/**
 * ModelsPanel — the 5-track Models surface:
 *
 *   Train · Adapt · Optimise · Run a pre-trained model · Registry
 *
 * A model is presented like a dataset (identity · evidence · lineage · used-by
 * · interface · versions), never a leaderboard. The Registry track lists the
 * live account catalog (GET /api/models) and opens a ModelObject on click. The
 * "Run a pre-trained model" track submits inference and renders the result with
 * the wave-1 viewers by evidence class.
 *
 * Train / Adapt / Optimise are project-scoped surfaces with no WS1 read
 * endpoint in this wave; they render descriptive track content (no fabricated
 * data). Any live data they receive arrives via props.
 */

import { useState } from "react"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs"
import { Skeleton } from "@/components/ui/skeleton"
import { GraduationCap, Wand2, Repeat, Rocket, Library, ChevronRight } from "lucide-react"
import { useModels, useTrainTrack, useAdaptTrack, useOptimiseTrack } from "./models-api"
import { ModelObjectLoader } from "./model-object"
import { RunPretrained } from "./run-pretrained"
import type { ModelSummary } from "./types"

export const MODELS_TRACKS = [
  "Train",
  "Adapt",
  "Optimise",
  "Run a pre-trained model",
  "Registry",
] as const

// ── Registry track ───────────────────────────────────────────────────────────
function RegistryTrack({ onOpenModel }: { onOpenModel: (id: string) => void }) {
  const { data: models, isLoading, isError } = useModels()

  if (isLoading) {
    return (
      <div className="space-y-2" data-testid="registry-loading">
        <Skeleton className="h-8 w-full" />
        <Skeleton className="h-8 w-full" />
        <Skeleton className="h-8 w-full" />
      </div>
    )
  }
  if (isError) {
    return (
      <p className="text-xs text-destructive" data-testid="registry-error">
        Could not load the model registry.
      </p>
    )
  }
  const rows: ModelSummary[] = models ?? []
  if (!rows.length) {
    return (
      <p className="text-xs text-muted-foreground" data-testid="registry-empty">
        No models registered in this account yet. A model trained in one project — or a pre-trained
        model you run — becomes a callable object listed here.
      </p>
    )
  }
  return (
    <div className="space-y-2" data-testid="registry-track">
      <p className="text-[10px] text-muted-foreground">
        Account-level · a model trained in one project is callable from any. A row opens the model
        object — evidence, lineage, consumers, interface, versions.
      </p>
      <div className="rounded border text-xs" data-testid="registry-table">
        <div className="grid grid-cols-[1.4fr_1fr_0.8fr_0.8fr_auto] gap-2 bg-muted px-2 py-1 font-semibold">
          <span>Model</span>
          <span>Family</span>
          <span>Origin</span>
          <span>Used by</span>
          <span />
        </div>
        {rows.map((m) => (
          <button
            key={m.id}
            type="button"
            className="grid grid-cols-[1.4fr_1fr_0.8fr_0.8fr_auto] gap-2 px-2 py-1.5 items-center w-full text-left border-t hover:bg-muted/40"
            data-testid={`registry-row-${m.id}`}
            onClick={() => onOpenModel(m.id)}
          >
            <span className="font-mono font-semibold truncate">
              {m.name} <span className="text-muted-foreground">{m.version}</span>
            </span>
            <span className="text-muted-foreground truncate">{m.family}</span>
            <span className="text-muted-foreground truncate">{m.origin}</span>
            <span className="text-muted-foreground">{m.usedByCount}</span>
            <ChevronRight className="h-3.5 w-3.5 text-muted-foreground" />
          </button>
        ))}
      </div>
    </div>
  )
}

// ── Optimise track (DMTA loop) ───────────────────────────────────────────────
/**
 * The closed loop, as rounds: design · make · test · analyse. Ported from the
 * prototype OptimiseTab/WetLabRound structure — the loop header (running/round),
 * surrogate model links, rounds list, and the proposal table where a rejected
 * proposal stays visible with its reason (safety-gate rejections shown, not
 * silently dropped).
 *
 * There is no WS1 read endpoint for the loop in this wave, so all data arrives
 * via the `data` prop; when it is absent the honest empty state renders (no
 * fabricated rounds, proposals or scores).
 */
export interface OptimiseSurrogate {
  /** Registry model id (opens the model object). */
  id: string
  /** Display label, e.g. "admet-herg v3". */
  label: string
}
export interface OptimiseRound {
  round: string
  status: string
  what: string
  when: string
}
export interface OptimiseProposal {
  id: string
  /** Score text as reported by the loop — never invented on the client. */
  score: string
  confidence: string
  /** "accepted" | "…rejected…" (safety-gate reason) | anything else → held. */
  verdict: string
}
export interface OptimiseData {
  running: boolean
  round: string | number
  budget?: string
  refitPolicy?: string
  surrogates: OptimiseSurrogate[]
  rounds: OptimiseRound[]
  proposal: OptimiseProposal[]
}

function proposalVerdictColor(verdict: string): string {
  if (verdict === "accepted") return "#22c55e"
  if (/reject/i.test(verdict)) return "#ef4444"
  return "#f59e0b" // held / anything else
}

function OptimiseTrack({
  data,
  onOpenModel,
}: {
  data?: OptimiseData
  onOpenModel: (id: string) => void
}) {
  if (!data) {
    return (
      <Card data-testid="track-optimise">
        <CardHeader className="pb-2">
          <CardTitle className="text-sm">Optimise · design · make · test · analyse</CardTitle>
        </CardHeader>
        <CardContent className="space-y-2">
          <p className="text-xs text-muted-foreground" data-testid="optimise-empty">
            No optimisation loop is running in this project yet. Start a design–make–test–analyse
            loop and the rounds, the surrogate models, and each round's proposal appear here.
          </p>
          <ul className="space-y-1">
            {[
              "A surrogate proposes, the bench measures, and a refit runs as a tracked training run — nothing about the loop is exempt from the evidence rules.",
              "Every proposal is accounted for; a candidate that produced no number still returns a reason.",
              "Censored values stay censored (IC50 > 30 µM is fitted as an inequality, never as 30).",
              "A rejected proposal stays on the list with its safety-gate reason.",
            ].map((b) => (
              <li key={b} className="text-[11px] flex items-start gap-1.5">
                <span className="mt-1 inline-block h-1 w-1 rounded-full bg-muted-foreground shrink-0" />
                <span>{b}</span>
              </li>
            ))}
          </ul>
        </CardContent>
      </Card>
    )
  }

  return (
    <div className="space-y-3" data-testid="track-optimise">
      {/* Loop header + surrogate + rounds */}
      <Card data-testid="optimise-loop">
        <CardHeader className="pb-2">
          <div className="flex items-center gap-2 flex-wrap">
            <CardTitle className="text-sm">Design · make · test · analyse</CardTitle>
            <Badge
              variant="outline"
              className="text-[10px] gap-1 ml-auto"
              style={{ color: data.running ? "#22c55e" : "#94a3b8" }}
              data-testid="optimise-loop-state"
            >
              <span
                className="inline-block h-1.5 w-1.5 rounded-full"
                style={{ background: data.running ? "#22c55e" : "#94a3b8" }}
              />
              {data.running ? `running · round ${data.round}` : "stopped"}
            </Badge>
          </div>
        </CardHeader>
        <CardContent className="space-y-2">
          <div className="grid grid-cols-[6rem_1fr] gap-x-2 gap-y-1 text-xs">
            <span className="text-muted-foreground">Surrogate</span>
            <span className="flex flex-wrap items-center gap-1" data-testid="optimise-surrogates">
              {data.surrogates.length ? (
                data.surrogates.map((s, i) => (
                  <span key={s.id} className="flex items-center gap-1">
                    {i > 0 && <span className="text-muted-foreground">+</span>}
                    <button
                      type="button"
                      className="font-mono text-primary hover:underline"
                      onClick={() => onOpenModel(s.id)}
                      data-testid={`optimise-surrogate-${s.id}`}
                    >
                      {s.label}
                    </button>
                  </span>
                ))
              ) : (
                <span className="text-muted-foreground">—</span>
              )}
            </span>
            {data.budget && (
              <>
                <span className="text-muted-foreground">Budget</span>
                <span>{data.budget}</span>
              </>
            )}
            {data.refitPolicy && (
              <>
                <span className="text-muted-foreground">Refit policy</span>
                <span>{data.refitPolicy}</span>
              </>
            )}
          </div>
          <div className="space-y-1" data-testid="optimise-rounds">
            {data.rounds.map((r) => (
              <div
                key={r.round}
                className="flex items-center gap-2 text-xs"
                data-testid={`optimise-round-${r.round}`}
              >
                <span className="inline-block h-1.5 w-1.5 rounded-full bg-muted-foreground shrink-0" />
                <span className="font-semibold">{r.round}</span>
                <Badge variant="outline" className="text-[10px]">{r.status}</Badge>
                <span>{r.what}</span>
                <span className="text-[10px] text-muted-foreground ml-auto">{r.when}</span>
              </div>
            ))}
          </div>
        </CardContent>
      </Card>

      {/* Proposal table */}
      <Card data-testid="optimise-proposal">
        <CardHeader className="pb-2">
          <div className="flex items-center gap-2">
            <CardTitle className="text-sm">Round {data.round} proposal</CardTitle>
            <span className="text-[10px] text-muted-foreground ml-auto">
              steerable before anything is ordered
            </span>
          </div>
        </CardHeader>
        <CardContent className="space-y-1">
          <div className="rounded border text-xs" data-testid="optimise-proposal-table">
            <div className="grid grid-cols-[1.2fr_0.8fr_0.9fr_1.2fr] gap-2 bg-muted px-2 py-1 font-semibold">
              <span>Candidate</span>
              <span>Score</span>
              <span>Confidence</span>
              <span>Verdict</span>
            </div>
            {data.proposal.length ? (
              data.proposal.map((p) => (
                <div
                  key={p.id}
                  className="grid grid-cols-[1.2fr_0.8fr_0.9fr_1.2fr] gap-2 px-2 py-1 items-center border-t"
                  data-testid={`optimise-proposal-${p.id}`}
                >
                  <span className="font-mono font-semibold truncate">{p.id}</span>
                  <span className="font-mono">{p.score}</span>
                  <span className="text-muted-foreground">{p.confidence}</span>
                  <Badge
                    variant="outline"
                    className="text-[10px] gap-1 w-fit"
                    style={{ color: proposalVerdictColor(p.verdict) }}
                    data-testid={`optimise-proposal-verdict-${p.id}`}
                  >
                    <span
                      className="inline-block h-1.5 w-1.5 rounded-full"
                      style={{ background: proposalVerdictColor(p.verdict) }}
                    />
                    {p.verdict}
                  </Badge>
                </div>
              ))
            ) : (
              <p className="px-2 py-2 text-[11px] text-muted-foreground border-t">
                No proposal for this round yet.
              </p>
            )}
          </div>
          <p className="text-[10px] text-muted-foreground pt-1">
            A rejected proposal stays on the list with its reason — you must be able to see what the
            loop wanted to do, and why the safety gate did not allow it.
          </p>
        </CardContent>
      </Card>
    </div>
  )
}

// ── Train track ──────────────────────────────────────────────────────────────
/**
 * The Train track, ported from the prototype TrainTab: the training loop (same
 * compute, same gates, same tracking as a workflow run), the training-runs list,
 * and the model families available. Training reuses the run language — only the
 * first and last steps are new decisions (which dataset, whether to register).
 *
 * The loop diagram and the model-family catalog are fixed design content (a
 * description of the surface, not measured data). The training-runs list is the
 * only data-bearing part; it arrives via `trainData.runs` and shows an honest
 * empty state when the project has not trained anything yet (no WS1 read
 * endpoint for training runs in this wave).
 */
export interface TrainRun {
  name: string
  family: string
  when: string
  /** "running" | "completed" | "failed" | anything else → queued/other. */
  status: string
  /** Gate label, e.g. "gate passed" / "gate blocked". */
  gate: string
  /** Metric label, e.g. "spearman 0.62". No number invented on the client. */
  metric: string
  /** Dataset version string. */
  dataset: string
  /** Resulting version note, e.g. "→ potency-gp v2". */
  version?: string
  /** Registry model id to open when the run is clicked (optional). */
  modelId?: string
}
export interface TrainData {
  runs: TrainRun[]
}

const TRAIN_LOOP: [string, string][] = [
  ["Dataset", "pick a dataset version — the only decision before Start"],
  ["Train", "runs on the run surface: phases, steps, tracking"],
  ["Quality gate", "a held-out floor, not a leaderboard"],
  ["Register", "a passing model is offered for registration, never silent"],
]

const MODEL_FAMILIES: [string, string][] = [
  ["Language", "instruction / extraction fine-tunes over text"],
  ["Tabular AutoML", "assay tables → property predictors"],
  ["Diffusion", "generative design over structures / sequences"],
  ["Molecular property", "ADMET-style scorers with confidence"],
]

function trainStatusColor(status: string): string {
  if (status === "completed") return "#22c55e"
  if (status === "failed") return "#ef4444"
  if (status === "running") return "#3b82f6"
  return "#94a3b8"
}

function TrainTrack({
  data,
  onOpenModel,
}: {
  data?: TrainData
  onOpenModel: (id: string) => void
}) {
  const runs = data?.runs ?? []
  return (
    <div className="space-y-3" data-testid="track-train">
      {/* The training loop */}
      <Card data-testid="train-loop">
        <CardHeader className="pb-2">
          <div className="flex items-center gap-2">
            <CardTitle className="text-sm">The training loop</CardTitle>
            <span className="text-[10px] text-muted-foreground ml-auto">
              same compute, same gates, same tracking as a workflow run
            </span>
          </div>
        </CardHeader>
        <CardContent className="space-y-1">
          {TRAIN_LOOP.map(([k, d], i) => (
            <div key={k} className="flex items-center gap-2 text-xs" data-testid={`train-loop-step-${i}`}>
              <span className="inline-flex h-4 w-4 items-center justify-center rounded-full bg-muted text-[10px] font-semibold shrink-0">
                {i + 1}
              </span>
              <span className="font-semibold">{k}</span>
              <span className="text-muted-foreground">{d}</span>
            </div>
          ))}
          <p className="text-[10px] text-muted-foreground pt-1">
            Only the first and last steps are new decisions: which dataset, and whether to register.
            Everything between reuses the run experience — training should feel like running a
            workflow.
          </p>
        </CardContent>
      </Card>

      {/* Training runs */}
      <Card data-testid="train-runs">
        <CardHeader className="pb-2">
          <CardTitle className="text-sm">Training runs</CardTitle>
        </CardHeader>
        <CardContent className="space-y-2">
          {runs.length ? (
            runs.map((r) => (
              <div
                key={r.name}
                className="rounded border px-2 py-1.5 text-xs space-y-1"
                data-testid={`train-run-${r.name}`}
              >
                <div className="flex items-center gap-2 flex-wrap">
                  <span className="font-semibold">{r.name}</span>
                  <Badge variant="outline" className="text-[10px]">{r.family}</Badge>
                  <span className="text-[10px] text-muted-foreground ml-auto">{r.when}</span>
                  <Badge
                    variant="outline"
                    className="text-[10px] gap-1"
                    style={{ color: trainStatusColor(r.status) }}
                    data-testid={`train-run-status-${r.name}`}
                  >
                    <span
                      className="inline-block h-1.5 w-1.5 rounded-full"
                      style={{ background: trainStatusColor(r.status) }}
                    />
                    {r.status}
                  </Badge>
                </div>
                <div className="flex items-center gap-2 flex-wrap">
                  <Badge variant="outline" className="text-[10px]">{r.metric}</Badge>
                  <Badge
                    variant="outline"
                    className="text-[10px] gap-1"
                    style={{ color: trainStatusColor(r.status) }}
                  >
                    <span
                      className="inline-block h-1.5 w-1.5 rounded-full"
                      style={{ background: trainStatusColor(r.status) }}
                    />
                    {r.gate}
                  </Badge>
                  <span className="font-mono text-[10px] text-muted-foreground truncate">{r.dataset}</span>
                  {(r.modelId || r.status === "running") && (
                    <button
                      type="button"
                      className="ml-auto text-primary hover:underline"
                      onClick={() => r.modelId && onOpenModel(r.modelId)}
                      data-testid={`train-run-open-${r.name}`}
                    >
                      {r.status === "running" ? "watch live →" : "open experiment →"}
                    </button>
                  )}
                </div>
                {r.version && <p className="text-[10px] text-muted-foreground">{r.version}</p>}
              </div>
            ))
          ) : (
            <p className="text-[11px] text-muted-foreground" data-testid="train-runs-empty">
              This project hasn't trained a model yet. Ask for model work — "train a potency
              predictor on our assay data" — and the run appears here, configured like any workflow
              run.
            </p>
          )}
        </CardContent>
      </Card>

      {/* Model families available */}
      <Card data-testid="train-families">
        <CardHeader className="pb-2">
          <CardTitle className="text-sm">Model families available</CardTitle>
        </CardHeader>
        <CardContent className="grid grid-cols-2 gap-2">
          {MODEL_FAMILIES.map(([n, s]) => (
            <div key={n} className="rounded border px-2 py-1.5 text-xs">
              <p className="font-semibold">{n}</p>
              <p className="text-[10px] text-muted-foreground">{s}</p>
            </div>
          ))}
        </CardContent>
      </Card>
    </div>
  )
}

// ── Adapt track ───────────────────────────────────────────────────────────────
/**
 * The Adapt track, ported from the prototype AdaptTab: adaptation is a list of
 * switchable things, not an opaque model change. The adaptation-level ladder
 * (rule → index → adapter, cheapest first) is fixed design content; the
 * "What was learned" list of before→after edit pairs is the data-bearing part.
 *
 * Each learned pair carries an `on` state owned by the parent; toggling fires
 * `onToggleLearned(id)` (no persistence endpoint in this wave). When there are
 * no pairs the honest empty state renders — nothing is learned silently.
 */
export interface AdaptPair {
  id: string
  /** The learned rule, e.g. "prefer 'cohort' over 'group' in methods". */
  learned: string
  /** Scope label, e.g. "organisation" / "project". */
  scope: string
  /** The correction: what BioMate wrote before → what you changed it to. */
  before: string
  after: string
  /** Where the edit came from, e.g. "Methods draft · 2026-08". */
  source: string
  /** Whether this learned rule is currently active. */
  on: boolean
}
export interface AdaptData {
  /** Count of queued before→after pairs not yet trained on. */
  pendingCount?: number
  pairs: AdaptPair[]
}

const ADAPT_LEVELS: [string, string, string][] = [
  ["Prompt rule", "cheapest · instant", "a written instruction, applied every run"],
  ["Few-shot index", "cheap · seconds", "retrieved examples steer the output"],
  ["Trained adapter", "costly · a training run", "weights updated, gated like any model"],
]

function AdaptTrack({
  data,
  onToggleLearned,
  onRetrain,
}: {
  data?: AdaptData
  onToggleLearned?: (id: string) => void
  onRetrain?: () => void
}) {
  const pairs = data?.pairs ?? []
  const activeCount = pairs.filter((p) => p.on).length
  return (
    <div className="space-y-3" data-testid="track-adapt">
      {/* Adaptation level ladder */}
      <Card data-testid="adapt-levels">
        <CardHeader className="pb-2">
          <div className="flex items-center gap-2 flex-wrap">
            <CardTitle className="text-sm">Adaptation level</CardTitle>
            <Badge variant="outline" className="text-[10px]">scope: organisation</Badge>
            <Button
              size="sm"
              className="h-6 text-[11px] px-2 ml-auto"
              onClick={() => onRetrain?.()}
              data-testid="adapt-retrain"
            >
              Re-train on my edits
              {data?.pendingCount ? ` (${data.pendingCount})` : ""}
            </Button>
          </div>
        </CardHeader>
        <CardContent className="space-y-2">
          <p className="text-xs text-muted-foreground">
            When you correct BioMate's output, the before→after pair is queued. Nothing is learned
            silently: every learned rule appears below and can be switched off.
          </p>
          <div className="space-y-1">
            {ADAPT_LEVELS.map(([n, cost, state]) => (
              <div key={n} className="rounded border px-2 py-1.5 text-xs">
                <div className="flex items-center gap-2">
                  <span className="font-semibold">{n}</span>
                  <span className="text-[10px] text-muted-foreground ml-auto">{cost}</span>
                </div>
                <p className="text-[10px] text-muted-foreground">{state}</p>
              </div>
            ))}
          </div>
          <p className="text-[10px] text-muted-foreground">
            Cheapest first: a rule is preferred over an index, and an index over a trained adapter.
            The level in use is visible, because it changes what "forget this" means.
          </p>
        </CardContent>
      </Card>

      {/* What was learned */}
      <Card data-testid="adapt-learned">
        <CardHeader className="pb-2">
          <div className="flex items-center gap-2">
            <CardTitle className="text-sm">What was learned</CardTitle>
            {pairs.length > 0 && (
              <span className="text-[10px] text-muted-foreground ml-auto">
                {activeCount} of {pairs.length} active
              </span>
            )}
          </div>
        </CardHeader>
        <CardContent className="space-y-2">
          {pairs.length ? (
            pairs.map((p) => (
              <div
                key={p.id}
                className={"rounded border px-2 py-1.5 text-xs space-y-1" + (p.on ? "" : " opacity-60")}
                data-testid={`adapt-pair-${p.id}`}
              >
                <div className="flex items-center gap-2 flex-wrap">
                  <span className="font-semibold">{p.learned}</span>
                  <Badge variant="outline" className="text-[10px] ml-auto">{p.scope}</Badge>
                  <button
                    type="button"
                    role="switch"
                    aria-checked={p.on}
                    className={
                      "relative inline-flex h-4 w-7 items-center rounded-full transition-colors " +
                      (p.on ? "bg-primary" : "bg-muted")
                    }
                    onClick={() => onToggleLearned?.(p.id)}
                    data-testid={`adapt-pair-toggle-${p.id}`}
                  >
                    <span
                      className={
                        "inline-block h-3 w-3 rounded-full bg-background transition-transform " +
                        (p.on ? "translate-x-3.5" : "translate-x-0.5")
                      }
                    />
                  </button>
                </div>
                <div className="flex items-center gap-2 text-[11px]">
                  <span className="line-through text-red-500/80" data-testid={`adapt-pair-before-${p.id}`}>
                    {p.before}
                  </span>
                  <span className="text-muted-foreground">→</span>
                  <span className="text-green-600" data-testid={`adapt-pair-after-${p.id}`}>
                    {p.after}
                  </span>
                </div>
                <p className="text-[10px] text-muted-foreground">from your edit in {p.source}</p>
              </div>
            ))
          ) : (
            <p className="text-[11px] text-muted-foreground" data-testid="adapt-learned-empty">
              Nothing learned yet. When you correct a BioMate output, the before→after pair is queued
              here as a switchable rule — never applied silently.
            </p>
          )}
        </CardContent>
      </Card>
    </div>
  )
}

// ── Panel ────────────────────────────────────────────────────────────────────
export interface ModelsPanelProps {
  /** Project name shown in the crumb. */
  project?: string
  /** Controlled selected track index (0–4). */
  tab?: number
  onTabChange?: (tab: number) => void
  className?: string
  /**
   * Live training-runs data for the Train track. There is no WS1 read endpoint
   * for training runs in this wave, so the parent supplies it; when absent, the
   * Train track shows its honest empty state (the loop diagram and family
   * catalog are fixed design content and always render).
   */
  trainData?: TrainData
  /**
   * Live adaptation data (learned before→after pairs) for the Adapt track. No
   * WS1 read/persist endpoint in this wave, so the parent owns the pair state;
   * when absent, the Adapt track shows its honest empty state (the level ladder
   * is fixed design content and always renders).
   */
  adaptData?: AdaptData
  /** Toggle a learned rule on/off (parent owns pair state). */
  onAdaptToggle?: (id: string) => void
  /** Queue a re-train over the pending edit pairs. */
  onAdaptRetrain?: () => void
  /**
   * Live DMTA loop data for the Optimise track. There is no WS1 read endpoint
   * for the loop in this wave, so the parent supplies it; when absent, the
   * Optimise track shows its honest empty state.
   */
  optimiseData?: OptimiseData
}

const TRACK_ICONS = [GraduationCap, Wand2, Repeat, Rocket, Library]

export function ModelsPanel({
  project = "Project",
  tab,
  onTabChange,
  className,
  trainData,
  adaptData,
  onAdaptToggle,
  onAdaptRetrain,
  optimiseData,
}: ModelsPanelProps) {
  const [internalTab, setInternalTab] = useState(0)
  const activeTab = tab ?? internalTab
  const setTab = (i: number) => {
    setInternalTab(i)
    onTabChange?.(i)
  }

  const { data: models } = useModels()
  const [openModelId, setOpenModelId] = useState<string | null>(null)

  // Self-fetch the project-scoped track data so the panel works standalone; an
  // explicit prop always overrides the fetched default (parent stays in control).
  const projectArg = project === "Project" ? undefined : project
  const { data: fetchedTrain } = useTrainTrack(projectArg)
  const { data: fetchedAdapt } = useAdaptTrack(projectArg)
  const { data: fetchedOptimise } = useOptimiseTrack(projectArg)
  const effectiveTrainData = trainData ?? fetchedTrain
  const effectiveAdaptData = adaptData ?? fetchedAdapt
  const effectiveOptimiseData = optimiseData ?? fetchedOptimise

  // A model object takes over the whole surface, like the prototype.
  if (openModelId) {
    return (
      <div className={className} data-testid="models-panel">
        <ModelObjectLoader
          modelId={openModelId}
          onBack={() => setOpenModelId(null)}
          onOpenModel={(ref) => setOpenModelId(ref)}
        />
      </div>
    )
  }

  return (
    <div className={className} data-testid="models-panel">
      <Card>
        <CardHeader className="pb-2">
          <div className="flex items-center gap-2 text-xs text-muted-foreground">
            <span>{project}</span>
            <span>/</span>
            <span>Models</span>
          </div>
          <div className="flex items-center gap-2 flex-wrap">
            <CardTitle className="text-base">Models</CardTitle>
            <Badge variant="outline" className="text-[10px]" data-testid="models-count">
              {(models?.length ?? 0)} registered
            </Badge>
          </div>
        </CardHeader>
        <CardContent>
          {/* Uncontrolled Radix Tabs (defaultValue) so in-panel switching works
              without a controlled value; the `key` remounts when a caller drives
              the `tab` prop, and onValueChange still notifies onTabChange. */}
          <Tabs
            key={tab ?? "uncontrolled"}
            defaultValue={String(activeTab)}
            onValueChange={(v) => setTab(Number(v))}
          >
            <TabsList className="mb-3 flex-wrap h-auto" data-testid="models-tabs">
              {MODELS_TRACKS.map((t, i) => {
                const Icon = TRACK_ICONS[i]
                return (
                  <TabsTrigger
                    key={t}
                    value={String(i)}
                    className="text-xs"
                    data-testid={`models-track-${i}`}
                  >
                    <Icon className="h-3 w-3 mr-1" />
                    {t}
                  </TabsTrigger>
                )
              })}
            </TabsList>

            <TabsContent value="0">
              <TrainTrack data={effectiveTrainData} onOpenModel={setOpenModelId} />
            </TabsContent>

            <TabsContent value="1">
              <AdaptTrack
                data={effectiveAdaptData}
                onToggleLearned={onAdaptToggle}
                onRetrain={onAdaptRetrain}
              />
            </TabsContent>

            <TabsContent value="2">
              <OptimiseTrack data={effectiveOptimiseData} onOpenModel={setOpenModelId} />
            </TabsContent>

            <TabsContent value="3">
              <RunPretrained onOpenModel={setOpenModelId} />
            </TabsContent>

            <TabsContent value="4">
              <RegistryTrack onOpenModel={setOpenModelId} />
            </TabsContent>
          </Tabs>
        </CardContent>
      </Card>
    </div>
  )
}
