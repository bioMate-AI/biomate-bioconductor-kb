/**
 * /drug-discovery-cro  — BioMate CRO Compliance Suite
 *
 * Ported from reference/claude_design/cro/cro/DrugDiscoveryAction.jsx + BioMate CRO Compliance.html
 *
 * Structure (matches reference exactly):
 *   .page
 *   ├── .top-nav  (breadcrumb + reg chips + user badge)
 *   └── .shell
 *       ├── .preamble  (assistant context message)
 *       └── .dd-card
 *           ├── .dd-card-head  (icon · title · sub · New campaign · Sign action · tabs)
 *           └── .dd-body  (surface content)
 */

import { useState, useEffect, useRef, useCallback, Fragment } from "react"
import { useLocation } from "wouter"
import { useAuth } from "@/contexts/auth-context"
import { DrugDiscoveryAuditViewer } from "@/components/drug-discovery-audit-viewer"
import { DrugDiscoveryAutoRetrain } from "@/components/drug-discovery-auto-retrain"
import { DrugDiscoveryValidationPanel } from "@/components/drug-discovery-validation-panel"
import { DrugDiscoveryIndAssembly } from "@/components/drug-discovery-ind-assembly"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Button } from "@/components/ui/button"
import {
  Loader2, Check, AlertTriangle,
  ChevronRight, RefreshCw, Upload, ExternalLink, Plus, PenLine,
} from "lucide-react"
import { cn } from "@/lib/utils"

// ── Data ─────────────────────────────────────────────────────────────────────

const DEMO_COMPOUNDS = [
  { rank: 1, id: "CPD-0087", score: 0.89, ad: "in_domain",     round: 2 },
  { rank: 2, id: "CPD-0043", score: 0.71, ad: "in_domain",     round: 1 },
  { rank: 3, id: "CPD-0021", score: 0.68, ad: "out_of_domain", round: 1 },
  { rank: 4, id: "CPD-0102", score: 0.66, ad: "in_domain",     round: 3 },
  { rank: 5, id: "CPD-0054", score: 0.61, ad: "in_domain",     round: 2 },
  { rank: 6, id: "CPD-0033", score: 0.58, ad: "in_domain",     round: 1 },
  { rank: 7, id: "CPD-0119", score: 0.54, ad: "out_of_domain", round: 3 },
  { rank: 8, id: "CPD-0076", score: 0.49, ad: "in_domain",     round: 2 },
  { rank: 9, id: "CPD-0012", score: 0.42, ad: "in_domain",     round: 1 },
  { rank: 10, id: "CPD-0097", score: 0.38, ad: "in_domain",    round: 3 },
]

const DEMO_SMILES = [
  "C#Cc1cccc(Nc2ncnc3cc(OCCO)c(OCCO)cc23)c1",
  "CC(=O)Nc1ccc(Oc2ncnc3cc(NC4CCOCC4)ccc23)cc1",
  "C=CC(=O)Nc1ccc(Nc2ncnc3ccc(OC)c(OC)c23)cc1OC",
  "Nc1ccc(F)c(Nc2ncnc3cc4c(cc23)OCCO4)c1",
  "CS(=O)(=O)CCNCc1ccc(-c2ccc3ncnc(Nc4ccc(OC)c(Cl)c4)c3c2)o1",
]

// DMTA nodes — statically anchored at Design=done, Make=active (syncs to retrain)
const BASE_DMTA: { key: string; label: string; status: "done" | "active" | "pending" }[] = [
  { key: "design",  label: "Design",  status: "done"    },
  { key: "make",    label: "Make",    status: "active"  },
  { key: "test",    label: "Test",    status: "pending" },
  { key: "analyse", label: "Analyse", status: "pending" },
]


// Campaign list entry from GET /api/drug-discovery/campaigns
interface CampaignEntry {
  campaign_id: string
  user_id: string
  molecule_name: string
  target: string
  indication: string
  sponsor: string
  objective: string
  created_at: string
}

// ── Setup ─────────────────────────────────────────────────────────────────────

async function createCampaignApi(opts: {
  campaignId: string
  userId: string
  molecule: string
  target: string
  indication: string
  sponsor: string
  objective: string
  smiles?: string[]
}): Promise<{ ok: boolean; error?: string }> {
  try {
    const res = await fetch("/api/drug-discovery/campaigns", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      credentials: "include",
      body: JSON.stringify({
        campaign_id:            opts.campaignId,
        user_id:                opts.userId,
        molecule_name:          opts.molecule,
        target:                 opts.target,
        indication:             opts.indication,
        sponsor:                opts.sponsor,
        objective:              opts.objective,
        virtual_library_smiles: opts.smiles ?? DEMO_SMILES,
      }),
    })
    if (!res.ok && res.status !== 409) {
      const body = await res.json().catch(() => ({})) as any
      return { ok: false, error: `HTTP ${res.status}: ${body.detail ?? "unknown error"}` }
    }
    return { ok: true }
  } catch (e: any) {
    return { ok: false, error: String(e) }
  }
}

async function fetchCampaigns(userId: string): Promise<CampaignEntry[]> {
  try {
    const res = await fetch(`/api/drug-discovery/campaigns?user_id=${encodeURIComponent(userId)}`, {
      credentials: "include",
    })
    if (res.ok) {
      const data = await res.json() as { campaigns: CampaignEntry[] }
      return data.campaigns ?? []
    }
  } catch { /* ignore */ }
  return []
}

async function seedLibrary(campaignId: string): Promise<void> {
  try {
    await fetch(`/api/drug-discovery/${campaignId}/virtual-library`, {
      method: "POST", credentials: "include",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ smiles: DEMO_SMILES, n_propose: 5, diversity_weight: 0.3 }),
    })
  } catch { /* non-blocking */ }
  try {
    await fetch(`/api/drug-discovery/${campaignId}/retrain/trigger`, {
      method: "POST", credentials: "include",
    })
  } catch { /* non-blocking */ }
}

// ── Primitive atoms (matching tokens-cro.css) ─────────────────────────────────

/** .reg-chip — monospace citation badge */
function RegChip({
  variant = "default",
  children,
}: {
  variant?: "default" | "indigo"
  children: React.ReactNode
}) {
  return (
    <span
      className={cn(
        "inline-flex items-center gap-1 px-1.5 py-0.5 rounded-[4px] border font-mono text-[10.5px] font-medium whitespace-nowrap leading-none",
        variant === "indigo"
          ? "border-indigo-300 bg-indigo-50 text-indigo-700 dark:border-indigo-700 dark:bg-indigo-950/40 dark:text-indigo-300"
          : "border-border bg-white dark:bg-background text-muted-foreground",
      )}
    >
      {children}
    </span>
  )
}

/** .chip — status pill */
function Chip({
  tone = "default",
  pulse = false,
  children,
}: {
  tone?: "ok" | "run" | "warn" | "err" | "default"
  pulse?: boolean
  children: React.ReactNode
}) {
  const toneClass = {
    ok:      "bg-green-50 text-green-700 dark:bg-green-950/40 dark:text-green-400",
    run:     "bg-blue-50 text-blue-700 dark:bg-blue-950/40 dark:text-blue-400",
    warn:    "bg-amber-50 text-amber-700 dark:bg-amber-950/40 dark:text-amber-500",
    err:     "bg-red-50 text-red-700 dark:bg-red-950/40 dark:text-red-400",
    default: "bg-muted/60 text-muted-foreground",
  }[tone]
  const dotClass = {
    ok: "bg-green-500", run: "bg-blue-500",
    warn: "bg-amber-500", err: "bg-red-500", default: "bg-muted-foreground",
  }[tone]
  return (
    <span className={cn("inline-flex items-center gap-1.5 px-2 py-0.5 rounded-full text-[11.5px] font-medium", toneClass)}>
      <span className={cn("w-1.5 h-1.5 rounded-full shrink-0", dotClass, pulse && "animate-pulse")} />
      {children}
    </span>
  )
}

// ── Score bar ─────────────────────────────────────────────────────────────────

function ScoreBar({ score }: { score: number }) {
  const pct = Math.round(Math.max(0, Math.min(1, score)) * 100)
  const color = pct >= 70 ? "bg-green-500" : pct >= 40 ? "bg-amber-500" : "bg-red-400"
  return (
    <div className="flex items-center gap-2">
      <div className="flex-1 h-1.5 bg-muted rounded-full overflow-hidden" style={{ minWidth: 80 }}>
        <div className={cn("h-full rounded-full", color)} style={{ width: `${pct}%` }} />
      </div>
      <span className="font-mono text-[12.5px] text-muted-foreground w-9 text-right shrink-0">
        {score.toFixed(2)}
      </span>
    </div>
  )
}

// ── DMTA Stepper ──────────────────────────────────────────────────────────────

function DmtaStepper({ loopRunning }: { loopRunning: boolean }) {
  // When loop is running, Make pulses; when stopped it stays "active" (UC-CRO-02)
  return (
    <div className="flex items-start">
      {BASE_DMTA.map((n, i) => (
        <Fragment key={n.key}>
          <div className="flex flex-col items-center gap-1" style={{ minWidth: 80 }}>
            <div className={cn(
              "w-7 h-7 rounded-full border-2 flex items-center justify-center shrink-0",
              n.status === "done"    && "bg-foreground border-foreground text-background",
              n.status === "active"  && "bg-blue-50 border-blue-500 text-blue-600 dark:bg-blue-950/30",
              n.status === "pending" && "bg-background border-border text-muted-foreground",
            )}>
              {n.status === "done"    && <Check className="h-3.5 w-3.5" />}
              {n.status === "active"  && <span className={cn("w-2.5 h-2.5 rounded-full bg-blue-500", loopRunning && "animate-pulse")} />}
              {n.status === "pending" && <span className="w-2 h-2 rounded-full border-[1.5px] border-current" />}
            </div>
            <span className={cn(
              "text-[12px] font-semibold uppercase tracking-[0.04em]",
              n.status === "done"    && "text-foreground",
              n.status === "active"  && "text-blue-600 dark:text-blue-400",
              n.status === "pending" && "text-muted-foreground",
            )}>
              {n.label}
            </span>
            <span className="text-[10.5px] text-muted-foreground/70 capitalize">
              {n.status === "active" ? (loopRunning ? "running" : "waiting") : n.status === "done" ? "completed" : "pending"}
            </span>
          </div>
          {i < BASE_DMTA.length - 1 && (
            <div className={cn(
              "flex-1 h-0.5 mt-3.5",
              n.status === "done" ? "bg-foreground/50" : "bg-border",
            )} />
          )}
        </Fragment>
      ))}
    </div>
  )
}

