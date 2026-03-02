import { useState, useEffect } from "react"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Separator } from "@/components/ui/separator"
import {
  AlertTriangle,
  CheckCircle2,
  XCircle,
  RotateCcw,
  ArrowRight,
  Settings2,
  Loader2,
  BookOpen,
} from "lucide-react"
import { cn } from "@/lib/utils"

// US-2.1a — Human-readable display names for pipeline process IDs
const PROCESS_DISPLAY_NAMES: Record<string, string> = {
  MOTION_CORRECTION: "Motion Correction",
  PATCH_MOTION_CORRECTION: "Motion Correction (Patch-based)",
  CTF_ESTIMATION: "CTF Estimation",
  CTF_ESTIMATE: "CTF Estimation",
  PATCH_CTF_ESTIMATION: "CTF Estimation (Patch-based)",
  PARTICLE_PICKING: "Particle Picking",
  BLOB_PARTICLE_PICKING: "Particle Picking (Blob)",
  AB_INITIO: "Ab Initio Reconstruction",
  HOMOGENEOUS_REFINEMENT: "Homogeneous Refinement",
  HETEROGENEOUS_REFINEMENT: "Heterogeneous Refinement",
  STAR_ALIGN: "Read Alignment (STAR)",
  HISAT2_ALIGN: "Read Alignment (HISAT2)",
  BWA_MEM: "Read Alignment (BWA-MEM)",
  BOWTIE2_ALIGN: "Read Alignment (Bowtie2)",
  FASTP: "Read Trimming (FASTP)",
  FASTP_TRIM: "Read Trimming (FASTP)",
  TRIMGALORE: "Read Trimming (TrimGalore)",
  TRIMMOMATIC: "Read Trimming (Trimmomatic)",
  FASTQC: "Quality Control (FastQC)",
  MULTIQC: "Quality Control (MultiQC)",
  FEATURECOUNTS: "Gene Counting (featureCounts)",
  SALMON: "Transcript Quantification (Salmon)",
  SALMON_QUANT: "Transcript Quantification (Salmon)",
  KALLISTO: "Transcript Quantification (Kallisto)",
  FLAGSTAT: "Alignment Statistics (flagstat)",
  SAMTOOLS_FLAGSTAT: "Alignment Statistics (flagstat)",
  MARKDUPLICATES: "Duplicate Marking (Picard)",
  CELLRANGER_COUNT: "Single-Cell Processing (Cell Ranger)",
  CELLRANGER: "Single-Cell Processing (Cell Ranger)",
  STARSOLO: "Single-Cell Alignment (STARsolo)",
  MACS2_CALLPEAK: "Peak Calling (MACS2)",
  MACS2: "Peak Calling (MACS2)",
  KRAKEN2: "Taxonomic Classification (Kraken2)",
  KRAKEN2_KRAKEN2: "Taxonomic Classification (Kraken2)",
  BRACKEN: "Abundance Estimation (Bracken)",
  // Drug discovery / pharmacology
  ADMET_PRED: "ADMET Safety Screening",
  PREDICT_ADMET_PROPERTIES: "ADMET Property Prediction",
  ADMET_TOXICITY: "Toxicity Safety Gate",
  ADMET_SAFETY: "ADMET Safety Check",
  HERG_SCREEN: "hERG Cardiotoxicity Screen",
  DILI_SCREEN: "DILI Hepatotoxicity Screen",
  TOXICITY_SCREEN: "Compound Toxicity Screen",
  SMILES_QC: "Compound Structure QC",
  COMPOUND_QC: "Compound Quality Check",
  STRUCTURE_QC: "Structure Validity Check",
  ADMET_PRECHECK: "ADMET Pre-screening",
  PGX_COVERAGE: "Pharmacogenomics Coverage",
  PGX_QC: "PGx Gene Coverage QC",
  CYP_COVERAGE: "CYP Gene Coverage",
  PHARMACOGENOMICS_QC: "Pharmacogenomics QC",
  PULLDOWN_QC: "Pulldown Enrichment QC",
  CHEMOPROTEOMICS_QC: "Chemoproteomics QC",
  ENRICHMENT_QC: "Enrichment Efficiency QC",
}

