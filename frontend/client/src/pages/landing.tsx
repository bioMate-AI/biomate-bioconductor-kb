import { useState } from "react"
import { useLocation } from "wouter"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
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

  const toolEcosystems = [
    {
      name: "Bioconductor",
      count: "2,000+",
      description: "R packages for genomics",
      icon: "🧬"
    },
    {
      name: "Biocontainer",
      count: "5,000+",
      description: "Containerized tools",
      icon: "📦"
    },
    {
      name: "Bioconda",
      count: "8,000+",
      description: "Conda packages",
      icon: "🐍"
    },
    {
      name: "HuggingFace",
      count: "500+",
      description: "AI models for biology",
      icon: "🤗"
    }
  ]

  const useCases = [
    {
      title: "Proteomics Analysis",
      description: "Automated DIA-LCMS workflow with dataset integration",
      steps: [
        "Upload mass spectrometry data",
        "AI suggests optimal analysis pipeline",
        "Auto-tune parameters for your sample type",
        "Generate publication-ready results"
      ],
      tools: ["MaxQuant", "MSFragger", "DIA-NN"],
      time: "3 hours → 30 minutes"
    },
    {
      title: "RNA-Seq Study Design",
      description: "Chat-based customized experimental design",
      steps: [
        "Describe your research question in plain English",
        "AI designs complete RNA-seq workflow",
        "Automatic sample size calculation",
        "Integration with public datasets (GEO, SRA)"
      ],
      tools: ["DESeq2", "edgeR", "STAR", "Salmon"],
      time: "Days → Minutes"
    },
    {
      title: "Workflow Migration",
      description: "Import existing Galaxy workflows",
      steps: [
        "Upload your Galaxy .ga workflow file",
        "Automatic conversion to BioMate format",
        "Tool compatibility check and updates",
        "Enhanced with AI parameter optimization"
      ],
      tools: ["Galaxy", "Nextflow", "Snakemake"],
      time: "Seamless migration"
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
      quote: "BioMate has transformed how we approach proteomics analysis. What used to take days now takes hours.",
      author: "Dr. Sarah Chen",
      role: "Principal Investigator, Stanford University",
      image: "https://api.dicebear.com/7.x/avataaars/svg?seed=Sarah"
    },
    {
      quote: "The AI-powered workflow suggestions have helped us discover novel insights in our genomics data.",
      author: "Prof. Michael Rodriguez",
      role: "Director of Bioinformatics, MIT",
      image: "https://api.dicebear.com/7.x/avataaars/svg?seed=Michael"
    },
    {
      quote: "Finally, a platform that understands the complexity of modern biomedical research.",
      author: "Dr. Emily Watson",
      role: "Research Scientist, Johns Hopkins",
      image: "https://api.dicebear.com/7.x/avataaars/svg?seed=Emily"
    }
  ]

  return (
    <div className="min-h-screen bg-background">
      {/* Hero Section */}
      <section className="relative overflow-hidden border-b">
        <div className="absolute inset-0 bg-gradient-to-br from-blue-500/10 via-purple-500/10 to-pink-500/10" />
        <div className="relative max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-24 sm:py-32">
          <div className="text-center space-y-8">
            <div className="space-y-4">
              <Badge variant="secondary" className="text-sm px-4 py-1">
                AI-Powered Biomedicine Platform
              </Badge>
              <h1 className="text-5xl sm:text-6xl lg:text-7xl font-bold tracking-tight">
                Your AI Mate for
                <br />
                <span className="text-transparent bg-clip-text bg-gradient-to-r from-blue-500 via-purple-500 to-pink-500">
                  Biomedicine
                </span>
              </h1>
              <p className="text-xl text-muted-foreground max-w-2xl mx-auto">
                <strong>100% Cloud-Based. Zero Code Required.</strong> Just chat with your AI mate to design and run complex analyses.
                No infrastructure setup, no programming skills needed—focus purely on your research.
              </p>
            </div>

            <div className="flex flex-col sm:flex-row gap-4 justify-center items-center">
              <Button
                size="lg"
                className="text-lg px-8 py-6"
                onClick={() => setLocation('/register')}
              >
                Start Free Trial
                <ArrowRight className="ml-2 h-5 w-5" />
              </Button>
              <Button
                size="lg"
                variant="outline"
                className="text-lg px-8 py-6"
                onClick={() => setLocation('/pricing')}
              >
                View Pricing
              </Button>
            </div>

            <p className="text-sm text-muted-foreground">
              No credit card required • No installation • No coding skills needed
            </p>
          </div>
        </div>
      </section>

      {/* Stats Section */}
      <section className="border-b">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-16">
          <div className="grid grid-cols-2 md:grid-cols-4 gap-8">
            {stats.map((stat, index) => (
              <div key={index} className="text-center">
                <div className="text-4xl font-bold">{stat.value}</div>
                <div className="text-muted-foreground mt-2">{stat.label}</div>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* How It Works Section */}
      <section className="py-24 border-b">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="text-center mb-16">
            <Badge variant="secondary" className="mb-4">
              Simple. Powerful. Cloud-Based.
            </Badge>
            <h2 className="text-4xl font-bold mb-4">
              Research Without the Complexity
            </h2>
            <p className="text-xl text-muted-foreground max-w-2xl mx-auto">
              No infrastructure worries. No coding required. Just focus on your science.
            </p>
          </div>

          <div className="grid md:grid-cols-2 lg:grid-cols-4 gap-8">
            <Card className="border-2">
              <CardHeader>
                <div className="w-12 h-12 rounded-full bg-blue-100 dark:bg-blue-900 flex items-center justify-center mb-4">
                  <MessageSquare className="h-6 w-6 text-blue-600 dark:text-blue-400" />
                </div>
                <CardTitle className="text-xl">1. Chat Your Task</CardTitle>
              </CardHeader>
              <CardContent>
                <p className="text-muted-foreground">
                  Describe your analysis in plain English. "I need to analyze DIA-LCMS proteomics data with 50 samples."
                </p>
              </CardContent>
            </Card>

            <Card className="border-2">
              <CardHeader>
                <div className="w-12 h-12 rounded-full bg-purple-100 dark:bg-purple-900 flex items-center justify-center mb-4">
                  <Bot className="h-6 w-6 text-purple-600 dark:text-purple-400" />
                </div>
                <CardTitle className="text-xl">2. AI Takes Over</CardTitle>
              </CardHeader>
              <CardContent>
                <p className="text-muted-foreground">
                  Your AI mate designs the workflow, provisions cloud resources, and starts the analysis automatically.
                </p>
              </CardContent>
            </Card>

            <Card className="border-2">
              <CardHeader>
                <div className="w-12 h-12 rounded-full bg-green-100 dark:bg-green-900 flex items-center justify-center mb-4">
                  <Sparkles className="h-6 w-6 text-green-600 dark:text-green-400" />
                </div>
                <CardTitle className="text-xl">3. Switch Attention</CardTitle>
              </CardHeader>
              <CardContent>
                <p className="text-muted-foreground">
                  Close your laptop and focus on other work. Everything runs in the cloud while you're away.
                </p>
              </CardContent>
            </Card>

            <Card className="border-2">
              <CardHeader>
                <div className="w-12 h-12 rounded-full bg-orange-100 dark:bg-orange-900 flex items-center justify-center mb-4">
                  <Zap className="h-6 w-6 text-orange-600 dark:text-orange-400" />
                </div>
                <CardTitle className="text-xl">4. Get Alerted</CardTitle>
              </CardHeader>
              <CardContent>
                <p className="text-muted-foreground">
                  Receive notifications when analysis completes, or when your mate needs clarification to proceed.
                </p>
              </CardContent>
            </Card>
          </div>

          <div className="mt-12 text-center">
            <Card className="max-w-3xl mx-auto bg-gradient-to-r from-blue-50 to-purple-50 dark:from-blue-950 dark:to-purple-950 border-2">
              <CardHeader>
                <CardTitle className="flex items-center justify-center gap-2">
                  <Shield className="h-5 w-5" />
                  Zero Infrastructure Headaches
                </CardTitle>
              </CardHeader>
              <CardContent>
                <p className="text-muted-foreground">
                  No servers to manage. No software to install. No containers to configure.
                  Your analyses run on enterprise-grade cloud infrastructure that automatically scales based on your needs.
                  Pay only for what you use—just like your electricity bill.
                </p>
              </CardContent>
            </Card>
          </div>
        </div>
      </section>

      {/* Use Cases Section */}
      <section className="py-24 border-b bg-muted/30">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="text-center mb-16">
            <Badge variant="secondary" className="mb-4">
              Real-World Applications
            </Badge>
            <h2 className="text-4xl font-bold mb-4">
              See BioMate in action
            </h2>
            <p className="text-xl text-muted-foreground max-w-2xl mx-auto">
              From automated workflows to custom study design, discover what you can accomplish
            </p>
          </div>

          <Tabs defaultValue="proteomics" className="w-full">
            <TabsList className="grid w-full max-w-2xl mx-auto grid-cols-3 mb-12">
              <TabsTrigger value="proteomics">Proteomics</TabsTrigger>
              <TabsTrigger value="rnaseq">RNA-Seq Design</TabsTrigger>
              <TabsTrigger value="migration">Migration</TabsTrigger>
            </TabsList>

            {useCases.map((useCase, idx) => (
              <TabsContent key={idx} value={['proteomics', 'rnaseq', 'migration'][idx]} className="mt-0">
                <Card className="max-w-4xl mx-auto">
                  <CardHeader>
                    <div className="flex items-start justify-between">
                      <div>
                        <CardTitle className="text-2xl mb-2">{useCase.title}</CardTitle>
                        <CardDescription className="text-base">{useCase.description}</CardDescription>
                      </div>
                      <Badge variant="outline" className="text-primary">
                        {useCase.time}
                      </Badge>
                    </div>
                  </CardHeader>
                  <CardContent className="space-y-6">
                    <div>
                      <h4 className="font-semibold mb-4 flex items-center gap-2">
                        <Sparkles className="h-5 w-5 text-primary" />
                        How it works
                      </h4>
                      <div className="space-y-3">
                        {useCase.steps.map((step, stepIdx) => (
                          <div key={stepIdx} className="flex items-start gap-3">
                            <div className="flex-shrink-0 w-6 h-6 rounded-full bg-primary text-primary-foreground flex items-center justify-center text-sm font-semibold">
                              {stepIdx + 1}
                            </div>
                            <p className="text-muted-foreground pt-0.5">{step}</p>
                          </div>
                        ))}
                      </div>
                    </div>

                    <div>
                      <h4 className="font-semibold mb-3">Tools included:</h4>
                      <div className="flex flex-wrap gap-2">
                        {useCase.tools.map((tool, toolIdx) => (
                          <Badge key={toolIdx} variant="secondary">
                            {tool}
                          </Badge>
                        ))}
                      </div>
                    </div>

                    <Button size="lg" className="w-full" onClick={() => setLocation('/register')}>
                      Try This Workflow
                      <ArrowRight className="ml-2 h-5 w-5" />
                    </Button>
                  </CardContent>
                </Card>
              </TabsContent>
            ))}
          </Tabs>
        </div>
      </section>

      {/* Features Section */}
      <section className="py-24 border-b">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="text-center mb-16">
            <h2 className="text-4xl font-bold mb-4">
              Everything you need for modern research
            </h2>
            <p className="text-xl text-muted-foreground max-w-2xl mx-auto">
              Powerful capabilities designed specifically for biomedical researchers
            </p>
          </div>

          <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-8">
            {features.map((feature, index) => (
              <Card key={index} className="border-2 hover:border-primary transition-colors group">
                <CardHeader>
                  <div className="w-12 h-12 rounded-lg bg-primary/10 flex items-center justify-center mb-4 group-hover:bg-primary/20 transition-colors">
                    <feature.icon className="h-6 w-6 text-primary" />
                  </div>
                  <CardTitle className="mb-2">{feature.title}</CardTitle>
                  <CardDescription className="text-base mb-2">{feature.description}</CardDescription>
                  <p className="text-sm text-muted-foreground italic">{feature.details}</p>
                </CardHeader>
              </Card>
            ))}
          </div>
        </div>
      </section>

      {/* Tool Ecosystem Section */}
      <section className="py-24 border-b bg-muted/30">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="text-center mb-16">
            <Badge variant="secondary" className="mb-4">
              10,000+ Tools Available
            </Badge>
            <h2 className="text-4xl font-bold mb-4">
              Massive tool library at your fingertips
            </h2>
            <p className="text-xl text-muted-foreground max-w-2xl mx-auto">
              Access the entire bioinformatics ecosystem - all containerized, tested, and ready to use
            </p>
          </div>

          <div className="grid md:grid-cols-2 lg:grid-cols-4 gap-6 mb-12">
            {toolEcosystems.map((ecosystem, index) => (
              <Card key={index} className="text-center hover:shadow-lg transition-shadow">
                <CardHeader>
                  <div className="text-5xl mb-4">{ecosystem.icon}</div>
                  <CardTitle>{ecosystem.name}</CardTitle>
                  <div className="text-3xl font-bold text-primary my-2">{ecosystem.count}</div>
                  <CardDescription>{ecosystem.description}</CardDescription>
                </CardHeader>
              </Card>
            ))}
          </div>

          <Card className="max-w-4xl mx-auto border-2">
            <CardHeader>
              <CardTitle className="text-center text-2xl">Plus Integration With</CardTitle>
            </CardHeader>
            <CardContent>
              <div className="grid grid-cols-2 md:grid-cols-4 gap-6 text-center">
                <div>
                  <div className="text-2xl font-semibold mb-1">Conda</div>
                  <div className="text-sm text-muted-foreground">Package manager</div>
                </div>
                <div>
                  <div className="text-2xl font-semibold mb-1">Docker</div>
                  <div className="text-sm text-muted-foreground">Containerization</div>
                </div>
                <div>
                  <div className="text-2xl font-semibold mb-1">Singularity</div>
                  <div className="text-sm text-muted-foreground">HPC containers</div>
                </div>
                <div>
                  <div className="text-2xl font-semibold mb-1">Kubernetes</div>
                  <div className="text-sm text-muted-foreground">Orchestration</div>
                </div>
              </div>
            </CardContent>
          </Card>
        </div>
      </section>

      {/* Workflow Compatibility Section */}
      <section className="py-24 border-b">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="text-center mb-16">
            <Badge variant="secondary" className="mb-4">
              Seamless Migration
            </Badge>
            <h2 className="text-4xl font-bold mb-4">
              Bring your existing workflows
            </h2>
            <p className="text-xl text-muted-foreground max-w-2xl mx-auto">
              Compatible with major workflow systems - migrate in minutes, not months
            </p>
          </div>

          <div className="grid md:grid-cols-3 gap-8 mb-12">
            {[
              {
                platform: "Galaxy",
                format: ".ga files",
                description: "Import Galaxy workflows with automatic tool mapping",
                supported: true
              },
              {
                platform: "Nextflow",
                format: ".nf files",
                description: "Convert Nextflow pipelines with DSL support",
                supported: true
              },
              {
                platform: "Snakemake",
                format: "Snakefile",
                description: "Migrate Snakemake workflows with rule preservation",
                supported: true
              }
            ].map((platform, index) => (
              <Card key={index} className="hover:border-primary transition-colors">
                <CardHeader>
                  <div className="flex items-center justify-between mb-4">
                    <CardTitle className="text-xl">{platform.platform}</CardTitle>
                    <Badge variant="outline" className="text-blue-600 border-blue-600">
                      ✓ Supported
                    </Badge>
                  </div>
                  <Badge variant="secondary" className="w-fit mb-3">{platform.format}</Badge>
                  <CardDescription className="text-base">{platform.description}</CardDescription>
                </CardHeader>
              </Card>
            ))}
          </div>

          <Card className="max-w-3xl mx-auto bg-gradient-to-r from-blue-50 to-purple-50 dark:from-blue-950 dark:to-purple-950 border-2">
            <CardContent className="p-8">
              <div className="flex items-start gap-4">
                <div className="w-12 h-12 rounded-full bg-primary/10 flex items-center justify-center flex-shrink-0">
                  <GitBranch className="h-6 w-6 text-primary" />
                </div>
                <div>
                  <h3 className="text-xl font-semibold mb-2">Migration Process</h3>
                  <div className="space-y-2 text-muted-foreground">
                    <p>1. <strong>Upload</strong> your existing workflow file</p>
                    <p>2. <strong>Auto-convert</strong> to BioMate format with tool compatibility checks</p>
                    <p>3. <strong>Enhance</strong> with AI parameter optimization and dataset integration</p>
                    <p>4. <strong>Run</strong> immediately with improved performance</p>
                  </div>
                </div>
              </div>
            </CardContent>
          </Card>
        </div>
      </section>

      {/* Testimonials Section */}
      <section className="py-24 border-b">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="text-center mb-16">
            <h2 className="text-4xl font-bold mb-4">
              Trusted by leading researchers
            </h2>
            <p className="text-xl text-muted-foreground">
              See what scientists are saying about BioMate
            </p>
          </div>

          <div className="grid md:grid-cols-3 gap-8">
            {testimonials.map((testimonial, index) => (
              <Card key={index}>
                <CardHeader>
                  <div className="flex items-center gap-4 mb-4">
                    <img
                      src={testimonial.image}
                      alt={testimonial.author}
                      className="w-12 h-12 rounded-full"
                    />
                    <div>
                      <div className="font-semibold">{testimonial.author}</div>
                      <div className="text-sm text-muted-foreground">{testimonial.role}</div>
                    </div>
                  </div>
                  <CardDescription className="text-base">
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
          <h2 className="text-4xl font-bold mb-4">
            Ready to accelerate your research?
          </h2>
          <p className="text-xl text-muted-foreground mb-8">
            Join thousands of researchers using BioMate to advance biomedicine
          </p>
          <div className="flex flex-col sm:flex-row gap-4 justify-center">
            <Button
              size="lg"
              className="text-lg px-8 py-6"
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
