/**
 * AutoLoopPanel — shows drug-discovery auto-loop QC results inline.
 *
 * Rendered when the backend emits autoloop_gate_results / autoloop_update /
 * autoloop_phase_complete / autoloop_escalation SSE events for ADMET, docking,
 * CYP-DDI, NCA-PK, or CiPA cardiac safety phases.
 *
 * Layout
 * ------
 *   • Gate results table (one row per gate, with pass/advisory/halt badge + regulatory_basis tier)
 *   • Expandable suggestion text per gate row
 *   • If all passed: green "Phase passed" banner
 *   • If failed: per-gate remediation cards with rationale + citation snippets
 *     – confident/heuristic: shows was→now param diff
 *     – manual: shows editable input fields so user can provide the value
 *   • Regulatory action notices (REGULATORY basis gates — no param tuning, guidance only)
 *   • "Apply & Re-run" button merges all auto + manual param changes
 */

import { useState } from "react"
import { CheckCircle2, XCircle, AlertTriangle, ChevronDown, ChevronUp, BookOpen, Beaker, ShieldAlert, Info } from "lucide-react"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { QCEvidenceTooltip } from "./qc-evidence-tooltip"

// ── Types ──────────────────────────────────────────────────────────────────────

export interface AutoLoopGate {
  gate: string
  action: "pass" | "advisory" | "halt"
  level: "GOLD" | "SILVER" | "BRONZE" | "FAIL"
  value: number
  threshold: number
  message: string
  suggestion?: string
  regulatory_basis?: "REGULATORY" | "RISK_STRATIFICATION" | "OPERATIONAL"
}

export interface AutoLoopCitation {
  source_text: string
  paper_ref: string
  paper_doi: string
  finding: string
}

export interface AutoLoopRemediation {
  phase: string
  gate: string
  param_changes: Record<string, unknown>
  rationale: string
  citations: AutoLoopCitation[]
  confidence?: "confident" | "heuristic" | "manual"
}

export interface AutoLoopRegulatoryAction {
  gate: string
  regulatory_basis: "REGULATORY"
  action_required: string
  param_changes: Record<string, unknown>
}

export interface AutoLoopGateResultsEvent {
  phase: string
  domain: string
  overall_level: string
  passed: boolean
  gates: AutoLoopGate[]
}

export interface AutoLoopUpdateEvent {
  phase: string
  domain: string
  attempt: number
  next_attempt: number
  remediations: AutoLoopRemediation[]
  regulatory_actions?: AutoLoopRegulatoryAction[]
  regulatory_gate_count?: number
  tunable_gate_count?: number
}

export interface AutoLoopCompleteEvent {
  phase: string
  domain: string
  outcome: "pass" | "escalated"
  level?: string
  failed_gates?: string[]
}

export interface AutoLoopPanelState {
  gateResults: AutoLoopGateResultsEvent | null
  remediations: AutoLoopRemediation[]
  regulatoryActions: AutoLoopRegulatoryAction[]
  complete: AutoLoopCompleteEvent | null
}

// ── Helpers ────────────────────────────────────────────────────────────────────

const DOMAIN_LABELS: Record<string, string> = {
  admet:   "ADMET Safety",
  docking: "Molecular Docking",
  cyp_ddi: "CYP DDI Risk",
  nca_pk:  "NCA Pharmacokinetics",
  cryo_em: "Cryo-EM Processing",
}

const PHASE_LABELS: Record<string, string> = {
  // Cryo-EM phases
  phase_A: "Phase A — Motion Correction & CTF",
  phase_B: "Phase B — Particle Picking",
  phase_C: "Phase C — 2D Classification",
  phase_D: "Phase D — Ab-Initio Model",
  phase_E: "Phase E — FSC Validation",
  // Drug discovery — ADMET
  phase_1_docking:           "Phase 1 — Docking",
  phase_2_admet_prediction:  "Phase 2 — ADMET Prediction",
  phase_3_herg_screen:       "Phase 3 — hERG Screen",
  phase_4_dili_ames:         "Phase 4 — DILI / Ames",
  phase_5_cipa_cardiac:      "Phase 5 — CiPA Cardiac Safety (ICH S7B)",
  phase_6_poppk:             "Phase 6 — Population PK (nlmixr2 / FDA 2019)",
  // DDI / PK
  phase_1_cyp_ddi:           "Phase 1 — CYP DDI",
  phase_1_nca_pk:            "Phase 1 — NCA-PK",
}

