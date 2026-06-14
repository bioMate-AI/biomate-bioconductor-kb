import { useState } from "react"
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter } from "@/components/ui/dialog"
import { Button } from "@/components/ui/button"
import { Label } from "@/components/ui/label"
import { RadioGroup, RadioGroupItem } from "@/components/ui/radio-group"
import { Checkbox } from "@/components/ui/checkbox"
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert"
import { Badge } from "@/components/ui/badge"
import { ScrollArea } from "@/components/ui/scroll-area"
import {
  Laptop,
  ExternalLink,
  Loader2,
  AlertCircle,
  Check,
  Copy,
  Clock,
  FileOutput
} from "lucide-react"

interface OutputFile {
  id: string
  name: string
  size: number
  type?: string
}

interface InteractiveLauncherProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  outputs?: OutputFile[]
  historyId?: string
}

type InteractiveTool = 'jupyter' | 'rstudio' | 'cellxgene'

const INTERACTIVE_TOOLS: Record<InteractiveTool, {
  name: string
  description: string
  preloaded: string[]
  bestFor: string
}> = {
  jupyter: {
    name: 'Jupyter Notebook',
    description: 'Python 3.10 interactive environment',
    preloaded: ['pandas', 'numpy', 'matplotlib', 'seaborn', 'scanpy', 'scikit-learn'],
    bestFor: 'Custom analysis, visualization, machine learning'
  },
  rstudio: {
    name: 'RStudio',
    description: 'R 4.3 statistical computing environment',
    preloaded: ['DESeq2', 'edgeR', 'ggplot2', 'tidyverse', 'Bioconductor'],
    bestFor: 'Statistical analysis, Bioconductor packages'
  },
  cellxgene: {
    name: 'CellxGene',
    description: 'Interactive single-cell visualization',
    preloaded: ['Scanpy integration', 'UMAP/t-SNE', 'Gene expression browser'],
    bestFor: 'Single-cell RNA-seq visualization and exploration'
  }
}

