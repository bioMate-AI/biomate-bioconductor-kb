import { useState, useMemo, useEffect } from "react"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { WorkflowGraph } from "./workflow-graph"
import { ParameterDialog } from "./parameter-dialog"
import { ExecutionTimeline } from "./execution-timeline"
import { JobLogViewer } from "./job-log-viewer"
import { SaveWorkflowDialog } from "./save-workflow-dialog"
import { DatasetValidationDialog, type ValidationResult } from "./dataset-validation-dialog"
import { useWorkflowExecution } from "../hooks/useWorkflowExecution"
import { type WorkflowStep as WorkflowStepType } from "./workflow-step"
import {
  Plus,
  Play,
  Pause,
  Square,
  RotateCcw,
  Save,
  Download,
  MessageCircle,
  SkipForward
} from "lucide-react"

//todo: remove mock functionality
const mockWorkflowSteps: WorkflowStepType[] = [
  {
    id: "step1",
    title: "Quality Control",
    description: "Assess the quality of raw sequencing reads and generate quality reports using FastQC",
    status: "completed",
    tool: "FastQC",
    parameters: {
      "Input format": "FASTQ",
      "Quality threshold": 20,
      "Adapter trimming": "Auto-detect"
    },
    complexity: "simple",
    estimatedTime: "3 min"
  },
  {
    id: "step2", 
    title: "Read Alignment",
    description: "Align quality-controlled reads to the reference genome using HISAT2",
    status: "running",
    tool: "HISAT2",
    parameters: {
      "Reference genome": "hg38",
      "Splice-aware": true,
      "Max intron length": 500000
    },
    complexity: "intermediate",
    estimatedTime: "15 min"
  },
  {
    id: "step3",
    title: "Gene Expression Quantification", 
    description: "Count reads mapping to genes and calculate expression levels using featureCounts",
    status: "pending",
    tool: "featureCounts",
    parameters: {
      "Annotation": "GENCODE v40",
      "Feature type": "exon",
      "Strand specificity": "unstranded"
    },
    complexity: "complex",
    estimatedTime: "8 min"
  },
  {
    id: "step4",
    title: "Differential Expression Analysis",
    description: "Identify genes with significant expression changes between conditions",
    status: "pending", 
    tool: "DESeq2",
    parameters: {
      "Contrast": "treatment vs control",
      "P-value threshold": 0.05,
      "Log2 fold change": 1.5
    },
    complexity: "complex",
    estimatedTime: "12 min"
  },
  {
    id: "step5",
    title: "Gene Ontology Enrichment",
    description: "Perform GO term enrichment analysis on differentially expressed genes",
    status: "pending",
    tool: "topGO",
    parameters: {
      "Organism": "Homo sapiens",
      "P-value cutoff": 0.01,
      "Ontology": "biological_process"
    },
    complexity: "intermediate",
    estimatedTime: "5 min"
  },
  {
    id: "step6",
    title: "Generate Report",
    description: "Create a comprehensive analysis report with visualizations and statistics",
    status: "pending",
    tool: "MultiQC",
    parameters: {
      "Report format": "HTML",
      "Include plots": true,
      "Custom config": "default"
    },
    complexity: "simple",
    estimatedTime: "2 min"
  }
]

type WorkflowStatus = 'idle' | 'running' | 'paused' | 'completed' | 'error'
type ExecutionMode = 'sequential' | 'step-by-step'

interface EnhancedWorkflowBuilderProps {
  workflowSteps?: WorkflowStepType[]
  onGetHelp?: () => void
  workflowName?: string
}

