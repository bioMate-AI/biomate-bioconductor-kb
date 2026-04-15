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
import { Copy, RotateCcw, Download, FileJson, FileText, FileDown, FlaskConical, PanelRight } from "lucide-react"
import { cn, getSimpleToolName } from "@/lib/utils"
import { downloadAsTxt, downloadAsMd, downloadAsDocx } from "@/lib/download-response"
import { GalaxyRecommendations } from "./galaxy-recommendations"
import { ChatOutputAttachments } from "./chat-output-attachments"
import { ThinkingDisplay } from "./thinking-display"
import { NextflowWorkflowViewer } from "./nextflow-workflow-viewer"
import { WorkflowChainPlan } from "./workflow-chain-plan"
import { WorkflowDisambiguationCard } from "./workflow-disambiguation-card"
import { PipelineListView } from "./pipeline-list-view"
import { BenchmarkEvidence, ResearchResponseDisplay } from "./benchmark-evidence"
import { InlineFeedbackWidget } from "./feedback/inline-feedback-widget"
import { DownloadOutcomePrompt } from "./feedback/download-outcome-prompt"
import { ReportConfusionButton } from "./feedback/report-confusion-button"
import { useToast } from "@/hooks/use-toast"
import { normalizePrereqChecklist } from "@/lib/prereq-normalizer"
import assistantAvatar from "@assets/generated_images/AI_assistant_avatar_8313ba2b.png"
import userAvatar from "@assets/generated_images/User_avatar_placeholder_d2803d15.png"

// Use the shared Message type for consistency
import type { ExecutionRun, Message } from '@shared/schema'
export type { Message }

