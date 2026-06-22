import { useState, useRef } from "react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Check, SkipForward, Plus } from "lucide-react"

// ── Taxonomy — mirrors backend/lib/galaxy/ai/domain_registry.py ───────────────
// 14 canonical user-facing domains + 8 routing-only domains users commonly pick.
// Canonical source: domain_registry.py — update there first.

export const DOMAIN_TAXONOMY: Record<string, string[]> = {
  // ── Canonical (user profile) domains ──────────────────────────────────────
  genomics: [
    "variant calling", "WGS", "WES", "copy number", "structural variants",
    "population genetics", "genome assembly", "de novo assembly",
  ],
  transcriptomics: [
    "bulk RNA-seq", "spatial transcriptomics", "long-read RNA-seq",
    "ATAC-seq", "microarray", "differential expression",
  ],
  single_cell: [
    "scRNA-seq", "scATAC-seq", "multiome", "cell typing", "trajectory analysis",
    "cell clustering", "Seurat", "Scanpy",
  ],
  epigenomics: [
    "ChIP-seq", "ATAC-seq", "bisulfite-seq", "CUT&RUN", "Hi-C",
    "DNA methylation", "WGBS", "RRBS",
  ],
  proteomics: [
    "DDA", "DIA", "phosphoproteomics", "protein-protein interaction",
    "structural proteomics", "mass spectrometry", "TMT",
  ],
  metabolomics: [
    "LC-MS", "GC-MS", "NMR", "lipidomics", "metabolic flux",
    "untargeted metabolomics", "targeted metabolomics",
  ],
  metagenomics: [
    "16S amplicon", "shotgun metagenomics", "metatranscriptomics",
    "binning/MAGs", "microbiome", "taxonomic profiling",
  ],
  structural_biology: [
    "AlphaFold", "molecular docking", "MD simulation",
    "X-ray crystallography", "protein structure prediction",
  ],
  drug_discovery: [
    "ADMET prediction", "lead optimization", "target identification",
    "virtual screening", "docking", "QSAR", "scaffold hopping",
    "PK/PD modeling", "IVIVE", "dose-response", "clinical pharmacology",
    "retrosynthesis", "generative chemistry", "drug repurposing",
  ],
  cryo_em: [
    "SPA", "cryo-ET", "subtomogram averaging", "helical reconstruction",
    "CryoSPARC", "RELION",
  ],
  systems_biology: [
    "ODE modeling", "network analysis", "flux balance analysis",
    "gene regulatory networks", "pathway modeling",
  ],
  synthetic_biology: [
    "genetic circuit design", "metabolic engineering", "CRISPR design",
    "gene synthesis", "plasmid design",
  ],
  bioimaging: [
    "cell segmentation", "fluorescence microscopy", "spatial omics imaging",
    "flow cytometry", "confocal", "image analysis",
  ],
  lab_automation: [
    "liquid handling", "plate reader", "OT-2", "PyLabRobot", "LIMS",
    "sample tracking", "high-throughput screening",
  ],
  // ── Commonly-selected routing-only domains ─────────────────────────────────
  immunology: [
    "antibody engineering", "flow cytometry / FACS", "TCR/BCR repertoire",
    "immunophenotyping", "cytokine profiling", "HLA typing",
  ],
  cancer_biology: [
    "somatic mutation", "CNV", "TCGA analysis", "tumour heterogeneity",
    "driver gene discovery", "liquid biopsy",
  ],
  multi_omics: [
    "multi-omics integration", "data fusion", "factor analysis",
    "cross-modal alignment", "MOFA", "WNN",
  ],
  molecular_biology: [
    "primer design", "PCR", "cloning", "guide RNA design",
    "restriction mapping", "vector design",
  ],
  cell_biology: [
    "cell line characterisation", "apoptosis", "cell signaling",
    "organelle imaging", "CRISPR screen",
  ],
  genetics: [
    "GWAS", "linkage analysis", "QTL mapping", "heritability",
    "Mendelian disease", "polygenic risk score",
  ],
  microbiology: [
    "antimicrobial resistance", "phage biology", "biofilm",
    "pathogen genomics", "microbiome-host interaction",
  ],
  biochemistry: [
    "enzyme kinetics", "binding assay", "ITC / SPR",
    "circular dichroism", "thermodynamics",
  ],
}

