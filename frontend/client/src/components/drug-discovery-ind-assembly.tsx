/**
 * Surface 6 — IND Section Assembly
 *
 * POST /api/drug-discovery/{campaign_id}/ind-assembly
 * Body: { molecule_name, sponsor, indication, target_name }
 * Returns:
 *   { campaign_id, sections, pandoc_available, docx_generated,
 *     generated_at, warnings, markdown_preview,
 *     markdown_path, docx_path }
 *
 * Regulatory reference: ICH M4 CTD §2.6.1 — Nonclinical Overview Pharmacology
 */
import { useState } from "react"
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
  AlertTriangle,
  ChevronDown,
  Download,
  FileText,
  Loader2,
  RefreshCw,
  Shield,
} from "lucide-react"
import { useToast } from "@/hooks/use-toast"
import { cn } from "@/lib/utils"

// ─────────────────────────────────────────────────────────────────────────────
// Types
// ─────────────────────────────────────────────────────────────────────────────

interface AssemblyResult {
  campaign_id: string
  sections: string[]          // e.g. ["2.6.1.1", "2.6.1.2", ...]
  pandoc_available: boolean
  docx_generated: boolean
  generated_at: string
  warnings: string[]
  markdown_preview: string    // first 2000 chars (for display)
  markdown_content: string    // full markdown (for download)
  markdown_path: string
  docx_path: string | null
}

// BioMate IND section titles (ICH M4 CTD §2.6.1–2.6.3 computational-CRO variant)
const SECTION_TITLES: Record<string, string> = {
  "2.6.1.1": "Overview of Computational Methods",
  "2.6.1.2": "PBPK Model Qualification",
  "2.6.1.3": "ADMET Screening Results",
  "2.6.1.4": "Compound Prioritization and Lead Candidate Selection",
  "2.6.1.5": "Applicability Domain Assessment",
  "2.6.1.6": "Audit Trail and Regulatory Traceability",
  "2.6.2":   "Nonclinical Overview: Pharmacokinetics",
  "2.6.3":   "Nonclinical Overview: Toxicology",
}

// ─────────────────────────────────────────────────────────────────────────────
// Main component
// ─────────────────────────────────────────────────────────────────────────────

interface PkSummary {
  status: string
  fu_plasma?: number | null
  vd_lkg?: number | null
  cl_hepatic_fraction?: number | null
  cl_renal_fraction?: number | null
  logP?: number | null
  mw_Da?: number | null
  estimation_method?: string
  per_compound?: Array<{
    compound_id: string
    fu_plasma_predicted?: number
    vd_lkg_estimated?: number
    cl_renal_fraction_estimated?: number
    logP?: number
    mw_Da?: number
  }>
}

interface InitialValues {
  mol?: string
  target?: string
  indication?: string
  sponsor?: string
}

