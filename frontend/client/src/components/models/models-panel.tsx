import { originLabel } from "./model-origin"
/**
 * ModelsPanel — the Models surface, three tabs:
 *
 *   训练 (Train)        general ML/DL: tabular classification/regression
 *                       (scikit-learn + Ludwig neural net), LLM fine-tuning
 *                       (LoRA / DPO / GRPO), scRNA + protein diffusion.
 *                       Configure → RUN (POST /api/model-training/plan then
 *                       POST /api/workflows/execute) + the training-runs list.
 *   模型库 (Library)     Registry + run a model, merged: the account catalog,
 *                       owned registered artifacts, and inference. A model whose
 *                       last inference failed shows the real reason.
 *   分子学习 (Molecular)  molecular property models (RDKit over SMILES) and the
 *                       design–make–test–analyse rounds.
 *
 * Removed in the 2026-11-10 rebuild: every "set up in chat" draft (the panel
 * runs training itself now), the "pre-built foundation models" workflow-search
 * section (it searched Nextflow pipelines, not models), and the House style tab
 * (see HOUSE_STYLE_HIDDEN). All visible strings come from the models.* i18n
 * namespace, complete in both en and zh.
 */

import { useEffect, useRef, useState } from "react"
import { useQueryClient } from "@tanstack/react-query"
import { t, tOr } from "@/lib/i18n"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs"
import { Skeleton } from "@/components/ui/skeleton"
import { GraduationCap, Library, FlaskConical, Sparkles, ChevronRight, AlertTriangle } from "lucide-react"
import { useModels, useTrainTrack, useOptimiseTrack } from "./models-api"
import { useActiveProjectSafe } from "@/contexts/active-project-context"
import { ModelObjectLoader } from "./model-object"
import { OwnedTrainingRegistry } from "./owned-training-registry"
import { RunPretrained } from "./run-pretrained"
import { TrainingLauncher } from "./training-launcher"
import { CodeSandboxPath } from "./code-sandbox-path"
import { formatRunTime, openRunManager, runStatusLabel } from "./training-logic"
import { TrainingRegistration } from "./training-registration"
import { RoundsSection } from "./dmta-rounds"
import { AdaptTrack } from "./adapt-track"
import type { ModelSummary } from "./types"

/** Resolve /models?tab=molecular|library|train|0|1|2 → tab index. */
export function tabIndexFromSearch(search: string): number | undefined {
  const raw = new URLSearchParams(search.startsWith("?") ? search.slice(1) : search).get("tab")
  if (raw == null || raw === "") return undefined
  if (raw === "train" || raw === "0") return 0
  if (raw === "library" || raw === "1") return 1
  if (raw === "molecular" || raw === "2") return 2
  if (raw === "adapt" || raw === "3") return 3
  const n = Number(raw)
  return Number.isInteger(n) && n >= 0 && n <= 3 ? n : undefined
}

/** Train-tab path: no-code UI (clinicians) vs code sandbox (power users). */
export type TrainPath = "ui" | "code"

/**
 * Adaptation (house style) is now surfaced as a first-class track. It wires the
 * AdaptTrack component to the live hooks (useAdaptTrack / useAdaptToggle /
 * useAdaptRetrain). The track is honest about what it does: it compiles the
 * phrasings you keep on BioMate's drafts into a retrieval index it reuses when it
 * writes (personalisation), NOT a model-weight retrain. When no edit pairs have
 * been recorded yet it shows an honest empty state rather than being hidden.
 * (Kept as an exported const — now false — so callers/tests can still reference it.)
 */
export const HOUSE_STYLE_HIDDEN = false

/**
 * The Code sandbox path is hidden for now (not deleted). It is a bare run_code
 * textarea with no catalog/model awareness, redundant with chat's run_code tool
 * (which has the LLM + knows the catalog and data). CodeSandboxPath and its tests
 * remain; flip this to false to restore the No-code ↔ Code toggle on the Train tab.
 */
