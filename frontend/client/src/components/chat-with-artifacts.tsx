import { useState, useEffect, useRef, useMemo, useCallback } from "react"
import { ChatInterface } from "./chat-interface"
import { NextflowWorkflowViewer } from "./nextflow-workflow-viewer"
import { normalizePrereqChecklist } from "@/lib/prereq-normalizer"
// WorkflowHistoryPanel removed
import { chatHistoryService } from "@/lib/chat-history"
import { useUnifiedExecution } from "@/hooks/useUnifiedExecution"
import { emitUxEvent } from "@/lib/ux-telemetry"
import { useNetworkStatus } from "@/lib/network-status"
import { getExecutionAsyncGuidance } from "@/lib/async-guidance"
import { Button } from "@/components/ui/button"
import { useToast } from "@/hooks/use-toast"
import { ToastAction } from "@/components/ui/toast"
import type { ChatSession } from "@shared/schema"
import { AlertTriangle, MessageCircle, Layers, RefreshCw, Play, CheckCircle2, XCircle, Clock, X, FlaskConical } from "lucide-react"
import { PostRunMicroSurvey } from "./feedback/post-run-micro-survey"
import { ReportConfusionButton } from "./feedback/report-confusion-button"
import { SessionEndPulse } from "./feedback/session-end-pulse"
import { analytics } from "@/lib/analytics"
import {
  getOutputReadinessHint,
  getRunPrimaryCta,
  isRunNeedsAttention,
  mapRunBucket,
  runUpdatedAtMs,
  type RunBucket,
  type RunListItem,
} from "./run-manager-utils"

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
  /** Called when the workflow panel opens (true) or closes (false).
   *  Parent uses this to auto-collapse the sidebar for more screen space. */
  onWorkflowPanelOpenChange?: (open: boolean) => void
}
type RunManagerScope = 'current_chat' | 'all_chats'
type RunManagerSort = 'updated_desc' | 'running_first' | 'failed_first'

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

/**
 * Chat-first layout: Full-width chat with workflows displayed inline as artifacts.
 * No split panel - workflows appear as collapsible cards within chat messages.
 */