function humanizeProcessName(raw: string): string {
  const base = raw.includes(":") ? raw.split(":").pop()! : raw
  return (
    PROCESS_DISPLAY_NAMES[base.toUpperCase()] ??
    base.replace(/_/g, " ").replace(/\b\w/g, (l) => l.toUpperCase())
  )
}

// US-7.1 — Domain-specific troubleshooting steps when no suggestions are available
const TROUBLESHOOTING_STEPS: Record<string, string[]> = {
  CTF_ESTIMATION: [
    "Verify accelerating voltage and spherical aberration (Cs) match your microscope",
    "Check pixel size calibration — incorrect values shift all defocus estimates",
    "Inspect micrographs for ice contamination or beam damage",
  ],
  CTF_ESTIMATE: [
    "Verify accelerating voltage and spherical aberration (Cs) match your microscope",
    "Check pixel size calibration — incorrect values shift all defocus estimates",
    "Inspect micrographs for ice contamination or beam damage",
  ],
  MOTION_CORRECTION: [
    "Check total electron dose — very high doses increase beam-induced motion",
    "Verify gain reference is correct for your detector",
    "Try reducing frames per micrograph to limit accumulated motion",
  ],
  STAR_ALIGN: [
    "Verify the genome species matches your sample (common: mouse vs human mix-up)",
    "Check for rRNA or adapter contamination with FastQC before alignment",
    "Ensure the STAR genome index was built with the correct genome and annotation versions",
  ],
  FASTP: [
    "Check raw FASTQ for systematic quality issues with FastQC",
    "Verify the input file is not truncated or corrupted",
    "Try a higher quality cutoff (--qualified_quality_phred 20 → 25)",
  ],
  FASTP_TRIM: [
    "Check raw FASTQ for systematic quality issues with FastQC",
    "Verify the input file is not truncated or corrupted",
    "Try a higher quality cutoff (--qualified_quality_phred 20 → 25)",
  ],
  FEATURECOUNTS: [
    "Verify strandedness matches your library prep (unstranded / forward / reverse)",
    "Check that the GTF annotation version matches the genome used for alignment",
    "Confirm reads are not multi-mapping excessively (check STAR alignment log)",
  ],
  KRAKEN2: [
    "Consider upgrading to the Standard 8 GB or 16 GB database for better coverage",
    "Remove the confidence threshold (set to 0.0) to classify more reads",
    "Check if your sample is from a poorly-represented environment in the database",
  ],
  KRAKEN2_KRAKEN2: [
    "Consider upgrading to the Standard 8 GB or 16 GB database for better coverage",
    "Remove the confidence threshold (set to 0.0) to classify more reads",
    "Check if your sample is from a poorly-represented environment in the database",
  ],
  // Drug discovery / pharmacology
  ADMET_PRED: [
    "Verify all SMILES strings are valid — use RDKit or ChemDraw to check structural validity",
    "For hERG risk: reduce logP below 3, break planar ring stacks, remove basic amines adjacent to aromatic rings",
    "For DILI risk: evaluate daily dose projection — low-dose compounds (< 10 mg/day) have substantially lower DILI incidence",
    "Consider scaffold hopping or bioisostere replacement to reduce toxicophores while maintaining potency",
  ],
  PREDICT_ADMET_PROPERTIES: [
    "Verify all SMILES strings are valid — use RDKit or ChemDraw to check structural validity",
    "For hERG risk: reduce logP below 3, break planar ring stacks, remove basic amines adjacent to aromatic rings",
    "For DILI risk: evaluate daily dose projection — low-dose compounds (< 10 mg/day) have substantially lower DILI incidence",
    "Confirm predictions with in vitro assays (hERG patch-clamp IC50, HepaRG DILI assay) before IND filing",
  ],
  HERG_SCREEN: [
    "Structural modifications to reduce hERG liability: lower logP, remove basic nitrogen atoms, reduce planarity",
    "Consider methyl or fluorine bioisostere substitutions that disrupt hERG channel binding",
    "Confirm with automated patch-clamp (IonWorks Barracuda) or manual patch-clamp for IC50 measurement",
    "Check if QT prolongation risk is acceptable relative to therapeutic benefit (FDA E14 guidance)",
  ],
  DILI_SCREEN: [
    "Evaluate daily dose — DILI incidence drops significantly below 10 mg/day (Lammert et al. 2010)",
    "Assess reactive metabolite formation potential via GSH trapping assay",
    "Run HepaRG or primary human hepatocyte cytotoxicity assay for mechanistic confirmation",
    "Review structural alerts: quinones, epoxides, Michael acceptors, thiophenes (reactive metabolite flags)",
  ],
  SMILES_QC: [
    "Check that SMILES notation is canonical (use RDKit Chem.MolToSmiles after parsing)",
    "Resolve salt forms: remove counterions using RDKit SaltRemover before analysis",
    "Resolve undefined stereocenters: assign R/S configuration or use racemic notation explicitly",
    "Ensure charged forms match physiological pH (typically deprotonated acids, protonated bases)",
  ],
  PGX_COVERAGE: [
    "CYP2D6 has high GC content — consider increasing depth target to 60× for reliable star allele calling",
    "CYP2D6 copy number variations (CNVs) require long-read or specialized CNV-aware tools",
    "Use CPIC-recommended star allele callers (Stargazer, Aldy, PyPGx) that account for GC bias",
    "Consider a targeted PGx panel (e.g., PGXT, xTARGet PGx) if WGS depth is insufficient",
  ],
  PHARMACOGENOMICS_QC: [
    "CYP2D6 has high GC content — consider increasing depth target to 60× for reliable star allele calling",
    "Use CPIC-recommended star allele callers that account for GC bias (Stargazer, Aldy, PyPGx)",
    "Verify the variant calling pipeline handles complex structural variants in CYP2D6 locus",
  ],
}

