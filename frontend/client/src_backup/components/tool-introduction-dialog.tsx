import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Separator } from "@/components/ui/separator"
import { 
  Clock, 
  Zap, 
  Settings, 
  FileText, 
  Play, 
  BookOpen,
  CheckCircle,
  AlertCircle,
  XCircle
} from "lucide-react"
import { cn } from "@/lib/utils"

interface ToolIntroductionDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  tool: ToolItem | null
  onAddToWorkflow?: (tool: ToolItem) => void
  onStartChat?: (tool: ToolItem) => void
}

interface ToolItem {
  id: string
  name: string
  description: string
  complexity: 'simple' | 'intermediate' | 'complex'
  category: string
  icon: any
}

// Extended tool information
const toolDetails: Record<string, {
  fullDescription: string
  inputs: string[]
  outputs: string[]
  parameters: Array<{ name: string; description: string; required: boolean }>
  useCases: string[]
  estimatedTime: string
  requirements: string[]
  citations?: string[]
}> = {
  fastqc: {
    fullDescription: "FastQC is a quality control tool for high throughput sequence data. It provides a modular set of analyses which you can use to give a quick impression of whether your data has any problems of which you should be aware before doing any further analysis.",
    inputs: ["FASTQ files", "SAM/BAM files"],
    outputs: ["HTML quality report", "Text summary file"],
    parameters: [
      { name: "Quality threshold", description: "Minimum quality score threshold", required: false },
      { name: "Adapter list", description: "File containing adapter sequences", required: false },
      { name: "Contaminant list", description: "File containing contaminant sequences", required: false }
    ],
    useCases: [
      "Quality assessment of raw sequencing reads",
      "Identification of adapter contamination",
      "Detection of overrepresented sequences",
      "Analysis of GC content distribution"
    ],
    estimatedTime: "2-5 minutes per file",
    requirements: ["FASTQ or SAM/BAM input files"],
    citations: ["Andrews, S. (2010). FastQC: a quality control tool for high throughput sequence data."]
  },
  hisat2: {
    fullDescription: "HISAT2 is a fast and sensitive alignment program for mapping next-generation sequencing reads to a population of human genomes. It uses an indexing scheme based on the Burrows-Wheeler transform and the FM index.",
    inputs: ["FASTQ files (single or paired-end)", "Reference genome index"],
    outputs: ["SAM/BAM alignment files", "Alignment summary statistics"],
    parameters: [
      { name: "Reference genome", description: "Path to reference genome index", required: true },
      { name: "Splice-aware mode", description: "Enable splice-aware alignment", required: false },
      { name: "Max intron length", description: "Maximum intron length", required: false },
      { name: "Thread count", description: "Number of parallel threads", required: false }
    ],
    useCases: [
      "RNA-seq read alignment",
      "Splice-aware mapping",
      "Transcriptome analysis",
      "Gene expression studies"
    ],
    estimatedTime: "10-30 minutes per sample",
    requirements: ["Reference genome index", "Quality-filtered FASTQ files"],
    citations: ["Kim, D., Langmead, B. & Salzberg, S. HISAT: a fast spliced aligner with low memory requirements. Nat Methods 12, 357–360 (2015)."]
  },
  deseq2: {
    fullDescription: "DESeq2 is an R package for differential gene expression analysis based on the negative binomial distribution. It provides methods for testing differential expression, shrinking log fold changes, and visualizing results.",
    inputs: ["Gene count matrix", "Sample metadata", "Experimental design"],
    outputs: ["Differential expression results", "Normalized count matrix", "Diagnostic plots"],
    parameters: [
      { name: "Design formula", description: "Experimental design formula", required: true },
      { name: "Contrast", description: "Comparison of interest", required: true },
      { name: "Alpha level", description: "Significance threshold", required: false },
      { name: "Log fold change threshold", description: "Minimum fold change", required: false }
    ],
    useCases: [
      "RNA-seq differential expression analysis",
      "Time course experiments",
      "Multi-factor experimental designs",
      "Batch effect correction"
    ],
    estimatedTime: "5-15 minutes depending on sample size",
    requirements: ["Gene count matrix", "Sample annotation", "R environment"],
    citations: ["Love, M.I., Huber, W., Anders, S. Moderated estimation of fold change and dispersion for RNA-seq data with DESeq2 Genome Biology 15(12):550 (2014)"]
  },
  gatk: {
    fullDescription: "The Genome Analysis Toolkit (GATK) is a structured software library that makes writing efficient analysis tools easy, and includes an extensive suite of tools for variant discovery and genotyping.",
    inputs: ["BAM alignment files", "Reference genome", "Known variant sites"],
    outputs: ["VCF variant files", "Quality metrics", "Filtered variants"],
    parameters: [
      { name: "Reference genome", description: "Reference FASTA file", required: true },
      { name: "Known sites", description: "VCF file of known variants", required: false },
      { name: "Ploidy", description: "Sample ploidy", required: false },
      { name: "Min base quality", description: "Minimum base quality score", required: false }
    ],
    useCases: [
      "SNP and indel discovery",
      "Germline variant calling",
      "Somatic mutation detection",
      "Population genetics studies"
    ],
    estimatedTime: "30-120 minutes per sample",
    requirements: ["Aligned BAM files", "Reference genome", "High-memory system"],
    citations: ["McKenna, A. et al. The Genome Analysis Toolkit: a MapReduce framework for analyzing next-generation DNA sequencing data. Genome Res. 20, 1297–1303 (2010)."]
  }
}

