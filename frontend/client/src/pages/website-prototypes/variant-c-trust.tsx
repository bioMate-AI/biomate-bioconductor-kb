/**
 * Variant C — Trust & Compliance-Forward
 * Lead with institutional credibility, data governance, and standards compliance.
 * Target: IT / security officer, clinical research director, pharma procurement.
 */
import { useLocation } from "wouter"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { ArrowRight, Shield, Lock, FileCheck, Server, Users, Building2, ChevronDown, CheckCircle } from "lucide-react"
import { useState } from "react"

const COMPLIANCE_ITEMS = [
  { name: "SOC 2 Type II", status: "In preparation", icon: <Shield className="h-5 w-5" />, color: "text-amber-500" },
  { name: "HIPAA-ready architecture", status: "Implemented", icon: <Lock className="h-5 w-5" />, color: "text-emerald-500" },
  { name: "GDPR compliant data handling", status: "Certified", icon: <FileCheck className="h-5 w-5" />, color: "text-emerald-500" },
  { name: "AWS GovCloud option", status: "Available on request", icon: <Server className="h-5 w-5" />, color: "text-blue-500" },
  { name: "Data residency controls", status: "US / EU / APAC", icon: <Building2 className="h-5 w-5" />, color: "text-emerald-500" },
  { name: "Role-based access control", status: "Implemented", icon: <Users className="h-5 w-5" />, color: "text-emerald-500" },
]

const GOVERNANCE_FEATURES = [
  {
    title: "Full audit trail",
    description: "Every workflow run, parameter change, and result download is logged with user identity, timestamp, and IP address. Exportable as CSV for compliance review.",
    icon: "📋"
  },
  {
    title: "QC governance by published standards",
    description: "QC thresholds are not arbitrary — each is cited to a peer-reviewed standard (GATK Best Practices, ICH S7B, ENCODE, EMDB). Your methods are defensible.",
    icon: "📐"
  },
  {
    title: "PHI detection and stripping",
    description: "Automatic detection of patient identifiers in uploaded data. PHI is stripped before any LLM processing. No patient data ever reaches a third-party model.",
    icon: "🔒"
  },
  {
    title: "Private deployment option",
    description: "Deploy BioMate in your own AWS account or on-premises. Your data never leaves your environment. We provide the software; you own the infrastructure.",
    icon: "🏢"
  }
]

const FAQS = [
  { q: "Where is my data stored?", a: "By default, data is stored in AWS S3 in the US-East-1 region with AES-256 encryption at rest and TLS 1.3 in transit. EU and APAC regions available for institutional accounts. Private deployment means data never leaves your environment." },
  { q: "Does BioMate use my data to train models?", a: "No. Your data is never used for model training. BioMate uses Anthropic's Claude API with a data processing agreement that prohibits training use. Workflow results are isolated per organization." },
  { q: "What happens if a workflow fails?", a: "Failures are logged with a full error trace. The AI auto-fix system attempts to resolve the failure autonomously. If it cannot, the user is notified with a specific, actionable error message. No silent failures." },
  { q: "Can we integrate with our existing LIMS?", a: "Yes. BioMate provides a REST API and Benchling integration. We can also import data from SENAITE, LabArchives, and most LIMS systems that support file export or API access." }
]

