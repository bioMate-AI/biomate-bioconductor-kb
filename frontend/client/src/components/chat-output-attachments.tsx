import { useState, useEffect } from "react"
import { useQuery } from "@tanstack/react-query"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Skeleton } from "@/components/ui/skeleton"
import {
  Download,
  Eye,
  EyeOff,
  FileText,
  Image as ImageIcon,
  FileCode,
  File,
  ExternalLink,
  Dna,
  Layers,
  Network,
} from "lucide-react"
import type { OutputDataset } from "@shared/schema"
import { VCFViewer, SequenceViewer, AnnotationViewer, InteractiveToolLauncher } from "./viewers"
import { CsvTableViewer } from "./viewers/csv-table-viewer"
import { StructureViewer } from "./viewers/structure-viewer"
import { DensityMapViewer } from "./viewers/density-map-viewer"
import { ReportConfusionButton } from "./feedback/report-confusion-button"
import { DownloadOutcomePrompt } from "./feedback/download-outcome-prompt"
import { emitUxEvent } from "@/lib/ux-telemetry"
import { StatusBadge } from "@/components/ui/status-badge"

interface ChatOutputAttachmentsProps {
  invocationId: string
  sessionId?: string
  runId?: string
  executionStatus?: string
  errorMessage?: string
  className?: string
}