function phaseLabel(phase: string): string {
  return PHASE_LABELS[phase] ?? phase.replace(/_/g, " ")
}

const GATE_LABELS: Record<string, string> = {
  // ADMET
  herg_ic50:                    "hERG IC50 (µM)",
  dili_probability:             "DILI Probability",
  dili_risk_level:              "DILI Risk Level",
  bsep_inhibition:              "BSEP Inhibition (Morgan 2010)",
  mito_toxicity:                "Mitochondrial Toxicity (Xu 2008)",
  reactive_metabolites:         "Reactive Metabolite Alerts (Thompson 2006)",
  ames_mutagenicity:            "Ames — Alert-Based (Kazius 2005)",
  ames_statistical_qsar:        "Ames — Statistical QSAR (ICH M7 Model B)",
  ames_model_concordance:       "Ames — Model Concordance (ICH M7 §5.1)",
  logp:                         "logP (Lipinski Ro5)",
  molecular_weight:             "Molecular Weight (Da)",
  // CiPA cardiac safety
  cipa_qnet:                    "CiPA qNET (pC/pF)",
  cipa_apd90_prolongation:      "APD90 Prolongation (%)",
  // Population PK
  poppk_convergence:            "Model Convergence (FDA Pop PK 2019)",
  poppk_eta_shrinkage:          "ETA Shrinkage % (Savic & Karlsson 2009)",
  poppk_condition_number:       "Covariance Condition Number",
  // Docking
  valid_poses:                  "Valid Poses",
  best_binding_score:           "Best Binding Score (kcal/mol)",
  // CYP DDI
  clinical_study_isoforms:      "CLINICAL_STUDY isoforms",
  investigate_isoforms:         "INVESTIGATE isoforms",
  tdi_concern:                  "TDI Concern",
  // NCA-PK
  auc_extrapolation:            "AUC Extrapolation (%)",
  terminal_slope_coverage:      "Terminal Slope Coverage",
  t_half_plausibility:          "t½ Plausibility",
  // Cryo-EM — Phase A
  motion_drift:                 "Total Motion Drift (Å)",
  per_frame_drift:              "Per-Frame Drift (Å/frame)",
  ctf_fit_quality:              "CTF Fit Quality (FOM)",
  astigmatism:                  "Astigmatism (Å)",
  // Cryo-EM — Phase B
  junk_fraction:                "Junk Class Fraction",
  particle_yield:               "Particles Selected",
  orientation_anisotropy:       "Orientation Anisotropy",
  // Cryo-EM — Phase C
  class_quality:                "Mean 2D Class Quality",
  // Cryo-EM — Phase D
  abinitio_class_score:         "Ab-Initio Class Score",
  abinitio_resolution:          "Ab-Initio Resolution (Å)",
  // Cryo-EM — Phase E
  fsc_resolution:               "FSC 0.143 Resolution (Å)",
}

function gateLabel(gate: string): string {
  return GATE_LABELS[gate] ?? gate.replace(/_/g, " ")
}

function actionBadge(action: "pass" | "advisory" | "halt" | string) {
  if (action === "pass")
    return <Badge className="bg-green-100 text-green-800 border-green-200 text-xs">PASS</Badge>
  if (action === "advisory")
    return <Badge className="bg-yellow-100 text-yellow-800 border-yellow-200 text-xs">ADVISORY</Badge>
  if (action === "halt")
    return <Badge className="bg-red-100 text-red-800 border-red-200 text-xs">HALT</Badge>
  return <Badge className="bg-gray-100 text-gray-700 border-gray-200 text-xs">{action.toUpperCase()}</Badge>
}

