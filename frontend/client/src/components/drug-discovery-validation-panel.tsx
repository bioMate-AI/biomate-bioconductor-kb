/**
 * Surface 2 — PBPK/ADMET Model Validation Panel
 *
 * Fetches GET /api/drug-discovery/model-validation/pbpk
 * Returns a ValidationReport (see model_validation.py):
 *   model_type, dataset_name, n_reference_compounds, per_compound[],
 *   metrics: { AFE_Cmax, AAFE_Cmax, R2_Cmax, within_2fold_Cmax,
 *              within_3fold_Cmax, AFE_AUC, AAFE_AUC, R2_AUC,
 *              within_2fold_AUC, within_3fold_AUC, ema_criterion_met },
 *   ema_criterion_met, regulatory_summary, warnings
 *
 * PerCompoundResult: name, dose_mg, route, observed_Cmax, predicted_Cmax,
 *   observed_AUC, predicted_AUC, fold_error_Cmax, fold_error_AUC, in_domain
 *
 * Regulatory reference: EMA/CHMP/EWP/37498/2011 — ≥67% within 2-fold
 */
import { useState, useEffect, useCallback } from "react"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert"
import {
  Collapsible,
  CollapsibleContent,
  CollapsibleTrigger,
} from "@/components/ui/collapsible"
import {
  CheckCircle2,
  XCircle,
  AlertTriangle,
  ChevronDown,
  RefreshCw,
  Download,
  Search,
  Loader2,
} from "lucide-react"
import { cn } from "@/lib/utils"

// ─────────────────────────────────────────────────────────────────────────────
// Types (mirror model_validation.py)
// ─────────────────────────────────────────────────────────────────────────────

interface PerCompound {
  name: string
  dose_mg: number
  route: string
  observed_Cmax: number
  predicted_Cmax: number | null
  observed_AUC: number
  predicted_AUC: number | null
  fold_error_Cmax: number | null
  fold_error_AUC: number | null
  in_domain: boolean
  notes?: string
}

interface ValidationMetrics {
  n_compounds: number
  AFE_Cmax: number
  AAFE_Cmax: number
  RMSE_Cmax: number
  R2_Cmax: number
  within_2fold_Cmax: number
  within_3fold_Cmax: number
  AFE_AUC: number
  AAFE_AUC: number
  RMSE_AUC: number
  R2_AUC: number
  within_2fold_AUC: number
  within_3fold_AUC: number
  ema_criterion_met: boolean
}

