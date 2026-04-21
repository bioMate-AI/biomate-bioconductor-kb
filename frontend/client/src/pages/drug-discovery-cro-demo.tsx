/**
 * /drug-discovery-cro  — BioMate CRO Compliance Suite standalone page.
 *
 * Visual design follows /reference/claude_design/cro/ exactly:
 *   - Breadcrumb sub-nav: Drug Discovery / ERB-001 / [tab]
 *   - Reg-chips in top-right: 21 CFR Part 11  ICH M4
 *   - Near-black active tab indicator (var(--text) / foreground)
 *   - DMTA stepper on Dashboard tab (Design → Make → Test → Analyse)
 *   - section-hd / meta-line / RegChip / Chip patterns throughout
 *
 * Tabs: Dashboard · Validation · Audit Trail · Auto-Retrain · IND Assembly
 */

import { useState, useEffect, Fragment } from "react"
import { useLocation } from "wouter"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { DrugDiscoveryAuditViewer } from "@/components/drug-discovery-audit-viewer"
import { DrugDiscoveryAutoRetrain } from "@/components/drug-discovery-auto-retrain"
import { DrugDiscoveryValidationPanel } from "@/components/drug-discovery-validation-panel"
import { DrugDiscoveryIndAssembly } from "@/components/drug-discovery-ind-assembly"
import { Button } from "@/components/ui/button"
import { Alert, AlertDescription } from "@/components/ui/alert"
import {
  Loader2, FlaskConical, Check, AlertTriangle,
  ChevronRight, RefreshCw, Upload, ExternalLink,
} from "lucide-react"
import { cn } from "@/lib/utils"

// ── Demo compound library: 5 EGFR inhibitors ────────────────────────────────

const DEMO_COMPOUNDS = [
  { name: "Erlotinib",   rank: 1, score: 0.87, ad: "in_domain",     round: 1, smiles: "C#Cc1cccc(Nc2ncnc3cc(OCCO)c(OCCO)cc23)c1" },
  { name: "Osimertinib", rank: 2, score: 0.82, ad: "in_domain",     round: 1, smiles: "CC(=O)Nc1ccc(Oc2ncnc3cc(NC4CCOCC4)ccc23)cc1" },
  { name: "Afatinib",    rank: 3, score: 0.76, ad: "in_domain",     round: 2, smiles: "C=CC(=O)Nc1ccc(Nc2ncnc3ccc(OC)c(OC)c23)cc1OC" },
  { name: "Gefitinib",   rank: 4, score: 0.71, ad: "in_domain",     round: 1, smiles: "Nc1ccc(F)c(Nc2ncnc3cc4c(cc23)OCCO4)c1" },
  { name: "Lapatinib",   rank: 5, score: 0.54, ad: "out_of_domain", round: 2, smiles: "CS(=O)(=O)CCNCc1ccc(-c2ccc3ncnc(Nc4ccc(OC)c(Cl)c4)c3c2)o1" },
]

const CAMPAIGN_META = {
  molecule:   "ERB-001",
  target:     "EGFR T790M",
  indication: "NSCLC — 2nd line after erlotinib failure",
  sponsor:    "BioMate Technologies",
  objective:  "balance",
  round:      3,
  updated:    "2026-04-21 08:14 UTC",
}

// Stable ID for the demo session (changes each page load intentionally)
const CAMPAIGN_ID = `cmp-demo-egfr-${Math.floor(Date.now() / 1000).toString(16)}`

// ── Setup functions ──────────────────────────────────────────────────────────

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
        virtual_library_smiles: DEMO_COMPOUNDS.map((c) => c.smiles),
      }),
    })
    if (!res.ok && res.status !== 409) {
      const body = await res.json().catch(() => ({}))
      return { ok: false, error: `HTTP ${res.status}: ${(body as any).detail ?? "unknown error"}` }
    }
    return { ok: true }
  } catch (e: any) {
    return { ok: false, error: String(e) }
  }
}