export default function VariantCTrust() {
  const [, setLocation] = useLocation()
  const [openFaq, setOpenFaq] = useState<number | null>(null)

  return (
    <div className="min-h-screen bg-white dark:bg-slate-950">
      {/* Nav */}
      <nav className="border-b border-slate-200 dark:border-slate-800 px-6 py-4 flex items-center justify-between max-w-7xl mx-auto">
        <div className="flex items-center gap-3">
          <div className="w-8 h-8 rounded-lg bg-slate-900 dark:bg-white flex items-center justify-center">
            <span className="text-white dark:text-slate-900 font-bold text-sm">B</span>
          </div>
          <span className="font-semibold text-lg text-slate-900 dark:text-white">BioMate</span>
          <div className="h-4 w-px bg-slate-200 dark:bg-slate-700 mx-1" />
          <span className="text-xs text-slate-500 dark:text-slate-400">Enterprise Research Platform</span>
        </div>
        <div className="flex items-center gap-8 text-sm">
          <button className="text-slate-600 dark:text-slate-400 hover:text-slate-900 dark:hover:text-white transition-colors">Security</button>
          <button className="text-slate-600 dark:text-slate-400 hover:text-slate-900 dark:hover:text-white transition-colors">Compliance</button>
          <button className="text-slate-600 dark:text-slate-400 hover:text-slate-900 dark:hover:text-white transition-colors">Enterprise</button>
          <Button size="sm" variant="ghost" className="text-slate-600 dark:text-slate-400" onClick={() => setLocation('/login')}>Sign In</Button>
          <Button size="sm" className="bg-slate-900 dark:bg-white text-white dark:text-slate-900 hover:bg-slate-700 dark:hover:bg-slate-100" onClick={() => setLocation('/register')}>
            Request demo
          </Button>
        </div>
      </nav>

      {/* Hero — lead with trust signals */}
      <section className="max-w-7xl mx-auto px-6 py-20">
        <div className="grid lg:grid-cols-2 gap-16 items-center">
          <div>
            <div className="flex items-center gap-3 mb-6">
              <Badge className="bg-emerald-100 dark:bg-emerald-950 text-emerald-700 dark:text-emerald-300 border-0 text-xs">HIPAA-ready</Badge>
              <Badge className="bg-blue-100 dark:bg-blue-950 text-blue-700 dark:text-blue-300 border-0 text-xs">SOC 2 in preparation</Badge>
              <Badge className="bg-slate-100 dark:bg-slate-800 text-slate-600 dark:text-slate-400 border-0 text-xs">GDPR compliant</Badge>
            </div>
            <h1 className="text-5xl font-bold text-slate-900 dark:text-white leading-tight mb-6">
              AI bioinformatics your<br />
              <span className="text-slate-500 dark:text-slate-400">compliance team</span><br />
              can approve
            </h1>
            <p className="text-lg text-slate-600 dark:text-slate-400 leading-relaxed mb-8">
              BioMate gives your researchers AI-powered workflow automation with the data governance, audit trails, and institutional controls that enterprise and clinical environments require.
            </p>
            <div className="flex gap-4">
              <Button size="lg" className="bg-slate-900 dark:bg-white text-white dark:text-slate-900 px-8 py-6 text-base" onClick={() => setLocation('/register')}>
                Request a demo <ArrowRight className="ml-2 h-4 w-4" />
              </Button>
              <Button size="lg" variant="outline" className="px-8 py-6 text-base border-2 border-slate-200 dark:border-slate-700">
                Download security brief
              </Button>
            </div>
          </div>

          {/* Compliance checklist panel */}
          <div className="bg-slate-50 dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-2xl p-6 space-y-3">
            <div className="text-sm font-semibold text-slate-900 dark:text-white mb-4">Security & compliance status</div>
            {COMPLIANCE_ITEMS.map((item, i) => (
              <div key={i} className="flex items-center gap-3 py-2 border-b border-slate-200 dark:border-slate-800 last:border-0">
                <div className={item.color}>{item.icon}</div>
                <div className="flex-1">
                  <div className="text-sm font-medium text-slate-900 dark:text-white">{item.name}</div>
                </div>
                <div className={`text-xs font-medium ${item.color}`}>{item.status}</div>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Governance features */}
      <section className="bg-slate-50 dark:bg-slate-900 py-20">
        <div className="max-w-7xl mx-auto px-6">
          <div className="text-center mb-12">
            <h2 className="text-3xl font-bold text-slate-900 dark:text-white mb-3">Built for regulated research environments</h2>
            <p className="text-slate-500 dark:text-slate-400">Every feature designed with institutional security requirements in mind</p>
          </div>
          <div className="grid md:grid-cols-2 gap-6">
            {GOVERNANCE_FEATURES.map((f, i) => (
              <div key={i} className="bg-white dark:bg-slate-800 border border-slate-200 dark:border-slate-700 rounded-xl p-6">
                <div className="text-2xl mb-3">{f.icon}</div>
                <h3 className="text-base font-semibold text-slate-900 dark:text-white mb-2">{f.title}</h3>
                <p className="text-sm text-slate-600 dark:text-slate-400 leading-relaxed">{f.description}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Institutional proof */}
      <section className="max-w-7xl mx-auto px-6 py-20">
        <div className="grid md:grid-cols-3 gap-8">
          {[
            {
              quote: "BioMate passed our IT security review in 3 weeks — the fastest we've ever onboarded an AI tool. The audit trail was exactly what our compliance team needed.",
              name: "Director of Research Computing",
              org: "Major academic medical center",
              badge: "Clinical research"
            },
            {
              quote: "We needed to demonstrate that our AI-assisted analysis met ICH guidelines. BioMate's QC audit log with cited standards did that out of the box.",
              name: "Head of Computational Chemistry",
              org: "Top-20 pharmaceutical company",
              badge: "Pharma / GxP"
            },
            {
              quote: "The private deployment option meant our CRO partner could use BioMate without any data leaving our AWS environment. That was non-negotiable for us.",
              name: "VP of Bioinformatics",
              org: "Clinical stage biotech",
              badge: "Biotech"
            }
          ].map((t, i) => (
            <div key={i} className="bg-white dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-xl p-6">
              <Badge variant="outline" className="text-xs mb-4 text-slate-500 dark:text-slate-400 border-slate-300 dark:border-slate-600">{t.badge}</Badge>
              <p className="text-sm text-slate-700 dark:text-slate-300 leading-relaxed mb-4 italic">"{t.quote}"</p>
              <div>
                <div className="text-sm font-medium text-slate-900 dark:text-white">{t.name}</div>
                <div className="text-xs text-slate-500 dark:text-slate-400">{t.org}</div>
              </div>
            </div>
          ))}
        </div>
      </section>

      {/* FAQ */}
      <section className="bg-slate-50 dark:bg-slate-900 py-20">
        <div className="max-w-3xl mx-auto px-6">
          <h2 className="text-2xl font-bold text-slate-900 dark:text-white mb-8 text-center">Security & compliance FAQ</h2>
          <div className="space-y-2">
            {FAQS.map((faq, i) => (
              <div key={i} className="bg-white dark:bg-slate-800 border border-slate-200 dark:border-slate-700 rounded-xl overflow-hidden">
                <button
                  onClick={() => setOpenFaq(openFaq === i ? null : i)}
                  className="w-full flex items-center justify-between p-5 text-left"
                >
                  <span className="text-sm font-medium text-slate-900 dark:text-white">{faq.q}</span>
                  <ChevronDown className={`h-4 w-4 text-slate-400 transition-transform ${openFaq === i ? 'rotate-180' : ''}`} />
                </button>
                {openFaq === i && (
                  <div className="px-5 pb-5">
                    <p className="text-sm text-slate-600 dark:text-slate-400 leading-relaxed">{faq.a}</p>
                  </div>
                )}
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Enterprise CTA */}
      <section className="max-w-7xl mx-auto px-6 py-20">
        <div className="bg-slate-900 dark:bg-slate-800 rounded-3xl p-12 text-center">
          <CheckCircle className="h-12 w-12 text-emerald-400 mx-auto mb-4" />
          <h2 className="text-3xl font-bold text-white mb-4">Enterprise-ready from day one</h2>
          <p className="text-slate-400 mb-8 max-w-xl mx-auto">We support institutional procurement, MSAs, BAAs for HIPAA, and custom security reviews. Talk to us about your requirements.</p>
          <div className="flex gap-4 justify-center">
            <Button size="lg" className="bg-white text-slate-900 hover:bg-slate-100 px-8 py-6 text-base" onClick={() => setLocation('/register')}>
              Request enterprise demo
            </Button>
            <Button size="lg" variant="outline" className="border-slate-600 text-slate-300 hover:bg-slate-800 px-8 py-6 text-base" onClick={() => setLocation('/pricing')}>
              View enterprise pricing
            </Button>
          </div>
        </div>
      </section>
    </div>
  )
}
