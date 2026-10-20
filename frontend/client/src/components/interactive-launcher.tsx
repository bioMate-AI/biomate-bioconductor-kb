import { useState, useEffect } from "react"
import { recommendViewers, VIEWER_META, VIEWER_TOOL_ID, type ViewerKey } from "@/lib/interactive-viewers"
import { useInteractiveToolsAvailable } from "@/hooks/use-interactive-tools"
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
  /** Byte size when known; omitted for sources (e.g. Nextflow S3 listings)
   *  that don't report it — the row then shows no size rather than "0 B". */
  size?: number
  type?: string
}

interface InteractiveLauncherProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  outputs?: OutputFile[]
  historyId?: string
  /** Explicitly pre-select this viewer. Usually leave unset and pass `datasetFormat` instead —
   *  the primary viewer is then auto-selected by the dataset's Galaxy datatype. */
  initialTool?: InteractiveTool
  /** Dataset Galaxy datatype/extension (e.g. 'h5ad','vcf','bam'). Drives auto-selection: the matching
   *  viewer is pre-selected and only relevant viewers (+ Jupyter/RStudio escape-hatch) are shown. */
  datasetFormat?: string
}

// Viewer identity + metadata now live in the shared registry (src/lib/interactive-viewers.ts) so the
// format→viewer mapping is one source of truth. Optional preloaded-package badges augment the meta.
type InteractiveTool = ViewerKey

const PRELOADED: Partial<Record<InteractiveTool, string[]>> = {
  jupyter: ['pandas', 'numpy', 'matplotlib', 'scanpy', 'scikit-learn'],
  rstudio: ['DESeq2', 'edgeR', 'ggplot2', 'tidyverse', 'Bioconductor'],
  cellxgene: ['UMAP/t-SNE', 'Gene expression browser'],
}
const INTERACTIVE_TOOLS: Record<InteractiveTool, { name: string; description: string; bestFor: string; preloaded: string[] }> =
  Object.fromEntries(
    (Object.keys(VIEWER_META) as InteractiveTool[]).map((k) => [k, { ...VIEWER_META[k], preloaded: PRELOADED[k] ?? [] }])
  ) as any

