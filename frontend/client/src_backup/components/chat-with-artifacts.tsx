import { useState, useEffect } from "react"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Separator } from "@/components/ui/separator"
import { ChatInterface } from "./chat-interface"
import { EnhancedWorkflowBuilder } from "./enhanced-workflow-builder"
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
  const [activeWorkflow, setActiveWorkflow] = useState<WorkflowProgress | null>(null)
  
  // Load existing workflows when chat session changes
  useEffect(() => {
    console.log('ChatWithArtifacts: Chat session changed', currentChatSession?.id, 'workflows:', currentChatSession?.workflows)
    if (currentChatSession?.workflows && Array.isArray(currentChatSession.workflows) && currentChatSession.workflows.length > 0) {
      // Convert all workflow steps from the session to WorkflowProgress format
      // Preserve all the original metadata from WorkflowStepWithDatasets
      const workflowSteps = currentChatSession.workflows
      const workflowProgress: WorkflowProgress = {
        id: 'workflow-' + currentChatSession.id,
        title: workflowSteps[0]?.tool ? `${workflowSteps[0].tool} Pipeline` : "Workflow from Chat",
        description: "Workflow loaded from chat history",
        status: 'pending', // TODO: Calculate overall status from steps
        progress: 0, // TODO: Calculate progress from completed steps
        steps: workflowSteps.map((step, index) => ({
          id: step.id || `step-${index}`,
          name: step.title || `Step ${index + 1}`,
          status: step.status || 'pending' as const,
          duration: step.estimatedTime // Preserve timing info
        }))
      }
      
      console.log('ChatWithArtifacts: Loading workflow from session', workflowProgress)
      setActiveWorkflow(workflowProgress)
      setShowProgress(true)
    } else {
      // No workflows in this session, clear the active workflow
      console.log('ChatWithArtifacts: No workflows in session, clearing')
      setActiveWorkflow(null)
      setShowProgress(false)
    }
  }, [currentChatSession])
  
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

  const handleWorkflowGenerated = (workflow: any) => {
    // This will be called when chat generates a new workflow
    console.log('ChatWithArtifacts: New workflow generated:', workflow)
    
    if (workflow && workflow.id && currentChatSession) {
      // Convert the generated workflow to our progress format
      const workflowProgress: WorkflowProgress = {
        id: workflow.id,
        title: workflow.title || "Generated Workflow",
        description: workflow.description || "Workflow generated from conversation",
        status: 'pending',
        progress: 0,
        steps: workflow.steps?.map((step: any, index: number) => ({
          id: step.id || `step-${index}`,
          name: step.title || step.name || `Step ${index + 1}`,
          status: 'pending' as const,
        })) || []
      }
      
      console.log('ChatWithArtifacts: Setting active workflow:', workflowProgress)
      setActiveWorkflow(workflowProgress)
      setShowProgress(true)
      
      // Save the workflow steps to the chat session
      // The workflows field expects an array of WorkflowStepWithDatasets
      const workflowSteps = workflow.steps?.map((step: any) => ({
        id: step.id,
        title: step.title,
        description: step.description,
        status: 'pending' as const,
        tool: step.tool || 'Unknown',
        complexity: step.complexity || 'simple' as const,
        estimatedTime: step.estimatedTime,
        inputs: step.inputs || [],
        outputs: step.outputs || []
      })) || []
      
      const updatedSession = {
        ...currentChatSession,
        workflows: workflowSteps
      }
      console.log('ChatWithArtifacts: Saving workflow steps to session:', updatedSession)
      onChatUpdated(updatedSession)
    } else {
      console.log('ChatWithArtifacts: Invalid workflow data or missing session:', { workflow, hasCurrentSession: !!currentChatSession })
    }
  }



  console.log('ChatWithArtifacts: Rendering with activeWorkflow:', activeWorkflow, 'showProgress:', showProgress)
  
  return (
    <div className="h-full flex flex-col">
      {/* Content */}
      <div className="flex-1 overflow-hidden">
            {activeWorkflow ? (
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
                    activeWorkflow={activeWorkflow}
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
                      <h3 className="font-semibold">Workflow Artifacts</h3>
                    </div>
                    <p className="text-sm text-muted-foreground mt-1">
                      Generated workflows and tools
                    </p>
                  </div>
                  
                  <ScrollArea className="flex-1">
                    <div className="p-4" data-testid="workflow-builder">
                      <EnhancedWorkflowBuilder
                        workflowSteps={currentChatSession?.workflows?.map((step, index) => ({
                          id: step.id,
                          title: step.title,
                          description: step.description,
                          status: step.status,
                          tool: step.tool,
                          complexity: step.complexity,
                          estimatedTime: step.estimatedTime || "5 min",
                          inputs: step.inputs,
                          outputs: step.outputs
                        })) || activeWorkflow.steps.map((step, index) => ({
                          id: step.id,
                          title: step.name,
                          description: `Generated step: ${step.name}`,
                          status: step.status,
                          tool: "Auto-selected",
                          complexity: index < 2 ? "simple" : index < 4 ? "intermediate" : "complex",
                          estimatedTime: step.duration || "5 min"
                        }))}
                        workflowName={activeWorkflow.title}
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
                  activeWorkflow={activeWorkflow}
                  showProgress={showProgress}
                  onToggleProgress={() => setShowProgress(!showProgress)}
                />
              </div>
            )}
      </div>
    </div>
  )
}