export function EnhancedWorkflowBuilder({
  workflowSteps = mockWorkflowSteps, //todo: remove mock functionality
  onGetHelp = () => console.log('Get help triggered'),
  workflowName = "RNA-seq Analysis Pipeline" //todo: remove mock functionality
}: EnhancedWorkflowBuilderProps) {
  const [steps, setSteps] = useState(workflowSteps)
  const [workflowStatus, setWorkflowStatus] = useState<WorkflowStatus>('idle')
  const [executionMode, setExecutionMode] = useState<ExecutionMode>('sequential')
  const [editingStep, setEditingStep] = useState<WorkflowStepType | null>(null)
  const [selectedStepForLogs, setSelectedStepForLogs] = useState<string | null>(null)
  const [showSaveDialog, setShowSaveDialog] = useState(false)
  const [validationResult, setValidationResult] = useState<ValidationResult | null>(null)
  const [showValidationDialog, setShowValidationDialog] = useState(false)
  const [pendingWorkflowStart, setPendingWorkflowStart] = useState(false)
  const [bioMateInvocationId, setBioMateInvocationId] = useState<string | null>(null)
  const [galaxyWorkflowId, setGalaxyWorkflowId] = useState<string | null>(null)
  const [galaxyWorkflowName, setGalaxyWorkflowName] = useState<string>(workflowName)

  // Real-time workflow execution hook
  const {
    invocationId,
    workflowState,
    steps: executionSteps,
    error: executionError,
    isConnected,
    isComplete,
    invokeWorkflow,
    cancelWorkflow,
    getTotalElapsedTime,
    formatElapsedTime,
  } = useWorkflowExecution()

  // Sync props to local state when workflow changes
  useEffect(() => {
    console.log('[EnhancedWorkflowBuilder] Props changed:', {
      propsStepsCount: workflowSteps?.length,
      localStepsCount: steps.length,
      propsWorkflowName: workflowName,
      localWorkflowName: galaxyWorkflowName
    });

    // Update local state when props change
    if (workflowSteps && workflowSteps.length > 0) {
      console.log('[EnhancedWorkflowBuilder] Updating local state with new workflow steps');
      setSteps(workflowSteps);
    }

    if (workflowName) {
      console.log('[EnhancedWorkflowBuilder] Updating local state with new workflow name:', workflowName);
      setGalaxyWorkflowName(workflowName);
    }
  }, [workflowSteps, workflowName, galaxyWorkflowName, steps.length]);

  // Handle workflow completion and fetch outputs
  useEffect(() => {
    const handleWorkflowCompletion = async () => {
      if (isComplete && bioMateInvocationId) {
        console.log('[Workflow] Workflow completed, fetching outputs for invocation:', bioMateInvocationId)

        try {
          // Update invocation status to completed
          await fetch(`/api/invocations/${bioMateInvocationId}`, {
            method: 'PATCH',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
              status: 'ok',
              completedSteps: steps.length,
              completedAt: new Date().toISOString()
            })
          })

          // Fetch outputs from Galaxy
          const fetchResponse = await fetch(`/api/invocations/${bioMateInvocationId}/fetch-outputs`, {
            method: 'POST'
          })

          if (fetchResponse.ok) {
            const outputs = await fetchResponse.json()
            console.log('[Workflow] Fetched', outputs.count, 'outputs')

            // TODO: Notify parent component or add chat message with invocationId
            setWorkflowStatus('completed')
          }
        } catch (error: any) {
          console.error('[Workflow] Failed to fetch outputs:', error)
        }
      }
    }

    handleWorkflowCompletion()
  }, [isComplete, bioMateInvocationId, steps.length])

  // Convert execution steps to timeline events
  // Use executionSteps from full workflow invocation, or fall back to local steps for individual execution
  const timelineEvents = useMemo(() => {
    if (executionSteps.size > 0) {
      // Full workflow mode: use executionSteps from SSE
      return Array.from(executionSteps.values()).map(step => {
        const workflowStep = steps.find(s => s.id === step.stepId)
        const timelineState =
          step.state === 'deleted' ? 'error' : step.state
        return {
          stepId: step.stepId,
          stepName: workflowStep?.title || step.stepId,
          state: timelineState,
          timestamp: step.updateTime,
          elapsedMs: step.elapsedMs,
          jobId: step.jobId,
        }
      })
    } else {
      // Individual step mode: use local steps state
      return steps
        .filter(s => s.status === 'running' || s.status === 'completed' || s.status === 'error')
        .map(step => ({
          stepId: step.id,
          stepName: step.title,
          state: (step.status === 'running' ? 'running' : step.status === 'completed' ? 'ok' : 'error') as 'running' | 'ok' | 'error',
          timestamp: new Date().toISOString(),
          elapsedMs: undefined,
          jobId: undefined,
        }))
    }
  }, [executionSteps, steps])

  // Get currently running step for log viewer
  const currentRunningStep = useMemo(() => {
    const runningStep = Array.from(executionSteps.values()).find(s => s.state === 'running')
    if (!runningStep) return null
    const workflowStep = steps.find(s => s.id === runningStep.stepId)
    return {
      stepId: runningStep.stepId,
      stepName: workflowStep?.title || runningStep.stepId,
      logs: runningStep.logs,
      isRunning: true,
    }
  }, [executionSteps, steps])

  // Selected step logs (for viewing completed/failed step logs)
  const selectedStepLogs = useMemo(() => {
    if (!selectedStepForLogs) return null
    const executionStep = executionSteps.get(selectedStepForLogs)
    if (!executionStep) return null
    const workflowStep = steps.find(s => s.id === selectedStepForLogs)
    return {
      stepId: executionStep.stepId,
      stepName: workflowStep?.title || executionStep.stepId,
      logs: executionStep.logs,
      isRunning: executionStep.state === 'running',
    }
  }, [selectedStepForLogs, executionSteps, steps])

  const totalSteps = steps.length
  const completedSteps = steps.filter(s => s.status === "completed").length
  const runningSteps = steps.filter(s => s.status === "running").length
  const errorSteps = steps.filter(s => s.status === "error").length
  
  const averageComplexity = steps.reduce((acc, step) => {
    const complexity = step.complexity === "simple" ? 1 : step.complexity === "intermediate" ? 2 : 3
    return acc + complexity
  }, 0) / totalSteps

  const complexityLevel = averageComplexity <= 1.5 ? "Simple" : averageComplexity <= 2.5 ? "Intermediate" : "Complex"
  const complexityColor = averageComplexity <= 1.5 ? "bg-green-500" : averageComplexity <= 2.5 ? "bg-yellow-500" : "bg-red-500"

  // Helper function to start workflow with validated inputs
  const startWorkflow = async (validation: ValidationResult) => {
    setWorkflowStatus('running')
    try {
      // First, create the workflow in Galaxy
      const workflowDefinition = {
        name: workflowName,
        annotation: `Workflow generated by bioMate AI`,
        steps: steps.reduce((acc, step, index) => {
          acc[index.toString()] = {
            id: index,
            tool_id: step.tool,
            tool_version: null,
            type: 'tool',
            annotation: step.description,
            tool_state: JSON.stringify(step.parameters || {})
          }
          return acc
        }, {} as Record<string, any>)
      }

      console.log('[Workflow] Creating workflow in Galaxy:', workflowName)
      const createResponse = await fetch('/api/galaxy/workflows', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ workflow: workflowDefinition })
      })

      if (!createResponse.ok) {
        const error = await createResponse.json()
        throw new Error(error.message || 'Failed to create workflow in Galaxy')
      }

      const createdWorkflow = await createResponse.json()
      const workflowId = createdWorkflow.id
      console.log('[Workflow] Created workflow in Galaxy with ID:', workflowId)

      // Update UI with Galaxy workflow details
      setGalaxyWorkflowId(workflowId)
      setGalaxyWorkflowName(createdWorkflow.name || workflowName)

      // Update workflow definition with actual Galaxy details
      if (createdWorkflow.steps) {
        console.log('[Workflow] Workflow has', Object.keys(createdWorkflow.steps).length, 'steps in Galaxy')
      }

      // Build workflow inputs from steps and validation mappings
      const workflowInputs: Record<string, any> = {}

      // Add dataset mappings from validation
      if (validation.mappings.length > 0) {
        validation.mappings.forEach(mapping => {
          workflowInputs[mapping.input_name] = mapping.dataset_id
        })
      }

      console.log('[Workflow] Invoking workflow:', workflowId, 'with inputs:', workflowInputs)

      // Invoke workflow in Galaxy
      const galaxyInvocation = await invokeWorkflow(workflowId, workflowInputs)
      console.log('[Workflow] Successfully invoked:', workflowId, 'Galaxy invocation:', galaxyInvocation)

      // Create invocation record in our backend for output tracking
      try {
        const invocationResponse = await fetch('/api/invocations', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            workflowName: galaxyWorkflowName,
            workflowDefinition: {
              id: workflowId,
              name: galaxyWorkflowName,
              steps: steps,
              galaxyWorkflowId: workflowId
            },
            galaxyInvocationId: galaxyInvocation.id,
            galaxyHistoryId: galaxyInvocation.history_id || '',
            totalSteps: steps.length,
            status: 'running'
          })
        })

        if (invocationResponse.ok) {
          const bioMateInvocation = await invocationResponse.json()
          console.log('[Workflow] Created bioMate invocation:', bioMateInvocation.id)

          // Store invocation ID for tracking
          setBioMateInvocationId(bioMateInvocation.id)
        }
      } catch (error: any) {
        console.error('[Workflow] Failed to create bioMate invocation:', error)
        // Don't fail workflow execution if tracking fails
      }
    } catch (error: any) {
      console.error('[Workflow] Failed to invoke:', error)
      setWorkflowStatus('error')
    }
  }

  // Handler for validation dialog confirmation
  const handleValidationConfirm = async () => {
    setShowValidationDialog(false)
    setPendingWorkflowStart(false)
    if (validationResult) {
      await startWorkflow(validationResult)
    }
  }

  // Handler for validation dialog edit
  const handleValidationEdit = () => {
    setShowValidationDialog(false)
    setPendingWorkflowStart(false)
    // TODO: Open dataset mapping editor
    console.log('[Workflow] Edit mappings requested')
  }

  const handleWorkflowAction = async (action: 'start' | 'pause' | 'resume' | 'stop' | 'restart') => {
    console.log(`Workflow ${action} triggered`)

    switch (action) {
      case 'start':
        try {
          // Call dataset validation API
          const validationResponse = await fetch('/api/datasets/validate', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
              workflow_name: galaxyWorkflowName,
              workflow_steps: steps.map(step => ({
                id: step.id,
                title: step.title,
                description: step.description,
                tool: step.tool,
                parameters: step.parameters
              }))
            })
          })

          const validation: ValidationResult = await validationResponse.json()
          setValidationResult(validation)

          // If valid and no issues, proceed automatically
          if (validation.valid && validation.issues.length === 0) {
            await startWorkflow(validation)
            return
          }

          // If there are issues, show confirmation dialog
          setShowValidationDialog(true)
          setPendingWorkflowStart(true)
        } catch (error: any) {
          console.error('[Workflow] Validation failed:', error)
          setWorkflowStatus('error')
        }
        break
      case 'pause':
        setWorkflowStatus('paused')
        // Pause all running steps (local UI state only for now)
        setSteps(prev => prev.map(s =>
          s.status === 'running' ? { ...s, status: 'pending' as const } : s
        ))
        break
      case 'resume':
        setWorkflowStatus('running')
        break
      case 'stop':
        setWorkflowStatus('idle')
        try {
          await cancelWorkflow()
          console.log('[Workflow] Cancelled successfully')
        } catch (error: any) {
          console.error('[Workflow] Failed to cancel:', error)
        }
        setSteps(prev => prev.map(s =>
          s.status === 'running' ? { ...s, status: 'pending' as const } : s
        ))
        break
      case 'restart':
        setWorkflowStatus('idle')
        setSteps(prev => prev.map(s => ({ ...s, status: 'pending' as const })))
        setSelectedStepForLogs(null)
        break
    }
  }

  const handleStepAction = async (stepId: string, action: 'run' | 'pause' | 'resume' | 'restart' | 'edit' | 'delete') => {
    console.log(`Step ${action} triggered for:`, stepId)

    switch (action) {
      case 'run':
        setSteps(prev => prev.map(s =>
          s.id === stepId ? { ...s, status: 'running' as const } : s
        ))

        // Execute step via API
        const step = steps.find(s => s.id === stepId)
        if (step) {
          try {
            const response = await fetch('/api/workflow/step/execute', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({
                step_id: stepId,
                tool_id: step.tool,
                parameters: step.parameters || {},
                inputs: {}
              })
            })

            if (!response.ok) {
              throw new Error(`Step execution failed: ${await response.text()}`)
            }

            const result = await response.json()
            console.log(`[Step] Execution started:`, result)

            // Poll for status
            const pollInterval = setInterval(async () => {
              try {
                const statusResponse = await fetch(`/api/workflow/step/${stepId}/status`)
                if (statusResponse.ok) {
                  const status = await statusResponse.json()

                  if (status.state === 'ok') {
                    clearInterval(pollInterval)
                    setSteps(prev => prev.map(s =>
                      s.id === stepId ? { ...s, status: 'completed' as const } : s
                    ))
                  } else if (status.state === 'error') {
                    clearInterval(pollInterval)
                    setSteps(prev => prev.map(s =>
                      s.id === stepId ? { ...s, status: 'error' as const } : s
                    ))
                  }
                }
              } catch (err) {
                console.error('[Step] Status check failed:', err)
              }
            }, 2000) // Poll every 2 seconds

            // Stop polling after 5 minutes
            setTimeout(() => clearInterval(pollInterval), 300000)
          } catch (error: any) {
            console.error('[Step] Execution failed:', error)
            setSteps(prev => prev.map(s =>
              s.id === stepId ? { ...s, status: 'error' as const } : s
            ))
          }
        }
        break
      case 'pause':
        setSteps(prev => prev.map(s =>
          s.id === stepId ? { ...s, status: 'pending' as const } : s
        ))
        break
      case 'restart':
        setSteps(prev => prev.map(s =>
          s.id === stepId ? { ...s, status: 'pending' as const } : s
        ))
        break
      case 'edit':
        const editStep = steps.find(s => s.id === stepId)
        if (editStep) {
          setEditingStep(editStep)
        }
        break
      case 'delete':
        setSteps(prev => prev.filter(s => s.id !== stepId))
        break
    }
  }

  const handleSaveParameters = (stepId: string, parameters: Record<string, any>) => {
    setSteps(prev => prev.map(s =>
      s.id === stepId ? { ...s, parameters } : s
    ))
  }

  const handleAddStep = () => {
    const newStep: WorkflowStepType = {
      id: `step${Date.now()}`,
      title: "New Step",
      description: "Configure this step",
      status: "pending",
      tool: "Select Tool",
      complexity: "simple",
      estimatedTime: "5 min"
    }
    setSteps(prev => [...prev, newStep])
  }

  const handleSaveWorkflow = async (template: any) => {
    try {
      console.log('[EnhancedWorkflowBuilder] Saving workflow template:', template)
      const response = await fetch('/api/workflow-templates', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(template),
      })

      if (!response.ok) {
        const error = await response.text()
        throw new Error(`Failed to save workflow: ${error}`)
      }

      const savedTemplate = await response.json()
      console.log('[EnhancedWorkflowBuilder] Workflow saved successfully:', savedTemplate)

      // Show success message (could use a toast notification here)
      alert('Workflow template saved successfully!')
    } catch (error: any) {
      console.error('[EnhancedWorkflowBuilder] Failed to save workflow:', error)
      throw error
    }
  }

  const handleExportWorkflow = () => {
    try {
      console.log('[EnhancedWorkflowBuilder] Exporting workflow as .ga format')

      // Convert workflow steps to Galaxy .ga format
      const workflowGa = {
        a_galaxy_workflow: "true",
        format_version: "0.1",
        name: galaxyWorkflowName,
        annotation: `Exported workflow: ${galaxyWorkflowName}`,
        tags: ["exported", new Date().toISOString().split('T')[0]],
        uuid: galaxyWorkflowId,
        steps: steps.reduce((acc, step, index) => {
          acc[index] = {
            id: index,
            tool_id: step.tool,
            tool_version: "latest",
            label: step.title,
            annotation: step.description,
            tool_state: step.parameters || {},
          }
          return acc
        }, {} as Record<number, any>)
      }

      // Create download
      const json = JSON.stringify(workflowGa, null, 2)
      const blob = new Blob([json], { type: 'application/json' })
      const url = URL.createObjectURL(blob)
      const link = document.createElement('a')
      link.href = url
      link.download = `${galaxyWorkflowName.replace(/\s+/g, '_')}.ga`
      document.body.appendChild(link)
      link.click()
      document.body.removeChild(link)
      URL.revokeObjectURL(url)

      console.log('[EnhancedWorkflowBuilder] Workflow exported successfully')
    } catch (error: any) {
      console.error('[EnhancedWorkflowBuilder] Failed to export workflow:', error)
      alert(`Failed to export workflow: ${error.message}`)
    }
  }

  const handlePauseJob = async (jobId: string) => {
    try {
      console.log('[EnhancedWorkflowBuilder] Pausing job:', jobId)
      const response = await fetch(`/api/galaxy/jobs/${jobId}/pause`, {
        method: 'PUT',
      })

      if (!response.ok) {
        const error = await response.json()
        throw new Error(error.message || 'Failed to pause job')
      }

      const result = await response.json()
      console.log('[EnhancedWorkflowBuilder] Job paused successfully:', result)

      // Optionally show success message
      // toast.success('Job paused successfully')
    } catch (error: any) {
      console.error('[EnhancedWorkflowBuilder] Failed to pause job:', error)
      alert(`Failed to pause job: ${error.message}`)
    }
  }

  const handleResumeJob = async (jobId: string) => {
    try {
      console.log('[EnhancedWorkflowBuilder] Resuming job:', jobId)
      const response = await fetch(`/api/galaxy/jobs/${jobId}/resume`, {
        method: 'PUT',
      })

      if (!response.ok) {
        const error = await response.json()
        throw new Error(error.message || 'Failed to resume job')
      }

      const result = await response.json()
      console.log('[EnhancedWorkflowBuilder] Job resumed successfully:', result)

      // Optionally show success message
      // toast.success('Job resumed successfully')
    } catch (error: any) {
      console.error('[EnhancedWorkflowBuilder] Failed to resume job:', error)
      alert(`Failed to resume job: ${error.message}`)
    }
  }

  const canStartWorkflow = workflowStatus === 'idle' && steps.some(s => s.status === 'pending')
  const canPauseWorkflow = workflowStatus === 'running'
  const canResumeWorkflow = workflowStatus === 'paused'

  return (
    <div className="space-y-6">
      {/* Header with integrated workflow controls */}
      <Card>
        <CardHeader>
          <div className="flex items-start justify-between mb-4">
            <div className="space-y-2">
              <CardTitle className="text-2xl">{galaxyWorkflowName}</CardTitle>
              <CardDescription>
                Graph-based workflow visualization with real-time execution tracking
                {galaxyWorkflowId && (
                  <span className="block mt-1 text-xs">
                    Galaxy Workflow ID: <code className="bg-muted px-1 py-0.5 rounded">{galaxyWorkflowId}</code>
                  </span>
                )}
              </CardDescription>
              <div className="flex items-center gap-4 flex-wrap">
                <div className="flex items-center gap-2">
                  <span className="text-sm text-muted-foreground">Progress:</span>
                  <Badge variant="outline">
                    {completedSteps} / {totalSteps} steps
                  </Badge>
                </div>
                <div className="flex items-center gap-2">
                  <span className="text-sm text-muted-foreground">Status:</span>
                  <Badge variant={workflowStatus === 'running' ? 'default' : 'secondary'}>
                    {workflowStatus}
                  </Badge>
                </div>
                {runningSteps > 0 && (
                  <div className="flex items-center gap-2">
                    <span className="text-sm text-muted-foreground">Running:</span>
                    <Badge variant="default">{runningSteps} steps</Badge>
                  </div>
                )}
                {errorSteps > 0 && (
                  <div className="flex items-center gap-2">
                    <span className="text-sm text-muted-foreground">Errors:</span>
                    <Badge variant="destructive">{errorSteps} steps</Badge>
                  </div>
                )}
              </div>
            </div>
            <Button
              variant="outline"
              onClick={onGetHelp}
              data-testid="button-get-workflow-help"
            >
              <MessageCircle className="w-4 h-4 mr-2" />
              Get Help
            </Button>
          </div>

          {/* Workflow Controls - Integrated into header */}
          <div className="space-y-3 border-t pt-4">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <span className="text-sm text-muted-foreground">Execution Mode:</span>
                <Button
                  variant={executionMode === 'sequential' ? 'default' : 'outline'}
                  size="sm"
                  onClick={() => setExecutionMode('sequential')}
                  data-testid="button-mode-sequential"
                >
                  Sequential
                </Button>
                <Button
                  variant={executionMode === 'step-by-step' ? 'default' : 'outline'}
                  size="sm"
                  onClick={() => setExecutionMode('step-by-step')}
                  data-testid="button-mode-step-by-step"
                >
                  <SkipForward className="w-4 h-4 mr-1" />
                  Step by Step
                </Button>
              </div>

              <div className="flex items-center gap-2">
                <Button
                  onClick={() => handleWorkflowAction('start')}
                  disabled={!canStartWorkflow}
                  data-testid="button-execute-workflow"
                >
                  <Play className="w-4 h-4 mr-2" />
                  Start Workflow
                </Button>

                {canPauseWorkflow && (
                  <Button
                    variant="outline"
                    onClick={() => handleWorkflowAction('pause')}
                    data-testid="button-workflow-pause"
                  >
                    <Pause className="w-4 h-4 mr-2" />
                    Pause
                  </Button>
                )}

                {canResumeWorkflow && (
                  <Button
                    variant="outline"
                    onClick={() => handleWorkflowAction('resume')}
                    data-testid="button-workflow-resume"
                  >
                    <Play className="w-4 h-4 mr-2" />
                    Resume
                  </Button>
                )}

                <Button
                  variant="outline"
                  onClick={() => handleWorkflowAction('stop')}
                  disabled={workflowStatus === 'idle'}
                  data-testid="button-workflow-stop"
                >
                  <Square className="w-4 h-4 mr-2" />
                  Stop
                </Button>

                <Button
                  variant="outline"
                  onClick={() => handleWorkflowAction('restart')}
                  data-testid="button-workflow-restart"
                >
                  <RotateCcw className="w-4 h-4 mr-2" />
                  Restart
                </Button>
              </div>
            </div>

            <div className="flex items-center gap-2">
              <Button
                variant="outline"
                onClick={() => setShowSaveDialog(true)}
                data-testid="button-save-workflow"
              >
                <Save className="w-4 h-4 mr-2" />
                Save
              </Button>
              <Button
                variant="outline"
                onClick={handleExportWorkflow}
                data-testid="button-export-workflow"
              >
                <Download className="w-4 h-4 mr-2" />
                Export
              </Button>
              <Button
                variant="outline"
                onClick={handleAddStep}
                data-testid="button-add-step"
              >
                <Plus className="w-4 h-4 mr-2" />
                Add Step
              </Button>
              <div className="ml-auto text-sm text-muted-foreground">
                Click nodes to see controls • Drag to pan
              </div>
            </div>
          </div>
        </CardHeader>
      </Card>

      {/* Workflow Graph - No tabs, graph only */}
      <WorkflowGraph
        steps={steps}
        onStepAction={handleStepAction}
      />

      {/* Execution Timeline - Shows step-by-step progress */}
      {timelineEvents.length > 0 && (
        <ExecutionTimeline
          events={timelineEvents}
          currentStepId={currentRunningStep?.stepId}
          formatElapsedTime={formatElapsedTime}
          onPauseJob={handlePauseJob}
          onResumeJob={handleResumeJob}
        />
      )}

      {/* Job Log Viewer - Shows real-time logs from running step */}
      {currentRunningStep && (
        <JobLogViewer
          stepId={currentRunningStep.stepId}
          stepName={currentRunningStep.stepName}
          logs={currentRunningStep.logs}
          isRunning={currentRunningStep.isRunning}
        />
      )}

      {/* Job Log Viewer - Shows logs from selected step */}
      {selectedStepLogs && !currentRunningStep && (
        <JobLogViewer
          stepId={selectedStepLogs.stepId}
          stepName={selectedStepLogs.stepName}
          logs={selectedStepLogs.logs}
          isRunning={selectedStepLogs.isRunning}
          onClear={() => setSelectedStepForLogs(null)}
        />
      )}

      {/* Connection Status Indicator */}
      {isConnected && (
        <Card className="border-blue-500 bg-blue-50 dark:bg-blue-950/20">
          <CardContent className="py-3">
            <div className="flex items-center justify-between text-sm">
              <div className="flex items-center gap-2">
                <div className="h-2 w-2 rounded-full bg-blue-500 animate-pulse" />
                <span className="text-blue-700 dark:text-blue-300">
                  Live connection to Galaxy • Invocation: {invocationId}
                </span>
              </div>
              {getTotalElapsedTime() && (
                <span className="text-blue-700 dark:text-blue-300">
                  Total elapsed: {formatElapsedTime(getTotalElapsedTime()!)}
                </span>
              )}
            </div>
          </CardContent>
        </Card>
      )}

      {/* Error Display */}
      {executionError && (
        <Card className="border-red-500 bg-red-50 dark:bg-red-950/20">
          <CardContent className="py-3">
            <div className="flex items-center gap-2 text-sm text-red-700 dark:text-red-300">
              <span className="font-semibold">Execution Error:</span>
              <span>{executionError}</span>
            </div>
          </CardContent>
        </Card>
      )}

      {/* Parameter Configuration Dialog */}
      <ParameterDialog
        open={editingStep !== null}
        onOpenChange={(open) => !open && setEditingStep(null)}
        step={editingStep}
        onSave={handleSaveParameters}
      />

      {/* Save Workflow Dialog */}
      <SaveWorkflowDialog
        isOpen={showSaveDialog}
        onClose={() => setShowSaveDialog(false)}
        workflowName={galaxyWorkflowName}
        workflowSteps={steps}
        onSave={handleSaveWorkflow}
      />

      {/* Dataset Validation Dialog */}
      <DatasetValidationDialog
        open={showValidationDialog}
        onOpenChange={setShowValidationDialog}
        validation={validationResult}
        onConfirm={handleValidationConfirm}
        onEdit={handleValidationEdit}
      />
    </div>
  )
}