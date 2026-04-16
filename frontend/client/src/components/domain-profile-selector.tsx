import { useState } from "react"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Checkbox } from "@/components/ui/checkbox"
import { Label } from "@/components/ui/label"
import { Check, ChevronRight, SkipForward } from "lucide-react"

// ── Taxonomy (hardcoded to avoid an extra round-trip) ─────────────────────────

export const DOMAIN_TAXONOMY: Record<string, string[]> = {
  genomics: ["variant calling", "WGS", "WES", "copy number", "structural variants", "population genetics"],
  transcriptomics: ["bulk RNA-seq", "spatial transcriptomics", "long-read RNA-seq", "ATAC-seq"],
  single_cell: ["scRNA-seq", "scATAC-seq", "multiome", "cell typing", "trajectory analysis"],
  epigenomics: ["ChIP-seq", "ATAC-seq", "bisulfite-seq", "CUT&RUN", "Hi-C"],
  proteomics: ["DDA", "DIA", "phosphoproteomics", "protein-protein interaction", "structural proteomics"],
  metabolomics: ["LC-MS", "GC-MS", "NMR", "lipidomics", "metabolic flux"],
  metagenomics: ["16S amplicon", "shotgun metagenomics", "metatranscriptomics", "binning/MAGs"],
  structural_biology: ["AlphaFold", "molecular docking", "MD simulation", "cryo-EM", "X-ray crystallography"],
  drug_discovery: ["ADMET prediction", "lead optimization", "target identification", "virtual screening"],
  cryo_em: ["SPA", "cryo-ET", "subtomogram averaging", "helical reconstruction"],
  pharmacology: ["PK/PD modeling", "IVIVE", "dose-response", "clinical pharmacology"],
  systems_biology: ["ODE modeling", "network analysis", "flux balance analysis", "gene regulatory networks"],
  synthetic_biology: ["genetic circuit design", "metabolic engineering", "CRISPR design"],
  bioimaging: ["cell segmentation", "fluorescence microscopy", "spatial omics imaging", "flow cytometry"],
}

export const DOMAIN_LABELS: Record<string, string> = {
  genomics: "Genomics",
  transcriptomics: "Transcriptomics",
  single_cell: "Single Cell",
  epigenomics: "Epigenomics",
  proteomics: "Proteomics",
  metabolomics: "Metabolomics",
  metagenomics: "Metagenomics",
  structural_biology: "Structural Biology",
  drug_discovery: "Drug Discovery",
  cryo_em: "Cryo-EM",
  pharmacology: "Pharmacology",
  systems_biology: "Systems Biology",
  synthetic_biology: "Synthetic Biology",
  bioimaging: "Bioimaging",
}

// ── Types ─────────────────────────────────────────────────────────────────────

export interface DomainProfile {
  domains: string[]
  topics: string[]
}

interface DomainProfileSelectorProps {
  initialProfile?: DomainProfile
  onSave: (profile: DomainProfile) => void
  onSkip: () => void
}

// ── Component ─────────────────────────────────────────────────────────────────