function regulatoryBasisBadge(basis?: string) {
  if (basis === "REGULATORY")
    return <Badge className="bg-red-50 text-red-700 border-red-200 text-[10px] px-1 py-0">REG</Badge>
  if (basis === "RISK_STRATIFICATION")
    return <Badge className="bg-blue-50 text-blue-700 border-blue-200 text-[10px] px-1 py-0">RISK</Badge>
  return null
}

function confidenceBadge(confidence?: string) {
  if (confidence === "confident")
    return <Badge className="bg-green-50 text-green-700 border-green-200 text-[10px] px-1 py-0">confident</Badge>
  if (confidence === "heuristic")
    return <Badge className="bg-yellow-50 text-yellow-700 border-yellow-200 text-[10px] px-1 py-0">heuristic</Badge>
  if (confidence === "manual")
    return <Badge className="bg-orange-50 text-orange-700 border-orange-200 text-[10px] px-1 py-0">manual input</Badge>
  return null
}

/** Format a gate value/threshold without scientific notation. */
function fmtNum(n: number): string {
  if (!isFinite(n)) return String(n)
  if (Number.isInteger(n)) return n.toString()
  if (Math.abs(n) >= 100)  return n.toFixed(1)
  if (Math.abs(n) >= 1)    return n.toFixed(2)
  return n.toFixed(4)
}

function levelDot(level: string) {
  const colors: Record<string, string> = {
    GOLD:   "bg-yellow-400",
    SILVER: "bg-gray-400",
    BRONZE: "bg-orange-400",
    FAIL:   "bg-red-500",
  }
  return (
    <span className={`inline-block w-2 h-2 rounded-full ${colors[level] ?? "bg-gray-300"} mr-1`} />
  )
}

const MAX_INLINE_CITATIONS = 3

// ── RemediationCard sub-component ──────────────────────────────────────────────

interface RemediationCardProps {
  rem: AutoLoopRemediation
  currentParams?: Record<string, unknown>
  onManualChange?: (gate: string, key: string, value: string) => void
  manualValues?: Record<string, string>
}

