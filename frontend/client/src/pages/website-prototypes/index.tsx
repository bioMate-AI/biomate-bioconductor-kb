/**
 * Design Preview Index — dev-only
 * Lists all website prototype variants with side-by-side comparison notes.
 */
import { useLocation } from "wouter"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { ExternalLink } from "lucide-react"

const VARIANTS = [
  {
    id: "a",
    name: "Variant A — Science-Forward",
    audience: "PI / senior researcher",
    lead: "Research outcomes, workflow catalog, publications",
    palette: "Dark (slate-950) + cyan accent",
    hero: "\"From research question to publication-ready results in under 30 minutes\"",
    strengths: [
      "Leads with credibility (published papers, cited standards)",
      "Shows actual workflow output (not marketing copy)",
      "Domain catalog with workflow count builds confidence",
      "Dark theme signals technical sophistication"
    ],
    tradeoffs: [
      "May feel cold to non-technical decision makers",
      "No pricing visible above fold"
    ],
    path: "/design-preview/a"
  },
  {
    id: "b",
    name: "Variant B — Product-Forward",
    audience: "Lab manager / department head",
    lead: "Speed, cost reduction, pain point elimination",
    palette: "White + blue-600 accent",
    hero: "\"Stop waiting for your bioinformatician\"",
    strengths: [
      "Pain-led: immediately resonates with bottlenecked labs",
      "Interactive pain-point switcher creates engagement",
      "Pricing visible — reduces friction for buyer evaluation",
      "Stats row (87%, 23 min) provides quick-scan proof points"
    ],
    tradeoffs: [
      "May feel too commercial for academic audiences",
      "Pain-led framing could alienate bioinformaticians (potential champions)"
    ],
    path: "/design-preview/b"
  },
  {
    id: "c",
    name: "Variant C — Trust/Compliance-Forward",
    audience: "IT security / clinical research director / pharma procurement",
    lead: "Data governance, compliance badges, institutional controls",
    palette: "White/slate + emerald accents for compliance status",
    hero: "\"AI bioinformatics your compliance team can approve\"",
    strengths: [
      "Directly addresses enterprise procurement blockers",
      "Compliance checklist panel signals institutional readiness",
      "FAQ section pre-empts security objections",
      "Private deployment option differentiates vs. SaaS-only competitors"
    ],
    tradeoffs: [
      "Slower to excite non-compliance readers",
      "Requires keeping compliance status current (badges must stay accurate)"
    ],
    path: "/design-preview/c"
  }
]

export default function DesignPreviewIndex() {
  const [, setLocation] = useLocation()

  return (
    <div className="min-h-screen bg-slate-950 text-white p-8">
      <div className="max-w-6xl mx-auto">
        {/* Header */}
        <div className="mb-10">
          <div className="flex items-center gap-3 mb-2">
            <Badge className="bg-amber-500/20 text-amber-400 border-amber-500/30 text-xs">DEV ONLY</Badge>
            <span className="text-slate-500 text-sm">not accessible in production</span>
          </div>
          <h1 className="text-3xl font-bold mb-3">BioMate Website Design Prototypes</h1>
          <p className="text-slate-400 max-w-2xl">
            Three landing page variants for comparative evaluation. Each targets a different primary audience and leads with a different value proposition. Use these to test messaging resonance with pilot study participants before choosing a direction.
          </p>
        </div>

        {/* Variants */}
        <div className="space-y-6">
          {VARIANTS.map((v) => (
            <div key={v.id} className="bg-slate-900 border border-slate-800 rounded-2xl overflow-hidden">
              <div className="p-6 grid md:grid-cols-3 gap-6">
                {/* Left: identity */}
                <div>
                  <div className="flex items-center gap-2 mb-1">
                    <div className="w-6 h-6 rounded-full bg-slate-700 flex items-center justify-center text-xs font-bold">{v.id.toUpperCase()}</div>
                    <span className="font-semibold text-white">{v.name}</span>
                  </div>
                  <div className="text-xs text-slate-400 mb-3">Audience: <span className="text-slate-300">{v.audience}</span></div>
                  <div className="text-xs text-slate-500 mb-1">Lead message:</div>
                  <div className="text-sm text-slate-300 italic mb-3">{v.hero}</div>
                  <div className="text-xs text-slate-500">Palette: {v.palette}</div>
                </div>

                {/* Middle: strengths */}
                <div>
                  <div className="text-xs font-medium text-emerald-400 uppercase tracking-wider mb-2">Strengths</div>
                  <ul className="space-y-1">
                    {v.strengths.map((s, i) => (
                      <li key={i} className="text-xs text-slate-300 flex gap-2">
                        <span className="text-emerald-500 flex-shrink-0">+</span>{s}
                      </li>
                    ))}
                  </ul>
                  <div className="text-xs font-medium text-amber-400 uppercase tracking-wider mb-2 mt-3">Trade-offs</div>
                  <ul className="space-y-1">
                    {v.tradeoffs.map((t, i) => (
                      <li key={i} className="text-xs text-slate-400 flex gap-2">
                        <span className="text-amber-500 flex-shrink-0">−</span>{t}
                      </li>
                    ))}
                  </ul>
                </div>

                {/* Right: open */}
                <div className="flex flex-col justify-between">
                  <div className="text-xs text-slate-500 mb-4">Lead value: <span className="text-slate-300">{v.lead}</span></div>
                  <Button
                    className="bg-slate-800 hover:bg-slate-700 text-white border border-slate-700 w-full"
                    onClick={() => setLocation(v.path)}
                  >
                    Open Variant {v.id.toUpperCase()} <ExternalLink className="ml-2 h-3 w-3" />
                  </Button>
                </div>
              </div>
            </div>
          ))}
        </div>

        {/* Notes */}
        <div className="mt-10 p-6 bg-slate-900 border border-slate-800 rounded-xl">
          <div className="text-sm font-medium text-slate-300 mb-3">Evaluation notes</div>
          <div className="text-sm text-slate-400 space-y-2">
            <p>• Show Variant A to 3–5 academic pilot study participants. Ask: "Does this reflect your workflow?"</p>
            <p>• Show Variant B to 3–5 lab managers / department heads. Ask: "Does this resonate with a pain you have?"</p>
            <p>• Show Variant C to 1–2 IT/compliance contacts. Ask: "What's missing from a procurement perspective?"</p>
            <p>• Competitive analysis in <code className="bg-slate-800 px-1 py-0.5 rounded text-xs">docs/20260412_WEBSITE_COMPETITIVE_ANALYSIS.md</code></p>
          </div>
        </div>
      </div>
    </div>
  )
}
