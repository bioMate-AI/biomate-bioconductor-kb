import { useState, useEffect, useRef, useMemo } from "react"
import { ChatInterface } from "./chat-interface"
// WorkflowHistoryPanel removed
import { chatHistoryService } from "@/lib/chat-history"
import { useUnifiedExecution } from "@/hooks/useUnifiedExecution"
import { emitUxEvent } from "@/lib/ux-telemetry"
import { useNetworkStatus } from "@/lib/network-status"
import { getExecutionAsyncGuidance } from "@/lib/async-guidance"
import { Button } from "@/components/ui/button"
import type { ChatSession } from "@shared/schema"
import { AlertTriangle, MessageCircle, Layers, RefreshCw } from "lucide-react"
import { PostRunMicroSurvey } from "./feedback/post-run-micro-survey"
import { ReportConfusionButton } from "./feedback/report-confusion-button"
import { SessionEndPulse } from "./feedback/session-end-pulse"
import { analytics } from "@/lib/analytics"

function normalizeSurveyStatus(status?: string): 'completed' | 'failed' | 'cancelled' | null {
  if (!status) return null
  if (status === 'completed' || status === 'ok') return 'completed'
  if (status === 'failed' || status === 'error') return 'failed'
  if (status === 'cancelled') return 'cancelled'
  return null
}

interface ChatWithArtifactsProps {
  currentChatSession: ChatSession | null
  onChatUpdated: (session: ChatSession) => void
}

interface RunListItem {
  id: string
  workflowName: string
  mode?: 'sandbox' | 'production'
  execution?: {
    status?: string
    galaxyInvocationId?: string
    galaxyWorkflowId?: string
    artifactReadiness?: {
      hasOutputs?: boolean
      visualizableCount?: number
      downloadableCount?: number
      totalOutputs?: number
      meetsContract?: boolean
    }
    nextflowStatus?: {
      artifactReadiness?: {
        hasOutputs?: boolean
        visualizableCount?: number
        downloadableCount?: number
        totalOutputs?: number
        meetsContract?: boolean
      }
      outputs?: unknown[]
      results?: unknown[]
      output_files?: unknown[]
    }
  }
  updatedAt?: string
  createdAt?: string
}

type RunBucket = 'running' | 'queued' | 'failed' | 'completed'
type RunManagerScope = 'current_chat' | 'all_chats'
type RunManagerSort = 'updated_desc' | 'running_first' | 'failed_first'

function mapRunBucket(status?: string): RunBucket {
  switch (status) {
    case 'running':
      return 'running'
    case 'configuring':
    case 'queued':
    case 'paused':
      return 'queued'
    case 'failed':
      return 'failed'
    case 'completed':
    case 'cancelled':
    default:
      return 'completed'
  }
}

function formatRunTime(raw?: string): string {
  if (!raw) return "n/a"
  const date = new Date(raw)
  if (Number.isNaN(date.getTime())) return "n/a"
  return date.toLocaleTimeString()
}

function formatFreshness(raw?: string): string {
  if (!raw) return "freshness unknown"
  const date = new Date(raw)
  if (Number.isNaN(date.getTime())) return "freshness unknown"
  const deltaMs = Date.now() - date.getTime()
  if (deltaMs < 0 || deltaMs < 60_000) return "just now"
  const deltaMinutes = Math.floor(deltaMs / 60_000)
  if (deltaMinutes < 60) return `${deltaMinutes}m ago`
  const deltaHours = Math.floor(deltaMinutes / 60)
  if (deltaHours < 24) return `${deltaHours}h ago`
  return `${Math.floor(deltaHours / 24)}d ago`
}

function shortenId(raw?: string, prefix = "", maxLen = 8): string {
  if (!raw) return `${prefix}n/a`
  const short = raw.length > maxLen ? raw.slice(0, maxLen) : raw
  return `${prefix}${short}`
}

function getOutputReadinessHint(run: RunListItem): string | null {
  const readiness = run.execution?.artifactReadiness || run.execution?.nextflowStatus?.artifactReadiness
  if (readiness) {
    if (readiness.meetsContract === true) {
      return `outputs ready (${readiness.visualizableCount ?? 0} viz / ${readiness.downloadableCount ?? 0} dl)`
    }
    if (readiness.hasOutputs) {
      return `partial outputs (${readiness.totalOutputs ?? 0})`
    }
    if (readiness.meetsContract === false) {
      return "outputs not ready"
    }
  }

  const outputCount =
    (Array.isArray(run.execution?.nextflowStatus?.outputs) ? run.execution?.nextflowStatus?.outputs.length : 0) +
    (Array.isArray(run.execution?.nextflowStatus?.results) ? run.execution?.nextflowStatus?.results.length : 0) +
    (Array.isArray(run.execution?.nextflowStatus?.output_files) ? run.execution?.nextflowStatus?.output_files.length : 0)

  if (outputCount > 0) return `outputs detected (${outputCount})`
  if (run.execution?.status === "completed") return "completed; check artifacts"
  return null
}