export function ChatOutputAttachments({
  invocationId,
  sessionId,
  runId,
  executionStatus,
  errorMessage,
  className,
}: ChatOutputAttachmentsProps) {
  const [downloadPromptOpen, setDownloadPromptOpen] = useState(false)
  const [downloadPromptContext, setDownloadPromptContext] = useState<{
    outputId?: string
    outputName?: string
    isDownloadAll?: boolean
  } | null>(null)

  const { data: outputs = [], isLoading, refetch } = useQuery<OutputDataset[]>({
    queryKey: ['outputs', invocationId],
    queryFn: async () => {
      const response = await fetch(`/api/invocations/${invocationId}/outputs`)
      if (!response.ok) throw new Error('Failed to fetch outputs')
      return response.json()
    },
    refetchInterval: (query) => {
      const data = (query.state.data as OutputDataset[] | undefined) || []
      if (data.length > 0) return false
      if (executionStatus === 'running' || executionStatus === 'completed') return 3000
      return false
    },
  })

  useEffect(() => {
    if (outputs.length > 0) {
      emitUxEvent('output.panel_opened', { invocationId, outputCount: outputs.length });
    }
  }, [invocationId, outputs.length]);

  useEffect(() => {
    if (outputs.length > 0) return
    if (executionStatus !== 'completed') return
    let cancelled = false
    ;(async () => {
      try {
        await fetch(`/api/invocations/${invocationId}/fetch-outputs`, { method: 'POST' })
      } catch {
        // best-effort fallback only
      }
      if (!cancelled) {
        await refetch()
      }
    })()
    return () => {
      cancelled = true
    }
  }, [executionStatus, invocationId, outputs.length, refetch])

  if (isLoading) {
    return (
      <div className={`space-y-4 ${className}`}>
        <Skeleton className="h-32 w-full" />
        <Skeleton className="h-32 w-full" />
      </div>
    )
  }

  // Filter out Nextflow internal files: 0-byte files, 8-char hex hash names,
  // and known internal filenames (dag.dot, versions.yml, etc.)
  const NF_INTERNAL_RE = /^[0-9a-f]{8}$/i;
  const NF_INTERNAL_NAMES = new Set(['dag.dot', 'versions.yml', 'nextflow_run_summary.txt', 'trace.txt', 'timeline.html', 'report.html']);
  const visibleOutputs = outputs.filter(o => {
    if ((o as any).size === 0) return false;
    const base = (o.name || '').split('/').pop() || o.name;
    if (NF_INTERNAL_RE.test(base)) return false;
    if (NF_INTERNAL_NAMES.has(base)) return false;
    return true;
  });

  if (visibleOutputs.length === 0) {
    return (
      <Card className={className}>
        <CardContent className="pt-6">
          <p className="text-sm text-muted-foreground text-center">
            No outputs generated yet
          </p>
        </CardContent>
      </Card>
    )
  }

  // Group outputs by type for better organization
  const visualizations = visibleOutputs.filter(o => o.fileType === 'image' || o.fileType === 'interactive')
  const tables = visibleOutputs.filter(o => o.fileType === 'table')
  const sequences = visibleOutputs.filter(o => o.fileType === 'sequence')
  const variants = visibleOutputs.filter(o => o.fileType === 'variants')
  const annotations = visibleOutputs.filter(o => o.fileType === 'annotation')
  const singleCell = visibleOutputs.filter(o => o.fileType === 'singlecell')
  const otherFiles = visibleOutputs.filter(o =>
    !['image', 'interactive', 'table', 'sequence', 'variants', 'annotation', 'singlecell'].includes(o.fileType)
  )

  const isTerminalStatus = executionStatus === 'completed' || executionStatus === 'failed' || executionStatus === 'cancelled'
  const hasOutputs = visibleOutputs.length > 0
  const isPartial = executionStatus === 'failed' || executionStatus === 'cancelled' || (executionStatus === 'running' && hasOutputs)
  const outputState = isPartial
    ? { label: 'Partial outputs', status: 'warning' as const }
    : hasOutputs && isTerminalStatus
      ? { label: 'Outputs found', status: 'success' as const }
      : { label: 'No outputs yet', status: 'pending' as const }

  const handleDownloadWithFeedback = (output: OutputDataset) => {
    emitUxEvent('output.download_clicked', {
      outputId: output.id,
      outputName: output.name,
      invocationId,
    })
    const link = document.createElement('a')
    link.href = `/api/outputs/${output.id}/download`
    link.download = output.name
    document.body.appendChild(link)
    link.click()
    document.body.removeChild(link)
    setDownloadPromptContext({
      outputId: output.id,
      outputName: output.name,
      isDownloadAll: false,
    })
    setDownloadPromptOpen(true)
  }

  return (
    <div className={`space-y-4 ${className}`}>
      <DownloadOutcomePrompt
        open={downloadPromptOpen}
        onOpenChange={setDownloadPromptOpen}
        outputId={downloadPromptContext?.outputId}
        outputName={downloadPromptContext?.outputName}
        invocationId={invocationId}
        sessionId={sessionId}
        runId={runId}
        isDownloadAll={downloadPromptContext?.isDownloadAll}
      />
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <span className="text-sm text-muted-foreground">Outputs</span>
          <div data-testid="output-result-state-badge">
            <StatusBadge status={outputState.status} className="text-xs">
              {outputState.label}
            </StatusBadge>
          </div>
        </div>
        <ReportConfusionButton
          runId={runId}
          sessionId={sessionId}
          invocationId={invocationId}
          context={{
            outputCount: outputs.length,
            executionStatus,
            errorMessage,
            hasVisualizations: visualizations.length > 0,
            hasTables: tables.length > 0,
          }}
          variant="ghost"
          size="sm"
        />
      </div>
      {/* Interactive Tool Launcher */}
      <InteractiveToolLauncher outputs={visibleOutputs} />

      {/* Visualizations Section */}
      {visualizations.length > 0 && (
        <div className="space-y-3">
          <div className="flex items-center gap-2">
            <ImageIcon className="h-4 w-4 text-muted-foreground" />
            <h4 className="text-sm font-medium">Visualizations</h4>
            <Badge variant="secondary">{visualizations.length}</Badge>
          </div>
          {visualizations.map(output => (
            <OutputRenderer key={output.id} output={output} invocationId={invocationId} onDownload={handleDownloadWithFeedback} />
          ))}
        </div>
      )}

      {/* Variants Section (VCF) */}
      {variants.length > 0 && (
        <div className="space-y-3">
          <div className="flex items-center gap-2">
            <Dna className="h-4 w-4 text-muted-foreground" />
            <h4 className="text-sm font-medium">Variant Calls</h4>
            <Badge variant="secondary">{variants.length}</Badge>
          </div>
          {variants.map(output => (
            <OutputRenderer key={output.id} output={output} invocationId={invocationId} onDownload={handleDownloadWithFeedback} />
          ))}
        </div>
      )}

      {/* Sequences Section (FASTA/FASTQ) */}
      {sequences.length > 0 && (
        <div className="space-y-3">
          <div className="flex items-center gap-2">
            <Dna className="h-4 w-4 text-muted-foreground" />
            <h4 className="text-sm font-medium">Sequences</h4>
            <Badge variant="secondary">{sequences.length}</Badge>
          </div>
          {sequences.map(output => (
            <OutputRenderer key={output.id} output={output} invocationId={invocationId} onDownload={handleDownloadWithFeedback} />
          ))}
        </div>
      )}

      {/* Annotations Section (BED/GFF/GTF) */}
      {annotations.length > 0 && (
        <div className="space-y-3">
          <div className="flex items-center gap-2">
            <Layers className="h-4 w-4 text-muted-foreground" />
            <h4 className="text-sm font-medium">Genomic Annotations</h4>
            <Badge variant="secondary">{annotations.length}</Badge>
          </div>
          {annotations.map(output => (
            <OutputRenderer key={output.id} output={output} invocationId={invocationId} onDownload={handleDownloadWithFeedback} />
          ))}
        </div>
      )}

      {/* Single-Cell Section */}
      {singleCell.length > 0 && (
        <div className="space-y-3">
          <div className="flex items-center gap-2">
            <Network className="h-4 w-4 text-muted-foreground" />
            <h4 className="text-sm font-medium">Single-Cell Data</h4>
            <Badge variant="secondary">{singleCell.length}</Badge>
          </div>
          {singleCell.map(output => (
            <OutputRenderer key={output.id} output={output} invocationId={invocationId} onDownload={handleDownloadWithFeedback} />
          ))}
        </div>
      )}

      {/* Data Tables Section */}
      {tables.length > 0 && (
        <div className="space-y-3">
          <div className="flex items-center gap-2">
            <FileText className="h-4 w-4 text-muted-foreground" />
            <h4 className="text-sm font-medium">Data Tables</h4>
            <Badge variant="secondary">{tables.length}</Badge>
          </div>
          {tables.map(output => (
            <OutputRenderer key={output.id} output={output} invocationId={invocationId} onDownload={handleDownloadWithFeedback} />
          ))}
        </div>
      )}

      {/* Other Files Section */}
      {otherFiles.length > 0 && (
        <div className="space-y-3">
          <div className="flex items-center gap-2">
            <File className="h-4 w-4 text-muted-foreground" />
            <h4 className="text-sm font-medium">Other Files</h4>
            <Badge variant="secondary">{otherFiles.length}</Badge>
          </div>
          {otherFiles.map(output => (
            <OutputRenderer key={output.id} output={output} invocationId={invocationId} onDownload={handleDownloadWithFeedback} />
          ))}
        </div>
      )}
    </div>
  )
}

