import { useState } from "react"
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
} from "lucide-react"
import type { OutputDataset } from "@shared/schema"

interface ChatOutputAttachmentsProps {
  invocationId: string
  className?: string
}

export function ChatOutputAttachments({ invocationId, className }: ChatOutputAttachmentsProps) {
  const { data: outputs = [], isLoading } = useQuery<OutputDataset[]>({
    queryKey: ['outputs', invocationId],
    queryFn: async () => {
      const response = await fetch(`/api/invocations/${invocationId}/outputs`)
      if (!response.ok) throw new Error('Failed to fetch outputs')
      return response.json()
    },
  })

  if (isLoading) {
    return (
      <div className={`space-y-4 ${className}`}>
        <Skeleton className="h-32 w-full" />
        <Skeleton className="h-32 w-full" />
      </div>
    )
  }

  if (outputs.length === 0) {
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
  const visualizations = outputs.filter(o => o.fileType === 'image' || o.fileType === 'interactive')
  const tables = outputs.filter(o => o.fileType === 'table')
  const otherFiles = outputs.filter(o => o.fileType !== 'image' && o.fileType !== 'interactive' && o.fileType !== 'table')

  return (
    <div className={`space-y-4 ${className}`}>
      {/* Visualizations Section */}
      {visualizations.length > 0 && (
        <div className="space-y-3">
          <div className="flex items-center gap-2">
            <ImageIcon className="h-4 w-4 text-muted-foreground" />
            <h4 className="text-sm font-medium">Visualizations</h4>
            <Badge variant="secondary">{visualizations.length}</Badge>
          </div>
          {visualizations.map(output => (
            <OutputRenderer key={output.id} output={output} />
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
            <OutputRenderer key={output.id} output={output} />
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
            <OutputRenderer key={output.id} output={output} />
          ))}
        </div>
      )}
    </div>
  )
}

interface OutputRendererProps {
  output: OutputDataset
}

function OutputRenderer({ output }: OutputRendererProps) {
  switch (output.fileType) {
    case 'image':
      return <ImageOutput output={output} />
    case 'interactive':
      return <InteractiveOutput output={output} />
    case 'table':
      return <TableOutput output={output} />
    case 'text':
      return <TextOutput output={output} />
    default:
      return <FileOutput output={output} />
  }
}

function ImageOutput({ output }: OutputRendererProps) {
  const [expanded, setExpanded] = useState(true)

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
            onClick={() => setExpanded(!expanded)}
          >
            {expanded ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
          </Button>
        </div>
      </CardHeader>
      <CardContent className="space-y-3">
        {expanded && (
          <div className="rounded-lg border bg-muted/30 p-2">
            <img
              src={`/api/outputs/${output.id}/display`}
              alt={output.name}
              className="max-w-full h-auto rounded"
              loading="lazy"
            />
          </div>
        )}
        <div className="flex gap-2">
          <Button
            variant="outline"
            size="sm"
            onClick={() => window.open(`/api/outputs/${output.id}/display`, '_blank')}
          >
            <ExternalLink className="h-4 w-4 mr-1" />
            Open Full Size
          </Button>
          <Button
            variant="outline"
            size="sm"
            onClick={() => handleDownload(output)}
          >
            <Download className="h-4 w-4 mr-1" />
            Download
          </Button>
        </div>
      </CardContent>
    </Card>
  )
}

function InteractiveOutput({ output }: OutputRendererProps) {
  const [expanded, setExpanded] = useState(true)

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
            onClick={() => setExpanded(!expanded)}
          >
            {expanded ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
          </Button>
        </div>
      </CardHeader>
      <CardContent className="space-y-3">
        {expanded && (
          <div className="rounded-lg border">
            <iframe
              src={`/api/outputs/${output.id}/display`}
              className="w-full h-96 rounded"
              sandbox="allow-scripts allow-same-origin"
              title={output.name}
            />
          </div>
        )}
        <div className="flex gap-2">
          <Button
            variant="outline"
            size="sm"
            onClick={() => window.open(`/api/outputs/${output.id}/display`, '_blank')}
          >
            <ExternalLink className="h-4 w-4 mr-1" />
            Open in New Tab
          </Button>
          <Button
            variant="outline"
            size="sm"
            onClick={() => handleDownload(output)}
          >
            <Download className="h-4 w-4 mr-1" />
            Download HTML
          </Button>
        </div>
      </CardContent>
    </Card>
  )
}

function TableOutput({ output }: OutputRendererProps) {
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
            onClick={() => handleDownload(output)}
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

function TextOutput({ output }: OutputRendererProps) {
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
            onClick={() => handleDownload(output)}
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

function FileOutput({ output }: OutputRendererProps) {
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
            onClick={() => handleDownload(output)}
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

async function handleDownload(output: OutputDataset) {
  // Trigger download
  const link = document.createElement('a')
  link.href = `/api/outputs/${output.id}/download`
  link.download = output.name
  document.body.appendChild(link)
  link.click()
  document.body.removeChild(link)
}