export const CODE_PATH_HIDDEN = true

/** Tab ids, in display order. */
export const MODELS_TRACKS = ["train", "library", "molecular", "adapt"] as const
export type ModelsTrack = (typeof MODELS_TRACKS)[number]
const TRACK_ICONS = [GraduationCap, Library, FlaskConical, Sparkles]

// ── 模型库 — catalog ─────────────────────────────────────────────────────────
function CatalogTable({ rows, onOpenModel, onRun }: { rows: ModelSummary[]; onOpenModel: (id: string) => void; onRun?: (id: string) => void }) {
  return (
    <div className="rounded border text-xs" data-testid="registry-table">
      <div className="grid grid-cols-[1.4fr_1fr_0.8fr_0.8fr_auto] gap-2 bg-muted px-2 py-1 font-semibold">
        <span>{t("models.col_model")}</span>
        <span>{t("models.col_family")}</span>
        <span>{t("models.col_origin")}</span>
        <span>{t("models.col_used_by")}</span>
        <span />
      </div>
      {rows.map((m) => (
        <div key={m.id} className="border-t">
          {/* The row's info is one clickable area (opens the model); Run sits beside it
              so a model can be launched straight from the catalog, no detour. */}
          <div className="grid grid-cols-[1.4fr_1fr_0.8fr_0.8fr_auto] items-center gap-2 px-2 py-1.5 hover:bg-muted/40">
            <button
              type="button"
              className="contents text-left"
              data-testid={`registry-row-${m.id}`}
              onClick={() => onOpenModel(m.id)}
            >
              <span className="truncate font-mono font-semibold">
                {m.name} <span className="text-muted-foreground">{m.version}</span>
              </span>
              <span className="truncate text-muted-foreground">{m.family}</span>
              <span className="truncate text-muted-foreground">{originLabel(m.origin)}</span>
              <span className="text-muted-foreground">{m.usedByCount}</span>
            </button>
            <div className="flex items-center justify-end gap-1">
              {onRun && (
                <button
                  type="button"
                  className="rounded border px-1.5 py-0.5 text-fs-xs hover:bg-muted"
                  data-testid={`registry-row-run-${m.id}`}
                  onClick={() => onRun(m.id)}
                >
                  {t("models.run_action")}
                </button>
              )}
              <ChevronRight className="h-3.5 w-3.5 text-muted-foreground" />
            </div>
          </div>
          {m.lastInference?.status === "failed" && (
            <p
              className="flex items-start gap-1 px-2 pb-1.5 text-fs-xs text-destructive"
              data-testid={`registry-row-failure-${m.id}`}
            >
              <AlertTriangle className="mt-0.5 h-3 w-3 shrink-0" />
              <span className="break-words">
                {t("models.last_inference_failed", {
                  detail: m.lastInference.error || t("models.reason_unavailable"),
                })}
              </span>
            </p>
          )}
        </div>
      ))}
    </div>
  )
}