interface OutputRendererProps {
  output: OutputDataset
  invocationId?: string
  onDownload?: (output: OutputDataset) => void
}

function OutputRenderer({ output, invocationId, onDownload }: OutputRendererProps) {
  switch (output.fileType) {
    case 'image':
      return <ImageOutput output={output} invocationId={invocationId} onDownload={onDownload} />
    case 'interactive':
      return <InteractiveOutput output={output} invocationId={invocationId} onDownload={onDownload} />
    case 'table':
      // Use sortable CsvTableViewer for structured data formats
      if (['json', 'csv', 'tsv', 'tabular'].includes(output.extension?.toLowerCase() || '')) {
        return (
          <div data-testid="csv-table-viewer">
            <CsvTableViewer output={output} className="w-full" />
          </div>
        )
      }
      return <TableOutput output={output} invocationId={invocationId} onDownload={onDownload} />
    case 'text':
      return <TextOutput output={output} invocationId={invocationId} onDownload={onDownload} />
    case 'variants':
      return <VCFViewer output={output} />
    case 'sequence':
      return <SequenceViewer output={output} />
    case 'annotation':
      return <AnnotationViewer output={output} />
    case 'structure':
      // PDB / mmCIF / CIF — 3Dmol.js interactive 3D viewer
      return <StructureViewer output={output} />
    case 'density_map':
      // MRC / MAP — orthogonal 2D slice viewer with contrast control
      return <DensityMapViewer output={output} />
    case 'singlecell':
      return <FileOutput output={output} invocationId={invocationId} onDownload={onDownload} />
    default:
      return <FileOutput output={output} invocationId={invocationId} onDownload={onDownload} />
  }
}