export function InteractiveLauncher({
  open,
  onOpenChange,
  outputs = [],
  historyId,
  initialTool,
  datasetFormat,
}: InteractiveLauncherProps) {
  // Contextual launch (a dataset format is known) → auto-select the primary viewer and show only
  // relevant ones (+ Jupyter/RStudio escape-hatch). Manual launch from the panel (no format) → show
  // ALL viewers and default to Jupyter. Explicit initialTool always wins.
  const rec = recommendViewers(datasetFormat)
  const allViewers = Object.keys(VIEWER_META) as InteractiveTool[]
  const defaultTool: InteractiveTool = initialTool ?? (datasetFormat ? rec.primary : 'jupyter')
  const shownTools: InteractiveTool[] = datasetFormat ? [rec.primary, ...rec.alternatives] : allViewers
  const [selectedTool, setSelectedTool] = useState<InteractiveTool>(defaultTool)

  // Re-apply the auto-selection whenever the dialog opens or the dataset/tool changes.
  // Because Dialog doesn't unmount, state persists between opens.
  useEffect(() => {
    if (open) setSelectedTool(defaultTool)
  }, [open, initialTool, datasetFormat])
  const [selectedOutputs, setSelectedOutputs] = useState<Set<string>>(new Set())
  const [isLaunching, setIsLaunching] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [session, setSession] = useState<{
    jobId: string
    entryPointUrl?: string
    state: string
  } | null>(null)
  const [copied, setCopied] = useState(false)
  const { data: itAvail } = useInteractiveToolsAvailable()
  // Known-unavailable only for the tools we actually probe (jupyter/rstudio/
  // cellxgene); other tools stay optimistic and rely on the launch error path.
  const probedTools = itAvail ? (itAvail.tools as Record<string, boolean>) : null
  const selectedToolAvailable = !probedTools || !(selectedTool in probedTools) || probedTools[selectedTool]
  // The launch API returns the session URL as soon as the entry-point row exists (~1-2s),
  // but the container needs ~10-30s more to actually serve — the URL 503s until then.
  // Poll it to readiness so we don't hand the user a dead link. 'timeout' still lets them
  // open it (slow boots do eventually serve); it just drops the "ready" guarantee.
  const [readyState, setReadyState] = useState<'idle' | 'starting' | 'ready' | 'timeout'>('idle')

  useEffect(() => {
    const url = session?.entryPointUrl
    if (!url) { setReadyState('idle'); return }
    let cancelled = false
    setReadyState('starting')
    const started = Date.now()
    const MAX_MS = 45000
    const tick = async () => {
      if (cancelled) return
      try {
        // Same-origin GET through our /interactive proxy; 200 once the container serves,
        // 503 while it (or its DB linkage) is still coming up.
        const res = await fetch(url, { method: 'GET', redirect: 'manual', cache: 'no-store' })
        // 200 = serving; opaqueredirect (status 0) = a redirect from a live upstream.
        // 503 = our proxy couldn't resolve/reach the container yet → keep polling.
        if (!cancelled && (res.status === 200 || res.type === 'opaqueredirect')) {
          setReadyState('ready'); return
        }
      } catch { /* network blip — keep polling */ }
      if (cancelled) return
      if (Date.now() - started > MAX_MS) { setReadyState('timeout'); return }
      setTimeout(tick, 2000)
    }
    const t = setTimeout(tick, 1000)
    return () => { cancelled = true; clearTimeout(t) }
  }, [session?.entryPointUrl])

  // Galaxy launches interactive tools asynchronously: /api/interactive/launch
  // returns { state: "queued", entry_point_url: null } immediately, and the
  // real URL only appears once the session container starts. That URL surfaces
  // on /api/interactive/sessions as the `target` field (rewritten server-side
  // to the public proxy host). Poll for it until it's ready, then stop.
  useEffect(() => {
    if (!session?.jobId || session.entryPointUrl) return
    let cancelled = false
    let attempts = 0
    const maxAttempts = 40 // ~2 min at 3s intervals
    const timer = setInterval(async () => {
      attempts += 1
      if (cancelled) return
      try {
        const resp = await fetch('/api/interactive/sessions', { credentials: 'include' })
        if (resp.ok) {
          const data = await resp.json()
          const match = (data.sessions || []).find((s: any) => s.job_id === session.jobId)
          const url = match?.target || match?.entry_point_url || match?.url
          if (url) {
            if (!cancelled) {
              setSession(prev => prev ? { ...prev, entryPointUrl: url, state: match?.state || 'running' } : prev)
            }
            clearInterval(timer)
            return
          }
        }
      } catch { /* keep polling */ }
      if (attempts >= maxAttempts) {
        clearInterval(timer)
        if (!cancelled) setError('Session is taking longer than expected to start. Please try again.')
      }
    }, 3000)
    return () => { cancelled = true; clearInterval(timer) }
  }, [session?.jobId, session?.entryPointUrl])

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
          tool_id: VIEWER_TOOL_ID[selectedTool],
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
                {shownTools.map((key, idx) => {
                  const tool = INTERACTIVE_TOOLS[key]
                  const preloaded = tool.preloaded ?? []
                  return (
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
                        {idx === 0 && datasetFormat && (
                          <Badge variant="secondary" className="ml-2 text-[10px]">Recommended for .{datasetFormat}</Badge>
                        )}
                      </Label>
                      <p className="text-xs text-muted-foreground mt-0.5">
                        {tool.description}
                      </p>
                      <p className="text-xs text-muted-foreground mt-1">
                        <strong>Best for:</strong> {tool.bestFor}
                      </p>
                      {preloaded.length > 0 && (
                        <div className="flex flex-wrap gap-1 mt-2">
                          {preloaded.slice(0, 4).map(pkg => (
                            <Badge key={pkg} variant="secondary" className="text-xs">{pkg}</Badge>
                          ))}
                          {preloaded.length > 4 && (
                            <Badge variant="outline" className="text-xs">+{preloaded.length - 4} more</Badge>
                          )}
                        </div>
                      )}
                    </div>
                  </div>
                  )
                })}
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
                        {/* Only show a size when we actually know it — Nextflow S3
                            output listings often carry no byte count, and a bogus
                            "0 B" on a non-empty file is worse than no size. */}
                        {typeof output.size === 'number' && output.size > 0 && (
                          <span className="text-xs text-muted-foreground">
                            {formatFileSize(output.size)}
                          </span>
                        )}
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
                Interactive sessions timeout after 2 hours of inactivity. Your work is auto-saved.
              </AlertDescription>
            </Alert>

            {error && (
              <Alert variant="destructive">
                <AlertCircle className="h-4 w-4" />
                <AlertDescription>{error}</AlertDescription>
              </Alert>
            )}

            {!selectedToolAvailable && (
              <Alert>
                <AlertCircle className="h-4 w-4" />
                <AlertDescription>
                  {toolInfo.name} isn’t enabled in this environment yet. Download the file(s) and
                  analyze them locally, or ask an admin to provision interactive tools.
                </AlertDescription>
              </Alert>
            )}

            <DialogFooter>
              <Button variant="outline" onClick={() => onOpenChange(false)}>
                Cancel
              </Button>
              <Button onClick={handleLaunch} disabled={isLaunching || !selectedToolAvailable}>
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
            {readyState === 'starting' ? (
              <Alert className="border-blue-500/50 bg-blue-50/50 dark:bg-blue-950/20">
                <Loader2 className="h-4 w-4 text-blue-600 animate-spin" />
                <AlertTitle className="text-blue-800 dark:text-blue-200">
                  Starting {toolInfo.name}…
                </AlertTitle>
                <AlertDescription className="text-blue-700 dark:text-blue-300">
                  <p className="text-sm">Your container is booting — this can take up to ~30 seconds.</p>
                  <p className="text-xs mt-1">State: {session.state}</p>
                </AlertDescription>
              </Alert>
            ) : (
              <Alert className="border-green-500/50 bg-green-50/50 dark:bg-green-950/20">
                <Check className="h-4 w-4 text-green-600" />
                <AlertTitle className="text-green-800 dark:text-green-200">
                  {toolInfo.name} Session {readyState === 'timeout' ? 'Launched' : 'Active'}
                </AlertTitle>
                <AlertDescription className="text-green-700 dark:text-green-300">
                  <p className="text-sm">
                    {readyState === 'timeout'
                      ? 'Still finishing startup — you can open it now; it may take a few more seconds to load.'
                      : 'Your interactive environment is ready.'}
                  </p>
                  <p className="text-xs mt-1">State: {session.state}</p>
                </AlertDescription>
              </Alert>
            )}

            {session.entryPointUrl ? (
              <div className="space-y-3">
                <Button
                  className="w-full"
                  disabled={readyState === 'starting'}
                  onClick={() => window.open(session.entryPointUrl, '_blank')}
                >
                  {readyState === 'starting' ? (
                    <>
                      <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                      Waiting for {toolInfo.name} to start…
                    </>
                  ) : (
                    <>
                      <ExternalLink className="h-4 w-4 mr-2" />
                      Open {toolInfo.name} in New Tab
                    </>
                  )}
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
