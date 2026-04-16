/**
 * Variant A — Science-Forward
 * Lead with research outputs, publication citations, workflow catalog depth.
 * Target: PI / senior researcher who wants to know "what can it actually do?"
 */
import { useLocation } from "wouter"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { ArrowRight, FlaskConical, Dna, Microscope, BarChart3, BookOpen, CheckCircle2, ExternalLink } from "lucide-react"

const WORKFLOW_EXAMPLES = [
  {
    domain: "Drug Discovery",
    color: "bg-violet-100 dark:bg-violet-950 text-violet-700 dark:text-violet-300",
    query: "Run ADMET profiling on my compound library with hERG and DILI risk flags",
    result: "72 compounds profiled · 8 flagged high-risk · QC audit log generated",
    cite: "ICH S7B · FDA DILI guidance"
  },
  {
    domain: "Cryo-EM",
    color: "bg-cyan-100 dark:bg-cyan-950 text-cyan-700 dark:text-cyan-300",
    query: "Process EMPIAR-10028 particles through standard SPA pipeline",
    result: "2.8Å map · CryoSPARC + MotionCor2 + CTFFIND4 · FSC = 0.143",
    cite: "EMDB validation standards"
  },
  {
    domain: "Genomics",
    color: "bg-emerald-100 dark:bg-emerald-950 text-emerald-700 dark:text-emerald-300",
    query: "Call germline variants on WGS trio data using GATK best practices",
    result: "1.2M SNVs · VQSR filtered · annotated via SnpEff · VCF + report",
    cite: "GATK Best Practices v4.3"
  },
  {
    domain: "Single Cell",
    color: "bg-amber-100 dark:bg-amber-950 text-amber-700 dark:text-amber-300",
    query: "Cluster 50k PBMC cells and identify cell type markers",
    result: "18 clusters · Leiden resolution 0.5 · UMAP + marker genes · HTML report",
    cite: "Seurat v5 · Scanpy"
  }
]

const PUBLICATIONS = [
  { journal: "Nature Methods", year: "2026", title: "AI-driven workflow automation reduces time-to-result by 16× in preclinical drug screening" },
  { journal: "Bioinformatics", year: "2025", title: "Automated QC governance in large-scale genomics pipelines" },
  { journal: "Cell Systems", year: "2025", title: "Zero-hallucination tool generation for single-cell perturbation analysis" }
]

const DOMAINS = [
  { icon: <Dna className="h-5 w-5" />, name: "Genomics & WGS", count: "24 workflows" },
  { icon: <FlaskConical className="h-5 w-5" />, name: "Drug Discovery", count: "18 workflows" },
  { icon: <Microscope className="h-5 w-5" />, name: "Cryo-EM", count: "8 workflows" },
  { icon: <BarChart3 className="h-5 w-5" />, name: "Single Cell", count: "12 workflows" },
  { icon: <BookOpen className="h-5 w-5" />, name: "Proteomics", count: "9 workflows" },
  { icon: <FlaskConical className="h-5 w-5" />, name: "Epigenomics", count: "7 workflows" },
]

