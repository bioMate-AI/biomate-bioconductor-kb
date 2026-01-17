import { useState } from "react"
import { useQuery } from "@tanstack/react-query"
import { formatDistanceToNow } from "date-fns"
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
  SheetTrigger,
} from "@/components/ui/sheet"
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Progress } from "@/components/ui/progress"
import {
  History,
  Download,
  Play,
  XCircle,
  CheckCircle,
  Loader2,
  Clock,
  Eye,
  Trash2,
  FileText,
  Image,
  Table,
  FileCode,
  ExternalLink,
  File,
} from "lucide-react"
import type { WorkflowInvocation, OutputDataset } from "@shared/schema"

interface WorkflowHistoryPanelProps {
  className?: string
}

export function WorkflowHistoryPanel({ className }: WorkflowHistoryPanelProps) {
  const [open, setOpen] = useState(false)
  const [selectedInvocation, setSelectedInvocation] = useState<string | null>(null)

  // Fetch invocations with auto-refresh for running workflows
  const { data: invocations = [], isLoading } = useQuery<WorkflowInvocation[]>({
    queryKey: ['invocations'],
    queryFn: async () => {
      const response = await fetch('/api/invocations')
      if (!response.ok) throw new Error('Failed to fetch invocations')
      return response.json()
    },
    refetchInterval: (data) => {
      // Refresh every 5s if there are running workflows
      const hasRunning = Array.isArray(data) && data.some(inv => inv.status === 'running' || inv.status === 'queued')
      return hasRunning ? 5000 : false
    },
  })

  // Group invocations by date
  const groupedInvocations = groupByDate(invocations)

  // Count running workflows
  const runningCount = invocations.filter(inv => inv.status === 'running').length

  return (
    <>
      <Sheet open={open} onOpenChange={setOpen}>
        <SheetTrigger asChild>
          <Button variant="outline" className={className}>
            <History className="h-4 w-4 mr-2" />
            My Workflows
            {runningCount > 0 && (
              <Badge variant="secondary" className="ml-2">
                {runningCount} running
              </Badge>
            )}
          </Button>
        </SheetTrigger>

        <SheetContent side="right" className="w-full sm:w-[600px] sm:max-w-[600px]">
          <SheetHeader>
            <SheetTitle>Workflow History</SheetTitle>
          </SheetHeader>

          <ScrollArea className="h-[calc(100vh-8rem)] mt-6">
            {isLoading && (
              <div className="flex items-center justify-center py-8">
                <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
              </div>
            )}

            {!isLoading && invocations.length === 0 && (
              <div className="flex flex-col items-center justify-center py-12 text-center">
                <History className="h-12 w-12 text-muted-foreground mb-4" />
                <p className="text-sm text-muted-foreground">
                  No workflows run yet. Start a workflow from chat to see it here!
                </p>
              </div>
            )}

            {!isLoading && Object.entries(groupedInvocations).map(([date, items]) => (
              <div key={date} className="mb-6">
                <h3 className="text-sm font-medium text-muted-foreground mb-3 px-1">
                  {date}
                </h3>

                <div className="space-y-3">
                  {items.map(invocation => (
                    <InvocationCard
                      key={invocation.id}
                      invocation={invocation}
                      onViewResults={() => setSelectedInvocation(invocation.id)}
                    />
                  ))}
                </div>
              </div>
            ))}
          </ScrollArea>
        </SheetContent>
      </Sheet>

      {/* Results viewer dialog */}
      <OutputsDialog
        invocationId={selectedInvocation}
        open={!!selectedInvocation}
        onClose={() => setSelectedInvocation(null)}
      />
    </>
  )
}

interface InvocationCardProps {
  invocation: WorkflowInvocation
  onViewResults: () => void
}

