import { useState, useRef } from "react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Check, SkipForward, Plus } from "lucide-react"

// ── Taxonomy — derived from backend/database/galaxy_ai_tools.db ───────────────
//
// 36 domain values in DB (2,632 workflows total). Topics reflect actual workflow
// coverage verified against the DB on 2026-06-21.
// Not shown in selector (routing-only): general, variant_calling, database,
// literature — these are internal routing labels, not user research areas.
// pharmacology (23 wf) and cryo_et (6 wf) are absorbed as topics.
// imaging (45 wf) is merged into bioimaging.
//
// Canonical source: backend/lib/galaxy/ai/domain_registry.py
// Update domain_registry.py first, then mirror here.

export const DOMAIN_TAXONOMY: Record<string, string[]> = {
  // ── Canonical (14 official user-profile domains) ──────────────────────────

  genomics: [
    "variant calling (SNP/indel, GATK4/Mutect2)",
    "WGS / WES",
    "genome assembly & de novo assembly",
    "copy number variation",
    "structural variant detection",
    "population genetics",
    "somatic mutation analysis",
  ],

  transcriptomics: [
    "bulk RNA-seq (STAR / Salmon / Kallisto)",
    "differential expression (DESeq2 / edgeR / limma)",
    "spatial transcriptomics",
    "long-read RNA-seq",
    "miRNA-seq",
    "gene quantification & TPM/FPKM",
    "splice variant analysis",
  ],

  single_cell: [
    "scRNA-seq (10x Chromium / Smart-seq)",
    "scATAC-seq",
    "multiome (RNA + ATAC)",
    "cell type annotation",
    "trajectory & pseudotime analysis",
    "cell clustering (Seurat / Scanpy)",
    "RNA velocity",
  ],

  epigenomics: [
    "ChIP-seq (histone modification / TF binding)",
    "ATAC-seq (chromatin accessibility)",
    "bisulfite-seq / WGBS / RRBS (DNA methylation)",
    "CUT&RUN / CUT&TAG",
    "Hi-C (3D genome)",
    "peak calling (MACS2)",
  ],

  proteomics: [
    "DDA mass spectrometry (MaxQuant / Mascot)",
    "DIA mass spectrometry (DIA-NN / Spectronaut)",
    "label-free quantification",
    "TMT / SILAC quantification",
    "phosphoproteomics / PTM analysis",
    "protein-protein interaction",
    "structural proteomics",
  ],

  metabolomics: [
    "untargeted LC-MS metabolomics",
    "targeted LC-MS / GC-MS",
    "NMR-based metabolomics",
    "lipidomics",
    "metabolite annotation & spectral matching",
    "pathway enrichment (FELLA / MetaboAnalyst)",
    "metabolic flux analysis",
  ],

  metagenomics: [
    "16S rRNA amplicon (DADA2 / QIIME2)",
    "shotgun metagenomics (Kraken2 / MetaPhlAn)",
    "metatranscriptomics",
    "MAG binning & assembly (CONCOCT)",
    "taxonomic profiling",
    "microbiome diversity analysis",
    "functional annotation (HUMAnN)",
  ],

  structural_biology: [
    "protein structure prediction (AlphaFold / Boltz / Chai-1)",
    "molecular docking (AutoDock Vina / DiffDock / Glide)",
    "molecular dynamics (GROMACS / AMBER)",
    "relative binding free energy (RBFE/FEP)",
    "X-ray crystallography",
    "protein-ligand interaction analysis",
  ],

  drug_discovery: [
    // Virtual screening & ligand design (drug_discovery DB domain)
    "virtual screening (Glide / AutoDock / DockString)",
    "ADMET prediction (hERG, DILI, Ames, physicochemical props)",
    "QSAR / machine learning on molecular data",
    "scaffold hopping & analogue design",
    "generative lead design (REINVENT4)",
    "retrosynthesis (AiZynthFinder)",
    "covalent warhead design",
    // PK / clinical (pharmacology DB domain — absorbed here)
    "PK/PD modeling & NCA (PKNCA / nlmixr2)",
    "PBPK simulation (Pk-Sim / Simcyp)",
    "population pharmacokinetics (NONMEM)",
    "allometric scaling & IVIVE",
    "BCS / oral absorption prediction",
    "CNS penetration prediction",
    "PBPK in special populations (paediatric / pregnancy)",
    // Regulatory / safety
    "FDA safety signal analysis",
    "pharmacogenomics (PGx / CYP2C19)",
    "drug repurposing (TxGNN)",
    "antibody / biologic design (ScFv, ADC, PROTAC, bispecific)",
    "clinical trial simulation & adaptive design",
  ],

  cryo_em: [
    // cryo_em DB domain (23 wf) + cryo_et DB domain (6 wf)
    "single-particle analysis (CryoSPARC / RELION)",
    "3D variability / conformational heterogeneity (cryoDRGN)",
    "focused refinement & particle subtraction",
    "helical reconstruction",
    "cryo-ET full pipeline",
    "subtomogram averaging",
    "tilt-series alignment & tomogram reconstruction",
    "global CTF refinement",
    "filament tracing",
  ],

  systems_biology: [
    "ODE / kinetic modeling (SBML)",
    "flux balance analysis (FBA / COBRA)",
    "gene regulatory network inference",
    "protein signaling network simulation",
    "Ras / dimerization ODE models",
    "renin-angiotensin system dynamics",
    "network analysis (Cytoscape)",
  ],

  synthetic_biology: [
    "gene circuit design & ODE simulation",
    "CRISPR design (sgRNA / knockout / knock-in)",
    "metabolic engineering & codon optimisation",
    "SBML network modelling",
    "barcode sequencing analysis",
    "bacterial growth rate analysis",
    "bifurcation diagram analysis",
  ],

  bioimaging: [
    // bioimaging (22 wf) + imaging (45 wf) merged
    "cell & nucleus segmentation (CellPose / StarDist / nnU-Net)",
    "fluorescence microscopy image analysis (ImageJ / Fiji)",
    "spatial transcriptomics imaging (MERSCOPE / Vizgen)",
    "spatial omics downstream analysis",
    "flow cytometry / FACS analysis",
    "confocal / live-cell image analysis",
    "cell counting & morphometry",
  ],

  lab_automation: [
    "liquid handling (Opentrons OT-2 / PyLabRobot)",
    "high-throughput screening (HTS) plate QC & hit calling",
    "plate reader data analysis",
    "LIMS & sample tracking",
    "robotic dispensing protocols",
    "Hamilton / Tecan / ECHO integration",
  ],

  // ── Routing-only domains with significant workflow coverage ───────────────

  immunology: [
    "flow cytometry / FACS immunophenotyping",
    "cytokine production analysis (CD4 T cells)",
    "cell proliferation (CFSE assay)",
    "immune cell tracking & motility",
    "ATAC-seq differential accessibility (immune cells)",
    "EBV antibody titers",
    "cell cycle phase duration modelling",
  ],

  cancer_biology: [
    "somatic mutation detection & annotation",
    "copy number / purity / ploidy analysis",
    "structural variation characterisation",
    "DDR network analysis",
    "cell senescence & apoptosis",
    "NMF gene expression analysis",
    "tumour growth inhibition (TGI / PhysiCell)",
  ],

  virtual_cell: [
    // virtual_cell DB domain (12 wf) — new in selector
    "gene perturbation prediction (GEARS, GPU)",
    "drug combination synergy (CPA / Synergy)",
    "transcriptomic mechanism of action (LINCS)",
    "cardiac safety ODE (CiPA)",
    "tumour growth ODE / PhysiCell",
    "metabolic flux FBA",
    "ODE signalling simulation",
    "cell state prediction (TranscriptFormer)",
    "virtual patient cohort",
  ],

  molecular_biology: [
    "primer & sgRNA design",
    "plasmid annotation & restriction site mapping",
    "Golden Gate / Gibson assembly design",
    "ORF finding & coding sequence extraction",
    "sequence mutation analysis",
    "PCR & gel electrophoresis simulation",
    "bacterial transformation protocol",
  ],

  cell_biology: [
    "cell cycle phase quantification (microscopy)",
    "mitochondrial morphology & potential",
    "cell motility & migration analysis",
    "flow cytometry cell sorting",
    "CRISPR screen phenotyping",
    "apoptosis & signalling assays",
  ],

  genetics: [
    "GWAS & fine-mapping (BayesVI)",
    "CRISPR genome editing outcome analysis (Cas9)",
    "transcription factor binding site identification",
    "genomic prediction modelling",
    "demographic history simulation",
    "coordinate liftover (genome build conversion)",
    "protein phylogeny analysis",
  ],

  microbiology: [
    "bacterial genome annotation",
    "bacterial growth dynamics (Lotka-Volterra / GLV)",
    "antimicrobial resistance analysis",
    "biofilm biomass quantification",
    "colony & CFU enumeration",
    "RNA secondary structure prediction",
    "microbial cell segmentation (deep learning)",
    "anaerobic digestion modelling",
  ],

  biochemistry: [
    "enzyme kinetics (Michaelis-Menten)",
    "ITC binding thermodynamics",
    "circular dichroism spectra analysis",
    "protease kinetics",
    "protein conservation analysis",
    "RNA secondary structure feature analysis",
    "dose-response curve fitting",
  ],

  physiology: [
    "ABR (auditory brainstem response) waveform analysis",
    "haemodynamic data analysis",
    "thyroid hormone pharmacokinetics (ODE)",
    "cosinor analysis (circadian rhythms)",
    "ciliary beat frequency analysis",
    "fatty acid composition (GC)",
    "endolysosomal calcium dynamics",
    "brain ADC map calculation (MRI)",
  ],

  bioengineering: [
    "calcium imaging data analysis",
    "cell migration & motility metrics",
    "in vitro drug release kinetics (Higuchi / Korsmeyer-Peppas)",
    "myofiber morphology analysis",
    "whole-cell ODE modelling",
    "neural trajectory decoding",
    "CRISPR-Cas9 genome editing",
  ],

  pathology: [
    "multiplexed cell quantification & segmentation",
    "thrombus histology analysis",
    "bone microCT morphometry",
    "aortic geometry & diameter analysis",
    "amyloid-β plaque quantification (MRI)",
    "corneal nerve fibre quantification",
    "ATP luminescence assay",
  ],

  structural_biology_xray: [], // placeholder — rolled into structural_biology above
}

