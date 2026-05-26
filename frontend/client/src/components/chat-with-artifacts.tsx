import { useState, useEffect, useRef, useMemo, useCallback } from "react"
import { useWorkflowTour } from "./workflow-tour"
import { ChatInterface } from "./chat-interface"
import { NextflowWorkflowViewer } from "./nextflow-workflow-viewer"
import { extractSubmittedParams } from "@/hooks/useRunAgainParamCarryover"
import { applyWorkflowEdits, type WorkflowEdit } from "@/lib/workflow-edits"
import { extractWorkflowEdits } from "@/lib/workflow-edits-extract"
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
  const { tourNode, startTour } = useWorkflowTour()
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
  const [showRunManager, setShowRunManager] = useState<boolean>(() => {
    try { return localStorage.getItem('biomate-run-manager-open') === 'true' } catch { return false }
  })
  useEffect(() => { try { localStorage.setItem('biomate-run-manager-open', String(showRunManager)) } catch {} }, [showRunManager])
  const [runList, setRunList] = useState<RunListItem[]>([])
  const [isRunListLoading, setIsRunListLoading] = useState(false)
  const [runListError, setRunListError] = useState<string | null>(null)
  const [runManagerScope, setRunManagerScope] = useState<RunManagerScope>(() => {
    try {
      const v = localStorage.getItem('biomate-run-manager-scope')
      return (v === 'all_chats' || v === 'current_chat') ? v : 'current_chat'
    } catch { return 'current_chat' }
  })
  useEffect(() => { try { localStorage.setItem('biomate-run-manager-scope', runManagerScope) } catch {} }, [runManagerScope])
  const [runSearchQuery, setRunSearchQuery] = useState("")
  const [runStatusFilter, setRunStatusFilter] = useState<"all" | RunBucket>("all")
  const [runSort, setRunSort] = useState<RunManagerSort>("updated_desc")
  const [focusedRunId, setFocusedRunId] = useState<string | null>(null)
  const [runAnchorRequestId, setRunAnchorRequestId] = useState(0)
  // ── Right panel (workflow panel) ────────────────────────────────────────────
  const [panelOpen, setPanelOpen] = useState(false)
  const [panelWorkflowMessageId, setPanelWorkflowMessageId] = useState<string | null>(null)
  const [panelWorkflow, setPanelWorkflow] = useState<any | null>(null)
  // Gap 2 — apply assistant-emitted workflow edits to the open panel artifact.
  // Backend extractor not yet wired (TODO in docs/20260521_GAP2_CHAT_DRIVEN_EDITS.md);
  // this effect activates the moment any assistant message arrives with
  // `metadata.workflowEdits`. Already-applied ops are tracked by message id so
  // re-renders (e.g. session restore) don't re-apply them.
  const appliedEditMessages = useRef<Set<string>>(new Set())
  const [appliedEditsDisplay, setAppliedEditsDisplay] = useState<Array<{ id: string; summary: string }>>([])
  // Structural ops (add_step / remove_step / reorder) are parked here and
  // require an explicit confirm before they mutate the panel artifact.
  // set_param auto-applies.
  const [pendingStructuralEdits, setPendingStructuralEdits] = useState<Array<{ id: string; edit: WorkflowEdit; summary: string }>>([])
  const summarizeEdit = (e: WorkflowEdit): string => {
    switch (e.op) {
      case 'set_param': return `${e.paramName}: ${JSON.stringify(e.value)}`
      case 'add_step':  return `+ ${e.workflowPath}${e.afterStepId ? ` after ${e.afterStepId}` : ''}`
      case 'remove_step': return `− ${e.stepId}`
      case 'reorder':   return `${e.stepId} before ${e.beforeStepId}`
    }
  }
  useEffect(() => {
    if (!panelWorkflow || !currentChatSession?.messages) return
    for (const msg of currentChatSession.messages) {
      if (msg.role !== 'assistant') continue
      const edits = (msg.metadata as any)?.workflowEdits as WorkflowEdit[] | undefined
      if (!edits || edits.length === 0) continue
      if (appliedEditMessages.current.has(msg.id)) continue
      appliedEditMessages.current.add(msg.id)
      // Partition: auto-apply set_param, park the rest.
      const auto = edits.filter((e) => e.op === 'set_param')
      const structural = edits.filter((e) => e.op !== 'set_param')
      if (auto.length > 0) {
        const result = applyWorkflowEdits(panelWorkflow, auto)
        setPanelWorkflow(result.next)
        if (result.rejected.length > 0) console.warn('[workflow-edits] rejected ops:', result.rejected)
        const summaries = result.applied.map(summarizeEdit)
        if (summaries.length > 0) {
          setAppliedEditsDisplay((prev) => [...prev, { id: `${msg.id}-${prev.length}`, summary: summaries.join(' · ') }])
        }
      }
      if (structural.length > 0) {
        setPendingStructuralEdits((prev) => [
          ...prev,
          ...structural.map((edit, i) => ({ id: `${msg.id}-pend-${i}`, edit, summary: summarizeEdit(edit) })),
        ])
      }
    }
  }, [currentChatSession?.messages, panelWorkflow])
  const confirmStructuralEdit = (id: string) => {
    const entry = pendingStructuralEdits.find((p) => p.id === id)
    if (!entry || !panelWorkflow) return
    const result = applyWorkflowEdits(panelWorkflow, [entry.edit])
    setPanelWorkflow(result.next)
    setPendingStructuralEdits((prev) => prev.filter((p) => p.id !== id))
    if (result.applied.length > 0) {
      setAppliedEditsDisplay((prev) => [...prev, { id: `confirm-${id}`, summary: entry.summary }])
    } else if (result.rejected.length > 0) {
      console.warn('[workflow-edits] confirm rejected:', result.rejected)
    }
  }
  const dismissStructuralEdit = (id: string) => {
    setPendingStructuralEdits((prev) => prev.filter((p) => p.id !== id))
  }

  // Gap 2 — rule-based extraction from user messages (frontend-only v1).
  const extractedFromUserMsgs = useRef<Set<string>>(new Set())
  useEffect(() => {
    if (!panelWorkflow || !currentChatSession?.messages) return
    for (const msg of currentChatSession.messages) {
      if (msg.role !== 'user') continue
      if (extractedFromUserMsgs.current.has(msg.id)) continue
      extractedFromUserMsgs.current.add(msg.id)
      const text = typeof msg.content === 'string' ? msg.content : ''
      const edits = extractWorkflowEdits(text, panelWorkflow)
      if (edits.length === 0) continue
      const result = applyWorkflowEdits(panelWorkflow, edits)
      if (result.applied.length === 0) continue
      setPanelWorkflow(result.next)
      const summaries = result.applied.map((e) => {
        if (e.op === 'set_param') return `${e.paramName}: ${JSON.stringify(e.value)}`
        return e.op
      })
      setAppliedEditsDisplay((prev) => [
        ...prev,
        { id: `user-${msg.id}-${prev.length}`, summary: summaries.join(' · ') },
      ])
    }
  }, [currentChatSession?.messages, panelWorkflow])

  // Phase 2.3 receiver — when the sidebar Workflows dialog dispatches "Run again",
  // it navigates here with ?runAgain=<runId>. Once on mount we load that run,
  // attach its workflow definition to the panel, and trigger handleRunWorkflow
  // with the prior submitted params (Gap 3's extractor flattens them).
  const handledRunAgain = useRef<string | null>(null)
  useEffect(() => {
    const url = new URL(window.location.href)
    const runId = url.searchParams.get('runAgain')
    if (!runId || handledRunAgain.current === runId) return
    handledRunAgain.current = runId
    ;(async () => {
      try {
        const r = await fetch(`/api/workflows/runs/${encodeURIComponent(runId)}`, { credentials: 'include' })
        if (!r.ok) throw new Error(`HTTP ${r.status}`)
        const run = await r.json()
        const wf = run?.workflowDefinition
        if (!wf) {
          console.warn('[runAgain] run has no workflowDefinition; skipping')
          return
        }
        const priorParams = extractSubmittedParams(run)
        setPanelWorkflow(wf)
        // Re-execute with prior params merged into inline_parameters so the
        // backend re-runs with the user's prior choices.
        await handleRunWorkflow({ ...wf, inline_parameters: { ...(wf.inline_parameters || {}), ...priorParams } }, [])
      } catch (e) {
        console.warn('[runAgain] failed:', e)
      } finally {
        // Strip the param so refreshes don't re-trigger
        url.searchParams.delete('runAgain')
        window.history.replaceState({}, '', url.toString())
      }
    })()
    // Only depend on the param; intentionally do not include handleRunWorkflow
    // because it changes identity each render and we want a single-shot.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  // Resizable panel width (px)
  const [panelWidth, setPanelWidth] = useState(520)
  const panelResizingRef = useRef(false)
  const panelResizeStartX = useRef(0)
  const panelResizeStartW = useRef(0)
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
    // Auto-open panel on run restore (e.g. after page refresh mid-run).
    // Only fires when the panel is closed and the run is active/running.
    const isActive = ['running', 'queued'].includes(currentRun.execution?.status ?? '');
    if (isActive && !panelWorkflow && currentRun.workflowDefinition) {
      setPanelWorkflow(currentRun.workflowDefinition)
      setPanelOpen(true)
    }
  }, [currentRun?.id]) // eslint-disable-line react-hooks/exhaustive-deps

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
      // Delay survey 8s so users can see the completion state / download panel first
      setTimeout(() => setShowPostRunSurvey(true), 8000)
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

  // Session-restore reconciliation: fires when the active chat session changes.
  // If a message in the session has an invocationId for a run that is still running,
  // re-load that run so the workflow panel and polling restart automatically.
  // This covers browser refresh, server HMR reload, and reopening BioMate mid-run.
  useEffect(() => {
    if (!currentChatSession?.id || currentRun) return; // already have a run
    const messages = currentChatSession.messages ?? [];
    // Scan messages newest-first for one with an invocationId
    for (let i = messages.length - 1; i >= 0; i--) {
      const msg = messages[i];
      const invId = msg.invocationId || msg.metadata?.invocationId;
      if (!invId) continue;
      // Load the run regardless of terminal status. The previous skip-on-terminal
      // logic left currentRun=null after App remount for completed runs, which
      // broke the workflow viewer's `(invocationId || runId) && showResults`
      // gate (props derived from currentRun → both undefined → no output panel).
      // loadRun() is safe for terminal runs: it only starts SSE/polling when
      // status === 'running' (see useUnifiedExecution.ts:621,628). Loading a
      // completed run just sets currentRun to the final state.
      // See docs/20260519_CS14_DEFINITIVE_FINDING.md.
      console.log(`[ChatWithArtifacts] Session restore: loading run ${invId} from message ${msg.id}`);
      loadRun(invId).catch(err =>
        console.warn('[ChatWithArtifacts] Session restore loadRun failed:', err)
      );
      break;
    }
  }, [currentChatSession?.id]); // eslint-disable-line react-hooks/exhaustive-deps

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

  // Drag-to-resize the workflow panel
  const handlePanelResizeStart = useCallback((e: React.MouseEvent) => {
    e.preventDefault()
    panelResizingRef.current = true
    panelResizeStartX.current = e.clientX
    panelResizeStartW.current = panelWidth

    const onMove = (ev: MouseEvent) => {
      if (!panelResizingRef.current) return
      const delta = panelResizeStartX.current - ev.clientX // dragging left = wider panel
      const next = Math.min(900, Math.max(320, panelResizeStartW.current + delta))
      setPanelWidth(next)
    }
    const onUp = () => {
      panelResizingRef.current = false
      window.removeEventListener('mousemove', onMove)
      window.removeEventListener('mouseup', onUp)
    }
    window.addEventListener('mousemove', onMove)
    window.addEventListener('mouseup', onUp)
  }, [panelWidth])

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
      // Belt-and-suspenders: merge LLM-extracted inline params from message.metadata.inlineParameters
      // (set by chat-stream final event) into the workflow object so the viewer's form prefills.
      // Per docs/20260518_tier0_audit_T01_results.md (Bug A+C).
      const meta = wf.metadata as any
      const inlineFromMeta =
        meta?.inlineParameters ??
        meta?.inline_parameters ??
        meta?.workflowSuggestion?.inlineParameters ??
        null
      const wfWithInline = inlineFromMeta && typeof inlineFromMeta === 'object' && Object.keys(inlineFromMeta).length > 0
        ? {
            ...wf.metadata.workflow,
            inline_parameters: {
              ...((wf.metadata.workflow as any)?.inline_parameters || {}),
              ...inlineFromMeta,
            },
          }
        : wf.metadata.workflow
      setPanelWorkflow(wfWithInline)
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
      {/* Chat top bar — matches reference: "New thread · Domain" */}
      <div className="chat-top flex-shrink-0" style={{
        height: 48, borderBottom: '1px solid var(--bm-border, hsl(var(--border)))',
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        padding: '0 18px',
        background: 'var(--bm-bg-elev, hsl(var(--background)))',
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <span style={{
            fontWeight: 600, fontSize: 14,
            color: 'var(--bm-text, hsl(var(--foreground)))',
            fontFamily: 'var(--bm-font-ui)',
          }}>
            {currentChatSession?.title || 'New thread'}
          </span>
          {isConnected && (
            <span style={{ fontSize: 11, color: 'var(--bm-ok, oklch(0.62 0.13 150))', display: 'flex', alignItems: 'center', gap: 4 }}>
              <span style={{ width: 6, height: 6, borderRadius: '50%', background: 'currentColor', display: 'inline-block' }} />
              live
            </span>
          )}
        </div>
        <div className="flex items-center gap-2">
          <Button
            variant="ghost"
            size="sm"
            data-testid="button-toggle-run-manager"
            onClick={() => setShowRunManager((prev) => !prev)}
            style={{ fontSize: 12, height: 28, gap: 5 }}
          >
            <Layers className="h-3 w-3" style={{ flexShrink: 0 }} />
            Run Manager
            {runningCount > 0 ? (
              <span style={{
                background: 'var(--bm-blue, oklch(0.55 0.18 240))',
                color: 'white', borderRadius: 9, fontSize: 10,
                padding: '0 5px', fontWeight: 600, lineHeight: '16px',
              }}>{runningCount}</span>
            ) : (
              <span style={{ color: 'var(--bm-text-dim)', fontSize: 11 }}>
                {runList.length > 0 ? runList.length : '0'}
              </span>
            )}
          </Button>
          <Button
            variant="ghost"
            size="icon"
            data-testid="button-refresh-run-manager"
            onClick={fetchRunList}
            disabled={isRunListLoading}
            title="Refresh run list"
            className="h-7 w-7"
          >
            <RefreshCw className={`h-3.5 w-3.5 ${isRunListLoading ? "animate-spin" : ""}`} />
          </Button>
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

      {/* Tour overlay portal */}
      {tourNode}

      {/* Split layout: Chat (left, flexible) + Workflow Panel (right, fixed 420px) */}
      <div className={`flex-1 overflow-hidden flex ${panelOpen ? "gap-0" : ""}`}>
        {/* Center: Chat */}
        <div className="flex-1 overflow-hidden min-w-0">
          {pendingStructuralEdits.length > 0 && (
            <div
              data-testid="workflow-edits-pending"
              style={{
                display: 'flex', flexWrap: 'wrap', gap: 6,
                padding: '6px 12px', borderTop: '1px solid var(--bm-border, oklch(0.92 0.005 260))',
                background: 'oklch(0.98 0.02 60)',
              }}
            >
              {pendingStructuralEdits.map((p) => (
                <span
                  key={p.id}
                  data-testid={`workflow-edits-pending-${p.id}`}
                  style={{
                    fontSize: 11, padding: '2px 6px 2px 8px', borderRadius: 999,
                    background: 'oklch(0.94 0.06 70)', color: 'oklch(0.40 0.12 60)',
                    fontFamily: 'JetBrains Mono, ui-monospace, monospace',
                    display: 'inline-flex', alignItems: 'center', gap: 4,
                  }}
                >
                  <span aria-hidden>?</span>
                  <span>{p.summary}</span>
                  <button
                    type="button"
                    aria-label="apply"
                    data-testid={`button-apply-${p.id}`}
                    onClick={() => confirmStructuralEdit(p.id)}
                    style={{ marginLeft: 4, padding: '0 4px', border: 'none', background: 'oklch(0.60 0.15 145)', color: 'white', borderRadius: 4, cursor: 'pointer', fontSize: 10 }}
                  >Apply</button>
                  <button
                    type="button"
                    aria-label="dismiss"
                    data-testid={`button-dismiss-${p.id}`}
                    onClick={() => dismissStructuralEdit(p.id)}
                    style={{ marginLeft: 2, padding: 0, border: 'none', background: 'transparent', cursor: 'pointer', color: 'inherit', opacity: 0.6 }}
                  >×</button>
                </span>
              ))}
            </div>
          )}
          {appliedEditsDisplay.length > 0 && (
            <div
              data-testid="workflow-edits-chips"
              style={{
                display: 'flex', flexWrap: 'wrap', gap: 6,
                padding: '6px 12px', borderTop: '1px solid var(--bm-border, oklch(0.92 0.005 260))',
                background: 'oklch(0.99 0.003 260)',
              }}
            >
              {appliedEditsDisplay.slice(-6).map((chip) => (
                <span
                  key={chip.id}
                  data-testid={`workflow-edits-chip-${chip.id}`}
                  className="workflow-edits-chip"
                  style={{
                    fontSize: 11, padding: '2px 8px', borderRadius: 999,
                    background: 'oklch(0.95 0.03 145)', color: 'oklch(0.40 0.10 145)',
                    fontFamily: 'JetBrains Mono, ui-monospace, monospace',
                    display: 'inline-flex', alignItems: 'center', gap: 4,
                  }}
                >
                  <span aria-hidden>✓</span>
                  <span>{chip.summary}</span>
                  <button
                    type="button"
                    aria-label="dismiss"
                    onClick={() => setAppliedEditsDisplay((prev) => prev.filter((c) => c.id !== chip.id))}
                    style={{
                      marginLeft: 2, padding: 0, border: 'none', background: 'transparent',
                      cursor: 'pointer', color: 'inherit', opacity: 0.6, lineHeight: 1,
                    }}
                  >
                    ×
                  </button>
                </span>
              ))}
            </div>
          )}
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
            className="flex-shrink-0 border-l bg-background flex flex-col overflow-hidden relative"
            style={{ width: panelWidth, minWidth: 320, maxWidth: 900 }}
            data-testid="workflow-right-panel"
          >
            {/* Drag handle — grab to resize panel width */}
            <div
              className="absolute top-0 bottom-0 w-1.5 cursor-col-resize hover:bg-primary/20 active:bg-primary/40 transition-colors z-10 select-none"
              style={{ left: -3 }}
              onMouseDown={handlePanelResizeStart}
              title="Drag to resize panel"
            />
            {/* Slim chrome bar — Tutorial + Close only; panel-head owns the workflow title */}
            <div className="flex items-center justify-end gap-2 px-3 py-1 border-b flex-shrink-0" style={{ minHeight: 36 }}>
              <button
                className="tut-btn"
                onClick={startTour}
                title="Start the workflow panel tutorial"
                data-testid="button-start-tour"
              >
                <span style={{ fontSize: 9 }}>▶</span> Tutorial
              </button>
              <button
                onClick={handleClosePanelWorkflow}
                className="rounded-sm p-1 hover:bg-muted"
                aria-label="Close workflow panel"
                data-testid="workflow-panel-close"
              >
                <X className="h-4 w-4" />
              </button>
            </div>

            {/* Panel body — viewer manages its own scroll via panel-body flex */}
            <div className="flex-1 overflow-hidden flex flex-col">
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
                      lastSubmittedParams={extractSubmittedParams(currentRun)}
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