function LibraryTrack({ project, onOpenModel, preselectModelId }: { project?: string; onOpenModel: (id: string) => void; preselectModelId?: string | null }) {
  const { data: models, isLoading, isError } = useModels()
  // A Run clicked on a catalog row preselects the "Run a model" card below and
  // scrolls to it (local, so it also layers over an incoming preselectModelId).
  const [rowRun, setRowRun] = useState<string | null>(null)
  const runRef = useRef<HTMLDivElement>(null)
  const runModel = (id: string) => {
    setRowRun(id)
    requestAnimationFrame(() => {
      const el = runRef.current
      if (el && typeof el.scrollIntoView === "function") el.scrollIntoView({ behavior: "smooth", block: "nearest" })
    })
  }
  return (
    <div className="space-y-3" data-testid="track-library">
      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-sm">{t("models.library_catalog_heading")}</CardTitle>
          <p className="text-fs-xs text-muted-foreground">{t("models.library_catalog_hint")}</p>
        </CardHeader>
        <CardContent>
          {isLoading ? (
            <div className="space-y-2" data-testid="registry-loading">
              <Skeleton className="h-8 w-full" />
              <Skeleton className="h-8 w-full" />
            </div>
          ) : isError ? (
            <p className="text-xs text-destructive" data-testid="registry-error">
              {t("models.registry_catalog_error")}
            </p>
          ) : (models ?? []).length ? (
            <CatalogTable rows={models as ModelSummary[]} onOpenModel={onOpenModel} onRun={runModel} />
          ) : (
            <p className="text-xs text-muted-foreground" data-testid="registry-empty">
              {t("models.registry_empty_catalog")}
            </p>
          )}
        </CardContent>
      </Card>

      {/* Owned, registered training artifacts (versions + gate evidence). */}
      <OwnedTrainingRegistry project={project} />

      {/* Run a model — merged here so the catalog and inference are one place. */}
      <div ref={runRef}>
        <RunPretrained onOpenModel={onOpenModel} initialModelId={rowRun ?? preselectModelId ?? undefined} />
      </div>
    </div>
  )
}

// ── Training runs list (训练 tab) ────────────────────────────────────────────
export interface TrainRun {
  runId?: string
  registrationEligible?: boolean
  chatSessionId?: string
  createdAt?: string | null
  name: string
  family: string
  when: string
  /** "running" | "completed" | "failed" | anything else → queued/other. */
  status: string
  gate: string
  metric: string
  /** Structured training result (from the run's metrics.json); absent → not recorded. */
  metricName?: string
  metricValue?: number
  gateStatus?: "pass" | "fail" | null
  gateThreshold?: number | null
  dataset: string
  version?: string
  modelId?: string
}
export interface TrainData { runs: TrainRun[] }

function trainStatusColor(status: string): string {
  if (status === "completed") return "#22c55e"
  if (status === "failed" || status === "interrupted") return "#ef4444"
  if (status === "running") return "#3b82f6"
  return "#94a3b8"
}

function notRecorded(value: string): string {
  return value === "Not recorded" ? t("models.not_recorded") : value
}

/** "准确率 0.896" / "Accuracy 0.896" — the same metric names the launcher's 验证指标 uses. */
function metricLabel(r: TrainRun): string {
  return r.metricName && typeof r.metricValue === "number"
    ? t("models.run_metric", { metric: tOr(`models.metric_${r.metricName}`, r.metricName), value: r.metricValue.toFixed(3) })
    : t("models.not_recorded")
}

/** "通过 · 阈值 0.60" / "Passed · threshold 0.60". */
function gateLabel(r: TrainRun): string {
  if (r.gateStatus !== "pass" && r.gateStatus !== "fail") return t("models.not_recorded")
  const key = r.gateStatus === "pass" ? "models.run_gate_pass" : "models.run_gate_fail"
  return typeof r.gateThreshold === "number"
    ? t(key + "_threshold", { threshold: r.gateThreshold.toFixed(2) })
    : t(key)
}

