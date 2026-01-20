/**
 * Interactive Tool Launcher Component
 * Suggests and launches Galaxy Interactive Tools based on output file types
 */

import { useState } from "react"
import { useMutation } from "@tanstack/react-query"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Skeleton } from "@/components/ui/skeleton"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog"
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from "@/components/ui/tooltip"
import {
  ExternalLink,
  Play,
  Loader2,
  AlertCircle,
  Microscope,
  Code,
  BarChart3,
  Network,
  FileSpreadsheet,
  Dna,
  Info,
} from "lucide-react"
import type { OutputDataset } from "@shared/schema"

interface InteractiveToolLauncherProps {
  outputs: OutputDataset[]
  className?: string
}

interface InteractiveTool {
  id: string
  name: string
  description: string
  icon: React.ReactNode
  supportedFormats: string[]
  galaxyToolId: string
  category: 'analysis' | 'visualization' | 'notebook' | 'browser'
}

// Available Galaxy Interactive Tools with their supported formats
const INTERACTIVE_TOOLS: InteractiveTool[] = [
  {
    id: 'cellxgene',
    name: 'CellxGene',
    description: 'Interactive single-cell data explorer with UMAP/t-SNE visualization',
    icon: <Network className="h-5 w-5" />,
    supportedFormats: ['h5ad', 'loom'],
    galaxyToolId: 'interactive_tool_cellxgene',
    category: 'visualization',
  },
  {
    id: 'jupyter',
    name: 'JupyterLab',
    description: 'Interactive Python/R notebook environment for custom analysis',
    icon: <Code className="h-5 w-5" />,
    supportedFormats: ['*'], // Supports all formats
    galaxyToolId: 'interactive_tool_jupyter_notebook',
    category: 'notebook',
  },
  {
    id: 'rstudio',
    name: 'RStudio',
    description: 'R development environment for statistical analysis',
    icon: <BarChart3 className="h-5 w-5" />,
    supportedFormats: ['csv', 'tsv', 'rdata', 'rds', 'txt'],
    galaxyToolId: 'interactive_tool_rstudio',
    category: 'notebook',
  },
  {
    id: 'pavian',
    name: 'Pavian',
    description: 'Interactive metagenomics visualization for Kraken/Bracken reports',
    icon: <Microscope className="h-5 w-5" />,
    supportedFormats: ['kreport', 'bracken', 'txt'],
    galaxyToolId: 'interactive_tool_pavian',
    category: 'visualization',
  },
  {
    id: 'igv',
    name: 'IGV',
    description: 'Integrative Genomics Viewer for alignment and variant visualization',
    icon: <Dna className="h-5 w-5" />,
    supportedFormats: ['bam', 'vcf', 'bed', 'gff', 'gtf', 'bigwig', 'bigbed'],
    galaxyToolId: 'interactive_tool_igv',
    category: 'browser',
  },
  {
    id: 'jbrowse',
    name: 'JBrowse',
    description: 'Genome browser for exploring alignments and annotations',
    icon: <Dna className="h-5 w-5" />,
    supportedFormats: ['bam', 'vcf', 'bed', 'gff', 'gtf', 'fasta'],
    galaxyToolId: 'interactive_tool_jbrowse2',
    category: 'browser',
  },
  {
    id: 'phinch',
    name: 'Phinch',
    description: 'Visualization framework for biological data (BIOM files)',
    icon: <FileSpreadsheet className="h-5 w-5" />,
    supportedFormats: ['biom'],
    galaxyToolId: 'interactive_tool_phinch',
    category: 'visualization',
  },
]

interface LaunchToolRequest {
  toolId: string
  datasetIds: string[]
}

interface LaunchToolResponse {
  success: boolean
  url?: string
  jobId?: string
  error?: string
}

