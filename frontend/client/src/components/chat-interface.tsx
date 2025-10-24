import { useState, useEffect, useRef } from "react"
import { ChatMessage, type Message } from "./chat-message"
import { ChatInput } from "./chat-input"
import { TypingIndicator } from "./typing-indicator"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Separator } from "@/components/ui/separator"
import { Card } from "@/components/ui/card"
import { useMutation } from "@tanstack/react-query"
import { apiRequest } from "@/lib/queryClient"
import { chatHistoryService } from "@/lib/chat-history"
import type { ChatSession } from "@shared/schema"
import { 
  ChevronRight, 
  ChevronDown,
  Play, 
  Pause, 
  CheckCircle, 
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
}

export function ChatInterface({ 
  chatSession,
  onSendMessage = (msg) => console.log('Send message:', msg),
  isTyping = false,
  className,
  onWorkflowGenerated = (workflow) => console.log('Workflow generated:', workflow),
  onChatUpdated,
  activeWorkflow,
  showProgress,
  onToggleProgress
}: ChatInterfaceProps) {
  const [isTypingLocal, setIsTypingLocal] = useState(false)
  const scrollRef = useRef<HTMLDivElement>(null)
  
  // Use messages from chat session or empty array if no session
  const displayMessages = chatSession?.messages || []
  const displayTyping = isTyping || isTypingLocal

  // Debug: Log message count
  useEffect(() => {
    console.log('[ChatInterface] displayMessages count:', displayMessages.length)
    console.log('[ChatInterface] displayMessages IDs:', displayMessages.map(m => m.id))
  }, [displayMessages])

  useEffect(() => {
    if (scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight
    }
  }, [displayMessages, displayTyping])

  // Galaxy Workflow Generation API integration (via Vite proxy)
  const chatMutation = useMutation({
    mutationFn: async (content: string) => {
      const response = await fetch('/api/ai_assistant/generate_workflow', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ request_text: content })
      })
      if (!response.ok) {
        throw new Error(`Galaxy API error: ${response.statusText}`)
      }
      return await response.json()
    },
    onSuccess: (data) => {
      console.log('[ChatInterface] API Response:', data)

      // Galaxy API response format
      const workflowInfo = data.success && data.workflow_ga ?
        `✅ ${data.message}\n\n${data.workflow_ga.annotation || 'Workflow generated successfully'}` :
        'Workflow generation completed'

      // Convert workflow_ga.steps object to array
      const stepsArray = data.workflow_ga?.steps ?
        Object.values(data.workflow_ga.steps).map((step: any) => ({
          name: step.name || step.tool_id || 'Unknown step',
          tool_id: step.tool_id,
          annotation: step.annotation
        })) : []

      console.log('[ChatInterface] Steps array:', stepsArray)

      const aiMessage: Message = {
        id: (Date.now() + 1).toString(),
        content: workflowInfo,
        role: "assistant",
        timestamp: new Date(),
        suggestions: data.success ? ["Open in Workflow Builder", "Show details", "Generate another"] : ["Try again", "Refine request"],
        metadata: {
          type: data.success ? 'workflow' : 'text',
          workflow: data.workflow_ga,
          steps: stepsArray,
          confidence: data.confidence,
          source: data.source
        }
      }

      console.log('[ChatInterface] Created AI message:', {
        id: aiMessage.id,
        metadata: aiMessage.metadata,
        hasWorkflow: !!aiMessage.metadata?.workflow,
        metadataType: aiMessage.metadata?.type
      })

      // Add message to chat session (create one if it doesn't exist)
      if (chatSession) {
        console.log('[ChatInterface] Adding message to existing session:', chatSession.id)
        const updatedSession = chatHistoryService.addMessage(chatSession.id, aiMessage)
        console.log('[ChatInterface] Updated session:', updatedSession?.messages.length, 'messages')

        // Also add workflow to session.workflows if workflow was generated
        if (data.success && data.workflow_ga && stepsArray.length > 0) {
          console.log('[ChatInterface] Extracting workflow to session.workflows')
          const workflowSteps = stepsArray.map((step: any, index: number) => ({
            id: `step_${index}`,
            tool: step.tool_id || step.name || 'Unknown Tool',
            name: step.name || step.tool_id || `Step ${index + 1}`,
            description: step.annotation || '',
            status: 'pending' as const,
            complexity: 'intermediate' as const,
            estimatedTime: '5 min',
            parameters: {},
            inputs: [],
            outputs: [],
          }))
          chatHistoryService.addWorkflow(chatSession.id, workflowSteps)
        }

        if (updatedSession && onChatUpdated) {
          onChatUpdated(updatedSession)
        }
      } else {
        console.log('[ChatInterface] No session, creating new one')
        // Auto-create session if it doesn't exist (e.g., in test environment)
        const newSession = chatHistoryService.createNewSession()
        chatHistoryService.addMessage(newSession.id, aiMessage)

        // Also add workflow to session.workflows if workflow was generated
        if (data.success && data.workflow_ga && stepsArray.length > 0) {
          console.log('[ChatInterface] Extracting workflow to new session.workflows')
          const workflowSteps = stepsArray.map((step: any, index: number) => ({
            id: `step_${index}`,
            tool: step.tool_id || step.name || 'Unknown Tool',
            name: step.name || step.tool_id || `Step ${index + 1}`,
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
      if (data.success && data.workflow_ga) {
        onWorkflowGenerated(data.workflow_ga, data)
      }
    },
    onError: (error) => {
      console.error('[ChatInterface] API Error:', error)
      console.error('[ChatInterface] Error details:', {
        message: error.message,
        name: error.name,
        stack: error.stack
      })
      // Fallback to demo response
      const responses = [
        "I understand you want to work on bioinformatics analysis. Let me help you build a workflow for that!",
        "Great! I can help you create a pipeline for your data analysis. Let's start building a workflow.",
        "Excellent choice! Let me design a workflow to help you process your data step by step.",
        "I'll help you set up an analysis pipeline. Let me create a workflow for you."
      ]
      
      const aiMessage: Message = {
        id: (Date.now() + 1).toString(),
        content: responses[Math.floor(Math.random() * responses.length)],
        role: "assistant",
        timestamp: new Date(),
        suggestions: ["Show me the workflow", "Explain the steps", "Start analysis", "Customize workflow"]
      }
      // Add message to chat session
      if (chatSession) {
        const updatedSession = chatHistoryService.addMessage(chatSession.id, aiMessage)
        if (updatedSession && onChatUpdated) {
          onChatUpdated(updatedSession)
        }
      }
      setIsTypingLocal(false)
      
      // Generate demo workflow when API fails
      onWorkflowGenerated(generateDemoWorkflow())
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
    
    if (msg.includes('rna-seq') || msg.includes('transcriptom')) return 'rna-seq'
    if (msg.includes('variant') || msg.includes('snp') || msg.includes('indel')) return 'variant-calling'
    if (msg.includes('genome') && msg.includes('assembl')) return 'genome-assembly'
    if (msg.includes('chip-seq') || msg.includes('chipseq')) return 'chip-seq'
    if (msg.includes('quality') || msg.includes('qc')) return 'quality-control'
    
    return 'rna-seq' // Default to RNA-seq for bioinformatics workflows
  }

  const getWorkflowTitleFromType = (type: string): string => {
    switch (type) {
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

  const handleSendMessage = (content: string) => {
    // Create user message
    const userMessage: Message = {
      id: Date.now().toString(),
      content,
      role: "user",
      timestamp: new Date()
    }

    // Add user message to chat session (create one if it doesn't exist)
    if (chatSession) {
      const updatedSession = chatHistoryService.addMessage(chatSession.id, userMessage)
      if (updatedSession && onChatUpdated) {
        onChatUpdated(updatedSession)
      }
    } else {
      // Auto-create session if it doesn't exist (e.g., in test environment)
      const newSession = chatHistoryService.createNewSession()
      chatHistoryService.addMessage(newSession.id, userMessage)
      const updatedSession = chatHistoryService.getSession(newSession.id)
      if (updatedSession && onChatUpdated) {
        onChatUpdated(updatedSession)
      }
    }

    setIsTypingLocal(true)

    // Call Galaxy API (always, regardless of session)
    chatMutation.mutate(content)

    onSendMessage(content)
  }

  const handleToolClick = (tool: any) => {
    console.log('Tool clicked:', tool)
    // Future: Navigate to tool details or add to workflow
  }

  const handleDatasetClick = (dataset: any) => {
    console.log('Dataset clicked:', dataset)
    // Future: Preview dataset or add to workflow inputs
  }

  return (
    <div className={`flex flex-col h-full ${className}`}>
      <ScrollArea className="flex-1 p-4" ref={scrollRef} data-testid="chat-messages">
        <div className="space-y-4">
          {displayMessages.map((message) => (
            <ChatMessage
              key={message.id}
              message={message}
              onToolClick={handleToolClick}
              onDatasetClick={handleDatasetClick}
            />
          ))}
          {displayTyping && <TypingIndicator />}
        </div>
      </ScrollArea>
      
      {/* Progress Section - Above Chat Input */}
      {activeWorkflow && (
        <div className="border-t bg-background">
          <div
            className="w-full p-4 cursor-pointer hover:bg-muted/50 transition-colors border-b"
            onClick={onToggleProgress}
            data-testid="button-toggle-progress"
          >
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-3">
                {showProgress ? <ChevronDown className="w-4 h-4" /> : <ChevronRight className="w-4 h-4" />}
                <div className="flex items-center gap-2">
                  {(() => {
                    const StatusIcon = getStatusIcon(activeWorkflow.status)
                    return <StatusIcon className={cn("w-4 h-4", getStatusColor(activeWorkflow.status))} />
                  })()}
                  <span className="font-medium">{activeWorkflow.title}</span>
                  <Badge variant="secondary" className="text-xs">
                    {activeWorkflow.progress}% complete
                  </Badge>
                </div>
              </div>
              <div className="flex items-center gap-2">
                <div className="text-sm text-muted-foreground">
                  Step {activeWorkflow.steps.filter(s => s.status === 'completed').length + 1} of {activeWorkflow.steps.length}
                </div>
                {activeWorkflow.status === 'running' && (
                  <Button
                    size="sm"
                    variant="outline"
                    onClick={(e) => {
                      e.stopPropagation()
                      console.log('Pause workflow')
                    }}
                  >
                    <Pause className="w-3 h-3" />
                  </Button>
                )}
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
      
      <ChatInput 
        onSend={handleSendMessage}
        disabled={displayTyping}
      />
    </div>
  )
}