function ImageOutput({ output, invocationId, onDownload }: OutputRendererProps) {
  const [expanded, setExpanded] = useState(true)
  const [imageError, setImageError] = useState(false)
  const [imageLoading, setImageLoading] = useState(true)

  return (
    <Card>
      <CardHeader>
        <div className="flex items-center justify-between">
          <div className="flex-1 min-w-0">
            <CardTitle className="text-base truncate">{output.name}</CardTitle>
            <CardDescription className="text-xs">
              {output.extension.toUpperCase()} • {formatBytes(output.size)}
              {output.metadata?.width && output.metadata?.height && (
                <> • {output.metadata.width}×{output.metadata.height}</>
              )}
            </CardDescription>
          </div>
          <Button
            variant="ghost"
            size="sm"
            onClick={() => {
              const next = !expanded
              if (next) {
                emitUxEvent('output.visualization_opened', {
                  outputId: output.id,
                  outputName: output.name,
                  fileType: 'image',
                  invocationId,
                  action: 'expand_inline',
                })
              }
              setExpanded(next)
            }}
          >
            {expanded ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
          </Button>
        </div>
      </CardHeader>
      <CardContent className="space-y-3">
        {expanded && (
          <div className="rounded-lg border bg-muted/30 p-2">
            {imageLoading && !imageError && (
              <Skeleton className="w-full h-48" />
            )}
            {imageError ? (
              <div className="flex flex-col items-center justify-center py-8 text-muted-foreground">
                <ImageIcon className="h-12 w-12 mb-2 opacity-50" />
                <p className="text-sm">Failed to load image</p>
                <Button
                  variant="ghost"
                  size="sm"
                  className="mt-2"
                  onClick={() => {
                    setImageError(false)
                    setImageLoading(true)
                  }}
                >
                  Retry
                </Button>
              </div>
            ) : (
              <img
                src={`/api/outputs/${output.id}/display`}
                alt={output.name}
                className={`max-w-full h-auto rounded ${imageLoading ? 'hidden' : ''}`}
                loading="lazy"
                onLoad={() => setImageLoading(false)}
                onError={() => {
                  setImageError(true)
                  setImageLoading(false)
                }}
              />
            )}
          </div>
        )}
        <div className="flex gap-2">
          <Button
            variant="outline"
            size="sm"
            onClick={() => {
              emitUxEvent('output.visualization_opened', {
                outputId: output.id,
                outputName: output.name,
                fileType: 'image',
                invocationId,
                action: 'open_full_size',
              })
              window.open(`/api/outputs/${output.id}/display`, '_blank')
            }}
          >
            <ExternalLink className="h-4 w-4 mr-1" />
            Open Full Size
          </Button>
          <Button
            variant="outline"
            size="sm"
            onClick={() => onDownload?.(output)}
          >
            <Download className="h-4 w-4 mr-1" />
            Download
          </Button>
        </div>
      </CardContent>
    </Card>
  )
}

function InteractiveOutput({ output, invocationId, onDownload }: OutputRendererProps) {
  const [expanded, setExpanded] = useState(true)
  const [iframeError, setIframeError] = useState(false)
  const [iframeLoading, setIframeLoading] = useState(true)

  return (
    <Card>
      <CardHeader>
        <div className="flex items-center justify-between">
          <div className="flex-1 min-w-0">
            <CardTitle className="text-base truncate">{output.name}</CardTitle>
            <CardDescription className="text-xs">
              Interactive Visualization • {formatBytes(output.size)}
            </CardDescription>
          </div>
          <Button
            variant="ghost"
            size="sm"
            onClick={() => {
              const next = !expanded
              if (next) {
                emitUxEvent('output.visualization_opened', {
                  outputId: output.id,
                  outputName: output.name,
                  fileType: 'interactive',
                  invocationId,
                  action: 'expand_inline',
                })
              }
              setExpanded(next)
            }}
          >
            {expanded ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
          </Button>
        </div>
      </CardHeader>
      <CardContent className="space-y-3">
        {expanded && (
          <div className="rounded-lg border relative">
            {iframeLoading && !iframeError && (
              <div className="absolute inset-0 flex items-center justify-center bg-muted/50">
                <Skeleton className="w-full h-96" />
              </div>
            )}
            {iframeError ? (
              <div className="flex flex-col items-center justify-center h-96 text-muted-foreground">
                <FileCode className="h-12 w-12 mb-2 opacity-50" />
                <p className="text-sm">Failed to load interactive content</p>
                <p className="text-xs text-muted-foreground mt-1">Try opening in a new tab</p>
                <Button
                  variant="ghost"
                  size="sm"
                  className="mt-2"
                  onClick={() => {
                    setIframeError(false)
                    setIframeLoading(true)
                  }}
                >
                  Retry
                </Button>
              </div>
            ) : (
              <iframe
                src={`/api/outputs/${output.id}/display`}
                className="w-full h-96 rounded"
                sandbox="allow-scripts allow-same-origin"
                title={output.name}
                onLoad={() => setIframeLoading(false)}
                onError={() => {
                  setIframeError(true)
                  setIframeLoading(false)
                }}
              />
            )}
          </div>
        )}
        <div className="flex gap-2">
          <Button
            variant="outline"
            size="sm"
            onClick={() => {
              emitUxEvent('output.visualization_opened', {
                outputId: output.id,
                outputName: output.name,
                fileType: 'interactive',
                invocationId,
                action: 'open_new_tab',
              })
              window.open(`/api/outputs/${output.id}/display`, '_blank')
            }}
          >
            <ExternalLink className="h-4 w-4 mr-1" />
            Open in New Tab
          </Button>
          <Button
            variant="outline"
            size="sm"
            onClick={() => onDownload?.(output)}
          >
            <Download className="h-4 w-4 mr-1" />
            Download HTML
          </Button>
        </div>
      </CardContent>
    </Card>
  )
}

function TableOutput({ output, invocationId, onDownload }: OutputRendererProps) {
  const [showPreview, setShowPreview] = useState(false)

  const { data: preview, isLoading } = useQuery({
    queryKey: ['preview', output.id],
    queryFn: async () => {
      const response = await fetch(`/api/outputs/${output.id}/preview?lines=50`)
      if (!response.ok) throw new Error('Failed to fetch preview')
      return response.json()
    },
    enabled: showPreview,
  })

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base truncate">{output.name}</CardTitle>
        <CardDescription className="text-xs">
          {output.extension.toUpperCase()} Table • {formatBytes(output.size)}
          {output.metadata?.rows && (
            <> • {formatNumber(output.metadata.rows)} rows</>
          )}
          {output.metadata?.columns && (
            <> • {output.metadata.columns} columns</>
          )}
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-3">
        <div className="flex gap-2">
          <Button
            variant={showPreview ? "default" : "outline"}
            size="sm"
            onClick={() => setShowPreview(!showPreview)}
            disabled={isLoading}
          >
            <Eye className="h-4 w-4 mr-1" />
            {showPreview ? 'Hide' : 'Show'} Preview
          </Button>
          <Button
            variant="outline"
            size="sm"
            onClick={() => onDownload?.(output)}
          >
            <Download className="h-4 w-4 mr-1" />
            Download Full Table
          </Button>
        </div>

        {showPreview && !isLoading && preview && (
          <div className="space-y-2">
            <ScrollArea className="h-64 rounded-lg border bg-muted/30">
              <pre className="p-4 text-xs font-mono">
                {preview.lines.join('\n')}
              </pre>
            </ScrollArea>
            {preview.hasMore && (
              <p className="text-xs text-muted-foreground">
                Showing first {preview.lines.length} of {formatNumber(preview.totalLines)} lines
              </p>
            )}
          </div>
        )}

        {showPreview && isLoading && (
          <Skeleton className="h-64 w-full" />
        )}
      </CardContent>
    </Card>
  )
}

function TextOutput({ output, invocationId, onDownload }: OutputRendererProps) {
  const [showPreview, setShowPreview] = useState(false)

  const { data: preview, isLoading } = useQuery({
    queryKey: ['preview', output.id],
    queryFn: async () => {
      const response = await fetch(`/api/outputs/${output.id}/preview?lines=100`)
      if (!response.ok) throw new Error('Failed to fetch preview')
      return response.json()
    },
    enabled: showPreview,
  })

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base truncate">{output.name}</CardTitle>
        <CardDescription className="text-xs">
          {output.extension.toUpperCase()} • {formatBytes(output.size)}
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-3">
        <div className="flex gap-2">
          <Button
            variant={showPreview ? "default" : "outline"}
            size="sm"
            onClick={() => setShowPreview(!showPreview)}
            disabled={isLoading}
          >
            <Eye className="h-4 w-4 mr-1" />
            {showPreview ? 'Hide' : 'Show'} Preview
          </Button>
          <Button
            variant="outline"
            size="sm"
            onClick={() => onDownload?.(output)}
          >
            <Download className="h-4 w-4 mr-1" />
            Download
          </Button>
        </div>

        {showPreview && !isLoading && preview && (
          <ScrollArea className="h-64 rounded-lg border bg-muted/30">
            <pre className="p-4 text-xs font-mono whitespace-pre-wrap">
              {preview.lines.join('\n')}
            </pre>
          </ScrollArea>
        )}

        {showPreview && isLoading && (
          <Skeleton className="h-64 w-full" />
        )}
      </CardContent>
    </Card>
  )
}