export const DOMAIN_LABELS: Record<string, string> = {
  genomics:          "Genomics",
  transcriptomics:   "Transcriptomics",
  single_cell:       "Single Cell",
  epigenomics:       "Epigenomics",
  proteomics:        "Proteomics",
  metabolomics:      "Metabolomics",
  metagenomics:      "Metagenomics",
  structural_biology: "Structural Biology",
  drug_discovery:    "Drug Discovery & Pharmacology",
  cryo_em:           "Cryo-EM",
  systems_biology:   "Systems Biology",
  synthetic_biology: "Synthetic Biology",
  bioimaging:        "Bioimaging",
  lab_automation:    "Lab Automation",
  immunology:        "Immunology",
  cancer_biology:    "Cancer Biology",
  multi_omics:       "Multi-omics",
  molecular_biology: "Molecular Biology",
  cell_biology:      "Cell Biology",
  genetics:          "Genetics",
  microbiology:      "Microbiology",
  biochemistry:      "Biochemistry",
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

  // "Other" domain free-text
  const [otherDomainChecked, setOtherDomainChecked] = useState(false)
  const [otherDomainText, setOtherDomainText] = useState("")
  const otherDomainRef = useRef<HTMLInputElement>(null)

  // "Other" topic free-text per domain key (including "other" itself)
  const [otherTopicText, setOtherTopicText] = useState<Record<string, string>>({})

  // ── Domain toggle ──────────────────────────────────────────────────────────

  const toggleDomain = (key: string) => {
    setSelectedDomains(prev => {
      const next = new Set(prev)
      if (next.has(key)) {
        next.delete(key)
        // Remove topics that belong exclusively to this domain
        const topicsForRemoved = DOMAIN_TAXONOMY[key] ?? []
        const remaining = Array.from(next)
        const stillValid = new Set(remaining.flatMap(d => DOMAIN_TAXONOMY[d] ?? []))
        setSelectedTopics(prev2 => {
          const next2 = new Set(prev2)
          for (const t of topicsForRemoved) {
            if (!stillValid.has(t)) next2.delete(t)
          }
          return next2
        })
      } else {
        next.add(key)
      }
      return next
    })
  }

  const toggleTopic = (topic: string) => {
    setSelectedTopics(prev => {
      const next = new Set(prev)
      if (next.has(topic)) next.delete(topic)
      else next.add(topic)
      return next
    })
  }

  const addOtherTopic = (domainKey: string) => {
    const text = (otherTopicText[domainKey] ?? "").trim()
    if (!text) return
    setSelectedTopics(prev => new Set([...prev, text]))
    setOtherTopicText(prev => ({ ...prev, [domainKey]: "" }))
  }

  // ── Save ───────────────────────────────────────────────────────────────────

  const handleSave = () => {
    const domains = Array.from(selectedDomains)
    if (otherDomainChecked && otherDomainText.trim()) {
      domains.push(otherDomainText.trim())
    }
    onSave({ domains, topics: Array.from(selectedTopics) })
  }

  // ── Render ─────────────────────────────────────────────────────────────────

  const domainKeys = Object.keys(DOMAIN_TAXONOMY)
  const selectedDomainKeys = domainKeys.filter(k => selectedDomains.has(k))

  return (
    <div className="space-y-5">
      {/* Header */}
      <div>
        <h3 className="text-base font-semibold text-foreground">
          Which research domains do you work in?
        </h3>
        <p className="text-sm text-muted-foreground mt-1">
          Select all that apply. Topics appear automatically once you pick a domain.
        </p>
      </div>

      {/* Domain grid */}
      <div className="grid grid-cols-2 sm:grid-cols-3 gap-2">
        {domainKeys.map(key => {
          const isSelected = selectedDomains.has(key)
          return (
            <button
              key={key}
              type="button"
              onClick={() => toggleDomain(key)}
              className={[
                "flex items-center gap-2 rounded-lg border px-3 py-2 text-left text-sm transition-colors",
                "hover:border-primary/60 hover:bg-primary/5",
                isSelected
                  ? "border-primary bg-primary/10 text-primary font-medium"
                  : "border-border bg-background text-foreground",
              ].join(" ")}
            >
              <div
                className={[
                  "flex h-3.5 w-3.5 shrink-0 items-center justify-center rounded border",
                  isSelected
                    ? "border-primary bg-primary text-primary-foreground"
                    : "border-muted-foreground",
                ].join(" ")}
              >
                {isSelected && <Check className="h-2.5 w-2.5" />}
              </div>
              <span className="leading-tight">{DOMAIN_LABELS[key]}</span>
            </button>
          )
        })}

        {/* Other domain */}
        <button
          type="button"
          onClick={() => {
            setOtherDomainChecked(prev => !prev)
            if (!otherDomainChecked) setTimeout(() => otherDomainRef.current?.focus(), 50)
          }}
          className={[
            "flex items-center gap-2 rounded-lg border px-3 py-2 text-left text-sm transition-colors",
            "hover:border-primary/60 hover:bg-primary/5",
            otherDomainChecked
              ? "border-primary bg-primary/10 text-primary font-medium"
              : "border-border bg-background text-foreground",
          ].join(" ")}
        >
          <div
            className={[
              "flex h-3.5 w-3.5 shrink-0 items-center justify-center rounded border",
              otherDomainChecked
                ? "border-primary bg-primary text-primary-foreground"
                : "border-muted-foreground",
            ].join(" ")}
          >
            {otherDomainChecked && <Check className="h-2.5 w-2.5" />}
          </div>
          <span className="leading-tight">Other…</span>
        </button>
      </div>

      {/* Other domain text input */}
      {otherDomainChecked && (
        <Input
          ref={otherDomainRef}
          placeholder="e.g. Glycoproteomics, Radiomics, Computational Neuroscience…"
          value={otherDomainText}
          onChange={e => setOtherDomainText(e.target.value)}
          className="text-sm"
        />
      )}

      {/* Inline topic expansion — one block per selected domain */}
      {selectedDomainKeys.length > 0 && (
        <div className="space-y-4 border-t pt-4">
          <p className="text-sm text-muted-foreground">
            Refine by topic <span className="text-xs">(optional)</span>
          </p>
          {selectedDomainKeys.map(domainKey => {
            const topics = DOMAIN_TAXONOMY[domainKey] ?? []
            return (
              <div key={domainKey} className="space-y-2">
                <h4 className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
                  {DOMAIN_LABELS[domainKey]}
                </h4>
                <div className="flex flex-wrap gap-1.5">
                  {topics.map(topic => {
                    const isSelected = selectedTopics.has(topic)
                    return (
                      <button
                        key={topic}
                        type="button"
                        onClick={() => toggleTopic(topic)}
                        className={[
                          "inline-flex items-center gap-1 rounded-full border px-2.5 py-0.5 text-xs transition-colors",
                          "hover:border-primary/60 hover:bg-primary/5",
                          isSelected
                            ? "border-primary bg-primary/10 text-primary font-medium"
                            : "border-border bg-background text-muted-foreground",
                        ].join(" ")}
                      >
                        {isSelected && <Check className="h-2.5 w-2.5 shrink-0" />}
                        {topic}
                      </button>
                    )
                  })}

                  {/* Other topic inline */}
                  <div className="flex items-center gap-1">
                    <input
                      type="text"
                      placeholder="Other topic…"
                      value={otherTopicText[domainKey] ?? ""}
                      onChange={e =>
                        setOtherTopicText(prev => ({ ...prev, [domainKey]: e.target.value }))
                      }
                      onKeyDown={e => {
                        if (e.key === "Enter") { e.preventDefault(); addOtherTopic(domainKey) }
                      }}
                      className={[
                        "h-6 rounded-full border border-dashed border-muted-foreground/50",
                        "bg-background px-2.5 text-xs text-muted-foreground placeholder:text-muted-foreground/50",
                        "focus:outline-none focus:border-primary focus:text-foreground",
                        "w-32",
                      ].join(" ")}
                    />
                    <button
                      type="button"
                      onClick={() => addOtherTopic(domainKey)}
                      className="flex h-5 w-5 items-center justify-center rounded-full border border-dashed border-muted-foreground/50 text-muted-foreground hover:border-primary hover:text-primary transition-colors"
                      title="Add topic"
                    >
                      <Plus className="h-3 w-3" />
                    </button>
                  </div>
                </div>
              </div>
            )
          })}
        </div>
      )}

      {/* Actions */}
      <div className="flex items-center justify-between pt-1">
        <Button variant="ghost" size="sm" onClick={onSkip} className="gap-2 text-muted-foreground">
          <SkipForward className="h-4 w-4" />
          Skip for now
        </Button>
        <Button
          onClick={handleSave}
          className="gap-2"
          disabled={selectedDomains.size === 0 && !otherDomainChecked}
        >
          <Check className="h-4 w-4" />
          Save profile
        </Button>
      </div>
    </div>
  )
}