export function DrugDiscoveryIndAssembly({
  campaignId,
  initialValues,
  onRequestSign,
}: {
  campaignId: string
  initialValues?: InitialValues
  onRequestSign?: () => void
}) {
  const { toast } = useToast()

  // Form state — pre-filled from initialValues when provided
  const [mol, setMol] = useState(initialValues?.mol ?? "")
  const [target, setTarget] = useState(initialValues?.target ?? "")
  const [indication, setIndication] = useState(initialValues?.indication ?? "")
  const [sponsor, setSponsor] = useState(initialValues?.sponsor ?? "")

  // Request state
  const [generating, setGenerating] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [result, setResult] = useState<AssemblyResult | null>(null)

  // PK summary from ADMET workflow
  const [pkSummary, setPkSummary] = useState<PkSummary | null>(null)
  const [pkLoading, setPkLoading] = useState(false)

  // Confirm overwrite
  const [confirming, setConfirming] = useState(false)

  // Collapsibles
  const [detailsOpen, setDetailsOpen] = useState(true)
  const [contentsOpen, setContentsOpen] = useState(true)
  const [previewOpen, setPreviewOpen] = useState(false)

  const canGenerate = mol.trim() && target.trim() && indication.trim() && !generating

  // Load pk_summary from campaign DB on mount
  const loadPkSummary = async () => {
    setPkLoading(true)
    try {
      const res = await fetch(`/api/drug-discovery/${campaignId}/pk-summary`, { credentials: "include" })
      if (res.ok) {
        const data: PkSummary = await res.json()
        setPkSummary(data)
      }
    } catch { /* not available */ } finally {
      setPkLoading(false)
    }
  }

  // Load on mount
  useState(() => { loadPkSummary() })

  const generate = async () => {
    setGenerating(true)
    setError(null)
    setConfirming(false)
    try {
      const body: Record<string, unknown> = {
        molecule_name: mol.trim(),
        target_name: target.trim(),
        indication: indication.trim(),
        sponsor: sponsor.trim() || "BioMate Technologies",
      }
      if (pkSummary) body.pk_summary = pkSummary

      const res = await fetch(`/api/drug-discovery/${campaignId}/ind-assembly`, {
        method: "POST",
        credentials: "include",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      })
      if (!res.ok) {
        const err = await res.json().catch(() => ({ detail: res.statusText }))
        throw new Error(err.detail || `HTTP ${res.status}`)
      }
      const data: AssemblyResult = await res.json()
      setResult(data)
      toast({
        title: "IND package generated",
        description: `${data.sections.length} sections · ${data.pandoc_available ? "MD + DOCX" : "MD only"}`,
      })
    } catch (e: any) {
      setError(e.message)
      toast({ title: "Generation failed", description: e.message, variant: "destructive" })
    } finally {
      setGenerating(false)
    }
  }

  const downloadMarkdown = () => {
    if (!result) return
    // Use full markdown_content if available, fall back to markdown_preview
    const content = result.markdown_content || result.markdown_preview
    const blob = new Blob([content], { type: "text/markdown" })
    const url = URL.createObjectURL(blob)
    const a = document.createElement("a")
    a.href = url
    a.download = `${campaignId}_CTD_Module2.6.md`
    a.click()
    URL.revokeObjectURL(url)

  }

  const downloadDocx = async () => {
    if (!result?.docx_generated) return
    const res = await fetch(
      `/api/drug-discovery/${campaignId}/ind-assembly/download?format=docx`,
      { credentials: "include" }
    )
    if (!res.ok) {
      toast({ title: "DOCX download failed", description: `HTTP ${res.status}`, variant: "destructive" })
      return
    }
    const blob = await res.blob()
    const url = URL.createObjectURL(blob)
    const a = document.createElement("a")
    a.href = url
    a.download = `${campaignId}_CTD_Module2.6.docx`
    a.click()
    URL.revokeObjectURL(url)
  }

  return (
    <div className="space-y-4">
      {/* Header */}
      <div>
        <h3 className="text-sm font-semibold">IND Section Assembly</h3>
        <div className="flex flex-wrap gap-1.5 mt-1">
          <Badge variant="outline" className="font-mono text-xs text-indigo-700 dark:text-indigo-400 border-indigo-300">
            ICH M4 — CTD §2.6.1–§2.6.3
          </Badge>
          <Badge variant="outline" className="font-mono text-xs">
            Pharmacology · Pharmacokinetics · Toxicology
          </Badge>
        </div>
      </div>

      {/* Campaign Details form */}
      <Collapsible open={detailsOpen} onOpenChange={setDetailsOpen}>
        <CollapsibleTrigger className="flex w-full items-center justify-between rounded-md border px-3 py-2 text-xs font-medium hover:bg-muted/50 transition-colors">
          <div className="flex items-center gap-2">
            <span>Campaign Details</span>
            <span className="text-muted-foreground font-normal">required</span>
          </div>
          <ChevronDown className={cn("h-3.5 w-3.5 text-muted-foreground transition-transform", detailsOpen && "rotate-180")} />
        </CollapsibleTrigger>
        <CollapsibleContent>
          <div className="mt-2 grid grid-cols-2 gap-3">
            <div className="space-y-1">
              <label className="text-xs font-medium text-muted-foreground">Investigational compound</label>
              <input
                className="w-full text-xs border rounded-md px-2 py-1.5 bg-background"
                placeholder="e.g. BMT-4451"
                value={mol}
                onChange={(e) => setMol(e.target.value)}
                data-testid="ind-mol-input"
              />
            </div>
            <div className="space-y-1">
              <label className="text-xs font-medium text-muted-foreground">Biological target</label>
              <input
                className="w-full text-xs border rounded-md px-2 py-1.5 bg-background"
                placeholder="e.g. EGFR L858R"
                value={target}
                onChange={(e) => setTarget(e.target.value)}
                data-testid="ind-target-input"
              />
            </div>
            <div className="space-y-1">
              <label className="text-xs font-medium text-muted-foreground">Therapeutic indication</label>
              <input
                className="w-full text-xs border rounded-md px-2 py-1.5 bg-background"
                placeholder="e.g. NSCLC — 2nd line"
                value={indication}
                onChange={(e) => setIndication(e.target.value)}
                data-testid="ind-indication-input"
              />
            </div>
            <div className="space-y-1">
              <label className="text-xs font-medium text-muted-foreground">Sponsor organization</label>
              <input
                className="w-full text-xs border rounded-md px-2 py-1.5 bg-background"
                placeholder="BioMate Technologies"
                value={sponsor}
                onChange={(e) => setSponsor(e.target.value)}
                data-testid="ind-sponsor-input"
              />
            </div>
          </div>
        </CollapsibleContent>
      </Collapsible>

      {/* Contents preview */}
      <Collapsible open={contentsOpen} onOpenChange={setContentsOpen}>
        <CollapsibleTrigger className="flex w-full items-center justify-between rounded-md border px-3 py-2 text-xs font-medium hover:bg-muted/50 transition-colors">
          <div className="flex items-center gap-2">
            <span>Contents Preview</span>
            <span className="text-muted-foreground font-normal">{Object.keys(SECTION_TITLES).length} sections · §2.6.1–§2.6.3</span>
          </div>
          <ChevronDown className={cn("h-3.5 w-3.5 text-muted-foreground transition-transform", contentsOpen && "rotate-180")} />
        </CollapsibleTrigger>
        <CollapsibleContent>
          <div className="mt-2 space-y-1">
            {Object.entries(SECTION_TITLES).map(([id, title]) => {
              const included = !result || result.sections.includes(id)
              return (
                <div key={id} className="flex items-center gap-2 py-1 px-2 rounded text-xs hover:bg-muted/20">
                  <CheckCircle2 className={cn(
                    "h-3.5 w-3.5 shrink-0",
                    included ? "text-green-600 dark:text-green-400" : "text-muted-foreground/40"
                  )} />
                  <span className="font-mono text-muted-foreground w-14">{id}</span>
                  <span className="font-medium">{title}</span>
                </div>
              )
            })}
          </div>
        </CollapsibleContent>
      </Collapsible>

      {/* PK Summary link status */}
      <div className="flex items-center gap-2 rounded-md border px-3 py-2 text-xs">
        <Badge
          variant="outline"
          className={cn(
            "font-mono text-xs shrink-0",
            pkSummary
              ? "text-green-700 dark:text-green-400 border-green-300"
              : "text-muted-foreground"
          )}
        >
          DMPK
        </Badge>
        <span className="flex-1 text-muted-foreground">
          {pkLoading ? "Loading ADMET predictions…" :
           pkSummary
             ? `PK data linked — f_u=${pkSummary.fu_plasma?.toFixed(2) ?? "N/A"}, Vd=${pkSummary.vd_lkg?.toFixed(1) ?? "N/A"} L/kg, CLh=${pkSummary.cl_hepatic_fraction !== null && pkSummary.cl_hepatic_fraction !== undefined ? (pkSummary.cl_hepatic_fraction * 100).toFixed(0) + "%" : "N/A"}`
             : "No ADMET predictions linked (run predict_admet_properties workflow first)"}
        </span>
        {!pkSummary && !pkLoading && (
          <button
            className="text-xs text-blue-600 dark:text-blue-400 underline shrink-0"
            onClick={loadPkSummary}
            data-testid="ind-refresh-pk"
          >
            Refresh
          </button>
        )}
        {pkSummary && (
          <button
            className="text-xs text-muted-foreground underline shrink-0"
            onClick={() => setPkSummary(null)}
            data-testid="ind-clear-pk"
          >
            Clear
          </button>
        )}
      </div>

      {/* Error */}
      {error && (
        <Alert variant="destructive">
          <AlertTriangle className="h-4 w-4" />
          <AlertTitle>Assembly failed</AlertTitle>
          <AlertDescription className="text-xs mt-1">{error}</AlertDescription>
        </Alert>
      )}

      {/* Generate button */}
      <div data-tour="ind-generate" className="flex items-center justify-center gap-3">
        <Button
          className="h-9 px-5 text-sm font-semibold gap-1.5"
          disabled={!canGenerate}
          onClick={result ? () => setConfirming(true) : generate}
          data-testid="ind-generate-button"
        >
          {generating ? (
            <>
              <Loader2 className="h-3.5 w-3.5 animate-spin" />
              Generating…
            </>
          ) : (
            <>
              Generate IND Package
              <ChevronDown className="h-3.5 w-3.5 -rotate-90" />
            </>
          )}
        </Button>
      </div>

      {/* Progress bar while generating */}
      {generating && (
        <div className="space-y-1.5">
          <div className="h-1.5 w-full bg-muted rounded-full overflow-hidden">
            <div className="h-full bg-blue-500 rounded-full animate-pulse" style={{ width: "60%" }} />
          </div>
          <p className="text-center text-xs text-muted-foreground">
            Assembling sections · rendering tables · validating citations
          </p>
        </div>
      )}

      {/* Output section */}
      {result && !generating && (
        <div className="pt-3 border-t space-y-3">
          <div className="flex items-center gap-2">
            <span className="text-xs font-semibold">Last generated</span>
            <span className="text-xs text-muted-foreground font-mono">{result.generated_at}</span>
            {result.sections.length > 0 && (
              <Badge variant="secondary" className="text-xs">
                {result.sections.length} sections
              </Badge>
            )}
          </div>

          {/* Download row — Markdown */}
          <div className="flex items-center gap-2 rounded-md border px-3 py-2 text-xs">
            <Badge variant="outline" className="font-mono text-xs shrink-0">MD</Badge>
            <span className="flex-1 truncate font-mono text-muted-foreground">
              {campaignId}_CTD_Module2.6.md
            </span>
            <Button
              size="sm"
              variant="outline"
              className="h-6 text-xs gap-1 shrink-0"
              onClick={downloadMarkdown}
              data-testid="ind-download-md-button"
            >
              <Download className="h-3 w-3" />
              Download
            </Button>
          </div>

          {/* Download row — DOCX (only if pandoc available) */}
          {result.pandoc_available && result.docx_generated ? (
            <div className="flex items-center gap-2 rounded-md border px-3 py-2 text-xs">
              <Badge variant="outline" className="font-mono text-xs shrink-0 text-blue-700 dark:text-blue-400 border-blue-300">DOCX</Badge>
              <span className="flex-1 truncate font-mono text-muted-foreground">
                {campaignId}_CTD_Module2.6.docx
              </span>
              <Button
                size="sm"
                variant="outline"
                className="h-6 text-xs gap-1 shrink-0"
                onClick={downloadDocx}
                data-testid="ind-download-docx-button"
              >
                <Download className="h-3 w-3" />
                Download
              </Button>
            </div>
          ) : !result.pandoc_available ? (
            <Alert className="border-amber-300 bg-amber-50 dark:bg-amber-950/30 py-2">
              <AlertTriangle className="h-3.5 w-3.5 text-amber-700 dark:text-amber-400" />
              <AlertTitle className="text-xs font-semibold text-amber-800 dark:text-amber-300">
                Pandoc not found — DOCX output unavailable
              </AlertTitle>
              <AlertDescription className="text-xs mt-0.5 text-amber-700 dark:text-amber-400">
                Markdown report generated. Install pandoc (<code className="font-mono">apt install pandoc</code>) to enable DOCX.
              </AlertDescription>
            </Alert>
          ) : null}

          {/* Markdown preview */}
          {result.markdown_preview && (
            <Collapsible open={previewOpen} onOpenChange={setPreviewOpen}>
              <CollapsibleTrigger className="flex w-full items-center justify-between rounded-md border px-3 py-2 text-xs font-medium hover:bg-muted/50 transition-colors">
                <div className="flex items-center gap-1.5">
                  <FileText className="h-3.5 w-3.5" />
                  <span>Markdown Preview</span>
                  <span className="text-muted-foreground font-normal">(first 2000 chars)</span>
                </div>
                <ChevronDown className={cn("h-3.5 w-3.5 text-muted-foreground transition-transform", previewOpen && "rotate-180")} />
              </CollapsibleTrigger>
              <CollapsibleContent>
                <pre className="mt-1 p-3 rounded-md bg-muted/40 text-xs font-mono whitespace-pre-wrap overflow-auto max-h-64 border">
                  {result.markdown_preview}
                </pre>
              </CollapsibleContent>
            </Collapsible>
          )}

          {/* Warnings */}
          {result.warnings.length > 0 && (
            <div className="space-y-1">
              {result.warnings.map((w, i) => (
                <div key={i} className="flex items-start gap-1.5 text-xs text-amber-700 dark:text-amber-400">
                  <AlertTriangle className="h-3.5 w-3.5 mt-0.5 shrink-0" />
                  {w}
                </div>
              ))}
            </div>
          )}

          {/* Approve & Sign (regulatory eSig — 21 CFR Part 11) */}
          {onRequestSign && (
            <div className="flex items-center gap-2 rounded-md border border-indigo-200 dark:border-indigo-800 px-3 py-2 text-xs bg-indigo-50/50 dark:bg-indigo-950/20">
              <Shield className="h-3.5 w-3.5 text-indigo-600 dark:text-indigo-400 shrink-0" />
              <span className="flex-1 text-muted-foreground">
                Electronic signature required for regulatory submission (21 CFR Part 11)
              </span>
              <Button
                size="sm"
                className="h-6 text-xs gap-1 shrink-0 bg-indigo-600 hover:bg-indigo-700 text-white"
                onClick={onRequestSign}
                data-testid="ind-approve-sign-button"
              >
                Approve &amp; Sign
              </Button>
            </div>
          )}

          {/* Regenerate controls */}
          <div className="flex items-center gap-2 pt-1">
            {!confirming ? (
              <Button
                size="sm"
                variant="outline"
                className="h-7 text-xs gap-1"
                onClick={() => setConfirming(true)}
                data-testid="ind-regenerate-button"
              >
                <RefreshCw className="h-3 w-3" />
                Regenerate
              </Button>
            ) : (
              <>
                <Button
                  size="sm"
                  variant="destructive"
                  className="h-7 text-xs"
                  onClick={generate}
                  data-testid="ind-confirm-overwrite-button"
                >
                  Confirm overwrite
                </Button>
                <Button
                  size="sm"
                  variant="ghost"
                  className="h-7 text-xs"
                  onClick={() => setConfirming(false)}
                >
                  Cancel
                </Button>
              </>
            )}
            {confirming && (
              <span className="text-xs text-muted-foreground">
                Regenerating overwrites the previous files.
              </span>
            )}
          </div>
        </div>
      )}
    </div>
  )
}
