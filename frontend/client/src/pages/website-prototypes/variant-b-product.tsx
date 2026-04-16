/**
 * Variant B — Product-Forward
 * Lead with speed, automation, and cost reduction. Pain-point messaging.
 * Target: Lab manager / department head who owns the budget and timeline.
 */
import { useState } from "react"
import { useLocation } from "wouter"
import { Button } from "@/components/ui/button"
import { ArrowRight, Clock, DollarSign, Zap, RefreshCw, ChevronRight, Timer, TrendingDown, Users } from "lucide-react"

const PAIN_POINTS = [
  {
    before: "Wait 3 days for your bioinformatician to run the pipeline",
    after: "Results in 30 minutes — run it yourself",
    icon: <Clock className="h-5 w-5" />,
    metric: "16×",
    metricLabel: "faster"
  },
  {
    before: "Hire a $120k/yr bioinformatics engineer for routine analyses",
    after: "Any lab member runs publication-ready workflows",
    icon: <DollarSign className="h-5 w-5" />,
    metric: "$0",
    metricLabel: "engineering overhead"
  },
  {
    before: "Manually configure containers, cloud queues, and reference genomes",
    after: "Type a sentence. BioMate handles the rest.",
    icon: <Zap className="h-5 w-5" />,
    metric: "0",
    metricLabel: "lines of code"
  },
  {
    before: "Pipeline fails at step 7. Two hours of debugging.",
    after: "Auto-fix detects and resolves failures automatically",
    icon: <RefreshCw className="h-5 w-5" />,
    metric: "87%",
    metricLabel: "auto-resolved"
  }
]

const STEPS = [
  { n: "1", label: "Describe your analysis", detail: "Plain English. No syntax. \"Run differential expression on my RNA-seq data comparing tumor vs normal\"" },
  { n: "2", label: "BioMate builds the workflow", detail: "AI selects tools, fills parameters, validates prerequisites — in seconds" },
  { n: "3", label: "Review and launch", detail: "One-click execution on AWS Batch. No cloud config needed." },
  { n: "4", label: "Download results + methods report", detail: "QC audit log, figures, and a publication-ready methods section — automatically generated" }
]

const LOGOS = ["Stanford", "MIT", "Pfizer", "Genentech", "St. Jude", "UCSF", "Mayo Clinic", "Broad Institute"]

const PRICING_PREVIEW = [
  { plan: "Researcher", price: "$29", per: "/month", cta: "Start free trial", highlight: false, features: ["Unlimited workflows", "5 concurrent jobs", "QC audit logs", "Email support"] },
  { plan: "Lab", price: "$149", per: "/month", cta: "Start free trial", highlight: true, features: ["Everything in Researcher", "10 users", "Priority queue", "Slack notifications", "Phone support"] },
  { plan: "Institution", price: "Custom", per: "", cta: "Contact us", highlight: false, features: ["Unlimited users", "Private cloud deploy", "SSO / SAML", "SLA guarantee", "Dedicated CSM"] }
]

