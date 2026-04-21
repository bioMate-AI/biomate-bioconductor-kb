/**
 * /drug-discovery-cro  — standalone demo page for the CRO compliance surfaces.
 *
 * Accessible after login.  Creates a real campaign via the API on mount, then
 * renders DrugDiscoveryAction in tabbed mode so every surface is reachable.
 *
 * Query params:
 *   ?cid=<campaign_id>   — re-attach to an existing campaign (skip creation)
 *   ?tab=<mode>          — open directly on a specific tab
 */

import { useState, useEffect } from "react"
import { useLocation } from "wouter"
import { DrugDiscoveryAction } from "@/components/drug-discovery-action"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Loader2, FlaskConical, ArrowLeft } from "lucide-react"

// ── Demo compound library: 5 EGFR inhibitors ──────────────────────────────────
const DEMO_SMILES = [
  "C#Cc1cccc(Nc2ncnc3cc(OCCO)c(OCCO)cc23)c1",           // erlotinib
  "Nc1ccc(F)c(Nc2ncnc3cc4c(cc23)OCCO4)c1",               // gefitinib
  "CC(=O)Nc1ccc(Oc2ncnc3cc(NC4CCOCC4)ccc23)cc1",         // osimertinib core
  "C=CC(=O)Nc1ccc(Nc2ncnc3ccc(OC)c(OC)c23)cc1OC",        // afatinib core
  "CS(=O)(=O)CCNCc1ccc(-c2ccc3ncnc(Nc4ccc(OC)c(Cl)c4)c3c2)o1", // lapatinib
]

const CAMPAIGN_ID = `cmp-demo-egfr-${Math.floor(Date.now() / 1000).toString(16)}`

async function setupCampaign(): Promise<{ ok: boolean; error?: string }> {
  try {
    const res = await fetch("/api/drug-discovery/campaigns", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      credentials: "include",
      body: JSON.stringify({
        campaign_id:            CAMPAIGN_ID,
        molecule_name:          "ERB-001",
        target:                 "EGFR T790M",
        indication:             "NSCLC — 2nd line after erlotinib failure",
        objective:              "balance",
        virtual_library_smiles: DEMO_SMILES,
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

export default function DrugDiscoveryCroDemo() {
  const [, navigate] = useLocation()
  const [phase, setPhase] = useState<"loading" | "ready" | "error">("loading")
  const [error, setError] = useState<string>("")

  useEffect(() => {
    setupCampaign().then(({ ok, error }) => {
      if (ok) {
        setPhase("ready")
      } else {
        setError(error ?? "Campaign setup failed")
        setPhase("error")
      }
    })
  }, [])

  if (phase === "loading") {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <div className="flex flex-col items-center gap-4 text-muted-foreground">
          <Loader2 className="h-8 w-8 animate-spin" />
          <p className="text-sm">Setting up demo campaign…</p>
        </div>
      </div>
    )
  }

  if (phase === "error") {
    return (
      <div className="flex items-center justify-center min-h-screen p-8">
        <Alert variant="destructive" className="max-w-md">
          <AlertDescription>
            <strong>Setup failed:</strong> {error}
            <br />
            <Button
              size="sm"
              variant="outline"
              className="mt-3"
              onClick={() => navigate("/home")}
            >
              Back to BioMate
            </Button>
          </AlertDescription>
        </Alert>
      </div>
    )
  }

  return (
    <div className="min-h-screen bg-background">
      {/* Header bar */}
      <div className="sticky top-0 z-10 border-b bg-background/95 backdrop-blur">
        <div className="max-w-5xl mx-auto px-4 py-3 flex items-center justify-between">
          <div className="flex items-center gap-3">
            <Button
              variant="ghost"
              size="sm"
              onClick={() => navigate("/home")}
              data-testid="cro-demo-back-btn"
            >
              <ArrowLeft className="h-4 w-4 mr-1" />
              BioMate
            </Button>
            <div className="flex items-center gap-2 text-sm font-medium">
              <FlaskConical className="h-4 w-4 text-blue-600" />
              Drug Discovery — CRO Compliance Demo
            </div>
          </div>
          <div className="flex items-center gap-2">
            <Badge
              variant="secondary"
              className="font-mono text-xs"
              data-testid="demo-campaign-id"
              data-campaign-id={CAMPAIGN_ID}
            >
              {CAMPAIGN_ID}
            </Badge>
            <Badge className="bg-green-600 text-white text-xs">LIVE</Badge>
          </div>
        </div>
      </div>

      {/* Context banner */}
      <div className="bg-blue-50 dark:bg-blue-950/30 border-b border-blue-100 dark:border-blue-900">
        <div className="max-w-5xl mx-auto px-4 py-2 text-xs text-blue-700 dark:text-blue-300">
          <strong>Campaign:</strong> ERB-001 · EGFR T790M · NSCLC 2nd-line ·
          5 EGFR inhibitor scaffolds loaded (erlotinib, gefitinib, osimertinib, afatinib, lapatinib analogs)
        </div>
      </div>

      {/* Main widget — full tabbed CRO view */}
      <div className="max-w-5xl mx-auto px-4 py-6">
        <DrugDiscoveryAction
          action={{
            type: "validation",
            campaign_id: CAMPAIGN_ID,
            initial_mode: "validation",
          }}
          data-testid="cro-demo-action"
        />
      </div>
    </div>
  )
}