function InvocationCard({ invocation, onViewResults }: InvocationCardProps) {
  const statusConfig = {
    running: {
      icon: Loader2,
      color: "default" as const,
      label: "Running",
      animate: true,
      bgColor: "bg-orange-500/10 dark:bg-orange-500/20"
    },
    ok: {
      icon: CheckCircle,
      color: "default" as const,
      label: "Completed",
      animate: false,
      bgColor: "bg-green-500/10 dark:bg-green-500/20"
    },
    error: {
      icon: XCircle,
      color: "destructive" as const,
      label: "Failed",
      animate: false,
      bgColor: "bg-red-500/10 dark:bg-red-500/20"
    },
    queued: {
      icon: Clock,
      color: "secondary" as const,
      label: "Queued",
      animate: false,
      bgColor: "bg-blue-500/10 dark:bg-blue-500/20"
    },
    new: {
      icon: Clock,
      color: "secondary" as const,
      label: "Starting",
      animate: false,
      bgColor: "bg-blue-500/10 dark:bg-blue-500/20"
    },
    paused: {
      icon: Clock,
      color: "secondary" as const,
      label: "Paused",
      animate: false,
      bgColor: "bg-gray-500/10 dark:bg-gray-500/20"
    },
    deleted: {
      icon: Trash2,
      color: "secondary" as const,
      label: "Deleted",
      animate: false,
      bgColor: "bg-gray-500/10 dark:bg-gray-500/20"
    },
  }

  const config = statusConfig[invocation.status] || statusConfig.new
  const Icon = config.icon
  const progressPercent = invocation.totalSteps > 0
    ? (invocation.completedSteps / invocation.totalSteps) * 100
    : 0

  return (
    <Card className={`transition-all hover:shadow-md ${config.bgColor}`}>
      <CardHeader className="pb-3">
        <div className="flex items-start justify-between gap-2">
          <div className="flex-1 min-w-0">
            <CardTitle className="text-base truncate">
              {invocation.workflowName}
            </CardTitle>
            <CardDescription className="text-xs mt-1">
              Started {formatDistanceToNow(new Date(invocation.createdAt), { addSuffix: true })}
            </CardDescription>
          </div>

          <Badge variant={config.color} className="shrink-0">
            <Icon className={`h-3 w-3 mr-1 ${config.animate ? 'animate-spin' : ''}`} />
            {config.label}
          </Badge>
        </div>
      </CardHeader>

      <CardContent className="pt-0 space-y-3">
        {/* Running workflow - show progress */}
        {invocation.status === 'running' && (
          <div className="space-y-2">
            <div className="flex items-center justify-between text-xs text-muted-foreground">
              <span>
                Step {invocation.completedSteps}/{invocation.totalSteps}
                {invocation.currentStepName && `: ${invocation.currentStepName}`}
              </span>
              <span>{Math.round(progressPercent)}%</span>
            </div>
            <Progress value={progressPercent} className="h-2" />
          </div>
        )}

        {/* Completed workflow - show outputs */}
        {invocation.status === 'ok' && (
          <div className="space-y-2">
            <div className="text-sm text-muted-foreground">
              {invocation.outputCount} output{invocation.outputCount !== 1 ? 's' : ''} ({formatBytes(invocation.totalOutputSize)})
            </div>

            <div className="flex gap-2">
              <Button
                size="sm"
                variant="default"
                onClick={onViewResults}
                className="flex-1"
              >
                <Eye className="h-4 w-4 mr-1" />
                View Results
              </Button>
              <Button
                size="sm"
                variant="outline"
                onClick={() => handleDownloadAll(invocation.id)}
              >
                <Download className="h-4 w-4 mr-1" />
                Download All
              </Button>
            </div>
          </div>
        )}

        {/* Failed workflow - show error */}
        {invocation.status === 'error' && (
          <div className="space-y-2">
            <div className="text-sm text-destructive">
              {invocation.errorMessage || 'Workflow execution failed'}
            </div>
            <Button
              size="sm"
              variant="outline"
              onClick={() => handleRetry(invocation.id)}
              className="w-full"
            >
              <Play className="h-4 w-4 mr-1" />
              Retry Workflow
            </Button>
          </div>
        )}

        {/* Queued workflow */}
        {(invocation.status === 'queued' || invocation.status === 'new') && (
          <div className="text-sm text-muted-foreground">
            Waiting to start...
          </div>
        )}
      </CardContent>
    </Card>
  )
}