export default function VariantBProduct() {
  const [, setLocation] = useLocation()
  const [activePain, setActivePain] = useState(0)

  return (
    <div className="min-h-screen bg-white dark:bg-slate-950">
      {/* Nav */}
      <nav className="border-b px-6 py-4 flex items-center justify-between max-w-7xl mx-auto">
        <div className="flex items-center gap-2">
          <div className="w-8 h-8 rounded-lg bg-gradient-to-br from-blue-600 to-purple-600 flex items-center justify-center text-white font-bold text-sm">B</div>
          <span className="font-semibold text-lg text-slate-900 dark:text-white">BioMate</span>
        </div>
        <div className="flex items-center gap-8 text-sm text-slate-600 dark:text-slate-400">
          <button className="hover:text-slate-900 dark:hover:text-white transition-colors">Product</button>
          <button className="hover:text-slate-900 dark:hover:text-white transition-colors">Pricing</button>
          <button className="hover:text-slate-900 dark:hover:text-white transition-colors">Case Studies</button>
          <Button size="sm" variant="ghost" onClick={() => setLocation('/login')}>Sign In</Button>
          <Button size="sm" className="bg-blue-600 hover:bg-blue-700 text-white" onClick={() => setLocation('/register')}>
            Free Trial <ArrowRight className="ml-1 h-3 w-3" />
          </Button>
        </div>
      </nav>

      {/* Hero — pain-led */}
      <section className="max-w-7xl mx-auto px-6 py-24 text-center">
        <div className="inline-flex items-center gap-2 text-sm text-blue-600 bg-blue-50 dark:bg-blue-950 border border-blue-200 dark:border-blue-800 px-4 py-2 rounded-full mb-8">
          <Timer className="h-4 w-4" /> Average time to result: <strong>23 minutes</strong>
        </div>
        <h1 className="text-6xl font-extrabold text-slate-900 dark:text-white leading-tight mb-6 max-w-4xl mx-auto">
          Stop waiting for your<br />
          <span className="text-transparent bg-clip-text bg-gradient-to-r from-blue-600 to-purple-600">bioinformatician</span>
        </h1>
        <p className="text-xl text-slate-500 dark:text-slate-400 max-w-2xl mx-auto mb-10">
          BioMate runs any genomics, drug discovery, or structural biology analysis in minutes — from a plain English description. No coding. No cloud expertise. No waiting.
        </p>
        <div className="flex gap-4 justify-center">
          <Button size="lg" className="bg-blue-600 hover:bg-blue-700 text-white px-8 py-6 text-base rounded-xl shadow-xl shadow-blue-500/20" onClick={() => setLocation('/register')}>
            Start free — no card needed <ArrowRight className="ml-2 h-5 w-5" />
          </Button>
          <Button size="lg" variant="outline" className="px-8 py-6 text-base rounded-xl border-2" onClick={() => setLocation('/home')}>
            Watch 3-min demo
          </Button>
        </div>

        {/* Trust logos */}
        <div className="mt-16">
          <p className="text-sm text-slate-400 mb-6">Trusted by researchers at</p>
          <div className="flex flex-wrap gap-8 justify-center items-center">
            {LOGOS.map((l, i) => (
              <span key={i} className="text-slate-300 dark:text-slate-600 font-semibold text-sm tracking-wide">{l}</span>
            ))}
          </div>
        </div>
      </section>

      {/* Pain-point switcher */}
      <section className="bg-slate-50 dark:bg-slate-900 py-20">
        <div className="max-w-7xl mx-auto px-6">
          <h2 className="text-3xl font-bold text-center text-slate-900 dark:text-white mb-4">
            The old way is costing you time and money
          </h2>
          <p className="text-center text-slate-500 dark:text-slate-400 mb-12">Click to see how BioMate changes each bottleneck</p>

          <div className="grid lg:grid-cols-4 gap-4 mb-8">
            {PAIN_POINTS.map((p, i) => (
              <button
                key={i}
                onClick={() => setActivePain(i)}
                className={`text-left p-4 rounded-xl border-2 transition-all ${activePain === i ? 'border-blue-500 bg-white dark:bg-slate-800 shadow-lg' : 'border-slate-200 dark:border-slate-700 hover:border-slate-300 dark:hover:border-slate-600'}`}
              >
                <div className={`${activePain === i ? 'text-blue-600' : 'text-slate-400'} mb-3`}>{p.icon}</div>
                <div className="text-2xl font-bold text-blue-600">{p.metric}</div>
                <div className="text-xs text-slate-500 dark:text-slate-400">{p.metricLabel}</div>
              </button>
            ))}
          </div>

          <div className="bg-white dark:bg-slate-800 rounded-2xl border border-slate-200 dark:border-slate-700 p-8 grid md:grid-cols-2 gap-8 items-center">
            <div className="space-y-4">
              <div className="flex items-start gap-3">
                <div className="w-6 h-6 rounded-full bg-red-100 dark:bg-red-950 text-red-500 flex items-center justify-center text-xs flex-shrink-0 mt-0.5">✕</div>
                <div>
                  <div className="text-xs font-medium text-red-500 uppercase tracking-wider mb-1">Before BioMate</div>
                  <p className="text-slate-700 dark:text-slate-300">{PAIN_POINTS[activePain].before}</p>
                </div>
              </div>
            </div>
            <div className="space-y-4">
              <div className="flex items-start gap-3">
                <div className="w-6 h-6 rounded-full bg-emerald-100 dark:bg-emerald-950 text-emerald-500 flex items-center justify-center text-xs flex-shrink-0 mt-0.5">✓</div>
                <div>
                  <div className="text-xs font-medium text-emerald-500 uppercase tracking-wider mb-1">With BioMate</div>
                  <p className="text-slate-700 dark:text-slate-300 font-medium">{PAIN_POINTS[activePain].after}</p>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* How it works */}
      <section className="max-w-7xl mx-auto px-6 py-20">
        <h2 className="text-3xl font-bold text-center text-slate-900 dark:text-white mb-16">Four steps from question to results</h2>
        <div className="grid md:grid-cols-4 gap-8">
          {STEPS.map((s, i) => (
            <div key={i} className="relative">
              {i < STEPS.length - 1 && (
                <ChevronRight className="hidden md:block absolute -right-4 top-5 text-slate-300 dark:text-slate-600 h-8 w-8 z-10" />
              )}
              <div className="w-10 h-10 rounded-full bg-blue-600 text-white flex items-center justify-center font-bold mb-4">{s.n}</div>
              <h3 className="font-semibold text-slate-900 dark:text-white mb-2">{s.label}</h3>
              <p className="text-sm text-slate-500 dark:text-slate-400">{s.detail}</p>
            </div>
          ))}
        </div>
      </section>

      {/* Stats row */}
      <section className="bg-blue-600 py-14">
        <div className="max-w-7xl mx-auto px-6 grid grid-cols-3 gap-8 text-center text-white">
          {[
            { icon: <TrendingDown className="h-6 w-6 mx-auto mb-2 opacity-80" />, value: "87%", label: "of failures auto-resolved" },
            { icon: <Timer className="h-6 w-6 mx-auto mb-2 opacity-80" />, value: "23 min", label: "average time to result" },
            { icon: <Users className="h-6 w-6 mx-auto mb-2 opacity-80" />, value: "10,000+", label: "researchers trust BioMate" }
          ].map((s, i) => (
            <div key={i}>
              {s.icon}
              <div className="text-4xl font-extrabold">{s.value}</div>
              <div className="text-blue-200 text-sm mt-1">{s.label}</div>
            </div>
          ))}
        </div>
      </section>

      {/* Pricing preview */}
      <section className="max-w-7xl mx-auto px-6 py-20">
        <h2 className="text-3xl font-bold text-center text-slate-900 dark:text-white mb-4">Simple, transparent pricing</h2>
        <p className="text-center text-slate-500 dark:text-slate-400 mb-12">Start free. Upgrade when you're ready.</p>
        <div className="grid md:grid-cols-3 gap-6">
          {PRICING_PREVIEW.map((p, i) => (
            <div key={i} className={`rounded-2xl border-2 p-8 ${p.highlight ? 'border-blue-500 shadow-xl shadow-blue-500/10 relative' : 'border-slate-200 dark:border-slate-700'}`}>
              {p.highlight && <div className="absolute -top-3 left-1/2 -translate-x-1/2 bg-blue-600 text-white text-xs px-3 py-1 rounded-full font-medium">Most popular</div>}
              <div className="text-xl font-bold text-slate-900 dark:text-white mb-1">{p.plan}</div>
              <div className="flex items-end gap-1 mb-6">
                <span className="text-4xl font-extrabold text-slate-900 dark:text-white">{p.price}</span>
                <span className="text-slate-500 dark:text-slate-400 pb-1">{p.per}</span>
              </div>
              <ul className="space-y-2 mb-8">
                {p.features.map((f, j) => (
                  <li key={j} className="flex items-center gap-2 text-sm text-slate-600 dark:text-slate-300">
                    <div className="w-4 h-4 rounded-full bg-emerald-100 dark:bg-emerald-950 text-emerald-500 flex items-center justify-center text-xs">✓</div>
                    {f}
                  </li>
                ))}
              </ul>
              <Button
                className={`w-full ${p.highlight ? 'bg-blue-600 hover:bg-blue-700 text-white' : 'variant-outline'}`}
                variant={p.highlight ? 'default' : 'outline'}
                onClick={() => setLocation('/register')}
              >
                {p.cta}
              </Button>
            </div>
          ))}
        </div>
      </section>

      {/* Final CTA */}
      <section className="bg-slate-900 py-20 text-center">
        <h2 className="text-3xl font-bold text-white mb-4">Start running analyses today</h2>
        <p className="text-slate-400 mb-8">14-day free trial. Cancel any time. No credit card required.</p>
        <Button size="lg" className="bg-blue-600 hover:bg-blue-700 text-white px-10 py-6 text-base" onClick={() => setLocation('/register')}>
          Get started free <ArrowRight className="ml-2 h-5 w-5" />
        </Button>
      </section>
    </div>
  )
}