// Remove placeholder
delete (DOMAIN_TAXONOMY as Record<string, string[]>)["structural_biology_xray"]

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
  cryo_em:           "Cryo-EM / Cryo-ET",
  systems_biology:   "Systems Biology",
  synthetic_biology: "Synthetic Biology",
  bioimaging:        "Bioimaging",
  lab_automation:    "Lab Automation",
  immunology:        "Immunology",
  cancer_biology:    "Cancer Biology",
  virtual_cell:      "Virtual Cell & Computational Biology",
  molecular_biology: "Molecular Biology",
  cell_biology:      "Cell Biology",
  genetics:          "Genetics",
  microbiology:      "Microbiology",
  biochemistry:      "Biochemistry",
  physiology:        "Physiology",
  bioengineering:    "Bioengineering",
  pathology:         "Pathology",
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

  // "Other" topic free-text per domain key
  const [otherTopicText, setOtherTopicText] = useState<Record<string, string>>({})

  // ── Domain toggle ──────────────────────────────────────────────────────────

  const toggleDomain = (key: string) => {
    setSelectedDomains(prev => {
      const next = new Set(prev)
      if (next.has(key)) {
        next.delete(key)
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
          Select all that apply — topics appear automatically. BioMate covers 36 domains and 2,600+ workflows.
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

      {/* Inline topic expansion — one section per selected domain */}
      {selectedDomainKeys.length > 0 && (
        <div className="space-y-4 border-t pt-4">
          <p className="text-sm text-muted-foreground">
            Refine by topic <span className="text-xs">(optional — select all that apply)</span>
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