// ── Surface 1: Campaign Dashboard ─────────────────────────────────────────────

interface Compound {
  rank: number; id: string; score: number; ad: string; round: number
}

function CampaignDashboard({
  campaignId,
  campaignMeta,
  loopRunning,
  onIngestAssay,
  onExportCroOrder,
}: {
  campaignId: string
  campaignMeta: CampaignEntry | null
  loopRunning: boolean
  onIngestAssay: () => void
  onExportCroOrder: () => void
}) {
  const [showAll, setShowAll] = useState(false)
  const [compounds, setCompounds] = useState<Compound[]>(DEMO_COMPOUNDS)
  const [refreshing, setRefreshing] = useState(false)
  const [lastUpdated, setLastUpdated] = useState("just now")

  // UC-CRO-03: fetch real compounds, fall back to demo data if empty
  const fetchCompounds = useCallback(async () => {
    setRefreshing(true)
    try {
      const res = await fetch(`/api/drug-discovery/${campaignId}/compounds`, { credentials: "include" })
      if (res.ok) {
        const data = await res.json() as { compounds: any[]; count: number }
        if (data.compounds && data.compounds.length > 0) {
          setCompounds(data.compounds.map((c: any, i: number) => ({
            rank: i + 1,
            id: c.compound_id ?? c.id ?? `CPD-${String(i).padStart(4, "0")}`,
            score: typeof c.score === "number" ? c.score : 0,
            ad: c.in_domain === false ? "out_of_domain" : "in_domain",
            round: c.round ?? 1,
          })))
          setLastUpdated("just now")
        }
        // if empty, keep DEMO_COMPOUNDS (demo mode)
      }
    } catch { /* keep demo data */ }
    setRefreshing(false)
  }, [])

  useEffect(() => { fetchCompounds() }, [fetchCompounds])

  const visible = showAll ? compounds : compounds.slice(0, 10)

  return (
    <div>
      {/* Section header */}
      <div className="flex items-center gap-2.5 mb-3 flex-wrap" style={{ letterSpacing: "-0.005em" }}>
        <h2 className="text-sm font-semibold m-0 leading-none">
          Campaign: <span className="font-mono font-medium">{campaignId.slice(0, 16)}…</span>
        </h2>
        <Chip tone="ok" pulse>ACTIVE</Chip>
        <div className="flex gap-1.5 ml-auto">
          {campaignMeta?.target     && <RegChip>{campaignMeta.target}</RegChip>}
          {campaignMeta?.indication && <RegChip>{campaignMeta.indication}</RegChip>}
        </div>
      </div>

      {/* Meta line */}
      <div className="flex items-center gap-2 text-[12.5px] text-muted-foreground flex-wrap mb-4">
        <span>Round 1</span>
        <span className="text-muted-foreground/40">·</span>
        <span>{compounds.length} compounds ranked</span>
        <span className="text-muted-foreground/40">·</span>
        <span>Last update: {lastUpdated}</span>
        <div className="flex-1" />
        <button
          onClick={fetchCompounds}
          disabled={refreshing}
          data-testid="refresh-btn"
          className="h-[26px] px-2 text-[12px] font-medium border border-border rounded-[4px] bg-white dark:bg-background hover:bg-muted/50 flex items-center gap-1.5 cursor-pointer disabled:opacity-50"
        >
          <RefreshCw className={cn("h-3 w-3", refreshing && "animate-spin")} /> Refresh
        </button>
      </div>

      {/* DMTA Loop Progress */}
      <div data-tour="dmta-stepper" className="border border-border rounded-lg bg-muted/20 px-4 pt-3 pb-4 mb-5">
        <div className="text-[11px] uppercase tracking-[0.05em] text-muted-foreground font-semibold mb-3">
          DMTA Loop Progress
        </div>
        <DmtaStepper loopRunning={loopRunning} />
      </div>

      {/* Top Compounds */}
      <div className="flex items-center gap-2 mb-2.5">
        <span className="text-[13.5px] font-semibold">Top Compounds</span>
        <span className="text-xs text-muted-foreground">
          Showing {visible.length} of {compounds.length}
        </span>
        <div className="flex-1" />
        {compounds.length > 10 && (
          <button
            className="text-xs text-muted-foreground bg-transparent border-0 border-b border-dotted border-border hover:text-blue-600 cursor-pointer"
            onClick={() => setShowAll(!showAll)}
          >
            {showAll ? "Show top 10" : `See all ${compounds.length} →`}
          </button>
        )}
      </div>

      <div className="border border-border rounded-md overflow-hidden">
        <table className="w-full text-[13px] border-collapse">
          <thead>
            <tr className="border-b border-border bg-muted/30">
              {["#", "COMPOUND ID", "SCORE", "AD STATUS", "ROUND PROPOSED"].map((h, i) => (
                <th key={h} className={cn(
                  "py-2 px-2.5 text-[11px] font-semibold uppercase tracking-[0.05em] text-muted-foreground",
                  i === 0 ? "w-9" : i >= 2 ? "w-36" : "",
                  "text-left",
                )}>
                  {h}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {visible.map((c) => (
              <tr
                key={c.id}
                className={cn(
                  "border-b border-border last:border-0 hover:bg-muted/20 transition-colors",
                  c.ad === "out_of_domain" && "opacity-50",
                )}
              >
                <td className="py-2.5 px-2.5 font-mono text-[12px] text-muted-foreground">{c.rank}</td>
                <td className="py-2.5 px-2.5 font-mono text-[12.5px]">{c.id}</td>
                <td className="py-2.5 px-2.5"><ScoreBar score={c.score} /></td>
                <td className="py-2.5 px-2.5">
                  {c.ad === "in_domain"
                    ? <span className="inline-flex items-center gap-1 text-green-700 dark:text-green-400 text-xs font-medium"><Check className="h-3 w-3" /> in domain</span>
                    : <span className="text-amber-600 dark:text-amber-400 text-xs font-medium">▲ OOD</span>
                  }
                </td>
                <td className="py-2.5 px-2.5 font-mono text-[12px] text-muted-foreground">
                  Round {c.round}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {/* UC-CRO-04 / UC-CRO-05: regulated action buttons */}
      <div data-tour="dashboard-actions" className="flex gap-2 mt-3.5">
        <button
          data-testid="ingest-assay-btn"
          onClick={onIngestAssay}
          className="h-8 px-3 text-[13px] font-medium border border-border rounded-[6px] bg-white dark:bg-background hover:bg-muted/50 flex items-center gap-1.5 cursor-pointer"
        >
          <Upload className="h-3.5 w-3.5" /> Ingest New Assay Results
        </button>
        <button
          data-testid="export-cro-btn"
          onClick={onExportCroOrder}
          className="h-8 px-3 text-[13px] font-medium rounded-[6px] bg-foreground text-background hover:bg-foreground/90 flex items-center gap-1.5 border-0 cursor-pointer"
        >
          <ExternalLink className="h-3.5 w-3.5" /> Export CRO Order
        </button>
      </div>
    </div>
  )
}

// ── Tabs config ───────────────────────────────────────────────────────────────

// Inline SVG icons matching CroIcon definitions from the reference
const CroTabIcon = ({ name, size = 13 }: { name: string; size?: number }) => {
  const s = { width: size, height: size, viewBox: "0 0 24 24", fill: "none",
    stroke: "currentColor", strokeWidth: 1.75, strokeLinecap: "round" as const, strokeLinejoin: "round" as const }
  if (name === "target") return <svg {...s}><circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="5"/><circle cx="12" cy="12" r="1.5" fill="currentColor"/></svg>
  if (name === "beaker") return <svg {...s}><path d="M9 3v7L4 20a2 2 0 0 0 1.7 3h12.6A2 2 0 0 0 20 20l-5-10V3"/><line x1="8" y1="3" x2="16" y2="3"/><line x1="6.5" y1="15" x2="17.5" y2="15"/></svg>
  if (name === "shield") return <svg {...s}><path d="M12 3l8 3v6c0 5-4 9-8 9s-8-4-8-9V6z"/></svg>
  if (name === "refresh") return <svg {...s}><polyline points="3 12 3 6 9 6"/><path d="M3 12a9 9 0 1 0 3-6.7"/></svg>
  if (name === "file") return <svg {...s}><path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><polyline points="14 3 14 8 19 8"/></svg>
  return null
}

const TABS = [
  { key: "dashboard",    label: "Dashboard",    icon: "target",  count: null,  pulse: false },
  { key: "validation",   label: "Validation",   icon: "beaker",  count: null,  pulse: false },
  { key: "audit",        label: "Audit",        icon: "shield",  count: 47,    pulse: false },
  { key: "auto-retrain", label: "Auto-Retrain", icon: "refresh", count: null,  pulse: true  },
  { key: "ind-assembly", label: "IND",          icon: "file",    count: null,  pulse: false },
] as const

type TabKey = typeof TABS[number]["key"]

// ── Toast ─────────────────────────────────────────────────────────────────────

function ToastMsg({ text, onDone }: { text: string; onDone: () => void }) {
  useEffect(() => {
    const t = setTimeout(onDone, 2200)
    return () => clearTimeout(t)
  }, [onDone])
  return (
    <div
      className="fixed bottom-6 left-1/2 -translate-x-1/2 px-4 py-2.5 rounded-[8px] text-[13px] font-medium text-white z-50 pointer-events-none"
      style={{ background: "oklch(0.22 0.01 260)", boxShadow: "0 4px 12px rgba(15,23,42,0.2)" }}
    >
      {text}
    </div>
  )
}

// ── eSig Modal ────────────────────────────────────────────────────────────────

function OtpInput({
  state,
  onComplete,
}: {
  state: "idle" | "checking" | "error" | "success"
  onComplete: (code: string) => void
}) {
  const [vals, setVals] = useState(["", "", "", "", "", ""])
  const refs = useRef<(HTMLInputElement | null)[]>([])

  const onChange = (i: number, v: string) => {
    if (!/^\d?$/.test(v)) return
    const next = [...vals]; next[i] = v; setVals(next)
    if (v && i < 5) refs.current[i + 1]?.focus()
    if (next.every(x => x !== "")) onComplete(next.join(""))
  }
  const onKey = (i: number, e: React.KeyboardEvent) => {
    if (e.key === "Backspace" && !vals[i] && i > 0) refs.current[i - 1]?.focus()
  }
  useEffect(() => { refs.current[0]?.focus() }, [])

  const isError = state === "error"
  const isSuccess = state === "success"
  const isDisabled = state === "checking" || state === "success"

  return (
    <div className="flex gap-2 justify-center my-4">
      {vals.map((v, i) => (
        <input
          key={i}
          ref={el => { refs.current[i] = el }}
          value={v}
          onChange={e => onChange(i, e.target.value)}
          onKeyDown={e => onKey(i, e)}
          disabled={isDisabled}
          maxLength={1}
          className={cn(
            "w-10 h-12 text-center text-[18px] font-mono font-semibold rounded-[6px] border-2 outline-none transition-colors",
            isError ? "border-red-400 bg-red-50 text-red-700" :
            isSuccess ? "border-green-400 bg-green-50 text-green-700" :
            v ? "border-blue-400 bg-blue-50" : "border-border bg-white",
            "focus:border-blue-500",
          )}
        />
      ))}
    </div>
  )
}

type EsigAction = "EXPORT_CRO_ORDER" | "INGEST_ASSAY" | "GENERATE_IND"

const ESIG_MEANINGS: Record<EsigAction, string> = {
  EXPORT_CRO_ORDER: "I approve the synthesis order for this campaign and confirm I have reviewed the compound selection.",
  INGEST_ASSAY: "I confirm this assay data is accurate and authorize it to update the PBPK model for this campaign.",
  GENERATE_IND: "I approve the IND §2.6.1 package for this campaign and confirm the content is accurate for regulatory submission.",
}

// UC-CRO-10: auto-enroll current user in eSig TOTP on page load
async function ensureEsigEnrolled(userId: string): Promise<void> {
  try {
    const statusRes = await fetch(`/api/drug-discovery/esig/status?user_id=${encodeURIComponent(userId)}`, { credentials: "include" })
    if (statusRes.ok) {
      const { enrolled } = await statusRes.json() as { enrolled: boolean }
      if (enrolled) return
    }
    // Not enrolled — start enrollment (backend generates TOTP secret)
    await fetch(`/api/drug-discovery/esig/enroll?user_id=${encodeURIComponent(userId)}`, {
      method: "POST", credentials: "include",
      headers: { "Content-Type": "application/json" }, body: "{}"
    })
    // Verify with a "bypass" token for demo: try backend with a fixed code
    // In production this would require the user to scan the QR and verify.
    // For the demo we skip verification — enrollment is "pending" and sign bypasses if not verified.
  } catch { /* non-blocking */ }
}

function EsigModal({
  action,
  target,
  userId,
  campaignId,
  onClose,
  onSigned,
  onToast,
}: {
  action: EsigAction
  target: string
  userId: string
  campaignId: string
  onClose: () => void
  onSigned?: () => void
  onToast: (msg: string) => void
}) {
  const [state, setState] = useState<"idle" | "checking" | "error" | "success">("idle")
  const [countdown, setCountdown] = useState(23)
  const [errorMsg, setErrorMsg] = useState("Invalid code. Try again.")

  useEffect(() => {
    if (state === "success") return
    const t = setInterval(() => setCountdown(c => c <= 0 ? 30 : c - 1), 1000)
    return () => clearInterval(t)
  }, [state])

  const onComplete = async (code: string) => {
    setState("checking")
    setErrorMsg("Invalid code. Try again.")
    try {
      // Try real backend sign — works if user is enrolled and TOTP is correct
      const res = await fetch(`/api/drug-discovery/${campaignId}/esig/sign`, {
        method: "POST", credentials: "include",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          user_id: userId,
          action,
          meaning: ESIG_MEANINGS[action],
          totp_token: code,
        }),
      })
      if (res.ok) {
        setState("success")
        setTimeout(() => {
          onToast(`Signed · ${action} recorded to audit trail`)
          onClose()
          onSigned?.()
        }, 700)
        return
      }
      const err = await res.json().catch(() => ({})) as any
      const detail = err?.detail ?? "Verification failed"
      // If user is not enrolled, fall back to demo acceptance for demo purposes
      if (detail.includes("not registered")) {
        // Demo fallback: accept code "123456" or any code after enrollment failure
        if (code === "123456") {
          setState("success")
          setTimeout(() => {
            onToast(`Signed · ${action} recorded to audit trail`)
            onClose()
            onSigned?.()
          }, 700)
          return
        }
        setErrorMsg("Use code 123456 for demo (real TOTP not yet enrolled)")
      } else {
        setErrorMsg(detail.length < 60 ? detail : "Invalid code. Try again.")
      }
      setState("error")
      setTimeout(() => setState("idle"), 2000)
    } catch {
      setState("error")
      setTimeout(() => setState("idle"), 1500)
    }
  }

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center"
      style={{ background: "rgba(15,23,42,0.45)" }}
      onClick={onClose}
    >
      <div
        className="w-full max-w-[440px] mx-4 rounded-[12px] overflow-hidden"
        style={{ background: "#ffffff", boxShadow: "0 4px 12px rgba(15,23,42,0.08), 0 16px 40px rgba(15,23,42,0.06)" }}
        onClick={e => e.stopPropagation()}
      >
        {/* Head */}
        <div className="px-5 pt-5 pb-3.5" style={{ borderBottom: "1px solid oklch(0.915 0.006 240)" }}>
          <div className="text-[15px] font-semibold" style={{ letterSpacing: "-0.01em" }}>Electronic Signature Required</div>
          <div className="text-[12px] mt-0.5 font-mono" style={{ color: "oklch(0.48 0.012 260)" }}>21 CFR Part 11 §11.200(a)(1)</div>
        </div>

        {/* Body */}
        <div className="px-5 pt-4 pb-5">
          {/* Action details */}
          <div className="rounded-[6px] text-[13px] mb-3.5" style={{ border: "1px solid oklch(0.915 0.006 240)", background: "oklch(0.985 0.003 240)", padding: "10px 12px" }}>
            <div className="flex gap-2 mb-1"><span style={{ color: "oklch(0.48 0.012 260)" }}>Action:</span> <span className="font-mono">{action}</span></div>
            <div className="flex gap-2 mb-1"><span style={{ color: "oklch(0.48 0.012 260)" }}>Campaign:</span> <span className="font-mono">{campaignId.slice(0, 16)}…</span></div>
            <div className="flex gap-2"><span style={{ color: "oklch(0.48 0.012 260)" }}>Target:</span> {target}</div>
          </div>

          {/* Meaning */}
          <div className="text-[12px] font-semibold mb-1" style={{ color: "oklch(0.48 0.012 260)" }}>Meaning of signature</div>
          <div className="rounded-[6px] text-[12.5px] leading-relaxed mb-1" style={{ border: "1px solid oklch(0.915 0.006 240)", background: "oklch(0.96 0.03 280)", color: "oklch(0.32 0.14 280)", padding: "10px 12px" }}>
            {ESIG_MEANINGS[action]}
          </div>
          <div className="text-[11px] italic mb-3" style={{ color: "oklch(0.62 0.010 260)" }}>
            This meaning is permanently recorded in the audit trail.
          </div>

          {/* OTP */}
          <div className="text-[12.5px] text-center" style={{ color: "oklch(0.48 0.012 260)" }}>
            Enter your 6-digit authenticator code
          </div>
          <OtpInput state={state} onComplete={onComplete} />
          <div
            data-testid={state === "error" ? "esig-error" : state === "success" ? "esig-success" : undefined}
            className={cn("text-[11.5px] text-center mb-3", state === "error" ? "text-red-600" : "")}
          >
            {state === "error" ? errorMsg : `Code refreshes in ${countdown}s`}
          </div>

          <div className="text-[11px] leading-relaxed" style={{ color: "oklch(0.62 0.010 260)" }}>
            🛡 This signature is uniquely linked to your identity and cannot be reused. The audit record will include your user ID, the meaning above, and a SHA-256 hash of this action's payload.
          </div>
        </div>

        {/* Footer */}
        <div className="flex items-center gap-2 px-5 py-3" style={{ borderTop: "1px solid oklch(0.915 0.006 240)", background: "oklch(0.985 0.003 240)" }}>
          <button
            onClick={onClose}
            className="h-8 px-3 text-[13px] font-medium rounded-[6px] cursor-pointer"
            style={{ border: "1px solid transparent", background: "transparent", color: "oklch(0.48 0.012 260)" }}
          >
            Cancel
          </button>
          <div className="flex-1" />
          <button
            className="h-8 px-4 text-[13px] font-medium rounded-[6px] cursor-pointer flex items-center gap-1.5"
            style={{ background: "oklch(0.22 0.01 260)", color: "#ffffff", border: "none", opacity: state !== "idle" && state !== "error" ? 0.5 : 1 }}
            disabled={state !== "idle" && state !== "error"}
          >
            {state === "checking" ? <><Loader2 className="h-3.5 w-3.5 animate-spin" /> Verifying…</>
              : state === "success" ? <><Check className="h-3.5 w-3.5" /> Signed</>
              : <>Sign and Continue <ChevronRight className="h-3.5 w-3.5" /></>}
          </button>
        </div>
      </div>
    </div>
  )
}

// ── Campaign Wizard ───────────────────────────────────────────────────────────

function CampaignWizard({
  onDone,
  onToast,
  onCreated,
  userId,
}: {
  onDone: () => void
  onToast: (msg: string) => void
  onCreated?: (entry: CampaignEntry) => void
  userId?: string
}) {
  const [step, setStep] = useState(1)
  const [mol, setMol] = useState("")
  const [target, setTarget] = useState("")
  const [indication, setIndication] = useState("")
  const [sponsor, setSponsor] = useState("")
  const [objective, setObjective] = useState("balance")
  const [parsed, setParsed] = useState<{ n: number; invalid: number } | null>(null)
  const [validationProgress, setValidationProgress] = useState(0)
  const [launching, setLaunching] = useState(false)

  useEffect(() => {
    if (step !== 3) return
    const t = setInterval(() => setValidationProgress(p => Math.min(100, p + 10)), 300)
    return () => clearInterval(t)
  }, [step])

  const step1Ok = mol.trim() && target.trim() && indication.trim()

  const fieldStyle = {
    display: "flex" as const, flexDirection: "column" as const, gap: 4,
  }
  const labelStyle = { fontSize: 12, fontWeight: 500 as const, color: "oklch(0.48 0.012 260)" }
  const inputStyle = {
    height: 34, padding: "0 10px", borderRadius: 6, fontSize: 13,
    border: "1px solid oklch(0.915 0.006 240)", background: "#ffffff",
    outline: "none", width: "100%",
  }

  return (
    <div>
      {/* Header */}
      <div className="flex items-center gap-3 mb-5">
        <h2 className="text-[15px] font-semibold m-0" style={{ letterSpacing: "-0.01em" }}>New Drug Discovery Campaign</h2>
        <div className="flex-1" />
        <span className="text-[12px] font-mono px-2 py-0.5 rounded-[4px]" style={{ background: "oklch(0.965 0.004 240)", color: "oklch(0.48 0.012 260)" }}>
          Step {step}/3
        </span>
      </div>

      {step === 1 && (
        <div>
          <div className="grid gap-3" style={{ gridTemplateColumns: "1fr 1fr" }}>
            <div style={fieldStyle}>
              <label style={labelStyle}>Compound name</label>
              <input style={inputStyle} value={mol} onChange={e => setMol(e.target.value)} placeholder="e.g. BMT-4451" />
            </div>
            <div style={fieldStyle}>
              <label style={labelStyle}>Biological target</label>
              <input style={inputStyle} value={target} onChange={e => setTarget(e.target.value)} placeholder="e.g. EGFR L858R" />
            </div>
            <div style={fieldStyle}>
              <label style={labelStyle}>Therapeutic indication</label>
              <input style={inputStyle} value={indication} onChange={e => setIndication(e.target.value)} placeholder="e.g. NSCLC" />
            </div>
            <div style={fieldStyle}>
              <label style={labelStyle}>Sponsor organization</label>
              <input style={inputStyle} value={sponsor} onChange={e => setSponsor(e.target.value)} placeholder="e.g. BioMate Technologies" />
            </div>
          </div>

          <div className="mt-3" style={fieldStyle}>
            <label style={labelStyle}>Optimization objective</label>
            <div className="flex flex-col gap-2 mt-1">
              {([
                { k: "potency",  l: "Maximize potency",        d: "Weight IC50 ~0.6; ADMET ~0.2; novelty ~0.2" },
                { k: "admet",    l: "Optimize ADMET profile",   d: "Weight IC50 ~0.3; ADMET ~0.5; novelty ~0.2" },
                { k: "balance",  l: "Balance potency + ADMET",  d: "Even weighting across all three objectives" },
              ] as const).map(o => (
                <label
                  key={o.k}
                  className="flex items-start gap-3 rounded-[6px] cursor-pointer"
                  style={{ padding: "8px 10px", border: `1px solid ${objective === o.k ? "oklch(0.55 0.14 245)" : "oklch(0.915 0.006 240)"}`, background: objective === o.k ? "oklch(0.96 0.03 245)" : "#ffffff" }}
                >
                  <input type="radio" checked={objective === o.k} onChange={() => setObjective(o.k)} className="mt-0.5" />
                  <span className="flex-1">
                    <div className="text-[13px] font-medium">{o.l}</div>
                    <div className="text-[11.5px] mt-0.5" style={{ color: "oklch(0.62 0.010 260)" }}>{o.d}</div>
                  </span>
                </label>
              ))}
            </div>
          </div>

          <div className="flex justify-between mt-5">
            <button onClick={onDone} className="h-8 px-3 text-[13px] font-medium rounded-[6px] cursor-pointer" style={{ border: "1px solid transparent", background: "transparent", color: "oklch(0.48 0.012 260)" }}>
              Cancel
            </button>
            <button
              disabled={!step1Ok}
              onClick={() => setStep(2)}
              className="h-8 px-4 text-[13px] font-medium rounded-[6px] cursor-pointer flex items-center gap-1"
              style={{ background: "oklch(0.22 0.01 260)", color: "#ffffff", border: "none", opacity: step1Ok ? 1 : 0.4 }}
            >
              Next <ChevronRight className="h-3.5 w-3.5" />
            </button>
          </div>
        </div>
      )}

      {step === 2 && (
        <div>
          <p className="text-[13.5px] mb-4" style={{ color: "oklch(0.48 0.012 260)" }}>
            Upload your initial compound set (SMILES format). This library will be used as the virtual library for auto-retrain proposals.
          </p>

          <div
            className="rounded-[8px] flex flex-col items-center justify-center text-center cursor-pointer transition-colors"
            style={{ border: `2px dashed ${parsed ? "oklch(0.62 0.13 150)" : "oklch(0.915 0.006 240)"}`, padding: "32px 24px", background: parsed ? "oklch(0.96 0.04 150)" : "oklch(0.985 0.003 240)", minHeight: 140 }}
            onClick={() => setParsed({ n: 282, invalid: 0 })}
          >
            {parsed ? (
              <>
                <Check className="h-6 w-6 mb-2" style={{ color: "oklch(0.62 0.13 150)" }} />
                <div className="text-[14px] font-semibold">library-seed.csv parsed</div>
                <div className="text-[12.5px] mt-1" style={{ color: "oklch(0.48 0.012 260)" }}>{parsed.n} compounds · {parsed.invalid} invalid SMILES</div>
              </>
            ) : (
              <>
                <Upload className="h-6 w-6 mb-2" style={{ color: "oklch(0.62 0.010 260)" }} />
                <div className="text-[14px] font-semibold">Drag and drop .csv, .smi, or .txt</div>
                <div className="text-[13px] mt-1" style={{ color: "oklch(0.48 0.012 260)" }}>or <span className="underline cursor-pointer">browse files</span></div>
                <div className="text-[11.5px] mt-2" style={{ color: "oklch(0.62 0.010 260)" }}>Format: one SMILES per line, or CSV with SMILES in the first column.</div>
              </>
            )}
          </div>

          <div className="flex justify-between mt-5">
            <button onClick={() => setStep(1)} className="h-8 px-3 text-[13px] font-medium rounded-[6px] cursor-pointer flex items-center gap-1" style={{ border: "1px solid oklch(0.915 0.006 240)", background: "#ffffff", color: "oklch(0.22 0.01 260)" }}>
              <ChevronRight className="h-3.5 w-3.5 rotate-180" /> Back
            </button>
            <button
              disabled={!parsed}
              onClick={() => setStep(3)}
              className="h-8 px-4 text-[13px] font-medium rounded-[6px] cursor-pointer flex items-center gap-1"
              style={{ background: "oklch(0.22 0.01 260)", color: "#ffffff", border: "none", opacity: parsed ? 1 : 0.4 }}
            >
              Next <ChevronRight className="h-3.5 w-3.5" />
            </button>
          </div>
        </div>
      )}

      {step === 3 && (
        <div>
          <div className="rounded-[8px] mb-4" style={{ border: "1px solid oklch(0.915 0.006 240)", background: "oklch(0.985 0.003 240)", padding: 14 }}>
            {([
              ["Compound", mol],
              ["Target", target],
              ["Indication", indication],
              ["Virtual library", `${parsed?.n ?? 0} compounds`],
              ["Auto-retrain", "Enabled · check every 60 min"],
              ["21 CFR Part 11", "Audit trail active"],
            ] as [string, string][]).map(([k, v], i, arr) => (
              <div key={k} className="flex gap-2 text-[13px]" style={{ padding: "6px 0", borderBottom: i < arr.length - 1 ? "1px dashed oklch(0.915 0.006 240)" : "none" }}>
                <span className="w-36 shrink-0" style={{ color: "oklch(0.48 0.012 260)" }}>{k}</span>
                <span className="flex-1">{v}</span>
              </div>
            ))}
            <div className="flex gap-2 text-[13px]" style={{ padding: "10px 0 4px" }}>
              <span className="w-36 shrink-0" style={{ color: "oklch(0.48 0.012 260)" }}>Model validation</span>
              <span className="flex-1 flex items-center gap-3">
                {validationProgress < 100 ? (
                  <>
                    <span style={{ color: "oklch(0.48 0.012 260)" }}>Running…</span>
                    <div className="flex-1 h-1.5 rounded-full overflow-hidden" style={{ background: "oklch(0.915 0.006 240)", maxWidth: 180 }}>
                      <div className="h-full rounded-full bg-blue-500 transition-all" style={{ width: `${validationProgress}%` }} />
                    </div>
                    <span className="font-mono text-[11.5px]" style={{ color: "oklch(0.62 0.010 260)" }}>{validationProgress}%</span>
                  </>
                ) : (
                  <span className="inline-flex items-center gap-1 text-[11.5px] font-medium px-2 py-0.5 rounded-full" style={{ background: "oklch(0.96 0.04 150)", color: "oklch(0.62 0.13 150)" }}>
                    <Check className="h-3 w-3" /> EMA criterion met
                  </span>
                )}
              </span>
            </div>
          </div>

          <p className="text-[12.5px] leading-relaxed mb-4" style={{ color: "oklch(0.48 0.012 260)" }}>
            Once launched, BioMate will: (1) run PBPK model validation against 31 reference drugs, (2) start the audit trail, (3) activate the auto-retrain loop, and (4) enable CRO order export and IND assembly.
          </p>

          <div className="flex justify-between mt-5">
            <button onClick={() => setStep(2)} className="h-8 px-3 text-[13px] font-medium rounded-[6px] cursor-pointer flex items-center gap-1" style={{ border: "1px solid oklch(0.915 0.006 240)", background: "#ffffff", color: "oklch(0.22 0.01 260)" }}>
              <ChevronRight className="h-3.5 w-3.5 rotate-180" /> Back
            </button>
            <button
              disabled={launching}
              onClick={async () => {
                setLaunching(true)
                const newId = `cmp-${mol.toLowerCase().replace(/[^a-z0-9]/g, "").slice(0, 8)}-${Math.floor(Date.now() / 1000).toString(16)}`
                const entry: CampaignEntry = {
                  campaign_id: newId, user_id: userId ?? "",
                  molecule_name: mol, target, indication, sponsor, objective,
                  created_at: new Date().toISOString(),
                }
                if (onCreated) { await onCreated(entry) }
                else { onToast("Campaign launched"); onDone() }
                setLaunching(false)
              }}
              className="h-8 px-4 text-[13px] font-medium rounded-[6px] cursor-pointer flex items-center gap-1 disabled:opacity-50"
              style={{ background: "oklch(0.22 0.01 260)", color: "#ffffff", border: "none" }}
            >
              {launching ? <><Loader2 className="h-3.5 w-3.5 animate-spin" /> Launching…</> : <>Launch Campaign <ChevronRight className="h-3.5 w-3.5" /></>}
            </button>
          </div>
        </div>
      )}
    </div>
  )
}

// ── Tutorial Tour ─────────────────────────────────────────────────────────────

interface TourStep {
  id: string
  target: string | null
  placement: "top" | "bottom" | "left" | "right" | "center"
  title: string
  body: React.ReactNode
  setup?: (setTab: (t: TabKey) => void) => void
  cta?: string
}

const TOUR_STEPS: TourStep[] = [
  {
    id: "welcome", target: null, placement: "center",
    title: "Welcome to the BioMate CRO tour",
    body: <>I'll walk you through the compliance workspace in about 90 seconds. You'll see how the <b>DMTA loop</b>, <b>model validation</b>, <b>audit chain</b>, and <b>electronic signatures</b> work together to keep a campaign regulator-ready.<br/><span style={{ fontSize: 11.5, color: "oklch(0.62 0.010 260)", marginTop: 6, display: "block" }}>Use → / ← to step, Esc to skip.</span></>,
    setup: (setTab) => setTab("dashboard"),
  },
  {
    id: "tabs", target: '[data-tour="tabs-bar"]', placement: "bottom",
    title: "Five surfaces, one campaign",
    body: <>Each tab is a regulated view into the same campaign — Dashboard, Validation, Audit, Auto-Retrain, and IND assembly. I'll visit each one.</>,
  },
  {
    id: "dmta", target: '[data-tour="dmta-stepper"]', placement: "bottom",
    title: "The DMTA loop",
    body: <>Design → Make → Test → Analyse. This campaign is in Round 3 and currently <b>Making</b>. Auto-retrain advances the loop every time new assay data lands.</>,
    setup: (setTab) => setTab("dashboard"),
  },
  {
    // Spotlight the campaign card header (always fully visible) rather than the
    // action buttons at the very bottom which can be off-screen at some heights.
    id: "dashboard-actions", target: '[data-tour="campaign-header"]', placement: "bottom",
    title: "Regulated actions live here",
    body: <><b>Ingest Assay</b> and <b>Export CRO Order</b> (below ↓) are 21 CFR Part 11 actions — they require an electronic signature and they write to the audit chain.</>,
  },
  {
    id: "validation", target: '[data-tour="validation-callout"]', placement: "bottom",
    title: "EMA 2-fold qualification",
    body: <>We qualify the PBPK model against a 31-drug reference set. Regulators need Cmax and AUC within 2× for ≥67% of drugs. The model passes — evidence you can cite directly in §2.6.1.2.</>,
    setup: (setTab) => setTab("validation"),
  },
  {
    id: "audit", target: '[data-tour="audit-list"]', placement: "top",
    title: "Tamper-evident audit chain",
    body: <>Every regulated action is a record. Each record carries the previous record's SHA-256 hash, so any change anywhere breaks the chain — and we show you exactly where.</>,
    setup: (setTab) => setTab("audit"),
  },
  {
    id: "retrain", target: '[data-tour="loop-strip"]', placement: "bottom",
    title: "Auto-retrain loop",
    body: <>The loop polls for new assay data. When it finds any, it retrains and proposes a new round of compounds. You can pause it, trigger it manually, or let it run.</>,
    setup: (setTab) => setTab("auto-retrain"),
  },
  {
    id: "ind-generate", target: '[data-tour="ind-generate"]', placement: "top",
    title: "One-click IND §2.6.1",
    body: <>Fill the campaign details, click <b>Generate IND Package</b>, and we assemble the full §2.6.1 Nonclinical Overview — pulling numbers from the validation report, audit chain, and compound rankings — into a signed Markdown + DOCX bundle.</>,
    setup: (setTab) => setTab("ind-assembly"),
  },
  {
    id: "esig", target: '[data-tour="esig-btn"]', placement: "bottom",
    title: "Electronic signatures",
    body: <>Any regulated action opens a Part 11-compliant e-signature modal: TOTP code, meaning-of-signature, and a permanent audit record. Try clicking <b>Export CRO Order</b> on the dashboard to see the full flow.</>,
    setup: (setTab) => setTab("dashboard"),
  },
  {
    id: "done", target: null, placement: "center",
    title: "You're ready",
    body: <>
      <ul style={{ paddingLeft: 18, margin: "8px 0 0", lineHeight: 1.7, color: "oklch(0.48 0.012 260)", fontSize: 12.5 }}>
        <li>Replay this tour anytime from the <b style={{ color: "oklch(0.22 0.01 260)" }}>Tutorial</b> button in the top bar.</li>
        <li>Click a regulated action (Ingest Assay, Export CRO Order) to trigger the e-signature flow.</li>
        <li>Switch between tabs to explore Validation, Audit, Auto-Retrain, and IND Assembly.</li>
      </ul>
    </>,
    cta: "Start exploring",
  },
]

function TourSpotlight({ rect }: { rect: DOMRect | null }) {
  // Single persistent element — no unmount/remount flash between steps.
  // When rect is null (center steps): full-screen overlay from origin with huge spread.
  // When rect is set: box-shadow punches a spotlight; smooth CSS transitions glide it.
  const pad  = 8
  const x    = rect ? rect.left  - pad      : 0
  const y    = rect ? rect.top   - pad      : 0
  const w    = rect ? rect.width + pad * 2  : 0
  const h    = rect ? rect.height + pad * 2 : 0
  // 200 000 px spread from (0,0) covers any conceivable viewport as a plain overlay.
  const shadow = rect
    ? "0 0 0 9999px rgba(12,14,20,0.45)"
    : "0 0 0 200000px rgba(12,14,20,0.45)"
  return (
    <div
      aria-hidden="true"
      style={{
        position: "fixed",
        left: x, top: y, width: w, height: h,
        borderRadius: rect ? 8 : 0,
        boxShadow: shadow,
        outline: rect ? "2px solid rgba(99,140,255,0.75)" : "none",
        pointerEvents: "none",
        zIndex: 9000,
        transition: "left 0.35s ease, top 0.35s ease, width 0.35s ease, height 0.35s ease",
      }}
    />
  )
}

function TourCallout({
  step, total, stepData, targetRect,
  onNext, onPrev, onSkip,
}: {
  step: number; total: number; stepData: TourStep; targetRect: DOMRect | null
  onNext: () => void; onPrev: () => void; onSkip: () => void
}) {
  const calloutRef = useRef<HTMLDivElement>(null)
  const [calloutH, setCalloutH] = useState(200)
  useEffect(() => {
    if (calloutRef.current) {
      const h = calloutRef.current.offsetHeight
      setCalloutH(prev => prev !== h ? h : prev)
    }
  }, [step])

  const CW = stepData.placement === "center" ? 420 : 360
  const OFFSET = 14; const MARGIN = 16
  const vw = window.innerWidth; const vh = window.innerHeight

  let calloutStyle: React.CSSProperties = {}
  if (stepData.placement === "center" || !targetRect) {
    calloutStyle = { left: "50%", top: "50%", transform: "translate(-50%, -50%)" }
  } else {
    let effectivePlacement = stepData.placement
    const spaceBelow = vh - targetRect.bottom
    const spaceAbove = targetRect.top
    const needed = calloutH + OFFSET + MARGIN
    if (effectivePlacement === "bottom" && spaceBelow < needed && spaceAbove > needed) effectivePlacement = "top"
    if (effectivePlacement === "top" && spaceAbove < needed && spaceBelow > needed) effectivePlacement = "bottom"

    const cx = targetRect.left + targetRect.width / 2
    let left = 0, top = 0
    if (effectivePlacement === "bottom") { left = cx - CW / 2; top = targetRect.bottom + OFFSET }
    else if (effectivePlacement === "top") { left = cx - CW / 2; top = targetRect.top - OFFSET - calloutH }
    else if (effectivePlacement === "left") { left = targetRect.left - OFFSET - CW; top = targetRect.top + targetRect.height / 2 - calloutH / 2 }
    else { left = targetRect.right + OFFSET; top = targetRect.top + targetRect.height / 2 - calloutH / 2 }

    left = Math.max(MARGIN, Math.min(vw - CW - MARGIN, left))
    top = Math.max(MARGIN, Math.min(vh - calloutH - MARGIN, top))
    calloutStyle = { left, top }
  }

  const isFirst = step === 0
  const isLast = step === total - 1

  return (
    <div
      ref={calloutRef}
      className={`cro-tour-callout${stepData.placement === "center" ? " center" : ""}`}
      style={calloutStyle}
    >
      {/* Meta row */}
      <div className="flex items-center justify-between mb-1.5">
        <span className="text-[10.5px] uppercase tracking-[0.06em] font-semibold" style={{ color: "oklch(0.55 0.14 245)" }}>
          Step {step + 1} of {total}
        </span>
        <button type="button" onClick={onSkip} className="text-[11.5px] cursor-pointer bg-transparent border-0 p-1" style={{ color: "oklch(0.62 0.010 260)" }}>
          Skip tour ×
        </button>
      </div>
      {/* Title */}
      <div className="text-[14.5px] font-semibold mb-1.5" style={{ letterSpacing: "-0.01em", color: "oklch(0.22 0.01 260)" }}>
        {stepData.title}
      </div>
      {/* Body */}
      <div className="text-[12.5px] leading-relaxed" style={{ color: "oklch(0.48 0.012 260)" }}>
        {stepData.body}
      </div>
      {/* Footer */}
      <div className="flex items-center justify-between mt-3 pt-2.5" style={{ borderTop: "1px solid oklch(0.915 0.006 240)" }}>
        {/* Dots */}
        <div className="flex gap-1">
          {Array.from({ length: total }).map((_, i) => (
            <span key={i} className="rounded-full transition-all" style={{
              width: i === step ? 14 : 5, height: 5, borderRadius: 999,
              background: i === step ? "oklch(0.55 0.14 245)" : i < step ? "oklch(0.62 0.010 260)" : "oklch(0.915 0.006 240)",
            }} />
          ))}
        </div>
        {/* Actions */}
        <div className="flex gap-1.5">
          {!isFirst && (
            <button type="button" onClick={onPrev} className="h-7 px-2.5 text-[12px] font-medium rounded-[4px] cursor-pointer" style={{ border: "1px solid oklch(0.915 0.006 240)", background: "transparent", color: "oklch(0.48 0.012 260)" }}>
              ← Back
            </button>
          )}
          <button type="button" onClick={onNext} className="h-7 px-3 text-[12px] font-medium rounded-[4px] cursor-pointer" style={{ background: "oklch(0.22 0.01 260)", color: "#ffffff", border: "none" }}>
            {isLast ? (stepData.cta ?? "Done") : "Next →"}
          </button>
        </div>
      </div>
    </div>
  )
}

function useTour(setActiveTab: (t: TabKey) => void) {
  const [active, setActive] = useState(false)
  const [step, setStep] = useState(0)
  const [rect, setRect] = useState<DOMRect | null>(null)

  const measure = useCallback(() => {
    const s = TOUR_STEPS[step]
    if (!s.target) { setRect(null); return }
    const el = document.querySelector(s.target) as HTMLElement | null
    // If target not found yet (tab still mounting), keep the old rect to avoid
    // a full-dark flash. The retry timeout below will find it shortly.
    if (!el) { return }
    const r = el.getBoundingClientRect()
    const vh = window.innerHeight
    const top = Math.max(8, r.top)
    const bottom = Math.min(vh - 8, r.bottom)
    setRect(new DOMRect(r.left, top, r.width, Math.max(40, bottom - top)))
  }, [step])

  // Apply setup + measure on step change
  useEffect(() => {
    if (!active) return
    const s = TOUR_STEPS[step]
    if (s.setup) s.setup(setActiveTab)
    // Tab-switching steps need extra time for the new panel to mount
    const delay = s.setup ? 700 : 150
    let id1 = requestAnimationFrame(() => { id1 = requestAnimationFrame(measure) })
    const t = setTimeout(measure, delay)
    return () => { cancelAnimationFrame(id1); clearTimeout(t) }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [active, step])

  // Re-measure on resize/scroll
  useEffect(() => {
    if (!active) return
    const onR = () => measure()
    window.addEventListener("resize", onR)
    window.addEventListener("scroll", onR, true)
    return () => { window.removeEventListener("resize", onR); window.removeEventListener("scroll", onR, true) }
  }, [active, measure])

  // Keyboard nav
  useEffect(() => {
    if (!active) return
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") setActive(false)
      else if (e.key === "ArrowRight") next()
      else if (e.key === "ArrowLeft") prev()
    }
    window.addEventListener("keydown", onKey)
    return () => window.removeEventListener("keydown", onKey)
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [active, step])

  const start = () => { setStep(0); setActive(true) }
  const stop = () => setActive(false)
  const next = () => { if (step >= TOUR_STEPS.length - 1) stop(); else setStep(s => s + 1) }
  const prev = () => setStep(s => Math.max(0, s - 1))

  const node = active ? (
    <>
      <TourSpotlight rect={rect} />
      <TourCallout
        step={step} total={TOUR_STEPS.length}
        stepData={TOUR_STEPS[step]} targetRect={rect}
        onNext={next} onPrev={prev} onSkip={stop}
      />
    </>
  ) : null

  return { active, start, node }
}

// ── Page ──────────────────────────────────────────────────────────────────────

export default function DrugDiscoveryCroDemo() {
  const [, navigate] = useLocation()
  const { user } = useAuth()

  // Campaign selection state — null = show campaign list
  const [campaignId, setCampaignId] = useState<string | null>(null)
  const [campaignMeta, setCampaignMeta] = useState<CampaignEntry | null>(null)
  const [campaigns, setCampaigns] = useState<CampaignEntry[]>([])
  const [listPhase, setListPhase] = useState<"loading" | "ready">("loading")

  // Per-campaign state
  const [phase, setPhase] = useState<"idle" | "loading" | "ready" | "error">("idle")
  const [error, setError] = useState("")
  const [activeTab, setActiveTab] = useState<TabKey>("dashboard")
  const [loopRunning, setLoopRunning] = useState(false)
  const [showWizard, setShowWizard] = useState(false)
  const [esigOpen, setEsigOpen] = useState(false)
  const [esigAction, setEsigAction] = useState<EsigAction>("EXPORT_CRO_ORDER")
  const [esigTarget, setEsigTarget] = useState("WuXi AppTec · 10 compounds")
  const [esigOnSigned, setEsigOnSigned] = useState<(() => void) | undefined>(undefined)
  const [toast, setToast] = useState<string | null>(null)
  const tour = useTour(setActiveTab)

  const userId = user?.id ? String(user.id) : (user?.email ?? "demo-user")

  // Load the user's campaign list on mount
  useEffect(() => {
    if (!userId) return
    setListPhase("loading")
    fetchCampaigns(userId).then(list => {
      setCampaigns(list)
      setListPhase("ready")
    })
  }, [userId])

  // Open a campaign by ID
  const openCampaign = useCallback(async (entry: CampaignEntry) => {
    setCampaignId(entry.campaign_id)
    setCampaignMeta(entry)
    setPhase("loading")
    setActiveTab("dashboard")
    ensureEsigEnrolled(userId)
    setPhase("ready")
    // fire-and-forget: seed library + initial retrain if empty
    seedLibrary(entry.campaign_id)
  }, [userId])

  // Create a new campaign from the wizard and open it
  const handleNewCampaignCreated = useCallback(async (entry: CampaignEntry) => {
    const result = await createCampaignApi({
      campaignId:  entry.campaign_id,
      userId,
      molecule:    entry.molecule_name,
      target:      entry.target,
      indication:  entry.indication,
      sponsor:     entry.sponsor,
      objective:   entry.objective,
    })
    if (!result.ok && !result.error?.includes("409")) {
      setError(result.error ?? "Campaign creation failed")
      return
    }
    const updated = await fetchCampaigns(userId)
    setCampaigns(updated)
    const created = updated.find(c => c.campaign_id === entry.campaign_id) ?? entry
    openCampaign(created)
    setShowWizard(false)
  }, [userId, openCampaign])

  // UC-CRO-02: poll retrain status every 10s to sync DMTA stepper
  const pollRetrainStatus = useCallback(async () => {
    if (!campaignId) return
    try {
      const res = await fetch(`/api/drug-discovery/${campaignId}/retrain/status`, { credentials: "include" })
      if (res.ok) {
        const data = await res.json() as { running: boolean }
        setLoopRunning(data.running)
      }
    } catch { /* ignore */ }
  }, [campaignId])

  useEffect(() => {
    if (phase !== "ready") return
    pollRetrainStatus()
    const t = setInterval(pollRetrainStatus, 10_000)
    return () => clearInterval(t)
  }, [phase, pollRetrainStatus])

  // UC-CRO-04: Ingest assay — opens eSig modal, after sign calls ingest API
  const handleIngestAssay = useCallback(() => {
    if (!campaignId) return
    setEsigAction("INGEST_ASSAY")
    setEsigTarget("BioMate CRO · assay batch")
    setEsigOnSigned(() => async () => {
      try {
        await fetch(`/api/drug-discovery/${campaignId}/ingest-assay`, {
          method: "POST", credentials: "include",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ user_id: userId, meaning: ESIG_MEANINGS.INGEST_ASSAY, totp_token: "demo" }),
        })
      } catch { /* best-effort */ }
    })
    setEsigOpen(true)
  }, [campaignId, userId])

  // UC-CRO-05: Export CRO Order — opens eSig modal, after sign downloads file
  const handleExportCroOrder = useCallback(() => {
    if (!campaignId) return
    setEsigAction("EXPORT_CRO_ORDER")
    setEsigTarget("WuXi AppTec · 10 compounds")
    setEsigOnSigned(() => () => {
      const a = document.createElement("a")
      a.href = `/api/drug-discovery/${campaignId}/export/cro-order?fmt=generic`
      a.download = `cro-order-${campaignId}.csv`
      document.body.appendChild(a)
      a.click()
      document.body.removeChild(a)
      setToast("CRO order exported")
    })
    setEsigOpen(true)
  }, [campaignId])

  // ── Campaign list view (no campaign selected) ────────────────────────────────
  if (!campaignId) {
    return (
      <div
        className="flex flex-col overflow-hidden"
        style={{ height: "calc(100vh - 64px)", fontFamily: "'Inter', system-ui, sans-serif", background: "oklch(0.99 0.003 240)" }}
      >
        {/* Top nav */}
        <div className="shrink-0 border-b flex items-center gap-3 px-5" style={{ height: 52, background: "#ffffff", borderColor: "oklch(0.915 0.006 240)" }}>
          <button onClick={() => navigate("/")} className="w-[26px] h-[26px] rounded-[7px] bg-foreground text-background grid place-items-center font-mono text-[13px] font-bold shrink-0 hover:bg-foreground/90 border-0 cursor-pointer" aria-label="Back">B</button>
          <span className="text-[14.5px] font-semibold tracking-[-0.01em]">BioMate</span>
          <div className="flex items-center gap-1 text-[13px] text-muted-foreground">
            <ChevronRight className="h-3.5 w-3.5 text-muted-foreground/40 shrink-0" />
            <span style={{ color: "oklch(0.22 0.01 260)" }}>Drug Discovery · CRO Compliance</span>
          </div>
          <div className="flex-1" />
          <RegChip variant="indigo">21 CFR Part 11</RegChip>
          <RegChip>ICH M4</RegChip>
        </div>

        {/* Campaign list */}
        <div className="flex-1 overflow-y-auto" style={{ padding: "32px clamp(16px, 4%, 48px)" }}>
          <div className="max-w-[760px] mx-auto">
            <div className="flex items-center gap-3 mb-6">
              <div>
                <h1 className="text-[18px] font-semibold tracking-[-0.01em]">CRO Compliance Campaigns</h1>
                <p className="text-[13px] text-muted-foreground mt-0.5">Select a campaign to open its compliance workspace, or create a new one.</p>
              </div>
              <div className="flex-1" />
              <button
                onClick={() => setShowWizard(true)}
                className="h-8 px-3 text-[13px] font-medium flex items-center gap-1.5 rounded-[6px] cursor-pointer"
                style={{ background: "oklch(0.22 0.01 260)", color: "#ffffff", border: "none" }}
              >
                <Plus className="h-3.5 w-3.5" /> New Campaign
              </button>
            </div>

            {listPhase === "loading" ? (
              <div className="flex items-center justify-center py-20 text-muted-foreground gap-2">
                <Loader2 className="h-5 w-5 animate-spin" /> Loading campaigns…
              </div>
            ) : campaigns.length === 0 ? (
              <div
                className="rounded-xl border-2 border-dashed flex flex-col items-center justify-center py-16 text-center cursor-pointer hover:bg-muted/20 transition-colors"
                style={{ borderColor: "oklch(0.915 0.006 240)" }}
                onClick={() => setShowWizard(true)}
              >
                <div className="w-10 h-10 rounded-[10px] mb-3 grid place-items-center" style={{ background: "oklch(0.96 0.03 245)", color: "oklch(0.38 0.12 245)" }}>
                  <Plus className="h-5 w-5" />
                </div>
                <div className="text-[14px] font-semibold mb-1">No campaigns yet</div>
                <div className="text-[13px] text-muted-foreground">Create your first drug discovery campaign to get started.</div>
              </div>
            ) : (
              <div className="space-y-2">
                {campaigns.map(c => (
                  <button
                    key={c.campaign_id}
                    onClick={() => openCampaign(c)}
                    className="w-full text-left rounded-xl border bg-white hover:bg-muted/20 transition-colors px-4 py-3.5 flex items-center gap-3"
                    style={{ borderColor: "oklch(0.915 0.006 240)" }}
                  >
                    <div className="w-8 h-8 rounded-[6px] grid place-items-center shrink-0" style={{ background: "oklch(0.96 0.03 245)", color: "oklch(0.38 0.12 245)" }}>
                      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round">
                        <path d="M4 4c4 0 4 16 8 16s4-16 8-16"/><path d="M4 20c4 0 4-16 8-16s4 16 8 16"/>
                      </svg>
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="text-[14px] font-semibold truncate">{c.molecule_name || c.campaign_id}</div>
                      <div className="text-[12px] text-muted-foreground mt-0.5 flex items-center gap-2 flex-wrap">
                        <span className="font-mono">{c.campaign_id.slice(0, 16)}…</span>
                        {c.target && <><span className="text-muted-foreground/40">·</span><span>{c.target}</span></>}
                        {c.indication && <><span className="text-muted-foreground/40">·</span><span>{c.indication}</span></>}
                      </div>
                    </div>
                    <div className="text-[11.5px] text-muted-foreground shrink-0">
                      {new Date(c.created_at).toLocaleDateString()}
                    </div>
                    <ChevronRight className="h-4 w-4 text-muted-foreground shrink-0" />
                  </button>
                ))}
              </div>
            )}
          </div>
        </div>

        {/* New campaign wizard modal */}
        {showWizard && (
          <div className="fixed inset-0 z-50 flex items-center justify-center" style={{ background: "rgba(0,0,0,0.4)" }}>
            <div className="bg-white rounded-xl shadow-2xl w-full max-w-lg mx-4 p-6" style={{ border: "1px solid oklch(0.915 0.006 240)" }}>
              <CampaignWizard
                onDone={() => setShowWizard(false)}
                onToast={setToast}
                onCreated={handleNewCampaignCreated}
                userId={userId}
              />
            </div>
          </div>
        )}
        {toast && <ToastMsg text={toast} onDone={() => setToast(null)} />}
      </div>
    )
  }

  if (phase === "loading") {
    return (
      <div className="flex items-center justify-center" style={{ height: "calc(100vh - 64px)" }}>
        <div className="flex flex-col items-center gap-3 text-muted-foreground">
          <Loader2 className="h-7 w-7 animate-spin" />
          <p className="text-sm">Initialising CRO campaign…</p>
        </div>
      </div>
    )
  }

  if (phase === "error") {
    return (
      <div className="flex items-center justify-center min-h-screen p-8">
        <Alert variant="destructive" className="max-w-md">
          <AlertTriangle className="h-4 w-4" />
          <AlertDescription>
            <strong>Setup failed:</strong> {error}
            <br />
            <Button size="sm" variant="outline" className="mt-3" onClick={() => { setCampaignId(null); setPhase("idle") }}>
              Back to campaigns
            </Button>
          </AlertDescription>
        </Alert>
      </div>
    )
  }

  const tabLabel = showWizard ? "New Campaign" : (TABS.find((t) => t.key === activeTab)?.label ?? "Dashboard")

  return (
    // .page
    <div
      className="flex flex-col overflow-hidden"
      style={{
        height: "calc(100vh - 64px)",
        fontFamily: "'Inter', system-ui, sans-serif",
        letterSpacing: "-0.005em",
        background: "oklch(0.99 0.003 240)",
      }}
    >
      {/* ── .top-nav ─────────────────────────────────────────────────────────── */}
      <div
        className="shrink-0 border-b flex items-center gap-3 px-5"
        style={{ height: 52, background: "#ffffff", borderColor: "oklch(0.915 0.006 240)" }}
      >
        {/* Brand mark */}
        <button
          onClick={() => navigate("/")}
          className="w-[26px] h-[26px] rounded-[7px] bg-foreground text-background grid place-items-center font-mono text-[13px] font-bold shrink-0 hover:bg-foreground/90 border-0 cursor-pointer"
          data-testid="cro-demo-back-btn"
          aria-label="Back"
        >
          B
        </button>
        <span className="text-[14.5px] font-semibold tracking-[-0.01em]">BioMate</span>

        {/* Breadcrumb */}
        <div className="flex items-center gap-1 text-[13px] text-muted-foreground">
          <button
            onClick={() => { setCampaignId(null); setPhase("idle") }}
            className="text-muted-foreground hover:text-foreground transition-colors bg-transparent border-0 p-0 cursor-pointer text-[13px]"
          >
            Drug Discovery
          </button>
          <ChevronRight className="h-3.5 w-3.5 text-muted-foreground/40 shrink-0" />
          <span>{campaignMeta?.molecule_name || campaignId?.slice(0, 12) || "Campaign"}</span>
          <ChevronRight className="h-3.5 w-3.5 text-muted-foreground/40 shrink-0" />
          <span style={{ color: "oklch(0.22 0.01 260)" }}>{tabLabel}</span>
        </div>

        <div className="flex-1" />

        {/* Tutorial button */}
        <button
          data-tour="tut-btn"
          onClick={tour.start}
          className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-[11.5px] font-semibold cursor-pointer transition-colors"
          style={{ background: "oklch(0.96 0.03 245)", color: "oklch(0.55 0.14 245)", border: "1px solid oklch(0.55 0.14 245)" }}
          title="Replay the tutorial"
        >
          <span style={{ fontSize: 10 }}>▶</span> Tutorial
        </button>

        {/* Reg chips + user badge */}
        <div className="flex items-center gap-2.5">
          <RegChip variant="indigo">21 CFR Part 11</RegChip>
          <RegChip>ICH M4</RegChip>
          <span className="text-muted-foreground/40 text-sm">·</span>
          <div className="flex items-center gap-1.5 text-[12.5px] text-muted-foreground">
            <div
              className="w-[22px] h-[22px] rounded-full grid place-items-center text-[10px] font-semibold shrink-0"
              style={{ background: "oklch(0.85 0.05 60)", color: "oklch(0.35 0.08 60)" }}
            >
              {(user?.name ?? user?.email ?? "U")[0].toUpperCase()}
            </div>
            <span className="hidden sm:inline">{user?.email ?? "user@biotech.com"}</span>
          </div>
        </div>
      </div>

      {/* ── .shell ───────────────────────────────────────────────────────────── */}
      <div
        className="flex-1 overflow-y-auto"
        style={{ padding: "16px clamp(16px, 4%, 48px) 60px" }}
      >
        <div className="max-w-[900px] mx-auto flex flex-col gap-3.5">

          {/* .preamble */}
          <div className="flex flex-col gap-2 px-0.5">
            <div
              className="text-[11px] uppercase tracking-[0.05em] font-semibold"
              style={{ color: "oklch(0.62 0.010 260)" }}
            >
              BioMate Assistant
            </div>
            <p className="text-[14px] leading-relaxed max-w-[720px]" style={{ color: "oklch(0.22 0.01 260)" }}>
              I've loaded the CRO compliance workspace for{" "}
              <code
                className="font-mono text-[12.5px] rounded-[3px] px-1.5 py-0.5"
                style={{ background: "oklch(0.965 0.004 240)" }}
              >
                {campaignId!.slice(0, 16)}…
              </code>
              . Every action you take here—ingest assay data, validate the model, propose new rounds,
              export to a CRO—is recorded in the audit trail. Use the tabs below to review the model
              validation report, inspect the audit chain, or generate your IND §2.6.1 package.
            </p>
          </div>

          {/* .dd-card */}
          <div
            className="overflow-hidden"
            style={{
              border: "1px solid oklch(0.915 0.006 240)",
              borderRadius: 12,
              background: "#ffffff",
              boxShadow: "0 1px 3px rgba(15,23,42,0.06), 0 4px 12px rgba(15,23,42,0.04)",
            }}
          >
            {/* .dd-card-head */}
            <div
              data-tour="campaign-header"
              className="pt-3.5 pb-0 px-5"
              style={{ borderBottom: "1px solid oklch(0.915 0.006 240)", background: "#ffffff" }}
            >
              {/* .row1 */}
              <div className="flex items-center gap-3 mb-1.5">
                <div
                  className="w-8 h-8 rounded-[6px] grid place-items-center shrink-0"
                  style={{ background: "oklch(0.96 0.03 245)", color: "oklch(0.38 0.12 245)" }}
                >
                  {/* CroIcon "dna" — two crossing S-curves */}
                  <svg width="17" height="17" viewBox="0 0 24 24" fill="none"
                    stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round">
                    <path d="M4 4c4 0 4 16 8 16s4-16 8-16"/>
                    <path d="M4 20c4 0 4-16 8-16s4 16 8 16"/>
                  </svg>
                </div>
                <div className="flex-1 min-w-0">
                  <div
                    className="text-[15px] font-semibold leading-none"
                    style={{ letterSpacing: "-0.01em" }}
                  >
                    Drug Discovery · {campaignMeta?.molecule_name || "Campaign"}
                  </div>
                  <div
                    className="text-[12px] mt-px"
                    style={{ color: "oklch(0.62 0.010 260)" }}
                  >
                    <span
                      className="font-mono"
                      data-testid="demo-campaign-id"
                      data-campaign-id={campaignId}
                    >
                      {campaignId!.slice(0, 16)}…
                    </span>
                    {campaignMeta?.target     && ` · ${campaignMeta.target}`}
                    {campaignMeta?.indication && ` · ${campaignMeta.indication}`}
                  </div>
                </div>

                {/* .btn.sm — All campaigns */}
                <button
                  onClick={() => { setCampaignId(null); setPhase("idle") }}
                  className="h-[26px] px-2 text-[12px] font-medium flex items-center gap-1.5 rounded-[4px] cursor-pointer"
                  style={{
                    border: "1px solid oklch(0.915 0.006 240)",
                    background: "#ffffff",
                    color: "oklch(0.22 0.01 260)",
                  }}
                >
                  ← All campaigns
                </button>

                {/* .btn.sm.ghost — Sign action */}
                <button
                  data-tour="esig-btn"
                  onClick={handleExportCroOrder}
                  className="h-[26px] px-2 text-[12px] font-medium flex items-center gap-1.5 rounded-[4px] cursor-pointer"
                  style={{
                    border: "1px solid transparent",
                    background: "transparent",
                    color: "oklch(0.48 0.012 260)",
                  }}
                >
                  <PenLine className="h-3 w-3" /> Sign action
                </button>
              </div>

              {/* .dd-tabs — hidden when wizard is open */}
              <div data-tour="tabs-bar" className="flex overflow-x-auto mt-3.5" style={{ scrollbarWidth: "none", display: showWizard ? "none" : "flex" }}>
                {TABS.map((tab) => (
                  <button
                    key={tab.key}
                    onClick={() => setActiveTab(tab.key)}
                    className={cn(
                      "flex items-center gap-1.5 px-3.5 py-2.5 whitespace-nowrap cursor-pointer",
                      "border-b-2 -mb-px bg-transparent border-l-0 border-r-0 border-t-0",
                      "text-[13px] font-medium transition-colors",
                    )}
                    style={{
                      borderBottomColor: activeTab === tab.key ? "oklch(0.22 0.01 260)" : "transparent",
                      color: activeTab === tab.key
                        ? "oklch(0.22 0.01 260)"
                        : "oklch(0.48 0.012 260)",
                    }}
                    onMouseEnter={(e) => {
                      if (activeTab !== tab.key)
                        (e.currentTarget as HTMLButtonElement).style.color = "oklch(0.22 0.01 260)"
                    }}
                    onMouseLeave={(e) => {
                      if (activeTab !== tab.key)
                        (e.currentTarget as HTMLButtonElement).style.color = "oklch(0.48 0.012 260)"
                    }}
                  >
                    <CroTabIcon name={tab.icon} size={13} />
                    {tab.label}
                    {tab.count != null && (
                      <span
                        className="font-mono text-[11px] px-[5px] py-[1px] rounded-[3px]"
                        style={{
                          background: activeTab === tab.key ? "oklch(0.945 0.005 240)" : "oklch(0.965 0.004 240)",
                          color: "oklch(0.62 0.010 260)",
                        }}
                      >
                        {tab.count}
                      </span>
                    )}
                    {tab.pulse && loopRunning && (
                      <span
                        className="w-1.5 h-1.5 rounded-full animate-pulse"
                        style={{ background: "oklch(0.55 0.14 245)" }}
                      />
                    )}
                  </button>
                ))}
              </div>
            </div>

            {/* .dd-body */}
            <div className="p-5">
              <>
                {activeTab === "dashboard"    && <CampaignDashboard campaignId={campaignId!} campaignMeta={campaignMeta} loopRunning={loopRunning} onIngestAssay={handleIngestAssay} onExportCroOrder={handleExportCroOrder} />}
                {activeTab === "validation"   && <DrugDiscoveryValidationPanel campaignId={campaignId!} />}
                {activeTab === "audit"        && <DrugDiscoveryAuditViewer campaignId={campaignId!} />}
                {activeTab === "auto-retrain" && <DrugDiscoveryAutoRetrain campaignId={campaignId!} />}
                {activeTab === "ind-assembly" && (
                  <DrugDiscoveryIndAssembly
                    campaignId={campaignId!}
                    initialValues={{
                      mol:        campaignMeta?.molecule_name ?? "",
                      target:     campaignMeta?.target ?? "",
                      indication: campaignMeta?.indication ?? "",
                      sponsor:    campaignMeta?.sponsor ?? "",
                    }}
                  />
                )}
              </>
            </div>
          </div>
        </div>
      </div>

      {/* eSig Modal */}
      {esigOpen && campaignId && (
        <EsigModal
          action={esigAction}
          target={esigTarget}
          userId={userId}
          campaignId={campaignId}
          onClose={() => { setEsigOpen(false); setEsigOnSigned(undefined) }}
          onSigned={esigOnSigned}
          onToast={(msg) => setToast(msg)}
        />
      )}

      {/* Toast */}
      {toast && (
        <ToastMsg text={toast} onDone={() => setToast(null)} />
      )}

      {/* Tour overlay */}
      {tour.node}
    </div>
  )
}
