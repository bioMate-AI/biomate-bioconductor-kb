/**
 * DrugDiscoveryAction — renders context-sensitive action widgets in the chat.
 *
 * Modes (original):
 *  assay_upload       — file picker + POST /api/drug-discovery/{id}/ingest-assay
 *  cro_export         — format selector + download /api/drug-discovery/{id}/export/cro-order
 *  campaign_dashboard — inline compound-ranking panel
 *
 * Modes (new, tabbed — shown when campaign_id is set):
 *  validation         — PBPK/ADMET validation panel (Surface 2)
 *  audit              — 21 CFR Part 11 hash-chain audit trail (Surface 3)
 *  auto_retrain       — DMTA Bayesian-optimizer retrain loop (Surface 4)
 *  ind_assembly       — IND section assembly (Surface 6)
 *  new_campaign       — Campaign creation wizard (Surface 7)
 */
import { useState, useRef, useEffect } from "react"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select"
import {
  Upload,
  Download,
  FlaskConical,
  CheckCircle,
  AlertTriangle,
  Loader2,
  BarChart3,
  FileText,
  Shield,
  RefreshCw,
  Beaker,
  Target,
} from "lucide-react"
import { cn } from "@/lib/utils"
import { DrugDiscoveryAuditViewer } from "@/components/drug-discovery-audit-viewer"
import { DrugDiscoveryAutoRetrain } from "@/components/drug-discovery-auto-retrain"
import { DrugDiscoveryValidationPanel } from "@/components/drug-discovery-validation-panel"
import { DrugDiscoveryIndAssembly } from "@/components/drug-discovery-ind-assembly"
import { DrugDiscoveryCampaignWizard } from "@/components/drug-discovery-campaign-wizard"

// ─────────────────────────────────────────────────────────────────────────────
// Types
// ─────────────────────────────────────────────────────────────────────────────

export type DrugDiscoveryMode =
  | "assay_upload"
  | "cro_export"
  | "campaign_dashboard"
  | "validation"
  | "audit"
  | "auto_retrain"
  | "ind_assembly"
  | "new_campaign"

export interface DrugDiscoveryActionData {
  type: DrugDiscoveryMode
  campaign_id: string | null
  endpoint: string | null
  description?: string
  csv_template?: string
  formats?: string[]
  /** Initial tab to show when type triggers the tabbed view */
  initial_mode?: DrugDiscoveryMode
}

interface DrugDiscoveryActionProps {
  action: DrugDiscoveryActionData
  className?: string
}

// ─────────────────────────────────────────────────────────────────────────────
// Assay upload widget
// ─────────────────────────────────────────────────────────────────────────────

