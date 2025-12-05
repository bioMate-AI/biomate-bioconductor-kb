import { useState } from "react"
import { ChatInterface } from "./chat-interface"
import { WorkflowHistoryPanel } from "./workflow-history-panel"
import { chatHistoryService } from "@/lib/chat-history"
import type { ChatSession } from "@shared/schema"
import { MessageCircle } from "lucide-react"

interface ChatWithArtifactsProps {
  currentChatSession: ChatSession | null
  onChatUpdated: (session: ChatSession) => void
}

/**
 * Chat-first layout: Full-width chat with workflows displayed inline as artifacts.
 * No split panel - workflows appear as collapsible cards within chat messages.
 */
export function ChatWithArtifacts({ currentChatSession, onChatUpdated }: ChatWithArtifactsProps) {
  const [isWorkflowRunning, setIsWorkflowRunning] = useState(false)
  const [workflowProgress, setWorkflowProgress] = useState(0)

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

  const handleRunWorkflow = async () => {
    console.log('ChatWithArtifacts: Running workflow');
    setIsWorkflowRunning(true);
    setWorkflowProgress(0);

    // TODO: Integrate with Galaxy workflow execution
    // The actual execution will be handled by ChatInterface when it invokes the workflow
  };

  const handleStopWorkflow = () => {
    console.log('ChatWithArtifacts: Stopping workflow');
    setIsWorkflowRunning(false);
    setWorkflowProgress(0);
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

  return (
    <div className="h-full flex flex-col">
      {/* Minimal Header */}
      <div className="border-b bg-background/95 backdrop-blur supports-[backdrop-filter]:bg-background/60">
        <div className="flex items-center justify-between px-4 py-2">
          <div className="flex items-center gap-2">
            <MessageCircle className="w-5 h-5 text-primary" />
            <h2 className="font-semibold">bioMate</h2>
          </div>
          <WorkflowHistoryPanel />
        </div>
      </div>

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
          onStopWorkflow={handleStopWorkflow}
          onParameterChange={handleParameterChange}
          isWorkflowRunning={isWorkflowRunning}
          workflowProgress={workflowProgress}
        />
      </div>
    </div>
  )
}
