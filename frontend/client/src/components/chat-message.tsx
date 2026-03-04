import { useState } from "react"
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar"
import { Button } from "@/components/ui/button"
import { Card } from "@/components/ui/card"
import { Copy, RotateCcw, Workflow, Download, FileJson } from "lucide-react"
import { cn, getSimpleToolName } from "@/lib/utils"
import { GalaxyRecommendations } from "./galaxy-recommendations"
import { ChatOutputAttachments } from "./chat-output-attachments"
import { ThinkingDisplay } from "./thinking-display"
import { NextflowWorkflowViewer } from "./nextflow-workflow-viewer"
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
  onRequestPrereqRecovery?: () => void
  onStopWorkflow?: () => void
  onParameterChange?: (stepId: string, params: Record<string, any>) => void
  onSuggestionClick?: (suggestion: string, message: Message) => void
  isWorkflowRunning?: boolean
  workflowProgress?: number
  currentExecutionRun?: ExecutionRun | null
  isLatestAssistantMessage?: boolean
  isRunAnchorFocused?: boolean
  isRunAnchorHighlighted?: boolean
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
  onRequestPrereqRecovery,
  onStopWorkflow,
  onParameterChange,
  onSuggestionClick = () => {},
  isWorkflowRunning = false,
  workflowProgress = 0,
  currentExecutionRun,
  isLatestAssistantMessage = false,
  isRunAnchorFocused = false,
  isRunAnchorHighlighted = false,
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
            <p className="text-sm leading-relaxed whitespace-pre-wrap">
              {message.content}
            </p>
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

          {/* Nextflow Workflow Viewer - Replaces WorkflowArtifact */}
          {isWorkflowMessage && (
            (() => {
              const invocationId = effectiveInvocationId;
              const executionStatus = currentExecutionRun?.execution?.status || (isWorkflowRunning ? 'running' : 'idle');
              const viewerStatus: 'idle' | 'running' | 'completed' | 'failed' =
                executionStatus === 'completed'
                  ? 'completed'
                  : executionStatus === 'failed' || executionStatus === 'cancelled'
                  ? 'failed'
                  : executionStatus === 'running'
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
                  toolInstallationSuccess:
                    message.metadata?.tool_installation?.success === false
                      ? false
                      : message.metadata?.tool_installation?.success === true
                      ? true
                      : undefined,
                  allowLowConfidenceOverride: !!executionBlockedReason,
                  allowPrereqRecovery: !!message.metadata?.prereqRecovery?.approved,
                }
              );
              const effectiveBlockedReason = executionBlockedReason;

              return (
                <div
                  id={`workflow-artifact-anchor-${message.id}`}
                  data-testid={`workflow-artifact-anchor-${message.id}`}
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
                    autofix={currentExecutionRun?.execution?.nextflowStatus?.autofix}
                    nextflowStatus={currentExecutionRun?.execution?.nextflowStatus}
                    status={viewerStatus}
                    errorMessage={currentExecutionRun?.execution?.errorMessage}
                    progress={workflowProgress}
                    onExecute={(params) =>
                      onRunWorkflow?.(
                        {
                          ...message.metadata?.workflow,
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
                        },
                        message.metadata?.steps || []
                      )
                    }
                    onParameterChange={(id, value) => onParameterChange?.(id, { value })}
                    onRequestPrereqRecovery={onRequestPrereqRecovery}
                    sessionId={sessionId}
                    runId={currentExecutionRun?.id}
                  />
                </div>
              );
            })()
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
              onClick={onCreateWorkflow}
              data-testid="button-create-workflow-icon"
              title="Create workflow"
              aria-label="Create workflow"
            >
              <Workflow className="h-4 w-4" />
            </Button>
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
            )}
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
        
        {message.suggestions && message.suggestions.length > 0 && (
          <div className="flex flex-wrap gap-2 mt-2">
            {message.suggestions.map((suggestion: string, index: number) => (
              <Button
                key={index}
                variant="outline"
                size="sm"
                onClick={() => onSuggestionClick(suggestion, message)}
                data-testid={`button-suggestion-${index}`}
              >
                {suggestion}
              </Button>
            ))}
          </div>
        )}

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