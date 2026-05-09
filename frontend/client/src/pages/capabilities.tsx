import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"
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
    title: "Cryo-EM Structure Solution",
    description:
      "Process raw movie stacks end-to-end: motion correction, CTF estimation, particle picking, 2-D / 3-D classification, and high-resolution reconstruction with density enhancement.",
    workflows: ["CryoSPARC SPA", "DeepEMhancer", "ModelAngelo (coming soon)"],
  },
  {
    title: "Rare Disease Translational Analysis",
    description:
      "Starting from whole-genome sequencing data, call variants with clinical-grade pipelines, identify candidate disease genes, and query approved drugs for repurposing opportunities.",
    workflows: ["nf-core/raredisease", "patient_gene", "TxGNN repurposing"],
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
      "Design siRNA candidates against any target transcript, screen off-target activity across the transcriptome, and optimise LNP formulation parameters for in-vivo delivery.",
    workflows: [
      "siRNA Design",
      "sirna_offtarget_analysis",
      "lnp_formulation_optimization",
    ],
  },
]

const comparisonRows = [
  {
    capability: "Relative binding free energy",
    biomate: "OpenFE RBFE",
    commercial: "Schrödinger FEP+",
    price: "~$100K+/year",
  },
  {
    capability: "Population PK modeling",
    biomate: "nlmixr2_population_pk",
    commercial: "NONMEM (Icon)",
    price: "~$30K/year",
  },
  {
    capability: "PBPK simulation",
    biomate: "simcyp_pbpk / pk_sim_pbpk",
    commercial: "Simulations Plus SimCYP",
    price: "~$40K/year",
  },
  {
    capability: "Generative lead design",
    biomate: "REINVENT4",
    commercial: "Schrödinger REINVENT",
    price: "~$80K/year",
  },
  {
    capability: "ADMET prediction",
    biomate: "Predict ADMET Properties (AI)",
    commercial: "StarDrop (Optibrium)",
    price: "~$20K/year",
  },
  {
    capability: "Adaptive trial design",
    biomate: "adaptive_trial_design",
    commercial: "East Adaptive (Cytel)",
    price: "~$25K/year",
  },
  {
    capability: "Drug repurposing",
    biomate: "TxGNN Repurposing",
    commercial: "CRO engagement",
    price: "~$50K/project",
  },
  {
    capability: "Cryo-EM reconstruction",
    biomate: "CryoSPARC SPA",
    commercial: "CryoSPARC license",
    price: "~$8K/year",
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
            BioMate connects 2,400+ bioinformatics workflows under a single
            AI assistant. Below are the high-value use cases researchers run
            most often, and how BioMate compares to the commercial software it
            replaces.
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
                <div className="mt-auto flex flex-wrap gap-1.5">
                  {cluster.workflows.map((wf) => (
                    <Badge key={wf} variant="outline" className="text-xs font-normal">
                      {wf}
                    </Badge>
                  ))}
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      </section>

      {/* Section 2 — comparison table */}
      <section className="border-t bg-muted/30">
        <div className="max-w-6xl mx-auto px-6 py-16">
          <h2 className="text-2xl font-semibold mb-2">
            BioMate vs. commercial software
          </h2>
          <p className="text-muted-foreground mb-8">
            BioMate runs the same underlying algorithms as the leading
            commercial suites — without per-seat licensing fees.
          </p>

          <div className="rounded-lg border overflow-hidden">
            <Table>
              <TableHeader>
                <TableRow className="bg-muted/50">
                  <TableHead className="font-semibold">Capability</TableHead>
                  <TableHead className="font-semibold">BioMate workflow</TableHead>
                  <TableHead className="font-semibold">Commercial alternative</TableHead>
                  <TableHead className="font-semibold text-right">Commercial price</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {comparisonRows.map((row, i) => (
                  <TableRow key={i}>
                    <TableCell className="font-medium">{row.capability}</TableCell>
                    <TableCell>
                      <Badge variant="secondary" className="font-mono text-xs font-normal">
                        {row.biomate}
                      </Badge>
                    </TableCell>
                    <TableCell className="text-muted-foreground">{row.commercial}</TableCell>
                    <TableCell className="text-right text-muted-foreground">{row.price}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>

          <p className="mt-5 text-sm font-semibold">
            Estimated stack replacement value: $353K+/year
          </p>
          <p className="mt-1 text-xs text-muted-foreground">
            Prices are public list prices as of 2025. Actual enterprise discounts vary.
          </p>
        </div>
      </section>

      {/* CTA */}
      <section className="border-t">
        <div className="max-w-6xl mx-auto px-6 py-16 text-center space-y-4">
          <h2 className="text-2xl font-semibold">Ready to run your first analysis?</h2>
          <p className="text-muted-foreground">
            Describe your experiment in plain language and BioMate handles the
            rest — workflow selection, parameter extraction, and execution on
            AWS Batch.
          </p>
          <Button size="lg" onClick={() => setLocation("/")}>
            Start a new chat <ArrowRight className="ml-2 h-4 w-4" />
          </Button>
        </div>
      </section>
    </div>
  )
}
