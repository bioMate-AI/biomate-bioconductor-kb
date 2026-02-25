import { useState } from "react"
import DOMPurify from "dompurify"
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from "@/components/ui/dialog"
import { Button } from "@/components/ui/button"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Badge } from "@/components/ui/badge"
import { Alert, AlertDescription } from "@/components/ui/alert"
import {
  FileText,
  Download,
  Copy,
  Check,
  Loader2,
  AlertCircle,
  ExternalLink
} from "lucide-react"

interface WorkflowReportViewerProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  invocationId: string
  workflowName?: string
}

export function WorkflowReportViewer({
  open,
  onOpenChange,
  invocationId,
  workflowName = "Workflow"
}: WorkflowReportViewerProps) {
  const [reportFormat, setReportFormat] = useState<'markdown' | 'html'>('markdown')
  const [report, setReport] = useState<string | null>(null)
  const [isLoading, setIsLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [copied, setCopied] = useState(false)

  const fetchReport = async (format: 'markdown' | 'html') => {
    setIsLoading(true)
    setError(null)

    try {
      const response = await fetch(`/api/invocations/${invocationId}/report?format=${format}`)

      if (!response.ok) {
        const errorData = await response.json()
        throw new Error(errorData.message || 'Failed to generate report')
      }

      const data = await response.json()
      setReport(data.report)
      setReportFormat(format)
    } catch (err: any) {
      setError(err.message || 'Failed to load report')
      setReport(null)
    } finally {
      setIsLoading(false)
    }
  }

  // Fetch report when dialog opens
  const handleOpenChange = (isOpen: boolean) => {
    if (isOpen && !report && !isLoading) {
      fetchReport('markdown')
    }
    onOpenChange(isOpen)
  }

  const handleCopy = async () => {
    if (report) {
      await navigator.clipboard.writeText(report)
      setCopied(true)
      setTimeout(() => setCopied(false), 2000)
    }
  }

  const handleDownload = () => {
    if (report) {
      const extension = reportFormat === 'html' ? 'html' : 'md'
      const mimeType = reportFormat === 'html' ? 'text/html' : 'text/markdown'
      const blob = new Blob([report], { type: mimeType })
      const url = URL.createObjectURL(blob)
      const a = document.createElement('a')
      a.href = url
      a.download = `${workflowName.replace(/\s+/g, '_')}_report.${extension}`
      document.body.appendChild(a)
      a.click()
      document.body.removeChild(a)
      URL.revokeObjectURL(url)
    }
  }

  // Simple markdown renderer (for display purposes)
  const renderMarkdown = (md: string) => {
    // Basic markdown to HTML conversion for preview
    let html = md
      // Headers
      .replace(/^### (.*$)/gim, '<h3 class="text-lg font-semibold mt-4 mb-2">$1</h3>')
      .replace(/^## (.*$)/gim, '<h2 class="text-xl font-bold mt-6 mb-3">$1</h2>')
      .replace(/^# (.*$)/gim, '<h1 class="text-2xl font-bold mt-6 mb-4">$1</h1>')
      // Bold and italic
      .replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>')
      .replace(/\*(.*?)\*/g, '<em>$1</em>')
      // Code blocks
      .replace(/```(\w+)?\n([\s\S]*?)```/g, '<pre class="bg-muted p-3 rounded-lg overflow-x-auto my-2 text-xs font-mono"><code>$2</code></pre>')
      .replace(/`([^`]+)`/g, '<code class="bg-muted px-1 py-0.5 rounded text-xs">$1</code>')
      // Tables (basic support)
      .replace(/\|(.+)\|/g, (match) => {
        const cells = match.split('|').filter(Boolean).map(cell => cell.trim())
        return `<tr>${cells.map(c => `<td class="border px-2 py-1 text-sm">${c}</td>`).join('')}</tr>`
      })
      // Lists
      .replace(/^\s*[-*]\s+(.*)$/gim, '<li class="ml-4">$1</li>')
      .replace(/^\s*\d+\.\s+(.*)$/gim, '<li class="ml-4 list-decimal">$1</li>')
      // Line breaks
      .replace(/\n\n/g, '</p><p class="my-2">')
      .replace(/\n/g, '<br/>')

    return `<div class="prose prose-sm dark:prose-invert max-w-none"><p class="my-2">${html}</p></div>`
  }

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogContent className="max-w-4xl max-h-[85vh]">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <FileText className="h-5 w-5" />
            Workflow Analysis Report
          </DialogTitle>
          <DialogDescription>
            Auto-generated report for {workflowName}
          </DialogDescription>
        </DialogHeader>

        <div className="flex items-center justify-between mb-4">
          <Tabs value={reportFormat} onValueChange={(v) => fetchReport(v as 'markdown' | 'html')}>
            <TabsList>
              <TabsTrigger value="markdown" className="text-xs">
                Markdown
              </TabsTrigger>
              <TabsTrigger value="html" className="text-xs">
                HTML
              </TabsTrigger>
            </TabsList>
          </Tabs>

          <div className="flex items-center gap-2">
            <Button
              variant="outline"
              size="sm"
              onClick={handleCopy}
              disabled={!report || isLoading}
            >
              {copied ? (
                <>
                  <Check className="h-4 w-4 mr-1" />
                  Copied
                </>
              ) : (
                <>
                  <Copy className="h-4 w-4 mr-1" />
                  Copy
                </>
              )}
            </Button>
            <Button
              variant="outline"
              size="sm"
              onClick={handleDownload}
              disabled={!report || isLoading}
            >
              <Download className="h-4 w-4 mr-1" />
              Download
            </Button>
          </div>
        </div>

        {isLoading && (
          <div className="flex items-center justify-center py-12">
            <Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
            <span className="ml-2 text-muted-foreground">Generating report...</span>
          </div>
        )}

        {error && (
          <Alert variant="destructive">
            <AlertCircle className="h-4 w-4" />
            <AlertDescription>{error}</AlertDescription>
          </Alert>
        )}

        {report && !isLoading && (
          <ScrollArea className="h-[60vh] border rounded-lg">
            <div className="p-4">
              {reportFormat === 'html' ? (
                <div
                  className="prose prose-sm dark:prose-invert max-w-none"
                  dangerouslySetInnerHTML={{ __html: DOMPurify.sanitize(report) }}
                />
              ) : (
                <div
                  dangerouslySetInnerHTML={{ __html: DOMPurify.sanitize(renderMarkdown(report)) }}
                />
              )}
            </div>
          </ScrollArea>
        )}

        {!report && !isLoading && !error && (
          <div className="flex flex-col items-center justify-center py-12 text-muted-foreground">
            <FileText className="h-12 w-12 mb-4 opacity-50" />
            <p>Click to generate report</p>
            <Button
              className="mt-4"
              onClick={() => fetchReport('markdown')}
            >
              Generate Report
            </Button>
          </div>
        )}
      </DialogContent>
    </Dialog>
  )
}