// Inline rename + delete for a training run, so the user can manage runs right
// here in the Train tab instead of discovering a separate Run Manager.
function RunManageControls({ runId, currentName, onChanged }: { runId: string; currentName: string; onChanged: () => void }) {
  const [mode, setMode] = useState<"idle" | "rename" | "confirmDelete">("idle")
  const [name, setName] = useState(currentName)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState("")

  const save = async () => {
    const next = name.trim()
    if (!next || next === currentName) { setMode("idle"); return }
    setBusy(true); setError("")
    try {
      const res = await fetch(`/api/workflows/runs/${encodeURIComponent(runId)}`, {
        method: "PATCH", credentials: "include",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ workflowName: next }),
      })
      if (!res.ok) throw new Error((await res.json().catch(() => ({})))?.error || t("models.run_rename_failed"))
      setMode("idle"); onChanged()
    } catch (cause) { setError((cause as Error).message || t("models.run_rename_failed")) } finally { setBusy(false) }
  }
  const remove = async () => {
    setBusy(true); setError("")
    try {
      const res = await fetch(`/api/workflows/runs/${encodeURIComponent(runId)}`, { method: "DELETE", credentials: "include" })
      if (!res.ok) throw new Error((await res.json().catch(() => ({})))?.error || t("models.run_delete_failed"))
      onChanged()
    } catch (cause) { setError((cause as Error).message || t("models.run_delete_failed")); setBusy(false) }
  }

  if (mode === "rename") {
    return (
      <span className="inline-flex flex-wrap items-center gap-1">
        <input
          className="rounded border bg-background px-1 py-0.5 text-fs-xs" value={name} autoFocus disabled={busy}
          onChange={(e) => setName(e.target.value)}
          onKeyDown={(e) => { if (e.key === "Enter") save(); if (e.key === "Escape") { setMode("idle"); setName(currentName) } }}
          data-testid={`train-run-rename-input-${runId}`} aria-label={t("models.run_rename")}
        />
        <button type="button" className="text-primary hover:underline" disabled={busy} onClick={save} data-testid={`train-run-rename-save-${runId}`}>{t("models.run_rename_save")}</button>
        <button type="button" className="text-muted-foreground hover:underline" disabled={busy} onClick={() => { setMode("idle"); setName(currentName) }}>{t("models.cancel")}</button>
        {error && <span className="text-destructive">{error}</span>}
      </span>
    )
  }
  if (mode === "confirmDelete") {
    return (
      <span className="inline-flex flex-wrap items-center gap-1">
        <span className="text-muted-foreground">{t("models.run_delete_confirm")}</span>
        <button type="button" className="text-destructive hover:underline" disabled={busy} onClick={remove} data-testid={`train-run-delete-confirm-${runId}`}>{t("models.run_delete")}</button>
        <button type="button" className="text-muted-foreground hover:underline" disabled={busy} onClick={() => setMode("idle")}>{t("models.cancel")}</button>
        {error && <span className="text-destructive">{error}</span>}
      </span>
    )
  }
  return (
    <span className="inline-flex items-center gap-2">
      <button type="button" className="text-muted-foreground hover:underline" onClick={() => { setName(currentName); setMode("rename") }} data-testid={`train-run-rename-${runId}`}>{t("models.run_rename")}</button>
      <button type="button" className="text-muted-foreground hover:underline" onClick={() => setMode("confirmDelete")} data-testid={`train-run-delete-${runId}`}>{t("models.run_delete")}</button>
    </span>
  )
}

