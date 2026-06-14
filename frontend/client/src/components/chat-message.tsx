import { useState } from "react"
import ReactMarkdown from "react-markdown"
import remarkGfm from "remark-gfm"
import rehypeRaw from "rehype-raw"
import { CodeExecutionBlock, type ToolBlock } from "./code-execution-block"

/**
 * Pre-processes assistant markdown to:
 * 1. Convert inline [N] citations → clickable [[N]](#ref-N) links
 * 2. Add <span id="ref-N"> anchors to each References list entry
 * 3. Make bare URLs in the References section into proper markdown links
 */
function addCitationLinks(text: string): string {
  if (!text) return text;

  // Split at the ## References / # References heading (case-insensitive)
  const refMatch = text.match(/^(#{1,3}\s*References?\s*)$/im);
  if (!refMatch || refMatch.index === undefined) {
    // No references section: just linkify inline citations to a #references hash
    return text.replace(/\[(\d+)\](?!\()/g, (_, n) => `[[${n}]](#references)`);
  }

  const bodyEnd = refMatch.index;
  const body = text.slice(0, bodyEnd);
  const refs = text.slice(bodyEnd);

  // Body: [N] → [[N]](#ref-N)  (don't replace already-linked [N](...))
  const linkedBody = body.replace(/\[(\d+)\](?!\()/g, (_, n) => `[[${n}]](#ref-${n})`);

  // References section:
  //   Lines starting with [N] text → inject HTML anchor before the number
  //   Bare URLs at end of line → convert to markdown links
  const linkedRefs = refs
    .replace(/^\[(\d+)\]/gm, (_, n) => `<span id="ref-${n}"></span>[${n}]`)
    .replace(
      /(https?:\/\/[^\s)\]]+)/g,
      (url) => `[${url}](${url})`,
    );

  return linkedBody + linkedRefs;
}
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar"
import { Button } from "@/components/ui/button"
import { Card } from "@/components/ui/card"
import {
  DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"
import { Copy, RotateCcw, Workflow, Download, FileJson, FileText, FileDown, FlaskConical, PanelRight, ExternalLink } from "lucide-react"
import { RollIntoIndAffordance } from "@/components/RollIntoIndAffordance";
import { cn, getSimpleToolName } from "@/lib/utils"
import { downloadAsTxt, downloadAsMd, downloadAsDocx } from "@/lib/download-response"
import { GalaxyRecommendations } from "./galaxy-recommendations"
import { ChatOutputAttachments } from "./chat-output-attachments"
import { ThinkingDisplay } from "./thinking-display"
import { NextflowWorkflowViewer } from "./nextflow-workflow-viewer"
import { WorkflowChainPlan } from "./workflow-chain-plan"
import { WorkflowDisambiguationCard, type DisambigCandidate } from "./workflow-disambiguation-card"
import { PipelineListView } from "./pipeline-list-view"
import { WorkflowRationale } from "./workflow-rationale"
import { ParamClarificationCard, type ParamClarification } from "./param-clarification-card"
import { BenchmarkEvidence, ResearchResponseDisplay } from "./benchmark-evidence"
import { InlineFeedbackWidget } from "./feedback/inline-feedback-widget"
import { DownloadOutcomePrompt } from "./feedback/download-outcome-prompt"
import { ReportConfusionButton } from "./feedback/report-confusion-button"
import { useToast } from "@/hooks/use-toast"
import { normalizePrereqChecklist } from "@/lib/prereq-normalizer"
import userAvatar from "@assets/generated_images/User_avatar_placeholder_d2803d15.png"

// Use the shared Message type for consistency
import type { ExecutionRun, Message } from '@shared/schema'
export type { Message }

// ── Speaker pill helpers ───────────────────────────────────────
// Maps metadata.kind → speaker key, mirroring deriveSpeakerFallback
// in research_agent_v2/src/ChatStream.jsx.
const SPEAKER_LABELS: Record<string, string> = {
  plan:  'PLAN',
  wf:    'WF',
  qc:    'QC',
  loop:  'LOOP',
  agent: 'AGENT',
  find:  'FIND',
}

function deriveSpeaker(kind: string | undefined): string {
  if (!kind) return 'wf'
  if (kind.startsWith('workflow.qc_'))      return 'qc'
  if (kind.startsWith('workflow.autoloop')) return 'loop'
  if (kind.startsWith('workflow.'))         return 'wf'
  if (kind.startsWith('deepagent.'))        return 'agent'
  if (kind.startsWith('plan.'))             return 'plan'
  if (kind.startsWith('findings.'))         return 'find'
  return 'wf'
}

interface ChatMessageProps {
  message: Message
  sessionId?: string
  onCopy?: () => void
  onRegenerate?: () => void
  onCreateWorkflow?: () => void
  onToolClick?: (tool: any) => void
  onDatasetClick?: (dataset: any) => void
  onRunWorkflow?: (workflow: any, steps: any[]) => void
  onRunChain?: (workflow: any) => void
  onRunPipeline?: (workflow: any) => void
  onApprovePipelineStep?: (workflow: any, completedStepId: string, nextStepId: string) => void
  onStopWorkflow?: () => void
  onPauseWorkflow?: () => void
  onResumeWorkflow?: () => void
  onParameterChange?: (stepId: string, params: Record<string, any>) => void
  onSuggestionClick?: (suggestion: string, message: Message) => void
  onAdjustViaChat?: (message?: string) => void
  /** Bubbled up from NextflowWorkflowViewer when the backend narrator emits a chat_progress SSE event. */
  onWorkflowProgress?: (event: { kind: string; friendly_message: string; ts?: number; technical?: any; invocationId?: string }) => void
  isWorkflowRunning?: boolean
  workflowProgress?: number
  currentExecutionRun?: ExecutionRun | null
  isLatestAssistantMessage?: boolean
  isRunAnchorFocused?: boolean
  isRunAnchorHighlighted?: boolean
  isInPanel?: boolean
  onOpenInPanel?: () => void
}

export function ChatMessage({
  message,
  sessionId,
  onCopy = () => console.log('Copy message triggered'),
  onRegenerate = () => console.log('Regenerate message triggered'),
  onCreateWorkflow = () => console.log('Create workflow triggered'),
  onToolClick,
  onDatasetClick,
  onRunWorkflow,
  onRunChain,
  onRunPipeline,
  onApprovePipelineStep,
  onStopWorkflow,
  onPauseWorkflow,
  onResumeWorkflow,
  onParameterChange,
  onSuggestionClick = () => {},
  onAdjustViaChat,
  onWorkflowProgress,
  isWorkflowRunning = false,
  workflowProgress = 0,
  currentExecutionRun,
  isLatestAssistantMessage = false,
  isRunAnchorFocused = false,
  isRunAnchorHighlighted = false,
  isInPanel = false,
  onOpenInPanel,
}: ChatMessageProps) {
  const isUser = message.role === "user"
  const isWorkflowMessage = !isUser && message.metadata?.type === "workflow" && !!message.metadata?.workflow
  // Workflow-progress messages: short, italic, friendly chat lines emitted by
  // the backend narrator (see backend/lib/galaxy/ai/workflow_ops/workflow_chat_narrator.py)
  // and delivered via the workflow SSE stream. Rendered as a single line, not
  // a full assistant card.
  const isProgressMessage = !isUser && message.metadata?.type === "workflow_progress"
  const { toast } = useToast()
  const [downloadPromptOpen, setDownloadPromptOpen] = useState(false)
  const effectiveInvocationId =
    (isRunAnchorFocused
      ? currentExecutionRun?.execution?.galaxyInvocationId || currentExecutionRun?.id
      : undefined) ||
    message.invocationId ||
    (isWorkflowMessage && isLatestAssistantMessage
      ? currentExecutionRun?.execution?.galaxyInvocationId || currentExecutionRun?.id
      : undefined)

  // Extract Galaxy Assistant metadata
  const hasGalaxyMetadata = message.metadata && (
    message.metadata.recommendedTools ||
    message.metadata.recommendedDatasets
  )

  const handleCopyResponse = async () => {
    onCopy()
    try {
      await navigator.clipboard.writeText(message.content || "")
      toast({ title: "Copied response" })
    } catch {
      toast({ title: "Copy failed", description: "Clipboard permission unavailable.", variant: "destructive" })
    }
  }

  const handleCopyWorkflow = async () => {
    const workflow = message.metadata?.workflow
    if (!workflow) {
      toast({ title: "No workflow to copy", variant: "destructive" })
      return
    }
    try {
      await navigator.clipboard.writeText(JSON.stringify(workflow, null, 2))
      toast({ title: "Copied workflow JSON" })
    } catch {
      toast({ title: "Copy failed", description: "Clipboard permission unavailable.", variant: "destructive" })
    }
  }

  const handleDownloadOutputs = () => {
    if (!effectiveInvocationId) {
      toast({ title: "No outputs yet", description: "Run a workflow first to enable download.", variant: "destructive" })
      return
    }
    window.open(`/api/invocations/${effectiveInvocationId}/download-all`, "_blank")
    setDownloadPromptOpen(true)
    toast({ title: "Download started" })
  }

  // Format timestamp like reference: "YOU · 3:40 PM"
  const timeLabel = message.timestamp
    ? new Date(message.timestamp).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })
    : null;

  // Early return for workflow-progress messages: render as a compact italic
  // status line, not the full assistant card. Keeps the chat from filling up
  // with N expanded cards when N progress events fire in a row.
  if (isProgressMessage) {
    const kind = (message.metadata as any)?.kind as string | undefined
    const speaker = deriveSpeaker(kind)
    const pillLabel = SPEAKER_LABELS[speaker] ?? 'WF'
    return (
      <div
        className={cn("msg progress px-4 py-1")}
        id={`chat-message-anchor-${message.id}`}
        data-testid={`chat-message-${message.id}`}
        data-role="assistant"
        data-message-type="workflow_progress"
        data-progress-kind={kind ?? "unknown"}
        style={{
          display: 'flex', alignItems: 'center', gap: 6,
          fontSize: 12, fontStyle: 'italic',
          color: 'var(--bm-text-dim, oklch(0.62 0.010 260))',
          opacity: 0.85,
        }}
      >
        <span aria-hidden style={{ fontStyle: 'normal' }}>🔹</span>
        <span className="speaker-pill" data-speaker={speaker} aria-label={pillLabel}>{pillLabel}</span>
        <span>{message.content}</span>
        {timeLabel && (
          <span style={{ fontSize: 10, opacity: 0.7, marginLeft: 4 }}>· {timeLabel}</span>
        )}
      </div>
    )
  }

  return (
    <div
      className={cn("msg px-4 py-2", isUser ? "user" : "assistant")}
      id={`chat-message-anchor-${message.id}`}
      data-testid={`chat-message-${message.id}`}
      data-role={message.role}
      data-run-anchor-focused={isRunAnchorFocused ? "true" : "false"}
      data-run-anchor-highlighted={isRunAnchorHighlighted ? "true" : "false"}
      data-is-latest-assistant={isLatestAssistantMessage ? "true" : "false"}
      style={{ display: 'flex', flexDirection: 'column', gap: 4, alignItems: isUser ? 'flex-end' : 'flex-start', maxWidth: '100%' }}
    >
      {/* Who label — "YOU · 3:40 PM" or "BIOMATE" */}
      <div className="who" style={{
        fontSize: 11, color: 'var(--bm-text-dim, oklch(0.62 0.010 260))',
        textTransform: 'uppercase', letterSpacing: '0.05em', fontWeight: 600,
        fontFamily: 'var(--bm-font-ui)',
      }}>
        {isUser ? `You${timeLabel ? ` · ${timeLabel}` : ''}` : 'BioMate'}
      </div>

      <div className={cn("max-w-full space-y-3", isUser && "flex flex-col items-end")}>
        <div className={cn(
          isUser
            ? "bubble"  /* reference: .msg.user .bubble */
            : ""        /* assistant: no card wrapper */
        )} style={isUser ? {
          background: 'var(--bm-surface-3, oklch(0.945 0.005 240))',
          color: 'var(--bm-text, oklch(0.22 0.01 260))',
          borderRadius: '14px 14px 2px 14px',
          padding: '10px 14px',
          maxWidth: '80%',
          fontSize: 14,
          lineHeight: 1.5,
          alignSelf: 'flex-end',
        } : undefined}>
            {isUser ? (
              <p className="text-sm leading-relaxed whitespace-pre-wrap">{message.content}</p>
            ) : (
              <>
              {/* Agent tool blocks — shown above the text response */}
              {(message.metadata?.toolBlocks as ToolBlock[] | undefined)?.map(block => (
                <CodeExecutionBlock key={block.tool_use_id} block={block} />
              ))}
              <div className="text-sm leading-relaxed prose prose-sm dark:prose-invert max-w-none
                prose-headings:font-semibold prose-headings:mt-4 prose-headings:mb-2
                prose-h1:text-base prose-h2:text-sm prose-h3:text-sm
                prose-p:my-1 prose-ul:my-1 prose-ol:my-1 prose-li:my-0.5
                prose-code:text-xs prose-code:bg-muted prose-code:px-1 prose-code:rounded
                prose-pre:bg-muted prose-pre:text-xs prose-pre:overflow-x-auto
                prose-blockquote:border-l-4 prose-blockquote:pl-3 prose-blockquote:italic prose-blockquote:text-muted-foreground
                prose-hr:my-3">
                <ReactMarkdown
                  remarkPlugins={[remarkGfm]}
                  rehypePlugins={[rehypeRaw]}
                  components={{
                    a: ({ href, children, ...props }) => (
                      <a
                        href={href}
                        target={href?.startsWith('#') ? '_self' : '_blank'}
                        rel={href?.startsWith('#') ? undefined : 'noopener noreferrer'}
                        {...props}
                      >
                        {children}
                      </a>
                    ),
                    table: ({ children, ...props }) => (
                      <div className="overflow-x-auto my-2 max-w-full">
                        <table className="w-full text-xs" {...props}>{children}</table>
                      </div>
                    ),
                    img: ({ src, alt, ...props }) => {
                      if (!src) return null;
                      return (
                        <img
                          src={src}
                          alt={alt ?? ''}
                          {...props}
                          onError={(e) => { (e.currentTarget as HTMLImageElement).style.display = 'none'; }}
                        />
                      );
                    },
                  }}
                >
                  {addCitationLinks(message.content || '')}
                </ReactMarkdown>
              </div>
              </>
            )}
          </div>

          {/* Thinking Display - Show AI reasoning process */}
          {!isUser && message.thinking_content && (
            <ThinkingDisplay
              thinkingContent={message.thinking_content}
              thinkingLevel={message.thinking_level}
              className="mt-3"
            />
          )}

          {/* Galaxy Assistant Recommendations */}
          {!isUser && hasGalaxyMetadata && (
            <GalaxyRecommendations
              tools={message.metadata?.recommendedTools}
              datasets={message.metadata?.recommendedDatasets}
              onToolClick={onToolClick}
              onDatasetClick={onDatasetClick}
            />
          )}

          {/* Benchmark Evidence - Shows validated tool comparisons */}
          {!isUser && message.metadata?.benchmark_evidence && (
            <BenchmarkEvidence
              benchmarkData={message.metadata.benchmark_evidence}
              onToolClick={(toolName, galaxyToolId) => {
                if (onToolClick && galaxyToolId) {
                  onToolClick({ tool: { tool_id: galaxyToolId, name: toolName }, relevanceScore: 1, reasoning: 'From benchmark' })
                }
              }}
              className="mt-3"
            />
          )}

          {/* Research Response - Shows answer with citations and evidence */}
          {!isUser && message.metadata?.type === 'research_response' && message.metadata?.research_response && (
            <ResearchResponseDisplay
              response={message.metadata.research_response}
              onFollowUpClick={(question) => console.log('Follow-up:', question)}
              onToolClick={(toolName, galaxyToolId) => {
                if (onToolClick && galaxyToolId) {
                  onToolClick({ tool: { tool_id: galaxyToolId, name: toolName }, relevanceScore: 1, reasoning: 'From research' })
                }
              }}
              className="mt-3"
            />
          )}

          {/* wf-chip: compact workflow card shown in chat when workflow is open in the panel */}
          {isWorkflowMessage && isInPanel && message.metadata?.workflow && (
            <div className="wf-chip" data-tour="chat-handoff">
              <div className="wf-chip-ic">
                <FlaskConical size={16} />
              </div>
              <div className="wf-chip-body">
                <div className="wf-chip-name">{message.metadata.workflow.name || message.metadata.workflow.display_name || 'Workflow'}</div>
                <div className="wf-chip-sub">
                  {[
                    message.metadata.workflow.domain,
                    message.metadata.workflow.subtitle ||
                      (message.metadata.workflow.steps && typeof message.metadata.workflow.steps === 'object' && !Array.isArray(message.metadata.workflow.steps)
                        ? `${Object.keys(message.metadata.workflow.steps).length} steps` : null),
                  ].filter(Boolean).join(' · ')}
                </div>
              </div>
              <span className="chip-ok">
                <span className="dot" />
                In panel
              </span>
            </div>
          )}

          {/* ParamClarificationCard — surfaces missing-required / enum-violation
              issues from schema-grounded extraction. Hidden when none present. */}
          {!isUser && (message.metadata as any)?.paramClarifications?.length > 0 && (
            <ParamClarificationCard
              workflowName={
                message.metadata?.workflow?.name ||
                message.metadata?.workflow?.display_name ||
                'workflow'
              }
              clarifications={(message.metadata as any).paramClarifications as ParamClarification[]}
              onSelect={(paramName, value) => {
                // Dispatch a custom event the workflow panel can listen for; the
                // panel patches the param value in place. The card itself does
                // not own param state.
                window.dispatchEvent(
                  new CustomEvent('biomate:param-clarification-resolved', {
                    detail: { messageId: message.id, paramName, value },
                  }),
                )
              }}
              onSkip={(paramName) => {
                window.dispatchEvent(
                  new CustomEvent('biomate:param-clarification-skipped', {
                    detail: { messageId: message.id, paramName },
                  }),
                )
              }}
              className="mt-2"
            />
          )}

          {/* Path A.4: Roll into IND project. Shows only when workflow completed +
              at least one IND project exists. The affordance itself queries
              listProjects() and hides if empty. */}
          {/* Path A.4: Roll into IND project. Shows only when workflow completed +
              at least one IND project exists. The affordance itself queries
              listProjects() and hides if empty. */}
          {isWorkflowMessage && message.metadata?.workflow && currentExecutionRun?.execution?.status === "completed" && (
            <RollIntoIndAffordance
              workflowName={message.metadata.workflow.name || message.metadata.workflow.display_name}
              workflowRunId={effectiveInvocationId || undefined}
            />
          )}

          {/* Nextflow Workflow Viewer - Replaces WorkflowArtifact */}
          {/* When the workflow is open in the right panel (isInPanel=true), render nothing
              here — all workflow UI lives exclusively in the panel. The AI text response
              above already tells the user to look at the panel. */}
          {isWorkflowMessage && !isInPanel && (
            (() => {
              const invocationId = effectiveInvocationId;
              const executionStatus = currentExecutionRun?.execution?.status || (isWorkflowRunning ? 'running' : 'idle');
              const executionStatusStr = executionStatus as string;
              const viewerStatus: 'pending_review' | 'idle' | 'running' | 'paused' | 'completed' | 'failed' =
                executionStatusStr === 'completed' || executionStatusStr === 'ok'
                  ? 'completed'
                  : executionStatusStr === 'paused'
                  ? 'paused'
                  : executionStatusStr === 'failed' || executionStatusStr === 'cancelled' || executionStatusStr === 'error'
                  ? 'failed'
                  : executionStatusStr === 'running'
                  ? 'running'
                  : 'idle';

              const workflowLevelDomainGuard = message.metadata?.workflow?.domainGuard || message.metadata?.workflow?.domain_guard;
              const workflowNeedsFeedback =
                !!message.metadata?.workflow?.needs_user_feedback || !!message.metadata?.workflow?.needsUserFeedback;
              const workflowFeedbackPrompt =
                message.metadata?.workflow?.feedback_prompt || message.metadata?.workflow?.feedbackPrompt;
              const executionBlockedReason =
                message.metadata?.domainGuard?.blocked
                  ? message.metadata?.domainGuard?.reason
                  : message.metadata?.needsUserFeedback
                  ? message.metadata?.feedbackPrompt || "Please review and confirm before execution."
                  : workflowLevelDomainGuard?.blocked
                  ? workflowLevelDomainGuard?.reason
                  : workflowNeedsFeedback
                  ? workflowFeedbackPrompt || "Please review and confirm before execution."
                  : undefined;
              const prereqChecklist = normalizePrereqChecklist(
                message.metadata?.prerequisitesValidation,
                {
                  executionBlockedReason,
                  allowLowConfidenceOverride: !!executionBlockedReason,
                }
              );
              const effectiveBlockedReason = executionBlockedReason;

              // When this workflow is open in the right panel, render only an invisible
              // anchor div so scroll/invocation tracking still works. No visible card
              // in the chat — all workflow UI lives exclusively in the right panel.
              if (isInPanel) {
                return (
                  <div
                    id={`workflow-artifact-anchor-${message.id}`}
                    data-testid={`workflow-artifact-anchor-${message.id}`}
                    data-invocation-id={effectiveInvocationId || undefined}
                    data-run-anchor-focused={isRunAnchorFocused ? "true" : "false"}
                    data-run-anchor-highlighted={isRunAnchorHighlighted ? "true" : "false"}
                    data-tour="chat-handoff"
                  />
                );
              }

              // Disambiguation card — backend found several plausible workflows
              const isDisambiguation = message.metadata?.workflow?.workflow_type === 'disambiguation'
              if (isDisambiguation) {
                const wf = message.metadata?.workflow
                const candidates = (wf.candidates || []) as DisambigCandidate[]
                return (
                  <div
                    id={`workflow-artifact-anchor-${message.id}`}
                    data-testid={`workflow-artifact-anchor-${message.id}`}
                  >
                    <WorkflowDisambiguationCard
                      message={wf.message || 'Which workflow best fits what you need?'}
                      candidates={candidates}
                      onSelect={(c) => onAdjustViaChat?.(`Use ${c.display_name || c.name}`)}
                    />
                  </div>
                )
              }

              // Assembled sequential pipeline (Tier 2/3 assistant)
              const isPipelineWorkflow = message.metadata?.workflow?.workflow_type === 'pipeline'
              if (isPipelineWorkflow) {
                const wf = message.metadata?.workflow
                const steps = (wf.pipeline_steps || []).map((s: any, idx: number) => ({
                  id: s.id || `step-${idx}`,
                  stepNumber: idx + 1,
                  workflowName: s.workflow_name || s.name || `Step ${idx + 1}`,
                  workflowPath: s.workflow_path || s.nextflow_path,
                  nextflowPath: s.nextflow_path || s.workflow_path,
                  params: s.params || s.parameters || {},
                  status: s.status || 'pending' as const,
                  outputTypes: s.output_types || [],
                  usesStepId: s.uses_step_id || s.input_from,
                  usesDescription: s.uses_description || s.input_type,
                }))
                return (
                  <div
                    id={`workflow-artifact-anchor-${message.id}`}
                    data-testid={`workflow-artifact-anchor-${message.id}`}
                  >
                    <PipelineListView
                      steps={steps}
                      approvalGate
                      chainRunId={wf.chain_run_id}
                      onConfirmRun={() => onRunPipeline?.(wf)}
                      onApproveStep={(completedStepId, nextStepId) =>
                        onApprovePipelineStep?.(wf, completedStepId, nextStepId)
                      }
                      onModifyStep={(stepId, msg) => onAdjustViaChat?.(`Modify pipeline step ${stepId}: ${msg}`)}
                    />
                  </div>
                )
              }

              // Chain plan — curated multi-step pipeline returned by workflow_chains lookup
              const isChainWorkflow = message.metadata?.workflow?.workflow_type === 'chain'
              if (isChainWorkflow) {
                const wf = message.metadata?.workflow
                return (
                  <div
                    id={`workflow-artifact-anchor-${message.id}`}
                    data-testid={`workflow-artifact-anchor-${message.id}`}
                  >
                    <WorkflowChainPlan
                      chainName={wf.chain_name || wf.name || ''}
                      displayName={wf.chain_display_name || wf.display_name || wf.name || 'Pipeline Plan'}
                      domain={wf.chain_domain || wf.domain || ''}
                      description={wf.chain_description || wf.description || ''}
                      steps={wf.chain_steps || []}
                      connections={wf.chain_connections || []}
                      requiredInputs={wf.required_inputs || []}
                      expectedOutputs={wf.expected_outputs || []}
                      onRunChain={
                        onRunChain
                          ? () => onRunChain(wf)
                          : undefined
                      }
                    />
                  </div>
                )
              }

              return (
                <div
                  id={`workflow-artifact-anchor-${message.id}`}
                  data-testid={`workflow-artifact-anchor-${message.id}`}
                  data-invocation-id={effectiveInvocationId || undefined}
                  data-run-anchor-focused={isRunAnchorFocused ? "true" : "false"}
                  data-run-anchor-highlighted={isRunAnchorHighlighted ? "true" : "false"}
                  className={cn(
                    "rounded-md transition-all duration-700",
                    isRunAnchorHighlighted && "ring-2 ring-primary/60 bg-primary/5"
                  )}
                >
                  <NextflowWorkflowViewer
                    workflowDefinition={message.metadata?.workflow}
                    invocationId={invocationId}
                    workflowId={message.metadata?.workflow?.id}
                    executionBlockedReason={effectiveBlockedReason}
                    prereqChecklist={prereqChecklist}
                    dataVerification={message.metadata?.prerequisitesValidation?.dataVerification}
                    autofix={currentExecutionRun?.execution?.nextflowStatus?.autofix}
                    nextflowStatus={currentExecutionRun?.execution?.nextflowStatus}
                    status={currentExecutionRun ? viewerStatus : (message.metadata?.workflowViewerStatus || viewerStatus)}
                    errorMessage={currentExecutionRun?.execution?.errorMessage}
                    progress={workflowProgress}
                    onAdjustViaChat={onAdjustViaChat}
                    onWorkflowProgress={
                      onWorkflowProgress
                        ? (ev) => onWorkflowProgress({ ...ev, invocationId })
                        : undefined
                    }
                    onExecute={(params) => {
                      const userParams = Object.fromEntries(
                        Object.entries(params || {}).filter(([k]) => !k.startsWith('__'))
                      );
                      onRunWorkflow?.(
                        {
                          ...message.metadata?.workflow,
                          inline_parameters: {
                            ...(message.metadata?.workflow?.inline_parameters || {}),
                            ...userParams,
                          },
                          __generationAssessment: {
                            scientificConfidence: message.metadata?.confidence,
                            needsUserFeedback: !!message.metadata?.needsUserFeedback,
                            feedbackPrompt: message.metadata?.feedbackPrompt,
                            source: message.metadata?.source,
                            domainGuardBlocked: !!message.metadata?.domainGuard?.blocked,
                            domainGuardReason: message.metadata?.domainGuard?.reason,
                            candidateWorkflows: message.metadata?.candidateWorkflows || [],
                            toolInstallationSuccess:
                              message.metadata?.tool_installation?.success !== false,
                          },
                          __executionOverrides: params?.__executionOverrides || undefined,
                          __qcConfig: params?.__qcConfig || undefined,
                        },
                        message.metadata?.steps || []
                      );
                    }}
                    onParameterChange={(id, value) => onParameterChange?.(id, { value })}
                    onPause={onPauseWorkflow}
                    onResume={onResumeWorkflow}
                    onCancel={onStopWorkflow}
                    sessionId={sessionId}
                    runId={currentExecutionRun?.id}
                    executionEngine={currentExecutionRun?.execution?.executionEngine}
                  />
                </div>
              );
            })()
          )}

          {/* Additional parallel workflow cards for multi-intent queries (e.g. "RNA-seq AND ATAC-seq") */}
          {(message.metadata?.additionalWorkflows || []).map((wf: any, idx: number) => {
            const wfData = wf?.workflow_ga || wf;
            if (!wfData) return null;
            return (
              <div key={idx} className="mt-3">
                <NextflowWorkflowViewer
                  workflowDefinition={wfData}
                  status="pending_review"
                  onExecute={(params) =>
                    onRunWorkflow?.(
                      {
                        ...wfData,
                        __generationAssessment: {
                          scientificConfidence: message.metadata?.confidence,
                          needsUserFeedback: false,
                          feedbackPrompt: undefined,
                          source: wf?.source || 'chat',
                          domainGuardBlocked: false,
                          domainGuardReason: undefined,
                          candidateWorkflows: [],
                          toolInstallationSuccess: true,
                        },
                        __executionOverrides: params?.__executionOverrides || undefined,
                        __qcConfig: params?.__qcConfig || undefined,
                      },
                      Object.values(wfData.steps || {}).map((s: any) => ({
                        name: s.name || s.tool_id || 'Unknown step',
                        tool_id: s.tool_id || s.tool,
                        annotation: s.annotation || s.description,
                      }))
                    )
                  }
                  sessionId={sessionId}
                />
              </div>
            );
          })}

          {/* Scientific Rationale — collapsed by default, shown for generated workflows */}
          {isWorkflowMessage && message.metadata?.rationale && (
            <WorkflowRationale rationale={message.metadata.rationale} />
          )}

          {/* Output Attachments - Show when workflow execution completes */}
          {!isUser && effectiveInvocationId && (isWorkflowMessage || isRunAnchorFocused) && (
            <ChatOutputAttachments
              invocationId={effectiveInvocationId}
              sessionId={sessionId}
              runId={currentExecutionRun?.id}
              executionStatus={currentExecutionRun?.execution?.status}
              errorMessage={currentExecutionRun?.execution?.errorMessage}
            />
          )}

          {/* IND Report handoff chip — shown after ADMET or PBPK workflows complete */}
          {!isUser && (() => {
            const wfName: string = (
              message.metadata?.workflow?.name ||
              message.metadata?.workflow?.display_name || ""
            ).toLowerCase()
            const isAdmetOrPbpk =
              wfName.includes("predict_admet") ||
              wfName.includes("admet_properties") ||
              wfName.includes("pbpk_simulation") ||
              wfName.includes("pbpk")
            const isCompleted = currentExecutionRun?.execution?.status === "completed"
            if (!isAdmetOrPbpk || !isCompleted) return null
            const label = wfName.includes("pbpk")
              ? "PBPK qualification complete"
              : "ADMET screening complete"
            const invId = effectiveInvocationId
            return (
              <a
                href={`/ind-report?from_invocation=${invId}`}
                className="mt-2 flex items-center gap-2 rounded-lg border border-blue-200 bg-blue-50 px-3 py-2 text-xs text-blue-800 hover:bg-blue-100 dark:border-blue-800 dark:bg-blue-950/40 dark:text-blue-300 dark:hover:bg-blue-950/60 transition-colors w-fit"
                data-testid="ind-report-handoff-chip"
              >
                <svg className="h-3.5 w-3.5 shrink-0" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5">
                  <path d="M3 2h10a1 1 0 011 1v10a1 1 0 01-1 1H3a1 1 0 01-1-1V3a1 1 0 011-1z"/>
                  <path d="M5 6h6M5 8.5h4M5 11h3"/>
                </svg>
                <span>{label} — <strong>Generate IND §2.6 report from these results →</strong></span>
              </a>
            )
          })()}
        </div>

        {!isUser && (
          <div className="flex items-center gap-2 flex-wrap">
            <DownloadOutcomePrompt
              open={downloadPromptOpen}
              onOpenChange={setDownloadPromptOpen}
              invocationId={effectiveInvocationId}
              sessionId={sessionId}
              runId={currentExecutionRun?.id}
              isDownloadAll={true}
            />
            <Button
              variant="ghost"
              size="icon"
              onClick={handleCopyResponse}
              data-testid="button-copy-response-icon"
              title="Copy response"
              aria-label="Copy response"
            >
              <Copy className="h-4 w-4" />
            </Button>
            {/* Save response as file */}
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <Button
                  variant="ghost"
                  size="icon"
                  title="Save response as file"
                  aria-label="Save response as file"
                  data-testid="button-save-response"
                >
                  <FileDown className="h-4 w-4" />
                </Button>
              </DropdownMenuTrigger>
              <DropdownMenuContent align="start">
                <DropdownMenuItem
                  onClick={() => downloadAsTxt(message.content || '', message.content)}
                  className="gap-2"
                >
                  <FileText className="h-4 w-4" />
                  Save as .txt
                </DropdownMenuItem>
                <DropdownMenuItem
                  onClick={() => downloadAsMd(message.content || '', message.content)}
                  className="gap-2"
                >
                  <FileText className="h-4 w-4" />
                  Save as .md
                </DropdownMenuItem>
                <DropdownMenuItem
                  onClick={() => downloadAsDocx(message.content || '', message.content)}
                  className="gap-2"
                >
                  <FileDown className="h-4 w-4" />
                  Save as .docx
                </DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
            <Button
              variant="ghost"
              size="icon"
              onClick={onRegenerate}
              data-testid="button-regenerate-message-icon"
              title="Regenerate response"
              aria-label="Regenerate response"
            >
              <RotateCcw className="h-4 w-4" />
            </Button>
            <Button
              variant="ghost"
              size="icon"
              onClick={handleDownloadOutputs}
              data-testid="button-download-outputs-icon"
              title="Download outputs"
              aria-label="Download outputs"
              disabled={!effectiveInvocationId}
            >
              <Download className="h-4 w-4" />
            </Button>
            {(message.metadata?.type === 'workflow' || message.invocationId || hasGalaxyMetadata) && (
              <InlineFeedbackWidget
                messageId={message.id}
                sessionId={sessionId}
                runId={currentExecutionRun?.id}
                invocationId={effectiveInvocationId}
                workflowId={message.metadata?.workflow?.id ?? undefined}
              />
            )}
          </div>
        )}
        
        {/* Suggestion buttons hidden per UX request */}

        {!isUser && message.metadata?.type === "error" && (
          <div className="flex flex-wrap items-center gap-2 mt-2">
            <Button
              variant="outline"
              size="sm"
              data-testid="button-async-try-again"
              onClick={() => onSuggestionClick("Try again", message)}
            >
              Try again
            </Button>
            <ReportConfusionButton
              sessionId={sessionId}
              context={{
                source: "chat_error_message",
                errorType: message.metadata?.errorType,
                errorMessage: message.metadata?.errorMessage,
              }}
              variant="outline"
              size="sm"
              onClick={() => onSuggestionClick("Report issue", message)}
              className="h-8"
            />
          </div>
        )}
    </div>
  )
}