function AssayUploadWidget({ action }: { action: DrugDiscoveryActionData }) {
  const [status, setStatus] = useState<"idle" | "uploading" | "success" | "error">("idle")
  const [result, setResult] = useState<any>(null)
  const [errorMsg, setErrorMsg] = useState<string | null>(null)
  const [campaignId, setCampaignId] = useState(action.campaign_id || "")
  const fileRef = useRef<HTMLInputElement>(null)

  const upload = async (file: File) => {
    const id = campaignId.trim() || "default_campaign"
    setStatus("uploading")
    setErrorMsg(null)
    try {
      const form = new FormData()
      form.append("file", file)
      const res = await fetch(`/api/drug-discovery/${id}/ingest-assay`, {
        method: "POST",
        body: form,
        credentials: "include",
      })
      if (!res.ok) {
        const err = await res.json().catch(() => ({ detail: res.statusText }))
        throw new Error(err.detail || `HTTP ${res.status}`)
      }
      const data = await res.json()
      setResult(data)
      setStatus("success")
    } catch (e: any) {
      setErrorMsg(e.message)
      setStatus("error")
    }
  }

  const onFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const f = e.target.files?.[0]
    if (f) upload(f)
  }

  return (
    <div className="space-y-3">
      <p className="text-sm text-muted-foreground">{action.description}</p>

      {!action.campaign_id && (
        <div className="flex items-center gap-2">
          <label className="text-xs font-medium text-muted-foreground w-28 shrink-0">Campaign ID</label>
          <input
            className="flex-1 text-xs border rounded px-2 py-1 bg-background"
            placeholder="e.g. bcr_abl_v1"
            value={campaignId}
            onChange={(e) => setCampaignId(e.target.value)}
          />
        </div>
      )}

      <div className="flex items-center gap-2">
        <Button
          size="sm"
          variant="outline"
          onClick={() => fileRef.current?.click()}
          disabled={status === "uploading"}
          className="gap-2"
        >
          {status === "uploading" ? (
            <Loader2 className="h-3.5 w-3.5 animate-spin" />
          ) : (
            <Upload className="h-3.5 w-3.5" />
          )}
          {status === "uploading" ? "Uploading…" : "Select Assay CSV"}
        </Button>

        <Button
          size="sm"
          variant="ghost"
          className="text-xs text-muted-foreground gap-1"
          onClick={() => {
            const blob = new Blob([action.csv_template || ""], { type: "text/csv" })
            const url = URL.createObjectURL(blob)
            const a = document.createElement("a")
            a.href = url
            a.download = "assay_template.csv"
            a.click()
            URL.revokeObjectURL(url)
          }}
        >
          <FileText className="h-3 w-3" />
          Download template
        </Button>
      </div>

      <input ref={fileRef} type="file" accept=".csv" className="hidden" onChange={onFileChange} />

      {status === "success" && result && (
        <div className="rounded-md border border-green-200 bg-green-50 dark:bg-green-950/30 p-3 space-y-2">
          <div className="flex items-center gap-2 text-green-700 dark:text-green-400 text-sm font-medium">
            <CheckCircle className="h-4 w-4" />
            {result.ingested} rows ingested
          </div>
          {result.errors?.length > 0 && (
            <p className="text-xs text-amber-600 dark:text-amber-400">{result.errors.length} rows skipped: {result.errors[0]}</p>
          )}
          {result.updated_ranks?.length > 0 && (
            <div className="text-xs space-y-1">
              <p className="font-medium text-muted-foreground">Updated ranking:</p>
              {result.updated_ranks.slice(0, 5).map((r: any) => (
                <div key={r.compound_id} className="flex items-center gap-2">
                  <span className="w-5 text-right text-muted-foreground font-mono">#{r.rank}</span>
                  <span className="font-medium">{r.compound_id}</span>
                  <span className="text-muted-foreground ml-auto">score {r.combined_score.toFixed(3)}</span>
                </div>
              ))}
              {result.updated_ranks.length > 5 && (
                <p className="text-muted-foreground">…and {result.updated_ranks.length - 5} more</p>
              )}
            </div>
          )}
        </div>
      )}

      {status === "error" && (
        <div className="rounded-md border border-red-200 bg-red-50 dark:bg-red-950/30 p-3 flex items-start gap-2 text-red-700 dark:text-red-400 text-sm">
          <AlertTriangle className="h-4 w-4 mt-0.5 shrink-0" />
          <span>{errorMsg}</span>
        </div>
      )}
    </div>
  )
}

// ─────────────────────────────────────────────────────────────────────────────
// CRO export widget
// ─────────────────────────────────────────────────────────────────────────────

