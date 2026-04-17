/**
 * AutoLoopPanel — shows drug-discovery auto-loop QC results inline.
 *
 * Rendered when the backend emits autoloop_gate_results / autoloop_update /
 * autoloop_phase_complete / autoloop_escalation SSE events for ADMET, docking,
 * CYP-DDI, or NCA-PK phases.
 *
 * Layout
 * ------
 *   • Gate results table (one row per gate, with pass/advisory/halt badge)
 *   • If all passed: green "Phase passed" banner
 *   • If failed: per-gate remediation cards with rationale + citation snippets
 *   • Dismiss button to clear the panel
 */

import { useState } from "react"
import { CheckCircle2, XCircle, AlertTriangle, ChevronDown, ChevronUp, BookOpen, Beaker } from "lucide-react"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"

// ── Types ──────────────────────────────────────────────────────────────────────

export interface AutoLoopGate {
  gate: string
  action: "pass" | "advisory" | "halt"
  level: "GOLD" | "SILVER" | "BRONZE" | "FAIL"
  value: number
  threshold: number
  message: string
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
  complete: AutoLoopCompleteEvent | null
}

// ── Helpers ────────────────────────────────────────────────────────────────────

const DOMAIN_LABELS: Record<string, string> = {
  admet:   "ADMET Safety",
  docking: "Molecular Docking",
  cyp_ddi: "CYP DDI Risk",
  nca_pk:  "NCA Pharmacokinetics",
}

const GATE_LABELS: Record<string, string> = {
  herg_ic50:                    "hERG IC50 (µM)",
  dili_probability:             "DILI Probability",
  dili_risk_level:              "DILI Risk Level",
  ames_mutagenicity:            "Ames Mutagenicity",
  logp:                         "logP (Lipinski)",
  molecular_weight:             "Molecular Weight (Da)",
  valid_poses:                  "Valid Poses",
  best_binding_score:           "Best Binding Score (kcal/mol)",
  clinical_study_isoforms:      "CLINICAL_STUDY isoforms",
  investigate_isoforms:         "INVESTIGATE isoforms",
  tdi_concern:                  "TDI Concern",
  auc_extrapolation:            "AUC Extrapolation (%)",
  terminal_slope_coverage:      "Terminal Slope Coverage",
  t_half_plausibility:          "t½ Plausibility",
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
  // Unknown action — render neutral badge so the gate row is still visible
  return <Badge className="bg-gray-100 text-gray-700 border-gray-200 text-xs">{action.toUpperCase()}</Badge>
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

// Max citations shown inline per remediation — keeps the card compact;
// the full list is available via the suggestion store REST endpoint.
const MAX_INLINE_CITATIONS = 3

// ── RemediationCard sub-component ──────────────────────────────────────────────

function RemediationCard({ rem }: { rem: AutoLoopRemediation }) {
  const [showCitations, setShowCitations] = useState(false)

  const paramEntries = Object.entries(rem.param_changes)

  return (
    <div className="rounded border border-amber-200 bg-amber-50 dark:border-amber-800 dark:bg-amber-950/30 p-3 space-y-2">
      <div className="flex items-start gap-2">
        <Beaker className="h-4 w-4 text-amber-600 mt-0.5 shrink-0" />
        <div className="flex-1 min-w-0">
          <p className="text-sm font-semibold text-amber-900 dark:text-amber-200">
            {gateLabel(rem.gate)}
          </p>
          <p className="text-xs text-amber-800 dark:text-amber-300 mt-0.5">{rem.rationale}</p>
        </div>
      </div>

      {paramEntries.length > 0 && (
        <div className="flex flex-wrap gap-1 ml-6">
          {paramEntries.map(([k, v]) => (
            <span
              key={k}
              className="inline-flex items-center gap-1 text-xs bg-white dark:bg-amber-900/40 border border-amber-200 dark:border-amber-700 rounded px-2 py-0.5"
            >
              <span className="font-mono text-amber-700 dark:text-amber-300">{k}</span>
              <span className="text-gray-400">→</span>
              <span className="font-mono text-blue-700 dark:text-blue-300">{String(v)}</span>
            </span>
          ))}
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

// ── Main component ─────────────────────────────────────────────────────────────

interface AutoLoopPanelProps {
  state: AutoLoopPanelState
  onDismiss: () => void
}

export function AutoLoopPanel({ state, onDismiss }: AutoLoopPanelProps) {
  const { gateResults, remediations, complete } = state

  if (!gateResults) return null

  const domain = DOMAIN_LABELS[gateResults.domain] ?? gateResults.domain
  const haltCount = gateResults.gates.filter(g => g.action === "halt").length
  const advisoryCount = gateResults.gates.filter(g => g.action === "advisory").length

  return (
    <Card
      data-testid="autoloop-panel"
      className="border border-blue-200 dark:border-blue-800 bg-blue-50/60 dark:bg-blue-950/20 shadow-sm"
    >
      <CardHeader className="pb-2 flex flex-row items-start justify-between gap-2">
        <div className="flex items-center gap-2 min-w-0">
          <span className="text-base">🔬</span>
          <CardTitle className="text-sm font-semibold text-blue-900 dark:text-blue-200 truncate">
            Auto-Loop QC — {domain}
          </CardTitle>
          {levelDot(gateResults.overall_level)}
          <span className="text-xs text-gray-500 dark:text-gray-400">{gateResults.overall_level}</span>
        </div>
        <Button variant="ghost" size="sm" className="h-6 w-6 p-0 shrink-0" onClick={onDismiss}>
          ×
        </Button>
      </CardHeader>

      <CardContent className="pt-0 space-y-3">
        {/* Gate results table */}
        <div className="overflow-x-auto">
          <table className="w-full text-xs">
            <thead>
              <tr className="border-b border-blue-200 dark:border-blue-800">
                <th className="text-left py-1 pr-3 text-gray-500 font-normal">Gate</th>
                <th className="text-right py-1 pr-3 text-gray-500 font-normal">Value</th>
                <th className="text-right py-1 pr-3 text-gray-500 font-normal">Threshold</th>
                <th className="text-center py-1 text-gray-500 font-normal">Status</th>
              </tr>
            </thead>
            <tbody>
              {gateResults.gates.map(g => (
                <tr key={g.gate} className="border-b border-blue-100 dark:border-blue-900/40 last:border-0">
                  <td className="py-1 pr-3 text-gray-700 dark:text-gray-300">{gateLabel(g.gate)}</td>
                  <td className="py-1 pr-3 text-right font-mono text-gray-600 dark:text-gray-400">
                    {typeof g.value === "number" ? fmtNum(g.value) : g.value}
                  </td>
                  <td className="py-1 pr-3 text-right font-mono text-gray-500">
                    {typeof g.threshold === "number" ? fmtNum(g.threshold) : g.threshold}
                  </td>
                  <td className="py-1 text-center">{actionBadge(g.action)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        {/* Phase outcome banner */}
        {complete && complete.outcome === "pass" && (
          <div className="flex items-center gap-2 text-green-700 dark:text-green-400 text-sm">
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

        {/* Remediation suggestions */}
        {remediations.length > 0 && (
          <div className="space-y-2">
            <p className="text-xs font-semibold text-amber-800 dark:text-amber-300">
              Suggested parameter adjustments for next run:
            </p>
            {remediations.map((rem, i) => (
              <RemediationCard key={`${rem.phase ?? ""}-${rem.gate}-${i}`} rem={rem} />
            ))}
          </div>
        )}
      </CardContent>
    </Card>
  )
}