export function TrainingRuns({ data, onOpenModel }: { data?: TrainData; onOpenModel: (id: string) => void }) {
  const runs = data?.runs ?? []
  const queryClient = useQueryClient()
  const refreshRuns = () => queryClient.invalidateQueries({ queryKey: ["/api/model-tracks/train"] })
  return (
    <Card data-testid="train-runs">
      <CardHeader className="pb-2">
        <CardTitle className="text-sm">{t("models.training_runs_heading")}</CardTitle>
      </CardHeader>
      <CardContent className="space-y-2">
        {runs.length ? (
          runs.map((r) => (
            <div
              key={r.runId || r.name}
              className="space-y-1 rounded border px-2 py-1.5 text-xs"
              data-testid={`train-run-${r.name}`}
            >
              <div className="flex flex-wrap items-center gap-2">
                <span className="font-semibold">{r.name}</span>
                <Badge variant="outline" className="text-fs-xs">
                  {r.family === "ml_training" ? t("models.training_workflow") : t("models.adaptation_workflow")}
                </Badge>
                <span className="ml-auto text-fs-xs text-muted-foreground" title={r.when}>{r.when === "Not recorded" ? notRecorded(r.when) : formatRunTime(r.when)}</span>
                <Badge
                  variant="outline"
                  className="gap-1 text-fs-xs"
                  style={{ color: trainStatusColor(r.status) }}
                  data-testid={`train-run-status-${r.name}`}
                >
                  <span className="inline-block h-1.5 w-1.5 rounded-full" style={{ background: trainStatusColor(r.status) }} />
                  {runStatusLabel(r.status)}
                </Badge>
              </div>
              <div className="flex flex-wrap items-center gap-2">
                <Badge variant="outline" className="text-fs-xs" data-testid={`train-run-metric-${r.name}`}>{metricLabel(r)}</Badge>
                <Badge variant="outline" className="text-fs-xs" data-testid={`train-run-gate-${r.name}`}
                  style={r.gateStatus === "pass" ? { color: "#15803d" } : r.gateStatus === "fail" ? { color: "#b91c1c" } : undefined}>
                  {gateLabel(r)}
                </Badge>
                <span className="truncate font-mono text-fs-xs text-muted-foreground">{notRecorded(r.dataset)}</span>
                {r.runId && /^(completed|complete|success|succeeded)$/i.test(r.status) && (
                  <TrainingRegistration runId={r.runId} eligible={r.registrationEligible} />
                )}
                {r.runId && (
                  <button
                    type="button"
                    className="ml-auto text-primary hover:underline"
                    data-testid={`train-run-open-run-${r.runId}`}
                    onClick={() => openRunManager()}
                  >
                    {t("models.open_in_run_manager")}
                  </button>
                )}
                {r.modelId && (
                  <button
                    type="button"
                    className="text-primary hover:underline"
                    onClick={() => r.modelId && onOpenModel(r.modelId)}
                    data-testid={`train-run-open-${r.name}`}
                  >
                    {t("models.open_model")}
                  </button>
                )}
              </div>
              {r.runId && (
                <RunManageControls runId={r.runId} currentName={r.name} onChanged={refreshRuns} />
              )}
              {r.version && <p className="text-fs-xs text-muted-foreground">{r.version}</p>}
            </div>
          ))
        ) : (
          <p className="text-fs-xs text-muted-foreground" data-testid="train-runs-empty">
            {t("models.training_runs_empty")}
          </p>
        )}
      </CardContent>
    </Card>
  )
}

// ── 分子学习 — rounds (DMTA) ────────────────────────────────────────────────
export interface OptimiseSurrogate { id: string; label: string }
export interface OptimiseRound { round: string; status: string; what: string; when: string }
export interface OptimiseProposal { id: string; score: string; confidence: string; verdict: string }
export interface OptimiseData {
  running: boolean
  round: string | number
  budget?: string
  refitPolicy?: string
  /** The active campaign's DMTA modality — fixed at creation; the panel reflects
   *  it so the modality selector matches the loop actually being shown. */
  modality?: "small_molecule" | "peptide" | "biologic"
  surrogates: OptimiseSurrogate[]
  rounds: OptimiseRound[]
  proposal: OptimiseProposal[]
}

function TrackRequestState({ query, overridden, children }: {
  query: { isPending: boolean; isError: boolean; refetch: () => unknown }
  overridden: boolean
  children: React.ReactNode
}) {
  if (!overridden && query.isPending) return <p role="status">{t("models.activity_loading")}</p>
  if (!overridden && query.isError) return (
    <div role="alert" className="space-y-2 rounded-lg border border-destructive/30 p-4">
      <p>{t("models.activity_error")}</p>
      <Button variant="outline" size="sm" onClick={() => query.refetch()}>{t("models.retry")}</Button>
    </div>
  )
  return <>{children}</>
}

// ── Panel ────────────────────────────────────────────────────────────────────
export interface ModelsPanelProps {
  project?: string
  /** Controlled selected tab index (0–2). */
  tab?: number
  onTabChange?: (tab: number) => void
  className?: string
  /** Explicit training-runs data (overrides the self-fetched track read). */
  trainData?: TrainData
  /** Explicit DMTA loop data for 分子学习 (overrides the self-fetched read). */
  optimiseData?: OptimiseData
}

