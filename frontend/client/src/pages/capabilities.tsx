import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { useLocation } from "wouter"
import { ArrowRight } from "lucide-react"

// ---------------------------------------------------------------------------
// Data
// ---------------------------------------------------------------------------

const jobClusters = [
  {
    title: "IND Package Preparation",
    description:
      "Take a candidate molecule from SMILES through the full IND data package: ADMET profiling, PBPK simulation, dose escalation modelling, and auto-generated §2.6 regulatory narrative ready for FDA submission.",
    workflows: [
      "Predict ADMET Properties",
      "pbpk_simulation",
      "clinical_trial_simulation",
      "IND §2.6 narrative",
    ],
  },
  {
    title: "Lead Optimization",
    description:
      "Identify hERG / DILI liabilities in your hit series, then use generative AI to decorate scaffolds and score optimized analogs against binding free energy predictions.",
    workflows: ["Predict ADMET", "REINVENT4", "OpenFE RBFE"],
  },
  {
    title: "Antibody-Drug Conjugate Design",
    description:
      "End-to-end ADC design across all 7 approved payload classes (MMAE, MMAF, DM1, DM4, SN-38, PBD, calicheamicin). Linker chemistry selection, DAR optimization, ADC-specific ADMET with bystander killing radius and off-target toxicity flags, plus two-analyte PK modeling.",
    workflows: ["adc_design", "antibody_developability", "scfv_antibody_design"],
  },
  {
    title: "Targeted Protein Degradation",
    description:
      "PROTAC and molecular glue design from target protein to optimized degrader. E3 ligase selection across CRBN, VHL, MDM2, IAP, DCAF15. POI warhead lookup for 25 named targets. Linker variants, beyond-Rule-of-Five ADMET, and ternary complex cooperativity scoring.",
    workflows: ["protac_design", "Predict ADMET Properties (AI)"],
  },
  {
    title: "Cell Therapy Construct Design",
    description:
      "CAR-T construct assembly from antigen target to complete protein sequence. 20-target scFv library covering CD19, BCMA, HER2, GD2, EGFR, MSLN, and more. Auto costimulatory domain selection (4-1BB or CD28), packaging size validation, and tonic signaling risk assessment.",
    workflows: ["cart_construct_design", "scfv_antibody_design", "bispecific_antibody_design"],
  },
  {
    title: "Cryo-EM Structure Solution",
    description:
      "Process raw movie stacks end-to-end: motion correction, CTF estimation, particle picking, 2-D / 3-D classification, and high-resolution reconstruction with density enhancement.",
    workflows: ["CryoSPARC SPA", "DeepEMhancer", "ModelAngelo (coming soon)"],
  },
  {
    title: "Rare Disease Translational Analysis",
    description:
      "Starting from whole-genome sequencing data, call variants with validated pipelines, identify candidate disease genes, query approved drugs for repurposing, and select the right AAV serotype for in vivo gene therapy delivery.",
    workflows: ["nf-core/raredisease", "patient_gene", "TxGNN repurposing", "aav_serotype_selection"],
  },
  {
    title: "Single-Cell Drug Mechanism",
    description:
      "Map drug mechanism of action at single-cell resolution: cluster scRNA-seq data, annotate cell states, and predict transcriptional responses to genetic or chemical perturbations.",
    workflows: [
      "Seurat / scdownstream",
      "STATE perturbation prediction",
      "GEARS",
    ],
  },
  {
    title: "RNA Therapeutic Design",
    description:
      "Design siRNA, ASO gapmer, and full mRNA therapeutic constructs against any target transcript. Includes codon optimization, UTR design, stability scoring, off-target screening, and LNP formulation tuned to delivery tissue.",
    workflows: [
      "mrna_therapeutic_design",
      "sirna_design_full",
      "aso_gapmer_design",
      "sirna_offtarget_analysis",
      "lnp_formulation_optimization",
    ],
  },
]


// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

export default function CapabilitiesPage() {
  const [, setLocation] = useLocation()

  return (
    <div className="min-h-screen bg-background">
      {/* Hero */}
      <section className="border-b bg-gradient-to-br from-blue-500/5 via-purple-500/5 to-pink-500/5">
        <div className="max-w-6xl mx-auto px-6 py-20 text-center space-y-4">
          <Badge variant="secondary" className="mb-2">Platform capabilities</Badge>
          <h1 className="text-4xl font-bold tracking-tight">
            What can BioMate do for you?
          </h1>
          <p className="text-lg text-muted-foreground max-w-2xl mx-auto">
            BioMate covers every major therapeutic modality in active
            clinical development — small molecule, antibody, ADC, mRNA, siRNA,
            ASO, CRISPR, CAR-T, PROTAC, and AAV gene therapy — in a single
            AI assistant. Below are the high-value use cases researchers run
            most often, and how BioMate compares to commercial software.
          </p>
          <Button
            className="mt-4"
            onClick={() => setLocation("/")}
          >
            Open the assistant <ArrowRight className="ml-2 h-4 w-4" />
          </Button>
        </div>
      </section>

      {/* Section 1 — job clusters */}
      <section className="max-w-6xl mx-auto px-6 py-16">
        <h2 className="text-2xl font-semibold mb-2">Use-case clusters</h2>
        <p className="text-muted-foreground mb-10">
          Each cluster is a complete job-to-be-done — start with a question in
          the chat interface and BioMate routes, parameterises, and executes
          the relevant workflows automatically.
        </p>

        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-5">
          {jobClusters.map((cluster) => (
            <Card key={cluster.title} className="flex flex-col">
              <CardHeader className="pb-2">
                <CardTitle className="text-base">{cluster.title}</CardTitle>
              </CardHeader>
              <CardContent className="flex flex-col gap-4 flex-1">
                <p className="text-sm text-muted-foreground leading-relaxed">
                  {cluster.description}
                </p>
                {/* Raw internal pipeline-name chips removed — capability is legible
                    through the plain-language cluster + the router, not an internal
                    workflow inventory (design-v2 no-inventory front door). */}
              </CardContent>
            </Card>
          ))}
        </div>
      </section>

      {/* Section 2 (BioMate-vs-commercial price table + "$1.5M+/year" claim)
          removed — competitor price comparisons and savings claims don't belong
          on the capability front door (design-v2 no-lying-labels / no-inventory). */}

      {/* CTA */}
      <section className="border-t">
        <div className="max-w-6xl mx-auto px-6 py-16 text-center space-y-4">
          <h2 className="text-2xl font-semibold">Ready to run your first analysis?</h2>
          <p className="text-muted-foreground">
            Describe your experiment in plain language and BioMate handles the
            rest — workflow selection, parameter extraction, and execution on
            BioMate's cloud compute.
          </p>
          <Button size="lg" onClick={() => setLocation("/")}>
            Start a new chat <ArrowRight className="ml-2 h-4 w-4" />
          </Button>
        </div>
      </section>
    </div>
  )
}