function RemediationCard({ rem, currentParams, onManualChange, manualValues }: RemediationCardProps) {
  const [showCitations, setShowCitations] = useState(false)
  const isManual = rem.confidence === "manual"
  const paramEntries = Object.entries(rem.param_changes)

  return (
    <div className="rounded border border-amber-200 bg-amber-50 dark:border-amber-800 dark:bg-amber-950/30 p-3 space-y-2">
      <div className="flex items-start gap-2">
        <Beaker className="h-4 w-4 text-amber-600 mt-0.5 shrink-0" />
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-1.5 flex-wrap">
            <p className="text-sm font-semibold text-amber-900 dark:text-amber-200">
              {gateLabel(rem.gate)}
            </p>
            {confidenceBadge(rem.confidence)}
          </div>
          <p className="text-xs text-amber-800 dark:text-amber-300 mt-0.5">{rem.rationale}</p>
        </div>
      </div>

      {/* confident / heuristic: show was→now diff */}
      {!isManual && paramEntries.length > 0 && (
        <div className="ml-6 space-y-0.5">
          {paramEntries.map(([k, v]) => (
            <div key={k} className="flex items-center gap-2 text-xs font-mono">
              <span className="text-gray-600 dark:text-gray-400 min-w-[120px]">{k}</span>
              <span className="text-red-500 dark:text-red-400 line-through opacity-80">
                {currentParams && k in currentParams ? String(currentParams[k]) : "…"}
              </span>
              <span className="text-gray-400">→</span>
              <span className="text-green-600 dark:text-green-400 font-semibold">{String(v)}</span>
            </div>
          ))}
        </div>
      )}

      {/* manual: editable inputs — system cannot determine correct value */}
      {isManual && (
        <div className="ml-6 space-y-1.5">
          {paramEntries.length > 0 ? (
            <>
              <p className="text-[10px] text-orange-700 dark:text-orange-400 font-medium">
                Enter value(s) manually — system cannot infer from available data:
              </p>
              {paramEntries.map(([k]) => (
                <div key={k} className="flex items-center gap-2 text-xs font-mono">
                  <label className="text-gray-600 dark:text-gray-400 min-w-[120px] shrink-0">{k}</label>
                  <Input
                    className="h-6 text-xs font-mono w-36 px-2"
                    placeholder="enter value…"
                    value={manualValues?.[k] ?? ""}
                    onChange={e => onManualChange?.(rem.gate, k, e.target.value)}
                    data-testid={`autoloop-manual-input-${rem.gate}-${k}`}
                  />
                </div>
              ))}
            </>
          ) : (
            <p className="text-[10px] text-orange-700 dark:text-orange-400">
              Review the gate output and adjust parameters manually before re-running.
            </p>
          )}
        </div>
      )}

      {rem.citations.length > 0 && (
        <div className="ml-6">
          <button
            className="flex items-center gap-1 text-xs text-amber-700 dark:text-amber-400 hover:underline"
            onClick={() => setShowCitations(s => !s)}
          >
            <BookOpen className="h-3 w-3" />
            {showCitations ? "Hide" : "Show"} {rem.citations.length} citation{rem.citations.length !== 1 ? "s" : ""}
            {showCitations ? <ChevronUp className="h-3 w-3" /> : <ChevronDown className="h-3 w-3" />}
          </button>

          {showCitations && (
            <div className="mt-1 space-y-1">
              {rem.citations.slice(0, MAX_INLINE_CITATIONS).map((c, i) => (
                <div key={i} className="text-xs bg-white dark:bg-slate-900 rounded p-2 border border-amber-100 dark:border-amber-900">
                  <p className="font-semibold text-gray-700 dark:text-gray-300">{c.paper_ref}</p>
                  <p className="text-gray-500 dark:text-gray-400 italic mt-0.5 line-clamp-2">
                    "{c.source_text}"
                  </p>
                  <p className="text-blue-600 dark:text-blue-400 mt-0.5">{c.finding}</p>
                </div>
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  )
}

// ── RegulatoryActionCard sub-component ─────────────────────────────────────────

function RegulatoryActionCard({ action }: { action: AutoLoopRegulatoryAction }) {
  return (
    <div className="rounded border border-red-200 bg-red-50 dark:border-red-800 dark:bg-red-950/20 p-3 space-y-1">
      <div className="flex items-start gap-2">
        <ShieldAlert className="h-4 w-4 text-red-600 mt-0.5 shrink-0" />
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-1.5 flex-wrap">
            <p className="text-sm font-semibold text-red-900 dark:text-red-200">
              {gateLabel(action.gate)}
            </p>
            <Badge className="bg-red-100 text-red-700 border-red-300 text-[10px] px-1 py-0">REGULATORY</Badge>
          </div>
          <p className="text-xs text-red-800 dark:text-red-300 mt-0.5">{action.action_required}</p>
        </div>
      </div>
    </div>
  )
}

// ── GateRow with expandable suggestion ─────────────────────────────────────────

function GateRow({ g, domain }: { g: AutoLoopGate; domain: string }) {
  const [expanded, setExpanded] = useState(false)
  const hasSuggestion = !!g.suggestion

  return (
    <>
      <tr
        title={!hasSuggestion ? (g.message || undefined) : undefined}
        className="border-b border-blue-100 dark:border-blue-900/40 last:border-0 cursor-default"
      >
        <td className="py-1 pr-2 font-mono text-gray-700 dark:text-gray-300">
          <div className="flex items-center gap-1 flex-wrap">
            <QCEvidenceTooltip domain={domain} gate={g.gate}>
              {gateLabel(g.gate)}
            </QCEvidenceTooltip>
            {regulatoryBasisBadge(g.regulatory_basis)}
          </div>
        </td>
        <td className={`py-1 pr-3 text-right font-mono font-semibold ${
          g.action === "halt"     ? "text-red-600 dark:text-red-400" :
          g.action === "pass"     ? "text-green-600 dark:text-green-400" :
                                    "text-amber-600 dark:text-amber-400"
        }`}>
          {typeof g.value === "number" ? fmtNum(g.value) : g.value}
        </td>
        <td className="py-1 pr-3 text-right font-mono text-gray-500">
          {typeof g.threshold === "number" ? fmtNum(g.threshold) : g.threshold}
        </td>
        <td className="py-1 text-center">{actionBadge(g.action)}</td>
        <td className="py-1 pl-1 text-center w-6">
          {hasSuggestion && (
            <button
              className="text-blue-400 hover:text-blue-600 dark:text-blue-500 dark:hover:text-blue-300"
              onClick={() => setExpanded(s => !s)}
              title="Show gate guidance"
            >
              <Info className="h-3.5 w-3.5" />
            </button>
          )}
        </td>
      </tr>
      {expanded && g.suggestion && (
        <tr className="bg-blue-50/50 dark:bg-blue-950/10">
          <td colSpan={5} className="py-1.5 px-2 text-[11px] text-blue-800 dark:text-blue-300 italic">
            {g.suggestion}
          </td>
        </tr>
      )}
    </>
  )
}

// ── Main component ─────────────────────────────────────────────────────────────

interface AutoLoopPanelProps {
  state: AutoLoopPanelState
  onDismiss: () => void
  /** Current workflow parameter values — used to show was→now in remediation cards */
  currentParams?: Record<string, unknown>
  /** Called when user clicks "Apply & Re-run". Receives merged param_changes. */
  onAccept?: (paramChanges: Record<string, unknown>) => void
}

export function AutoLoopPanel({ state, onDismiss, onAccept, currentParams }: AutoLoopPanelProps) {
  const { gateResults, remediations, regulatoryActions, complete } = state

  // Manual override values keyed by `${gate}.${param_key}`
  const [manualValues, setManualValues] = useState<Record<string, string>>({})

  function handleManualChange(gate: string, key: string, value: string) {
    setManualValues(prev => ({ ...prev, [`${gate}.${key}`]: value }))
  }

  if (!gateResults) return null

  const domain = DOMAIN_LABELS[gateResults.domain] ?? gateResults.domain
  const haltCount = gateResults.gates.filter(g => g.action === "halt").length
  const advisoryCount = gateResults.gates.filter(g => g.action === "advisory").length

  const tunableRemediations = remediations.filter(r => r.confidence !== undefined)
  const hasManualRems = tunableRemediations.some(r => r.confidence === "manual")

  function buildMergedParams(): Record<string, unknown> {
    const merged: Record<string, unknown> = {}
    for (const rem of tunableRemediations) {
      if (rem.confidence === "manual") {
        // Collect user-entered values for this gate's params
        for (const key of Object.keys(rem.param_changes)) {
          const override = manualValues[`${rem.gate}.${key}`]
          if (override !== undefined && override.trim() !== "") {
            const num = Number(override)
            merged[key] = isNaN(num) ? override : num
          }
        }
      } else {
        Object.assign(merged, rem.param_changes)
      }
    }
    return merged
  }

  return (
    <Card
      data-testid="autoloop-panel"
      className="border border-blue-200 dark:border-blue-800 bg-blue-50/60 dark:bg-blue-950/20 shadow-sm"
    >
      <CardHeader className="pb-2 flex flex-row items-start justify-between gap-2">
        <div className="flex items-center gap-2 min-w-0">
          <span className="text-base">🔬</span>
          <div className="min-w-0">
            <CardTitle className="text-sm font-semibold text-blue-900 dark:text-blue-200 truncate">
              Auto-Loop QC — {domain}
            </CardTitle>
            <p className="text-xs text-blue-700 dark:text-blue-400 truncate">{phaseLabel(gateResults.phase)}</p>
          </div>
          {levelDot(gateResults.overall_level)}
          <span className="text-xs text-gray-500 dark:text-gray-400">{gateResults.overall_level}</span>
        </div>
        <Button variant="ghost" size="sm" className="h-6 w-6 p-0 shrink-0" onClick={onDismiss}>
          ×
        </Button>
      </CardHeader>

      <CardContent className="pt-0 space-y-3">
        {/* Gate results table */}
        <div className="overflow-x-auto" data-testid="autoloop-gate-table">
          <table className="w-full text-xs">
            <thead>
              <tr className="border-b border-blue-200 dark:border-blue-800">
                <th className="text-left py-1 pr-2 text-gray-500 font-normal">Gate</th>
                <th className="text-right py-1 pr-3 text-gray-500 font-normal">Value</th>
                <th className="text-right py-1 pr-3 text-gray-500 font-normal">Threshold</th>
                <th className="text-center py-1 text-gray-500 font-normal">Status</th>
                <th className="w-6" />
              </tr>
            </thead>
            <tbody>
              {gateResults.gates.map(g => (
                <GateRow key={g.gate} g={g} domain={gateResults.domain} />
              ))}
            </tbody>
          </table>
        </div>

        {/* Phase outcome banner */}
        {complete && complete.outcome === "pass" && (
          <div data-testid="autoloop-phase-complete-banner" className="flex items-center gap-2 text-green-700 dark:text-green-400 text-sm">
            <CheckCircle2 className="h-4 w-4 shrink-0" />
            <span>Phase passed ({complete.level ?? gateResults.overall_level})</span>
          </div>
        )}

        {complete && complete.outcome === "escalated" && (
          <div className="flex items-start gap-2 text-red-700 dark:text-red-400 text-sm">
            <XCircle className="h-4 w-4 shrink-0 mt-0.5" />
            <div>
              <p className="font-semibold">Phase escalated — {haltCount} gate{haltCount !== 1 ? "s" : ""} failed</p>
              {complete.failed_gates && complete.failed_gates.length > 0 && (
                <p className="text-xs mt-0.5 text-red-600 dark:text-red-400">
                  {complete.failed_gates.map(gateLabel).join(", ")}
                </p>
              )}
            </div>
          </div>
        )}

        {/* Advisory notice (no halt, but warnings) */}
        {!complete && advisoryCount > 0 && haltCount === 0 && (
          <div className="flex items-center gap-2 text-yellow-700 dark:text-yellow-400 text-xs">
            <AlertTriangle className="h-3.5 w-3.5 shrink-0" />
            <span>{advisoryCount} advisory warning{advisoryCount !== 1 ? "s" : ""} — phase will continue</span>
          </div>
        )}

        {/* Regulatory actions — REGULATORY basis gates, guidance only, no re-run */}
        {regulatoryActions && regulatoryActions.length > 0 && (
          <div className="space-y-2" data-testid="autoloop-regulatory-actions">
            <p className="text-xs font-semibold text-red-800 dark:text-red-300">
              Regulatory actions required (parameter tuning cannot resolve):
            </p>
            {regulatoryActions.map((a, i) => (
              <RegulatoryActionCard key={`${a.gate}-${i}`} action={a} />
            ))}
          </div>
        )}

        {/* Tunable remediation suggestions (RISK_STRATIFICATION gates) */}
        {tunableRemediations.length > 0 && (
          <div className="space-y-2" data-testid="autoloop-remediation-card">
            <p className="text-xs font-semibold text-amber-800 dark:text-amber-300">
              Suggested parameter adjustments for next run:
            </p>
            {tunableRemediations.map((rem, i) => (
              <RemediationCard
                key={`${rem.phase ?? ""}-${rem.gate}-${i}`}
                rem={rem}
                currentParams={currentParams}
                onManualChange={handleManualChange}
                manualValues={
                  Object.fromEntries(
                    Object.keys(rem.param_changes).map(k => [k, manualValues[`${rem.gate}.${k}`] ?? ""])
                  )
                }
              />
            ))}

            {onAccept && (() => {
              const merged = buildMergedParams()
              const hasAuto  = tunableRemediations.some(r => r.confidence !== "manual" && Object.keys(r.param_changes).length > 0)
              const canApply = hasAuto || (hasManualRems && Object.keys(merged).length > 0)
              if (!canApply) return null
              return (
                <Button
                  size="sm"
                  className="mt-1 w-full bg-amber-600 hover:bg-amber-700 text-white text-xs"
                  data-testid="autoloop-accept-btn"
                  onClick={() => onAccept(merged)}
                >
                  <Beaker className="h-3.5 w-3.5 mr-1.5" />
                  Apply {Object.keys(merged).length} change{Object.keys(merged).length !== 1 ? "s" : ""} &amp; Re-run
                </Button>
              )
            })()}
          </div>
        )}
      </CardContent>
    </Card>
  )
}
