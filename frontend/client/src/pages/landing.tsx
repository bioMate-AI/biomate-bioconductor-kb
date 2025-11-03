import { useState } from "react"
import { useLocation } from "wouter"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Check, ArrowRight, Beaker, Bot, Workflow, Zap, Shield, Users, Database, Settings, MessageSquare, Package, GitBranch, Sparkles } from "lucide-react"

export default function LandingPage() {
  const [, setLocation] = useLocation()

  const features = [
    {
      icon: MessageSquare,
      title: "Chat-Based. Zero Code.",
      description: "Design and run complex analyses through natural conversation—no programming required",
      details: "Your AI mate understands research terminology and translates it into optimized workflows"
    },
    {
      icon: Shield,
      title: "100% Cloud Infrastructure",
      description: "Enterprise-grade compute that scales automatically—no servers to manage",
      details: "Work from anywhere. Your analyses continue running even when you close your laptop"
    },
    {
      icon: Bot,
      title: "Smart Notifications",
      description: "Get alerted when jobs complete or when AI needs your input to proceed",
      details: "Stay in the loop without constantly checking status—focus on other work"
    },
    {
      icon: Settings,
      title: "Auto Parameter Tuning",
      description: "AI optimizes parameters for your specific analysis requirements",
      details: "No manual tuning needed—our AI finds optimal settings based on your data"
    },
    {
      icon: Package,
      title: "10,000+ Ready-to-Use Tools",
      description: "Instant access to Bioconductor, Biocontainer, Bioconda, Conda, and HuggingFace",
      details: "All containerized and pre-configured—no installation or dependency hell"
    },
    {
      icon: GitBranch,
      title: "Seamless Workflow Migration",
      description: "Import from Galaxy, Nextflow, Snakemake with one click",
      details: "Automatically converts and optimizes your existing workflows for cloud execution"
    }
  ]

  const stats = [
    { value: "10,000+", label: "Researchers" },
    { value: "500+", label: "Institutions" },
    { value: "1M+", label: "Workflows Run" },
    { value: "99.9%", label: "Uptime" }
  ]

  const testimonials = [
    {
      quote: "BioMate has transformed how we approach proteomics analysis. What used to take days now takes hours. The AI understands our research needs and optimizes workflows automatically.",
      author: "Dr. Sarah Chen",
      role: "Principal Investigator, Stanford University",
      image: "https://api.dicebear.com/7.x/avataaars/svg?seed=Sarah"
    },
    {
      quote: "Finally, a platform that understands the complexity of modern biomedical research. Migration from Galaxy was seamless, and we're now running analyses 16× faster.",
      author: "Prof. Michael Rodriguez",
      role: "Director of Bioinformatics, MIT",
      image: "https://api.dicebear.com/7.x/avataaars/svg?seed=Michael"
    }
  ]

  return (
    <div className="min-h-screen bg-background">
      {/* Hero Section */}
      <section className="relative border-b">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-16 sm:py-24">
          <div className="grid lg:grid-cols-2 gap-12 items-center">
            {/* Left Column - Text */}
            <div className="space-y-8">
              <div className="space-y-6">
                <div className="inline-flex items-center gap-2 text-sm text-blue-600 dark:text-blue-400 bg-gradient-to-r from-blue-50 to-purple-50 dark:from-blue-950 dark:to-purple-950 px-3 py-1 rounded-full border border-blue-200 dark:border-blue-800">
                  <div className="w-2 h-2 bg-gradient-to-r from-cyan-500 to-blue-500 rounded-full animate-pulse" />
                  AI-Powered Bioinformatics
                </div>
                <h1 className="text-4xl sm:text-5xl lg:text-6xl font-bold tracking-tight text-slate-900 dark:text-slate-50 leading-tight">
                  Chat Your Way to
                  <br />
                  <span className="bg-gradient-to-r from-cyan-600 via-blue-600 to-purple-600 bg-clip-text text-transparent">Scientific Discoveries</span>
                </h1>
                <p className="text-lg sm:text-xl text-slate-600 dark:text-slate-400 leading-relaxed max-w-xl">
                  No coding. No infrastructure. Just describe your analysis in plain English and watch your AI mate handle the rest—from workflow design to cloud execution.
                </p>
              </div>

              <div className="flex flex-col sm:flex-row gap-3">
                <Button
                  size="lg"
                  className="bg-gradient-to-r from-blue-600 to-purple-600 hover:from-blue-700 hover:to-purple-700 text-white px-6 py-6 text-base shadow-lg shadow-blue-500/30"
                  onClick={() => setLocation('/register')}
                >
                  Start Free Trial
                  <ArrowRight className="ml-2 h-4 w-4" />
                </Button>
                <Button
                  size="lg"
                  variant="outline"
                  className="px-6 py-6 text-base border-2 border-blue-200 dark:border-blue-800 hover:bg-blue-50 dark:hover:bg-blue-950"
                  onClick={() => setLocation('/pricing')}
                >
                  See Pricing
                </Button>
              </div>

              <div className="flex items-center gap-6 text-sm text-slate-500 dark:text-slate-400">
                <div className="flex items-center gap-2">
                  <Check className="h-4 w-4 text-blue-600" />
                  No credit card
                </div>
                <div className="flex items-center gap-2">
                  <Check className="h-4 w-4 text-blue-600" />
                  Free trial
                </div>
                <div className="flex items-center gap-2">
                  <Check className="h-4 w-4 text-blue-600" />
                  Cancel anytime
                </div>
              </div>
            </div>

            {/* Right Column - Simple Visual */}
            <div className="relative hidden lg:block">
              <div className="relative">
                <div className="rounded-2xl border-2 border-blue-200 dark:border-blue-800 bg-gradient-to-br from-blue-50 via-purple-50 to-pink-50 dark:from-blue-950 dark:via-purple-950 dark:to-pink-950 p-8 shadow-2xl">
                  <div className="text-center space-y-6">
                    <div className="inline-flex items-center justify-center w-20 h-20 rounded-2xl bg-gradient-to-br from-cyan-500 via-blue-500 to-purple-600 shadow-lg animate-pulse">
                      <Sparkles className="h-10 w-10 text-white" />
                    </div>
                    <div>
                      <h3 className="text-2xl font-bold bg-gradient-to-r from-blue-600 to-purple-600 bg-clip-text text-transparent mb-2">
                        Your AI Research Mate
                      </h3>
                      <p className="text-slate-600 dark:text-slate-400">
                        Intelligent, fast, and always learning
                      </p>
                    </div>
                    <div className="grid grid-cols-2 gap-4 pt-4">
                      <div className="text-center p-3 rounded-xl bg-white/50 dark:bg-slate-800/50 border border-blue-100 dark:border-blue-900">
                        <div className="text-3xl font-bold bg-gradient-to-r from-cyan-600 to-blue-600 bg-clip-text text-transparent">10,000+</div>
                        <div className="text-xs text-slate-600 dark:text-slate-400 mt-1">Tools & Models</div>
                      </div>
                      <div className="text-center p-3 rounded-xl bg-white/50 dark:bg-slate-800/50 border border-purple-100 dark:border-purple-900">
                        <div className="text-3xl font-bold bg-gradient-to-r from-purple-600 to-pink-600 bg-clip-text text-transparent">16×</div>
                        <div className="text-xs text-slate-600 dark:text-slate-400 mt-1">Faster</div>
                      </div>
                    </div>
                  </div>
                </div>
                <div className="absolute -z-10 top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-96 h-96 bg-gradient-to-r from-blue-500/20 to-purple-500/20 rounded-full blur-3xl" />
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* Platform Architecture Flow - Draw.io Style */}
      <section className="py-20 bg-gradient-to-b from-slate-50 to-white dark:from-slate-900 dark:to-slate-950 border-b">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="text-center mb-12">
            <h2 className="text-3xl sm:text-4xl font-bold text-slate-900 dark:text-slate-50 mb-3">
              How BioMate Works
            </h2>
            <p className="text-lg text-slate-600 dark:text-slate-400 max-w-2xl mx-auto">
              Professional bioinformatics platform with end-to-end automation
            </p>
          </div>

          <div className="relative max-w-6xl mx-auto">
            {/* Flow Diagram Container */}
            <div className="grid grid-cols-1 md:grid-cols-5 gap-6">

              {/* Node 1: Input */}
              <div className="relative">
                <div className="bg-white dark:bg-slate-800 rounded-xl border-2 border-blue-300 dark:border-blue-700 shadow-lg p-6 hover:shadow-xl transition-shadow">
                  <div className="flex flex-col items-center text-center space-y-3">
                    <div className="w-14 h-14 rounded-xl bg-gradient-to-br from-blue-400 to-blue-600 flex items-center justify-center shadow-md">
                      <MessageSquare className="h-7 w-7 text-white" />
                    </div>
                    <div>
                      <h3 className="font-bold text-slate-900 dark:text-slate-100 mb-1">Input</h3>
                      <p className="text-xs text-slate-600 dark:text-slate-400">Natural language or workflow files</p>
                    </div>
                  </div>
                  <div className="mt-4 pt-4 border-t border-slate-200 dark:border-slate-700 space-y-1.5 text-xs">
                    <div className="flex items-center gap-2">
                      <div className="w-1.5 h-1.5 rounded-full bg-blue-500"></div>
                      <span className="text-slate-700 dark:text-slate-300">Chat queries</span>
                    </div>
                    <div className="flex items-center gap-2">
                      <div className="w-1.5 h-1.5 rounded-full bg-blue-500"></div>
                      <span className="text-slate-700 dark:text-slate-300">Galaxy .ga</span>
                    </div>
                    <div className="flex items-center gap-2">
                      <div className="w-1.5 h-1.5 rounded-full bg-blue-500"></div>
                      <span className="text-slate-700 dark:text-slate-300">Nextflow .nf</span>
                    </div>
                  </div>
                </div>
                {/* Arrow */}
                <div className="hidden md:block absolute top-1/2 -right-3 transform -translate-y-1/2 z-10">
                  <ArrowRight className="h-6 w-6 text-slate-400 dark:text-slate-600" />
                </div>
              </div>

              {/* Node 2: AI Engine */}
              <div className="relative">
                <div className="bg-white dark:bg-slate-800 rounded-xl border-2 border-teal-300 dark:border-teal-700 shadow-lg p-6 hover:shadow-xl transition-shadow">
                  <div className="flex flex-col items-center text-center space-y-3">
                    <div className="w-14 h-14 rounded-xl bg-gradient-to-br from-teal-400 to-green-600 flex items-center justify-center shadow-md">
                      <Sparkles className="h-7 w-7 text-white" />
                    </div>
                    <div>
                      <h3 className="font-bold text-slate-900 dark:text-slate-100 mb-1">AI Engine</h3>
                      <p className="text-xs text-slate-600 dark:text-slate-400">Intelligent processing</p>
                    </div>
                  </div>
                  <div className="mt-4 pt-4 border-t border-slate-200 dark:border-slate-700 space-y-1.5 text-xs">
                    <div className="flex items-center gap-2">
                      <div className="w-1.5 h-1.5 rounded-full bg-teal-500"></div>
                      <span className="text-slate-700 dark:text-slate-300">Parameter tuning</span>
                    </div>
                    <div className="flex items-center gap-2">
                      <div className="w-1.5 h-1.5 rounded-full bg-teal-500"></div>
                      <span className="text-slate-700 dark:text-slate-300">Tool selection</span>
                    </div>
                    <div className="flex items-center gap-2">
                      <div className="w-1.5 h-1.5 rounded-full bg-teal-500"></div>
                      <span className="text-slate-700 dark:text-slate-300">Optimization</span>
                    </div>
                  </div>
                </div>
                {/* Arrow */}
                <div className="hidden md:block absolute top-1/2 -right-3 transform -translate-y-1/2 z-10">
                  <ArrowRight className="h-6 w-6 text-slate-400 dark:text-slate-600" />
                </div>
              </div>

              {/* Node 3: Tool Library */}
              <div className="relative">
                <div className="bg-white dark:bg-slate-800 rounded-xl border-2 border-purple-300 dark:border-purple-700 shadow-lg p-6 hover:shadow-xl transition-shadow">
                  <div className="flex flex-col items-center text-center space-y-3">
                    <div className="w-14 h-14 rounded-xl bg-gradient-to-br from-purple-400 to-purple-600 flex items-center justify-center shadow-md">
                      <Package className="h-7 w-7 text-white" />
                    </div>
                    <div>
                      <h3 className="font-bold text-slate-900 dark:text-slate-100 mb-1">Tool Library</h3>
                      <p className="text-xs text-slate-600 dark:text-slate-400">10,000+ tools</p>
                    </div>
                  </div>
                  <div className="mt-4 pt-4 border-t border-slate-200 dark:border-slate-700 space-y-1.5 text-xs">
                    <div className="flex items-center justify-between">
                      <span className="text-slate-700 dark:text-slate-300">Bioconda</span>
                      <span className="font-medium text-purple-600">8,000+</span>
                    </div>
                    <div className="flex items-center justify-between">
                      <span className="text-slate-700 dark:text-slate-300">Galaxy</span>
                      <span className="font-medium text-purple-600">3,000+</span>
                    </div>
                    <div className="flex items-center justify-between">
                      <span className="text-slate-700 dark:text-slate-300">Updates</span>
                      <span className="font-medium text-green-600">Daily</span>
                    </div>
                  </div>
                </div>
                {/* Arrow */}
                <div className="hidden md:block absolute top-1/2 -right-3 transform -translate-y-1/2 z-10">
                  <ArrowRight className="h-6 w-6 text-slate-400 dark:text-slate-600" />
                </div>
              </div>

              {/* Node 4: Cloud Execution */}
              <div className="relative">
                <div className="bg-white dark:bg-slate-800 rounded-xl border-2 border-green-300 dark:border-green-700 shadow-lg p-6 hover:shadow-xl transition-shadow">
                  <div className="flex flex-col items-center text-center space-y-3">
                    <div className="w-14 h-14 rounded-xl bg-gradient-to-br from-green-400 to-emerald-600 flex items-center justify-center shadow-md">
                      <Zap className="h-7 w-7 text-white" />
                    </div>
                    <div>
                      <h3 className="font-bold text-slate-900 dark:text-slate-100 mb-1">Execution</h3>
                      <p className="text-xs text-slate-600 dark:text-slate-400">Cloud parallel</p>
                    </div>
                  </div>
                  <div className="mt-4 pt-4 border-t border-slate-200 dark:border-slate-700 space-y-1.5 text-xs">
                    <div className="flex items-center gap-2">
                      <div className="w-1.5 h-1.5 rounded-full bg-green-500"></div>
                      <span className="text-slate-700 dark:text-slate-300">Auto-scaling</span>
                    </div>
                    <div className="flex items-center gap-2">
                      <div className="w-1.5 h-1.5 rounded-full bg-green-500"></div>
                      <span className="text-slate-700 dark:text-slate-300">Parallel jobs</span>
                    </div>
                    <div className="flex items-center gap-2">
                      <div className="w-1.5 h-1.5 rounded-full bg-green-500"></div>
                      <span className="text-slate-700 dark:text-slate-300">16× faster</span>
                    </div>
                  </div>
                </div>
                {/* Arrow */}
                <div className="hidden md:block absolute top-1/2 -right-3 transform -translate-y-1/2 z-10">
                  <ArrowRight className="h-6 w-6 text-slate-400 dark:text-slate-600" />
                </div>
              </div>

              {/* Node 5: Results */}
              <div className="relative">
                <div className="bg-white dark:bg-slate-800 rounded-xl border-2 border-orange-300 dark:border-orange-700 shadow-lg p-6 hover:shadow-xl transition-shadow">
                  <div className="flex flex-col items-center text-center space-y-3">
                    <div className="w-14 h-14 rounded-xl bg-gradient-to-br from-orange-400 to-red-500 flex items-center justify-center shadow-md">
                      <Beaker className="h-7 w-7 text-white" />
                    </div>
                    <div>
                      <h3 className="font-bold text-slate-900 dark:text-slate-100 mb-1">Results</h3>
                      <p className="text-xs text-slate-600 dark:text-slate-400">Publication-ready</p>
                    </div>
                  </div>
                  <div className="mt-4 pt-4 border-t border-slate-200 dark:border-slate-700 space-y-1.5 text-xs">
                    <div className="flex items-center gap-2">
                      <div className="w-1.5 h-1.5 rounded-full bg-orange-500"></div>
                      <span className="text-slate-700 dark:text-slate-300">Interactive plots</span>
                    </div>
                    <div className="flex items-center gap-2">
                      <div className="w-1.5 h-1.5 rounded-full bg-orange-500"></div>
                      <span className="text-slate-700 dark:text-slate-300">Auto reports</span>
                    </div>
                    <div className="flex items-center gap-2">
                      <div className="w-1.5 h-1.5 rounded-full bg-orange-500"></div>
                      <span className="text-slate-700 dark:text-slate-300">Data export</span>
                    </div>
                  </div>
                </div>
              </div>

            </div>

            {/* Bottom Info Banner */}
            <div className="mt-8 bg-slate-100 dark:bg-slate-800 rounded-xl p-6 border border-slate-200 dark:border-slate-700">
              <div className="flex flex-wrap items-center justify-center gap-x-8 gap-y-4 text-sm">
                <div className="flex items-center gap-2">
                  <Shield className="h-4 w-4 text-teal-600" />
                  <span className="text-slate-700 dark:text-slate-300 font-medium">SOC 2 Compliant</span>
                </div>
                <div className="flex items-center gap-2">
                  <Shield className="h-4 w-4 text-teal-600" />
                  <span className="text-slate-700 dark:text-slate-300 font-medium">HIPAA Ready</span>
                </div>
                <div className="flex items-center gap-2">
                  <Zap className="h-4 w-4 text-green-600" />
                  <span className="text-slate-700 dark:text-slate-300 font-medium">Real-time Monitoring</span>
                </div>
                <div className="flex items-center gap-2">
                  <Package className="h-4 w-4 text-purple-600" />
                  <span className="text-slate-700 dark:text-slate-300 font-medium">Weekly Tool Updates</span>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* Stats Section */}
      <section className="border-b">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-12">
          <div className="flex flex-wrap items-center justify-center gap-x-12 gap-y-6 text-center">
            {stats.map((stat, index) => (
              <div key={index} className="flex items-baseline gap-2">
                <div className="text-3xl font-bold text-slate-900 dark:text-slate-50">{stat.value}</div>
                <div className="text-sm text-slate-600 dark:text-slate-400">{stat.label}</div>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Key Differentiators Section */}
      <section className="py-16 bg-slate-50 dark:bg-slate-900 border-b">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="grid md:grid-cols-2 gap-6">
            {/* Import Existing Workflows */}
            <div className="bg-white dark:bg-slate-800 rounded-xl p-6 border border-slate-200 dark:border-slate-700">
              <div className="flex items-start gap-4">
                <div className="w-10 h-10 rounded-lg bg-blue-100 dark:bg-blue-900 flex items-center justify-center flex-shrink-0">
                  <GitBranch className="h-5 w-5 text-blue-600 dark:text-blue-400" />
                </div>
                <div className="flex-1">
                  <h3 className="font-semibold text-slate-900 dark:text-slate-50 mb-2">Import Existing Workflows</h3>
                  <p className="text-sm text-slate-600 dark:text-slate-400 mb-3">
                    Drag & drop your Galaxy (.ga), Nextflow (.nf), or Snakemake workflows
                  </p>
                  <div className="space-y-1.5">
                    <div className="flex items-center gap-2 text-xs text-slate-600 dark:text-slate-400">
                      <Check className="h-3 w-3 text-green-600" />
                      <span>Automatic tool mapping</span>
                    </div>
                    <div className="flex items-center gap-2 text-xs text-slate-600 dark:text-slate-400">
                      <Check className="h-3 w-3 text-green-600" />
                      <span>Parameter preservation</span>
                    </div>
                    <div className="flex items-center gap-2 text-xs text-slate-600 dark:text-slate-400">
                      <Check className="h-3 w-3 text-green-600" />
                      <span>Cloud-optimized execution</span>
                    </div>
                  </div>
                </div>
              </div>
            </div>

            {/* Extend & Customize */}
            <div className="bg-white dark:bg-slate-800 rounded-xl p-6 border border-slate-200 dark:border-slate-700">
              <div className="flex items-start gap-4">
                <div className="w-10 h-10 rounded-lg bg-purple-100 dark:bg-purple-900 flex items-center justify-center flex-shrink-0">
                  <Package className="h-5 w-5 text-purple-600 dark:text-purple-400" />
                </div>
                <div className="flex-1">
                  <h3 className="font-semibold text-slate-900 dark:text-slate-50 mb-2">Extend Pipelines Effortlessly</h3>
                  <p className="text-sm text-slate-600 dark:text-slate-400 mb-3">
                    Add new tools or concatenate workflows with a simple chat command
                  </p>
                  <div className="bg-slate-50 dark:bg-slate-900 rounded p-2 text-xs font-mono text-slate-700 dark:text-slate-300 border border-slate-200 dark:border-slate-700">
                    "Add DESeq2 normalization after alignment"
                  </div>
                  <div className="mt-2 text-[10px] text-slate-500 dark:text-slate-400">
                    → AI instantly integrates new steps into your workflow
                  </div>
                </div>
              </div>
            </div>

            {/* Always Up-to-Date */}
            <div className="bg-white dark:bg-slate-800 rounded-xl p-6 border border-slate-200 dark:border-slate-700">
              <div className="flex items-start gap-4">
                <div className="w-10 h-10 rounded-lg bg-teal-100 dark:bg-teal-900 flex items-center justify-center flex-shrink-0">
                  <Sparkles className="h-5 w-5 text-teal-600 dark:text-teal-400" />
                </div>
                <div className="flex-1">
                  <h3 className="font-semibold text-slate-900 dark:text-slate-50 mb-2">Cutting-Edge Tools</h3>
                  <p className="text-sm text-slate-600 dark:text-slate-400 mb-3">
                    Latest bioinformatics tools, AI models, and datasets automatically integrated
                  </p>
                  <div className="space-y-1.5">
                    <div className="flex items-center justify-between text-xs">
                      <span className="text-slate-600 dark:text-slate-400">New tools detected:</span>
                      <span className="text-teal-600 dark:text-teal-400 font-semibold">Weekly</span>
                    </div>
                    <div className="flex items-center justify-between text-xs">
                      <span className="text-slate-600 dark:text-slate-400">Database updates:</span>
                      <span className="text-teal-600 dark:text-teal-400 font-semibold">Daily</span>
                    </div>
                    <div className="mt-2 text-[10px] text-slate-500 dark:text-slate-400">
                      Access 10,000+ tools from Bioconda, Biocontainer, HuggingFace
                    </div>
                  </div>
                </div>
              </div>
            </div>

            {/* Smart Parameter Tuning */}
            <div className="bg-white dark:bg-slate-800 rounded-xl p-6 border border-slate-200 dark:border-slate-700">
              <div className="flex items-start gap-4">
                <div className="w-10 h-10 rounded-lg bg-orange-100 dark:bg-orange-900 flex items-center justify-center flex-shrink-0">
                  <Settings className="h-5 w-5 text-orange-600 dark:text-orange-400" />
                </div>
                <div className="flex-1">
                  <h3 className="font-semibold text-slate-900 dark:text-slate-50 mb-2">Smart Parameter Tuning</h3>
                  <p className="text-sm text-slate-600 dark:text-slate-400 mb-3">
                    AI optimizes parameters based on your data characteristics and research goals
                  </p>
                  <div className="space-y-1.5">
                    <div className="flex items-center gap-2 text-xs text-slate-600 dark:text-slate-400">
                      <Check className="h-3 w-3 text-green-600" />
                      <span>Sample size-aware optimization</span>
                    </div>
                    <div className="flex items-center gap-2 text-xs text-slate-600 dark:text-slate-400">
                      <Check className="h-3 w-3 text-green-600" />
                      <span>Data type-specific settings</span>
                    </div>
                    <div className="flex items-center gap-2 text-xs text-slate-600 dark:text-slate-400">
                      <Check className="h-3 w-3 text-green-600" />
                      <span>Quality threshold auto-adjustment</span>
                    </div>
                  </div>
                  <div className="mt-2 text-[10px] text-slate-500 dark:text-slate-400 italic">
                    No manual parameter tweaking needed
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* Use Cases Section - Simplified */}
      <section className="py-20 border-b bg-slate-50 dark:bg-slate-900">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="text-center mb-12">
            <h2 className="text-3xl font-bold mb-3 text-slate-900 dark:text-slate-50">
              Real-World Applications
            </h2>
            <p className="text-lg text-slate-600 dark:text-slate-400">
              From proteomics to genomics, handle complex analyses effortlessly
            </p>
          </div>

          <div className="grid md:grid-cols-2 gap-6 max-w-5xl mx-auto">
            <Card className="border-2 hover:border-blue-300 dark:hover:border-blue-700 transition-colors">
              <CardHeader>
                <CardTitle className="flex items-center gap-2">
                  <Beaker className="h-5 w-5 text-blue-600" />
                  Proteomics & MS Analysis
                </CardTitle>
                <CardDescription>
                  Upload mass spec data, get automated DIA-LCMS workflows with optimized parameters
                </CardDescription>
              </CardHeader>
              <CardContent>
                <div className="text-sm text-slate-600 dark:text-slate-400 mb-3">
                  MaxQuant · MSFragger · DIA-NN
                </div>
                <Badge variant="secondary" className="text-xs">3 hours → 30 minutes</Badge>
              </CardContent>
            </Card>

            <Card className="border-2 hover:border-purple-300 dark:hover:border-purple-700 transition-colors">
              <CardHeader>
                <CardTitle className="flex items-center gap-2">
                  <Workflow className="h-5 w-5 text-purple-600" />
                  RNA-Seq & Genomics
                </CardTitle>
                <CardDescription>
                  Describe your research question, AI designs complete pipelines with sample size calculations
                </CardDescription>
              </CardHeader>
              <CardContent>
                <div className="text-sm text-slate-600 dark:text-slate-400 mb-3">
                  DESeq2 · STAR · Salmon · edgeR
                </div>
                <Badge variant="secondary" className="text-xs">Days → Minutes</Badge>
              </CardContent>
            </Card>
          </div>
        </div>
      </section>

      {/* Tools & Integration - Merged Section */}
      <section className="py-16 border-b">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="text-center mb-12">
            <h2 className="text-3xl font-bold mb-3 text-slate-900 dark:text-slate-50">
              Complete Bioinformatics Ecosystem
            </h2>
            <p className="text-lg text-slate-600 dark:text-slate-400">
              10,000+ tools from Bioconda, Biocontainer, HuggingFace · Compatible with Galaxy, Nextflow, Snakemake
            </p>
          </div>

          <div className="grid md:grid-cols-2 gap-6 max-w-5xl mx-auto">
            <Card className="border-2">
              <CardHeader>
                <CardTitle className="flex items-center gap-2 text-xl">
                  <Package className="h-5 w-5 text-purple-600" />
                  Tool Library
                </CardTitle>
                <CardDescription>
                  Pre-configured tools from major bioinformatics repositories
                </CardDescription>
              </CardHeader>
              <CardContent className="space-y-2">
                <div className="flex items-center justify-between text-sm">
                  <span className="text-slate-600 dark:text-slate-400">Bioconda packages</span>
                  <span className="font-semibold text-purple-600">8,000+</span>
                </div>
                <div className="flex items-center justify-between text-sm">
                  <span className="text-slate-600 dark:text-slate-400">Biocontainers</span>
                  <span className="font-semibold text-purple-600">5,000+</span>
                </div>
                <div className="flex items-center justify-between text-sm">
                  <span className="text-slate-600 dark:text-slate-400">HuggingFace models</span>
                  <span className="font-semibold text-purple-600">500+</span>
                </div>
              </CardContent>
            </Card>

            <Card className="border-2">
              <CardHeader>
                <CardTitle className="flex items-center gap-2 text-xl">
                  <GitBranch className="h-5 w-5 text-blue-600" />
                  Workflow Import
                </CardTitle>
                <CardDescription>
                  Seamlessly migrate existing workflows from major platforms
                </CardDescription>
              </CardHeader>
              <CardContent className="space-y-2">
                <div className="flex items-center justify-between text-sm">
                  <span className="text-slate-600 dark:text-slate-400">Galaxy (.ga)</span>
                  <Badge variant="outline" className="text-green-600 border-green-600">✓ Supported</Badge>
                </div>
                <div className="flex items-center justify-between text-sm">
                  <span className="text-slate-600 dark:text-slate-400">Nextflow (.nf)</span>
                  <Badge variant="outline" className="text-green-600 border-green-600">✓ Supported</Badge>
                </div>
                <div className="flex items-center justify-between text-sm">
                  <span className="text-slate-600 dark:text-slate-400">Snakemake</span>
                  <Badge variant="outline" className="text-green-600 border-green-600">✓ Supported</Badge>
                </div>
              </CardContent>
            </Card>
          </div>
        </div>
      </section>

      {/* Testimonials Section */}
      <section className="py-16 border-b bg-slate-50 dark:bg-slate-900">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="text-center mb-12">
            <h2 className="text-3xl font-bold mb-3 text-slate-900 dark:text-slate-50">
              Trusted by Leading Researchers
            </h2>
            <p className="text-lg text-slate-600 dark:text-slate-400">
              See what scientists are saying about BioMate
            </p>
          </div>

          <div className="grid md:grid-cols-2 gap-8 max-w-5xl mx-auto">
            {testimonials.map((testimonial, index) => (
              <Card key={index} className="hover:shadow-lg transition-all">
                <CardHeader>
                  <div className="flex items-center gap-4 mb-4">
                    <div className="w-12 h-12 rounded-full bg-slate-200 dark:bg-slate-700 flex items-center justify-center overflow-hidden">
                      <img
                        src={testimonial.image}
                        alt={testimonial.author}
                        className="w-full h-full object-cover"
                      />
                    </div>
                    <div>
                      <div className="font-semibold">{testimonial.author}</div>
                      <div className="text-sm text-slate-600 dark:text-slate-400">{testimonial.role}</div>
                    </div>
                  </div>
                  <CardDescription className="text-base leading-relaxed">
                    "{testimonial.quote}"
                  </CardDescription>
                </CardHeader>
              </Card>
            ))}
          </div>
        </div>
      </section>

      {/* CTA Section */}
      <section className="py-24">
        <div className="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 text-center">
          <div className="mb-8">
            <h2 className="text-4xl sm:text-5xl font-bold mb-4 text-slate-900 dark:text-slate-50">
              Ready to Accelerate Your Research?
            </h2>
            <p className="text-xl text-slate-600 dark:text-slate-400 mb-4">
              Join thousands of researchers using BioMate to advance biomedicine
            </p>
            <p className="text-base text-slate-500 dark:text-slate-400">
              No credit card required • No installation • Start analyzing in minutes
            </p>
          </div>

          <div className="flex flex-col sm:flex-row gap-4 justify-center">
            <Button
              size="lg"
              className="text-lg px-8 py-6 bg-teal-600 hover:bg-teal-700 text-white"
              onClick={() => setLocation('/register')}
            >
              Start Free Trial
              <ArrowRight className="ml-2 h-5 w-5" />
            </Button>
            <Button
              size="lg"
              variant="outline"
              className="text-lg px-8 py-6"
              onClick={() => setLocation('/contact')}
            >
              Contact Sales
            </Button>
          </div>
        </div>
      </section>
    </div>
  )
}
