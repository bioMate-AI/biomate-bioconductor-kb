import { useState, useEffect, useRef, useCallback, useMemo } from "react"
import { CodeExecutionBlock, type ToolBlock, type AgentToolEvent } from "./code-execution-block"
import { ChatMessage, type Message } from "./chat-message"
import { ChatInput } from "./chat-input"
import { TaskList, type TaskItem, type TaskStatus } from "./task-list"
import { TypingIndicator } from "./typing-indicator"
// FileUpload moved into ChatInput component as a popover
import { CompressionDialog, CompressionStatusBadge } from "./compression-dialog"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Separator } from "@/components/ui/separator"
import { Card } from "@/components/ui/card"
import { useMutation } from "@tanstack/react-query"
import { apiRequest } from "@/lib/queryClient"
import { chatHistoryService } from "@/lib/chat-history"
import { emitUxEvent } from "@/lib/ux-telemetry"
import { getChatAsyncGuidance } from "@/lib/async-guidance"
import { useNetworkStatus } from "@/lib/network-status"
import type { ChatSession, ExecutionRun } from "@shared/schema"
import { analytics } from "@/lib/analytics"
import {
  ChevronRight,
  ChevronDown,
  Loader2,
  CheckCircle,
  Check,
  Clock,
  AlertTriangle,
  Settings
} from "lucide-react"
import { cn } from "@/lib/utils"

interface WorkflowProgress {
  id: string
  title: string
  description: string
  status: 'running' | 'completed' | 'pending' | 'error'
  progress: number
  steps: Array<{
    id: string
    name: string
    status: 'running' | 'completed' | 'pending' | 'error'
    duration?: string
  }>
}

interface ChatInterfaceProps {
  chatSession?: ChatSession | null
  onSendMessage?: (message: string) => void
  isTyping?: boolean
  className?: string
  onWorkflowGenerated?: (workflow: any) => void
  onChatUpdated?: (session: ChatSession) => void
  activeWorkflow?: WorkflowProgress | null
  showProgress?: boolean
  onToggleProgress?: () => void
  // Workflow execution props for inline artifacts
  onRunWorkflow?: (workflow: any, steps: any[]) => void
  onStopWorkflow?: () => void
  onPauseWorkflow?: () => void
  onResumeWorkflow?: () => void
  onParameterChange?: (stepId: string, params: Record<string, any>) => void
  isWorkflowRunning?: boolean
  workflowProgress?: number
  workflowError?: string | null
  currentExecutionRun?: ExecutionRun | null
  externalPromptRequest?: { id: number; prompt: string } | null
  onExternalPromptConsumed?: (id: number) => void
  focusedRunId?: string | null
  runAnchorRequestId?: number
  // Right panel
  onOpenWorkflowInPanel?: (messageId: string, workflow: any) => void
  panelWorkflowMessageId?: string | null
  /** Whether the workflow panel is currently open. When true, all inline
   *  workflow cards (viewer, pipeline, chain) are suppressed in chat messages
   *  so workflow UI lives exclusively in the panel. */
  isPanelOpen?: boolean
  onRegisterSetDraft?: (setter: (draft: string) => void) => void
}

// ── Onboarding welcome ────────────────────────────────────────────────────────
// Step 1: pick domains (all 14 + free-text "Other")
// Step 2: pick topics per selected domain (+ free-text "Other" per domain)
// "Next" saves profile then closes welcome — user enters the platform.
// Suggested queries are deferred until verified (see backend/experiments/verified_queries/).

import { DOMAIN_TAXONOMY, DOMAIN_LABELS } from "@/components/domain-profile-selector"

const ONBOARDING_DONE_KEY = 'biomate_onboarding_done'

function OnboardingWelcome({
  onComplete,
  visible,
}: {
  onComplete: () => void
  visible: boolean
}) {
  const [step, setStep] = useState<"domains" | "topics">("domains")
  const [selectedDomains, setSelectedDomains] = useState<Set<string>>(new Set())
  const [otherDomain, setOtherDomain] = useState("")
  const [selectedTopics, setSelectedTopics] = useState<Set<string>>(new Set())
  const [otherTopics, setOtherTopics] = useState<Record<string, string>>({}) // domainKey → free text
  const [saving, setSaving] = useState(false)

  if (!visible) return null

  const domainKeys = Object.keys(DOMAIN_TAXONOMY)
  const domainsArray = Array.from(selectedDomains)

  const toggleDomain = (key: string) => {
    setSelectedDomains(prev => {
      const next = new Set(prev)
      if (next.has(key)) {
        next.delete(key)
        const removed = DOMAIN_TAXONOMY[key] ?? []
        const stillValid = new Set(Array.from(next).flatMap(d => DOMAIN_TAXONOMY[d] ?? []))
        setSelectedTopics(prev2 => {
          const next2 = new Set(prev2)
          for (const t of removed) { if (!stillValid.has(t)) next2.delete(t) }
          return next2
        })
      } else {
        next.add(key)
      }
      return next
    })
  }

  const toggleTopic = (topic: string) => {
    setSelectedTopics(prev => {
      const next = new Set(prev)
      next.has(topic) ? next.delete(topic) : next.add(topic)
      return next
    })
  }

  const handleNext = async () => {
    setSaving(true)
    // Collect final domains + topics including free-text "Others"
    const customDomains = otherDomain.trim()
      ? otherDomain.split(',').map(s => s.trim()).filter(Boolean)
      : []
    const allDomains = [...domainsArray, ...customDomains]

    const customTopics = Object.values(otherTopics)
      .flatMap(v => v.split(',').map(s => s.trim()).filter(Boolean))
    const allTopics = [...Array.from(selectedTopics), ...customTopics]

    // Best-effort save — never block the user
    try {
      await fetch('/api/user/domain-profile', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        credentials: 'include',
        body: JSON.stringify({ domains: allDomains, topics: allTopics }),
      })
    } catch { /* non-fatal */ }

    localStorage.setItem(ONBOARDING_DONE_KEY, '1')
    setSaving(false)
    onComplete()
  }

  // ── Step 1: domain selection ────────────────────────────────────────────────
  if (step === "domains") {
    return (
      <div data-testid="onboarding-welcome" className="flex flex-col items-center justify-center min-h-[60vh] px-4 py-8">
        <div className="w-full max-w-2xl">
          <div className="mb-6 text-center">
            <h2 className="text-2xl font-semibold mb-1">What would you like to analyze?</h2>
            <p className="text-sm text-muted-foreground">
              Select your research areas — BioMate will prioritise relevant workflows.
            </p>
          </div>

          <div className="grid grid-cols-2 gap-2 mb-4">
            {domainKeys.map(key => {
              const isSelected = selectedDomains.has(key)
              return (
                <button
                  key={key}
                  type="button"
                  data-testid={`onboarding-domain-btn-${key}`}
                  onClick={() => toggleDomain(key)}
                  className={cn(
                    "flex items-center gap-3 rounded-lg border px-4 py-2.5 text-left transition-colors text-sm",
                    "hover:border-primary/60 hover:bg-primary/5",
                    isSelected
                      ? "border-primary bg-primary/10 text-primary font-medium"
                      : "border-border bg-background"
                  )}
                >
                  <div className={cn(
                    "flex h-4 w-4 shrink-0 items-center justify-center rounded border",
                    isSelected ? "border-primary bg-primary text-primary-foreground" : "border-muted-foreground"
                  )}>
                    {isSelected && <Check className="h-3 w-3" />}
                  </div>
                  {DOMAIN_LABELS[key]}
                </button>
              )
            })}
          </div>

          {/* Other domain free-text */}
          <div className="mb-6">
            <input
              type="text"
              placeholder="Other domain (e.g. spatial genomics, immunology) — separate with commas"
              value={otherDomain}
              onChange={e => setOtherDomain(e.target.value)}
              className="w-full rounded-lg border border-border bg-background px-4 py-2 text-sm placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-primary/40"
            />
          </div>

          <div className="flex items-center justify-between">
            <span className="text-xs text-muted-foreground">
              {selectedDomains.size + (otherDomain.trim() ? 1 : 0)} selected
            </span>
            <div className="flex gap-2">
              <Button variant="ghost" size="sm" onClick={() => { localStorage.setItem(ONBOARDING_DONE_KEY, '1'); onComplete() }}>
                Skip
              </Button>
              <Button
                onClick={() => setStep("topics")}
                disabled={selectedDomains.size === 0 && !otherDomain.trim()}
                className="gap-2"
              >
                Continue <ChevronRight className="h-4 w-4" />
              </Button>
            </div>
          </div>
        </div>
      </div>
    )
  }

  // ── Step 2: topic selection ─────────────────────────────────────────────────
  return (
    <div data-testid="onboarding-welcome" className="flex flex-col items-center justify-center min-h-[60vh] px-4 py-8">
      <div className="w-full max-w-2xl">
        <div className="mb-6 text-center">
          <h2 className="text-2xl font-semibold mb-1">Which topics interest you?</h2>
          <p className="text-sm text-muted-foreground">
            Optional — helps BioMate surface the most relevant workflows for your work.
          </p>
        </div>

        <div className="space-y-5 mb-6 max-h-[50vh] overflow-y-auto pr-1">
          {domainsArray.map(domainKey => (
            <div key={domainKey}>
              <h4 className="text-xs font-semibold uppercase tracking-wider text-muted-foreground mb-2">
                {DOMAIN_LABELS[domainKey]}
              </h4>
              <div className="flex flex-wrap gap-2 mb-2">
                {(DOMAIN_TAXONOMY[domainKey] ?? []).map(topic => {
                  const isSel = selectedTopics.has(topic)
                  return (
                    <button
                      key={topic}
                      type="button"
                      onClick={() => toggleTopic(topic)}
                      className={cn(
                        "inline-flex items-center gap-1.5 rounded-full border px-3 py-1 text-xs transition-colors",
                        "hover:border-primary/60 hover:bg-primary/5",
                        isSel
                          ? "border-primary bg-primary/10 text-primary font-medium"
                          : "border-border text-muted-foreground"
                      )}
                    >
                      {isSel && <Check className="h-3 w-3 shrink-0" />}
                      {topic}
                    </button>
                  )
                })}
              </div>
              {/* Per-domain "Other" free-text */}
              <input
                type="text"
                placeholder={`Other ${DOMAIN_LABELS[domainKey]} topics — separate with commas`}
                value={otherTopics[domainKey] ?? ""}
                onChange={e => setOtherTopics(prev => ({ ...prev, [domainKey]: e.target.value }))}
                className="w-full rounded-lg border border-border bg-background px-3 py-1.5 text-xs placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-primary/40"
              />
            </div>
          ))}

          {/* Other domain section (if user typed a custom domain) */}
          {otherDomain.trim() && (
            <div>
              <h4 className="text-xs font-semibold uppercase tracking-wider text-muted-foreground mb-2">
                Other: {otherDomain}
              </h4>
              <input
                type="text"
                placeholder="Specific topics within this area — separate with commas"
                value={otherTopics['__other__'] ?? ""}
                onChange={e => setOtherTopics(prev => ({ ...prev, '__other__': e.target.value }))}
                className="w-full rounded-lg border border-border bg-background px-3 py-1.5 text-xs placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-primary/40"
              />
            </div>
          )}
        </div>

        <div className="flex items-center justify-between">
          <Button variant="ghost" size="sm" onClick={() => setStep("domains")}>Back</Button>
          <Button onClick={handleNext} disabled={saving} className="gap-2">
            {saving ? <Loader2 className="h-4 w-4 animate-spin" /> : null}
            Next — Enter BioMate <ChevronRight className="h-4 w-4" />
          </Button>
        </div>
      </div>
    </div>
  )
}