interface ValidationReport {
  model_type: string
  dataset_name: string
  n_reference_compounds: number
  per_compound: PerCompound[]
  metrics: ValidationMetrics
  regulatory_summary: string
  ema_criterion_met: boolean
  warnings: string[]
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-components
// ─────────────────────────────────────────────────────────────────────────────

function FoldCell({ fold }: { fold: number | null }) {
  if (fold === null) return <span className="text-muted-foreground text-xs">—</span>
  const abs = Math.abs(fold)
  const label = fold < 1 ? `${fold.toFixed(2)}×` : `${fold.toFixed(2)}×`
  const color =
    abs <= 2 ? "text-green-700 dark:text-green-400"
    : abs <= 3 ? "text-amber-700 dark:text-amber-400"
    : "text-red-700 dark:text-red-400"
  const bgColor =
    abs <= 2 ? "bg-green-100 dark:bg-green-900/30"
    : abs <= 3 ? "bg-amber-100 dark:bg-amber-900/30"
    : "bg-red-100 dark:bg-red-900/30"
  return (
    <span className={cn("font-mono text-xs px-1.5 py-0.5 rounded", color, bgColor)}>
      {label}
    </span>
  )
}

function AdBadge({ inDomain }: { inDomain: boolean }) {
  return inDomain ? (
    <Badge variant="outline" className="text-xs font-mono text-green-700 dark:text-green-400 border-green-300">
      in-domain
    </Badge>
  ) : (
    <Badge variant="outline" className="text-xs font-mono text-amber-700 dark:text-amber-400 border-amber-300">
      OOD
    </Badge>
  )
}

function MetricRow({
  label,
  cmaxVal,
  aucVal,
  interpretation,
  highlight,
}: {
  label: string
  cmaxVal: string
  aucVal: string
  interpretation: string
  highlight?: { cmax?: boolean; auc?: boolean }
}) {
  return (
    <tr>
      <td className="py-1.5 pr-3 text-xs font-medium">{label}</td>
      <td className={cn(
        "py-1.5 px-2 text-right font-mono text-xs",
        highlight?.cmax
          ? "text-green-700 dark:text-green-400 font-semibold"
          : "text-foreground"
      )}>
        {cmaxVal}
      </td>
      <td className={cn(
        "py-1.5 px-2 text-right font-mono text-xs",
        highlight?.auc
          ? "text-green-700 dark:text-green-400 font-semibold"
          : "text-foreground"
      )}>
        {aucVal}
      </td>
      <td className="py-1.5 pl-3 text-xs text-muted-foreground">{interpretation}</td>
    </tr>
  )
}

// ─────────────────────────────────────────────────────────────────────────────
// Main component
// ─────────────────────────────────────────────────────────────────────────────

export function DrugDiscoveryValidationPanel({ campaignId }: { campaignId: string }) {
  const [report, setReport] = useState<ValidationReport | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  // Per-compound filter state
  const [search, setSearch] = useState("")
  const [filter, setFilter] = useState<"all" | "within2" | "outside2" | "ood">("all")
  const [shown, setShown] = useState(10)

  // Collapsible open state
  const [metricsOpen, setMetricsOpen] = useState(true)
  const [compoundsOpen, setCompoundsOpen] = useState(true)

  const fetchReport = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      const res = await fetch("/api/drug-discovery/model-validation/pbpk", {
        credentials: "include",
      })
      if (!res.ok) {
        const err = await res.json().catch(() => ({ detail: res.statusText }))
        throw new Error(err.detail || `HTTP ${res.status}`)
      }
      const data: ValidationReport = await res.json()
      setReport(data)
    } catch (e: any) {
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    fetchReport()
  }, [fetchReport])

  const handleDownload = async () => {
    // Trigger re-run endpoint then download via validation API endpoint
    // For now: download the JSON report directly
    if (!report) return
    const blob = new Blob([JSON.stringify(report, null, 2)], { type: "application/json" })
    const url = URL.createObjectURL(blob)
    const a = document.createElement("a")
    a.href = url
    a.download = `validation_report_pbpk_${new Date().toISOString().slice(0, 10)}.json`
    a.click()
    URL.revokeObjectURL(url)
  }

  // Filter compounds
  const filteredCompounds = (report?.per_compound ?? []).filter((d) => {
    if (search && !d.name.toLowerCase().includes(search.toLowerCase())) return false
    if (filter === "within2" && (d.fold_error_Cmax === null || Math.abs(d.fold_error_Cmax) > 2)) return false
    if (filter === "outside2" && (d.fold_error_Cmax === null || Math.abs(d.fold_error_Cmax) <= 2)) return false
    if (filter === "ood" && d.in_domain) return false
    return true
  })

  // ─── Loading ───────────────────────────────────────────────────────────────
  if (loading && !report) {
    return (
      <div className="flex items-center justify-center py-12 gap-2 text-muted-foreground">
        <Loader2 className="h-4 w-4 animate-spin" />
        <span className="text-sm">Loading validation report…</span>
      </div>
    )
  }

  if (error && !report) {
    return (
      <Alert variant="destructive" className="mt-2">
        <XCircle className="h-4 w-4" />
        <AlertTitle>Validation unavailable</AlertTitle>
        <AlertDescription className="text-xs mt-1">{error}</AlertDescription>
      </Alert>
    )
  }

  const m = report?.metrics
  const cmaxOk = !!m && m.within_2fold_Cmax >= 0.67
  const aucOk = !!m && m.within_2fold_AUC >= 0.67
  const overallOk = cmaxOk && aucOk

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="flex items-start justify-between gap-2">
        <div>
          <h3 className="text-sm font-semibold">Model Validation Report</h3>
          <div className="flex flex-wrap gap-1.5 mt-1">
            <Badge variant="outline" className="font-mono text-xs text-indigo-700 dark:text-indigo-400 border-indigo-300">
              EMA/CHMP/EWP/37498/2011
            </Badge>
            <Badge variant="outline" className="font-mono text-xs">
              PBPK Qualification
            </Badge>
          </div>
        </div>
        <div className="flex items-center gap-1.5 shrink-0">
          <Button
            size="sm"
            variant="outline"
            className="h-7 text-xs gap-1"
            onClick={fetchReport}
            disabled={loading}
            data-testid="validation-rerun-button"
          >
            {loading
              ? <Loader2 className="h-3 w-3 animate-spin" />
              : <RefreshCw className="h-3 w-3" />
            }
            Re-run
          </Button>
          <Button
            size="sm"
            variant="outline"
            className="h-7 text-xs gap-1"
            onClick={handleDownload}
            disabled={!report}
            data-testid="validation-download-button"
          >
            <Download className="h-3 w-3" />
            JSON
          </Button>
        </div>
      </div>

      {report && (
        <div className="text-xs text-muted-foreground">
          <span>Model: <span className="font-mono">pbpk.v2</span></span>
          <span className="mx-1.5">·</span>
          <span>Reference set: {report.n_reference_compounds} drugs</span>
          <span className="mx-1.5">·</span>
          <span>{report.dataset_name}</span>
        </div>
      )}

      {/* EMA criterion callout */}
      {report && (
        <Alert
          className={cn(
            "border",
            overallOk
              ? "border-green-300 bg-green-50 dark:bg-green-950/30"
              : "border-red-300 bg-red-50 dark:bg-red-950/30"
          )}
          data-testid="ema-criterion-alert"
          data-status={overallOk ? "pass" : "fail"}
        >
          {overallOk ? (
            <CheckCircle2 className="h-4 w-4 text-green-700 dark:text-green-400" />
          ) : (
            <XCircle className="h-4 w-4 text-red-700 dark:text-red-400" />
          )}
          <AlertTitle className={cn(
            "text-xs font-semibold tracking-wide",
            overallOk ? "text-green-800 dark:text-green-300" : "text-red-800 dark:text-red-300"
          )}>
            EMA 2-FOLD CRITERION {overallOk ? "MET" : "FAILED"}
          </AlertTitle>
          <AlertDescription className="text-xs mt-1 space-y-0.5">
            <div>
              <strong>Cmax:</strong>{" "}
              {Math.round(m!.within_2fold_Cmax * 100)}% within 2-fold{" "}
              {cmaxOk ? "(≥67% required ✓)" : "(< 67% required ✗)"}
            </div>
            <div>
              <strong>AUC:</strong>{" "}
              {Math.round(m!.within_2fold_AUC * 100)}% within 2-fold{" "}
              {aucOk ? "(≥67% required ✓)" : "(✗)"}
            </div>
          </AlertDescription>
        </Alert>
      )}

      {/* Aggregate Metrics */}
      {report && (
        <Collapsible open={metricsOpen} onOpenChange={setMetricsOpen}>
          <CollapsibleTrigger className="flex w-full items-center justify-between rounded-md border px-3 py-2 text-xs font-medium hover:bg-muted/50 transition-colors">
            <div className="flex items-center gap-2">
              <span>Aggregate Metrics</span>
              <span className="text-muted-foreground font-normal">AFE, AAFE, R², fold distribution</span>
            </div>
            <ChevronDown className={cn("h-3.5 w-3.5 text-muted-foreground transition-transform", metricsOpen && "rotate-180")} />
          </CollapsibleTrigger>
          <CollapsibleContent>
            <div className="overflow-x-auto mt-1 rounded-md border">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b bg-muted/30">
                    <th className="py-2 px-3 text-left text-xs font-semibold w-28">Metric</th>
                    <th className="py-2 px-2 text-right text-xs font-semibold">Cmax</th>
                    <th className="py-2 px-2 text-right text-xs font-semibold">AUC</th>
                    <th className="py-2 pl-3 text-left text-xs font-semibold text-muted-foreground">Interpretation</th>
                  </tr>
                </thead>
                <tbody className="divide-y">
                  <MetricRow
                    label="AFE"
                    cmaxVal={m!.AFE_Cmax.toFixed(2)}
                    aucVal={m!.AFE_AUC.toFixed(2)}
                    interpretation="Average fold error"
                  />
                  <MetricRow
                    label="AAFE"
                    cmaxVal={m!.AAFE_Cmax.toFixed(2)}
                    aucVal={m!.AAFE_AUC.toFixed(2)}
                    interpretation="Absolute avg fold error"
                  />
                  <MetricRow
                    label="R²"
                    cmaxVal={m!.R2_Cmax.toFixed(2)}
                    aucVal={m!.R2_AUC.toFixed(2)}
                    interpretation="Log-log correlation"
                  />
                  <MetricRow
                    label="Within 2×"
                    cmaxVal={`${Math.round(m!.within_2fold_Cmax * 100)}%`}
                    aucVal={`${Math.round(m!.within_2fold_AUC * 100)}%`}
                    interpretation="EMA threshold: ≥67%"
                    highlight={{ cmax: cmaxOk, auc: aucOk }}
                  />
                  <MetricRow
                    label="Within 3×"
                    cmaxVal={`${Math.round(m!.within_3fold_Cmax * 100)}%`}
                    aucVal={`${Math.round(m!.within_3fold_AUC * 100)}%`}
                    interpretation="Advisory only"
                  />
                </tbody>
              </table>
            </div>
          </CollapsibleContent>
        </Collapsible>
      )}

      {/* Per-Compound Results */}
      {report && (
        <Collapsible open={compoundsOpen} onOpenChange={setCompoundsOpen}>
          <CollapsibleTrigger className="flex w-full items-center justify-between rounded-md border px-3 py-2 text-xs font-medium hover:bg-muted/50 transition-colors">
            <div className="flex items-center gap-2">
              <span>Per-Compound Results</span>
              <span className="text-muted-foreground font-normal">{report.per_compound.length} drugs</span>
            </div>
            <ChevronDown className={cn("h-3.5 w-3.5 text-muted-foreground transition-transform", compoundsOpen && "rotate-180")} />
          </CollapsibleTrigger>
          <CollapsibleContent>
            {/* Filter bar */}
            <div className="flex items-center gap-2 mt-2 mb-1">
              <div className="relative flex-1">
                <Search className="absolute left-2 top-1/2 -translate-y-1/2 h-3 w-3 text-muted-foreground" />
                <input
                  className="w-full pl-6 pr-2 py-1 text-xs border rounded-md bg-background"
                  placeholder="Search drugs…"
                  value={search}
                  onChange={(e) => { setSearch(e.target.value); setShown(10) }}
                />
              </div>
              <select
                className="text-xs border rounded-md px-2 py-1 bg-background"
                value={filter}
                onChange={(e) => { setFilter(e.target.value as typeof filter); setShown(10) }}
              >
                <option value="all">All results</option>
                <option value="within2">Within 2×</option>
                <option value="outside2">Outside 2×</option>
                <option value="ood">OOD only</option>
              </select>
              <span className="text-xs text-muted-foreground whitespace-nowrap">
                {Math.min(shown, filteredCompounds.length)} / {filteredCompounds.length}
              </span>
            </div>

            <div className="overflow-x-auto rounded-md border">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b bg-muted/30">
                    <th className="py-2 px-3 text-left text-xs font-semibold">Drug</th>
                    <th className="py-2 px-2 text-right text-xs font-semibold">Obs Cmax</th>
                    <th className="py-2 px-2 text-right text-xs font-semibold">Pred Cmax</th>
                    <th className="py-2 px-3 text-left text-xs font-semibold">Fold Error</th>
                    <th className="py-2 px-3 text-left text-xs font-semibold">AD</th>
                  </tr>
                </thead>
                <tbody className="divide-y">
                  {filteredCompounds.slice(0, shown).map((d) => (
                    <tr key={d.name} className="hover:bg-muted/20">
                      <td className="py-1.5 px-3 text-xs font-medium">{d.name}</td>
                      <td className="py-1.5 px-2 text-right font-mono text-xs text-muted-foreground">
                        {d.observed_Cmax.toFixed(3)}
                      </td>
                      <td className="py-1.5 px-2 text-right font-mono text-xs text-muted-foreground">
                        {d.predicted_Cmax !== null ? d.predicted_Cmax.toFixed(3) : "—"}
                      </td>
                      <td className="py-1.5 px-3">
                        <FoldCell fold={d.fold_error_Cmax} />
                      </td>
                      <td className="py-1.5 px-3">
                        <AdBadge inDomain={d.in_domain} />
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            {shown < filteredCompounds.length && (
              <Button
                variant="ghost"
                size="sm"
                className="mt-2 h-7 text-xs w-full"
                onClick={() => setShown((s) => s + 10)}
              >
                Load {Math.min(10, filteredCompounds.length - shown)} more
              </Button>
            )}

            <p className="text-xs text-muted-foreground italic mt-2">
              1 drug excluded from validation (Clopidogrel — prodrug; CL_true exceeds hepatic blood flow).
            </p>
          </CollapsibleContent>
        </Collapsible>
      )}

      {/* Regulatory summary */}
      {report?.regulatory_summary && (
        <p className="text-xs text-muted-foreground border-l-2 border-muted pl-3 leading-relaxed">
          {report.regulatory_summary}
        </p>
      )}

      {/* Warnings */}
      {report?.warnings && report.warnings.length > 0 && (
        <div className="space-y-1">
          {report.warnings.map((w, i) => (
            <div key={i} className="flex items-start gap-1.5 text-xs text-amber-700 dark:text-amber-400">
              <AlertTriangle className="h-3.5 w-3.5 mt-0.5 shrink-0" />
              {w}
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
