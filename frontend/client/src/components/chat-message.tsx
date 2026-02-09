import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar"
import { Button } from "@/components/ui/button"
import { Card } from "@/components/ui/card"
import { Copy, RotateCcw, Workflow } from "lucide-react"
import { cn, getSimpleToolName } from "@/lib/utils"
import { GalaxyRecommendations } from "./galaxy-recommendations"
import { ChatOutputAttachments } from "./chat-output-attachments"
import { ThinkingDisplay } from "./thinking-display"
import { WorkflowArtifact } from "./workflow-artifact"
import { BenchmarkEvidence, ResearchResponseDisplay } from "./benchmark-evidence"
import assistantAvatar from "@assets/generated_images/AI_assistant_avatar_8313ba2b.png"
import userAvatar from "@assets/generated_images/User_avatar_placeholder_d2803d15.png"

// Use the shared Message type for consistency
import type { ExecutionRun, Message } from '@shared/schema'
export type { Message }

interface ChatMessageProps {
  message: Message
  onCopy?: () => void
  onRegenerate?: () => void
  onCreateWorkflow?: () => void
  onToolClick?: (tool: any) => void
  onDatasetClick?: (dataset: any) => void
  onRunWorkflow?: (workflow: any, steps: any[]) => void
  onStopWorkflow?: () => void
  onParameterChange?: (stepId: string, params: Record<string, any>) => void
  isWorkflowRunning?: boolean
  workflowProgress?: number
  currentExecutionRun?: ExecutionRun | null
}

export function ChatMessage({
  message,
  onCopy = () => console.log('Copy message triggered'),
  onRegenerate = () => console.log('Regenerate message triggered'),
  onCreateWorkflow = () => console.log('Create workflow triggered'),
  onToolClick,
  onDatasetClick,
  onRunWorkflow,
  onStopWorkflow,
  onParameterChange,
  isWorkflowRunning = false,
  workflowProgress = 0,
  currentExecutionRun,
}: ChatMessageProps) {
  const isUser = message.role === "user"

  // Extract Galaxy Assistant metadata
  const hasGalaxyMetadata = message.metadata && (
    message.metadata.recommendedTools ||
    message.metadata.recommendedDatasets
  )

  return (
    <div
      className={cn("flex gap-4 p-4", isUser && "flex-row-reverse")}
      data-testid={`chat-message-${message.id}`}
      data-role={message.role}
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

          {/* Workflow Artifact - Interactive inline workflow display */}
          {!isUser && message.metadata?.type === 'workflow' && message.metadata?.workflow && (
            <WorkflowArtifact
              workflow={message.metadata.workflow}
              steps={message.metadata.steps || []}
              confidence={message.metadata.confidence || 0}
              onRun={onRunWorkflow}
              onStop={onStopWorkflow}
              onParameterChange={onParameterChange}
              isRunning={isWorkflowRunning}
              progress={workflowProgress}
              className="mt-2"
              // Citation and pilot run props from workflow generation
              citations={message.metadata.citations || []}
              methodsSection={message.metadata.methods_section}
              pilotRunSuggested={message.metadata.pilot_run_suggested || false}
              pilotReasons={message.metadata.pilot_reasons || []}
              pilotMessage={message.metadata.pilot_message}
              totalSamples={message.metadata.total_samples || 0}
              tuningConfig={message.metadata.tuning_config}
              parameterRecommendations={message.metadata.parameter_recommendations || {}}
              // Validation info for transparency
              validationIssues={message.metadata.validation?.issues || []}
              validationWarnings={message.metadata.validation?.warnings || []}
              // Prerequisites validation (input data, parameters needed)
              prerequisitesValidation={message.metadata.prerequisitesValidation}
              // Execution engine detection
              executionEngine={message.metadata.execution_engine}
              workflowTags={message.metadata.workflow_tags || []}
              // Invocation ID for workflow report viewer
              invocationId={message.invocationId}
              galaxyWorkflowId={currentExecutionRun?.execution?.galaxyWorkflowId}
              currentExecutionRun={currentExecutionRun || undefined}
            />
          )}

          {/* Output Attachments - Show when workflow execution completes */}
          {!isUser && message.invocationId && (
            <ChatOutputAttachments invocationId={message.invocationId} />
          )}
        </div>

        {!isUser && (
          <div className="flex items-center gap-2">
            <Button
              variant="ghost"
              size="sm"
              onClick={onCopy}
              data-testid="button-copy-message"
            >
              <Copy className="h-3 w-3 mr-1" />
              Copy
            </Button>
            <Button
              variant="ghost"
              size="sm"
              onClick={onRegenerate}
              data-testid="button-regenerate-message"
            >
              <RotateCcw className="h-3 w-3 mr-1" />
              Regenerate
            </Button>
            <Button
              variant="ghost"
              size="sm"
              onClick={onCreateWorkflow}
              data-testid="button-create-workflow"
            >
              <Workflow className="h-3 w-3 mr-1" />
              Create Workflow
            </Button>
          </div>
        )}
        
        {message.suggestions && message.suggestions.length > 0 && (
          <div className="flex flex-wrap gap-2 mt-2">
            {message.suggestions.map((suggestion: string, index: number) => (
              <Button
                key={index}
                variant="outline"
                size="sm"
                onClick={() => console.log('Suggestion clicked:', suggestion)}
                data-testid={`button-suggestion-${index}`}
              >
                {suggestion}
              </Button>
            ))}
          </div>
        )}
      </div>
    </div>
  )
}