// ─────────────────────────────────────────────────────────────────────────────

export function ChatInterface({
  chatSession,
  onSendMessage = (msg) => console.log('Send message:', msg),
  isTyping = false,
  className,
  onWorkflowGenerated = (workflow) => console.log('Workflow generated:', workflow),
  onChatUpdated,
  activeWorkflow,
  showProgress,
  onToggleProgress,
  onRunWorkflow,
  onStopWorkflow,
  onPauseWorkflow,
  onResumeWorkflow,
  onParameterChange,
  isWorkflowRunning = false,
  workflowProgress = 0,
  workflowError,
  currentExecutionRun,
  externalPromptRequest = null,
  onExternalPromptConsumed,
  focusedRunId = null,
  runAnchorRequestId = 0,
  onOpenWorkflowInPanel,
  panelWorkflowMessageId,
  isPanelOpen = false,
  onRegisterSetDraft,
}: ChatInterfaceProps) {
  const [isTypingLocal, setIsTypingLocal] = useState(false)
  // Soft query queue: messages submitted while AI is responding are held here
  // and auto-submitted one-at-a-time once each response completes.
  const [pendingMessages, setPendingMessages] = useState<string[]>([])
  const pendingMessagesRef = useRef<string[]>([])
  pendingMessagesRef.current = pendingMessages

  const abortControllerRef = useRef<AbortController | null>(null)
  const scrollRef = useRef<HTMLDivElement>(null)
  const messagesEndRef = useRef<HTMLDivElement>(null)
  const [focusedAnchorMessageId, setFocusedAnchorMessageId] = useState<string | null>(null)
  const [highlightedAnchorMessageId, setHighlightedAnchorMessageId] = useState<string | null>(null)

  // Stop dialog state
  const [showStopDialog, setShowStopDialog] = useState(false)
  // Snapshot of queue length at the moment stop was clicked (avoids stale reactive read)
  const [stopDialogQueueCount, setStopDialogQueueCount] = useState(0)

  // LangGraph task tracking
  const [langgraphTasks, setLanggraphTasks] = useState<TaskItem[]>([])
  const langgraphTasksRef = useRef<TaskItem[]>([])
  langgraphTasksRef.current = langgraphTasks

  // Compression state
  const [showCompressionDialog, setShowCompressionDialog] = useState(false)
  const [isCompressing, setIsCompressing] = useState(false)
  const [currentTokenCount, setCurrentTokenCount] = useState(0)
  const [compressionDismissed, setCompressionDismissed] = useState(false)
  const [onboardingDone, setOnboardingDone] = useState(() =>
    typeof window !== 'undefined' && localStorage.getItem(ONBOARDING_DONE_KEY) === '1'
  )
  const { isOnline } = useNetworkStatus()
  
  // Use messages from chat session or empty array if no session
  const displayMessages = chatSession?.messages || []
  // Hide typing indicator once streaming content has started appearing in the placeholder
  const lastMsg = displayMessages[displayMessages.length - 1]
  const streamingHasContent = (isTyping || isTypingLocal) && lastMsg?.role === 'assistant' && !!lastMsg?.content?.trim()
  const displayTyping = (isTyping || isTypingLocal) && !streamingHasContent
  const latestAssistantMessageId = [...displayMessages]
    .reverse()
    .find((msg) => msg.role !== "user")?.id

  // Debug: Log message count
  useEffect(() => {
    console.log('[ChatInterface] displayMessages count:', displayMessages.length)
    console.log('[ChatInterface] displayMessages IDs:', displayMessages.map(m => m.id))
  }, [displayMessages])

  // Auto-scroll to bottom when messages change
  useEffect(() => {
    if (messagesEndRef.current) {
      messagesEndRef.current.scrollIntoView({ behavior: 'smooth' })
    }
  }, [displayMessages, displayTyping])

  // Anchor chat view to the workflow artifact associated with the focused run.
  useEffect(() => {
    if (!focusedRunId) {
      setFocusedAnchorMessageId(null)
      setHighlightedAnchorMessageId(null)
      return
    }
    if (displayMessages.length === 0) return

    const candidateInvocationIds = new Set<string>([focusedRunId])
    if (currentExecutionRun?.id) {
      candidateInvocationIds.add(currentExecutionRun.id)
    }
    if (currentExecutionRun?.execution?.galaxyInvocationId) {
      candidateInvocationIds.add(currentExecutionRun.execution.galaxyInvocationId)
    }

    const reversedMessages = [...displayMessages].reverse()
    const targetMessage =
      reversedMessages.find((message) => {
        if (message.role !== "assistant") return false
        if (message.invocationId && candidateInvocationIds.has(message.invocationId)) return true
        return false
      }) ||
      reversedMessages.find((message) => {
        if (message.role !== "assistant") return false
        if (message.metadata?.type !== "workflow" || !message.metadata?.workflow) return false
        if (!currentExecutionRun?.workflowName) return false
        return (
          message.metadata.workflow.name === currentExecutionRun.workflowName ||
          message.metadata.workflow.workflow_name === currentExecutionRun.workflowName
        )
      })

    if (!targetMessage) {
      setFocusedAnchorMessageId(null)
      return
    }

    setFocusedAnchorMessageId(targetMessage.id)
    setHighlightedAnchorMessageId(targetMessage.id)

    const scrollToTarget = () => {
      const artifactElement = document.getElementById(`workflow-artifact-anchor-${targetMessage.id}`)
      const messageElement = document.getElementById(`chat-message-anchor-${targetMessage.id}`)
      const targetElement = artifactElement || messageElement
      targetElement?.scrollIntoView({ behavior: "smooth", block: "center" })
    }

    if (typeof window !== "undefined" && typeof window.requestAnimationFrame === "function") {
      window.requestAnimationFrame(scrollToTarget)
    } else {
      scrollToTarget()
    }

    const highlightTimer = setTimeout(() => {
      setHighlightedAnchorMessageId((prev) => (prev === targetMessage.id ? null : prev))
    }, 2200)

    return () => {
      clearTimeout(highlightTimer)
    }
  }, [
    focusedRunId,
    runAnchorRequestId,
    currentExecutionRun?.id,
    currentExecutionRun?.execution?.galaxyInvocationId,
    currentExecutionRun?.workflowName,
    displayMessages,
  ])

  // Monitor token count and trigger compression dialog
  useEffect(() => {
    if (!chatSession || !displayMessages.length) {
      setCurrentTokenCount(0)
      return
    }

    // Calculate current token count using chat history service
    const session = chatHistoryService.getSession(chatSession.id)
    if (!session) return

    const tokenCount = session.totalTokens || 0
    setCurrentTokenCount(tokenCount)

    console.log('[ChatInterface] Token monitoring:', {
      sessionId: chatSession.id,
      tokenCount,
      percentage: ((tokenCount / 200000) * 100).toFixed(1) + '%',
      messageCount: displayMessages.length
    })

    // Check if compression dialog should be shown
    const percentage = (tokenCount / 200000) * 100

    if (percentage >= 80 && !showCompressionDialog && !compressionDismissed) {
      // Critical: Show dialog immediately at 80%
      console.log('[ChatInterface] Token count critical (80%+), showing compression dialog')
      setShowCompressionDialog(true)
    } else if (percentage >= 70 && !showCompressionDialog && !compressionDismissed) {
      // Warning: Show dialog at 70%
      console.log('[ChatInterface] Token count warning (70%+), showing compression dialog')
      setShowCompressionDialog(true)
    }
  }, [displayMessages, chatSession, showCompressionDialog, compressionDismissed])

  interface ChatRequestPayload {
    content: string
    sessionId: string
    placeholderId: string
  }

  const updateMessageInSession = (sessionId: string, messageId: string, updates: Partial<Message>) => {
    const session = chatHistoryService.getSession(sessionId)
    if (!session) return
    const updatedMessages = session.messages.map((msg) =>
      msg.id === messageId ? { ...msg, ...updates } : msg
    )
    const updatedSession = chatHistoryService.updateSession(sessionId, { messages: updatedMessages })
    if (updatedSession && onChatUpdated) {
      onChatUpdated(updatedSession)
    }
  }

  // Galaxy Chat API integration with full hybrid intelligence
  // Uses /api/chat which provides: intent analysis, tool search, dataset RAG, workflow generation
  const chatMutation = useMutation({
    mutationFn: async ({ content, sessionId, placeholderId }: ChatRequestPayload) => {
      const session = chatHistoryService.getSession(sessionId)
      const previousMessages = (session?.messages || [])
        .filter((m) => (m.role === "user" || m.role === "assistant") && !!m.content?.trim())
        .slice(-4)
        .map((m) => ({ role: m.role, content: m.content }))
      abortControllerRef.current = new AbortController()
      const response = await fetch('/api/chat/stream', {
        method: 'POST',
        signal: abortControllerRef.current.signal,
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          message: content,
          stream: true,
          context: {
            previousMessages,
            // Include session ID for memory integration
            ...(sessionId && { memorySessionId: sessionId }),
          }
        })
      })
      if (!response.ok) {
        throw new Error(`Chat API error: ${response.statusText}`)
      }
      if (!response.body) {
        throw new Error('Streaming response body unavailable')
      }

      const reader = response.body.getReader()
      const decoder = new TextDecoder()
      let buffer = ''
      let accumulatedText = ''
      let finalPayload: any = null
      // Agent tool blocks accumulate during streaming
      const toolBlocksMap = new Map<string, ToolBlock>()

      try {
        while (true) {
          const { done, value } = await reader.read()
          if (done) break
          buffer += decoder.decode(value, { stream: true })

          while (true) {
            const eventBoundary = buffer.indexOf('\n\n')
            if (eventBoundary === -1) break

            const rawEvent = buffer.slice(0, eventBoundary)
            buffer = buffer.slice(eventBoundary + 2)

            const lines = rawEvent.split('\n')
            let eventName = 'message'
            const dataLines: string[] = []
            for (const line of lines) {
              if (line.startsWith('event:')) eventName = line.slice(6).trim()
              if (line.startsWith('data:')) dataLines.push(line.slice(5).trim())
            }

            const payloadText = dataLines.join('\n')
            if (!payloadText) continue
            let payload: any
            try {
              payload = JSON.parse(payloadText)
            } catch (parseErr: any) {
              console.error('[ChatInterface] SSE JSON parse error for event:', eventName, parseErr?.message, payloadText.slice(0, 100))
              continue
            }

            if (eventName === 'delta' && typeof payload.text === 'string') {
              accumulatedText += payload.text
              updateMessageInSession(sessionId, placeholderId, { content: accumulatedText })
            } else if (eventName === 'tool_event') {
              const event = payload as AgentToolEvent
              const id = event.tool_use_id
              if (!toolBlocksMap.has(id)) {
                toolBlocksMap.set(id, { tool_use_id: id, name: event.name })
              }
              const block = toolBlocksMap.get(id)!
              if (event.type === 'tool_call') block.call = event
              else if (event.type === 'tool_result') block.result = event
              // Persist tool blocks into the placeholder message metadata (merge-safe)
              const currentSession = chatHistoryService.getSession(sessionId)
              const currentMsg = currentSession?.messages.find(m => m.id === placeholderId)
              updateMessageInSession(sessionId, placeholderId, {
                metadata: { ...(currentMsg?.metadata ?? {}), toolBlocks: Array.from(toolBlocksMap.values()) }
              })
            } else if (eventName === 'final') {
              console.log('[ChatInterface] SSE final event received, workflow:', !!payload.workflow, 'keys:', Object.keys(payload))
              // Merge accumulated tool blocks into final payload
              if (toolBlocksMap.size > 0) {
                finalPayload = { ...payload, toolBlocks: Array.from(toolBlocksMap.values()) }
              } else {
                finalPayload = payload
              }
            } else if (eventName === 'error') {
              throw new Error(payload.message || 'Streaming chat failed')
            }
          }
        }
        console.log('[ChatInterface] SSE stream complete, finalPayload set:', !!finalPayload)
      } catch (err: any) {
        console.error('[ChatInterface] SSE read error:', err?.name, err?.message)
        if (err?.name === 'AbortError') {
          // Stream was stopped by user — not an error, just return what we have
          return finalPayload ?? { message: accumulatedText, aborted: true }
        }
        throw err
      }

      if (!finalPayload) {
        console.error('[ChatInterface] No final payload received from stream')
        throw new Error('No final payload received from stream')
      }
      return finalPayload
    },
    onSuccess: async (data, variables) => {
      console.log('[ChatInterface] API Response:', data)

      // Handle /api/chat response format (full hybrid intelligence)
      // Response structure: { response, suggestions, workflow, thinking_content, metadata }
      let workflowData = data.workflow?.workflow_ga || data.workflow;
      let workflowSuccess = !!data.workflow?.success || (data.workflow && !data.workflow.error);

      // Check if workflow was generated
      if (data.workflow && !workflowSuccess) {
        console.warn('[ChatInterface] Workflow generation returned but failed:', data.workflow.error || data.workflow.message);
        workflowData = null;
      }

      // Use the natural language response from /api/chat
      // This includes tool recommendations, dataset suggestions, etc.
      let workflowInfo: string = data.response || '';
      const diagnostics = data.metadata?.workflowGenerationDiagnostics;
      const hasFailureDiagnostics = !!diagnostics?.failed;
      const failureNarrativePattern =
        /workflow generation failed|could not build (a|the) runnable workflow|domain alignment|recovery plan|targeted follow-up questions/i;
      const looksLikeNarrativeFailure =
        typeof data.response === 'string' && failureNarrativePattern.test(data.response);
      const shouldRenderCollaborativeFailure =
        !workflowSuccess && (!!data.workflow || hasFailureDiagnostics || looksLikeNarrativeFailure);

      // If workflow was generated, append workflow-specific info
      if (workflowSuccess && workflowData) {
        // Response already contains helpful context from Claude
        if (!workflowInfo.toLowerCase().includes('workflow')) {
          workflowInfo += '\n\n✅ I\'ve generated a workflow for you based on your request.';
        }
        if (data.workflow?.needs_user_feedback) {
          workflowInfo += `\n\n⚠️ ${data.workflow?.feedback_prompt || 'Confidence is not high enough yet. Please review and provide corrections before execution.'}`;
        }
      } else if (shouldRenderCollaborativeFailure) {
        const reasons = Array.isArray(diagnostics?.likelyReasons) ? diagnostics.likelyReasons : [];
        const actions = Array.isArray(diagnostics?.recommendedActions) ? diagnostics.recommendedActions : [];
        const followUps = Array.isArray(diagnostics?.followUpQuestions) ? diagnostics.followUpQuestions : [];
        const reasonText = reasons.length > 0 ? `\n\nLikely reasons:\n- ${reasons.join('\n- ')}` : '';
        const actionText = actions.length > 0 ? `\n\nSuggested next actions:\n- ${actions.join('\n- ')}` : '';
        const followUpText =
          followUps.length > 0
            ? `\n\nTo continue collaboratively, please answer:\n- ${followUps.join('\n- ')}`
            : '';
        const baseFailureText = /workflow generation is currently unavailable/i.test(data.response || '')
          ? (data.response || '')
          : `${data.response || ''}\n\n⚠️ **Workflow generation is currently unavailable for this request.**`;
        workflowInfo =
          baseFailureText +
          reasonText +
          actionText +
          followUpText;
      } else if (!workflowInfo) {
        // Empty response — likely a backend initialization error during workflow generation.
        // Emit an informative recovery message so classifiers and users can act on it.
        workflowInfo = '⚠️ **Workflow generation failed — no response received from the AI service.** ' +
          'This may be a temporary initialization issue. Please try your request again, or rephrase your query. ' +
          'Suggested recovery steps:\n- Retry the same message\n- Simplify your request\n- Check that the backend service is running';
      }

      // Convert workflow_ga.steps object to array
      const stepsArray = workflowData?.steps ?
        Object.values(workflowData.steps).map((step: any) => ({
          name: step.name || step.tool_id || step.title || 'Unknown step',
          tool_id: step.tool_id || step.tool,
          annotation: step.annotation || step.description
        })) : []

      console.log('[ChatInterface] Steps array:', stepsArray)

      const aiMessage: Message = {
        id: variables.placeholderId,
        content: workflowInfo,
        role: "assistant",
        timestamp: new Date(),
        // Include invocationId from API response to trigger output viewers
        invocationId: data.invocationId,
        // Use suggestions from /api/chat or fallbacks
        suggestions: data.suggestions || (data.workflow?.needs_user_feedback
          ? ["This domain looks correct", "Use different domain/tools", "Regenerate with stricter constraints", "Show alternative workflows"]
          : workflowSuccess
          ? ["Open in Workflow Builder", "Show details", "Generate another"]
          : data.metadata?.workflowGenerationDiagnostics?.followUpQuestions?.slice?.(0, 3) ||
            ["Try again with different request", "Provide required inputs/formats", "Regenerate with tighter constraints"]),
        metadata: {
          type: workflowSuccess ? 'workflow' : (data.researchResponse ? 'research_response' : 'text'),
          research_response: data.researchResponse || null,
          workflow: workflowData,
          steps: stepsArray,
          confidence: data.workflow?.confidence || data.metadata?.workflowSuggestion?.confidence,
          source: data.workflow?.source || 'chat',
          needsUserFeedback: !!data.workflow?.needs_user_feedback,
          feedbackPrompt: data.workflow?.feedback_prompt,
          candidateWorkflows: data.workflow?.candidate_workflows || [],
          selectedTrial: data.workflow?.selected_trial,
          trialCount: data.workflow?.trial_count,
          isDemo: false,
          generationFailed: data.workflow && !workflowSuccess,
          failureReason: data.workflow?.error || data.workflow?.message,
          // Thinking mode support from /api/chat
          thinking_content: data.thinking_content,
          thinking_level: data.thinking_level,
          // Tool and dataset recommendations from hybrid intelligence
          recommendedTools: data.metadata?.recommendedTools || [],
          recommendedDatasets: data.metadata?.recommendedDatasets || [],
          workflowSuggestion: data.metadata?.workflowSuggestion,
          sources: data.metadata?.sources || {},
          memoryUsed: data.metadata?.memoryUsed || false,
          domainGuard: data.metadata?.domainGuard,
          episodeId: data.episodeId,
          // Validation info from workflow if available
          validation: data.workflow?.validation || { is_valid: true, issues: [], warnings: [] },
          tool_installation: data.workflow?.tool_installation || { success: true, failed_tools: [] },
          // Prerequisites validation (input data, parameters needed before execution)
          prerequisitesValidation: data.prerequisitesValidation || null
        }
      }

      console.log('[ChatInterface] Created AI message:', {
        id: aiMessage.id,
        invocationId: aiMessage.invocationId,
        metadata: aiMessage.metadata,
        hasWorkflow: !!aiMessage.metadata?.workflow,
        metadataType: aiMessage.metadata?.type
      })

      // Add message to chat session (create one if it doesn't exist)
      if (variables.sessionId) {
        console.log('[ChatInterface] Updating streaming placeholder:', variables.placeholderId)
        updateMessageInSession(variables.sessionId, variables.placeholderId, aiMessage)

        // Also add workflow to session.workflows if workflow was generated
        if (workflowSuccess && workflowData && stepsArray.length > 0) {
          console.log('[ChatInterface] Extracting workflow to session.workflows')
          const workflowSteps = stepsArray.map((step: any, index: number) => ({
            id: `step_${index}`,
            title: step.name || step.tool_id || `Step ${index + 1}`,
            tool: step.tool_id || step.name || 'Unknown Tool',
            description: step.annotation || '',
            status: 'pending' as const,
            complexity: 'intermediate' as const,
            estimatedTime: '5 min',
            parameters: {},
            inputs: [],
            outputs: [],
          }))
          chatHistoryService.addWorkflow(variables.sessionId, workflowSteps)
        }
      } else {
        console.log('[ChatInterface] No session, creating new one')
        // Auto-create session if it doesn't exist (e.g., in test environment)
        const newSession = chatHistoryService.createNewSession()
        chatHistoryService.addMessage(newSession.id, aiMessage)

        // Also add workflow to session.workflows if workflow was generated
        if (workflowSuccess && workflowData && stepsArray.length > 0) {
          console.log('[ChatInterface] Extracting workflow to new session.workflows')
          const workflowSteps = stepsArray.map((step: any, index: number) => ({
            id: `step_${index}`,
            title: step.name || step.tool_id || `Step ${index + 1}`,
            tool: step.tool_id || step.name || 'Unknown Tool',
            description: step.annotation || '',
            status: 'pending' as const,
            complexity: 'intermediate' as const,
            estimatedTime: '5 min',
            parameters: {},
            inputs: [],
            outputs: [],
          }))
          chatHistoryService.addWorkflow(newSession.id, workflowSteps)
        }

        const updatedSession = chatHistoryService.getSession(newSession.id)
        console.log('[ChatInterface] New session created with', updatedSession?.messages.length, 'messages')
        if (updatedSession && onChatUpdated) {
          onChatUpdated(updatedSession)
        }
      }
      setIsTypingLocal(false)

      // Trigger workflow builder display
      if (workflowSuccess && workflowData) {
        emitUxEvent('workflow.generated', {
          sessionId: chatSession?.id,
          invocationId: data.invocationId,
        })
        onWorkflowGenerated(workflowData)
      }
    },
    onError: (error, variables) => {
      console.error('[ChatInterface] API Error:', error)
      console.error('[ChatInterface] Error details:', {
        message: error.message,
        name: error.name,
        stack: error.stack
      })

      const errorMessage = error.message || 'Unknown error occurred';
      const guidance = getChatAsyncGuidance(errorMessage, { isOnline });
      const isNetworkError = guidance.isNetworkRelated;
      const userFriendlyError = `⚠️ **${guidance.title}**\n\n` +
        `**Reason:** ${guidance.reason}\n\n` +
        `**Try again:** ${guidance.retry}\n\n` +
        `**Report issue:** ${guidance.escalation}`;

      const aiMessage: Message = {
        id: (Date.now() + 1).toString(),
        content: userFriendlyError,
        role: "assistant",
        timestamp: new Date(),
        suggestions: ["Try again", "Refine my request", "Check server status", "Report issue"],
        metadata: {
          type: 'error',
          errorType: isNetworkError ? 'network' : 'api',
          errorMessage: errorMessage,
        }
      }

      emitUxEvent('workflow.error_shown', {
        sessionId: chatSession?.id,
        errorType: isNetworkError ? 'network' : 'api',
        errorMessage: errorMessage,
      })

      // Add error message to chat session
      if (variables?.sessionId && variables?.placeholderId) {
        updateMessageInSession(variables.sessionId, variables.placeholderId, aiMessage)
      }
      setIsTypingLocal(false)

      // Do not emit demo workflows on error; keep real-only behavior.
    }
  })

  const shouldGenerateWorkflow = (response: string): boolean => {
    const workflowKeywords = [
      'workflow', 'pipeline', 'analysis', 'steps', 'process',
      'RNA-seq', 'variant calling', 'genome assembly', 'alignment',
      'quality control', 'differential expression'
    ]
    return workflowKeywords.some(keyword => 
      response.toLowerCase().includes(keyword.toLowerCase())
    )
  }

  const generateWorkflowFromResponse = (response: string) => {
    // Generate workflow based on response content with concrete steps
    const detectedType = detectWorkflowTypeFromResponse(response)
    return {
      id: `workflow-${Date.now()}`,
      title: getWorkflowTitleFromType(detectedType),
      description: "Workflow generated from conversation",
      type: detectedType,
      steps: getStepsForType(detectedType)
    }
  }

  const detectWorkflowTypeFromResponse = (response: string): string => {
    const msg = response.toLowerCase()

    // Biomni tools - database queries
    if (msg.includes('uniprot') || msg.includes('protein') && msg.includes('query')) return 'database-query'
    if (msg.includes('ncbi') || msg.includes('genbank') || msg.includes('entrez')) return 'database-query'

    // Biomni tools - genomics/bioinformatics
    if (msg.includes('gene set enrichment') || msg.includes('gsea') || msg.includes('pathway')) return 'enrichment-analysis'
    if (msg.includes('primer') || msg.includes('pcr')) return 'primer-design'
    if (msg.includes('cell type annotation') || msg.includes('scrna') || msg.includes('single-cell')) return 'scrna-analysis'

    // Biomni tools - bioimaging
    if (msg.includes('segment') && (msg.includes('cell') || msg.includes('nuclei') || msg.includes('image'))) return 'cell-segmentation'
    if (msg.includes('image registration') || msg.includes('align') && msg.includes('image')) return 'image-registration'
    if (msg.includes('microscopy') || msg.includes('fluorescence')) return 'bioimaging'

    // Biomni tools - pharmacology
    if (msg.includes('drug') && (msg.includes('target') || msg.includes('interaction'))) return 'drug-target'
    if (msg.includes('smiles') || msg.includes('compound')) return 'drug-target'

    // Standard bioinformatics workflows
    if (msg.includes('rna-seq') || msg.includes('transcriptom')) return 'rna-seq'
    if (msg.includes('variant') || msg.includes('snp') || msg.includes('indel')) return 'variant-calling'
    if (msg.includes('genome') && msg.includes('assembl')) return 'genome-assembly'
    if (msg.includes('chip-seq') || msg.includes('chipseq')) return 'chip-seq'
    if (msg.includes('quality') || msg.includes('qc')) return 'quality-control'

    return 'custom' // Default to custom workflow instead of hardcoded RNA-seq
  }

  const getWorkflowTitleFromType = (type: string): string => {
    switch (type) {
      // Biomni workflow types
      case 'database-query': return 'Database Query Workflow'
      case 'enrichment-analysis': return 'Gene Set Enrichment Analysis'
      case 'primer-design': return 'PCR Primer Design Workflow'
      case 'scrna-analysis': return 'scRNA-seq Cell Type Annotation'
      case 'cell-segmentation': return 'Cell Segmentation Workflow'
      case 'image-registration': return 'Image Registration Pipeline'
      case 'bioimaging': return 'Bioimaging Analysis Workflow'
      case 'drug-target': return 'Drug-Target Interaction Prediction'
      case 'custom': return 'Custom Analysis Workflow'
      // Standard bioinformatics workflow types
      case 'rna-seq': return 'RNA-seq Analysis Pipeline'
      case 'variant-calling': return 'Variant Calling Workflow'
      case 'genome-assembly': return 'Genome Assembly Pipeline'
      case 'chip-seq': return 'ChIP-seq Analysis Workflow'
      case 'quality-control': return 'Data Quality Control Pipeline'
      default: return 'Bioinformatics Analysis Workflow'
    }
  }

  const getStepsForType = (type: string) => {
    switch (type) {
      // Biomni workflow types
      case 'database-query':
        return [
          {
            id: 'step1',
            title: 'Database Query',
            description: 'Query protein/gene database for information',
            tool: 'UniProt Query',
            complexity: 'simple',
            estimatedTime: '1 min'
          }
        ]

      case 'enrichment-analysis':
        return [
          {
            id: 'step1',
            title: 'Gene Set Enrichment',
            description: 'Analyze gene set enrichment across pathways',
            tool: 'GSEA',
            complexity: 'intermediate',
            estimatedTime: '5 min'
          }
        ]

      case 'primer-design':
        return [
          {
            id: 'step1',
            title: 'Primer Design',
            description: 'Design PCR primers for target sequence',
            tool: 'Primer3',
            complexity: 'simple',
            estimatedTime: '2 min'
          }
        ]

      case 'scrna-analysis':
        return [
          {
            id: 'step1',
            title: 'Cell Type Annotation',
            description: 'Annotate cell types in scRNA-seq data',
            tool: 'scRNA Annotator',
            complexity: 'complex',
            estimatedTime: '10 min'
          }
        ]

      case 'cell-segmentation':
        return [
          {
            id: 'step1',
            title: 'Cell Segmentation',
            description: 'Segment cells/nuclei in microscopy images',
            tool: 'CellProfiler',
            complexity: 'intermediate',
            estimatedTime: '5 min'
          }
        ]

      case 'image-registration':
        return [
          {
            id: 'step1',
            title: 'Image Registration',
            description: 'Align images to reference',
            tool: 'Image Aligner',
            complexity: 'intermediate',
            estimatedTime: '3 min'
          }
        ]

      case 'drug-target':
        return [
          {
            id: 'step1',
            title: 'Drug-Target Prediction',
            description: 'Predict drug-target interactions',
            tool: 'DTI Predictor',
            complexity: 'complex',
            estimatedTime: '5 min'
          }
        ]

      case 'custom':
        return [
          {
            id: 'step1',
            title: 'Analysis Step',
            description: 'Custom analysis step based on request',
            tool: 'Custom Tool',
            complexity: 'intermediate',
            estimatedTime: '5 min'
          }
        ]

      // Standard bioinformatics workflow types
      case 'rna-seq':
        return [
          {
            id: 'step1',
            title: 'Quality Control',
            description: 'Assess raw sequencing reads quality using FastQC',
            tool: 'FastQC',
            complexity: 'simple',
            estimatedTime: '5 min'
          },
          {
            id: 'step2',
            title: 'Read Alignment',
            description: 'Align reads to reference genome using HISAT2',
            tool: 'HISAT2',
            complexity: 'intermediate',
            estimatedTime: '15 min'
          },
          {
            id: 'step3',
            title: 'Gene Expression Quantification',
            description: 'Count reads mapping to genes using featureCounts',
            tool: 'featureCounts',
            complexity: 'complex',
            estimatedTime: '8 min'
          },
          {
            id: 'step4',
            title: 'Differential Expression Analysis',
            description: 'Identify significant expression changes using DESeq2',
            tool: 'DESeq2',
            complexity: 'complex',
            estimatedTime: '12 min'
          }
        ]

      case 'variant-calling':
        return [
          {
            id: 'step1',
            title: 'Quality Control',
            description: 'Check raw sequencing data quality',
            tool: 'FastQC',
            complexity: 'simple',
            estimatedTime: '5 min'
          },
          {
            id: 'step2',
            title: 'Read Alignment',
            description: 'Align reads to reference genome',
            tool: 'BWA-MEM',
            complexity: 'intermediate', 
            estimatedTime: '20 min'
          },
          {
            id: 'step3',
            title: 'Variant Calling',
            description: 'Call variants using GATK HaplotypeCaller',
            tool: 'GATK',
            complexity: 'complex',
            estimatedTime: '25 min'
          },
          {
            id: 'step4',
            title: 'Variant Filtering',
            description: 'Filter variants by quality metrics',
            tool: 'GATK VariantFiltration',
            complexity: 'intermediate',
            estimatedTime: '10 min'
          }
        ]
        
      default:
        return [
          {
            id: 'step1',
            title: 'Quality Control',
            description: 'Assess raw sequencing reads quality using FastQC',
            tool: 'FastQC',
            complexity: 'simple',
            estimatedTime: '5 min'
          },
          {
            id: 'step2', 
            title: 'Read Alignment',
            description: 'Align reads to reference genome using HISAT2',
            tool: 'HISAT2',
            complexity: 'intermediate',
            estimatedTime: '15 min'
          },
          {
            id: 'step3',
            title: 'Gene Expression Quantification',
            description: 'Count reads mapping to genes using featureCounts',
            tool: 'featureCounts', 
            complexity: 'complex',
            estimatedTime: '8 min'
          },
          {
            id: 'step4',
            title: 'Differential Expression Analysis',
            description: 'Identify significant expression changes using DESeq2',
            tool: 'DESeq2',
            complexity: 'complex',
            estimatedTime: '12 min'
          }
        ]
    }
  }

  const generateDemoWorkflow = () => {
    return {
      id: `workflow-${Date.now()}`,
      title: "RNA-seq Analysis Pipeline", 
      description: "Complete RNA-seq data analysis workflow",
      type: "rna-seq",
      steps: [
        {
          id: 'step1',
          title: 'Quality Control',
          description: 'Assess raw sequencing reads quality using FastQC',
          tool: 'FastQC',
          complexity: 'simple',
          estimatedTime: '5 min'
        },
        {
          id: 'step2', 
          title: 'Read Alignment',
          description: 'Align reads to reference genome using HISAT2',
          tool: 'HISAT2',
          complexity: 'intermediate',
          estimatedTime: '15 min'
        },
        {
          id: 'step3',
          title: 'Gene Expression Quantification',
          description: 'Count reads mapping to genes using featureCounts',
          tool: 'featureCounts', 
          complexity: 'complex',
          estimatedTime: '8 min'
        },
        {
          id: 'step4',
          title: 'Differential Expression Analysis',
          description: 'Identify significant expression changes using DESeq2',
          tool: 'DESeq2',
          complexity: 'complex',
          estimatedTime: '12 min'
        }
      ]
    }
  }

  const getStatusIcon = (status: WorkflowProgress['status']) => {
    switch (status) {
      case 'running': return Clock
      case 'completed': return CheckCircle
      case 'error': return AlertTriangle
      default: return Clock
    }
  }

  const getStatusColor = (status: WorkflowProgress['status']) => {
    switch (status) {
      case 'running': return 'text-blue-500'
      case 'completed': return 'text-green-500'
      case 'error': return 'text-red-500'
      default: return 'text-muted-foreground'
    }
  }

  const handleSendMessage = async (content: string, files?: File[]) => {
    // Handle attached files: upload to backend and include dataset IDs in prompt context.
    if (files && files.length > 0) {
      console.log('[ChatInterface] Files attached:', files.map((f) => f.name))
      const uploaded: Array<{ name: string; datasetId?: string; galaxyDatasetId?: string }> = []
      const failedUploads: string[] = []

      for (const file of files) {
        try {
          const formData = new FormData()
          formData.append('file', file)
          formData.append('description', 'Uploaded from BioMate chat composer')

          const response = await fetch('/api/datasets/upload', {
            method: 'POST',
            body: formData,
            credentials: 'include',
          })

          if (!response.ok) {
            failedUploads.push(`${file.name} (HTTP ${response.status})`)
            continue
          }

          const result = await response.json()
          uploaded.push({
            name: file.name,
            datasetId: result.dataset_id,
            galaxyDatasetId: result.galaxy_dataset_id,
          })
        } catch {
          failedUploads.push(file.name)
        }
      }

      const fileNames = files.map((f) => f.name).join(', ')
      const uploadedContext =
        uploaded.length > 0
          ? uploaded
              .map(
                (f) =>
                  `${f.name}: dataset_id=${f.datasetId || 'n/a'}${
                    f.galaxyDatasetId ? `, galaxy_dataset_id=${f.galaxyDatasetId}` : ''
                  }`
              )
              .join('; ')
          : ''
      const failedContext = failedUploads.length > 0 ? failedUploads.join(', ') : ''

      content =
        content +
        (content ? '\n\n' : '') +
        `[Attached files: ${fileNames}]` +
        (uploadedContext ? `\n[Uploaded datasets: ${uploadedContext}]` : '') +
        (failedContext ? `\n[Upload warnings: ${failedContext}]` : '')
    }

    // Create user message
    const userMessage: Message = {
      id: Date.now().toString(),
      content,
      role: "user",
      timestamp: new Date()
    }

    // Add user message to chat session (create one if it doesn't exist)
    const sessionId = chatSession?.id || chatHistoryService.createNewSession().id
    const updatedSession = chatHistoryService.addMessage(sessionId, userMessage)
    if (updatedSession && onChatUpdated) {
      onChatUpdated(updatedSession)
    }

    // Add placeholder assistant message for streaming UX
    const placeholderId = `assistant-stream-${Date.now()}`
    const placeholderMessage: Message = {
      id: placeholderId,
      content: "",
      role: "assistant",
      timestamp: new Date(),
      suggestions: [],
      metadata: {
        type: "text",
      },
    }
    const withPlaceholder = chatHistoryService.addMessage(sessionId, placeholderMessage)
    if (withPlaceholder && onChatUpdated) {
      onChatUpdated(withPlaceholder)
    }

    setIsTypingLocal(true)

    analytics.track('query_sent', { query_length: content.length })

    // Call Galaxy API (always, regardless of session)
    chatMutation.mutate({ content, sessionId, placeholderId })

    onSendMessage(content)
  }

  /**
   * Soft-queue wrapper around handleSendMessage.
   * Text-only messages submitted while the AI is responding are held in
   * pendingMessages and auto-submitted as soon as each response completes.
   * Messages with file attachments bypass the queue and go immediately.
   */
  const handleSendOrQueue = useCallback((content: string, files?: File[]) => {
    if (displayTyping && !files?.length && content.trim()) {
      setPendingMessages(prev => [...prev, content.trim()])
      return
    }
    handleSendMessage(content, files)
  }, [displayTyping]) // eslint-disable-line react-hooks/exhaustive-deps

  const stopStreaming = useCallback(() => {
    abortControllerRef.current?.abort()
    abortControllerRef.current = null
    setIsTypingLocal(false)
    const queuedCount = pendingMessagesRef.current.length
    if (queuedCount > 0) {
      setStopDialogQueueCount(queuedCount)
      setShowStopDialog(true)
    }
  }, [])

  // Auto-submit the next queued message once the AI finishes responding.
  useEffect(() => {
    if (!displayTyping && pendingMessagesRef.current.length > 0) {
      const [next, ...rest] = pendingMessagesRef.current
      setPendingMessages(rest)
      handleSendMessage(next)
    }
  }, [displayTyping]) // eslint-disable-line react-hooks/exhaustive-deps

  const handleToolClick = (tool: any) => {
    console.log('Tool clicked:', tool)
    // Future: Navigate to tool details or add to workflow
  }

  const handleSuggestionClick = (suggestion: string, message: Message) => {
    const normalized = suggestion.toLowerCase().trim()
    console.log("[ChatInterface] Suggestion clicked:", suggestion)

    // "Continue" — request continuation of a truncated response
    if (normalized === 'continue') {
      handleSendMessage('Please continue from where you left off.')
      return
    }

    if (normalized.includes("try again")) {
      const lastUserMessage = [...displayMessages].reverse().find((m) => m.role === "user" && m.content?.trim())
      if (lastUserMessage?.content) {
        emitUxEvent("async.retry_clicked", {
          sessionId: chatSession?.id,
          source: "chat_error_surface",
          suggestion,
        })
        handleSendMessage(lastUserMessage.content)
      }
      return
    }

    if (normalized.includes("report issue")) {
      emitUxEvent("async.report_issue_clicked", {
        sessionId: chatSession?.id,
        source: "chat_error_surface",
        suggestion,
        errorType: message.metadata?.errorType,
      })
      return
    }

    emitUxEvent("chat.suggestion_clicked", {
      sessionId: chatSession?.id,
      suggestion,
      messageRole: message.role,
    })
  }

  const handleDatasetClick = (dataset: any) => {
    console.log('Dataset clicked:', dataset)
    // Future: Preview dataset or add to workflow inputs
  }

  const handleCompress = async () => {
    if (!chatSession) {
      console.error('[ChatInterface] Cannot compress: no active session')
      return
    }

    try {
      setIsCompressing(true)
      console.log('[ChatInterface] Starting compression for session:', chatSession.id)

      // Call backend compression service
      const response = await fetch('/api/compress-session', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          sessionId: chatSession.id,
          messages: displayMessages,
          keepRecentCount: 3
        })
      })

      if (!response.ok) {
        throw new Error(`Compression failed: ${response.statusText}`)
      }

      const result = await response.json()

      console.log('[ChatInterface] Compression successful:', {
        messagesReduced: `${result.messagesBeforeCount} → ${result.messagesAfterCount}`,
        tokensReduced: `${result.tokensBeforeCount} → ${result.tokensAfterCount}`,
        compressionRatio: `${(result.compressionRatio * 100).toFixed(1)}%`
      })

      // Update session with compressed messages
      chatHistoryService.updateSession(chatSession.id, {
        messages: result.compressedMessages
      })

      // Update local state
      const updatedSession = chatHistoryService.getSession(chatSession.id)
      if (updatedSession && onChatUpdated) {
        onChatUpdated(updatedSession)
      }

      // Record compression in backend (optional - don't fail if this fails)
      try {
        await fetch(`/api/memory/sessions/${chatSession.id}/compress`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json'
          },
          body: JSON.stringify({
            summary: result.summary,
            messages_before: result.messagesBeforeCount,
            messages_after: result.messagesAfterCount,
            tokens_before: result.tokensBeforeCount,
            tokens_after: result.tokensAfterCount
          })
        })
      } catch (recordError) {
        console.warn('[ChatInterface] Failed to record compression in backend:', recordError)
        // Don't fail the compression - the local compression already succeeded
      }

      // Close dialog
      setShowCompressionDialog(false)
      setCompressionDismissed(false) // Allow showing again if needed

    } catch (error) {
      console.error('[ChatInterface] Compression failed:', error)
      alert('Compression failed. Please try again.')
    } finally {
      setIsCompressing(false)
    }
  }

  const handleCancelCompression = () => {
    console.log('[ChatInterface] Compression dismissed by user')
    setShowCompressionDialog(false)
    setCompressionDismissed(true)

    // Allow showing again after 10 minutes
    setTimeout(() => {
      setCompressionDismissed(false)
    }, 10 * 60 * 1000)
  }

  // Listen for LangGraph task updates dispatched via custom DOM events from SSE handlers
  useEffect(() => {
    const handler = (e: CustomEvent<{ task_id: string; status: TaskStatus; description?: string; elapsed_ms?: number }>) => {
      const { task_id, status, description, elapsed_ms } = e.detail
      setLanggraphTasks(prev => {
        const existing = prev.find(t => t.id === task_id)
        if (existing) {
          return prev.map(t =>
            t.id === task_id ? { ...t, status, elapsedMs: elapsed_ms } : t
          )
        }
        return [...prev, { id: task_id, description: description || task_id, status, elapsedMs: elapsed_ms }]
      })
    }
    window.addEventListener('langgraphTaskUpdate', handler as EventListener)
    return () => window.removeEventListener('langgraphTaskUpdate', handler as EventListener)
  }, [])

  const handleStopTask = useCallback((taskId: string) => {
    setLanggraphTasks(prev =>
      prev.map(t => t.id === taskId ? { ...t, status: 'stopped' as TaskStatus } : t)
    )
  }, [])

  const handleRetryTask = useCallback((taskId: string) => {
    setLanggraphTasks(prev =>
      prev.map(t => t.id === taskId ? { ...t, status: 'pending' as TaskStatus } : t)
    )
  }, [])

  const handleRemoveTask = useCallback((taskId: string) => {
    setLanggraphTasks(prev => prev.filter(t => t.id !== taskId))
  }, [])

  useEffect(() => {
    if (!externalPromptRequest) return
    if (displayTyping) return
    const prompt = externalPromptRequest.prompt?.trim()
    if (!prompt) {
      onExternalPromptConsumed?.(externalPromptRequest.id)
      return
    }
    handleSendMessage(prompt)
    onExternalPromptConsumed?.(externalPromptRequest.id)
  }, [externalPromptRequest, displayTyping])

  return (
    <div className={`flex flex-col h-full ${className}`}>
      <div
        className="sr-only"
        data-testid="chat-run-anchor-state"
        data-focused-run-id={focusedRunId || ""}
        data-focused-message-id={focusedAnchorMessageId || ""}
        data-highlighted-message-id={highlightedAnchorMessageId || ""}
        data-generating={isTypingLocal ? "true" : "false"}
      />
      {/* Compression status badge */}
      {currentTokenCount > 0 && (
        <div className="flex justify-end p-2 border-b bg-background/95">
          <CompressionStatusBadge
            currentTokens={currentTokenCount}
            tokenLimit={200000}
          />
        </div>
      )}

      <ScrollArea className="flex-1 p-4" ref={scrollRef} data-testid="chat-messages">
        <OnboardingWelcome
          onComplete={() => setOnboardingDone(true)}
          visible={displayMessages.length === 0 && !isTyping && !isTypingLocal && !onboardingDone}
        />
        <div className="space-y-4">
          {displayMessages
            .filter(msg => !(msg.role === 'assistant' && !msg.content?.trim() && (isTyping || isTypingLocal)))
            .map((message) => (
            <ChatMessage
              key={message.id}
              message={message}
              sessionId={chatSession?.id}
              onToolClick={handleToolClick}
              onDatasetClick={handleDatasetClick}
              onCreateWorkflow={() => {
                if (message.metadata?.workflow) {
                  onWorkflowGenerated(message.metadata.workflow);
                }
              }}
              // Workflow execution props for inline artifacts
              onRunWorkflow={onRunWorkflow}
              onStopWorkflow={onStopWorkflow}
              onPauseWorkflow={onPauseWorkflow}
              onResumeWorkflow={onResumeWorkflow}
              onParameterChange={onParameterChange}
              onSuggestionClick={handleSuggestionClick}
              isWorkflowRunning={isWorkflowRunning}
              workflowProgress={workflowProgress}
              currentExecutionRun={currentExecutionRun}
              isLatestAssistantMessage={message.id === latestAssistantMessageId}
              isRunAnchorFocused={focusedAnchorMessageId === message.id}
              isRunAnchorHighlighted={highlightedAnchorMessageId === message.id}
              // Right panel: suppress all inline workflow UI when the panel is open.
              // isInPanel=true hides the workflow widget for the exact matched message;
              // isPanelOpen=true suppresses pipeline/chain views for other messages too.
              isInPanel={isPanelOpen || !!(panelWorkflowMessageId && message.id === panelWorkflowMessageId)}
              onOpenInPanel={
                message.metadata?.type === 'workflow' && message.metadata?.workflow
                  ? () => onOpenWorkflowInPanel?.(message.id, message.metadata!.workflow)
                  : undefined
              }
            />
          ))}
          {displayTyping && <TypingIndicator />}
          {/* Auto-scroll anchor */}
          <div ref={messagesEndRef} />
        </div>
      </ScrollArea>
      
      {/* Compact Progress Indicator - Shows ONLY if workflow running but NO inline artifact visible
          The inline WorkflowArtifact in chat messages is the primary progress display.
          This compact bar only shows for workflows started outside chat or legacy mode.
          UI Simplification: Removed detailed step list - see inline artifact for details. */}
      {activeWorkflow && !displayMessages.some(m => m.metadata?.type === 'workflow' && m.metadata?.workflow) && (
        <div className="border-t bg-background">
          <div
            className="w-full p-3 cursor-pointer hover:bg-muted/50 transition-colors"
            onClick={onToggleProgress}
            data-testid="button-toggle-progress"
          >
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                {(() => {
                  const StatusIcon = getStatusIcon(activeWorkflow.status)
                  return <StatusIcon className={cn("w-4 h-4", getStatusColor(activeWorkflow.status))} />
                })()}
                <span className="text-sm font-medium">{activeWorkflow.title}</span>
                <Badge variant="secondary" className="text-xs">
                  {activeWorkflow.progress}%
                </Badge>
              </div>
              <div className="flex items-center gap-2 text-xs text-muted-foreground">
                {activeWorkflow.steps.filter(s => s.status === 'completed').length}/{activeWorkflow.steps.length} steps
                {showProgress ? <ChevronDown className="w-3 h-3" /> : <ChevronRight className="w-3 h-3" />}
              </div>
            </div>
          </div>

          {showProgress && (
            <div className="p-4 pt-0">
              <Separator className="mb-4" />
              
              {/* Progress Bar */}
              <div className="mb-4">
                <div className="flex justify-between text-sm mb-2">
                  <span className="text-muted-foreground">Overall Progress</span>
                  <span className="font-medium">{activeWorkflow.progress}%</span>
                </div>
                <div className="w-full bg-muted rounded-full h-2">
                  <div 
                    className="bg-primary h-2 rounded-full transition-all duration-500"
                    style={{ width: `${activeWorkflow.progress}%` }}
                  />
                </div>
              </div>

              {/* Steps Detail */}
              <div className="space-y-2">
                <h4 className="font-medium text-sm">Pipeline Steps</h4>
                <div className="space-y-1">
                  {activeWorkflow.steps.map((step, index) => {
                    const StepIcon = getStatusIcon(step.status)
                    return (
                      <div key={step.id} className="flex items-center gap-2 text-sm p-2 rounded-md hover:bg-muted/50">
                        <div className="w-6 h-6 rounded-full border-2 flex items-center justify-center text-xs font-medium bg-background">
                          {index + 1}
                        </div>
                        <StepIcon className={cn("w-3 h-3", getStatusColor(step.status))} />
                        <span className="flex-1">{step.name}</span>
                        {step.duration && (
                          <span className="text-xs text-muted-foreground">{step.duration}</span>
                        )}
                        {step.status === 'running' && (
                          <div className="w-2 h-2 bg-blue-500 rounded-full animate-pulse" />
                        )}
                      </div>
                    )
                  })}
                </div>
              </div>

              {/* Quick Actions */}
              <div className="flex gap-2 mt-4">
                <Button size="sm" variant="outline" data-testid="button-view-logs">
                  View Logs
                </Button>
                <Button size="sm" variant="outline" data-testid="button-workflow-settings">
                  <Settings className="w-3 h-3 mr-1" />
                  Settings
                </Button>
              </div>
            </div>
          )}
        </div>
      )}

      {(langgraphTasks.length > 0 || pendingMessages.length > 0) && (
        <div className="px-4 pb-2">
          <TaskList
            tasks={langgraphTasks}
            queuedMessages={pendingMessages}
            onStopTask={handleStopTask}
            onRemoveTask={handleRemoveTask}
            onRetryTask={handleRetryTask}
            onRemoveMessage={(i) => setPendingMessages(prev => prev.filter((_, idx) => idx !== i))}
          />
        </div>
      )}
      {showStopDialog && (
        <div
          className="mx-4 mb-2 rounded-lg border bg-background shadow-md p-3 text-sm"
          data-testid="stop-dialog"
        >
          <p className="font-medium mb-2 text-foreground">
            Reply stopped. What should happen to your {stopDialogQueueCount} queued message{stopDialogQueueCount !== 1 ? 's' : ''}?
          </p>
          <div className="flex gap-2">
            <button
              className="rounded border border-border px-3 py-1.5 text-xs hover:bg-muted"
              data-testid="stop-reply-only"
              onClick={() => setShowStopDialog(false)}
            >
              Keep queued ({stopDialogQueueCount})
            </button>
            <button
              className="rounded bg-destructive text-destructive-foreground px-3 py-1.5 text-xs hover:bg-destructive/90"
              data-testid="stop-and-clear-queue"
              onClick={() => {
                setPendingMessages([])
                setShowStopDialog(false)
              }}
            >
              Clear all queued
            </button>
          </div>
        </div>
      )}
      <ChatInput
        onSend={handleSendOrQueue}
        pendingCount={pendingMessages.length}
        isStreaming={displayTyping}
        onStop={stopStreaming}
        onRegisterSetDraft={onRegisterSetDraft}
      />
      {displayTyping && (
        <div
          className="border-t bg-muted/40 px-4 py-2 text-sm"
          role="status"
          aria-live="polite"
          data-testid="chat-analysis-status"
        >
          <div className="flex items-center gap-2 text-muted-foreground">
            <Loader2 className="h-4 w-4 animate-spin" />
            <span>Analyzing request… response will stream in as soon as it&apos;s ready.</span>
          </div>
        </div>
      )}

      {/* Compression dialog */}
      <CompressionDialog
        open={showCompressionDialog}
        currentTokens={currentTokenCount}
        tokenLimit={200000}
        messageCount={displayMessages.length}
        isCompressing={isCompressing}
        onCompress={handleCompress}
        onCancel={handleCancelCompression}
      />
    </div>
  )
}