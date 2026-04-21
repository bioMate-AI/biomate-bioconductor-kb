/**
 * /drug-discovery-cro  — BioMate CRO Compliance Suite standalone page.
 *
 * Creates a real demo campaign on mount, seeds the virtual library,
 * and triggers an initial Bayesian retrain so every tab has live content.
 *
 * Tabs:
 *   Overview     — campaign summary + EGFR inhibitor scaffold table
 *   Validation   — PBPK qualification report (EMA 2-fold criterion)
 *   Audit Trail  — 21 CFR Part 11 SHA-256 hash-chain log
 *   Auto-Retrain — DMTA Bayesian-optimizer loop + proposals
 *   IND Assembly — ICH M4 CTD §2.6.1 Nonclinical Overview generation
 */

import { useState, useEffect } from "react"
import { useLocation } from "wouter"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { DrugDiscoveryAuditViewer } from "@/components/drug-discovery-audit-viewer"
import { DrugDiscoveryAutoRetrain } from "@/components/drug-discovery-auto-retrain"
import { DrugDiscoveryValidationPanel } from "@/components/drug-discovery-validation-panel"
import { DrugDiscoveryIndAssembly } from "@/components/drug-discovery-ind-assembly"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Separator } from "@/components/ui/separator"
import {
  Loader2, FlaskConical, ArrowLeft, Target, Shield,
  BarChart3, FileText, RefreshCw, Library, CheckCircle2,
  Beaker, AlertTriangle, Dna, Layers,
} from "lucide-react"
import { cn } from "@/lib/utils"

// ── Demo compound library: 5 EGFR inhibitors ──────────────────────────────────

const DEMO_COMPOUNDS = [
  { name: "Erlotinib",   generation: "1st-gen TKI",  mw: 393.4, hba: 6,  psa: 74.4, smiles: "C#Cc1cccc(Nc2ncnc3cc(OCCO)c(OCCO)cc23)c1" },
  { name: "Gefitinib",   generation: "1st-gen TKI",  mw: 446.9, hba: 6,  psa: 68.7, smiles: "Nc1ccc(F)c(Nc2ncnc3cc4c(cc23)OCCO4)c1" },
  { name: "Osimertinib", generation: "3rd-gen TKI",  mw: 499.6, hba: 6,  psa: 100.0, smiles: "CC(=O)Nc1ccc(Oc2ncnc3cc(NC4CCOCC4)ccc23)cc1" },
  { name: "Afatinib",    generation: "2nd-gen TKI",  mw: 485.9, hba: 7,  psa: 78.5, smiles: "C=CC(=O)Nc1ccc(Nc2ncnc3ccc(OC)c(OC)c23)cc1OC" },
  { name: "Lapatinib",   generation: "Dual EGFR/HER2", mw: 581.1, hba: 8, psa: 112.5, smiles: "CS(=O)(=O)CCNCc1ccc(-c2ccc3ncnc(Nc4ccc(OC)c(Cl)c4)c3c2)o1" },
]

const CAMPAIGN_META = {
  molecule:    "ERB-001",
  target:      "EGFR T790M",
  indication:  "NSCLC — 2nd line after erlotinib failure",
  sponsor:     "BioMate Technologies",
  objective:   "balance",
}

const CAMPAIGN_ID = `cmp-demo-egfr-${Math.floor(Date.now() / 1000).toString(16)}`

// ── Setup functions ────────────────────────────────────────────────────────────

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
      return { ok: false, error: `HTTP ${res.status}: ${body.detail ?? "unknown error"}` }
    }
    return { ok: true }
  } catch (e: any) {
    return { ok: false, error: String(e) }
  }
}

/** Seed virtual library + trigger initial proposal so Auto-Retrain tab has content. */
async function seedLibraryAndProposals(): Promise<void> {
  // POST the demo SMILES as the virtual library
  try {
    await fetch(`/api/drug-discovery/${CAMPAIGN_ID}/virtual-library`, {
      method: "POST",
      credentials: "include",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        smiles: DEMO_COMPOUNDS.map((c) => c.smiles),
        n_propose: 5,
        diversity_weight: 0.3,
      }),
    })
  } catch { /* non-blocking */ }

  // Trigger an initial Bayesian retrain so proposals are visible immediately
  try {
    await fetch(`/api/drug-discovery/${CAMPAIGN_ID}/retrain/trigger`, {
      method: "POST",
      credentials: "include",
    })
  } catch { /* non-blocking */ }
}

// ── Overview tab: compound scaffold table ─────────────────────────────────────