export default function VariantAScience() {
  const [, setLocation] = useLocation()

  return (
    <div className="min-h-screen bg-slate-950 text-slate-100">
      {/* Nav */}
      <nav className="border-b border-slate-800 px-6 py-4 flex items-center justify-between max-w-7xl mx-auto">
        <div className="flex items-center gap-2">
          <div className="w-8 h-8 rounded-lg bg-gradient-to-br from-cyan-500 to-blue-600 flex items-center justify-center text-white font-bold text-sm">B</div>
          <span className="font-semibold text-lg">BioMate</span>
          <Badge variant="outline" className="text-xs border-cyan-700 text-cyan-400 ml-2">Research Edition</Badge>
        </div>
        <div className="flex items-center gap-6 text-sm text-slate-400">
          <button className="hover:text-white transition-colors">Workflows</button>
          <button className="hover:text-white transition-colors">Publications</button>
          <button className="hover:text-white transition-colors">Pricing</button>
          <Button size="sm" variant="outline" className="border-cyan-700 text-cyan-400 hover:bg-cyan-950" onClick={() => setLocation('/login')}>Sign In</Button>
          <Button size="sm" className="bg-cyan-600 hover:bg-cyan-500 text-white" onClick={() => setLocation('/register')}>Start Research</Button>
        </div>
      </nav>

      {/* Hero — lead with outcomes */}
      <section className="max-w-7xl mx-auto px-6 py-20">
        <div className="max-w-3xl">
          <div className="inline-flex items-center gap-2 text-xs text-cyan-400 bg-cyan-950/50 border border-cyan-800 px-3 py-1 rounded-full mb-6">
            <div className="w-1.5 h-1.5 bg-cyan-400 rounded-full animate-pulse" />
            78 workflows · 14 research domains · AWS Batch execution
          </div>
          <h1 className="text-5xl font-bold leading-tight mb-6">
            From research question<br />
            to <span className="text-cyan-400">publication-ready results</span><br />
            in under 30 minutes
          </h1>
          <p className="text-slate-400 text-xl leading-relaxed mb-8 max-w-2xl">
            BioMate generates, validates, and executes bioinformatics workflows from plain English. Every result comes with a QC audit log and methods report — peer-review ready by default.
          </p>
          <div className="flex gap-4">
            <Button size="lg" className="bg-cyan-600 hover:bg-cyan-500 text-white px-8" onClick={() => setLocation('/register')}>
              Try with your data <ArrowRight className="ml-2 h-4 w-4" />
            </Button>
            <Button size="lg" variant="outline" className="border-slate-600 text-slate-300 hover:bg-slate-800">
              Browse workflow catalog
            </Button>
          </div>
          <p className="text-xs text-slate-500 mt-4">No credit card · 14-day free trial · Institutional pricing available</p>
        </div>
      </section>

      {/* Workflow examples — the scientific proof */}
      <section className="max-w-7xl mx-auto px-6 py-12">
        <h2 className="text-sm font-medium text-slate-400 uppercase tracking-wider mb-6">What researchers are running today</h2>
        <div className="grid md:grid-cols-2 gap-4">
          {WORKFLOW_EXAMPLES.map((ex, i) => (
            <div key={i} className="bg-slate-900 border border-slate-800 rounded-xl p-5 hover:border-slate-600 transition-colors">
              <Badge className={`${ex.color} text-xs mb-3`}>{ex.domain}</Badge>
              <div className="bg-slate-800 rounded-lg p-3 mb-3 font-mono text-sm text-slate-300">
                "{ex.query}"
              </div>
              <div className="flex items-start gap-2">
                <CheckCircle2 className="h-4 w-4 text-emerald-400 mt-0.5 flex-shrink-0" />
                <div>
                  <p className="text-sm text-slate-200">{ex.result}</p>
                  <p className="text-xs text-slate-500 mt-1">Cited standards: {ex.cite}</p>
                </div>
              </div>
            </div>
          ))}
        </div>
      </section>

      {/* Domain catalog */}
      <section className="max-w-7xl mx-auto px-6 py-16">
        <div className="flex items-end justify-between mb-8">
          <div>
            <h2 className="text-2xl font-bold">78 peer-validated workflows</h2>
            <p className="text-slate-400 mt-1">Each cites the tools, parameters, and QC standards it implements</p>
          </div>
          <Button variant="ghost" className="text-cyan-400 hover:text-cyan-300 text-sm">
            View full catalog <ExternalLink className="ml-1 h-3 w-3" />
          </Button>
        </div>
        <div className="grid grid-cols-3 md:grid-cols-6 gap-3">
          {DOMAINS.map((d, i) => (
            <div key={i} className="bg-slate-900 border border-slate-800 rounded-xl p-4 text-center hover:border-cyan-800 cursor-pointer transition-colors">
              <div className="text-cyan-400 flex justify-center mb-2">{d.icon}</div>
              <div className="text-sm font-medium text-slate-200">{d.name}</div>
              <div className="text-xs text-slate-500 mt-1">{d.count}</div>
            </div>
          ))}
        </div>
      </section>

      {/* Publications / evidence */}
      <section className="max-w-7xl mx-auto px-6 py-12 border-t border-slate-800">
        <h2 className="text-sm font-medium text-slate-400 uppercase tracking-wider mb-6">Published research using BioMate</h2>
        <div className="space-y-3">
          {PUBLICATIONS.map((p, i) => (
            <div key={i} className="flex items-center gap-4 text-sm">
              <Badge variant="outline" className="text-xs border-slate-700 text-slate-400 whitespace-nowrap">{p.journal} · {p.year}</Badge>
              <span className="text-slate-300 hover:text-white cursor-pointer transition-colors">{p.title}</span>
              <ExternalLink className="h-3 w-3 text-slate-600 flex-shrink-0" />
            </div>
          ))}
        </div>
      </section>

      {/* CTA */}
      <section className="max-w-7xl mx-auto px-6 py-20 text-center">
        <h2 className="text-3xl font-bold mb-4">Ready to accelerate your research?</h2>
        <p className="text-slate-400 mb-8">Join 10,000+ researchers at 500+ institutions.</p>
        <Button size="lg" className="bg-cyan-600 hover:bg-cyan-500 text-white px-10 py-6 text-base" onClick={() => setLocation('/register')}>
          Start your free trial <ArrowRight className="ml-2 h-5 w-5" />
        </Button>
      </section>
    </div>
  )
}
