import { useState, useEffect, useRef } from "react"
import { Card, CardContent, CardHeader } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible"
import { Progress } from "@/components/ui/progress"
import { Separator } from "@/components/ui/separator"
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert"
import {
  ChevronDown,
  ChevronRight,
  Play,
  Square,
  Settings2,
  CheckCircle2,
  Clock,
  AlertCircle,
  Loader2,
  Workflow,
  FileOutput,
  BookOpen,
  FlaskConical,
  AlertTriangle,
  Info,
  FileText,
  Laptop,
  Scissors,
  Download,
  Sparkles,
  History,
  Lock,
} from "lucide-react"
import { cn, getSimpleToolName } from "@/lib/utils"
import { ParameterDialog } from "./parameter-dialog"
import { CitationPanel } from "./citation-panel"
import { PilotRunPanel } from "./pilot-run-panel"
import { ExecutionControlPanel } from "./execution-control-panel"
import { WorkflowReportViewer } from "./workflow-report-viewer"
import { InteractiveLauncher } from "./interactive-launcher"
import { SubworkflowExtractor } from "./subworkflow-extractor"
import { QCGateModal } from "./qc-gate-modal"
import type { Citation, MethodsSection, TuningConfig, ParameterRecommendation, ExecutionRun, ExecutionConfig } from "@shared/schema"

interface WorkflowStep {
  id: string
  name?: string
  tool_id?: string
  title?: string
  description?: string
  status?: 'pending' | 'running' | 'completed' | 'error'
  parameters?: Record<string, any>
  inputs?: any[]
  outputs?: any[]
}

interface OutputFile {
  id: string
  name: string
  size: number
  type?: string
}

interface WorkflowArtifactProps {
  workflow: {
    name?: string
    annotation?: string
    steps?: any
  }
  steps: WorkflowStep[]
  confidence?: number
  onRun?: (workflow: any, steps: WorkflowStep[]) => void
  onStop?: () => void
  onParameterChange?: (stepId: string, params: Record<string, any>) => void
  isRunning?: boolean
  progress?: number
  className?: string
  // Citation support
  citations?: Citation[]
  methodsSection?: MethodsSection
  onViewCitations?: () => void
  // Pilot run support - enhanced with reasons
  pilotRunSuggested?: boolean
  pilotReasons?: string[]
  pilotMessage?: string
  totalSamples?: number
  tuningConfig?: TuningConfig
  onStartPilotRun?: (config: TuningConfig) => Promise<void>
  onProceedToFullRun?: (params: Record<string, any>) => void
  // Parameter recommendations
  parameterRecommendations?: Record<string, ParameterRecommendation>
  // Validation info
  validationIssues?: string[]
  validationWarnings?: string[]
  // Completion state (for post-execution actions)
  isCompleted?: boolean
  invocationId?: string
  galaxyWorkflowId?: string
  galaxyHistoryId?: string
  outputs?: OutputFile[]
  // Unified Execution (new system - replaces pilot run when enabled)
  useUnifiedExecution?: boolean
  currentExecutionRun?: ExecutionRun
  previousExecutionRuns?: ExecutionRun[]
  onUnifiedExecute?: (config: ExecutionConfig) => Promise<void>
  onPauseExecution?: () => Promise<void>
  onResumeExecution?: () => Promise<void>
  onCancelExecution?: () => Promise<void>
  onPromoteToProduction?: (runId: string) => void
  strataColumns?: string[]
  // Prerequisites validation (from LLM analysis of input/parameter requirements)
  prerequisitesValidation?: {
    fulfilled: boolean
    analysis: {
      missingInputs: Array<{ stepId: string; stepLabel: string; inputName: string; description: string; expectedFormats?: string[] }>
      missingParameters: Array<{ stepId: string; stepLabel: string; parameterName: string; description: string }>
      inputMappings: Array<{ stepId: string; inputName: string; datasetId: string; datasetName: string; compatibility: string }>
    }
    llmResponse?: string
  } | null
}