interface ChatMessageProps {
  message: Message
  sessionId?: string
  onCopy?: () => void
  onRegenerate?: () => void
  onCreateWorkflow?: () => void
  onToolClick?: (tool: any) => void
  onDatasetClick?: (dataset: any) => void
  onRunWorkflow?: (workflow: any, steps: any[]) => void
  onStopWorkflow?: () => void
  onPauseWorkflow?: () => void
  onResumeWorkflow?: () => void
  onParameterChange?: (stepId: string, params: Record<string, any>) => void
  onSuggestionClick?: (suggestion: string, message: Message) => void
  onAdjustViaChat?: (message?: string) => void
  isWorkflowRunning?: boolean
  workflowProgress?: number
  currentExecutionRun?: ExecutionRun | null
  isLatestAssistantMessage?: boolean
  isGeneratingWorkflow?: boolean
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
  onStopWorkflow,
  onPauseWorkflow,
  onResumeWorkflow,
  onParameterChange,
  onSuggestionClick = () => {},
  onAdjustViaChat,
  isWorkflowRunning = false,
  workflowProgress = 0,
  currentExecutionRun,
  isLatestAssistantMessage = false,
  isGeneratingWorkflow = false,
  isRunAnchorFocused = false,
  isRunAnchorHighlighted = false,
  isInPanel = false,
  onOpenInPanel,
}: ChatMessageProps) {
  const isUser = message.role === "user"
  const isWorkflowMessage = !isUser && message.metadata?.type === "workflow" && !!message.metadata?.workflow
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

  return (
    <div
      className={cn("flex gap-4 p-4", isUser && "flex-row-reverse")}
      id={`chat-message-anchor-${message.id}`}
      data-testid={`chat-message-${message.id}`}
      data-role={message.role}
      data-run-anchor-focused={isRunAnchorFocused ? "true" : "false"}
      data-run-anchor-highlighted={isRunAnchorHighlighted ? "true" : "false"}
      data-is-latest-assistant={isLatestAssistantMessage ? "true" : "false"}
    >
      <Avatar className="h-8 w-8 flex-shrink-0">
        <AvatarImage 
          src={isUser ? userAvatar : assistantAvatar} 
          alt={isUser ? "User" : "Assistant"} 
        />
        <AvatarFallback>{isUser ? "U" : "AI"}</AvatarFallback>
      </Avatar>
      
      <div className={cn("flex-1 space-y-2", isUser && "flex flex-col items-end")}>
        <div className="max-w-full space-y-3">
          <Card className={cn(
            "p-4",
            isUser
              ? "bg-primary text-primary-foreground ml-auto"
              : "bg-card"
          )}>
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
                  }}
                >
                  {addCitationLinks(message.content || '')}
                </ReactMarkdown>
              </div>
              </>
            )}
          </Card>

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

          {/* Workflow panel loading skeleton — shown while streaming is still ongoing */}
          {isGeneratingWorkflow && !isWorkflowMessage && (
            <div className="mt-3 rounded-lg border border-border bg-muted/30 p-4 flex items-center gap-3 animate-pulse">
              <div className="h-5 w-5 rounded-full bg-primary/20 flex-shrink-0" />
              <div className="flex-1 space-y-2">
                <div className="h-3 w-48 rounded bg-muted-foreground/20" />
                <div className="h-2 w-32 rounded bg-muted-foreground/10" />
              </div>
              <span className="text-xs text-muted-foreground flex-shrink-0">Preparing workflow panel…</span>
            </div>
          )}

          {/* Nextflow Workflow Viewer - Replaces WorkflowArtifact */}
          {isWorkflowMessage && (
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
              const inlineParams = message.metadata?.workflow?.inline_parameters || {};
              // hasInlineData: true only for actual biological content (SMILES, FASTA, multi-line data),
              // NOT for simple file paths like "beta_gal.mrc" which must be uploaded separately.
              const FILE_PATH_RE = /^[\w./~\-]+\.(mrc|pdb|cif|tif|tiff|eer|fastq|fq|bam|sam|vcf|gz|zip|tar|hdf5|h5|ccp4|map|spi|xmf|star|mrcs|xtc|gro|top|itp|mol2|sdf|sd)$/i;
              const hasInlineData = Object.values(inlineParams).some((v: any) => {
                if (v == null) return false;
                const s = String(v).trim();
                if (!s || s.length < 3) return false;
                // Reject bare file paths — these need to be uploaded, not pasted as inline data
                if (FILE_PATH_RE.test(s)) return false;
                return true;
              });
              const prereqChecklist = normalizePrereqChecklist(
                message.metadata?.prerequisitesValidation,
                {
                  executionBlockedReason,
                  allowLowConfidenceOverride: !!executionBlockedReason,
                  hasInlineData,
                }
              );
              const effectiveBlockedReason = executionBlockedReason;

              // When this workflow is open in the right panel, show a compact pill instead
              if (isInPanel) {
                const workflowName = message.metadata?.workflow?.name || 'Generated Workflow';
                const effectiveStatus: string = currentExecutionRun ? viewerStatus : (message.metadata?.workflowViewerStatus || viewerStatus)
                const statusLabel =
                  effectiveStatus === 'running' ? 'Running' :
                  effectiveStatus === 'completed' ? 'Completed' :
                  effectiveStatus === 'failed' ? 'Failed' :
                  effectiveStatus === 'paused' ? 'Paused' :
                  effectiveStatus === 'pending_review' ? 'Awaiting Review' :
                  'Ready';
                return (
                  <div
                    id={`workflow-artifact-anchor-${message.id}`}
                    data-testid={`workflow-artifact-anchor-${message.id}`}
                    data-invocation-id={effectiveInvocationId || undefined}
                    data-run-anchor-focused={isRunAnchorFocused ? "true" : "false"}
                    data-run-anchor-highlighted={isRunAnchorHighlighted ? "true" : "false"}
                    className="flex items-center gap-2 rounded-lg border border-border/60 bg-muted/30 px-3 py-2 text-sm"
                  >
                    <FlaskConical className="h-4 w-4 flex-shrink-0 text-muted-foreground" />
                    <span className="font-medium truncate flex-1">{workflowName}</span>
                    <span className="text-xs text-muted-foreground flex-shrink-0">{statusLabel}</span>
                    <button
                      className="ml-auto flex items-center gap-1 text-xs text-primary hover:text-primary/80 flex-shrink-0"
                      onClick={onOpenInPanel}
                      title="View workflow in panel"
                    >
                      <PanelRight className="h-3 w-3" />
                      View
                    </button>
                  </div>
                );
              }

              // Dynamic multi-step pipeline — AI-generated sequential execution plan
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
                      onConfirmRun={() => {
                        fetch('/api/workflows/chain', {
                          method: 'POST',
                          headers: { 'Content-Type': 'application/json' },
                          body: JSON.stringify({
                            workflow_name: wf.name || wf.chain_name || 'Pipeline',
                            workflow_steps: steps.map((s: any) => ({
                              nextflow_path: s.nextflowPath || s.workflowPath,
                              params: s.params,
                            })),
                          }),
                        }).catch(console.error);
                      }}
                      onModifyStep={(stepId, msg) => onAdjustViaChat?.(`Modify pipeline step ${stepId}: ${msg}`)}
                    />
                  </div>
                )
              }

              // Disambiguation — backend found multiple close-scoring candidates
              const isDisambiguation = message.metadata?.workflow?.workflow_type === 'disambiguation'
              if (isDisambiguation) {
                const wf = message.metadata?.workflow
                const candidates = wf?.candidates || []
                if (candidates.length > 0) {
                  return (
                    <div
                      id={`workflow-artifact-anchor-${message.id}`}
                      data-testid={`workflow-artifact-anchor-${message.id}`}
                    >
                      <WorkflowDisambiguationCard
                        message={wf.message || "I found several workflows that could match. Which best fits your needs?"}
                        candidates={candidates}
                        onSelect={(c) => {
                          onAdjustViaChat?.(`I want to use ${c.display_name}`)
                        }}
                      />
                    </div>
                  )
                }
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
                  {onOpenInPanel && (
                    <div className="flex justify-end mb-1 px-1">
                      <button
                        data-testid="button-open-workflow-in-panel"
                        onClick={onOpenInPanel}
                        className="text-xs text-muted-foreground flex items-center gap-1 hover:text-foreground transition-colors"
                        title="View in side panel"
                      >
                        <PanelRight className="h-3 w-3" />
                        Open in panel →
                      </button>
                    </div>
                  )}
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
                    executionMetrics={currentExecutionRun?.metrics}
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

          {/* Output Attachments are shown inside NextflowWorkflowViewer (View Results button).
              Rendering them here too caused a duplicate panel — removed. */}
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
            {/* Copy workflow JSON — disabled for now
            {message.metadata?.workflow && (
              <Button
                variant="ghost"
                size="icon"
                onClick={handleCopyWorkflow}
                data-testid="button-copy-workflow-icon"
                title="Copy workflow JSON"
                aria-label="Copy workflow JSON"
              >
                <FileJson className="h-4 w-4" />
              </Button>
            )} */}
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
    </div>
  )
}