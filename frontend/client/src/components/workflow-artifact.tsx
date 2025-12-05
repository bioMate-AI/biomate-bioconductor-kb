import { useState, useEffect } from "react"
import { Card, CardContent, CardHeader } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible"
import { Progress } from "@/components/ui/progress"
import { Separator } from "@/components/ui/separator"
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
  FileOutput
} from "lucide-react"
import { cn, getSimpleToolName } from "@/lib/utils"
import { ParameterDialog } from "./parameter-dialog"

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

interface WorkflowArtifactProps {
  workflow: {
    name?: string
    annotation?: string
    steps?: any
  }
  steps: WorkflowStep[]
  confidence?: number
  onRun?: () => void
  onStop?: () => void
  onParameterChange?: (stepId: string, params: Record<string, any>) => void
  isRunning?: boolean
  progress?: number
  className?: string
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
  className
}: WorkflowArtifactProps) {
  const [isExpanded, setIsExpanded] = useState(true)
  const [expandedSteps, setExpandedSteps] = useState<Set<string>>(new Set())
  const [editingStep, setEditingStep] = useState<WorkflowStep | null>(null)

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

                {isRunning ? (
                  <Button size="sm" variant="destructive" onClick={onStop}>
                    <Square className="h-3 w-3 mr-1" />
                    Stop
                  </Button>
                ) : (
                  <Button size="sm" onClick={onRun} className="bg-green-600 hover:bg-green-700">
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
    </>
  )
}