interface QCMetric {
  name: string
  value: number
  threshold: number
  passed: boolean
  unit?: string
}

interface ParameterSuggestion {
  parameter: string
  currentValue: any
  suggestedValue: any
  reason: string
  confidence: number
  // US-6.1: provenance — "rule" = empirical heuristic, "literature" = cites a published standard
  source?: string
}

interface QCGateModalProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  processName: string
  metrics: QCMetric[]
  failures: string[]
  suggestions: ParameterSuggestion[]
  onRetryWithSuggested: () => Promise<void>
  onProceedAnyway: () => void
  onCancel: () => void
  isApplying?: boolean
  // US-7.3a/b
  retryCount?: number
  previousMetrics?: Record<string, number>
  // For diff panel
  qcMetrics?: Record<string, number>
}

export function QCGateModal({
  open,
  onOpenChange,
  processName,
  metrics,
  failures,
  suggestions,
  onRetryWithSuggested,
  onProceedAnyway,
  onCancel,
  isApplying = false,
  retryCount,
  previousMetrics,
  qcMetrics,
}: QCGateModalProps) {
  // US-2.2 — pre-check only suggestions with confidence >= 0.7
  const [selectedSuggestions, setSelectedSuggestions] = useState<Set<string>>(
    new Set(suggestions.filter((s) => s.confidence >= 0.7).map((s) => s.parameter))
  )
  // US-2.5 — two-step Proceed Anyway confirmation
  const [confirmingProceed, setConfirmingProceed] = useState(false)
  // Reset confirmation state whenever the modal is reopened (e.g. after a retry)
  useEffect(() => {
    if (open) setConfirmingProceed(false)
  }, [open])

  const toggleSuggestion = (param: string) => {
    setSelectedSuggestions((prev) => {
      const next = new Set(prev)
      if (next.has(param)) {
        next.delete(param)
      } else {
        next.add(param)
      }
      return next
    })
  }

  const handleRetry = async () => {
    const appliedSuggestions = suggestions.filter((s) =>
      selectedSuggestions.has(s.parameter)
    )
    console.log("Applying suggestions:", appliedSuggestions)
    await onRetryWithSuggested()
  }

  const passedMetrics = metrics.filter((m) => m.passed)
  const failedMetrics = metrics.filter((m) => !m.passed)

  // US-7.1 — look up domain-specific troubleshooting steps
  const processKey = processName.includes(":")
    ? processName.split(":").pop()!.toUpperCase()
    : processName.toUpperCase()
  const troubleshootingSteps = TROUBLESHOOTING_STEPS[processKey] ?? []

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl max-h-[80vh] overflow-y-auto">
        <DialogHeader>
          {/* US-7.3a — retry counter in title */}
          <DialogTitle className="flex items-center gap-2">
            <AlertTriangle className="h-5 w-5 text-amber-600" />
            Quality Control Gate Triggered
            {retryCount != null && retryCount > 0 && (
              <span className="text-sm font-normal text-muted-foreground">
                (Retry #{retryCount})
              </span>
            )}
          </DialogTitle>
          {/* US-2.1a — humanised process name */}
          <DialogDescription>
            Process <strong>{humanizeProcessName(processName)}</strong> did not meet quality thresholds
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-4">
          {/* US-7.3b — before/after diff panel when previousMetrics available */}
          {previousMetrics && Object.keys(previousMetrics).length > 0 && qcMetrics && (
            <div className="text-xs border rounded-md p-2 bg-muted/40">
              <p className="font-medium text-muted-foreground mb-1">vs. previous attempt:</p>
              {Object.entries(previousMetrics)
                .filter(([k]) => qcMetrics[k] !== undefined)
                .map(([k, prev]) => {
                  const curr = qcMetrics[k] as number
                  const delta = curr - prev
                  return (
                    <div key={k} className="flex items-center gap-2">
                      <span className="capitalize">{k.replace(/_/g, " ")}</span>
                      <span className="text-muted-foreground">
                        {prev.toFixed(1)} → {curr.toFixed(1)}
                      </span>
                      <span className={delta > 0 ? "text-green-600" : "text-red-500"}>
                        ({delta > 0 ? "+" : ""}{delta.toFixed(1)})
                      </span>
                    </div>
                  )
                })}
            </div>
          )}

          {/* QC Metrics Section */}
          <div>
            <h4 className="text-sm font-medium mb-2">Quality Metrics</h4>
            <div className="space-y-2">
              {failedMetrics.map((metric, idx) => (
                <Alert key={idx} variant="destructive" className="py-2">
                  <XCircle className="h-4 w-4" />
                  <AlertDescription className="text-sm">
                    <div className="flex items-center justify-between">
                      <span className="font-medium">{metric.name}</span>
                      <div className="flex items-center gap-2">
                        <Badge variant="destructive" className="text-xs">
                          {metric.value}{metric.unit || ""}
                        </Badge>
                        <span className="text-xs text-muted-foreground">
                          Threshold: {metric.threshold}{metric.unit || ""}
                        </span>
                      </div>
                    </div>
                  </AlertDescription>
                </Alert>
              ))}

              {passedMetrics.length > 0 && (
                <details className="text-xs">
                  <summary className="cursor-pointer text-muted-foreground hover:text-foreground">
                    {passedMetrics.length} metric(s) passed
                  </summary>
                  <div className="mt-2 space-y-1 pl-4">
                    {passedMetrics.map((metric, idx) => (
                      <div key={idx} className="flex items-center justify-between text-green-600">
                        <span className="flex items-center gap-1">
                          <CheckCircle2 className="h-3 w-3" />
                          {metric.name}
                        </span>
                        <span>
                          {metric.value}{metric.unit || ""} (threshold:{" "}
                          {metric.threshold}{metric.unit || ""})
                        </span>
                      </div>
                    ))}
                  </div>
                </details>
              )}
            </div>
          </div>

          {/* Issues Section */}
          {failures.length > 0 && (
            <div>
              <h4 className="text-sm font-medium mb-2">Issues Detected</h4>
              <ul className="text-sm space-y-1 text-muted-foreground">
                {failures.map((failure, idx) => (
                  <li key={idx} className="flex items-start gap-2">
                    <span className="text-amber-600">•</span>
                    {failure}
                  </li>
                ))}
              </ul>
            </div>
          )}

          <Separator />

          {/* Parameter Suggestions Section */}
          {suggestions.length > 0 ? (
            <div>
              <h4 className="text-sm font-medium mb-2 flex items-center gap-2">
                <Settings2 className="h-4 w-4" />
                Suggested Parameter Adjustments
              </h4>
              <p className="text-xs text-muted-foreground mb-3">
                Select which adjustments to apply. High-confidence suggestions are pre-selected.
              </p>

              <div className="space-y-2">
                {suggestions.map((suggestion, idx) => (
                  <div
                    key={idx}
                    className={cn(
                      "border rounded-lg p-3 cursor-pointer transition-colors",
                      selectedSuggestions.has(suggestion.parameter)
                        ? "border-primary bg-primary/5"
                        : suggestion.confidence < 0.7
                        ? "border-yellow-400/60 hover:border-yellow-500/60"
                        : "border-border hover:border-primary/50"
                    )}
                    onClick={() => toggleSuggestion(suggestion.parameter)}
                  >
                    <div className="flex items-start justify-between">
                      <div className="flex-1">
                        <div className="flex items-center gap-2 mb-1">
                          <span className="font-medium text-sm">{suggestion.parameter}</span>
                          <Badge
                            variant={suggestion.confidence > 0.8 ? "default" : "secondary"}
                            className="text-xs"
                          >
                            {(suggestion.confidence * 100).toFixed(0)}% confidence
                          </Badge>
                          {/* US-6.1 — source provenance badge, shown only for literature-backed suggestions */}
                          {suggestion.source === "literature" && (
                            <span className="inline-flex items-center gap-1 text-xs text-sky-600 dark:text-sky-400 font-normal">
                              <BookOpen className="h-3 w-3" />
                              Literature
                            </span>
                          )}
                        </div>
                        <p className="text-xs text-muted-foreground mb-2">
                          {suggestion.reason}
                        </p>
                        {/* US-2.2 — advisory label for low-confidence suggestions */}
                        {suggestion.confidence < 0.7 && (
                          <p className="text-xs text-yellow-600 mb-2">
                            Lower confidence — review before applying
                          </p>
                        )}
                        <div className="flex items-center gap-4 text-xs">
                          <div>
                            <span className="text-muted-foreground">Current: </span>
                            <code className="bg-muted px-1 py-0.5 rounded">
                              {JSON.stringify(suggestion.currentValue)}
                            </code>
                          </div>
                          <ArrowRight className="h-3 w-3 text-muted-foreground" />
                          <div>
                            <span className="text-muted-foreground">Suggested: </span>
                            <code className="bg-primary/10 px-1 py-0.5 rounded font-medium">
                              {JSON.stringify(suggestion.suggestedValue)}
                            </code>
                          </div>
                        </div>
                      </div>
                      <div className="ml-3">
                        <input
                          type="checkbox"
                          checked={selectedSuggestions.has(suggestion.parameter)}
                          onChange={() => toggleSuggestion(suggestion.parameter)}
                          className="h-4 w-4 rounded border-gray-300"
                          onClick={(e) => e.stopPropagation()}
                        />
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          ) : (
            /* US-7.1 — domain-specific troubleshooting fallback */
            <div>
              <Alert className="border-amber-500/50 bg-amber-50/50 dark:bg-amber-950/20">
                <AlertTriangle className="h-4 w-4 text-amber-600" />
                <AlertDescription className="text-sm text-amber-800 dark:text-amber-200">
                  No automatic parameter suggestions available.
                  {troubleshootingSteps.length === 0 &&
                    " You may need to manually adjust parameters."}
                </AlertDescription>
              </Alert>
              {troubleshootingSteps.length > 0 && (
                <div className="mt-3">
                  <p className="text-xs font-medium text-muted-foreground mb-2">
                    Troubleshooting steps for {humanizeProcessName(processName)}:
                  </p>
                  <ul className="text-xs space-y-1.5 text-muted-foreground">
                    {troubleshootingSteps.map((step, idx) => (
                      <li key={idx} className="flex items-start gap-2">
                        <span className="text-amber-600 mt-0.5">{idx + 1}.</span>
                        {step}
                      </li>
                    ))}
                  </ul>
                </div>
              )}
            </div>
          )}

          {/* US-2.4 — summary line of selected changes */}
          {selectedSuggestions.size > 0 && (
            <p className="text-xs text-muted-foreground">
              <span className="font-medium">Will apply: </span>
              {suggestions
                .filter((s) => selectedSuggestions.has(s.parameter))
                .map(
                  (s) =>
                    `${s.parameter}: ${JSON.stringify(s.currentValue)} → ${JSON.stringify(s.suggestedValue)}`
                )
                .join(" · ")}
            </p>
          )}
        </div>

        {/* US-2.1b + US-2.5 — footer with button consequence subtitles */}
        <DialogFooter className="flex-col sm:flex-row gap-2 mt-2">
          {confirmingProceed ? (
            <>
              <p className="text-xs text-muted-foreground flex-1 text-left self-center">
                Proceeding will be recorded in the workflow audit log.
              </p>
              <Button
                variant="ghost"
                size="sm"
                onClick={() => setConfirmingProceed(false)}
                disabled={isApplying}
              >
                Go Back
              </Button>
              <Button
                variant="destructive"
                size="sm"
                onClick={onProceedAnyway}
                disabled={isApplying}
              >
                Confirm Proceed
              </Button>
            </>
          ) : (
            <>
              <div className="flex flex-col items-start gap-0.5">
                <Button
                  variant="outline"
                  onClick={onCancel}
                  disabled={isApplying}
                >
                  Cancel Workflow
                </Button>
                <p className="text-xs text-muted-foreground">
                  Stops the workflow — completed steps are saved
                </p>
              </div>

              <div className="flex flex-col items-start gap-0.5">
                <Button
                  variant="outline"
                  onClick={() => setConfirmingProceed(true)}
                  disabled={isApplying}
                >
                  Proceed Anyway
                </Button>
                <p className="text-xs text-muted-foreground">
                  Continues with current metrics — results may be inaccurate
                </p>
              </div>

              <div className="flex flex-col items-start gap-0.5">
                <Button
                  onClick={handleRetry}
                  disabled={
                    suggestions.length === 0 ||
                    selectedSuggestions.size === 0 ||
                    isApplying
                  }
                  className="bg-green-600 hover:bg-green-700"
                >
                  {isApplying ? (
                    <>
                      <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                      Applying...
                    </>
                  ) : (
                    <>
                      <RotateCcw className="h-4 w-4 mr-2" />
                      Retry with {selectedSuggestions.size} Adjustment
                      {selectedSuggestions.size !== 1 ? "s" : ""}
                    </>
                  )}
                </Button>
                <p className="text-xs text-muted-foreground">
                  Re-runs this step with updated parameters
                </p>
              </div>
            </>
          )}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
