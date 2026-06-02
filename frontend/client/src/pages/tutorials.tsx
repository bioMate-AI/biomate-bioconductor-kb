import { useEffect } from "react"
import { useLocation } from "wouter"
import { Button } from "@/components/ui/button"

const VIDEOS = [
  {
    id: "bpG0IWrwN5g",
    title: "BioMate — The AI Lab Platform for Life Sciences",
    description:
      "An overview of BioMate — the AI-native lab platform that turns complex bioinformatics pipelines into a conversation. From raw data to publication-ready outputs, all without writing code.",
  },
  {
    id: "C4gQD-xbHnQ",
    title: "Multi-step Workflow Automation with Quality Control",
    description:
      "See BioMate run a CryoSPARC single-particle analysis end to end — 5 phases, 23 steps, live QC gates, auto-loop remediation, and per-step output previews, all submitted to AWS Batch GPUs from a single chat message.",
  },
  {
    id: "F2DgmBa5gq8",
    title: "After Run Report — Reproducibility in One Click",
    description:
      "Every completed BioMate run generates a structured 7-tab report: Findings, Outputs, Methods, Parameters, Software, Citations, and QC Audit. Download as DOCX, Markdown, or LaTeX — manuscript-ready without copy-paste.",
  },
  {
    id: "IDcICWmB0Oo",
    title: "IND Report — Automated Section 2.6 Nonclinical Dossier with 21 CFR Part 11 Sign-Off",
    description:
      "A five-step pipeline — ADMET profiling, PBPK modeling, lead prioritization, and LLM-generated regulatory prose — builds an IND-quality section 2.6 dossier. The live document panel updates in place as each step completes, with a full 21 CFR Part 11 sign-and-freeze at the end.",
  },
]

export default function TutorialsPage() {
  const [, setLocation] = useLocation()

  useEffect(() => {
    const prev = document.title
    document.title = "Tutorials | BioMate AI"

    let meta = document.querySelector('meta[name="description"]') as HTMLMetaElement | null
    const created = !meta
    if (!meta) {
      meta = document.createElement("meta")
      meta.setAttribute("name", "description")
      document.head.appendChild(meta)
    }
    const prevContent = meta.getAttribute("content") ?? ""
    meta.setAttribute(
      "content",
      "Step-by-step video tutorials for BioMate AI — CryoSPARC SPA, drug screening auto-loop, IND report generation, and reproducible after-run reports for life science research."
    )

    return () => {
      document.title = prev
      if (meta) {
        if (created) meta.remove()
        else meta.setAttribute("content", prevContent)
      }
    }
  }, [])

  return (
    <div className="min-h-screen bg-background">
      {/* Hero */}
      <section className="relative overflow-hidden border-b">
        <div className="absolute inset-0 bg-gradient-to-br from-blue-500/10 via-purple-500/10 to-pink-500/10" />
        <div className="relative max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-20">
          <div className="text-center space-y-4">
            <h1 className="text-5xl font-bold">
              Tutorials
            </h1>
            <p className="text-xl text-muted-foreground max-w-2xl mx-auto">
              Watch BioMate in action — step-by-step demos for each key workflow.
            </p>
          </div>
        </div>
      </section>

      {/* Video grid */}
      <section className="py-16">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-10">
            {VIDEOS.map((v) => (
              <div key={v.id} className="flex flex-col gap-4">
                <div className="relative w-full rounded-xl overflow-hidden border shadow-sm bg-black"
                     style={{ paddingBottom: "56.25%" }}>
                  <iframe
                    className="absolute inset-0 w-full h-full"
                    src={`https://www.youtube.com/embed/${v.id}?rel=0`}
                    title={v.title}
                    allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
                    allowFullScreen
                  />
                </div>
                <div>
                  <h2 className="text-lg font-semibold leading-snug mb-1">{v.title}</h2>
                  <p className="text-sm text-muted-foreground leading-relaxed">{v.description}</p>
                </div>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* CTA */}
      <section className="py-16 border-t">
        <div className="max-w-3xl mx-auto px-4 sm:px-6 lg:px-8 text-center">
          <h2 className="text-3xl font-bold mb-3">Ready to run your own analysis?</h2>
          <p className="text-muted-foreground mb-8">
            Start free — no credit card required.
          </p>
          <div className="flex flex-col sm:flex-row gap-4 justify-center">
            <Button size="lg" onClick={() => setLocation("/register")}>
              Start Free Trial
            </Button>
            <Button size="lg" variant="outline" onClick={() => setLocation("/about")}>
              Learn More
            </Button>
          </div>
        </div>
      </section>
    </div>
  )
}
