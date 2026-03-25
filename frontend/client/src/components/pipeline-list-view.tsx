import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Separator } from '@/components/ui/separator'
import {
  CheckCircle2,
  XCircle,
  Clock,
  Loader2,
  Minus,
  Play,
  ArrowRight,
  ArrowLeft,
  GitMerge,
} from 'lucide-react'
import { cn } from '@/lib/utils'

// ─── Types ────────────────────────────────────────────────────────────────────

export interface PipelineStep {
  id: string
  /** 1-based display number — auto-derived from array index if omitted */
  stepNumber?: number
  workflowName: string
  /** disk path to main.nf — accepted as either workflowPath or nextflowPath */
  workflowPath?: string
  nextflowPath?: string
  params: Record<string, any>
  status: 'pending' | 'running' | 'completed' | 'failed' | 'skipped'
  outputTypes?: string[]
  /** step id whose output feeds this step — also accepted as inputFrom */
  usesStepId?: string
  inputFrom?: string
  /** human description of the data dependency — also accepted as inputType */
  usesDescription?: string
  inputType?: string
  runParallelWith?: string[]
  durationMs?: number
  errorMessage?: string
}

export interface PipelineListViewProps {
  steps: PipelineStep[]
  /** called when user clicks Confirm & Run — receives steps or no args */
  onConfirmRun?: () => void
  onConfirm?: (steps: PipelineStep[]) => void
  onRemoveStep?: (stepId: string) => void
  onModifyStep?: (stepId: string, message: string) => void
  onClose?: () => void
  isReadOnly?: boolean
  chainRunId?: string
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

/** HTML entities exist for ① – ⑳ (Unicode circled numbers) */
const CIRCLED_DIGITS = [
  '①', '②', '③', '④', '⑤',
  '⑥', '⑦', '⑧', '⑨', '⑩',
  '⑪', '⑫', '⑬', '⑭', '⑮',
  '⑯', '⑰', '⑱', '⑲', '⑳',
]

function circledNumber(n: number): string {
  if (n >= 1 && n <= 20) return CIRCLED_DIGITS[n - 1]
  return `(${n})`
}

function formatDuration(ms: number): string {
  if (ms < 1000) return `${ms}ms`
  if (ms < 60_000) return `${(ms / 1000).toFixed(1)}s`
  const m = Math.floor(ms / 60_000)
  const s = Math.round((ms % 60_000) / 1000)
  return `${m}m ${s}s`
}

function renderParamSummary(params: Record<string, string | number | boolean>): string {
  const entries = Object.entries(params).slice(0, 3)
  const parts = entries.map(([k, v]) => `${k}: ${v}`)
  if (Object.keys(params).length > 3) parts.push('…')
  return parts.join(' | ')
}

// ─── Status Badge ─────────────────────────────────────────────────────────────

interface StatusBadgeProps {
  status: PipelineStep['status']
}

function StepStatusBadge({ status }: StatusBadgeProps) {
  const configs: Record<PipelineStep['status'], { label: string; icon: React.ReactNode; className: string }> = {
    pending: {
      label: 'PENDING',
      icon: <Clock className="h-3 w-3" />,
      className: 'bg-gray-100 text-gray-600 border-gray-200 dark:bg-gray-800 dark:text-gray-400 dark:border-gray-700',
    },
    running: {
      label: 'RUNNING',
      icon: <Loader2 className="h-3 w-3 animate-spin" />,
      className: 'bg-blue-100 text-blue-700 border-blue-200 dark:bg-blue-900/40 dark:text-blue-300 dark:border-blue-800',
    },
    completed: {
      label: 'COMPLETED',
      icon: <CheckCircle2 className="h-3 w-3" />,
      className: 'bg-green-100 text-green-700 border-green-200 dark:bg-green-900/40 dark:text-green-300 dark:border-green-800',
    },
    failed: {
      label: 'FAILED',
      icon: <XCircle className="h-3 w-3" />,
      className: 'bg-red-100 text-red-700 border-red-200 dark:bg-red-900/40 dark:text-red-300 dark:border-red-800',
    },
    skipped: {
      label: 'SKIPPED',
      icon: <Minus className="h-3 w-3" />,
      className: 'bg-muted text-muted-foreground border-border',
    },
  }

  const cfg = configs[status]
  return (
    <Badge
      variant="outline"
      className={cn('flex items-center gap-1 text-[10px] font-semibold tracking-wide px-1.5 py-0.5', cfg.className)}
    >
      {cfg.icon}
      {cfg.label}
    </Badge>
  )
}

// ─── Step Row ─────────────────────────────────────────────────────────────────

interface StepRowProps {
  step: PipelineStep
  steps: PipelineStep[]
  isReadOnly: boolean
  onRemoveStep?: (id: string) => void
  onModifyStep?: (id: string, message: string) => void
  isFirst: boolean
  isLast: boolean
}

function StepRow({ step, steps, isReadOnly, onRemoveStep, onModifyStep }: StepRowProps) {
  const usesStep = step.usesStepId
    ? steps.find(s => s.id === step.usesStepId)
    : undefined

  const paramSummary = renderParamSummary(step.params)
  const hasParams = Object.keys(step.params).length > 0

  return (
    <div
      data-testid={`pipeline-step-${step.id}`}
      className={cn(
        'relative flex gap-3 p-3 rounded-lg border transition-colors',
        step.status === 'running' && 'border-blue-300 bg-blue-50/50 dark:border-blue-800 dark:bg-blue-900/10',
        step.status === 'completed' && 'border-green-200 bg-green-50/30 dark:border-green-900 dark:bg-green-900/10',
        step.status === 'failed' && 'border-red-200 bg-red-50/30 dark:border-red-900 dark:bg-red-900/10',
        step.status === 'skipped' && 'opacity-60 border-border bg-muted/20',
        step.status === 'pending' && 'border-border bg-card',
      )}
    >
      {/* Circle number */}
      <div
        className={cn(
          'flex-shrink-0 w-7 h-7 rounded-full flex items-center justify-center text-sm font-semibold select-none',
          step.status === 'pending' && 'bg-muted text-muted-foreground',
          step.status === 'running' && 'bg-blue-500 text-white',
          step.status === 'completed' && 'bg-green-500 text-white',
          step.status === 'failed' && 'bg-red-500 text-white',
          step.status === 'skipped' && 'bg-muted text-muted-foreground',
        )}
        aria-label={`Step ${step.stepNumber ?? ''}`}
      >
        {circledNumber(step.stepNumber ?? 1)}
      </div>

      {/* Body */}
      <div className="flex-1 min-w-0 space-y-1">
        {/* Name + status */}
        <div className="flex items-start justify-between gap-2">
          <span className="font-semibold text-sm leading-snug truncate">{step.workflowName}</span>
          <div className="flex items-center gap-1.5 flex-shrink-0">
            {step.durationMs != null && step.status === 'completed' && (
              <span className="text-[10px] text-muted-foreground font-mono">
                {formatDuration(step.durationMs)}
              </span>
            )}
            <StepStatusBadge status={step.status} />
            {!isReadOnly && (
              <button
                data-testid={`pipeline-step-remove-${step.id}`}
                className="text-muted-foreground hover:text-destructive transition-colors p-0.5 rounded"
                onClick={() => onRemoveStep?.(step.id)}
                title="Remove step"
                aria-label={`Remove step ${step.stepNumber}`}
              >
                ×
              </button>
            )}
          </div>
        </div>

        {/* Params */}
        {hasParams && (
          <p className="text-xs text-muted-foreground font-mono leading-relaxed">
            {paramSummary}
          </p>
        )}

        {/* Outputs */}
        {step.outputTypes && step.outputTypes.length > 0 && (
          <p className="text-xs text-muted-foreground flex items-center gap-1">
            <ArrowRight className="h-3 w-3 text-emerald-500 flex-shrink-0" />
            <span>
              <span className="text-emerald-600 dark:text-emerald-400 font-medium">outputs:</span>{' '}
              {step.outputTypes.join(', ')}
            </span>
          </p>
        )}

        {/* Uses step */}
        {usesStep && (
          <p className="text-xs text-muted-foreground flex items-center gap-1">
            <ArrowLeft className="h-3 w-3 text-sky-500 flex-shrink-0" />
            <span>
              <span className="text-sky-600 dark:text-sky-400 font-medium">uses:</span>{' '}
              {circledNumber(usesStep.stepNumber ?? 1)}
              {step.usesDescription && ` ${step.usesDescription}`}
            </span>
          </p>
        )}

        {/* Error message */}
        {step.status === 'failed' && step.errorMessage && (
          <p className="text-xs text-red-600 dark:text-red-400 mt-1 leading-snug">
            ⚠ {step.errorMessage}
          </p>
        )}

        {/* Modify shortcut */}
        {!isReadOnly && onModifyStep && (
          <button
            className="text-[10px] text-muted-foreground underline underline-offset-2 hover:no-underline"
            onClick={() => onModifyStep?.(step.id, `modify step ${step.stepNumber ?? ''} `)}
          >
            edit via chat
          </button>
        )}
      </div>
    </div>
  )
}

// ─── Main Component ───────────────────────────────────────────────────────────

export function PipelineListView({
  steps: rawSteps,
  onConfirmRun,
  onConfirm,
  onRemoveStep,
  onModifyStep,
  onClose,
  isReadOnly = false,
  chainRunId,
}: PipelineListViewProps) {
  // Normalise steps: fill in stepNumber and field aliases
  const steps: PipelineStep[] = rawSteps.map((s, i) => ({
    ...s,
    stepNumber: s.stepNumber ?? i + 1,
    workflowPath: s.workflowPath ?? s.nextflowPath,
    usesStepId: s.usesStepId ?? s.inputFrom,
    usesDescription: s.usesDescription ?? s.inputType,
  }))

  const handleConfirm = () => {
    onConfirmRun?.()
    onConfirm?.(steps)
  }

  const anyRunning = steps.some(s => s.status === 'running')
  const confirmDisabled = isReadOnly || anyRunning || steps.length === 0

  /**
   * Build a rendering plan: group parallel steps together so we can
   * insert a "run in parallel" label above the group.
   *
   * A step is in a parallel group if its `runParallelWith` array
   * mentions another step's id, OR another step's `runParallelWith`
   * mentions this step's id. We union these into groups and deduplicate.
   */
  type RenderItem =
    | { type: 'step'; step: PipelineStep; isFirst: boolean; isLast: boolean }
    | { type: 'parallel-group'; groupSteps: PipelineStep[] }

  const rendered: RenderItem[] = []
  const handledIds = new Set<string>()

  for (const step of steps) {
    if (handledIds.has(step.id)) continue

    // Collect all steps that are parallel to this one
    const parallelIds = new Set<string>()
    if (step.runParallelWith && step.runParallelWith.length > 0) {
      step.runParallelWith.forEach(id => parallelIds.add(id))
    }
    // Check if other steps mention this one
    steps.forEach(s => {
      if (s.runParallelWith?.includes(step.id)) {
        parallelIds.add(s.id)
      }
    })

    if (parallelIds.size > 0) {
      const groupSteps = [step, ...steps.filter(s => parallelIds.has(s.id))]
        .sort((a, b) => (a.stepNumber ?? 0) - (b.stepNumber ?? 0))
      groupSteps.forEach(s => handledIds.add(s.id))
      rendered.push({ type: 'parallel-group', groupSteps })
    } else {
      handledIds.add(step.id)
      rendered.push({
        type: 'step',
        step,
        isFirst: rendered.length === 0,
        isLast: false, // updated below
      })
    }
  }

  // Update isLast flag
  for (let i = 0; i < rendered.length; i++) {
    const item = rendered[i]
    if (item.type === 'step') {
      rendered[i] = { ...item, isLast: i === rendered.length - 1 }
    }
  }

  return (
    <div
      data-testid="pipeline-list-view"
      className="rounded-xl border border-border bg-card shadow-sm overflow-hidden"
    >
      {/* ── Header ── */}
      <div className="px-4 py-3 bg-muted/40 border-b border-border">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <GitMerge className="h-4 w-4 text-muted-foreground" />
            <span className="text-xs font-semibold uppercase tracking-widest text-muted-foreground">
              Pipeline
            </span>
            <Badge variant="secondary" className="text-xs font-mono">
              {steps.length} step{steps.length !== 1 ? 's' : ''}
            </Badge>
          </div>
          {chainRunId && (
            <span className="text-[10px] font-mono text-muted-foreground">
              run: {chainRunId.slice(0, 8)}…
            </span>
          )}
        </div>
      </div>

      <Separator />

      {/* ── Step list ── */}
      <div className="p-3 space-y-2">
        {steps.length === 0 ? (
          <p className="text-sm text-muted-foreground text-center py-6">
            No steps in this pipeline yet.
          </p>
        ) : (
          rendered.map((item, idx) => {
            if (item.type === 'step') {
              return (
                <StepRow
                  key={item.step.id}
                  step={item.step}
                  steps={steps}
                  isReadOnly={isReadOnly}
                  onRemoveStep={onRemoveStep}
                  onModifyStep={onModifyStep}
                  isFirst={item.isFirst}
                  isLast={item.isLast}
                />
              )
            }

            // Parallel group
            const { groupSteps } = item
            const stepNums = groupSteps.map(s => `step ${s.stepNumber ?? '?'}`).join(' and ')
            return (
              <div key={`parallel-${idx}`} className="space-y-1.5">
                <div className="flex items-center gap-2 px-1">
                  <div className="h-px flex-1 bg-border" />
                  <span className="text-[10px] text-muted-foreground uppercase tracking-wide flex-shrink-0 flex items-center gap-1">
                    <GitMerge className="h-3 w-3" />
                    {stepNums} run in parallel
                  </span>
                  <div className="h-px flex-1 bg-border" />
                </div>
                <div className="space-y-1.5 pl-2 border-l-2 border-dashed border-blue-200 dark:border-blue-800">
                  {groupSteps.map((s, si) => (
                    <StepRow
                      key={s.id}
                      step={s}
                      steps={steps}
                      isReadOnly={isReadOnly}
                      onRemoveStep={onRemoveStep}
                      onModifyStep={onModifyStep}
                      isFirst={idx === 0 && si === 0}
                      isLast={idx === rendered.length - 1 && si === groupSteps.length - 1}
                    />
                  ))}
                </div>
              </div>
            )
          })
        )}
      </div>

      <Separator />

      {/* ── Chat hint ── */}
      {!isReadOnly && (
        <div className="px-4 py-2 bg-muted/20 text-xs text-muted-foreground">
          💬 Chat to edit: "remove step 2", "change padj to 0.01", "add GSEA after step 3"
        </div>
      )}

      <Separator />

      {/* ── Footer / Confirm ── */}
      <div className="px-4 py-3 flex items-center justify-between gap-3">
        <span className="text-xs text-muted-foreground">
          {anyRunning
            ? 'Pipeline is running…'
            : isReadOnly
            ? 'Run in progress — edits disabled'
            : `${steps.length} step${steps.length !== 1 ? 's' : ''} ready`}
        </span>
        <Button
          data-testid="pipeline-confirm-run"
          onClick={handleConfirm}
          disabled={confirmDisabled}
          className={cn(
            'gap-2',
            !confirmDisabled && 'bg-green-600 hover:bg-green-700 dark:bg-green-700 dark:hover:bg-green-600 text-white',
          )}
        >
          {anyRunning ? (
            <Loader2 className="h-4 w-4 animate-spin" />
          ) : (
            <Play className="h-4 w-4" />
          )}
          {anyRunning ? 'Running…' : 'Confirm & Run Pipeline'}
        </Button>
      </div>
    </div>
  )
}

export default PipelineListView