export function ChatWithArtifacts({ currentChatSession, onChatUpdated, onWorkflowPanelOpenChange }: ChatWithArtifactsProps) {
  const { toast } = useToast()
  // Track run statuses to detect transitions (running→completed, running→failed).
  // We only fire a toast on the transition, not on every poll.
  const prevRunStatusesRef = useRef<Map<string, string>>(new Map())
  // Track start time per run for elapsed-time display
  const runStartTimesRef = useRef<Map<string, number>>(new Map())
  const [elapsedTick, setElapsedTick] = useState(0)

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
  // ── Right panel (workflow panel) ────────────────────────────────────────────
  const [panelOpen, setPanelOpen] = useState(false)
  const [panelWorkflowMessageId, setPanelWorkflowMessageId] = useState<string | null>(null)
  const [panelWorkflow, setPanelWorkflow] = useState<any | null>(null)
  // Ref to ChatInterface's setChatDraft — set when ChatInterface registers it
  const setChatDraftRef = useRef<((draft: string) => void) | undefined>(undefined)
  const [postRunSurveyContext, setPostRunSurveyContext] = useState<{
    runId: string
    runStatus: 'completed' | 'failed' | 'cancelled'
    invocationId?: string
    actualTimeSec?: number
  } | null>(null)
  const surveyedRunIds = useRef<Set<string>>(new Set())
  const pulseShownForSession = useRef<Set<string>>(new Set())
  const recentRunSwitchesRef = useRef<number[]>([])
  const recentErrorCountsRef = useRef<Map<string, { count: number; windowStartMs: number }>>(new Map())
  const outputDeadEndSignalRunsRef = useRef<Set<string>>(new Set())
  const retryWithoutProgressRef = useRef<Map<string, { count: number; baselineProgress: number; windowStartMs: number }>>(new Map())
  const runListRequestSeqRef = useRef(0)
  const buildRunLineageContext = () => {
    const runId = currentRun?.id
    if (!runId) return {}
    const rootRunId = currentRun?.parentRunId || runId
    return {
      runId,
      rootRunId,
      parentRunId: currentRun?.parentRunId,
      runSequence: currentRun?.runSequence ?? 1,
    }
  }

  // Unified workflow execution hook (with input validation)
  const {
    currentRun,
    error: executionError,
    isConnected,
    isComplete,
    isRunning,
    executeWorkflow,
    pauseRun,
    resumeRun,
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
      params.set("offset", "0")
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

  // Elapsed-time ticker — updates every 30 s so status bar re-renders.
  useEffect(() => {
    const id = setInterval(() => setElapsedTick(t => t + 1), 30000)
    return () => clearInterval(id)
  }, [])

  // Watch runList for status transitions → fire in-app toast.
  useEffect(() => {
    const prev = prevRunStatusesRef.current
    for (const run of runList) {
      const bucket = mapRunBucket(run.execution?.status)
      const prevBucket = prev.get(run.id)

      // Track start time when a run goes running
      if (bucket === "running" && !runStartTimesRef.current.has(run.id)) {
        runStartTimesRef.current.set(run.id, Date.now())
      }

      if (prevBucket && prevBucket !== bucket) {
        if (bucket === "completed") {
          toast({
            title: "Workflow complete",
            description: run.workflowName || "Your workflow finished successfully.",
            action: (
              <ToastAction
                altText="View results"
                onClick={() => {
                  const invId = run.execution?.galaxyInvocationId || run.id
                  const el = document.querySelector(`[data-invocation-id="${invId}"]`)
                  el?.scrollIntoView({ behavior: "smooth", block: "center" })
                }}
              >
                View results
              </ToastAction>
            ),
            duration: 8000,
          })
        } else if (bucket === "failed") {
          toast({
            variant: "destructive",
            title: "Workflow failed",
            description: run.workflowName || "A workflow encountered an error.",
            action: (
              <ToastAction
                altText="View & fix"
                onClick={() => {
                  const invId = run.execution?.galaxyInvocationId || run.id
                  const el = document.querySelector(`[data-invocation-id="${invId}"]`)
                  el?.scrollIntoView({ behavior: "smooth", block: "center" })
                  setFocusedRunId(run.id)
                  setShowRunManager(true)
                }}
              >
                View & fix
              </ToastAction>
            ),
            duration: 0,
          })
        }
      }
      prev.set(run.id, bucket)
    }
  }, [runList]) // eslint-disable-line react-hooks/exhaustive-deps

  // Post-run micro-survey: trigger once per run when status is completed/failed/cancelled
  useEffect(() => {
    const status = normalizeSurveyStatus(currentRun?.execution?.status)
    const runId = currentRun?.id
    if (!runId || !status) return
    if (!surveyedRunIds.current.has(runId)) {
      surveyedRunIds.current.add(runId)
      // Check suppression before firing — avoids a flash-of-survey on the first render
      try {
        const suppressedUntil = localStorage.getItem('biomate_survey_suppressed_until')
        if (suppressedUntil && Date.now() < Number(suppressedUntil)) return
      } catch { /* localStorage unavailable */ }
      setPostRunSurveyContext({
        runId,
        runStatus: status,
        invocationId: currentRun?.execution?.galaxyInvocationId,
        actualTimeSec: currentRun?.execution?.nextflowStatus?.duration_s ?? undefined,
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

  // Detect output dead-ends (terminal completion without artifact readiness contract).
  useEffect(() => {
    const runId = currentRun?.id
    const status = currentRun?.execution?.status
    const readiness = currentRun?.execution?.nextflowStatus?.artifactReadiness
    if (!runId || status !== "completed" || !readiness) return
    if (readiness.meetsContract !== false) return
    if (outputDeadEndSignalRunsRef.current.has(runId)) return

    outputDeadEndSignalRunsRef.current.add(runId)
    const lineage = buildRunLineageContext()
    emitUxEvent("workflow.confusion_signal", {
      sessionId: currentChatSession?.id,
      ...lineage,
      signal: "output_dead_end",
      severity: readiness.hasOutputs ? "medium" : "high",
      hasOutputs: !!readiness.hasOutputs,
      totalOutputs: readiness.totalOutputs ?? 0,
      visualizableCount: readiness.visualizableCount ?? 0,
      downloadableCount: readiness.downloadableCount ?? 0,
    })
  }, [
    currentRun?.id,
    currentRun?.execution?.status,
    currentRun?.execution?.nextflowStatus?.artifactReadiness,
    currentChatSession?.id,
  ])

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

    const isNextflow = workflow.workflow_type === 'nextflow' || workflow.workflow_type === 'cryosparc' || workflow.format === 'nextflow' || !!workflow.nextflow_path;

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
        console.log('[ChatWithArtifacts] Preparing Nextflow/CryoSPARC workflow for unified execution');
        // Merge inline_parameters (user edits from the viewer panel) over the original
        // AI-suggested parameters so that values the user typed/changed are actually sent.
        const mergedParams = {
          ...(workflow.parameters || {}),
          ...(workflow.inline_parameters || {}),
        };
        workflowDefinition = {
          ...workflow,
          name: workflow.name || workflow.workflow_name || 'bioMate Nextflow Workflow',
          // Preserve the original workflow_type (e.g. 'cryosparc') — do not force 'nextflow'
          workflow_type: workflow.workflow_type || 'nextflow',
          format: workflow.format || 'nextflow',
          parameters: mergedParams,
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

  const handlePauseWorkflow = async () => {
    try {
      await pauseRun("Paused from chat execution controls")
      emitUxEvent("workflow.pause_clicked", {
        sessionId: currentChatSession?.id,
        runId: currentRun?.id,
      })
    } catch (error) {
      console.error("[ChatWithArtifacts] Failed to pause workflow:", error)
    }
  }

  const handleResumeWorkflow = async () => {
    try {
      await resumeRun()
      emitUxEvent("workflow.resume_clicked", {
        sessionId: currentChatSession?.id,
        runId: currentRun?.id,
      })
    } catch (error) {
      console.error("[ChatWithArtifacts] Failed to resume workflow:", error)
    }
  }

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

    const now = Date.now()
    const currentProgress = currentRun?.progress?.percentComplete ?? 0
    const retryChainKey =
      currentRun?.parentRunId ||
      currentRun?.id ||
      `${currentChatSession.id}:${lastWorkflowMessage.metadata?.workflow?.name || "workflow"}`
    const existing = retryWithoutProgressRef.current.get(retryChainKey)
    const withinWindow = existing && now - existing.windowStartMs <= 180000
    const sameOrWorseProgress = existing ? currentProgress <= existing.baselineProgress : false
    const count = withinWindow && sameOrWorseProgress ? existing.count + 1 : 1
    retryWithoutProgressRef.current.set(retryChainKey, {
      count,
      baselineProgress: Math.max(existing?.baselineProgress ?? currentProgress, currentProgress),
      windowStartMs: withinWindow ? existing!.windowStartMs : now,
    })

    if (count >= 2) {
      const lineage = buildRunLineageContext()
      emitUxEvent("workflow.confusion_signal", {
        sessionId: currentChatSession.id,
        ...lineage,
        signal: "retry_without_progress",
        severity: "high",
        progressPercent: currentProgress,
        count,
        retryChainKey,
        baselineProgressPercent: retryWithoutProgressRef.current.get(retryChainKey)?.baselineProgress ?? currentProgress,
        windowMs: 180000,
      })
    }

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

  // ── Right panel handlers ────────────────────────────────────────────────────
  const handleOpenWorkflowInPanel = useCallback((messageId: string, workflow: any) => {
    setPanelWorkflowMessageId(messageId)
    setPanelWorkflow(workflow)
    setPanelOpen(true)
    onWorkflowPanelOpenChange?.(true)
  }, [onWorkflowPanelOpenChange])

  const handleClosePanelWorkflow = useCallback(() => {
    setPanelOpen(false)
    setPanelWorkflowMessageId(null)
    onWorkflowPanelOpenChange?.(false)
    setPanelWorkflow(null)
  }, [])

  // Auto-open right panel whenever a new workflow message arrives
  const autoOpenedWorkflowMsgIdRef = useRef<string | null>(null)
  const lastWorkflowMsgId = useMemo(() => {
    const msgs = currentChatSession?.messages ?? []
    for (let i = msgs.length - 1; i >= 0; i--) {
      const m = msgs[i]
      if (m.role === 'assistant' && m.metadata?.type === 'workflow' && m.metadata?.workflow) {
        return m.id
      }
    }
    return null
  }, [currentChatSession?.messages])

  useEffect(() => {
    if (!lastWorkflowMsgId) return
    if (lastWorkflowMsgId === autoOpenedWorkflowMsgIdRef.current) return
    autoOpenedWorkflowMsgIdRef.current = lastWorkflowMsgId
    const msgs = currentChatSession?.messages ?? []
    const wf = msgs.find(m => m.id === lastWorkflowMsgId)
    if (wf?.metadata?.workflow) {
      setPanelWorkflowMessageId(lastWorkflowMsgId)
      setPanelWorkflow(wf.metadata.workflow)
      setPanelOpen(true)
      onWorkflowPanelOpenChange?.(true)
    }
  }, [lastWorkflowMsgId, currentChatSession?.messages, onWorkflowPanelOpenChange])

  const executionGuidance = getExecutionAsyncGuidance(executionError, { isOnline })
  const autofixState = currentRun?.execution?.nextflowStatus?.autofix?.state as string | undefined
  const isAutofixActive =
    currentRun?.execution?.nextflowStatus?.autofix?.active === true ||
    ["analyzing", "fixing", "restarting"].includes((autofixState || "").toLowerCase())
  const runningCount = runList.filter((run) => mapRunBucket(run.execution?.status) === "running").length
  const queuedCount  = runList.filter((run) => mapRunBucket(run.execution?.status) === "queued").length
  const completedTodayCount = runList.filter((run) => {
    if (mapRunBucket(run.execution?.status) !== "completed") return false
    const updatedAt = run.updatedAt ? new Date(run.updatedAt).getTime() : 0
    return Date.now() - updatedAt < 86400000
  }).length
  // Only count failures from the last 24 h — stale historical failures should not
  // keep the status bar permanently visible.
  const failedCount  = runList.filter((run) => {
    if (mapRunBucket(run.execution?.status) !== "failed") return false
    const updatedAt = run.updatedAt ? new Date(run.updatedAt).getTime() : 0
    return Date.now() - updatedAt < 86400000
  }).length

  // Format elapsed time for status bar (e.g. "4 min")
  const formatElapsed = (runId: string): string => {
    const started = runStartTimesRef.current.get(runId)
    if (!started) return ""
    const mins = Math.floor((Date.now() - started) / 60000)
    if (mins < 1) return "< 1 min"
    return `${mins} min`
  }

  // Active runs for status bar (running + queued, most recent first)
  const activeRuns = useMemo(() => runList
    .filter(r => ["running", "queued"].includes(mapRunBucket(r.execution?.status)))
    .slice(0, 3), // show at most 3 in the bar
    [runList] // eslint-disable-line react-hooks/exhaustive-deps
  )
  const filteredSortedRuns = useMemo(() => {
    const normalizedQuery = runSearchQuery.trim().toLowerCase()
    const filtered = runList.filter((run) => {
      const matchesQuery =
        normalizedQuery.length === 0 ||
        (run.workflowName || "").toLowerCase().includes(normalizedQuery) ||
        run.id.toLowerCase().includes(normalizedQuery)
      const matchesStatus =
        runStatusFilter === "all" ||
        (runStatusFilter === "needs_attention"
          ? isRunNeedsAttention(run)
          : mapRunBucket(run.execution?.status) === runStatusFilter)
      return matchesQuery && matchesStatus
    })

    const byUpdatedAtDesc = (a: RunListItem, b: RunListItem) => {
      return runUpdatedAtMs(b) - runUpdatedAtMs(a)
    }

    if (runSort === "updated_desc") {
      return [...filtered].sort(byUpdatedAtDesc)
    }

    const priorityByBucket: Record<Exclude<RunBucket, "needs_attention">, number> =
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
    needs_attention: filteredSortedRuns.filter((run) => isRunNeedsAttention(run)),
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
                <option value="needs_attention">Needs Attention</option>
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
          <div className="grid grid-cols-1 gap-3 md:grid-cols-2 xl:grid-cols-5">
            {(["needs_attention", "running", "queued", "failed", "completed"] as RunBucket[]).map((bucket) => (
              <div
                key={bucket}
                className="rounded-md border bg-background p-2"
                data-testid={`run-manager-bucket-${bucket}`}
              >
                <div className="mb-2 flex items-center justify-between">
                  <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">
                    {bucket === "needs_attention" ? "Needs Attention" : bucket}
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
                          <p
                            className="mt-1 inline-flex rounded border border-border px-1.5 py-0.5 text-[11px] font-medium text-foreground/90"
                            data-testid={`run-manager-item-cta-${run.id}`}
                          >
                            {getRunPrimaryCta(run)}
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
          actualTimeSec={postRunSurveyContext.actualTimeSec}
        />
      )}

      <SessionEndPulse
        open={showSessionEndPulse}
        onOpenChange={setShowSessionEndPulse}
        sessionId={currentChatSession?.id}
        runId={currentRun?.id}
        invocationId={currentRun?.execution?.galaxyInvocationId}
      />

      {/* Split layout: Chat (left, flexible) + Workflow Panel (right, fixed 420px) */}
      <div className={`flex-1 overflow-hidden flex ${panelOpen ? "gap-0" : ""}`}>
        {/* Center: Chat */}
        <div className="flex-1 overflow-hidden min-w-0">
          <ChatInterface
            chatSession={currentChatSession}
            onWorkflowGenerated={handleWorkflowGenerated}
            onChatUpdated={onChatUpdated}
            activeWorkflow={null}
            showProgress={false}
            onToggleProgress={() => {}}
            onRunWorkflow={handleRunWorkflow}
            onStopWorkflow={handleStopWorkflow}
            onPauseWorkflow={handlePauseWorkflow}
            onResumeWorkflow={handleResumeWorkflow}
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
            onOpenWorkflowInPanel={handleOpenWorkflowInPanel}
            panelWorkflowMessageId={panelWorkflowMessageId}
            isPanelOpen={panelOpen}
            onRegisterSetDraft={(setter) => { setChatDraftRef.current = setter }}
          />
        </div>

        {/* Right: Workflow Panel — auto-opens when AI returns a workflow */}
        {panelOpen && (
          <div
            className="w-[500px] flex-shrink-0 border-l bg-background flex flex-col overflow-hidden"
            data-testid="workflow-right-panel"
          >
            {/* Panel header */}
            <div className="flex items-center justify-between border-b px-4 py-2 flex-shrink-0">
              <div className="flex items-center gap-2">
                <FlaskConical className="h-4 w-4 text-primary" />
                <span className="text-sm font-semibold">Workflow Panel</span>
              </div>
              <button
                onClick={handleClosePanelWorkflow}
                className="rounded-sm p-1 hover:bg-muted"
                aria-label="Close workflow panel"
                data-testid="workflow-panel-close"
              >
                <X className="h-4 w-4" />
              </button>
            </div>

            {/* Panel body — scrollable */}
            <div className="flex-1 overflow-y-auto p-3">
              {panelWorkflow ? (
                (() => {
                  const execStatusStr = (
                    currentRun?.execution?.status ||
                    (isWorkflowRunning ? 'running' : 'idle')
                  ) as string
                  const viewerStatus: 'pending_review' | 'idle' | 'running' | 'paused' | 'completed' | 'failed' =
                    execStatusStr === 'completed' || execStatusStr === 'ok' ? 'completed'
                    : execStatusStr === 'paused'  ? 'paused'
                    : execStatusStr === 'failed'  || execStatusStr === 'cancelled' || execStatusStr === 'error' ? 'failed'
                    : execStatusStr === 'running' ? 'running'
                    : 'idle'

                  const prereqChecklist = normalizePrereqChecklist(
                    panelWorkflow?.prerequisitesValidation,
                    {}
                  )
                  return (
                    <NextflowWorkflowViewer
                      workflowDefinition={panelWorkflow}
                      invocationId={currentRun?.execution?.galaxyInvocationId || currentRun?.id}
                      workflowId={panelWorkflow?.id}
                      prereqChecklist={prereqChecklist}
                      autofix={currentRun?.execution?.nextflowStatus?.autofix}
                      nextflowStatus={currentRun?.execution?.nextflowStatus}
                      status={currentRun ? viewerStatus : (panelWorkflow?.workflowViewerStatus || viewerStatus)}
                      errorMessage={currentRun?.execution?.errorMessage}
                      progress={workflowProgress}
                      onExecute={(params) => {
                        const userParams = Object.fromEntries(
                          Object.entries(params || {}).filter(([k]) => !k.startsWith('__'))
                        )
                        handleRunWorkflow(
                          {
                            ...panelWorkflow,
                            inline_parameters: {
                              ...(panelWorkflow?.inline_parameters || {}),
                              ...userParams,
                            },
                            __executionOverrides: params?.__executionOverrides || undefined,
                            __qcConfig: params?.__qcConfig || undefined,
                          },
                          []
                        )
                      }}
                      onParameterChange={(id, value) => handleParameterChange(id, { value })}
                      onPause={handlePauseWorkflow}
                      onResume={handleResumeWorkflow}
                      onCancel={handleStopWorkflow}
                      onAdjustViaChat={(msg) => {
                        if (msg) setChatDraftRef.current?.(msg)
                      }}
                      sessionId={currentChatSession?.id}
                      runId={currentRun?.id}
                      executionEngine={currentRun?.execution?.executionEngine}
                      executionMetrics={currentRun?.metrics}
                    />
                  )
                })()
              ) : (
                <div className="flex h-full items-center justify-center">
                  <p className="text-sm text-muted-foreground text-center px-4">
                    Workflow details will appear here when you run a workflow.
                  </p>
                </div>
              )}
            </div>
          </div>
        )}
      </div>
    </div>
  )
}
