import { useState, useEffect } from "react"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Separator } from "@/components/ui/separator"
import { ChatInterface } from "./chat-interface"
import { EnhancedWorkflowBuilder } from "./enhanced-workflow-builder"
import { useWorkflowSync } from "../hooks/useWorkflowSync"
import { chatHistoryService } from "@/lib/chat-history"
import type { ChatSession } from "@shared/schema"
import { ResizablePanelGroup, ResizablePanel, ResizableHandle } from "@/components/ui/resizable"
import {
  Workflow,
  Play,
  Pause,
  CheckCircle,
  Clock,
  AlertTriangle,
  Settings,
  MessageCircle
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

const mockWorkflowProgress: WorkflowProgress = {
  id: "workflow-1",
  title: "RNA-seq Analysis Pipeline",
  description: "Processing transcriptomic data through quality control, alignment, and differential expression analysis",
  status: 'running',
  progress: 45,
  steps: [
    { id: "step1", name: "Quality Control", status: "completed", duration: "2m 15s" },
    { id: "step2", name: "Read Alignment", status: "running" },
    { id: "step3", name: "Gene Expression Quantification", status: "pending" },
    { id: "step4", name: "Differential Expression Analysis", status: "pending" },
    { id: "step5", name: "Generate Report", status: "pending" }
  ]
}

interface ToolItem {
  id: string
  name: string
  description: string
  complexity: 'simple' | 'intermediate' | 'complex'
  category: string
  icon: any
}

interface ChatWithArtifactsProps {
  currentChatSession: ChatSession | null
  onChatUpdated: (session: ChatSession) => void
}

export function ChatWithArtifacts({ currentChatSession, onChatUpdated }: ChatWithArtifactsProps) {
  const [showProgress, setShowProgress] = useState(false)

  // Use workflow sync hook for bidirectional state management
  const {
    workflowState,
    setWorkflowFromChat,
    updateWorkflow,
    updateStep,
    hasWorkflow,
    isFromChat,
  } = useWorkflowSync();

  // Load existing workflows when chat session changes
  useEffect(() => {
    console.log('ChatWithArtifacts: Chat session changed', currentChatSession?.id, 'workflows:', currentChatSession?.workflows)
    if (currentChatSession?.workflows && Array.isArray(currentChatSession.workflows) && currentChatSession.workflows.length > 0) {
      // Convert chat session workflows to workflow sync format
      const workflow = {
        id: 'workflow-' + currentChatSession.id,
        name: currentChatSession.workflows[0]?.tool ? `${currentChatSession.workflows[0].tool} Pipeline` : "Workflow from Chat",
        steps: currentChatSession.workflows,
      };

      console.log('ChatWithArtifacts: Loading workflow from session');
      setWorkflowFromChat(workflow);
      setShowProgress(true);
    } else {
      // No workflows in this session
      console.log('ChatWithArtifacts: No workflows in session');
      setShowProgress(false);
    }
  }, [currentChatSession, setWorkflowFromChat])
  
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

  const handleWorkflowGenerated = (workflow: any, metadata?: any) => {
    // This will be called when chat generates a new workflow with Galaxy Assistant
    console.log('ChatWithArtifacts: New workflow generated:', workflow, metadata);

    if (!workflow) {
      console.log('ChatWithArtifacts: No workflow to process');
      return;
    }

    // Set workflow using sync hook (handles both Galaxy .ga and simple formats)
    setWorkflowFromChat(workflow, metadata);
    setShowProgress(true);

    // Save to chat session if available
    if (currentChatSession) {
      const updatedSession = {
        ...currentChatSession,
        workflows: workflowState.workflowSteps.map(step => ({
          id: step.id,
          title: step.title,
          description: step.description,
          status: step.status,
          tool: step.tool || 'Unknown',
          complexity: step.complexity || 'simple' as const,
          estimatedTime: step.estimatedTime || '5 min',
          inputs: step.inputs || [],
          outputs: step.outputs || [],
        })),
      };
      console.log('ChatWithArtifacts: Saving workflow to session');
      onChatUpdated(updatedSession);
    }
  };

  // Handle workflow updates from workflow builder
  const handleWorkflowUpdate = (steps: any[]) => {
    console.log('ChatWithArtifacts: Workflow updated from builder:', steps.length, 'steps');
    updateWorkflow(steps);

    // Sync back to chat session
    if (currentChatSession) {
      const updatedSession = {
        ...currentChatSession,
        workflows: steps.map(step => ({
          id: step.id,
          title: step.title,
          description: step.description,
          status: step.status,
          tool: step.tool || 'Unknown',
          complexity: step.complexity || 'simple' as const,
          estimatedTime: step.estimatedTime || '5 min',
          inputs: step.inputs || [],
          outputs: step.outputs || [],
        })),
      };
      onChatUpdated(updatedSession);
    }
  }



  console.log('ChatWithArtifacts: Rendering with workflow:', hasWorkflow, 'showProgress:', showProgress)

  return (
    <div className="h-full flex flex-col">
      {/* Content */}
      <div className="flex-1 overflow-hidden">
            {hasWorkflow ? (
              <ResizablePanelGroup direction="horizontal" className="h-full">
                {/* Chat Section */}
                <ResizablePanel
                  defaultSize={60}
                  minSize={40}
                  className="flex flex-col"
                >
                  <ChatInterface
                    chatSession={currentChatSession}
                    onWorkflowGenerated={handleWorkflowGenerated}
                    onChatUpdated={onChatUpdated}
                    activeWorkflow={null}
                    showProgress={showProgress}
                    onToggleProgress={() => setShowProgress(!showProgress)}
                  />
                </ResizablePanel>

                <ResizableHandle withHandle />

                {/* Artifacts Panel - Only show when there's a workflow */}
                <ResizablePanel
                  defaultSize={40}
                  minSize={25}
                  className="flex flex-col bg-muted/30"
                  data-testid="artifacts-panel"
                >
                  <div className="p-4 border-b">
                    <div className="flex items-center gap-2">
                      <Workflow className="w-4 h-4" />
                      <h3 className="font-semibold">Workflow Builder</h3>
                      {isFromChat && (
                        <Badge variant="outline" className="text-xs">
                          Generated from Chat
                        </Badge>
                      )}
                    </div>
                    <p className="text-sm text-muted-foreground mt-1">
                      {workflowState.workflowName || 'Generated workflow'}
                    </p>
                  </div>

                  <ScrollArea className="flex-1">
                    <div className="p-4" data-testid="workflow-builder">
                      <EnhancedWorkflowBuilder
                        workflowSteps={workflowState.workflowSteps}
                        workflowName={workflowState.workflowName}
                        onGetHelp={() => console.log('Get help from artifacts')}
                      />
                    </div>
                  </ScrollArea>
                </ResizablePanel>
              </ResizablePanelGroup>
            ) : (
              <div className="h-full flex flex-col">
                <ChatInterface
                  chatSession={currentChatSession}
                  onWorkflowGenerated={handleWorkflowGenerated}
                  onChatUpdated={onChatUpdated}
                  activeWorkflow={null}
                  showProgress={showProgress}
                  onToggleProgress={() => setShowProgress(!showProgress)}
                />
              </div>
            )}
      </div>
    </div>
  )
}