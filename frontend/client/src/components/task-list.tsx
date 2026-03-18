/**
 * TaskList — shown at the bottom of the AI reply while LangGraph is orchestrating.
 * Shows generation sub-tasks (from SSE) and queued chat messages.
 */
import { CheckCircle2, XCircle, Loader2, Circle, StopCircle, Minus } from 'lucide-react'
import { Separator } from '@/components/ui/separator'
import { useState } from 'react'

export type TaskStatus = 'pending' | 'running' | 'completed' | 'failed' | 'stopped' | 'skipped'

export interface TaskItem {
  id: string
  description: string
  status: TaskStatus
  elapsedMs?: number
}

interface TaskListProps {
  tasks: TaskItem[]
  queuedMessages: string[]
  onStopTask: (taskId: string) => void
  onRemoveTask: (taskId: string) => void
  onRetryTask: (taskId: string) => void
  onRemoveMessage: (index: number) => void
}

function StatusIcon({ status }: { status: TaskStatus }) {
  switch (status) {
    case 'completed': return <CheckCircle2 className="h-3.5 w-3.5 text-green-500 flex-shrink-0" />
    case 'running':   return <Loader2 className="h-3.5 w-3.5 text-blue-500 animate-spin flex-shrink-0" />
    case 'failed':    return <XCircle className="h-3.5 w-3.5 text-red-500 flex-shrink-0" />
    case 'stopped':   return <StopCircle className="h-3.5 w-3.5 text-amber-500 flex-shrink-0" />
    case 'skipped':   return <Minus className="h-3.5 w-3.5 text-muted-foreground flex-shrink-0" />
    default:          return <Circle className="h-3.5 w-3.5 text-muted-foreground flex-shrink-0" />
  }
}

function formatElapsed(ms?: number) {
  if (!ms) return ''
  if (ms < 1000) return `${ms}ms`
  return `${(ms / 1000).toFixed(1)}s`
}

export function TaskList({
  tasks,
  queuedMessages,
  onStopTask,
  onRemoveTask,
  onRetryTask,
  onRemoveMessage,
}: TaskListProps) {
  const [expanded, setExpanded] = useState(true)

  const allDone = tasks.length > 0 && tasks.every(
    t => t.status === 'completed' || t.status === 'skipped'
  )

  if (allDone && !expanded) {
    return (
      <div
        data-testid="task-list-summary"
        className="mt-2 flex items-center gap-1.5 text-xs text-muted-foreground"
      >
        <CheckCircle2 className="h-3.5 w-3.5 text-green-500" />
        <span>{tasks.length} step{tasks.length !== 1 ? 's' : ''} complete</span>
        <button
          className="underline underline-offset-2 hover:no-underline"
          onClick={() => setExpanded(true)}
        >
          show steps
        </button>
      </div>
    )
  }

  const showSummaryToggle = allDone && expanded

  return (
    <div
      data-testid="task-list"
      className="mt-3 rounded-md border border-border/60 bg-muted/30 text-xs"
    >
      {/* Header */}
      <div className="flex items-center justify-between px-3 py-1.5 border-b border-border/40">
        <span className="font-medium text-muted-foreground uppercase tracking-wide text-[10px]">Tasks</span>
        {showSummaryToggle && (
          <button
            className="text-muted-foreground underline underline-offset-2 hover:no-underline"
            onClick={() => setExpanded(false)}
          >
            collapse
          </button>
        )}
      </div>

      {/* Generation tasks */}
      {tasks.length > 0 && (
        <div className="divide-y divide-border/30">
          {tasks.map(task => (
            <div
              key={task.id}
              data-testid={`task-row-${task.id}`}
              className="flex items-center gap-2 px-3 py-1.5"
            >
              <StatusIcon status={task.status} />
              <span className={`flex-1 truncate ${task.status === 'skipped' ? 'line-through text-muted-foreground' : ''}`}>
                {task.description}
              </span>
              {task.elapsedMs != null && (
                <span className="text-muted-foreground flex-shrink-0">{formatElapsed(task.elapsedMs)}</span>
              )}
              {/* Per-row action button */}
              {task.status === 'running' && (
                <button
                  data-testid={`task-stop-${task.id}`}
                  className="flex-shrink-0 rounded border border-border px-2 py-0.5 hover:bg-muted"
                  onClick={() => onStopTask(task.id)}
                >
                  Stop
                </button>
              )}
              {(task.status === 'failed' || task.status === 'stopped') && (
                <button
                  data-testid={`task-retry-${task.id}`}
                  className="flex-shrink-0 rounded border border-border px-2 py-0.5 hover:bg-muted"
                  onClick={() => onRetryTask(task.id)}
                >
                  Retry
                </button>
              )}
              {(task.status === 'pending' || task.status === 'completed' || task.status === 'skipped') && (
                <button
                  data-testid={`task-remove-${task.id}`}
                  className="flex-shrink-0 text-muted-foreground hover:text-foreground"
                  onClick={() => onRemoveTask(task.id)}
                  title="Remove"
                >
                  ×
                </button>
              )}
            </div>
          ))}
        </div>
      )}

      {/* Queued messages section */}
      {queuedMessages.length > 0 && (
        <>
          {tasks.length > 0 && (
            <div className="px-3 py-1 flex items-center gap-2">
              <Separator className="flex-1" />
              <span className="text-[10px] text-muted-foreground uppercase tracking-wide flex-shrink-0">Queued messages</span>
              <Separator className="flex-1" />
            </div>
          )}
          <div className="divide-y divide-border/30">
            {queuedMessages.map((msg, i) => (
              <div
                key={i}
                data-testid={`queued-message-${i}`}
                className="flex items-center gap-2 px-3 py-1.5"
              >
                <Circle className="h-3.5 w-3.5 text-muted-foreground flex-shrink-0" />
                <span className="flex-1 truncate text-muted-foreground italic">
                  {msg.length > 60 ? `${msg.slice(0, 60)}…` : msg}
                </span>
                <button
                  data-testid={`queued-message-remove-${i}`}
                  className="flex-shrink-0 text-muted-foreground hover:text-foreground"
                  onClick={() => onRemoveMessage(i)}
                  title="Remove"
                >
                  ×
                </button>
              </div>
            ))}
          </div>
        </>
      )}
    </div>
  )
}
