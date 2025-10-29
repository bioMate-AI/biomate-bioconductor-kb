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
} from "lucide-react"
import type { WorkflowInvocation } from "@shared/schema"

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
      const hasRunning = data?.some(inv => inv.status === 'running' || inv.status === 'queued')
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

      {/* Results detail dialog - will be implemented in next phase */}
      {selectedInvocation && (
        <div>TODO: Results detail view</div>
      )}
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
      bgColor: "bg-green-500/10 dark:bg-green-500/20"
    },
    error: {
      icon: XCircle,
      color: "destructive" as const,
      label: "Failed",
      bgColor: "bg-red-500/10 dark:bg-red-500/20"
    },
    queued: {
      icon: Clock,
      color: "secondary" as const,
      label: "Queued",
      bgColor: "bg-blue-500/10 dark:bg-blue-500/20"
    },
    new: {
      icon: Clock,
      color: "secondary" as const,
      label: "Starting",
      bgColor: "bg-blue-500/10 dark:bg-blue-500/20"
    },
    paused: {
      icon: Clock,
      color: "secondary" as const,
      label: "Paused",
      bgColor: "bg-gray-500/10 dark:bg-gray-500/20"
    },
    deleted: {
      icon: Trash2,
      color: "secondary" as const,
      label: "Deleted",
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
  // TODO: Implement download all as zip
  console.log('Download all outputs for:', invocationId)
}

async function handleRetry(invocationId: string) {
  // TODO: Implement workflow retry
  console.log('Retry workflow:', invocationId)
}
