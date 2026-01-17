import { useState, useEffect } from "react"
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
  Download
} from "lucide-react"
import { cn, getSimpleToolName } from "@/lib/utils"
import { ParameterDialog } from "./parameter-dialog"
import { CitationPanel } from "./citation-panel"
import { PilotRunPanel } from "./pilot-run-panel"
import { ExecutionControlPanel } from "./execution-control-panel"
import { WorkflowReportViewer } from "./workflow-report-viewer"
import { InteractiveLauncher } from "./interactive-launcher"
import { SubworkflowExtractor } from "./subworkflow-extractor"
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
  strataColumns = []
}: WorkflowArtifactProps) {
  const [isExpanded, setIsExpanded] = useState(true)
  const [expandedSteps, setExpandedSteps] = useState<Set<string>>(new Set())
  const [editingStep, setEditingStep] = useState<WorkflowStep | null>(null)
  const [showCitations, setShowCitations] = useState(false)
  const [showPilotRun, setShowPilotRun] = useState(false)
  const [showUnifiedExecution, setShowUnifiedExecution] = useState(false)
  const [pilotBannerDismissed, setPilotBannerDismissed] = useState(false)
  // P1-P3: New dialog states
  const [showReportViewer, setShowReportViewer] = useState(false)
  const [showInteractiveLauncher, setShowInteractiveLauncher] = useState(false)
  const [showSubworkflowExtractor, setShowSubworkflowExtractor] = useState(false)

  // Determine if we should show the pilot suggestion banner prominently
  const showPilotBanner = pilotRunSuggested && !pilotBannerDismissed && !isRunning && pilotReasons.length > 0

  const citationsCount = citations.filter(c => c.doi || c.pmid || c.title).length

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

  const handleSaveParameters = (params: Record<string, any>) => {
    if (editingStep && onParameterChange) {
      onParameterChange(editingStep.id, params)
    }
    setEditingStep(null)
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
                {confidence > 0 && (
                  <Badge
                    variant={confidence > 0.8 ? "default" : confidence > 0.6 ? "secondary" : "outline"}
                    className="text-xs"
                  >
                    {(confidence * 100).toFixed(0)}% confidence
                  </Badge>
                )}

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
                  <Button size="sm" onClick={() => onRun?.(workflow, normalizedSteps)} className="bg-green-600 hover:bg-green-700">
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

            {workflow.annotation && (
              <p className="text-sm text-muted-foreground mt-2">
                {workflow.annotation}
              </p>
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
                      onClick={() => setPilotBannerDismissed(true)}
                    >
                      {useUnifiedExecution ? 'Skip' : 'Skip pilot'}
                    </Button>
                  </div>
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
                            {step.name || step.title || getSimpleToolName(step.tool_id) || `Step ${idx + 1}`}
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
                  </div>
                ))}
              </div>

              {/* Completion Actions Panel - P1, P2, P3 */}
              {isCompleted && !isRunning && (
                <>
                  <Separator className="my-4" />
                  <div className="space-y-3">
                    <h4 className="text-sm font-medium flex items-center gap-2">
                      <CheckCircle2 className="h-4 w-4 text-green-500" />
                      Workflow Completed
                    </h4>

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
                        disabled={outputs.length === 0}
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
            tool: editingStep.tool_id || '',
            parameters: editingStep.parameters || {}
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
    </>
  )
}