function runUpdatedAtMs(run: RunListItem): number {
  const value = run.updatedAt || run.createdAt
  if (!value) return 0
  const ms = new Date(value).getTime()
  return Number.isFinite(ms) ? ms : 0
}

/**
 * Chat-first layout: Full-width chat with workflows displayed inline as artifacts.
 * No split panel - workflows appear as collapsible cards within chat messages.
 */
export function ChatWithArtifacts({ currentChatSession, onChatUpdated }: ChatWithArtifactsProps) {
  const [isWorkflowRunning, setIsWorkflowRunning] = useState(false)
  const [workflowProgress, setWorkflowProgress] = useState(0)
  const [currentWorkflowId, setCurrentWorkflowId] = useState<string | null>(null)
  const [workflowError, setWorkflowError] = useState<string | null>(null)
  const [showPostRunSurvey, setShowPostRunSurvey] = useState(false)
  const [showSessionEndPulse, setShowSessionEndPulse] = useState(false)
  const [externalPromptRequest, setExternalPromptRequest] = useState<{ id: number; prompt: string } | null>(null)
  const promptRequestCounter = useRef(0)
  const [showRunManager, setShowRunManager] = useState(false)
  const [runList, setRunList] = useState<RunListItem[]>([])
  const [isRunListLoading, setIsRunListLoading] = useState(false)
  const [runListError, setRunListError] = useState<string | null>(null)
  const [runManagerScope, setRunManagerScope] = useState<RunManagerScope>('current_chat')
  const [runSearchQuery, setRunSearchQuery] = useState("")
  const [runStatusFilter, setRunStatusFilter] = useState<"all" | RunBucket>("all")
  const [runSort, setRunSort] = useState<RunManagerSort>("updated_desc")
  const [focusedRunId, setFocusedRunId] = useState<string | null>(null)
  const [runAnchorRequestId, setRunAnchorRequestId] = useState(0)
  const [postRunSurveyContext, setPostRunSurveyContext] = useState<{
    runId: string
    runStatus: 'completed' | 'failed' | 'cancelled'
    invocationId?: string
  } | null>(null)
  const surveyedRunIds = useRef<Set<string>>(new Set())
  const pulseShownForSession = useRef<Set<string>>(new Set())
  const recentRunSwitchesRef = useRef<number[]>([])
  const recentErrorCountsRef = useRef<Map<string, { count: number; windowStartMs: number }>>(new Map())
  const runListRequestSeqRef = useRef(0)

  // Unified workflow execution hook (with input validation)
  const {
    currentRun,
    error: executionError,
    isConnected,
    isComplete,
    isRunning,
    executeWorkflow,
    cancelRun,
    loadRun,
  } = useUnifiedExecution()
  const { isOnline } = useNetworkStatus()

  // Update progress based on execution run
  useEffect(() => {
    if (currentRun?.progress) {
      setWorkflowProgress(currentRun.progress.percentComplete || 0)
    }
  }, [currentRun?.progress])

  // Handle workflow completion
  useEffect(() => {
    if (isComplete) {
      console.log('[ChatWithArtifacts] Workflow execution complete')
      setIsWorkflowRunning(false)
      setWorkflowProgress(100)
      const status = currentRun?.execution?.status
      if (status === 'completed') {
        analytics.track('workflow_completed', {
          invocation_id: currentRun?.execution?.galaxyInvocationId,
        })
      } else if (status === 'failed') {
        analytics.track('workflow_failed', {
          invocation_id: currentRun?.execution?.galaxyInvocationId,
          error: currentRun?.execution?.errorMessage,
        })
      } else if (status === 'cancelled') {
        analytics.track('workflow_cancelled', {
          invocation_id: currentRun?.execution?.galaxyInvocationId,
        })
      }
    }
  }, [isComplete]) // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    if (!currentRun) return
    setCurrentWorkflowId(
      currentRun.execution?.galaxyWorkflowId ||
      currentRun.execution?.galaxyInvocationId ||
      currentRun.id
    )
  }, [currentRun])

  useEffect(() => {
    if (currentRun?.id) {
      setFocusedRunId(currentRun.id)
    }
  }, [currentRun?.id])

  const fetchRunList = async () => {
    const requestSeq = ++runListRequestSeqRef.current
    setIsRunListLoading(true)
    setRunListError(null)
    try {
      const params = new URLSearchParams({ limit: "50" })
      if (runManagerScope === "current_chat" && currentChatSession?.id) {
        params.set("chatSessionId", currentChatSession.id)
      }
      const response = await fetch(`/api/workflows/runs?${params.toString()}`)
      if (!response.ok) {
        throw new Error(`Failed to fetch runs: ${response.status}`)
      }
      const data = await response.json()
      const runs = Array.isArray(data) ? data : []
      if (requestSeq !== runListRequestSeqRef.current) {
        return
      }
      setRunList(runs)
    } catch (error: any) {
      if (requestSeq !== runListRequestSeqRef.current) {
        return
      }
      setRunListError(error?.message || "Failed to fetch runs")
    } finally {
      if (requestSeq !== runListRequestSeqRef.current) {
        return
      }
      setIsRunListLoading(false)
    }
  }

  useEffect(() => {
    fetchRunList()
    const intervalId = setInterval(fetchRunList, 10000)
    return () => clearInterval(intervalId)
  }, [currentChatSession?.id, runManagerScope])

  // Post-run micro-survey: trigger once per run when status is completed/failed/cancelled
  useEffect(() => {
    const status = normalizeSurveyStatus(currentRun?.execution?.status)
    const runId = currentRun?.id
    if (!runId || !status) return
    if (!surveyedRunIds.current.has(runId)) {
      surveyedRunIds.current.add(runId)
      setPostRunSurveyContext({
        runId,
        runStatus: status,
        invocationId: currentRun?.execution?.galaxyInvocationId,
      })
      setShowPostRunSurvey(true)
    }
  }, [currentRun?.id, currentRun?.execution?.status, currentRun?.execution?.galaxyInvocationId])

  // Handle execution errors
  useEffect(() => {
    if (executionError) {
      emitUxEvent('workflow.error_shown', {
        sessionId: currentChatSession?.id,
        runId: currentRun?.id,
        errorMessage: executionError,
      })
      const runKey = currentRun?.id || "unknown"
      const now = Date.now()
      const existing = recentErrorCountsRef.current.get(runKey)
      const withinWindow = existing && now - existing.windowStartMs <= 120000
      const count = withinWindow ? existing.count + 1 : 1
      recentErrorCountsRef.current.set(runKey, {
        count,
        windowStartMs: withinWindow ? existing.windowStartMs : now,
      })
      if (count >= 3) {
        emitUxEvent("workflow.confusion_signal", {
          sessionId: currentChatSession?.id,
          runId: currentRun?.id,
          signal: "repeated_error_surface",
          severity: "high",
          windowMs: 120000,
          count,
        })
      }
      console.error('[ChatWithArtifacts] Workflow execution error:', executionError)
      setIsWorkflowRunning(false)
    }
  }, [executionError, currentChatSession?.id, currentRun?.id])

  // Session-end pulse: show once per chat session after post-run survey is dismissed.
  useEffect(() => {
    const status = normalizeSurveyStatus(currentRun?.execution?.status)
    const runId = currentRun?.id
    const sessionId = currentChatSession?.id
    if (!sessionId || !status || !runId) return
    const surveyPreparedForRun = postRunSurveyContext?.runId === runId
    if (surveyPreparedForRun && !showPostRunSurvey && !pulseShownForSession.current.has(sessionId)) {
      pulseShownForSession.current.add(sessionId)
      setShowSessionEndPulse(true)
    }
  }, [currentRun?.id, currentRun?.execution?.status, currentChatSession?.id, postRunSurveyContext?.runId, showPostRunSurvey])

  const handleWorkflowGenerated = (workflow: any, metadata?: any) => {
    console.log('ChatWithArtifacts: New workflow generated:', workflow);

    if (!workflow || !currentChatSession) {
      return;
    }

    // Get fresh session and update with workflow data in the message metadata
    const freshSession = chatHistoryService.getSession(currentChatSession.id);
    if (freshSession) {
      // Workflow is now stored in the message metadata (via ChatInterface)
      // Just trigger the update to persist
      onChatUpdated(freshSession);
    }
  };

  const handleRunWorkflow = async (workflow: any, steps: any[]) => {
    emitUxEvent('workflow.run_clicked', {
      sessionId: currentChatSession?.id,
      workflowId: workflow?.id ?? workflow?.name,
    });
    console.log('[ChatWithArtifacts] Running workflow:', workflow?.name || 'unnamed');
    console.log('[ChatWithArtifacts] Steps:', steps?.length || 0);
    console.log('[ChatWithArtifacts] Workflow format:', workflow?.workflow_type || workflow?.format || (workflow?.a_galaxy_workflow ? 'galaxy' : 'unknown'));

    if (!workflow) {
      console.error('[ChatWithArtifacts] No workflow to run');
      return;
    }

    // Clear any previous error
    setWorkflowError(null);
    setIsWorkflowRunning(true);
    setWorkflowProgress(0);

    const isNextflow = workflow.workflow_type === 'nextflow' || workflow.format === 'nextflow' || !!workflow.nextflow_path;

    // Non-Nextflow workflows still require concrete step definitions.
    if (!isNextflow && (!steps || steps.length === 0)) {
      console.error('[ChatWithArtifacts] No steps to run (Galaxy workflow requires steps)');
      setIsWorkflowRunning(false);
      return;
    }

    try {
      // Build workflow definition (Galaxy .ga format)
      let workflowDefinition: any;

      if (isNextflow) {
        console.log('[ChatWithArtifacts] Preparing Nextflow workflow for unified execution');
        workflowDefinition = {
          ...workflow,
          name: workflow.name || workflow.workflow_name || 'bioMate Nextflow Workflow',
          workflow_type: 'nextflow',
          format: workflow.format || 'nextflow',
          parameters: workflow.parameters || {},
        };
      } else if (workflow.a_galaxy_workflow) {
        console.log('[ChatWithArtifacts] Using AI-generated .ga workflow format');
        workflowDefinition = workflow;
      } else {
        console.log('[ChatWithArtifacts] Building workflow from simplified format');
        workflowDefinition = {
          a_galaxy_workflow: "true",
          "format-version": "0.1",
          name: workflow.name || 'bioMate Generated Workflow',
          annotation: workflow.annotation || `Workflow generated by bioMate AI`,
          tags: ["biomate-generated"],
          steps: workflow.steps || steps.reduce((acc: Record<string, any>, step: any, index: number) => {
            acc[index.toString()] = {
              id: index,
              tool_id: step.tool_id || step.tool,
              tool_version: null,
              type: 'tool',
              name: step.name || step.tool_id || `Step ${index + 1}`,
              annotation: step.annotation || step.description,
              tool_state: JSON.stringify(step.parameters || {}),
              position: { top: index * 150, left: 200 },
              input_connections: index > 0 ? { input: { id: index - 1, output_name: 'output' } } : {},
              outputs: []
            }
            return acc
          }, {} as Record<string, any>)
        }
      }

      // Build inputs from dataset_assignments if available
      const inputs: Array<{ id: string; src: string; step_id?: number }> = [];
      if (workflow.dataset_assignments?.workflow_steps) {
        for (const stepData of workflow.dataset_assignments.workflow_steps) {
          if (stepData.dataset_needed && stepData.selected_datasets?.length > 0) {
            const dataset = stepData.selected_datasets[0];
            inputs.push({
              id: dataset.id,
              src: 'hda',
              step_id: stepData.step
            });
          }
        }
      }

      console.log('[ChatWithArtifacts] Executing workflow via unified API');
      console.log('[ChatWithArtifacts] Inputs:', inputs.length);

      // Execute workflow using unified API (handles validation, history creation, invocation)
      const allowLowConfidenceOverride =
        workflow.__executionOverrides?.allowLowConfidence === true;
      const retryContext = workflow.__retryContext
        ? {
            runId: workflow.__retryContext.runId,
            galaxyInvocationId: workflow.__retryContext.galaxyInvocationId,
          }
        : undefined;
      const run = await executeWorkflow({
        workflowDefinition,
        workflowName: workflow.name || 'bioMate Workflow',
        chatSessionId: currentChatSession?.id || undefined,
        executionConfig: {
          mode: 'sandbox',
          dataScope: { fraction: 1.0, samplingStrategy: 'sequential', sampledIds: [] },
          allowLowConfidence: allowLowConfidenceOverride,
          retryOfRunId: retryContext?.runId,
          retryOfInvocationId: retryContext?.galaxyInvocationId,
        },
        inputs,
        generationAssessment: workflow.__generationAssessment
          ? {
              ...workflow.__generationAssessment,
              userConfirmedLowConfidence: allowLowConfidenceOverride,
            }
          : undefined,
        retryContext,
      });

      console.log('[ChatWithArtifacts] Workflow execution started:', run?.id);
      analytics.track('workflow_started', {
        domain: workflow.domain,
        workflow_steps: (workflow.steps ? Object.keys(workflow.steps).length : steps?.length) ?? 0,
        execution_engine: isNextflow ? 'nextflow' : 'galaxy',
        qc_profile: workflow.qc_profile,
        total_samples: workflow.totalSamples,
        invocation_id: run?.execution?.galaxyInvocationId,
      })
      setCurrentWorkflowId(
        run?.execution?.galaxyWorkflowId ||
        run?.execution?.galaxyInvocationId ||
        null
      );

      // Update message with invocationId for output tracking
      if (run && currentChatSession) {
        const freshSession = chatHistoryService.getSession(currentChatSession.id);
        if (freshSession) {
          const updatedMessages = [...freshSession.messages];
          const invocationForMessage =
            run.execution?.galaxyInvocationId ||
            run.id;

          // Prefer exact workflow-name match, but always fall back to latest workflow message.
          let targetIndex = updatedMessages.findIndex(
            (msg) =>
              msg.metadata?.type === 'workflow' &&
              msg.metadata?.workflow?.name &&
              workflow.name &&
              msg.metadata.workflow.name === workflow.name
          );
          if (targetIndex < 0) {
            for (let i = updatedMessages.length - 1; i >= 0; i--) {
              if (updatedMessages[i].metadata?.type === 'workflow') {
                targetIndex = i;
                break;
              }
            }
          }

          if (targetIndex >= 0) {
            console.log('[ChatWithArtifacts] Updating message with invocation ID:', invocationForMessage);
            updatedMessages[targetIndex] = {
              ...updatedMessages[targetIndex],
              invocationId: invocationForMessage,
            };
          }

          const updatedSession = { ...freshSession, messages: updatedMessages };
          chatHistoryService.updateSession(freshSession.id, updatedSession);
          onChatUpdated(updatedSession);
        }
      }

    } catch (error: any) {
      console.error('[ChatWithArtifacts] Failed to run workflow:', error);
      setIsWorkflowRunning(false);
      setWorkflowProgress(0);

      analytics.track('workflow_failed', { error: error?.message || 'Failed to run workflow' })

      // Error message comes from unified API (includes input validation errors)
      setWorkflowError(error?.message || 'Failed to run workflow');
    }
  };

  const handleStopWorkflow = async () => {
    console.log('[ChatWithArtifacts] Stopping workflow');
    try {
      await cancelRun();
      setIsWorkflowRunning(false);
      setWorkflowProgress(0);
      setCurrentWorkflowId(null);
    } catch (error: any) {
      console.error('[ChatWithArtifacts] Failed to stop workflow:', error);
    }
  };

  const handleParameterChange = (stepId: string, params: Record<string, any>) => {
    console.log('ChatWithArtifacts: Parameter changed for step', stepId, params);

    // Update workflow parameters in the current session
    if (currentChatSession) {
      const freshSession = chatHistoryService.getSession(currentChatSession.id);
      if (freshSession) {
        // Find the message with the workflow and update its parameters
        const updatedMessages = freshSession.messages.map(msg => {
          if (msg.metadata?.type === 'workflow' && msg.metadata?.steps) {
            const updatedSteps = msg.metadata.steps.map((step: any) =>
              step.id === stepId ? { ...step, parameters: params } : step
            );
            return {
              ...msg,
              metadata: { ...msg.metadata, steps: updatedSteps }
            };
          }
          return msg;
        });

        const updatedSession = { ...freshSession, messages: updatedMessages };
        onChatUpdated(updatedSession);
      }
    }
  };

  const handleRetryExecution = async () => {
    if (!currentChatSession || isWorkflowRunning) return;
    const freshSession = chatHistoryService.getSession(currentChatSession.id);
    const lastWorkflowMessage = [...(freshSession?.messages || [])]
      .reverse()
      .find((msg) => msg.metadata?.type === "workflow" && msg.metadata?.workflow);

    if (!lastWorkflowMessage?.metadata?.workflow) return;

    emitUxEvent("async.retry_clicked", {
      sessionId: currentChatSession.id,
      runId: currentRun?.id,
      source: "execution_error_surface",
    });

    await handleRunWorkflow(
      {
        ...lastWorkflowMessage.metadata.workflow,
        __retryContext: {
          runId: currentRun?.id,
          galaxyInvocationId: currentRun?.execution?.galaxyInvocationId,
        },
      },
      lastWorkflowMessage.metadata?.steps || []
    );
  };

  const handleSwitchRun = async (runId: string) => {
    setFocusedRunId(runId)
    setRunAnchorRequestId((prev) => prev + 1)
    const now = Date.now()
    const recentSwitches = recentRunSwitchesRef.current.filter((ts) => now - ts <= 120000)
    recentSwitches.push(now)
    recentRunSwitchesRef.current = recentSwitches
    if (recentSwitches.length >= 4) {
      emitUxEvent("workflow.confusion_signal", {
        sessionId: currentChatSession?.id,
        runId,
        signal: "run_switch_oscillation",
        severity: "medium",
        windowMs: 120000,
        count: recentSwitches.length,
      })
    }
    try {
      await loadRun(runId)
      emitUxEvent("workflow.run_switched", {
        sessionId: currentChatSession?.id,
        runId,
      })
    } catch (error) {
      console.error("[RunManager] Failed to switch run:", error)
    }
  }

  const submitBackgroundPrompt = (prompt: string, actionId: string) => {
    promptRequestCounter.current += 1
    emitUxEvent("workflow.background_action_selected", {
      sessionId: currentChatSession?.id,
      runId: currentRun?.id,
      actionId,
    })
    setExternalPromptRequest({ id: promptRequestCounter.current, prompt })
  }

  const handlePrereqRecoveryRequest = () => {
    promptRequestCounter.current += 1
    emitUxEvent("workflow.prereq_recovery_requested", {
      sessionId: currentChatSession?.id,
      runId: currentRun?.id,
    })
    setExternalPromptRequest({
      id: promptRequestCounter.current,
      prompt:
        "My current workflow run is blocked by missing prerequisites. Please generate a runnable demo path with sample/test inputs and a workflow variant that can produce one visualizable report and downloadable outputs.",
    })
  }

  const executionGuidance = getExecutionAsyncGuidance(executionError, { isOnline })
  const autofixState = currentRun?.execution?.nextflowStatus?.autofix?.state as string | undefined
  const isAutofixActive =
    currentRun?.execution?.nextflowStatus?.autofix?.active === true ||
    ["analyzing", "fixing", "restarting"].includes((autofixState || "").toLowerCase())
  const runningCount = runList.filter((run) => mapRunBucket(run.execution?.status) === "running").length
  const filteredSortedRuns = useMemo(() => {
    const normalizedQuery = runSearchQuery.trim().toLowerCase()
    const filtered = runList.filter((run) => {
      const matchesQuery =
        normalizedQuery.length === 0 ||
        (run.workflowName || "").toLowerCase().includes(normalizedQuery) ||
        run.id.toLowerCase().includes(normalizedQuery)
      const bucket = mapRunBucket(run.execution?.status)
      const matchesStatus = runStatusFilter === "all" || bucket === runStatusFilter
      return matchesQuery && matchesStatus
    })

    const byUpdatedAtDesc = (a: RunListItem, b: RunListItem) => {
      return runUpdatedAtMs(b) - runUpdatedAtMs(a)
    }

    if (runSort === "updated_desc") {
      return [...filtered].sort(byUpdatedAtDesc)
    }

    const priorityByBucket: Record<RunBucket, number> =
      runSort === "running_first"
        ? { running: 0, queued: 1, failed: 2, completed: 3 }
        : { failed: 0, running: 1, queued: 2, completed: 3 }

    return [...filtered].sort((a, b) => {
      const bucketDelta =
        priorityByBucket[mapRunBucket(a.execution?.status)] -
        priorityByBucket[mapRunBucket(b.execution?.status)]
      if (bucketDelta !== 0) return bucketDelta
      return byUpdatedAtDesc(a, b)
    })
  }, [runList, runSearchQuery, runStatusFilter, runSort])
  const runBuckets: Record<RunBucket, RunListItem[]> = {
    running: filteredSortedRuns.filter((run) => mapRunBucket(run.execution?.status) === "running"),
    queued: filteredSortedRuns.filter((run) => mapRunBucket(run.execution?.status) === "queued"),
    failed: filteredSortedRuns.filter((run) => mapRunBucket(run.execution?.status) === "failed"),
    completed: filteredSortedRuns.filter((run) => mapRunBucket(run.execution?.status) === "completed"),
  }

  return (
    <div className="h-full flex flex-col">
      {/* Minimal Header */}
      <div className="border-b bg-background/95 backdrop-blur supports-[backdrop-filter]:bg-background/60">
        <div className="flex items-center justify-between px-4 py-2">
          <div className="flex items-center gap-2">
            <MessageCircle className="w-5 h-5 text-primary" />
            <h2 className="font-semibold">bioMate</h2>
            {/* Connection status indicator */}
            {isConnected && (
              <div className="flex items-center gap-1 ml-2">
                <div className="h-2 w-2 rounded-full bg-green-500 animate-pulse" />
                <span className="text-xs text-muted-foreground">Live</span>
              </div>
            )}
          </div>
          <div className="flex items-center gap-2">
            <Button
              variant="outline"
              size="sm"
              data-testid="button-toggle-run-manager"
              onClick={() => setShowRunManager((prev) => !prev)}
            >
              <Layers className="h-4 w-4 mr-1" />
              Run Manager
              <span className="ml-2 rounded bg-muted px-1.5 py-0.5 text-xs">{runningCount}</span>
            </Button>
            <Button
              variant="ghost"
              size="icon"
              data-testid="button-refresh-run-manager"
              onClick={fetchRunList}
              disabled={isRunListLoading}
              title="Refresh run list"
            >
              <RefreshCw className={`h-4 w-4 ${isRunListLoading ? "animate-spin" : ""}`} />
            </Button>
          </div>
        </div>
      </div>

      {showRunManager && (
        <div className="border-b bg-muted/20 px-4 py-3" data-testid="run-manager-panel">
          <div
            className="sr-only"
            data-testid="run-manager-focused-run-state"
            data-focused-run-id={focusedRunId || ""}
          />
          {runListError && (
            <p className="text-xs text-red-600 dark:text-red-400 mb-2">
              Failed to refresh runs: {runListError}
            </p>
          )}
          <div className="mb-3 flex flex-col gap-2 xl:flex-row xl:items-center xl:justify-between">
            <div className="inline-flex rounded-md border bg-background p-0.5" data-testid="run-manager-scope-toggle">
              <button
                type="button"
                data-testid="run-manager-scope-current-chat"
                onClick={() => setRunManagerScope("current_chat")}
                className={`rounded px-2 py-1 text-xs ${
                  runManagerScope === "current_chat" ? "bg-primary text-primary-foreground" : "text-muted-foreground"
                }`}
              >
                Current chat
              </button>
              <button
                type="button"
                data-testid="run-manager-scope-all-chats"
                onClick={() => setRunManagerScope("all_chats")}
                className={`rounded px-2 py-1 text-xs ${
                  runManagerScope === "all_chats" ? "bg-primary text-primary-foreground" : "text-muted-foreground"
                }`}
              >
                All chats
              </button>
            </div>
            <div className="grid grid-cols-1 gap-2 sm:grid-cols-3 xl:min-w-[720px]">
              <input
                value={runSearchQuery}
                onChange={(event) => setRunSearchQuery(event.target.value)}
                data-testid="run-manager-search-input"
                placeholder="Search workflow or run id"
                className="h-8 rounded-md border bg-background px-2 text-xs"
              />
              <select
                value={runStatusFilter}
                onChange={(event) => setRunStatusFilter(event.target.value as "all" | RunBucket)}
                data-testid="run-manager-filter-status"
                className="h-8 rounded-md border bg-background px-2 text-xs"
              >
                <option value="all">All statuses</option>
                <option value="running">Running</option>
                <option value="queued">Queued</option>
                <option value="failed">Failed</option>
                <option value="completed">Completed</option>
              </select>
              <select
                value={runSort}
                onChange={(event) => setRunSort(event.target.value as RunManagerSort)}
                data-testid="run-manager-sort-select"
                className="h-8 rounded-md border bg-background px-2 text-xs"
              >
                <option value="updated_desc">Updated (newest first)</option>
                <option value="running_first">Running first</option>
                <option value="failed_first">Failed first</option>
              </select>
            </div>
          </div>
          <div className="grid grid-cols-1 gap-3 md:grid-cols-2 xl:grid-cols-4">
            {(["running", "queued", "failed", "completed"] as RunBucket[]).map((bucket) => (
              <div
                key={bucket}
                className="rounded-md border bg-background p-2"
                data-testid={`run-manager-bucket-${bucket}`}
              >
                <div className="mb-2 flex items-center justify-between">
                  <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">
                    {bucket}
                  </p>
                  <span
                    className="text-xs text-muted-foreground"
                    data-testid={`run-manager-bucket-count-${bucket}`}
                  >
                    {runBuckets[bucket].length}
                  </span>
                </div>
                <div className="space-y-1.5">
                  {runBuckets[bucket].slice(0, 6).map((run) => (
                    (() => {
                      const readinessHint = getOutputReadinessHint(run)
                      return (
                        <button
                          key={run.id}
                          type="button"
                          className={`w-full rounded border px-2 py-1.5 text-left text-xs hover:bg-muted ${
                            focusedRunId === run.id || currentRun?.id === run.id
                              ? "border-primary bg-primary/5"
                              : "border-border"
                          }`}
                          data-testid={`run-manager-item-${run.id}`}
                          onClick={() => handleSwitchRun(run.id)}
                        >
                          <p className="font-medium truncate">{run.workflowName || "Untitled run"}</p>
                          <p className="text-muted-foreground">
                            {run.execution?.status || "unknown"} · {formatRunTime(run.updatedAt || run.createdAt)}
                          </p>
                          <p className="text-[11px] text-muted-foreground">
                            {shortenId(run.id, "run ")}
                            {run.execution?.galaxyInvocationId ? ` · ${shortenId(run.execution.galaxyInvocationId, "inv ")}` : ""}
                            {` · ${formatFreshness(run.updatedAt || run.createdAt)}`}
                          </p>
                          {readinessHint && (
                            <p className="text-[11px] text-muted-foreground">{readinessHint}</p>
                          )}
                        </button>
                      )
                    })()
                  ))}
                  {runBuckets[bucket].length === 0 && (
                    <p className="text-xs text-muted-foreground">No runs</p>
                  )}
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Execution status bar */}
      {!isOnline && (
        <div
          className="border-b bg-amber-50 dark:bg-amber-950/20 px-4 py-2"
          data-testid="offline-banner"
        >
          <div className="flex items-center gap-2 text-sm text-amber-800 dark:text-amber-200">
            <AlertTriangle className="h-4 w-4" />
            <span className="font-medium">You appear to be offline.</span>
          </div>
          <p className="mt-1 text-xs text-amber-700 dark:text-amber-300" data-testid="offline-retry-guidance">
            Reconnect to continue chat and workflow operations. Your current session remains available locally.
          </p>
        </div>
      )}

      {isWorkflowRunning && (
        <div className="border-b bg-blue-50 dark:bg-blue-950/20 px-4 py-2">
          <div className="flex items-center justify-between text-sm">
            <div className="flex items-center gap-2">
              <div className="h-2 w-2 rounded-full bg-blue-500 animate-pulse" />
              <span className="text-blue-700 dark:text-blue-300">
                Executing workflow... {workflowProgress}%
              </span>
            </div>
            {currentWorkflowId && (
              <span className="text-xs text-muted-foreground font-mono">
                ID: {currentWorkflowId}
              </span>
            )}
          </div>
          <div className="mt-2 h-1 bg-blue-200 dark:bg-blue-900 rounded-full overflow-hidden">
            <div
              className="h-full bg-blue-500 transition-all duration-500"
              style={{ width: `${workflowProgress}%` }}
            />
          </div>
          <div
            className="mt-3 rounded-md border border-blue-200/70 bg-white/70 p-2 text-xs dark:border-blue-800/70 dark:bg-blue-950/25"
            data-testid="background-assist-panel"
          >
            <p className="mb-2 text-blue-900 dark:text-blue-200">
              Workflow is running. I can help in parallel:
            </p>
            <div className="flex flex-wrap gap-2">
              <Button
                size="sm"
                variant="outline"
                data-testid="button-background-action-review-params"
                onClick={() =>
                  submitBackgroundPrompt(
                    "Review current workflow parameters and suggest quality/performance improvements before completion.",
                    "review_parameters"
                  )
                }
              >
                Review parameters
              </Button>
              <Button
                size="sm"
                variant="outline"
                data-testid="button-background-action-prepare-next"
                onClick={() =>
                  submitBackgroundPrompt(
                    "Prepare a candidate next workflow based on this run type, likely outputs, and common follow-up analyses.",
                    "prepare_next_workflow"
                  )
                }
              >
                Prepare next workflow
              </Button>
              <Button
                size="sm"
                variant="outline"
                data-testid="button-background-action-draft-report"
                onClick={() =>
                  submitBackgroundPrompt(
                    "Draft a concise report outline template for this run (methods, QC checks, expected outputs, and interpretation checklist).",
                    "draft_report_outline"
                  )
                }
              >
                Draft report outline
              </Button>
            </div>
          </div>
        </div>
      )}

      {/* Execution error display */}
      {executionError && (
        <div className="border-b bg-red-50 dark:bg-red-950/20 px-4 py-2">
          <div className="space-y-2 text-sm text-red-700 dark:text-red-300">
            <div className="flex items-center gap-2">
              <AlertTriangle className="h-4 w-4" />
              <span className="font-semibold">{executionGuidance.title}</span>
            </div>
            <p>
              <span className="font-medium">Reason:</span>{" "}
              {executionGuidance.reason}
            </p>
            <p>
              <span className="font-medium">Retry guidance:</span>{" "}
              {executionGuidance.retry}
            </p>
            <div className="flex items-center justify-between gap-3">
              <p className="text-xs">
                <span className="font-medium">Escalation path:</span>{" "}
                {executionGuidance.escalation}
              </p>
              <div className="flex items-center gap-2">
                <Button
                  variant="outline"
                  size="sm"
                  data-testid="button-execution-try-again"
                  onClick={handleRetryExecution}
                  disabled={isWorkflowRunning || isAutofixActive}
                >
                  {isAutofixActive ? "Auto-fix in progress" : "Try again"}
                </Button>
                <ReportConfusionButton
                  runId={currentRun?.id}
                  sessionId={currentChatSession?.id}
                  invocationId={currentRun?.execution?.galaxyInvocationId}
                  workflowId={currentRun?.execution?.galaxyWorkflowId}
                  context={{
                    executionStatus: currentRun?.execution?.status,
                    errorMessage: executionError,
                    workflowName: currentRun?.workflowName,
                  }}
                  variant="outline"
                  size="sm"
                  onClick={() =>
                    emitUxEvent("async.report_issue_clicked", {
                      sessionId: currentChatSession?.id,
                      runId: currentRun?.id,
                      source: "execution_error_surface",
                    })
                  }
                />
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Post-run micro-survey (once per run) */}
      {postRunSurveyContext && (
        <PostRunMicroSurvey
          open={showPostRunSurvey}
          onOpenChange={setShowPostRunSurvey}
          runId={postRunSurveyContext.runId}
          runStatus={postRunSurveyContext.runStatus}
          sessionId={currentChatSession?.id}
          invocationId={postRunSurveyContext.invocationId}
        />
      )}

      <SessionEndPulse
        open={showSessionEndPulse}
        onOpenChange={setShowSessionEndPulse}
        sessionId={currentChatSession?.id}
        runId={currentRun?.id}
        invocationId={currentRun?.execution?.galaxyInvocationId}
      />

      {/* Full-width Chat - Workflows appear inline as artifacts */}
      <div className="flex-1 overflow-hidden">
        <ChatInterface
          chatSession={currentChatSession}
          onWorkflowGenerated={handleWorkflowGenerated}
          onChatUpdated={onChatUpdated}
          activeWorkflow={null}
          showProgress={false}
          onToggleProgress={() => {}}
          // Workflow execution props - passed down to chat messages
          onRunWorkflow={handleRunWorkflow}
          onRequestPrereqRecovery={handlePrereqRecoveryRequest}
          onStopWorkflow={handleStopWorkflow}
          onParameterChange={handleParameterChange}
          isWorkflowRunning={isWorkflowRunning}
          workflowProgress={workflowProgress}
          currentExecutionRun={currentRun}
          workflowError={workflowError}
          externalPromptRequest={externalPromptRequest}
          focusedRunId={focusedRunId}
          runAnchorRequestId={runAnchorRequestId}
          onExternalPromptConsumed={(id) => {
            setExternalPromptRequest((prev) => (prev?.id === id ? null : prev))
          }}
        />
      </div>
    </div>
  )
}