async function seedLibraryAndProposals(): Promise<void> {
  try {
    await fetch(`/api/drug-discovery/${CAMPAIGN_ID}/virtual-library`, {
      method: "POST",
      credentials: "include",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ smiles: DEMO_COMPOUNDS.map((c) => c.smiles), n_propose: 5, diversity_weight: 0.3 }),
    })
  } catch { /* non-blocking */ }
  try {
    await fetch(`/api/drug-discovery/${CAMPAIGN_ID}/retrain/trigger`, {
      method: "POST", credentials: "include",
    })
  } catch { /* non-blocking */ }
}

// ── Atoms matching reference primitives ─────────────────────────────────────

/** RegChip — monospace citation badge from reference tokens-cro.css */
function RegChip({ variant = "default", children }: { variant?: "default" | "indigo"; children: React.ReactNode }) {
  return (
    <span className={cn(
      "inline-flex items-center gap-1 px-1.5 py-0.5 rounded border font-mono text-[10.5px] font-medium whitespace-nowrap",
      variant === "indigo"
        ? "border-indigo-200 bg-indigo-50 text-indigo-700 dark:border-indigo-800 dark:bg-indigo-950/50 dark:text-indigo-300"
        : "border-border bg-white dark:bg-background text-muted-foreground",
    )}>
      {children}
    </span>
  )
}

/** Status chip with optional pulse dot */
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
    ok: "bg-green-500", run: "bg-blue-500", warn: "bg-amber-500", err: "bg-red-500", default: "bg-muted-foreground",
  }[tone]

  return (
    <span className={cn(
      "inline-flex items-center gap-1.5 px-2 py-0.5 rounded-full text-[11.5px] font-medium",
      toneClass,
    )}>
      <span className={cn("w-1.5 h-1.5 rounded-full", dotClass, pulse && "animate-pulse")} />
      {children}
    </span>
  )
}

/** Section header: title + status chip + reg-chips right-aligned */
function SectionHd({
  title,
  mono,
  chip,
  regChips,
}: {
  title: string
  mono?: string
  chip?: React.ReactNode
  regChips?: React.ReactNode
}) {
  return (
    <div className="flex items-center gap-2.5 mb-3.5 flex-wrap" style={{ letterSpacing: "-0.005em" }}>
      <h2 className="text-[14px] font-semibold m-0 leading-none">
        {title}
        {mono && (
          <span className="font-mono font-medium ml-2 text-[13px]">{mono}</span>
        )}
      </h2>
      {chip}
      {regChips && <div className="flex gap-1.5 ml-auto">{regChips}</div>}
    </div>
  )
}

/** Meta line: small dim text row with · separators */
function MetaLine({ items }: { items: (string | React.ReactNode)[] }) {
  return (
    <div className="flex items-center gap-2 text-[12.5px] text-muted-foreground flex-wrap mb-4">
      {items.map((item, i) => (
        <Fragment key={i}>
          {i > 0 && <span className="text-muted-foreground/60">·</span>}
          <span>{item}</span>
        </Fragment>
      ))}
    </div>
  )
}

// ── DMTA Stepper ─────────────────────────────────────────────────────────────

const DMTA_NODES: { key: string; label: string; status: "done" | "active" | "pending" }[] = [
  { key: "design",  label: "Design",  status: "done" },
  { key: "make",    label: "Make",    status: "done" },
  { key: "test",    label: "Test",    status: "active" },
  { key: "analyse", label: "Analyse", status: "pending" },
]

function DmtaStepper() {
  return (
    <div className="flex items-start">
      {DMTA_NODES.map((n, i) => (
        <Fragment key={n.key}>
          {/* Node */}
          <div className="flex flex-col items-center gap-1" style={{ minWidth: 72 }}>
            {/* Dot */}
            <div className={cn(
              "w-7 h-7 rounded-full border-2 flex items-center justify-center shrink-0",
              n.status === "done"    && "bg-foreground border-foreground text-background",
              n.status === "active"  && "bg-blue-50 border-blue-500 text-blue-600 dark:bg-blue-950/30",
              n.status === "pending" && "bg-background border-border text-muted-foreground",
            )}>
              {n.status === "done" && <Check className="h-3.5 w-3.5" />}
              {n.status === "active" && (
                <span className="w-2.5 h-2.5 rounded-full bg-blue-500 animate-pulse" />
              )}
              {n.status === "pending" && (
                <span className="w-2 h-2 rounded-full border-[1.5px] border-current" />
              )}
            </div>
            {/* Label */}
            <span className={cn(
              "text-[12px] font-medium",
              n.status === "done"    && "text-foreground",
              n.status === "active"  && "text-blue-600 dark:text-blue-400",
              n.status === "pending" && "text-muted-foreground",
            )}>
              {n.label}
            </span>
            {/* Sublabel */}
            <span className="text-[10.5px] text-muted-foreground/70">
              {n.status === "done" ? "completed" : n.status === "active" ? "running" : "pending"}
            </span>
          </div>
          {/* Connector line */}
          {i < DMTA_NODES.length - 1 && (
            <div className={cn(
              "flex-1 h-0.5 mt-3.5",
              n.status === "done" ? "bg-foreground/60" : "bg-border",
            )} />
          )}
        </Fragment>
      ))}
    </div>
  )
}