export function WorkflowArtifact({
  workflow,
  steps,
  confidence = 0,
  onRun,
  onStop,
  onParameterChange,
  isRunning = false,
  progress = 0,
  className,
  // Citation props
  citations = [],
  methodsSection,
  onViewCitations,
  // Pilot run props - enhanced
  pilotRunSuggested = false,
  pilotReasons = [],
  pilotMessage,
  totalSamples = 0,
  tuningConfig,
  onStartPilotRun,
  onProceedToFullRun,
  // Parameter recommendations
  parameterRecommendations = {},
  // Validation info
  validationIssues = [],
  validationWarnings = [],
  // Completion state
  isCompleted = false,
  invocationId,
  galaxyWorkflowId,
  galaxyHistoryId,
  outputs = [],
  // Unified Execution
  useUnifiedExecution = false,
  currentExecutionRun,
  previousExecutionRuns = [],
  onUnifiedExecute,
  onPauseExecution,
  onResumeExecution,
  onCancelExecution,
  onPromoteToProduction,
  strataColumns = [],
  prerequisitesValidation = null
}: WorkflowArtifactProps) {
  const [isExpanded, setIsExpanded] = useState(true)
  const [expandedSteps, setExpandedSteps] = useState<Set<string>>(new Set())
  const [editingStep, setEditingStep] = useState<WorkflowStep | null>(null)
  const [showCitations, setShowCitations] = useState(false)
  const [showPilotRun, setShowPilotRun] = useState(false)
  const [showUnifiedExecution, setShowUnifiedExecution] = useState(false)
  // US-4.1 — 7-day localStorage suppression for skip-pilot
  const pilotSuppressKey = `biomate_pilot_suppress_${(workflow.name || '').toLowerCase().replace(/\W+/g, '_')}`
  const [pilotBannerDismissed, setPilotBannerDismissed] = useState(() => {
    try {
      const stored = localStorage.getItem(pilotSuppressKey)
      return stored ? Date.now() < parseInt(stored, 10) : false
    } catch { return false }
  })
  const [autofixStatus, setAutofixStatus] = useState<any | null>(null)
  const [autofixError, setAutofixError] = useState<string | null>(null)
  const [isAutofixRunning, setIsAutofixRunning] = useState(false)
  const [autofixSessions, setAutofixSessions] = useState<any[]>([])
  const [isAutofixSessionsLoading, setIsAutofixSessionsLoading] = useState(false)
  const [showNextflowDetails, setShowNextflowDetails] = useState(false)
  // P1-P3: New dialog states
  const [showReportViewer, setShowReportViewer] = useState(false)
  const [showInteractiveLauncher, setShowInteractiveLauncher] = useState(false)
  const [showSubworkflowExtractor, setShowSubworkflowExtractor] = useState(false)

  // QC Gate modal state (Gap 3)
  const [showQCGateModal, setShowQCGateModal] = useState(false)
  const [qcGateData, setQCGateData] = useState<{
    processName: string
    qcMetrics: Record<string, number>
    // Structured failure objects from backend (preferred) or fallback plain strings
    failures: Array<{ metric: string; value: number; threshold: number; operator: string; message: string } | string>
    suggestions: Array<{
      parameter: string
      currentValue: any
      suggestedValue: any
      reason: string
      confidence: number
    }>
  } | null>(null)
  const [isApplyingSuggestions, setIsApplyingSuggestions] = useState(false)
  // US-7.3 — retry counter + previous metrics per process
  const [qcRetryCount, setQCRetryCount] = useState<Record<string, number>>({})
  const [qcPreviousMetrics, setQCPreviousMetrics] = useState<Record<string, Record<string, number>>>({})
  // US-7.2 — SSE connection status + reconnect refs
  const [sseStatus, setSseStatus] = useState<"connected" | "reconnecting" | "failed">("connected")
  const [sseRetryKey, setSseRetryKey] = useState(0)
  const sseRef = useRef<EventSource | null>(null)
  const reconnectAttemptsRef = useRef(0)
  // US-2.6 — per-step QC annotations
  const [stepQCAnnotations, setStepQCAnnotations] = useState<
    Record<string, { processName: string; failures: any[]; severity?: string }>
  >({})
  // US-6.2 — QC event report fetched after workflow completes
  const [qcReport, setQCReport] = useState<{
    gates_triggered: number
    warnings_emitted: number
    events: any[]
    methods_text: string
    active_profile?: string
  } | null>(null)
  const [showQCSummary, setShowQCSummary] = useState(false)
  // Ref to read latest qcGateData in SSE closure without stale capture
  const qcGateDataRef = useRef(qcGateData)
  qcGateDataRef.current = qcGateData
  // US-4.2 — pauseAtQcFailures ref updated when execution config is submitted
  const pauseAtQcRef = useRef(true)

  // Determine if we should show the pilot suggestion banner prominently
  const showPilotBanner = pilotRunSuggested && !pilotBannerDismissed && !isRunning && pilotReasons.length > 0

  const citationsCount = citations.filter(c => c.doi || c.pmid || c.title).length
  const isFailed = currentExecutionRun?.execution.status === 'failed'
  const autofixWorkflowId = currentExecutionRun?.execution?.galaxyWorkflowId || galaxyWorkflowId
  const autofixInvocationId = currentExecutionRun?.execution?.galaxyInvocationId || invocationId
  const nextflowStatus = currentExecutionRun?.execution?.nextflowStatus
  const sseInvocationId = currentExecutionRun?.execution?.galaxyInvocationId || invocationId

  // Normalize steps array
  const normalizedSteps: WorkflowStep[] = Array.isArray(steps) ? steps :
    (workflow.steps && typeof workflow.steps === 'object' ?
      Object.values(workflow.steps).map((step: any, idx) => ({
        id: step.id || `step-${idx}`,
        name: step.name || step.label || getSimpleToolName(step.tool_id) || `Step ${idx + 1}`,
        tool_id: step.tool_id,
        status: step.status || 'pending',
        parameters: step.tool_state || step.parameters || {},
        inputs: step.inputs || [],
        outputs: step.outputs || []
      })) : [])

  const completedSteps = normalizedSteps.filter(s => s.status === 'completed').length
  const totalSteps = normalizedSteps.length

  // SSE listener for QC gate events (Gap 3) — with exponential-backoff reconnect (US-7.2)
  useEffect(() => {
    if (!sseInvocationId) return

    let stopped = false

    const connect = () => {
      if (stopped) return

      const es = new EventSource(`/api/workflows/${sseInvocationId}/events`)
      sseRef.current = es

      es.onopen = () => {
        reconnectAttemptsRef.current = 0
        setSseStatus("connected")
      }

      es.addEventListener("qc_gate_triggered", (event) => {
        try {
          const data = JSON.parse(event.data)
          console.log("[QC Gate] Event received:", data)

          const processKey = data.process_name
          // US-7.3 — save previous metrics before overwriting, increment retry count
          setQCPreviousMetrics((prev) => ({
            ...prev,
            [processKey]: qcGateDataRef.current?.qcMetrics ?? {},
          }))
          setQCRetryCount((prev) => ({
            ...prev,
            [processKey]: (prev[processKey] ?? 0) + 1,
          }))

          const gateData = {
            processName: data.process_name,
            qcMetrics: data.qc_metrics,
            failures: data.failures || [],
            suggestions: data.suggestions || [],
          }
          setQCGateData(gateData)

          // US-4.2 — auto-apply mode: if pauseAtQcFailures=false, apply high-confidence suggestions silently
          if (!pauseAtQcRef.current && gateData.suggestions.length > 0 && onParameterChange) {
            const highConf = gateData.suggestions.filter((s: any) => (s.confidence ?? 0) >= 0.7)
            console.log(`[QC Gate] Auto-apply mode — applying ${highConf.length}/${gateData.suggestions.length} high-confidence suggestions`)
            for (const suggestion of highConf) {
              const step = normalizedSteps.find(s => {
                if (!s.parameters) return false
                const keys = Object.keys(s.parameters)
                return keys.includes(suggestion.parameter) || keys.some(k => k.toLowerCase() === suggestion.parameter.toLowerCase())
              })
              if (step) {
                const sv = suggestion.suggestedValue
                onParameterChange(step.id, sv !== null && typeof sv === 'object' && !Array.isArray(sv)
                  ? { ...step.parameters, ...sv }
                  : { ...step.parameters, [suggestion.parameter]: sv })
              }
            }
            annotateQCStep(data.process_name, data.failures || [], "warning")
            setQCGateData(null)
            // continue workflow
            if (onRun) void onRun(workflow, normalizedSteps)
          } else {
            setShowQCGateModal(true)
          }
        } catch (error) {
          console.error("[QC Gate] Failed to parse event:", error)
        }
      })

      // US-6.3 — qc_warning → annotate the step without opening a modal
      es.addEventListener("qc_warning", (event) => {
        try {
          const data = JSON.parse(event.data)
          const step = normalizedSteps.find(
            (s) =>
              s.name?.toUpperCase() === data.process_name?.toUpperCase() ||
              s.name
                ?.toUpperCase()
                .includes(data.process_name?.split(":").pop()?.toUpperCase() ?? "")
          )
          if (step) {
            setStepQCAnnotations((prev) => ({
              ...prev,
              [step.id]: {
                processName: data.process_name,
                failures: data.failures || [],
                severity: "warning",
              },
            }))
          }
        } catch (error) {
          console.error("[QC Warning] Failed to parse event:", error)
        }
      })

      // US-1.3 — pilot_qc_passed → auto-advance to full run
      es.addEventListener("pilot_qc_passed", () => {
        if (onRun) {
          onRun(workflow, normalizedSteps)
        }
      })

      es.onerror = () => {
        es.close()
        sseRef.current = null
        if (stopped) return
        const attempt = reconnectAttemptsRef.current
        reconnectAttemptsRef.current += 1
        const delay = Math.min(2000 * Math.pow(2, attempt), 30000)
        if (attempt < 5) {
          setSseStatus("reconnecting")
          setTimeout(connect, delay)
        } else {
          setSseStatus("failed")
        }
      }
    }

    connect()

    return () => {
      stopped = true
      sseRef.current?.close()
      sseRef.current = null
    }
  }, [sseInvocationId, sseRetryKey]) // eslint-disable-line react-hooks/exhaustive-deps

  // US-6.2: fetch QC event report when workflow completes
  useEffect(() => {
    if (!isCompleted || !invocationId) return
    fetch(`/api/invocations/${invocationId}/qc-events`)
      .then(r => r.ok ? r.json() : null)
      .then(data => { if (data) setQCReport(data) })
      .catch(() => {}) // non-critical; summary section simply won't show
  }, [isCompleted, invocationId])

  const toggleStepExpanded = (stepId: string) => {
    setExpandedSteps(prev => {
      const next = new Set(prev)
      if (next.has(stepId)) {
        next.delete(stepId)
      } else {
        next.add(stepId)
      }
      return next
    })
  }

  const getStepIcon = (status?: string) => {
    switch (status) {
      case 'completed': return <CheckCircle2 className="h-4 w-4 text-green-500" />
      case 'running': return <Loader2 className="h-4 w-4 text-blue-500 animate-spin" />
      case 'error': return <AlertCircle className="h-4 w-4 text-red-500" />
      default: return <Clock className="h-4 w-4 text-muted-foreground" />
    }
  }

  const canTriggerAutofix = Boolean(isFailed && autofixWorkflowId && autofixInvocationId)

  const handleAutofix = async () => {
    if (!canTriggerAutofix) return
    if (!autofixWorkflowId || !autofixInvocationId) return
    setIsAutofixRunning(true)
    setAutofixError(null)
    try {
      const response = await fetch(
        `/api/galaxy/workflows/${autofixWorkflowId}/invocations/${autofixInvocationId}/autofix3/run`,
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            max_attempts: 5,
            timeout_seconds: 300,
            auto_apply: false,
          }),
        }
      )
      if (!response.ok) {
        const errorPayload = await response.json().catch(() => ({}))
        throw new Error(errorPayload.message || errorPayload.error || 'AutoFix failed')
      }
      const data = await response.json()
      setAutofixStatus(data)
    } catch (error: any) {
      setAutofixError(error.message || 'AutoFix failed')
    } finally {
      setIsAutofixRunning(false)
    }
  }

  const handleFetchAutofixSessions = async () => {
    if (!autofixWorkflowId || !autofixInvocationId) return
    setIsAutofixSessionsLoading(true)
    setAutofixError(null)
    try {
      const response = await fetch(
        `/api/galaxy/workflows/${autofixWorkflowId}/invocations/${autofixInvocationId}/autofix3/sessions?limit=5`
      )
      if (!response.ok) {
        const errorPayload = await response.json().catch(() => ({}))
        throw new Error(errorPayload.message || errorPayload.error || 'Failed to load AutoFix history')
      }
      const data = await response.json()
      setAutofixSessions(data.sessions || [])
    } catch (error: any) {
      setAutofixError(error.message || 'Failed to load AutoFix history')
    } finally {
      setIsAutofixSessionsLoading(false)
    }
  }

  const handleSaveParameters = (params: Record<string, any>) => {
    if (editingStep && onParameterChange) {
      onParameterChange(editingStep.id, params)
    }
    setEditingStep(null)
  }

  // QC Gate handlers (Gap 3)
  const handleRetryWithSuggestions = async () => {
    if (!qcGateData || !onParameterChange) return

    setIsApplyingSuggestions(true)
    try {
      for (const suggestion of qcGateData.suggestions) {
        // Exact key match first; fall back to case-insensitive exact match.
        // substring/includes is intentionally avoided — it causes false positives
        // e.g. "dose" matching "overdose_correction".
        const step = normalizedSteps.find(s => {
          if (!s.parameters) return false
          const keys = Object.keys(s.parameters)
          return (
            keys.includes(suggestion.parameter) ||
            keys.some(k => k.toLowerCase() === suggestion.parameter.toLowerCase())
          )
        })

        if (step) {
          const suggestedValue = suggestion.suggestedValue
          // If suggestedValue is a plain object (e.g. defocus range dict), merge each key
          if (suggestedValue !== null && typeof suggestedValue === 'object' && !Array.isArray(suggestedValue)) {
            console.log(`[QC Gate] Applying dict suggestion for ${suggestion.parameter}:`, suggestedValue)
            onParameterChange(step.id, { ...step.parameters, ...suggestedValue })
          } else {
            console.log(`[QC Gate] Applying ${suggestion.parameter}: ${suggestion.currentValue} → ${suggestedValue}`)
            onParameterChange(step.id, { ...step.parameters, [suggestion.parameter]: suggestedValue })
          }
        } else {
          console.warn(`[QC Gate] No step found with parameter "${suggestion.parameter}" — suggestion skipped`)
        }
      }

      setShowQCGateModal(false)
      setQCGateData(null)

      if (onRun) {
        await onRun(workflow, normalizedSteps)
      }
    } catch (error) {
      console.error('[QC Gate] Failed to apply suggestions:', error)
    } finally {
      setIsApplyingSuggestions(false)
    }
  }

  // US-2.6 — helper: find the step matching a QC process name and annotate it
  const annotateQCStep = (processName: string, failures: any[], severity: string) => {
    const key = processName.split(":").pop()?.toUpperCase() ?? processName.toUpperCase()
    const step = normalizedSteps.find(
      (s) =>
        s.name?.toUpperCase() === processName.toUpperCase() ||
        s.name?.toUpperCase() === key
    )
    if (step) {
      setStepQCAnnotations((prev) => ({
        ...prev,
        [step.id]: { processName, failures, severity },
      }))
    }
  }

  const handleProceedAnyway = () => {
    console.log("[QC Gate] User chose to proceed despite QC failures")
    if (qcGateData) {
      annotateQCStep(qcGateData.processName, qcGateData.failures, "failed")
    }
    setShowQCGateModal(false)
    setQCGateData(null)
  }

  const handleCancelWorkflow = () => {
    console.log("[QC Gate] User cancelled workflow due to QC failures")
    if (qcGateData) {
      annotateQCStep(qcGateData.processName, qcGateData.failures, "failed")
    }
    setShowQCGateModal(false)
    setQCGateData(null)
    if (onStop) {
      onStop()
    }
  }

  return (
    <>
      <Card className={cn("border-2 border-primary/20 bg-gradient-to-br from-card to-muted/30", className)}>
        <Collapsible open={isExpanded} onOpenChange={setIsExpanded}>
          {/* Header - Always visible */}
          <CardHeader className="p-4 pb-2">
            <div className="flex items-center justify-between">
              <CollapsibleTrigger asChild>
                <Button variant="ghost" className="p-0 h-auto hover:bg-transparent">
                  <div className="flex items-center gap-2">
                    {isExpanded ? (
                      <ChevronDown className="h-4 w-4" />
                    ) : (
                      <ChevronRight className="h-4 w-4" />
                    )}
                    <Workflow className="h-5 w-5 text-primary" />
                    <span className="font-semibold">
                      {workflow.name || 'Generated Workflow'}
                    </span>
                  </div>
                </Button>
              </CollapsibleTrigger>

              <div className="flex items-center gap-2">
                <Badge variant="secondary" className="text-xs">
                  {totalSteps} step{totalSteps !== 1 ? 's' : ''}
                </Badge>
                {confidence > 0 && (() => {
                  // Normalize confidence to 0-100 range for display
                  const normalizedConfidence = confidence > 1 ? confidence : confidence * 100;
                  return (
                    <Badge
                      variant={normalizedConfidence > 80 ? "default" : normalizedConfidence > 60 ? "secondary" : "outline"}
                      className="text-xs"
                    >
                      {normalizedConfidence.toFixed(0)}% confidence
                    </Badge>
                  );
                })()}

                {/* Citation badge */}
                {citationsCount > 0 && (
                  <Button
                    variant="ghost"
                    size="sm"
                    className="h-7 px-2 text-xs"
                    onClick={() => {
                      setShowCitations(!showCitations)
                      onViewCitations?.()
                    }}
                  >
                    <BookOpen className="h-3 w-3 mr-1" />
                    {citationsCount} citation{citationsCount !== 1 ? 's' : ''}
                  </Button>
                )}

                {/* Execution button - unified or legacy pilot */}
                {pilotRunSuggested && !isRunning && (
                  <Button
                    variant="outline"
                    size="sm"
                    className="h-7 px-2 text-xs border-amber-500/50 text-amber-600 hover:bg-amber-50 dark:hover:bg-amber-950/20"
                    onClick={() => useUnifiedExecution ? setShowUnifiedExecution(true) : setShowPilotRun(true)}
                  >
                    <FlaskConical className="h-3 w-3 mr-1" />
                    {useUnifiedExecution ? 'Execute' : 'Pilot Run'}
                  </Button>
                )}

                {isRunning ? (
                  <Button size="sm" variant="destructive" onClick={onStop}>
                    <Square className="h-3 w-3 mr-1" />
                    Stop
                  </Button>
                ) : (
                  <Button
                    size="sm"
                    onClick={() => onRun?.(workflow, normalizedSteps)}
                    className="bg-green-600 hover:bg-green-700"
                    disabled={prerequisitesValidation?.fulfilled === false}
                    title={prerequisitesValidation?.fulfilled === false ? 'Missing required inputs - see details below' : undefined}
                  >
                    <Play className="h-3 w-3 mr-1" />
                    Run
                  </Button>
                )}
              </div>
            </div>

            {/* Progress bar when running */}
            {isRunning && (
              <div className="mt-3 space-y-1">
                <div className="flex justify-between text-xs text-muted-foreground">
                  <span>Running workflow...</span>
                  <span>{completedSteps}/{totalSteps} complete</span>
                </div>
                <Progress value={(completedSteps / totalSteps) * 100} className="h-2" />
              </div>
            )}

            {nextflowStatus && (
              <div className="mt-3 rounded-md border border-blue-200/60 bg-blue-50/40 px-3 py-2 text-xs text-blue-800 dark:border-blue-900/60 dark:bg-blue-950/20 dark:text-blue-200">
                <div className="flex flex-wrap gap-3">
                  <span>Nextflow progress: {nextflowStatus.progressPercent ?? 0}%</span>
                  <span>Completed: {nextflowStatus.completedTasks ?? 0}/{nextflowStatus.totalTasks ?? 0}</span>
                  <span>Running: {nextflowStatus.runningTasks ?? 0}</span>
                  <span>Failed: {nextflowStatus.failedTasks ?? 0}</span>
                </div>
                {Array.isArray(nextflowStatus.processes) && nextflowStatus.processes.length > 0 && (
                  <div className="mt-2">
                    <Button
                      size="sm"
                      variant="ghost"
                      className="h-6 px-2 text-xs"
                      onClick={() => setShowNextflowDetails((prev) => !prev)}
                    >
                      {showNextflowDetails ? 'Hide details' : 'View details'}
                    </Button>
                    {showNextflowDetails && (
                      <div className="mt-2 space-y-1">
                        {nextflowStatus.processes.slice(0, 6).map((proc: any, idx: number) => (
                          <div key={proc.name || idx} className="text-xs text-muted-foreground">
                            {proc.name || `Process ${idx + 1}`} · {proc.status || 'unknown'} · {proc.completed || 0}/{proc.total || 0}
                          </div>
                        ))}
                        {nextflowStatus.processes.length > 6 && (
                          <div className="text-xs text-muted-foreground">
                            …and {nextflowStatus.processes.length - 6} more
                          </div>
                        )}
                      </div>
                    )}
                  </div>
                )}
              </div>
            )}

            {/* Prerequisites Warning - Show if inputs or parameters are missing */}
            {prerequisitesValidation && !prerequisitesValidation.fulfilled && (() => {
              const hasMissingInputs = prerequisitesValidation.analysis.missingInputs.length > 0;
              const hasMissingParams = prerequisitesValidation.analysis.missingParameters.length > 0;
              const isParameterOnly = !hasMissingInputs && hasMissingParams;

              return (
                <Alert className={cn(
                  "mt-3",
                  isParameterOnly
                    ? "border-amber-500/50 bg-amber-50/50 dark:bg-amber-950/20"
                    : "border-red-500/50 bg-red-50/50 dark:bg-red-950/20"
                )}>
                  {isParameterOnly ? (
                    <Settings2 className="h-4 w-4 text-amber-600" />
                  ) : (
                    <AlertCircle className="h-4 w-4 text-red-600" />
                  )}
                  <AlertTitle className={cn(
                    "text-sm font-medium",
                    isParameterOnly
                      ? "text-amber-800 dark:text-amber-200"
                      : "text-red-800 dark:text-red-200"
                  )}>
                    {isParameterOnly ? 'Parameters Need Configuration' : 'Input Data Required'}
                  </AlertTitle>
                  <AlertDescription className={cn(
                    isParameterOnly
                      ? "text-amber-700 dark:text-amber-300"
                      : "text-red-700 dark:text-red-300"
                  )}>
                    <p className="text-xs mb-2">
                      {prerequisitesValidation.llmResponse || (
                        isParameterOnly
                          ? 'This workflow needs parameter configuration before it can run.'
                          : 'This workflow requires input data before it can run.'
                      )}
                    </p>

                    {/* Missing Inputs */}
                    {hasMissingInputs && (
                      <div className="mt-2">
                        <p className="text-xs font-medium mb-1">Missing Input Data:</p>
                        <ul className="text-xs list-disc list-inside space-y-1">
                          {prerequisitesValidation.analysis.missingInputs.map((input, i) => (
                            <li key={i}>
                              <span className="font-medium">{input.inputName}</span>
                              {input.description && <span className="text-muted-foreground"> - {input.description}</span>}
                              {input.expectedFormats && input.expectedFormats.length > 0 && (
                                <span className="text-muted-foreground"> (formats: {input.expectedFormats.join(', ')})</span>
                              )}
                            </li>
                          ))}
                        </ul>
                      </div>
                    )}

                    {/* Missing Parameters */}
                    {hasMissingParams && (
                      <div className="mt-2">
                        <p className="text-xs font-medium mb-1">Parameters to Configure:</p>
                        <ul className="text-xs list-disc list-inside space-y-1">
                          {prerequisitesValidation.analysis.missingParameters.map((param, i) => (
                            <li key={i}>
                              <span className="font-medium">{param.parameterName}</span>
                              {param.description && <span className="text-muted-foreground"> - {param.description}</span>}
                            </li>
                          ))}
                        </ul>
                      </div>
                    )}

                    {/* Available Dataset Mappings */}
                    {prerequisitesValidation.analysis.inputMappings.length > 0 && (
                      <div className="mt-2">
                        <p className="text-xs font-medium mb-1 text-green-700">Available Data:</p>
                        <ul className="text-xs list-disc list-inside space-y-1">
                          {prerequisitesValidation.analysis.inputMappings.map((mapping, i) => (
                            <li key={i} className="text-green-700">
                              {mapping.datasetName} → {mapping.inputName}
                              <span className="text-muted-foreground"> ({mapping.compatibility})</span>
                            </li>
                          ))}
                        </ul>
                      </div>
                    )}

                    <p className="text-xs mt-2 italic">
                      {isParameterOnly
                        ? 'Click on workflow steps to configure parameters, or ask me to help set them up.'
                        : 'Please upload your data files to Galaxy or ask me to help you prepare test data.'
                      }
                    </p>
                  </AlertDescription>
                </Alert>
              );
            })()}

            {isFailed && (
              <Alert className="mt-3 border-red-500/40 bg-red-50/40 dark:bg-red-950/20">
                <AlertCircle className="h-4 w-4 text-red-600" />
                <AlertTitle className="text-sm font-medium text-red-800 dark:text-red-200">
                  Workflow failed
                </AlertTitle>
                <AlertDescription className="text-xs text-red-700 dark:text-red-300">
                  <p>
                    You can run AutoFix to analyze logs and suggest corrective actions.
                  </p>
                  <div className="mt-2 flex items-center gap-2">
                    <Button
                      size="sm"
                      variant="outline"
                      className="h-7"
                      onClick={handleAutofix}
                      disabled={!canTriggerAutofix || isAutofixRunning}
                    >
                      {isAutofixRunning ? (
                        <>
                          <Loader2 className="h-3 w-3 mr-1 animate-spin" />
                          Running AutoFix
                        </>
                      ) : (
                        <>
                          <Sparkles className="h-3 w-3 mr-1" />
                          Run AutoFix
                        </>
                      )}
                    </Button>
                    <Button
                      size="sm"
                      variant="ghost"
                      className="h-7"
                      onClick={handleFetchAutofixSessions}
                      disabled={!autofixWorkflowId || !autofixInvocationId || isAutofixSessionsLoading}
                    >
                      {isAutofixSessionsLoading ? (
                        <>
                          <Loader2 className="h-3 w-3 mr-1 animate-spin" />
                          Loading history
                        </>
                      ) : (
                        <>
                          <History className="h-3 w-3 mr-1" />
                          View AutoFix history
                        </>
                      )}
                    </Button>
                  </div>
                  {autofixError && (
                    <p className="mt-2 text-xs text-red-700">
                      AutoFix error: {autofixError}
                    </p>
                  )}
                  {autofixStatus && (
                    <div className="mt-2 text-xs text-muted-foreground">
                      <p>Session: {autofixStatus.session_id || 'unknown'}</p>
                      <p>Result: {autofixStatus.termination_reason || 'unknown'}</p>
                      <p>Attempts: {autofixStatus.total_attempts ?? 'n/a'}</p>
                    </div>
                  )}
                  {autofixSessions.length > 0 && (
                    <div className="mt-2 text-xs text-muted-foreground">
                      <p className="font-medium text-red-700 dark:text-red-300">Recent AutoFix sessions:</p>
                      <ul className="mt-1 space-y-1">
                      {autofixSessions.map((session: any, idx: number) => (
                        <li key={session.session_id || `session-${idx}`}>
                          {session.session_id || 'unknown'} · {session.termination_reason || 'unknown'} · attempts {session.total_attempts ?? 'n/a'}
                        </li>
                      ))}
                      </ul>
                    </div>
                  )}
                </AlertDescription>
              </Alert>
            )}

            {workflow.annotation && (
              <p className="text-sm text-muted-foreground mt-2">
                {workflow.annotation}
              </p>
            )}

            {/* US-7.2 — SSE reconnection banner */}
            {invocationId && isRunning && sseStatus !== "connected" && (
              <Alert className="mt-2 py-2 border-yellow-500/40 bg-yellow-50/30 dark:bg-yellow-950/10">
                <Loader2
                  className={cn(
                    "h-3 w-3 text-yellow-600",
                    sseStatus === "reconnecting" && "animate-spin"
                  )}
                />
                <AlertDescription className="text-xs text-yellow-700 dark:text-yellow-300">
                  {sseStatus === "reconnecting" ? (
                    "Live updates paused — reconnecting..."
                  ) : (
                    <>
                      Live updates unavailable.{" "}
                      <button
                        className="underline"
                        onClick={() => {
                          reconnectAttemptsRef.current = 0
                          setSseRetryKey((k) => k + 1)
                        }}
                      >
                        Retry
                      </button>
                    </>
                  )}
                </AlertDescription>
              </Alert>
            )}

            {/* Prominent Pilot Run Suggestion Banner */}
            {showPilotBanner && (
              <Alert className="mt-3 border-amber-500/50 bg-amber-50/50 dark:bg-amber-950/20">
                <FlaskConical className="h-4 w-4 text-amber-600" />
                <AlertTitle className="text-amber-800 dark:text-amber-200 text-sm font-medium">
                  Pilot Run Recommended
                </AlertTitle>
                <AlertDescription className="text-amber-700 dark:text-amber-300">
                  <p className="text-xs mb-2">
                    {pilotMessage || 'We suggest running a pilot test before full execution.'}
                  </p>
                  {pilotReasons.length > 0 && (
                    <ul className="text-xs space-y-1 mb-3">
                      {pilotReasons.map((reason, idx) => (
                        <li key={idx} className="flex items-start gap-1">
                          <AlertTriangle className="h-3 w-3 mt-0.5 flex-shrink-0" />
                          <span>{reason}</span>
                        </li>
                      ))}
                    </ul>
                  )}
                  <div className="flex items-center gap-2">
                    <Button
                      size="sm"
                      variant="default"
                      className="h-7 bg-amber-600 hover:bg-amber-700 text-white"
                      onClick={() => useUnifiedExecution ? setShowUnifiedExecution(true) : setShowPilotRun(true)}
                    >
                      <FlaskConical className="h-3 w-3 mr-1" />
                      {useUnifiedExecution ? 'Configure Execution' : 'Configure Pilot Run'}
                    </Button>
                    <Button
                      size="sm"
                      variant="ghost"
                      className="h-7 text-xs text-amber-700 hover:text-amber-800"
                      onClick={() => {
                        try {
                          localStorage.setItem(pilotSuppressKey, String(Date.now() + 7 * 24 * 60 * 60 * 1000))
                        } catch {}
                        setPilotBannerDismissed(true)
                      }}
                    >
                      {useUnifiedExecution ? 'Skip' : 'Skip pilot'}
                    </Button>
                  </div>
                  {/* US-1.1 — consequence note for skip; US-4.1 — 7-day suppression note */}
                  <p className="text-xs text-amber-600/70 mt-1">
                    Full dataset will run immediately — no quality check first.
                    This workflow won&apos;t ask for a pilot again for 7 days.
                  </p>
                </AlertDescription>
              </Alert>
            )}

            {/* Validation Issues Warning */}
            {validationIssues.length > 0 && (
              <Alert variant="destructive" className="mt-3">
                <AlertCircle className="h-4 w-4" />
                <AlertTitle className="text-sm font-medium">Validation Issues</AlertTitle>
                <AlertDescription>
                  <ul className="text-xs space-y-1 mt-1">
                    {validationIssues.slice(0, 3).map((issue, idx) => (
                      <li key={idx}>{issue}</li>
                    ))}
                    {validationIssues.length > 3 && (
                      <li className="text-muted-foreground">+{validationIssues.length - 3} more issues</li>
                    )}
                  </ul>
                </AlertDescription>
              </Alert>
            )}

            {/* Validation Warnings */}
            {validationWarnings.length > 0 && validationIssues.length === 0 && (
              <Alert className="mt-3 border-yellow-500/50 bg-yellow-50/50 dark:bg-yellow-950/20">
                <Info className="h-4 w-4 text-yellow-600" />
                <AlertTitle className="text-yellow-800 dark:text-yellow-200 text-sm font-medium">Warnings</AlertTitle>
                <AlertDescription className="text-yellow-700 dark:text-yellow-300">
                  <ul className="text-xs space-y-1 mt-1">
                    {validationWarnings.slice(0, 3).map((warning, idx) => (
                      <li key={idx}>{warning}</li>
                    ))}
                    {validationWarnings.length > 3 && (
                      <li className="text-muted-foreground">+{validationWarnings.length - 3} more warnings</li>
                    )}
                  </ul>
                </AlertDescription>
              </Alert>
            )}
          </CardHeader>

          {/* Expandable content - Step list */}
          <CollapsibleContent>
            <CardContent className="p-4 pt-0">
              <Separator className="my-3" />
              {/* US-1.2 — Phase 0 / Phase 1 visual grouping */}
              {pilotRunSuggested && (
                <div className="flex items-center gap-2 mb-2">
                  <span className={cn(
                    "text-xs font-semibold px-2 py-0.5 rounded-full",
                    isRunning
                      ? "bg-blue-100 text-blue-700 dark:bg-blue-900/40 dark:text-blue-300"
                      : isCompleted
                        ? "bg-green-100 text-green-700 dark:bg-green-900/40 dark:text-green-300"
                        : "bg-amber-100 text-amber-700 dark:bg-amber-900/40 dark:text-amber-300"
                  )}>
                    Phase 0 · Pilot
                  </span>
                  <span className="text-xs text-muted-foreground">
                    {isRunning ? "Running on sample subset…" : isCompleted ? "Complete" : "Ready to run"}
                  </span>
                </div>
              )}

              <div className="space-y-2">
                {normalizedSteps.map((step, idx) => (
                  <div
                    key={step.id}
                    className={cn(
                      "rounded-lg border bg-background p-3 transition-colors",
                      step.status === 'running' && "border-blue-500/50 bg-blue-50/50 dark:bg-blue-950/20",
                      step.status === 'completed' && "border-green-500/30",
                      step.status === 'error' && "border-red-500/50"
                    )}
                  >
                    <div className="flex items-center justify-between">
                      <div className="flex items-center gap-3">
                        <span className="flex items-center justify-center w-6 h-6 rounded-full bg-muted text-xs font-medium">
                          {idx + 1}
                        </span>
                        {getStepIcon(step.status)}
                        <div>
                          <p className="font-medium text-sm">
                            {step.name || step.title || getSimpleToolName(step.tool_id || '') || `Step ${idx + 1}`}
                          </p>
                          {step.tool_id && (
                            <p className="text-xs text-muted-foreground font-mono">
                              {step.tool_id}
                            </p>
                          )}
                        </div>
                      </div>

                      <div className="flex items-center gap-1">
                        {step.status === 'completed' && step.outputs && step.outputs.length > 0 && (
                          <Button variant="ghost" size="sm" className="h-7 px-2">
                            <FileOutput className="h-3 w-3" />
                          </Button>
                        )}
                        <Button
                          variant="ghost"
                          size="sm"
                          className="h-7 px-2"
                          onClick={() => setEditingStep(step)}
                          disabled={isRunning}
                        >
                          <Settings2 className="h-3 w-3" />
                        </Button>
                        <Button
                          variant="ghost"
                          size="sm"
                          className="h-7 px-2"
                          onClick={() => toggleStepExpanded(step.id)}
                        >
                          {expandedSteps.has(step.id) ? (
                            <ChevronDown className="h-3 w-3" />
                          ) : (
                            <ChevronRight className="h-3 w-3" />
                          )}
                        </Button>
                      </div>
                    </div>

                    {/* Expanded step details */}
                    {expandedSteps.has(step.id) && (
                      <div className="mt-3 pl-9 space-y-2 text-sm">
                        {step.parameters && Object.keys(step.parameters).length > 0 && (
                          <div>
                            <p className="text-xs font-medium text-muted-foreground mb-1">Parameters</p>
                            <div className="bg-muted/50 rounded p-2 font-mono text-xs space-y-1">
                              {Object.entries(step.parameters).slice(0, 5).map(([key, value]) => (
                                <div key={key} className="flex gap-2">
                                  <span className="text-muted-foreground">{key}:</span>
                                  <span className="truncate">{String(value)}</span>
                                </div>
                              ))}
                              {Object.keys(step.parameters).length > 5 && (
                                <p className="text-muted-foreground">
                                  +{Object.keys(step.parameters).length - 5} more
                                </p>
                              )}
                            </div>
                          </div>
                        )}
                        {step.inputs && step.inputs.length > 0 && (
                          <div>
                            <p className="text-xs font-medium text-muted-foreground mb-1">Inputs</p>
                            <div className="text-xs text-muted-foreground">
                              {step.inputs.map((input: any, i: number) => (
                                <span key={i}>
                                  {input.name || input.label || `Input ${i + 1}`}
                                  {i < step.inputs!.length - 1 && ', '}
                                </span>
                              ))}
                            </div>
                          </div>
                        )}
                      </div>
                    )}

                    {/* US-2.6 — per-step QC annotation */}
                    {stepQCAnnotations[step.id] && (
                      <Collapsible className="mt-1">
                        <CollapsibleTrigger className="flex items-center gap-1 text-xs text-amber-600 ml-9 hover:underline cursor-pointer">
                          <AlertTriangle className="h-3 w-3" />
                          Last run: QC {stepQCAnnotations[step.id].severity === "warning" ? "warning" : "failed"}
                        </CollapsibleTrigger>
                        <CollapsibleContent className="ml-9 mt-1 space-y-0.5">
                          {stepQCAnnotations[step.id].failures.map((f: any, i: number) => (
                            <p key={i} className="text-xs text-muted-foreground">
                              {typeof f === "string" ? f : f.message}
                            </p>
                          ))}
                        </CollapsibleContent>
                      </Collapsible>
                    )}
                  </div>
                ))}
              </div>

              {/* US-1.2 — Phase 1 locked indicator */}
              {pilotRunSuggested && !isCompleted && (
                <div className="mt-3 rounded-lg border border-dashed border-muted-foreground/30 p-3 flex items-center gap-3">
                  <Lock className="h-4 w-4 text-muted-foreground/50 flex-shrink-0" />
                  <div>
                    <p className="text-xs font-medium text-muted-foreground">Phase 1 · Full Dataset</p>
                    <p className="text-xs text-muted-foreground/70">
                      Full dataset run starts after pilot QC passes
                    </p>
                  </div>
                </div>
              )}

              {/* Completion Actions Panel - P1, P2, P3 */}
              {isCompleted && !isRunning && (
                <>
                  <Separator className="my-4" />
                  <div className="space-y-3">
                    <h4 className="text-sm font-medium flex items-center gap-2">
                      <CheckCircle2 className="h-4 w-4 text-green-500" />
                      Workflow Completed
                    </h4>

                    {/* US-6.2 — QC Summary (shows when events exist) */}
                    {qcReport && (qcReport.gates_triggered > 0 || qcReport.warnings_emitted > 0) && (
                      <div className="border rounded-md text-xs">
                        <button
                          className="w-full flex items-center justify-between px-3 py-2 text-left hover:bg-muted/40 transition-colors"
                          onClick={() => setShowQCSummary(v => !v)}
                        >
                          <span className="flex items-center gap-2 font-medium">
                            <AlertTriangle className="h-3.5 w-3.5 text-amber-500" />
                            QC Summary
                            {qcReport.active_profile && (
                              <span className="text-xs font-normal text-muted-foreground">
                                · profile: {qcReport.active_profile.replace(/_/g, " ")}
                              </span>
                            )}
                          </span>
                          <span className="text-muted-foreground flex gap-3">
                            {qcReport.gates_triggered > 0 && (
                              <span className="text-red-600">{qcReport.gates_triggered} gate{qcReport.gates_triggered !== 1 ? "s" : ""}</span>
                            )}
                            {qcReport.warnings_emitted > 0 && (
                              <span className="text-amber-600">{qcReport.warnings_emitted} warning{qcReport.warnings_emitted !== 1 ? "s" : ""}</span>
                            )}
                            <ChevronDown className={cn("h-3.5 w-3.5 transition-transform", showQCSummary && "rotate-180")} />
                          </span>
                        </button>
                        {showQCSummary && (
                          <div className="border-t px-3 py-2 space-y-2">
                            {qcReport.events.map((ev: any, i: number) => (
                              <div key={i} className={cn(
                                "rounded px-2 py-1.5 space-y-0.5",
                                ev.type === "gate" ? "bg-red-50/60 dark:bg-red-950/20" : "bg-amber-50/60 dark:bg-amber-950/20"
                              )}>
                                <p className="font-medium capitalize">
                                  {ev.type === "gate" ? "🔴" : "⚠️"}{" "}
                                  {(ev.process_name || "").replace(/_/g, " ").toLowerCase().replace(/\b\w/g, (c: string) => c.toUpperCase())}
                                </p>
                                {(ev.failures || ev.warnings || []).map((f: any, j: number) => (
                                  <p key={j} className="text-muted-foreground pl-2">
                                    {typeof f === "string" ? f : f.message || `${f.metric}: ${f.value}`}
                                  </p>
                                ))}
                              </div>
                            ))}
                            <div className="pt-1 border-t">
                              <p className="text-muted-foreground italic leading-snug">{qcReport.methods_text}</p>
                              <button
                                className="mt-1 text-primary hover:underline"
                                onClick={() => navigator.clipboard?.writeText(qcReport.methods_text)}
                              >
                                Copy methods text
                              </button>
                            </div>
                          </div>
                        )}
                      </div>
                    )}

                    {/* Output summary */}
                    {outputs.length > 0 && (
                      <div className="text-xs text-muted-foreground">
                        {outputs.length} output file{outputs.length !== 1 ? 's' : ''} generated
                      </div>
                    )}

                    {/* Action buttons grid */}
                    <div className="grid grid-cols-2 sm:grid-cols-4 gap-2">
                      {/* P1: Generate Report */}
                      <Button
                        variant="outline"
                        size="sm"
                        className="h-auto py-2 flex-col gap-1"
                        onClick={() => setShowReportViewer(true)}
                        disabled={!invocationId}
                      >
                        <FileText className="h-4 w-4" />
                        <span className="text-xs">Report</span>
                      </Button>

                      {/* P2: Open in Jupyter */}
                      <Button
                        variant="outline"
                        size="sm"
                        className="h-auto py-2 flex-col gap-1"
                        onClick={() => setShowInteractiveLauncher(true)}
                      >
                        <Laptop className="h-4 w-4" />
                        <span className="text-xs">Jupyter</span>
                      </Button>

                      {/* P3: Extract Subworkflow */}
                      <Button
                        variant="outline"
                        size="sm"
                        className="h-auto py-2 flex-col gap-1"
                        onClick={() => setShowSubworkflowExtractor(true)}
                        disabled={!galaxyWorkflowId}
                      >
                        <Scissors className="h-4 w-4" />
                        <span className="text-xs">Extract</span>
                      </Button>

                      {/* Download outputs */}
                      <Button
                        variant="outline"
                        size="sm"
                        className="h-auto py-2 flex-col gap-1"
                        onClick={() => {
                          if (!invocationId || outputs.length === 0) return
                          window.open(`/api/invocations/${invocationId}/download-all`, "_blank")
                        }}
                        disabled={!invocationId || outputs.length === 0}
                      >
                        <Download className="h-4 w-4" />
                        <span className="text-xs">Download</span>
                      </Button>
                    </div>
                  </div>
                </>
              )}
            </CardContent>
          </CollapsibleContent>
        </Collapsible>
      </Card>

      {/* Parameter Dialog */}
      {editingStep && (
        <ParameterDialog
          open={!!editingStep}
          onOpenChange={(open) => !open && setEditingStep(null)}
          step={{
            id: editingStep.id,
            title: editingStep.name || editingStep.title || 'Step',
            description: editingStep.description || '',
            status: 'pending',
            tool: editingStep.tool_id || '',
            parameters: editingStep.parameters || {},
            complexity: 'simple',
          }}
          onSave={(stepId, params) => handleSaveParameters(params)}
        />
      )}

      {/* Citation Panel */}
      {showCitations && (citations.length > 0 || methodsSection || workflow) && (
        <div className="mt-3">
          <CitationPanel
            citations={citations}
            methodsSection={methodsSection}
            workflow={workflow}
            isCollapsed={false}
            onExportBibTeX={() => {
              console.log('Exporting BibTeX...')
            }}
          />
        </div>
      )}

      {/* Pilot Run Panel (Legacy) */}
      {showPilotRun && !useUnifiedExecution && (
        <div className="mt-3">
          <PilotRunPanel
            workflowId={workflow.name || 'workflow'}
            totalSamples={totalSamples || 10}
            initialConfig={tuningConfig}
            onStartPilot={onStartPilotRun}
            onProceedToFull={onProceedToFullRun}
            onClose={() => setShowPilotRun(false)}
            parameterRecommendations={parameterRecommendations}
          />
        </div>
      )}

      {/* Unified Execution Control Panel (New) */}
      {(showUnifiedExecution || currentExecutionRun) && useUnifiedExecution && (
        <div className="mt-3">
          <ExecutionControlPanel
            workflowName={workflow.name || 'Workflow'}
            totalSamples={totalSamples || 10}
            totalSteps={normalizedSteps.length}
            strataColumns={strataColumns}
            currentRun={currentExecutionRun}
            previousRuns={previousExecutionRuns}
            recommendations={parameterRecommendations}
            onExecute={async (config) => {
              // US-4.2 — capture auto-apply preference from execution config
              pauseAtQcRef.current = config.pauseAtQcFailures !== false
              if (onUnifiedExecute) {
                await onUnifiedExecute(config)
              }
            }}
            onPause={onPauseExecution}
            onResume={onResumeExecution}
            onCancel={onCancelExecution}
            onEditParameters={() => {
              // Open parameter dialog for first step with params
              const stepWithParams = normalizedSteps.find(s => s.parameters && Object.keys(s.parameters).length > 0)
              if (stepWithParams) {
                setEditingStep(stepWithParams)
              }
            }}
            onApplyRecommendation={(paramKey, value) => {
              // Apply recommendation - parse paramKey as toolId.paramName
              const [stepId, paramName] = paramKey.split('.')
              if (onParameterChange && stepId && paramName) {
                const step = normalizedSteps.find(s => s.id === stepId || s.tool_id === stepId)
                if (step) {
                  onParameterChange(step.id, { ...step.parameters, [paramName]: value })
                }
              }
            }}
            onPromote={onPromoteToProduction}
            isLoading={isRunning}
            compact={false}
          />
        </div>
      )}

      {/* P1: Workflow Report Viewer */}
      {invocationId && (
        <WorkflowReportViewer
          open={showReportViewer}
          onOpenChange={setShowReportViewer}
          invocationId={invocationId}
          workflowName={workflow.name}
        />
      )}

      {/* P2: Interactive Tool Launcher */}
      <InteractiveLauncher
        open={showInteractiveLauncher}
        onOpenChange={setShowInteractiveLauncher}
        outputs={outputs}
        historyId={galaxyHistoryId}
      />

      {/* P3: Subworkflow Extractor */}
      {galaxyWorkflowId && (
        <SubworkflowExtractor
          open={showSubworkflowExtractor}
          onOpenChange={setShowSubworkflowExtractor}
          workflowId={galaxyWorkflowId}
          workflowName={workflow.name}
          steps={normalizedSteps}
        />
      )}

      {/* QC Gate Modal (Gap 3) */}
      {showQCGateModal && qcGateData && (
        <QCGateModal
          open={showQCGateModal}
          onOpenChange={setShowQCGateModal}
          processName={qcGateData.processName}
          metrics={Object.entries(qcGateData.qcMetrics || {}).map(([name, value]) => {
            // Use structured failure object when available (exact metric match),
            // fall back to plain-string scan only if backend sent legacy format.
            const structuredFailure = qcGateData.failures.find(
              (f): f is { metric: string; value: number; threshold: number; operator: string; message: string } =>
                typeof f === 'object' && (f as any).metric === name
            )
            const passed = !structuredFailure &&
              !qcGateData.failures.some(f =>
                typeof f === 'string' && f.toLowerCase().includes(name.replace(/_/g, ' ').toLowerCase())
              )
            const threshold = structuredFailure?.threshold ?? 0

            return {
              name: name.replace(/_/g, ' ').replace(/\b\w/g, (l: string) => l.toUpperCase()),
              value: typeof value === 'number' ? value : 0,
              threshold,
              passed,
              unit: name.includes('angstrom') ? 'Å' : undefined
            }
          })}
          failures={qcGateData.failures.map(f => typeof f === 'string' ? f : f.message)}
          suggestions={qcGateData.suggestions}
          onRetryWithSuggested={handleRetryWithSuggestions}
          onProceedAnyway={handleProceedAnyway}
          onCancel={handleCancelWorkflow}
          isApplying={isApplyingSuggestions}
          retryCount={(qcRetryCount[qcGateData.processName] ?? 1) - 1}
          previousMetrics={qcPreviousMetrics[qcGateData.processName]}
          qcMetrics={qcGateData.qcMetrics}
        />
      )}
    </>
  )
}