export function InteractiveToolLauncher({ outputs, className }: InteractiveToolLauncherProps) {
  const [selectedTool, setSelectedTool] = useState<InteractiveTool | null>(null)
  const [selectedOutputs, setSelectedOutputs] = useState<Set<string>>(new Set())
  const [dialogOpen, setDialogOpen] = useState(false)
  const [launchedUrl, setLaunchedUrl] = useState<string | null>(null)

  // Find tools that support the given outputs
  const getSuggestedTools = (): InteractiveTool[] => {
    const extensions = new Set(outputs.map(o => o.extension.toLowerCase()))

    return INTERACTIVE_TOOLS.filter(tool => {
      if (tool.supportedFormats.includes('*')) return true
      return tool.supportedFormats.some(format =>
        Array.from(extensions).some(ext => ext.includes(format))
      )
    })
  }

  const suggestedTools = getSuggestedTools()

  // Mutation to launch interactive tool
  const launchMutation = useMutation<LaunchToolResponse, Error, LaunchToolRequest>({
    mutationFn: async ({ toolId, datasetIds }) => {
      const response = await fetch('/api/interactive-tools/launch', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ toolId, datasetIds }),
      })
      if (!response.ok) {
        const error = await response.json()
        throw new Error(error.message || 'Failed to launch interactive tool')
      }
      return response.json()
    },
    onSuccess: (data) => {
      if (data.url) {
        setLaunchedUrl(data.url)
      }
    },
  })

  const handleToolSelect = (tool: InteractiveTool) => {
    setSelectedTool(tool)

    // Pre-select compatible outputs
    const compatibleOutputs = outputs.filter(o => {
      if (tool.supportedFormats.includes('*')) return true
      return tool.supportedFormats.some(format =>
        o.extension.toLowerCase().includes(format)
      )
    })
    setSelectedOutputs(new Set(compatibleOutputs.map(o => o.id)))
    setDialogOpen(true)
  }

  const handleLaunch = () => {
    if (!selectedTool || selectedOutputs.size === 0) return

    launchMutation.mutate({
      toolId: selectedTool.galaxyToolId,
      datasetIds: Array.from(selectedOutputs),
    })
  }

  const toggleOutputSelection = (outputId: string) => {
    const newSelection = new Set(selectedOutputs)
    if (newSelection.has(outputId)) {
      newSelection.delete(outputId)
    } else {
      newSelection.add(outputId)
    }
    setSelectedOutputs(newSelection)
  }

  const getCategoryColor = (category: string): string => {
    switch (category) {
      case 'visualization': return 'bg-purple-100 text-purple-800'
      case 'notebook': return 'bg-blue-100 text-blue-800'
      case 'browser': return 'bg-green-100 text-green-800'
      default: return 'bg-gray-100 text-gray-800'
    }
  }

  if (outputs.length === 0) return null

  return (
    <Card className={className}>
      <CardHeader>
        <CardTitle className="flex items-center gap-2 text-base">
          <Play className="h-4 w-4" />
          Interactive Analysis
        </CardTitle>
        <CardDescription>
          Launch interactive tools to explore your outputs
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        {suggestedTools.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            No interactive tools available for these output formats.
          </p>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
            {suggestedTools.map((tool) => (
              <TooltipProvider key={tool.id}>
                <Tooltip>
                  <TooltipTrigger asChild>
                    <Button
                      variant="outline"
                      className="h-auto py-3 px-4 justify-start"
                      onClick={() => handleToolSelect(tool)}
                    >
                      <div className="flex items-start gap-3">
                        <div className="p-2 rounded-lg bg-muted">
                          {tool.icon}
                        </div>
                        <div className="text-left">
                          <div className="flex items-center gap-2">
                            <span className="font-medium">{tool.name}</span>
                            <Badge variant="secondary" className={`text-xs ${getCategoryColor(tool.category)}`}>
                              {tool.category}
                            </Badge>
                          </div>
                          <p className="text-xs text-muted-foreground mt-1 line-clamp-2">
                            {tool.description}
                          </p>
                        </div>
                      </div>
                    </Button>
                  </TooltipTrigger>
                  <TooltipContent side="bottom" className="max-w-xs">
                    <p className="text-sm">{tool.description}</p>
                    <p className="text-xs text-muted-foreground mt-1">
                      Formats: {tool.supportedFormats.join(', ')}
                    </p>
                  </TooltipContent>
                </Tooltip>
              </TooltipProvider>
            ))}
          </div>
        )}

        {/* Launch Dialog */}
        <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
          <DialogContent className="max-w-lg">
            <DialogHeader>
              <DialogTitle className="flex items-center gap-2">
                {selectedTool?.icon}
                Launch {selectedTool?.name}
              </DialogTitle>
              <DialogDescription>
                {selectedTool?.description}
              </DialogDescription>
            </DialogHeader>

            {launchedUrl ? (
              <div className="space-y-4">
                <div className="p-4 rounded-lg bg-green-50 border border-green-200">
                  <p className="text-sm text-green-800 font-medium">
                    Interactive session launched successfully!
                  </p>
                  <p className="text-xs text-green-600 mt-1">
                    Your session is now ready. Click below to open it in a new tab.
                  </p>
                </div>
                <Button
                  className="w-full"
                  onClick={() => window.open(launchedUrl, '_blank')}
                >
                  <ExternalLink className="h-4 w-4 mr-2" />
                  Open {selectedTool?.name}
                </Button>
              </div>
            ) : (
              <>
                <div className="space-y-3">
                  <div className="flex items-center gap-2 text-sm font-medium">
                    <Info className="h-4 w-4 text-muted-foreground" />
                    Select outputs to include:
                  </div>
                  <div className="max-h-48 overflow-y-auto space-y-2">
                    {outputs.map((output) => {
                      const isCompatible = selectedTool?.supportedFormats.includes('*') ||
                        selectedTool?.supportedFormats.some(f =>
                          output.extension.toLowerCase().includes(f)
                        )

                      return (
                        <label
                          key={output.id}
                          className={`flex items-center gap-3 p-2 rounded-lg border cursor-pointer transition-colors ${
                            selectedOutputs.has(output.id)
                              ? 'bg-primary/5 border-primary'
                              : 'hover:bg-muted/50'
                          } ${!isCompatible ? 'opacity-50' : ''}`}
                        >
                          <input
                            type="checkbox"
                            checked={selectedOutputs.has(output.id)}
                            onChange={() => toggleOutputSelection(output.id)}
                            disabled={!isCompatible}
                            className="rounded"
                          />
                          <div className="flex-1 min-w-0">
                            <p className="text-sm font-medium truncate">{output.name}</p>
                            <p className="text-xs text-muted-foreground">
                              {output.extension.toUpperCase()} • {(output.size / 1024).toFixed(1)} KB
                            </p>
                          </div>
                          {!isCompatible && (
                            <Badge variant="outline" className="text-xs">
                              Incompatible
                            </Badge>
                          )}
                        </label>
                      )
                    })}
                  </div>
                </div>

                {launchMutation.isError && (
                  <div className="p-3 rounded-lg bg-destructive/10 border border-destructive/20">
                    <div className="flex items-center gap-2 text-sm text-destructive">
                      <AlertCircle className="h-4 w-4" />
                      {launchMutation.error.message}
                    </div>
                  </div>
                )}

                <DialogFooter>
                  <Button variant="outline" onClick={() => setDialogOpen(false)}>
                    Cancel
                  </Button>
                  <Button
                    onClick={handleLaunch}
                    disabled={selectedOutputs.size === 0 || launchMutation.isPending}
                  >
                    {launchMutation.isPending ? (
                      <>
                        <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                        Launching...
                      </>
                    ) : (
                      <>
                        <Play className="h-4 w-4 mr-2" />
                        Launch {selectedTool?.name}
                      </>
                    )}
                  </Button>
                </DialogFooter>
              </>
            )}
          </DialogContent>
        </Dialog>
      </CardContent>
    </Card>
  )
}