export function InteractiveLauncher({
  open,
  onOpenChange,
  outputs = [],
  historyId
}: InteractiveLauncherProps) {
  const [selectedTool, setSelectedTool] = useState<InteractiveTool>('jupyter')
  const [selectedOutputs, setSelectedOutputs] = useState<Set<string>>(new Set())
  const [isLaunching, setIsLaunching] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [session, setSession] = useState<{
    jobId: string
    entryPointUrl?: string
    state: string
  } | null>(null)
  const [copied, setCopied] = useState(false)

  const formatFileSize = (bytes: number): string => {
    if (bytes === 0) return '0 B'
    const k = 1024
    const sizes = ['B', 'KB', 'MB', 'GB']
    const i = Math.floor(Math.log(bytes) / Math.log(k))
    return Math.round(bytes / Math.pow(k, i) * 100) / 100 + ' ' + sizes[i]
  }

  const toggleOutput = (outputId: string) => {
    setSelectedOutputs(prev => {
      const next = new Set(prev)
      if (next.has(outputId)) {
        next.delete(outputId)
      } else {
        next.add(outputId)
      }
      return next
    })
  }

  const selectAllOutputs = () => {
    if (selectedOutputs.size === outputs.length) {
      setSelectedOutputs(new Set())
    } else {
      setSelectedOutputs(new Set(outputs.map(o => o.id)))
    }
  }

  const handleLaunch = async () => {
    setIsLaunching(true)
    setError(null)

    try {
      const response = await fetch('/api/interactive/launch', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          tool_id: selectedTool === 'jupyter' ? 'interactive_tool_jupyter_notebook' :
                   selectedTool === 'rstudio' ? 'interactive_tool_rstudio' :
                   'interactive_tool_cellxgene',
          inputs: {
            history_id: historyId,
            dataset_ids: Array.from(selectedOutputs)
          }
        })
      })

      if (!response.ok) {
        const errorData = await response.json()
        throw new Error(errorData.message || 'Failed to launch interactive tool')
      }

      const data = await response.json()
      setSession({
        jobId: data.job_id,
        entryPointUrl: data.entry_point_url,
        state: data.state
      })
    } catch (err: any) {
      setError(err.message || 'Failed to launch interactive tool')
    } finally {
      setIsLaunching(false)
    }
  }

  const handleCopyCode = async () => {
    const code = selectedTool === 'jupyter'
      ? `import pandas as pd\n\n# Load your workflow outputs\n${outputs.filter(o => selectedOutputs.has(o.id)).map(o =>
          `# ${o.name}\ndf_${o.name.replace(/[^a-zA-Z0-9]/g, '_')} = pd.read_csv('/data/${o.name}', sep='\\t')`
        ).join('\n\n')}`
      : `library(tidyverse)\n\n# Load your workflow outputs\n${outputs.filter(o => selectedOutputs.has(o.id)).map(o =>
          `# ${o.name}\ndf_${o.name.replace(/[^a-zA-Z0-9]/g, '_')} <- read_tsv('/data/${o.name}')`
        ).join('\n\n')}`

    await navigator.clipboard.writeText(code)
    setCopied(true)
    setTimeout(() => setCopied(false), 2000)
  }

  const toolInfo = INTERACTIVE_TOOLS[selectedTool]

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Laptop className="h-5 w-5" />
            Launch Interactive Environment
          </DialogTitle>
          <DialogDescription>
            Explore your workflow outputs in an interactive computing environment
          </DialogDescription>
        </DialogHeader>

        {!session ? (
          <>
            {/* Tool Selection */}
            <div className="space-y-4">
              <Label className="text-sm font-medium">Choose Environment</Label>
              <RadioGroup
                value={selectedTool}
                onValueChange={(v) => setSelectedTool(v as InteractiveTool)}
                className="space-y-3"
              >
                {(Object.entries(INTERACTIVE_TOOLS) as [InteractiveTool, typeof INTERACTIVE_TOOLS['jupyter']][]).map(([key, tool]) => (
                  <div
                    key={key}
                    className={`flex items-start space-x-3 p-3 rounded-lg border cursor-pointer transition-colors ${
                      selectedTool === key ? 'border-primary bg-primary/5' : 'hover:bg-muted/50'
                    }`}
                    onClick={() => setSelectedTool(key)}
                  >
                    <RadioGroupItem value={key} id={key} className="mt-1" />
                    <div className="flex-1">
                      <Label htmlFor={key} className="text-sm font-medium cursor-pointer">
                        {tool.name}
                      </Label>
                      <p className="text-xs text-muted-foreground mt-0.5">
                        {tool.description}
                      </p>
                      <p className="text-xs text-muted-foreground mt-1">
                        <strong>Best for:</strong> {tool.bestFor}
                      </p>
                      <div className="flex flex-wrap gap-1 mt-2">
                        {tool.preloaded.slice(0, 4).map(pkg => (
                          <Badge key={pkg} variant="secondary" className="text-xs">
                            {pkg}
                          </Badge>
                        ))}
                        {tool.preloaded.length > 4 && (
                          <Badge variant="outline" className="text-xs">
                            +{tool.preloaded.length - 4} more
                          </Badge>
                        )}
                      </div>
                    </div>
                  </div>
                ))}
              </RadioGroup>
            </div>

            {/* Output Selection */}
            {outputs.length > 0 && (
              <div className="space-y-3">
                <div className="flex items-center justify-between">
                  <Label className="text-sm font-medium">Data to Load</Label>
                  <Button
                    variant="ghost"
                    size="sm"
                    className="text-xs h-7"
                    onClick={selectAllOutputs}
                  >
                    {selectedOutputs.size === outputs.length ? 'Deselect All' : 'Select All'}
                  </Button>
                </div>
                <ScrollArea className="h-40 border rounded-lg p-2">
                  <div className="space-y-2">
                    {outputs.map(output => (
                      <label
                        key={output.id}
                        htmlFor={`launcher-output-${output.id}`}
                        className="flex items-center space-x-2 p-2 rounded hover:bg-muted/50 cursor-pointer"
                      >
                        <Checkbox
                          id={`launcher-output-${output.id}`}
                          checked={selectedOutputs.has(output.id)}
                          onCheckedChange={() => toggleOutput(output.id)}
                        />
                        <FileOutput className="h-4 w-4 text-muted-foreground" />
                        <span className="text-sm flex-1 truncate">{output.name}</span>
                        <span className="text-xs text-muted-foreground">
                          {formatFileSize(output.size)}
                        </span>
                      </label>
                    ))}
                  </div>
                </ScrollArea>
                <p className="text-xs text-muted-foreground">
                  {selectedOutputs.size} file{selectedOutputs.size !== 1 ? 's' : ''} selected
                </p>
              </div>
            )}

            {/* Timeout Warning */}
            <Alert>
              <Clock className="h-4 w-4" />
              <AlertDescription className="text-xs">
                Interactive sessions timeout after 2 hours of inactivity. Your work is saved to the Galaxy history.
              </AlertDescription>
            </Alert>

            {error && (
              <Alert variant="destructive">
                <AlertCircle className="h-4 w-4" />
                <AlertDescription>{error}</AlertDescription>
              </Alert>
            )}

            <DialogFooter>
              <Button variant="outline" onClick={() => onOpenChange(false)}>
                Cancel
              </Button>
              <Button onClick={handleLaunch} disabled={isLaunching}>
                {isLaunching ? (
                  <>
                    <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                    Launching...
                  </>
                ) : (
                  <>
                    <Laptop className="h-4 w-4 mr-2" />
                    Launch {toolInfo.name}
                  </>
                )}
              </Button>
            </DialogFooter>
          </>
        ) : (
          /* Session Active */
          <div className="space-y-4">
            <Alert className="border-green-500/50 bg-green-50/50 dark:bg-green-950/20">
              <Check className="h-4 w-4 text-green-600" />
              <AlertTitle className="text-green-800 dark:text-green-200">
                {toolInfo.name} Session Active
              </AlertTitle>
              <AlertDescription className="text-green-700 dark:text-green-300">
                <p className="text-sm">Your interactive environment is ready.</p>
                <p className="text-xs mt-1">State: {session.state}</p>
              </AlertDescription>
            </Alert>

            {session.entryPointUrl ? (
              <div className="space-y-3">
                <Button
                  className="w-full"
                  onClick={() => window.open(session.entryPointUrl, '_blank')}
                >
                  <ExternalLink className="h-4 w-4 mr-2" />
                  Open {toolInfo.name} in New Tab
                </Button>

                <div className="p-3 bg-muted rounded-lg">
                  <div className="flex items-center justify-between mb-2">
                    <Label className="text-xs font-medium">Quick Start Code</Label>
                    <Button
                      variant="ghost"
                      size="sm"
                      className="h-6 text-xs"
                      onClick={handleCopyCode}
                    >
                      {copied ? (
                        <>
                          <Check className="h-3 w-3 mr-1" />
                          Copied
                        </>
                      ) : (
                        <>
                          <Copy className="h-3 w-3 mr-1" />
                          Copy
                        </>
                      )}
                    </Button>
                  </div>
                  <pre className="text-xs font-mono overflow-x-auto p-2 bg-background rounded">
                    {selectedTool === 'jupyter'
                      ? `import pandas as pd\n# Your data is in /data/`
                      : `library(tidyverse)\n# Your data is in /data/`
                    }
                  </pre>
                </div>

                {selectedOutputs.size > 0 && (
                  <div className="text-xs text-muted-foreground">
                    <p className="font-medium mb-1">Pre-loaded data:</p>
                    <ul className="list-disc list-inside">
                      {outputs.filter(o => selectedOutputs.has(o.id)).map(o => (
                        <li key={o.id}>/data/{o.name}</li>
                      ))}
                    </ul>
                  </div>
                )}
              </div>
            ) : (
              <div className="flex items-center justify-center py-8">
                <Loader2 className="h-6 w-6 animate-spin text-muted-foreground mr-2" />
                <span className="text-muted-foreground">Waiting for session URL...</span>
              </div>
            )}

            <DialogFooter>
              <Button variant="outline" onClick={() => {
                setSession(null)
                onOpenChange(false)
              }}>
                Close
              </Button>
            </DialogFooter>
          </div>
        )}
      </DialogContent>
    </Dialog>
  )
}
