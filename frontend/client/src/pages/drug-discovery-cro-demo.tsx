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

import { useState, useEffect, useRef, Fragment } from "react"
import { useLocation } from "wouter"
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

const DMTA_NODES: { key: string; label: string; status: "done" | "active" | "pending" }[] = [
  { key: "design",  label: "Design",  status: "done"    },
  { key: "make",    label: "Make",    status: "active"  },
  { key: "test",    label: "Test",    status: "pending" },
  { key: "analyse", label: "Analyse", status: "pending" },
]

const CAMPAIGN_META = {
  molecule:   "BMT-4451",
  target:     "EGFR L858R",
  indication: "NSCLC",
  sponsor:    "BioMate Technologies",
  round:      3,
  total:      42,
  updated:    "2h ago",
  objective:  "balance",
}

const CAMPAIGN_ID = `cmp-demo-egfr-${Math.floor(Date.now() / 1000).toString(16)}`

// ── Setup ─────────────────────────────────────────────────────────────────────

async function createCampaign(): Promise<{ ok: boolean; error?: string }> {
  try {
    const res = await fetch("/api/drug-discovery/campaigns", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      credentials: "include",
      body: JSON.stringify({
        campaign_id:            CAMPAIGN_ID,
        molecule_name:          CAMPAIGN_META.molecule,
        target:                 CAMPAIGN_META.target,
        indication:             CAMPAIGN_META.indication,
        objective:              CAMPAIGN_META.objective,
        virtual_library_smiles: DEMO_SMILES,
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

async function seedLibrary(): Promise<void> {
  try {
    await fetch(`/api/drug-discovery/${CAMPAIGN_ID}/virtual-library`, {
      method: "POST", credentials: "include",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ smiles: DEMO_SMILES, n_propose: 5, diversity_weight: 0.3 }),
    })
  } catch { /* non-blocking */ }
  try {
    await fetch(`/api/drug-discovery/${CAMPAIGN_ID}/retrain/trigger`, {
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

function DmtaStepper() {
  return (
    <div className="flex items-start">
      {DMTA_NODES.map((n, i) => (
        <Fragment key={n.key}>
          <div className="flex flex-col items-center gap-1" style={{ minWidth: 80 }}>
            <div className={cn(
              "w-7 h-7 rounded-full border-2 flex items-center justify-center shrink-0",
              n.status === "done"    && "bg-foreground border-foreground text-background",
              n.status === "active"  && "bg-blue-50 border-blue-500 text-blue-600 dark:bg-blue-950/30",
              n.status === "pending" && "bg-background border-border text-muted-foreground",
            )}>
              {n.status === "done"    && <Check className="h-3.5 w-3.5" />}
              {n.status === "active"  && <span className="w-2.5 h-2.5 rounded-full bg-blue-500 animate-pulse" />}
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
              {n.status === "active" ? "running" : n.status === "done" ? "completed" : "pending"}
            </span>
          </div>
          {i < DMTA_NODES.length - 1 && (
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

function CampaignDashboard() {
  const [showAll, setShowAll] = useState(false)
  const visible = showAll ? DEMO_COMPOUNDS : DEMO_COMPOUNDS.slice(0, 10)

  return (
    <div>
      {/* Section header */}
      <div className="flex items-center gap-2.5 mb-3 flex-wrap" style={{ letterSpacing: "-0.005em" }}>
        <h2 className="text-sm font-semibold m-0 leading-none">
          Campaign: <span className="font-mono font-medium">{CAMPAIGN_ID.slice(0, 14)}…</span>
        </h2>
        <Chip tone="ok" pulse>ACTIVE</Chip>
        <div className="flex gap-1.5 ml-auto">
          <RegChip>{CAMPAIGN_META.target}</RegChip>
          <RegChip>{CAMPAIGN_META.indication}</RegChip>
        </div>
      </div>

      {/* Meta line */}
      <div className="flex items-center gap-2 text-[12.5px] text-muted-foreground flex-wrap mb-4">
        <span>Round {CAMPAIGN_META.round}</span>
        <span className="text-muted-foreground/40">·</span>
        <span>{CAMPAIGN_META.total} compounds ranked</span>
        <span className="text-muted-foreground/40">·</span>
        <span>Last update: {CAMPAIGN_META.updated}</span>
        <div className="flex-1" />
        <button
          className="h-[26px] px-2 text-[12px] font-medium border border-border rounded-[4px] bg-white dark:bg-background hover:bg-muted/50 flex items-center gap-1.5 cursor-pointer"
        >
          <RefreshCw className="h-3 w-3" /> Refresh
        </button>
      </div>

      {/* DMTA Loop Progress */}
      <div className="border border-border rounded-lg bg-muted/20 px-4 pt-3 pb-4 mb-5">
        <div className="text-[11px] uppercase tracking-[0.05em] text-muted-foreground font-semibold mb-3">
          DMTA Loop Progress
        </div>
        <DmtaStepper />
      </div>

      {/* Top Compounds */}
      <div className="flex items-center gap-2 mb-2.5">
        <span className="text-[13.5px] font-semibold">Top Compounds</span>
        <span className="text-xs text-muted-foreground">
          Showing {visible.length} of {DEMO_COMPOUNDS.length}
        </span>
        <div className="flex-1" />
        <button
          className="text-xs text-muted-foreground bg-transparent border-0 border-b border-dotted border-border hover:text-blue-600 cursor-pointer"
          onClick={() => setShowAll(!showAll)}
        >
          {showAll ? "Show top 10" : `See all ${DEMO_COMPOUNDS.length} →`}
        </button>
      </div>

      <div className="border border-border rounded-md overflow-hidden">
        <table className="w-full text-[13px] border-collapse">
          <thead>
            <tr className="border-b border-border bg-muted/30">
              {["#", "COMPOUND ID", "SCORE", "AD STATUS", "ROUND PROPOSED"].map((h, i) => (
                <th key={h} className={cn(
                  "py-2 px-2.5 text-[11px] font-semibold uppercase tracking-[0.05em] text-muted-foreground",
                  i === 0 ? "w-9" : i >= 2 ? "w-36" : "",
                  i === 0 ? "text-left" : "text-left",
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

      <div className="flex gap-2 mt-3.5">
        <button className="h-8 px-3 text-[13px] font-medium border border-border rounded-[6px] bg-white dark:bg-background hover:bg-muted/50 flex items-center gap-1.5 cursor-pointer">
          <Upload className="h-3.5 w-3.5" /> Ingest New Assay Results
        </button>
        <button className="h-8 px-3 text-[13px] font-medium rounded-[6px] bg-foreground text-background hover:bg-foreground/90 flex items-center gap-1.5 border-0 cursor-pointer">
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

function EsigModal({
  action,
  target,
  onClose,
  onSigned,
  onToast,
}: {
  action: EsigAction
  target: string
  onClose: () => void
  onSigned?: () => void
  onToast: (msg: string) => void
}) {
  const [state, setState] = useState<"idle" | "checking" | "error" | "success">("idle")
  const [countdown, setCountdown] = useState(23)
  const [attempts, setAttempts] = useState(0)

  useEffect(() => {
    if (state === "success") return
    const t = setInterval(() => setCountdown(c => c <= 0 ? 30 : c - 1), 1000)
    return () => clearInterval(t)
  }, [state])

  const onComplete = (code: string) => {
    setState("checking")
    setTimeout(() => {
      if (code === "123456" || attempts > 0) {
        setState("success")
        setTimeout(() => {
          onToast(`Signed · ${action} recorded to audit trail`)
          onClose()
          onSigned?.()
        }, 700)
      } else {
        setState("error")
        setAttempts(a => a + 1)
        setTimeout(() => setState("idle"), 1500)
      }
    }, 700)
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
            <div className="flex gap-2 mb-1"><span style={{ color: "oklch(0.48 0.012 260)" }}>Campaign:</span> <span className="font-mono">{CAMPAIGN_ID.slice(0, 14)}…</span></div>
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
          <div className={cn("text-[11.5px] text-center mb-3", state === "error" ? "text-red-600" : "")}>
            {state === "error" ? "Invalid code. Try again." : `Code refreshes in ${countdown}s`}
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

function CampaignWizard({ onDone, onToast }: { onDone: () => void; onToast: (msg: string) => void }) {
  const [step, setStep] = useState(1)
  const [mol, setMol] = useState("")
  const [target, setTarget] = useState("")
  const [indication, setIndication] = useState("")
  const [objective, setObjective] = useState("balance")
  const [parsed, setParsed] = useState<{ n: number; invalid: number } | null>(null)
  const [validationProgress, setValidationProgress] = useState(0)

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
              onClick={() => { onToast("Campaign launched"); onDone() }}
              className="h-8 px-4 text-[13px] font-medium rounded-[6px] cursor-pointer flex items-center gap-1"
              style={{ background: "oklch(0.22 0.01 260)", color: "#ffffff", border: "none" }}
            >
              Launch Campaign <ChevronRight className="h-3.5 w-3.5" />
            </button>
          </div>
        </div>
      )}
    </div>
  )
}

// ── Page ──────────────────────────────────────────────────────────────────────

export default function DrugDiscoveryCroDemo() {
  const [, navigate] = useLocation()
  const [phase, setPhase] = useState<"loading" | "ready" | "error">("loading")
  const [error, setError] = useState("")
  const [activeTab, setActiveTab] = useState<TabKey>("dashboard")
  const [loopRunning] = useState(true)   // matches reference default knobs loopState='running'
  const [showWizard, setShowWizard] = useState(false)
  const [esigOpen, setEsigOpen] = useState(false)
  const [esigAction, setEsigAction] = useState<EsigAction>("EXPORT_CRO_ORDER")
  const [toast, setToast] = useState<string | null>(null)

  useEffect(() => {
    async function setup() {
      const result = await createCampaign()
      if (!result.ok) { setError(result.error ?? "Campaign setup failed"); setPhase("error"); return }
      seedLibrary()   // fire-and-forget
      setPhase("ready")
    }
    setup()
  }, [])

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
            <Button size="sm" variant="outline" className="mt-3" onClick={() => navigate("/home")}>
              Back to BioMate
            </Button>
          </AlertDescription>
        </Alert>
      </div>
    )
  }

  const tabLabel = TABS.find((t) => t.key === activeTab)?.label ?? "Dashboard"

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
            onClick={() => navigate("/")}
            className="text-muted-foreground hover:text-foreground transition-colors bg-transparent border-0 p-0 cursor-pointer text-[13px]"
          >
            Drug Discovery
          </button>
          <ChevronRight className="h-3.5 w-3.5 text-muted-foreground/40 shrink-0" />
          <span>{CAMPAIGN_META.molecule}</span>
          <ChevronRight className="h-3.5 w-3.5 text-muted-foreground/40 shrink-0" />
          <span style={{ color: "oklch(0.22 0.01 260)" }}>{tabLabel}</span>
        </div>

        <div className="flex-1" />

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
              U
            </div>
            <span className="hidden sm:inline">user@biotech.com</span>
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
                {CAMPAIGN_ID.slice(0, 14)}…
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
                    Drug Discovery · {CAMPAIGN_META.molecule}
                  </div>
                  <div
                    className="text-[12px] mt-px"
                    style={{ color: "oklch(0.62 0.010 260)" }}
                  >
                    <span
                      className="font-mono"
                      data-testid="demo-campaign-id"
                      data-campaign-id={CAMPAIGN_ID}
                    >
                      {CAMPAIGN_ID.slice(0, 14)}…
                    </span>
                    {" · "}{CAMPAIGN_META.target}{" · "}{CAMPAIGN_META.indication}
                  </div>
                </div>

                {/* .btn.sm — New campaign */}
                {!showWizard && (
                  <button
                    onClick={() => setShowWizard(true)}
                    className="h-[26px] px-2 text-[12px] font-medium flex items-center gap-1.5 rounded-[4px] cursor-pointer"
                    style={{
                      border: "1px solid oklch(0.915 0.006 240)",
                      background: "#ffffff",
                      color: "oklch(0.22 0.01 260)",
                    }}
                  >
                    <Plus className="h-3 w-3" /> New campaign
                  </button>
                )}

                {/* .btn.sm.ghost — Sign action */}
                <button
                  onClick={() => { setEsigAction("EXPORT_CRO_ORDER"); setEsigOpen(true) }}
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

              {/* .dd-tabs */}
              <div className="flex overflow-x-auto mt-3.5" style={{ scrollbarWidth: "none" }}>
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
              {activeTab === "dashboard"    && <CampaignDashboard />}
              {activeTab === "validation"   && <DrugDiscoveryValidationPanel campaignId={CAMPAIGN_ID} />}
              {activeTab === "audit"        && <DrugDiscoveryAuditViewer campaignId={CAMPAIGN_ID} />}
              {activeTab === "auto-retrain" && <DrugDiscoveryAutoRetrain campaignId={CAMPAIGN_ID} />}
              {activeTab === "ind-assembly" && (
                <DrugDiscoveryIndAssembly
                  campaignId={CAMPAIGN_ID}
                  initialValues={{
                    mol:        CAMPAIGN_META.molecule,
                    target:     CAMPAIGN_META.target,
                    indication: `${CAMPAIGN_META.indication} — 2nd line after erlotinib failure`,
                    sponsor:    CAMPAIGN_META.sponsor,
                  }}
                />
              )}
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