function FileOutput({ output, invocationId, onDownload }: OutputRendererProps) {
  const getFileIcon = () => {
    const ext = output.extension.toLowerCase()
    if (['json', 'xml', 'yaml', 'yml'].includes(ext)) return <FileCode className="h-8 w-8" />
    return <File className="h-8 w-8" />
  }

  return (
    <Card>
      <CardContent className="pt-6">
        <div className="flex items-center gap-4">
          <div className="text-muted-foreground">
            {getFileIcon()}
          </div>
          <div className="flex-1 min-w-0">
            <p className="font-medium truncate">{output.name}</p>
            <p className="text-sm text-muted-foreground">
              {output.extension.toUpperCase()} • {formatBytes(output.size)}
            </p>
          </div>
          <Button
            variant="outline"
            size="sm"
            onClick={() => onDownload?.(output)}
          >
            <Download className="h-4 w-4 mr-1" />
            Download
          </Button>
        </div>
      </CardContent>
    </Card>
  )
}

// Helper functions
function formatBytes(bytes: number): string {
  if (bytes === 0) return '0 Bytes'
  const k = 1024
  const sizes = ['Bytes', 'KB', 'MB', 'GB']
  const i = Math.floor(Math.log(bytes) / Math.log(k))
  return Math.round(bytes / Math.pow(k, i) * 100) / 100 + ' ' + sizes[i]
}

function formatNumber(num: number): string {
  return new Intl.NumberFormat().format(num)
}