// ── Score bar ────────────────────────────────────────────────────────────────

function ScoreBar({ score }: { score: number }) {
  const pct = Math.round(Math.max(0, Math.min(1, score)) * 100)
  const color = pct >= 70 ? "bg-green-500" : pct >= 40 ? "bg-amber-500" : "bg-red-400"
  return (
    <div className="flex items-center gap-2">
      <div className="flex-1 h-1.5 bg-muted rounded-full overflow-hidden" style={{ minWidth: 80 }}>
        <div className={cn("h-full rounded-full", color)} style={{ width: `${pct}%` }} />
      </div>
      <span className="font-mono text-xs text-muted-foreground w-9 text-right shrink-0">
        {score.toFixed(2)}
      </span>
    </div>
  )
}

// ── Dashboard tab ────────────────────────────────────────────────────────────

function CampaignDashboard() {
  const [showAll, setShowAll] = useState(false)
  const visible = showAll ? DEMO_COMPOUNDS : DEMO_COMPOUNDS.slice(0, 10)

  return (
    <div>
      <SectionHd
        title={`Campaign:`}
        mono={CAMPAIGN_META.molecule}
        chip={<Chip tone="ok" pulse>ACTIVE</Chip>}
        regChips={
          <>
            <RegChip>{CAMPAIGN_META.target}</RegChip>
            <RegChip>NSCLC 2nd-line</RegChip>
          </>
        }
      />

      <MetaLine items={[
        `Round ${CAMPAIGN_META.round}`,
        `${DEMO_COMPOUNDS.length} compounds ranked`,
        `Last update: ${CAMPAIGN_META.updated}`,
        <Button key="refresh" variant="outline" size="sm" className="h-6 text-xs px-2 gap-1 font-normal">
          <RefreshCw className="h-3 w-3" /> Refresh
        </Button>,
      ]} />

      {/* DMTA stepper */}
      <div className="border border-border rounded-lg bg-muted/20 px-4 pt-3 pb-4 mb-5">
        <div className="text-[11px] uppercase tracking-[0.05em] text-muted-foreground font-semibold mb-3">
          DMTA Loop Progress
        </div>
        <DmtaStepper />
      </div>

      {/* Top compounds */}
      <div className="flex items-center gap-2.5 mb-2.5">
        <span className="text-[13.5px] font-semibold">Top Compounds</span>
        <span className="text-xs text-muted-foreground">
          Showing {visible.length} of {DEMO_COMPOUNDS.length}
        </span>
        <div className="flex-1" />
        <button
          className="text-xs text-muted-foreground border-b border-dotted border-border hover:text-blue-600 hover:border-blue-500 bg-transparent border-t-0 border-l-0 border-r-0 cursor-pointer"
          onClick={() => setShowAll(!showAll)}
        >
          {showAll ? "Show top 10" : `See all ${DEMO_COMPOUNDS.length} →`}
        </button>
      </div>

      <div className="border border-border rounded-md overflow-hidden bg-white dark:bg-background">
        <table className="w-full text-[13px] border-collapse">
          <thead>
            <tr className="border-b border-border bg-muted/40">
              <th className="py-2 px-2.5 text-left text-[11px] font-semibold uppercase tracking-[0.05em] text-muted-foreground w-8">#</th>
              <th className="py-2 px-2.5 text-left text-[11px] font-semibold uppercase tracking-[0.05em] text-muted-foreground">Compound ID</th>
              <th className="py-2 px-2.5 text-left text-[11px] font-semibold uppercase tracking-[0.05em] text-muted-foreground" style={{ width: 200 }}>Score</th>
              <th className="py-2 px-2.5 text-left text-[11px] font-semibold uppercase tracking-[0.05em] text-muted-foreground" style={{ width: 130 }}>AD Status</th>
              <th className="py-2 px-2.5 text-left text-[11px] font-semibold uppercase tracking-[0.05em] text-muted-foreground" style={{ width: 130 }}>Round</th>
            </tr>
          </thead>
          <tbody>
            {visible.map((c) => (
              <tr
                key={c.name}
                className={cn(
                  "border-b border-border last:border-0 hover:bg-muted/20 transition-colors",
                  c.ad === "out_of_domain" && "opacity-50",
                )}
              >
                <td className="py-2.5 px-2.5 font-mono text-[12px] text-muted-foreground">{c.rank}</td>
                <td className="py-2.5 px-2.5 font-mono text-[12.5px]">{c.name}</td>
                <td className="py-2.5 px-2.5"><ScoreBar score={c.score} /></td>
                <td className="py-2.5 px-2.5">
                  {c.ad === "in_domain"
                    ? <span className="inline-flex items-center gap-1 text-green-700 dark:text-green-400 text-xs font-medium"><Check className="h-3 w-3" /> in domain</span>
                    : <span className="text-amber-600 dark:text-amber-400 text-xs font-medium">⚠ OOD</span>
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
        <Button variant="outline" size="sm" className="gap-1.5 text-xs h-8">
          <Upload className="h-3.5 w-3.5" /> Ingest New Assay Results
        </Button>
        <Button size="sm" className="gap-1.5 text-xs h-8 bg-foreground text-background hover:bg-foreground/90">
          <ExternalLink className="h-3.5 w-3.5" /> Export CRO Order
        </Button>
      </div>
    </div>
  )
}

// ── Page tabs config ─────────────────────────────────────────────────────────

const TABS = [
  { key: "dashboard",   label: "Dashboard" },
  { key: "validation",  label: "Validation" },
  { key: "audit",       label: "Audit Trail" },
  { key: "auto_retrain",label: "Auto-Retrain" },
  { key: "ind",         label: "IND Assembly" },
] as const

type TabKey = typeof TABS[number]["key"]

// ── Page ─────────────────────────────────────────────────────────────────────

export default function DrugDiscoveryCroDemo() {
  const [, navigate] = useLocation()
  const [phase, setPhase] = useState<"loading" | "ready" | "error">("loading")
  const [error, setError] = useState<string>("")
  const [activeTab, setActiveTab] = useState<TabKey>("dashboard")

  useEffect(() => {
    async function setup() {
      const result = await createCampaign()
      if (!result.ok) {
        setError(result.error ?? "Campaign setup failed")
        setPhase("error")
        return
      }
      seedLibraryAndProposals()   // fire-and-forget
      setPhase("ready")
    }
    setup()
  }, [])

  // ── Loading ────────────────────────────────────────────────────────────────
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

  // ── Error ──────────────────────────────────────────────────────────────────
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

  // ── Ready ──────────────────────────────────────────────────────────────────
  const tabLabel = TABS.find((t) => t.key === activeTab)?.label ?? "Dashboard"

  return (
    <div
      className="flex flex-col bg-background"
      style={{ height: "calc(100vh - 64px)", fontFamily: "'Inter', system-ui, sans-serif", letterSpacing: "-0.005em" }}
    >
      {/* ── Sub-nav: breadcrumb + reg-chips ────────────────────────────────── */}
      <div
        className="shrink-0 border-b bg-white dark:bg-background"
        style={{ height: 52 }}
      >
        <div className="h-full max-w-5xl mx-auto px-5 flex items-center gap-3">
          {/* Brand mark */}
          <button
            onClick={() => navigate("/")}
            className="w-7 h-7 rounded-[7px] bg-foreground text-background grid place-items-center font-mono text-[13px] font-bold shrink-0 hover:bg-foreground/90 transition-colors border-0 cursor-pointer"
            aria-label="Back to BioMate"
            data-testid="cro-demo-back-btn"
          >
            B
          </button>

          {/* Breadcrumb */}
          <div className="flex items-center gap-1.5 text-[13px] text-muted-foreground">
            <button
              onClick={() => navigate("/")}
              className="text-muted-foreground hover:text-foreground transition-colors bg-transparent border-0 p-0 cursor-pointer text-[13px]"
            >
              Drug Discovery
            </button>
            <ChevronRight className="h-3.5 w-3.5 text-muted-foreground/50 shrink-0" />
            <span className="text-muted-foreground">{CAMPAIGN_META.molecule}</span>
            <ChevronRight className="h-3.5 w-3.5 text-muted-foreground/50 shrink-0" />
            <span className="text-foreground font-medium">{tabLabel}</span>
          </div>

          <div className="flex-1" />

          {/* Campaign ID + Reg chips */}
          <div className="flex items-center gap-2">
            <span
              className="font-mono text-[11px] text-muted-foreground"
              data-testid="demo-campaign-id"
              data-campaign-id={CAMPAIGN_ID}
            >
              {CAMPAIGN_ID.slice(0, 24)}…
            </span>
            <RegChip variant="indigo">21 CFR Part 11</RegChip>
            <RegChip>ICH M4</RegChip>
          </div>
        </div>
      </div>

      {/* ── Scrollable content ─────────────────────────────────────────────── */}
      <div className="flex-1 overflow-y-auto">
        <div className="max-w-5xl mx-auto px-5 py-5">

          {/* ── Tabs ─────────────────────────────────────────────────────────── */}
          <Tabs
            value={activeTab}
            onValueChange={(v) => setActiveTab(v as TabKey)}
            className="space-y-5"
          >
            {/* Tab bar — near-black active indicator matching reference .dd-tab.active */}
            <div className="border-b border-border">
              <TabsList className="h-auto bg-transparent p-0 rounded-none w-full justify-start gap-0">
                {TABS.map((tab) => (
                  <TabsTrigger
                    key={tab.key}
                    value={tab.key}
                    className={cn(
                      "rounded-none border-b-2 border-transparent px-3.5 py-2.5",
                      "text-[13px] font-medium text-muted-foreground",
                      "hover:text-foreground transition-colors",
                      "data-[state=active]:border-foreground data-[state=active]:text-foreground",
                      "data-[state=active]:bg-transparent data-[state=active]:shadow-none",
                      "-mb-px",
                    )}
                  >
                    {tab.label}
                  </TabsTrigger>
                ))}
              </TabsList>
            </div>

            {/* Dashboard */}
            <TabsContent value="dashboard" className="mt-0 focus-visible:ring-0 focus-visible:outline-none">
              <CampaignDashboard />
            </TabsContent>

            {/* Validation */}
            <TabsContent value="validation" className="mt-0 focus-visible:ring-0 focus-visible:outline-none">
              <DrugDiscoveryValidationPanel campaignId={CAMPAIGN_ID} />
            </TabsContent>

            {/* Audit Trail */}
            <TabsContent value="audit" className="mt-0 focus-visible:ring-0 focus-visible:outline-none">
              <DrugDiscoveryAuditViewer campaignId={CAMPAIGN_ID} />
            </TabsContent>

            {/* Auto-Retrain */}
            <TabsContent value="auto_retrain" className="mt-0 focus-visible:ring-0 focus-visible:outline-none">
              <DrugDiscoveryAutoRetrain campaignId={CAMPAIGN_ID} />
            </TabsContent>

            {/* IND Assembly — pre-filled from campaign metadata */}
            <TabsContent value="ind" className="mt-0 focus-visible:ring-0 focus-visible:outline-none">
              <DrugDiscoveryIndAssembly
                campaignId={CAMPAIGN_ID}
                initialValues={{
                  mol:        CAMPAIGN_META.molecule,
                  target:     CAMPAIGN_META.target,
                  indication: CAMPAIGN_META.indication,
                  sponsor:    CAMPAIGN_META.sponsor,
                }}
              />
            </TabsContent>
          </Tabs>
        </div>
      </div>
    </div>
  )
}