export function ModelsPanel({
  project = "Project", tab, onTabChange, className, trainData, optimiseData,
}: ModelsPanelProps) {
  const [internalTab, setInternalTab] = useState(0)
  // Deep-link /models?tab=molecular (chat Optimise → Models Rounds).
  useEffect(() => {
    if (tab !== undefined) return
    try {
      const fromUrl = tabIndexFromSearch(window.location.search)
      if (fromUrl !== undefined) setInternalTab(fromUrl)
    } catch { /* non-browser */ }
  }, [tab])
  const activeTab = tab ?? internalTab
  const setTab = (i: number) => { setInternalTab(i); onTabChange?.(i) }
  // Two paths on Train: default no-code launcher; code → owned run_code sandbox
  // (not Galaxy Interactive Tools — those never worked in BioMate).
  const [trainPath, setTrainPath] = useState<TrainPath>("ui")

  const { data: models } = useModels()
  const [openModelId, setOpenModelId] = useState<string | null>(null)
  // A model the user chose to "use in a run" — lands on the Library tab with
  // RunPretrained preselected to it, so the detail view is no longer a dead end.
  const [runPreselect, setRunPreselect] = useState<string | null>(null)

  // The Models page renders <ModelsPanel/> with no `project` prop (it defaults to
  // the "Project" placeholder), so scope the track queries to the ACTIVE project
  // from context — otherwise /api/model-tracks/optimise is called with no project
  // and the backend falls back to the owner's first campaign, showing a DIFFERENT
  // campaign's rounds than the active project. The Rounds controls already use the
  // active-project context directly, so without this the display and the actions
  // target different campaigns.
  const activeProjectCtx = useActiveProjectSafe()
  const projectArg = project && project !== "Project"
    ? project
    : (activeProjectCtx?.activeProjectId || undefined)
  const trainQuery = useTrainTrack(projectArg)
  const optimiseQuery = useOptimiseTrack(projectArg)
  const effectiveTrainData = trainData ?? trainQuery.data
  const effectiveOptimiseData = optimiseData ?? optimiseQuery.data ?? undefined

  if (openModelId) {
    return (
      <div className={className} data-testid="models-panel">
        <ModelObjectLoader
          modelId={openModelId}
          onBack={() => setOpenModelId(null)}
          onOpenModel={(ref) => setOpenModelId(ref)}
          // Wire the detail actions so the model page is no longer a dead end:
          onUseInRun={(id) => { setRunPreselect(id); setOpenModelId(null); setTab(1) }}
          onSupersede={() => { setOpenModelId(null); setTab(0) }}
          onOpenRun={() => openRunManager()}
        />
      </div>
    )
  }

  return (
    <div className={className} data-testid="models-panel">
      <Card>
        <CardHeader className="pb-2">
          <div className="flex items-center gap-2 text-xs text-muted-foreground">
            <span>{project === "Project" ? t("models.account_scope") : project}</span>
            <span>/</span>
            <span>{t("models.panel_title")}</span>
          </div>
          <div className="flex flex-wrap items-center gap-2">
            <CardTitle className="text-base">{t("models.panel_title")}</CardTitle>
            <Badge variant="outline" className="text-fs-xs" data-testid="models-count">
              {t("models.registered_count", { count: models?.length ?? 0 })}
            </Badge>
          </div>
          <p className="text-fs-xs text-muted-foreground" data-testid="models-panel-subtitle">
            {t("models.panel_subtitle")}
          </p>
        </CardHeader>
        <CardContent>
          <Tabs value={String(activeTab)} onValueChange={(v) => setTab(Number(v))}>
            <TabsList className="mb-3 h-auto flex-wrap" data-testid="models-tabs">
              {MODELS_TRACKS.map((track, i) => {
                const Icon = TRACK_ICONS[i]
                return (
                  <TabsTrigger key={track} value={String(i)} className="text-xs" data-testid={`models-track-${i}`}>
                    <Icon className="mr-1 h-3 w-3" />
                    {t(`models.tab_${track}`)}
                  </TabsTrigger>
                )
              })}
            </TabsList>

            <TabsContent value="0" className="space-y-3">
              <p className="text-fs-xs text-muted-foreground" data-testid="tab-purpose-train">
                {t("models.tab_purpose_train")}
              </p>
              {/* Up-front: the algorithm families trainable here, so the scope is clear
                  before a dataset is picked (the exact options then adapt to the data). */}
              <div className="rounded border bg-muted/30 p-2 text-fs-xs" data-testid="train-capabilities">
                <p className="font-semibold text-muted-foreground">{t("models.train_capabilities_heading")}</p>
                <ul className="mt-1 space-y-0.5 text-muted-foreground">
                  <li>• {t("models.train_cap_tabular")}</li>
                  <li>• {t("models.train_cap_llm")}</li>
                  <li>• {t("models.train_cap_generative")}</li>
                </ul>
                <p className="mt-1 text-muted-foreground/70">{t("models.train_cap_note")}</p>
              </div>
              {!CODE_PATH_HIDDEN && (
                <div className="flex flex-wrap gap-1" data-testid="train-path-toggle" role="group" aria-label={t("models.path_toggle_label")}>
                  <Button
                    type="button"
                    size="sm"
                    variant={trainPath === "ui" ? "default" : "outline"}
                    className="h-7 text-xs"
                    onClick={() => setTrainPath("ui")}
                    data-testid="train-path-ui"
                  >
                    {t("models.path_ui")}
                  </Button>
                  <Button
                    type="button"
                    size="sm"
                    variant={trainPath === "code" ? "default" : "outline"}
                    className="h-7 text-xs"
                    onClick={() => setTrainPath("code")}
                    data-testid="train-path-code"
                  >
                    {t("models.path_code")}
                  </Button>
                </div>
              )}
              <p className="text-fs-xs text-muted-foreground" data-testid="train-path-hint">
                {CODE_PATH_HIDDEN || trainPath === "ui" ? t("models.path_ui_hint") : t("models.path_code_hint")}
              </p>
              {CODE_PATH_HIDDEN || trainPath === "ui" ? (
                <>
                  <TrainingLauncher family="general" />
                  <TrackRequestState query={trainQuery} overridden={trainData !== undefined}>
                    <TrainingRuns data={effectiveTrainData} onOpenModel={setOpenModelId} />
                  </TrackRequestState>
                </>
              ) : (
                <CodeSandboxPath />
              )}
            </TabsContent>

            <TabsContent value="1" className="space-y-3">
              <p className="text-fs-xs text-muted-foreground" data-testid="tab-purpose-library">
                {t("models.tab_purpose_library")}
              </p>
              <LibraryTrack project={projectArg} onOpenModel={setOpenModelId} preselectModelId={runPreselect} />
            </TabsContent>

            <TabsContent value="2" className="space-y-3">
              <p className="text-fs-xs text-muted-foreground" data-testid="tab-purpose-molecular">
                {t("models.tab_purpose_molecular")}
              </p>
              {/* Loop leads; the molecular launcher sits below, scoped as the loop's surrogate model. */}
              <TrackRequestState query={optimiseQuery} overridden={optimiseData !== undefined}>
                <RoundsSection
                  data={effectiveOptimiseData ?? undefined}
                  projectId={projectArg}
                  onOpenModel={setOpenModelId}
                />
              </TrackRequestState>
              <div className="space-y-1" data-testid="loop-surrogate-section">
                <p className="text-fs-xs text-muted-foreground">{t("models.loop_model_note")}</p>
                <TrainingLauncher family="molecular" />
              </div>
            </TabsContent>

            <TabsContent value="3" className="space-y-3">
              <p className="text-fs-xs text-muted-foreground" data-testid="tab-purpose-adapt">
                {t("models.tab_purpose_adapt")}
              </p>
              <AdaptTrack project={projectArg} />
            </TabsContent>
          </Tabs>
        </CardContent>
      </Card>
    </div>
  )
}
