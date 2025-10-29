import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar"
import { Button } from "@/components/ui/button"
import { Card } from "@/components/ui/card"
import { Copy, RotateCcw, Workflow } from "lucide-react"
import { cn } from "@/lib/utils"
import { GalaxyRecommendations } from "./galaxy-recommendations"
import { ChatOutputAttachments } from "./chat-output-attachments"
import assistantAvatar from "@assets/generated_images/AI_assistant_avatar_8313ba2b.png"
import userAvatar from "@assets/generated_images/User_avatar_placeholder_d2803d15.png"

// Use the shared Message type for consistency
export type { Message } from '@shared/schema'

interface ChatMessageProps {
  message: Message
  onCopy?: () => void
  onRegenerate?: () => void
  onCreateWorkflow?: () => void
  onToolClick?: (tool: any) => void
  onDatasetClick?: (dataset: any) => void
}

export function ChatMessage({
  message,
  onCopy = () => console.log('Copy message triggered'),
  onRegenerate = () => console.log('Regenerate message triggered'),
  onCreateWorkflow = () => console.log('Create workflow triggered'),
  onToolClick,
  onDatasetClick,
}: ChatMessageProps) {
  const isUser = message.role === "user"

  // Extract Galaxy Assistant metadata
  const hasGalaxyMetadata = message.metadata && (
    message.metadata.recommendedTools ||
    message.metadata.recommendedDatasets
  )

  return (
    <div className={cn("flex gap-4 p-4", isUser && "flex-row-reverse")} data-testid={`chat-message-${message.id}`}>
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

          {/* Galaxy Assistant Recommendations */}
          {!isUser && hasGalaxyMetadata && (
            <GalaxyRecommendations
              tools={message.metadata?.recommendedTools}
              datasets={message.metadata?.recommendedDatasets}
              onToolClick={onToolClick}
              onDatasetClick={onDatasetClick}
            />
          )}

          {/* Workflow Display */}
          {!isUser && message.metadata?.type === 'workflow' && message.metadata?.workflow && (
            <Card className="p-4 bg-muted/50" data-testid="workflow-generated-message">
              <div className="space-y-3">
                <div>
                  <h4 className="font-semibold text-sm">{message.metadata.workflow.name || 'Generated Workflow'}</h4>
                  {message.metadata.steps && message.metadata.steps.length > 0 && (
                    <p className="text-xs text-muted-foreground mt-1">
                      {message.metadata.steps.length} steps • Confidence: {((message.metadata.confidence || 0) * 100).toFixed(1)}%
                    </p>
                  )}
                </div>
                {message.metadata.workflow.annotation && (
                  <p className="text-xs text-muted-foreground">
                    {message.metadata.workflow.annotation}
                  </p>
                )}
                {message.metadata.steps && message.metadata.steps.length > 0 && (
                  <div className="space-y-1">
                    {message.metadata.steps.slice(0, 5).map((step: any, idx: number) => (
                      <div key={idx} className="flex items-center gap-2 text-xs">
                        <span className="font-mono text-muted-foreground">{idx + 1}.</span>
                        <span>{step.name || step.tool_id || 'Unknown step'}</span>
                      </div>
                    ))}
                    {message.metadata.steps.length > 5 && (
                      <p className="text-xs text-muted-foreground">
                        ...and {message.metadata.steps.length - 5} more steps
                      </p>
                    )}
                  </div>
                )}
                <Button
                  variant="default"
                  size="sm"
                  onClick={onCreateWorkflow}
                  className="w-full"
                  data-testid="button-open-workflow-builder"
                >
                  <Workflow className="h-3 w-3 mr-1" />
                  Open in Workflow Builder
                </Button>
              </div>
            </Card>
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