export function DomainProfileSelector({
  initialProfile,
  onSave,
  onSkip,
}: DomainProfileSelectorProps) {
  const [selectedDomains, setSelectedDomains] = useState<Set<string>>(
    new Set(initialProfile?.domains ?? [])
  )
  const [selectedTopics, setSelectedTopics] = useState<Set<string>>(
    new Set(initialProfile?.topics ?? [])
  )
  const [step, setStep] = useState<"domains" | "topics">("domains")

  // ── Domain selection ───────────────────────────────────────────────────────

  const toggleDomain = (key: string) => {
    setSelectedDomains(prev => {
      const next = new Set(prev)
      if (next.has(key)) {
        next.delete(key)
        // Remove topics that belong exclusively to this domain
        const topicsForRemoved = DOMAIN_TAXONOMY[key] ?? []
        const remainingDomains = Array.from(next)
        const topicsStillValid = new Set(
          remainingDomains.flatMap(d => DOMAIN_TAXONOMY[d] ?? [])
        )
        setSelectedTopics(prev2 => {
          const next2 = new Set(prev2)
          for (const t of topicsForRemoved) {
            if (!topicsStillValid.has(t)) next2.delete(t)
          }
          return next2
        })
      } else {
        next.add(key)
      }
      return next
    })
  }

  const domainsArray = Array.from(selectedDomains)

  // Topics available given current domain selection
  const availableTopics = Array.from(
    new Set(domainsArray.flatMap(d => DOMAIN_TAXONOMY[d] ?? []))
  )

  const toggleTopic = (topic: string) => {
    setSelectedTopics(prev => {
      const next = new Set(prev)
      if (next.has(topic)) {
        next.delete(topic)
      } else {
        next.add(topic)
      }
      return next
    })
  }

  const handleContinue = () => {
    if (selectedDomains.size === 0) {
      onSkip()
      return
    }
    setStep("topics")
  }

  const handleSave = () => {
    onSave({
      domains: domainsArray,
      topics: Array.from(selectedTopics),
    })
  }

  const handleBack = () => setStep("domains")

  // ── Render ─────────────────────────────────────────────────────────────────

  const domainKeys = Object.keys(DOMAIN_TAXONOMY)

  return (
    <div className="space-y-6">
      {step === "domains" && (
        <>
          <div>
            <h3 className="text-base font-semibold text-foreground">
              Which research domains do you work in?
            </h3>
            <p className="text-sm text-muted-foreground mt-1">
              Select all that apply. BioMate will prioritise relevant workflows.
            </p>
          </div>

          <div className="grid grid-cols-2 gap-3">
            {domainKeys.map(key => {
              const isSelected = selectedDomains.has(key)
              return (
                <button
                  key={key}
                  type="button"
                  onClick={() => toggleDomain(key)}
                  className={[
                    "flex items-center gap-3 rounded-lg border px-4 py-3 text-left transition-colors",
                    "hover:border-primary/60 hover:bg-primary/5",
                    isSelected
                      ? "border-primary bg-primary/10 text-primary font-medium"
                      : "border-border bg-background text-foreground",
                  ].join(" ")}
                >
                  <div
                    className={[
                      "flex h-4 w-4 shrink-0 items-center justify-center rounded border",
                      isSelected
                        ? "border-primary bg-primary text-primary-foreground"
                        : "border-muted-foreground",
                    ].join(" ")}
                  >
                    {isSelected && <Check className="h-3 w-3" />}
                  </div>
                  <span className="text-sm">{DOMAIN_LABELS[key]}</span>
                </button>
              )
            })}
          </div>

          <div className="flex items-center justify-between pt-2">
            <Button variant="ghost" size="sm" onClick={onSkip} className="gap-2 text-muted-foreground">
              <SkipForward className="h-4 w-4" />
              Skip for now
            </Button>
            <Button onClick={handleContinue} className="gap-2" disabled={selectedDomains.size === 0}>
              Continue
              <ChevronRight className="h-4 w-4" />
            </Button>
          </div>
        </>
      )}

      {step === "topics" && (
        <>
          <div>
            <h3 className="text-base font-semibold text-foreground">
              Which specific topics interest you?
            </h3>
            <p className="text-sm text-muted-foreground mt-1">
              Optional — select topics to further refine your recommendations.
            </p>
          </div>

          {domainsArray.map(domainKey => {
            const topics = DOMAIN_TAXONOMY[domainKey] ?? []
            return (
              <div key={domainKey} className="space-y-2">
                <h4 className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
                  {DOMAIN_LABELS[domainKey]}
                </h4>
                <div className="flex flex-wrap gap-2">
                  {topics.map(topic => {
                    const isSelected = selectedTopics.has(topic)
                    return (
                      <button
                        key={topic}
                        type="button"
                        onClick={() => toggleTopic(topic)}
                        className={[
                          "inline-flex items-center gap-1.5 rounded-full border px-3 py-1 text-xs transition-colors",
                          "hover:border-primary/60 hover:bg-primary/5",
                          isSelected
                            ? "border-primary bg-primary/10 text-primary font-medium"
                            : "border-border bg-background text-muted-foreground",
                        ].join(" ")}
                      >
                        {isSelected && <Check className="h-3 w-3 shrink-0" />}
                        {topic}
                      </button>
                    )
                  })}
                </div>
              </div>
            )
          })}

          <div className="flex items-center justify-between pt-2">
            <Button variant="ghost" size="sm" onClick={handleBack}>
              Back
            </Button>
            <div className="flex gap-2">
              <Button variant="outline" size="sm" onClick={onSkip} className="text-muted-foreground">
                Skip for now
              </Button>
              <Button onClick={handleSave} className="gap-2">
                <Check className="h-4 w-4" />
                Save profile
              </Button>
            </div>
          </div>
        </>
      )}
    </div>
  )
}