function CROExportWidget({ action }: { action: DrugDiscoveryActionData }) {
  const [fmt, setFmt] = useState<string>("wuxi")
  const [status, setStatus] = useState<"idle" | "loading" | "error">("idle")
  const [errorMsg, setErrorMsg] = useState<string | null>(null)
  const [campaignId, setCampaignId] = useState(action.campaign_id || "")

  const download = async () => {
    const id = campaignId.trim() || "default_campaign"
    setStatus("loading")
    setErrorMsg(null)
    try {
      const res = await fetch(`/api/drug-discovery/${id}/export/cro-order?fmt=${fmt}`, {
        credentials: "include",
      })
      if (!res.ok) {
        const err = await res.json().catch(() => ({ detail: res.statusText }))
        throw new Error(err.detail || `HTTP ${res.status}`)
      }
      const blob = await res.blob()
      const url = URL.createObjectURL(blob)
      const a = document.createElement("a")
      a.href = url
      a.download = `${id}_${fmt}_order.csv`
      a.click()
      URL.revokeObjectURL(url)
      setStatus("idle")
    } catch (e: any) {
      setErrorMsg(e.message)
      setStatus("error")
    }
  }

  const fmtLabels: Record<string, string> = {
    wuxi: "WuXi AppTec",
    pharmaron: "Pharmaron",
    enamine: "Enamine",
    generic: "Generic CSV",
  }

  return (
    <div className="space-y-3">
      <p className="text-sm text-muted-foreground">{action.description}</p>

      {!action.campaign_id && (
        <div className="flex items-center gap-2">
          <label className="text-xs font-medium text-muted-foreground w-28 shrink-0">Campaign ID</label>
          <input
            className="flex-1 text-xs border rounded px-2 py-1 bg-background"
            placeholder="e.g. bcr_abl_v1"
            value={campaignId}
            onChange={(e) => setCampaignId(e.target.value)}
          />
        </div>
      )}

      <div className="flex items-center gap-2">
        <Select value={fmt} onValueChange={setFmt}>
          <SelectTrigger className="w-40 h-8 text-xs">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            {(action.formats || ["wuxi", "pharmaron", "enamine", "generic"]).map((f) => (
              <SelectItem key={f} value={f} className="text-xs">
                {fmtLabels[f] || f}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>

        <Button size="sm" onClick={download} disabled={status === "loading"} className="gap-2">
          {status === "loading" ? (
            <Loader2 className="h-3.5 w-3.5 animate-spin" />
          ) : (
            <Download className="h-3.5 w-3.5" />
          )}
          {status === "loading" ? "Generating…" : `Download ${fmtLabels[fmt] || fmt}`}
        </Button>
      </div>

      {status === "error" && (
        <div className="rounded-md border border-red-200 bg-red-50 dark:bg-red-950/30 p-3 flex items-start gap-2 text-red-700 dark:text-red-400 text-sm">
          <AlertTriangle className="h-4 w-4 mt-0.5 shrink-0" />
          <span>{errorMsg}</span>
        </div>
      )}
    </div>
  )
}

// ─────────────────────────────────────────────────────────────────────────────
// Campaign dashboard (inline, fetched on mount)
// ─────────────────────────────────────────────────────────────────────────────

function CampaignDashboardWidget({ action }: { action: DrugDiscoveryActionData }) {
  const [data, setData] = useState<any>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [campaignId, setCampaignId] = useState(action.campaign_id || "")

  // Auto-load when campaign_id is pre-set (e.g. from the CRO demo page)
  useEffect(() => {
    if (action.campaign_id) load(action.campaign_id)
  }, [action.campaign_id]) // eslint-disable-line react-hooks/exhaustive-deps

  const load = async (id: string) => {
    if (!id.trim()) return
    setLoading(true)
    setError(null)
    try {
      const res = await fetch(`/api/drug-discovery/${id.trim()}/compounds`, {
        credentials: "include",
      })
      if (!res.ok) {
        const err = await res.json().catch(() => ({ detail: res.statusText }))
        throw new Error(err.detail || `HTTP ${res.status}`)
      }
      setData(await res.json())
    } catch (e: any) {
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }

  const maxScore = data?.compounds?.[0]?.combined_score || 1

  return (
    <div className="space-y-3">
      <div className="flex items-center gap-2">
        <input
          className="flex-1 text-xs border rounded px-2 py-1 bg-background"
          placeholder="Campaign ID (e.g. bcr_abl_v1)"
          value={campaignId}
          onChange={(e) => setCampaignId(e.target.value)}
          onKeyDown={(e) => e.key === "Enter" && load(campaignId)}
        />
        <Button size="sm" variant="outline" onClick={() => load(campaignId)} disabled={loading} className="gap-1.5">
          {loading ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <BarChart3 className="h-3.5 w-3.5" />}
          Load
        </Button>
      </div>

      {error && (
        <div className="rounded-md border border-red-200 bg-red-50 dark:bg-red-950/30 p-3 flex items-start gap-2 text-red-600 dark:text-red-400 text-xs">
          <AlertTriangle className="h-3.5 w-3.5 mt-0.5 shrink-0" />
          {error}
        </div>
      )}

      {data && (
        <div className="space-y-2">
          <div className="flex items-center justify-between text-xs text-muted-foreground">
            <span>Campaign: <span className="font-medium text-foreground">{data.campaign_id}</span></span>
            <span>{data.count} compound{data.count !== 1 ? "s" : ""}</span>
          </div>

          {data.compounds?.length === 0 ? (
            <p className="text-xs text-muted-foreground py-2">
              No compounds yet. Upload assay data via the assay upload action.
            </p>
          ) : (
            <div className="space-y-1.5">
              {data.compounds.slice(0, 10).map((c: any) => {
                const pct = Math.round((c.combined_score / maxScore) * 100)
                const tier = pct >= 80 ? "green" : pct >= 50 ? "amber" : "red"
                const tierClass = {
                  green: "bg-green-500",
                  amber: "bg-amber-500",
                  red: "bg-red-500",
                }[tier]
                return (
                  <div key={c.compound_id} className="flex items-center gap-2 text-xs">
                    <span className="w-5 text-right font-mono text-muted-foreground">#{c.rank}</span>
                    <span className="w-36 truncate font-medium">{c.compound_id}</span>
                    <div className="flex-1 bg-muted rounded-full h-1.5 overflow-hidden">
                      <div className={cn("h-full rounded-full", tierClass)} style={{ width: `${pct}%` }} />
                    </div>
                    <span className="w-12 text-right text-muted-foreground font-mono">
                      {c.combined_score.toFixed(3)}
                    </span>
                  </div>
                )
              })}
              {data.compounds.length > 10 && (
                <p className="text-xs text-muted-foreground pl-7">+{data.compounds.length - 10} more</p>
              )}
            </div>
          )}
        </div>
      )}
    </div>
  )
}

// ─────────────────────────────────────────────────────────────────────────────
// Tabbed campaign view (shown when campaign_id is set + type is a tab mode)
// ─────────────────────────────────────────────────────────────────────────────

const TABBED_MODES: DrugDiscoveryMode[] = [
  "campaign_dashboard",
  "validation",
  "audit",
  "auto_retrain",
  "ind_assembly",
]

interface TabDef {
  key: DrugDiscoveryMode
  label: string
  icon: React.ReactNode
}

const TABS: TabDef[] = [
  { key: "campaign_dashboard", label: "Dashboard",    icon: <Target     className="h-3.5 w-3.5" /> },
  { key: "validation",         label: "Validation",   icon: <Beaker     className="h-3.5 w-3.5" /> },
  { key: "audit",              label: "Audit",        icon: <Shield     className="h-3.5 w-3.5" /> },
  { key: "auto_retrain",       label: "Auto-Retrain", icon: <RefreshCw  className="h-3.5 w-3.5" /> },
  { key: "ind_assembly",       label: "IND",          icon: <FileText   className="h-3.5 w-3.5" /> },
]

function CampaignTabs({
  action,
  initialMode,
}: {
  action: DrugDiscoveryActionData
  initialMode: DrugDiscoveryMode
}) {
  const [activeTab, setActiveTab] = useState<DrugDiscoveryMode>(initialMode)
  const campaignId = action.campaign_id!

  return (
    <div className="space-y-0">
      {/* Tab bar */}
      <div className="flex items-center gap-0.5 border-b border-border px-1 pt-1 overflow-x-auto">
        {TABS.map((tab) => (
          <button
            key={tab.key}
            onClick={() => setActiveTab(tab.key)}
            className={cn(
              "flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium rounded-t-md border border-b-0 -mb-px transition-colors whitespace-nowrap",
              activeTab === tab.key
                ? "border-border bg-background text-foreground"
                : "border-transparent text-muted-foreground hover:text-foreground hover:bg-muted/40",
            )}
          >
            {tab.icon}
            {tab.label}
          </button>
        ))}
      </div>

      {/* Tab content */}
      <div className="p-4">
        {activeTab === "campaign_dashboard" && <CampaignDashboardWidget action={action} />}
        {activeTab === "audit" && (
          <DrugDiscoveryAuditViewer campaignId={campaignId} />
        )}
        {activeTab === "auto_retrain" && (
          <DrugDiscoveryAutoRetrain campaignId={campaignId} />
        )}
        {activeTab === "validation" && (
          <DrugDiscoveryValidationPanel campaignId={campaignId} />
        )}
        {activeTab === "ind_assembly" && (
          <DrugDiscoveryIndAssembly campaignId={campaignId} />
        )}
      </div>
    </div>
  )
}

// ─────────────────────────────────────────────────────────────────────────────
// Main export
// ─────────────────────────────────────────────────────────────────────────────

export function DrugDiscoveryAction({ action, className }: DrugDiscoveryActionProps) {
  const [launchedCampaignId, setLaunchedCampaignId] = useState<string | null>(null)

  const iconMap: Partial<Record<DrugDiscoveryMode, React.ReactNode>> = {
    assay_upload:       <Upload    className="h-4 w-4" />,
    cro_export:         <Download  className="h-4 w-4" />,
    campaign_dashboard: <BarChart3 className="h-4 w-4" />,
    validation:         <Beaker    className="h-4 w-4" />,
    audit:              <Shield    className="h-4 w-4" />,
    auto_retrain:       <RefreshCw className="h-4 w-4" />,
    ind_assembly:       <FileText  className="h-4 w-4" />,
  }
  const titleMap: Partial<Record<DrugDiscoveryMode, string>> = {
    assay_upload:       "Assay Data Upload",
    cro_export:         "CRO Compound Export",
    campaign_dashboard: "Campaign Dashboard",
    validation:         "Model Validation",
    audit:              "Audit Trail",
    auto_retrain:       "Auto-Retrain Loop",
    ind_assembly:       "IND Assembly",
    new_campaign:       "New Campaign",
  }

  // After wizard launches a campaign, switch to tabbed view for it
  const effectiveCampaignId = launchedCampaignId ?? action.campaign_id

  // When campaign_id is set and the type is a tab-capable mode, render the
  // full tabbed view. Otherwise render the original single-widget layout.
  const useTabs =
    !!effectiveCampaignId && (TABBED_MODES.includes(action.type) || !!launchedCampaignId)

  const isWizard = action.type === "new_campaign" && !launchedCampaignId

  const initialMode: DrugDiscoveryMode =
    launchedCampaignId ? "campaign_dashboard"
    : action.initial_mode ?? action.type

  return (
    <Card className={cn("border-blue-200 dark:border-blue-800 bg-blue-50/50 dark:bg-blue-950/20 mt-3", className)}>
      <CardHeader className="pb-2 pt-3 px-4">
        <CardTitle className="text-sm flex items-center gap-2 text-blue-800 dark:text-blue-300">
          <FlaskConical className="h-4 w-4" />
          {isWizard ? null : iconMap[action.type]}
          {useTabs ? "Drug Discovery" : (titleMap[action.type] ?? action.type)}
          {effectiveCampaignId && (
            <Badge variant="secondary" className="text-xs font-mono ml-1">
              {effectiveCampaignId}
            </Badge>
          )}
        </CardTitle>
      </CardHeader>
      <CardContent className={cn("pb-4", useTabs ? "px-0 pt-0" : "px-4")}>
        {isWizard ? (
          <DrugDiscoveryCampaignWizard
            onDone={(cid) => setLaunchedCampaignId(cid)}
            onCancel={() => {}}
          />
        ) : useTabs ? (
          <CampaignTabs
            action={{ ...action, campaign_id: effectiveCampaignId }}
            initialMode={initialMode}
          />
        ) : (
          <>
            {action.type === "assay_upload"       && <AssayUploadWidget    action={action} />}
            {action.type === "cro_export"          && <CROExportWidget       action={action} />}
            {action.type === "campaign_dashboard"  && <CampaignDashboardWidget action={action} />}
          </>
        )}
      </CardContent>
    </Card>
  )
}