// Helper functions
function groupByDate(invocations: WorkflowInvocation[]): Record<string, WorkflowInvocation[]> {
  const groups: Record<string, WorkflowInvocation[]> = {}
  const now = new Date()
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate())
  const yesterday = new Date(today)
  yesterday.setDate(yesterday.getDate() - 1)
  const lastWeek = new Date(today)
  lastWeek.setDate(lastWeek.getDate() - 7)

  invocations.forEach(invocation => {
    const date = new Date(invocation.createdAt)
    const dateOnly = new Date(date.getFullYear(), date.getMonth(), date.getDate())

    let groupName: string
    if (dateOnly.getTime() === today.getTime()) {
      groupName = 'Today'
    } else if (dateOnly.getTime() === yesterday.getTime()) {
      groupName = 'Yesterday'
    } else if (date >= lastWeek) {
      groupName = 'Last 7 Days'
    } else {
      groupName = 'Older'
    }

    if (!groups[groupName]) {
      groups[groupName] = []
    }
    groups[groupName].push(invocation)
  })

  return groups
}

function formatBytes(bytes: number): string {
  if (bytes === 0) return '0 Bytes'
  const k = 1024
  const sizes = ['Bytes', 'KB', 'MB', 'GB']
  const i = Math.floor(Math.log(bytes) / Math.log(k))
  return Math.round(bytes / Math.pow(k, i) * 100) / 100 + ' ' + sizes[i]
}

async function handleDownloadAll(invocationId: string) {
  try {
    // Trigger ZIP download via browser
    const downloadUrl = `/api/invocations/${invocationId}/download-all`
    const link = document.createElement('a')
    link.href = downloadUrl
    link.download = '' // Let server set filename via Content-Disposition
    document.body.appendChild(link)
    link.click()
    document.body.removeChild(link)
  } catch (error) {
    console.error('Failed to download outputs:', error)
    alert('Failed to download outputs. Please try again.')
  }
}

async function handleRetry(invocationId: string, workflowDefinition?: any, inputDatasets?: any[]) {
  try {
    if (!workflowDefinition) {
      // Fetch invocation to get workflow definition
      const response = await fetch(`/api/invocations/${invocationId}`)
      if (!response.ok) throw new Error('Failed to fetch invocation details')
      const invocation = await response.json()
      workflowDefinition = invocation.workflowDefinition
      inputDatasets = invocation.inputDatasets
    }

    // Re-invoke the workflow with the same inputs
    const invokeResponse = await fetch('/api/galaxy/workflows/invoke', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        workflow_definition: workflowDefinition,
        inputs: inputDatasets || [],
      }),
    })

    if (!invokeResponse.ok) {
      const error = await invokeResponse.json()
      throw new Error(error.message || 'Failed to retry workflow')
    }

    const result = await invokeResponse.json()
    alert(`Workflow restarted! New invocation ID: ${result.invocation?.id || 'unknown'}`)

    // Optionally refresh the page or trigger a refetch
    window.location.reload()
  } catch (error: any) {
    console.error('Failed to retry workflow:', error)
    alert(`Failed to retry workflow: ${error.message}`)
  }
}

// ============================================================================
// Outputs Dialog - View workflow results with Galaxy visualizations
// ============================================================================

interface OutputsDialogProps {
  invocationId: string | null
  open: boolean
  onClose: () => void
}