function CompoundOverview() {
  return (
    <div className="space-y-6">
      {/* Campaign summary */}
      <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
        {[
          { label: "Molecule",    value: CAMPAIGN_META.molecule,    icon: <FlaskConical className="h-4 w-4 text-blue-600" /> },
          { label: "Target",      value: CAMPAIGN_META.target,       icon: <Target        className="h-4 w-4 text-violet-600" /> },
          { label: "Indication",  value: "NSCLC 2nd-line",           icon: <Dna           className="h-4 w-4 text-rose-600" /> },
          { label: "Scaffolds",   value: "5 EGFR inhibitors",        icon: <Library       className="h-4 w-4 text-emerald-600" /> },
        ].map(({ label, value, icon }) => (
          <Card key={label} className="border shadow-none">
            <CardContent className="pt-4 pb-3 px-4">
              <div className="flex items-center gap-2 mb-1.5">
                {icon}
                <span className="text-xs font-medium text-muted-foreground uppercase tracking-wide">
                  {label}
                </span>
              </div>
              <p className="text-sm font-semibold leading-tight">{value}</p>
            </CardContent>
          </Card>
        ))}
      </div>

      {/* Regulatory frameworks */}
      <div className="flex items-center gap-2 flex-wrap">
        <span className="text-xs font-medium text-muted-foreground">Regulatory frameworks:</span>
        {[
          "21 CFR Part 11 — Electronic Records",
          "EMA/CHMP/EWP/37498/2011 — PBPK Qualification",
          "ICH M4 — CTD §2.6.1 Nonclinical Overview",
        ].map((f) => (
          <Badge key={f} variant="outline" className="text-xs font-mono">
            {f}
          </Badge>
        ))}
      </div>

      <Separator />

      {/* Compound scaffold table */}
      <div>
        <h3 className="text-sm font-semibold mb-3">Virtual Library — EGFR Inhibitor Scaffolds</h3>
        <div className="rounded-lg border overflow-hidden">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b bg-muted/40">
                <th className="py-2.5 px-4 text-left text-xs font-semibold text-muted-foreground">#</th>
                <th className="py-2.5 px-4 text-left text-xs font-semibold text-muted-foreground">Compound</th>
                <th className="py-2.5 px-4 text-left text-xs font-semibold text-muted-foreground">Generation</th>
                <th className="py-2.5 px-4 text-right text-xs font-semibold text-muted-foreground">MW (g/mol)</th>
                <th className="py-2.5 px-4 text-right text-xs font-semibold text-muted-foreground">HBA</th>
                <th className="py-2.5 px-4 text-right text-xs font-semibold text-muted-foreground">PSA (Å²)</th>
                <th className="py-2.5 px-4 text-left text-xs font-semibold text-muted-foreground">Status</th>
              </tr>
            </thead>
            <tbody className="divide-y">
              {DEMO_COMPOUNDS.map((c, i) => (
                <tr key={c.name} className="hover:bg-muted/20 transition-colors">
                  <td className="py-2.5 px-4 text-xs text-muted-foreground font-mono">{i + 1}</td>
                  <td className="py-2.5 px-4">
                    <span className="text-sm font-medium">{c.name}</span>
                  </td>
                  <td className="py-2.5 px-4">
                    <Badge variant="secondary" className="text-xs font-normal">
                      {c.generation}
                    </Badge>
                  </td>
                  <td className="py-2.5 px-4 text-right font-mono text-xs">{c.mw}</td>
                  <td className="py-2.5 px-4 text-right font-mono text-xs">{c.hba}</td>
                  <td className="py-2.5 px-4 text-right font-mono text-xs">{c.psa}</td>
                  <td className="py-2.5 px-4">
                    <div className="flex items-center gap-1.5 text-xs text-emerald-700 dark:text-emerald-400">
                      <CheckCircle2 className="h-3.5 w-3.5 shrink-0" />
                      In library
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <p className="text-xs text-muted-foreground mt-2">
          SMILES loaded into Bayesian virtual library. Run the Auto-Retrain loop to score and rank them.
        </p>
      </div>
    </div>
  )
}

// ── Page ──────────────────────────────────────────────────────────────────────

const TABS = [
  { key: "overview",     label: "Overview",      icon: <Layers     className="h-4 w-4" /> },
  { key: "validation",   label: "Validation",    icon: <Beaker     className="h-4 w-4" /> },
  { key: "audit",        label: "Audit Trail",   icon: <Shield     className="h-4 w-4" /> },
  { key: "auto_retrain", label: "Auto-Retrain",  icon: <RefreshCw  className="h-4 w-4" /> },
  { key: "ind",          label: "IND Assembly",  icon: <FileText   className="h-4 w-4" /> },
] as const

export default function DrugDiscoveryCroDemo() {
  const [, navigate] = useLocation()
  const [phase, setPhase] = useState<"loading" | "seeding" | "ready" | "error">("loading")
  const [error, setError] = useState<string>("")

  useEffect(() => {
    async function setup() {
      // Step 1: create campaign
      const result = await createCampaign()
      if (!result.ok) {
        setError(result.error ?? "Campaign setup failed")
        setPhase("error")
        return
      }

      setPhase("seeding")

      // Step 2: seed library + initial proposals (non-blocking, fire and forget)
      // Don't await — let tabs render and load independently
      seedLibraryAndProposals()

      setPhase("ready")
    }
    setup()
  }, [])

  // ── Loading ──────────────────────────────────────────────────────────────────
  if (phase === "loading" || phase === "seeding") {
    return (
      <div className="flex items-center justify-center" style={{ height: "calc(100vh - 64px)" }}>
        <div className="flex flex-col items-center gap-4 text-muted-foreground">
          <Loader2 className="h-8 w-8 animate-spin" />
          <p className="text-sm">
            {phase === "loading" ? "Setting up demo campaign…" : "Seeding compound library…"}
          </p>
        </div>
      </div>
    )
  }

  // ── Error ────────────────────────────────────────────────────────────────────
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

  // ── Ready ────────────────────────────────────────────────────────────────────
  return (
    <div className="flex flex-col bg-background" style={{ height: "calc(100vh - 64px)" }}>

      {/* ── Page header ──────────────────────────────────────────────────────── */}
      <div className="shrink-0 border-b bg-background/95 backdrop-blur supports-[backdrop-filter]:bg-background/60">
        <div className="max-w-6xl mx-auto px-6 py-4 flex items-center gap-4">
          <Button
            variant="ghost"
            size="sm"
            onClick={() => navigate("/")}
            className="gap-1.5 text-muted-foreground hover:text-foreground"
            data-testid="cro-demo-back-btn"
          >
            <ArrowLeft className="h-4 w-4" />
            BioMate
          </Button>

          <Separator orientation="vertical" className="h-5" />

          <div className="flex items-center gap-2.5">
            <div className="h-8 w-8 rounded-lg bg-blue-600 flex items-center justify-center shrink-0">
              <FlaskConical className="h-4 w-4 text-white" />
            </div>
            <div>
              <h1 className="text-sm font-semibold leading-none">Drug Discovery CRO Suite</h1>
              <p className="text-xs text-muted-foreground mt-0.5">Regulatory-grade computational drug discovery</p>
            </div>
          </div>

          <div className="ml-auto flex items-center gap-2">
            <Badge
              variant="outline"
              className="font-mono text-xs"
              data-testid="demo-campaign-id"
              data-campaign-id={CAMPAIGN_ID}
            >
              {CAMPAIGN_ID}
            </Badge>
            <Badge className="bg-emerald-600 hover:bg-emerald-600 text-white text-xs gap-1">
              <span className="h-1.5 w-1.5 rounded-full bg-white inline-block animate-pulse" />
              LIVE
            </Badge>
          </div>
        </div>
      </div>

      {/* ── Scrollable content ───────────────────────────────────────────────── */}
      <div className="flex-1 overflow-y-auto">
        <div className="max-w-6xl mx-auto px-6 py-6">

          {/* Campaign context strip */}
          <div className="flex items-center gap-2 flex-wrap mb-6 p-3 rounded-lg bg-blue-50 dark:bg-blue-950/30 border border-blue-100 dark:border-blue-900">
            <FlaskConical className="h-3.5 w-3.5 text-blue-600 shrink-0" />
            <span className="text-xs text-blue-800 dark:text-blue-300">
              <strong>Campaign:</strong> {CAMPAIGN_META.molecule} &nbsp;·&nbsp;
              <strong>Target:</strong> {CAMPAIGN_META.target} &nbsp;·&nbsp;
              <strong>Indication:</strong> {CAMPAIGN_META.indication}
            </span>
          </div>

          {/* ── Main tabs ────────────────────────────────────────────────────── */}
          <Tabs defaultValue="overview" className="space-y-6">
            <TabsList className="h-auto bg-transparent border-b rounded-none p-0 w-full justify-start gap-0">
              {TABS.map((tab) => (
                <TabsTrigger
                  key={tab.key}
                  value={tab.key}
                  className={cn(
                    "rounded-none border-b-2 border-transparent px-4 py-2.5 text-sm font-medium gap-2",
                    "text-muted-foreground hover:text-foreground transition-colors",
                    "data-[state=active]:border-blue-600 data-[state=active]:text-blue-700",
                    "dark:data-[state=active]:border-blue-400 dark:data-[state=active]:text-blue-400",
                    "data-[state=active]:bg-transparent data-[state=active]:shadow-none",
                    "-mb-px",
                  )}
                >
                  {tab.icon}
                  {tab.label}
                </TabsTrigger>
              ))}
            </TabsList>

            {/* Overview */}
            <TabsContent value="overview" className="mt-0 pt-2 focus-visible:ring-0 focus-visible:outline-none">
              <CompoundOverview />
            </TabsContent>

            {/* Validation */}
            <TabsContent value="validation" className="mt-0 pt-2 focus-visible:ring-0 focus-visible:outline-none">
              <DrugDiscoveryValidationPanel campaignId={CAMPAIGN_ID} />
            </TabsContent>

            {/* Audit Trail */}
            <TabsContent value="audit" className="mt-0 pt-2 focus-visible:ring-0 focus-visible:outline-none">
              <DrugDiscoveryAuditViewer campaignId={CAMPAIGN_ID} />
            </TabsContent>

            {/* Auto-Retrain */}
            <TabsContent value="auto_retrain" className="mt-0 pt-2 focus-visible:ring-0 focus-visible:outline-none">
              <DrugDiscoveryAutoRetrain campaignId={CAMPAIGN_ID} />
            </TabsContent>

            {/* IND Assembly — pre-filled from campaign metadata */}
            <TabsContent value="ind" className="mt-0 pt-2 focus-visible:ring-0 focus-visible:outline-none">
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