const complexityColors = {
  simple: "bg-green-100 text-green-700 dark:bg-green-900 dark:text-green-300",
  intermediate: "bg-yellow-100 text-yellow-700 dark:bg-yellow-900 dark:text-yellow-300", 
  complex: "bg-red-100 text-red-700 dark:bg-red-900 dark:text-red-300"
}

const complexityIcons = {
  simple: CheckCircle,
  intermediate: AlertCircle,
  complex: XCircle
}

export function ToolIntroductionDialog({ 
  open, 
  onOpenChange, 
  tool, 
  onAddToWorkflow = () => console.log('Add to workflow'),
  onStartChat = () => console.log('Start chat')
}: ToolIntroductionDialogProps) {
  if (!tool) return null

  const details = toolDetails[tool.id] || {
    fullDescription: tool.description,
    inputs: ["Various input formats"],
    outputs: ["Analysis results"],
    parameters: [],
    useCases: ["General bioinformatics analysis"],
    estimatedTime: "Variable",
    requirements: ["Input data"]
  }

  const ComplexityIcon = complexityIcons[tool.complexity]

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-4xl max-h-[80vh] overflow-y-auto" data-testid="dialog-tool-introduction">
        <DialogHeader>
          <div className="flex items-start gap-4">
            <div className="p-3 rounded-lg bg-primary/10">
              <tool.icon className="w-6 h-6 text-primary" />
            </div>
            <div className="flex-1 min-w-0">
              <DialogTitle className="text-2xl font-bold" data-testid="text-tool-name">
                {tool.name}
              </DialogTitle>
              <DialogDescription className="text-base mt-1">
                {tool.description}
              </DialogDescription>
              <div className="flex items-center gap-2 mt-3">
                <Badge variant="outline" className="text-xs" data-testid="badge-category">
                  {tool.category}
                </Badge>
                <Badge variant="outline" className="text-xs flex items-center gap-1" data-testid="badge-time">
                  <Clock className="w-3 h-3" />
                  {details.estimatedTime}
                </Badge>
              </div>
            </div>
          </div>
        </DialogHeader>

        <Separator className="my-6" />

        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          {/* Left Column */}
          <div className="space-y-6">
            <Card>
              <CardHeader>
                <CardTitle className="text-lg flex items-center gap-2">
                  <BookOpen className="w-4 h-4" />
                  Overview
                </CardTitle>
              </CardHeader>
              <CardContent>
                <p className="text-sm text-muted-foreground leading-relaxed">
                  {details.fullDescription}
                </p>
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <CardTitle className="text-lg flex items-center gap-2">
                  <Zap className="w-4 h-4" />
                  Use Cases
                </CardTitle>
              </CardHeader>
              <CardContent>
                <ul className="space-y-2">
                  {details.useCases.map((useCase, index) => (
                    <li key={index} className="text-sm text-muted-foreground flex items-start gap-2">
                      <div className="w-1.5 h-1.5 rounded-full bg-primary mt-2 flex-shrink-0" />
                      {useCase}
                    </li>
                  ))}
                </ul>
              </CardContent>
            </Card>

            {details.citations && (
              <Card>
                <CardHeader>
                  <CardTitle className="text-lg flex items-center gap-2">
                    <FileText className="w-4 h-4" />
                    Citations
                  </CardTitle>
                </CardHeader>
                <CardContent>
                  {details.citations.map((citation, index) => (
                    <p key={index} className="text-xs text-muted-foreground italic">
                      {citation}
                    </p>
                  ))}
                </CardContent>
              </Card>
            )}
          </div>

          {/* Right Column */}
          <div className="space-y-6">
            <Card>
              <CardHeader>
                <CardTitle className="text-lg">Input/Output</CardTitle>
              </CardHeader>
              <CardContent className="space-y-4">
                <div>
                  <h4 className="text-sm font-medium mb-2 text-green-600 dark:text-green-400">Inputs</h4>
                  <ul className="space-y-1">
                    {details.inputs.map((input, index) => (
                      <li key={index} className="text-sm text-muted-foreground">• {input}</li>
                    ))}
                  </ul>
                </div>
                <div>
                  <h4 className="text-sm font-medium mb-2 text-blue-600 dark:text-blue-400">Outputs</h4>
                  <ul className="space-y-1">
                    {details.outputs.map((output, index) => (
                      <li key={index} className="text-sm text-muted-foreground">• {output}</li>
                    ))}
                  </ul>
                </div>
              </CardContent>
            </Card>

            {details.parameters.length > 0 && (
              <Card>
                <CardHeader>
                  <CardTitle className="text-lg flex items-center gap-2">
                    <Settings className="w-4 h-4" />
                    Key Parameters
                  </CardTitle>
                </CardHeader>
                <CardContent>
                  <div className="space-y-3">
                    {details.parameters.map((param, index) => (
                      <div key={index} className="pb-3 border-b border-border/50 last:border-0 last:pb-0">
                        <div className="flex items-start justify-between gap-2">
                          <span className="text-sm font-medium">{param.name}</span>
                          {param.required && (
                            <Badge variant="destructive" className="text-xs">Required</Badge>
                          )}
                        </div>
                        <p className="text-xs text-muted-foreground mt-1">{param.description}</p>
                      </div>
                    ))}
                  </div>
                </CardContent>
              </Card>
            )}

            <Card>
              <CardHeader>
                <CardTitle className="text-lg">Requirements</CardTitle>
              </CardHeader>
              <CardContent>
                <ul className="space-y-1">
                  {details.requirements.map((req, index) => (
                    <li key={index} className="text-sm text-muted-foreground">• {req}</li>
                  ))}
                </ul>
              </CardContent>
            </Card>
          </div>
        </div>

        <Separator className="my-6" />

        <div className="flex justify-end gap-3">
          <Button 
            variant="outline" 
            onClick={() => onStartChat(tool)}
            data-testid="button-ask-questions"
          >
            <BookOpen className="w-4 h-4 mr-2" />
            Ask Questions
          </Button>
          <Button 
            onClick={() => onAddToWorkflow(tool)}
            data-testid="button-add-to-workflow"
          >
            <Play className="w-4 h-4 mr-2" />
            Add to Workflow
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  )
}