function OutputsDialog({ invocationId, open, onClose }: OutputsDialogProps) {
  // Fetch outputs for the selected invocation
  const { data: outputs = [], isLoading } = useQuery<OutputDataset[]>({
    queryKey: ['outputs', invocationId],
    queryFn: async () => {
      if (!invocationId) return []
      const response = await fetch(`/api/invocations/${invocationId}/outputs`)
      if (!response.ok) throw new Error('Failed to fetch outputs')
      return response.json()
    },
    enabled: !!invocationId && open,
  })

  // Get icon for file type
  const getFileIcon = (fileType: string, extension: string) => {
    switch (fileType) {
      case 'image':
        return <Image className="h-5 w-5 text-purple-500" />
      case 'table':
        return <Table className="h-5 w-5 text-green-500" />
      case 'text':
        return <FileText className="h-5 w-5 text-blue-500" />
      case 'interactive':
        return <FileCode className="h-5 w-5 text-orange-500" />
      default:
        return <File className="h-5 w-5 text-gray-500" />
    }
  }

  // Check if file can be viewed inline
  const canViewInline = (fileType: string, extension: string) => {
    const viewableExtensions = ['png', 'jpg', 'jpeg', 'gif', 'svg', 'html', 'htm', 'txt', 'csv', 'tsv', 'pdf']
    return viewableExtensions.includes(extension.toLowerCase())
  }

  // Open file in Galaxy viewer or new tab
  const handleView = (output: OutputDataset) => {
    const displayUrl = `/api/outputs/${output.id}/display`
    window.open(displayUrl, '_blank')
  }

  // Download single file
  const handleDownload = (output: OutputDataset) => {
    const downloadUrl = `/api/outputs/${output.id}/download`
    const link = document.createElement('a')
    link.href = downloadUrl
    link.download = `${output.name}.${output.extension}`
    document.body.appendChild(link)
    link.click()
    document.body.removeChild(link)
  }

  return (
    <Dialog open={open} onOpenChange={(isOpen) => !isOpen && onClose()}>
      <DialogContent className="max-w-2xl max-h-[80vh]">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Eye className="h-5 w-5" />
            Workflow Results
            {outputs.length > 0 && (
              <Badge variant="secondary">{outputs.length} file{outputs.length !== 1 ? 's' : ''}</Badge>
            )}
          </DialogTitle>
        </DialogHeader>

        <ScrollArea className="h-[60vh] pr-4">
          {isLoading && (
            <div className="flex items-center justify-center py-8">
              <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
            </div>
          )}

          {!isLoading && outputs.length === 0 && (
            <div className="flex flex-col items-center justify-center py-12 text-center">
              <File className="h-12 w-12 text-muted-foreground mb-4" />
              <p className="text-sm text-muted-foreground">
                No output files found. The workflow may still be running.
              </p>
            </div>
          )}

          {!isLoading && outputs.length > 0 && (
            <div className="space-y-2">
              {outputs.map((output) => (
                <Card key={output.id} className="p-3">
                  <div className="flex items-center gap-3">
                    {/* File icon */}
                    {getFileIcon(output.fileType, output.extension)}

                    {/* File info */}
                    <div className="flex-1 min-w-0">
                      <div className="font-medium text-sm truncate">
                        {output.name}
                      </div>
                      <div className="text-xs text-muted-foreground flex items-center gap-2">
                        <span className="uppercase">{output.extension}</span>
                        <span>•</span>
                        <span>{formatBytes(output.size)}</span>
                        {output.fileType === 'interactive' && (
                          <>
                            <span>•</span>
                            <Badge variant="outline" className="text-xs py-0">Interactive</Badge>
                          </>
                        )}
                      </div>
                    </div>

                    {/* Actions */}
                    <div className="flex gap-1">
                      {canViewInline(output.fileType, output.extension) && (
                        <Button
                          size="sm"
                          variant="ghost"
                          onClick={() => handleView(output)}
                          title="View in new tab"
                        >
                          <ExternalLink className="h-4 w-4" />
                        </Button>
                      )}
                      <Button
                        size="sm"
                        variant="ghost"
                        onClick={() => handleDownload(output)}
                        title="Download"
                      >
                        <Download className="h-4 w-4" />
                      </Button>
                    </div>
                  </div>

                  {/* Preview metadata for tables */}
                  {output.fileType === 'table' && output.metadata?.rows && (
                    <div className="mt-2 text-xs text-muted-foreground border-t pt-2">
                      {output.metadata.rows.toLocaleString()} rows
                      {output.metadata.columns && ` × ${output.metadata.columns} columns`}
                    </div>
                  )}

                  {/* Preview metadata for images */}
                  {output.fileType === 'image' && output.metadata?.width && (
                    <div className="mt-2 text-xs text-muted-foreground border-t pt-2">
                      {output.metadata.width} × {output.metadata.height} pixels
                    </div>
                  )}
                </Card>
              ))}
            </div>
          )}
        </ScrollArea>

        {/* Footer actions */}
        {outputs.length > 0 && (
          <div className="flex justify-between items-center pt-4 border-t">
            <div className="text-sm text-muted-foreground">
              Total: {formatBytes(outputs.reduce((sum, o) => sum + o.size, 0))}
            </div>
            <Button
              variant="outline"
              onClick={() => invocationId && handleDownloadAll(invocationId)}
            >
              <Download className="h-4 w-4 mr-2" />
              Download All as ZIP
            </Button>
          </div>
        )}
      </DialogContent>
    </Dialog>
  )
}
