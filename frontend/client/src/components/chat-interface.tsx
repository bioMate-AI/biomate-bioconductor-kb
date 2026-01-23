import { useState, useEffect, useRef } from "react"
import { ChatMessage, type Message } from "./chat-message"
import { ChatInput } from "./chat-input"
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
  // Workflow execution props for inline artifacts
  onRunWorkflow?: (workflow: any, steps: any[]) => void
  onStopWorkflow?: () => void
  onParameterChange?: (stepId: string, params: Record<string, any>) => void
  isWorkflowRunning?: boolean
  workflowProgress?: number
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
  onToggleProgress,
  onRunWorkflow,
  onStopWorkflow,
  onParameterChange,
  isWorkflowRunning = false,
  workflowProgress = 0
}: ChatInterfaceProps) {
  const [isTypingLocal, setIsTypingLocal] = useState(false)
  const scrollRef = useRef<HTMLDivElement>(null)
  const messagesEndRef = useRef<HTMLDivElement>(null)

  // Compression state
  const [showCompressionDialog, setShowCompressionDialog] = useState(false)
  const [isCompressing, setIsCompressing] = useState(false)
  const [currentTokenCount, setCurrentTokenCount] = useState(0)
  const [compressionDismissed, setCompressionDismissed] = useState(false)
  
  // Use messages from chat session or empty array if no session
  const displayMessages = chatSession?.messages || []
  const displayTyping = isTyping || isTypingLocal

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

  // Galaxy Chat API integration with full hybrid intelligence
  // Uses /api/chat which provides: intent analysis, tool search, dataset RAG, workflow generation
  const chatMutation = useMutation({
    mutationFn: async (content: string) => {
      const response = await fetch('/api/chat', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          message: content,
          context: {
            previousMessages: displayMessages.slice(-10).map(m => ({
              role: m.role,
              content: m.content
            })),
            // Include session ID for memory integration
            ...(chatSession?.id && { memorySessionId: chatSession.id }),
          }
        })
      })
      if (!response.ok) {
        throw new Error(`Chat API error: ${response.statusText}`)
      }
      return await response.json()
    },
    onSuccess: (data) => {
      console.log('[ChatInterface] API Response:', data)

      // Handle /api/chat response format (full hybrid intelligence)
      // Response structure: { response, suggestions, workflow, thinking_content, metadata }
      let workflowData = data.workflow?.workflow_ga || data.workflow;
      let workflowSuccess = !!data.workflow?.success || (data.workflow && !data.workflow.error);
      let isDemo = false;

      // Check if workflow was generated
      if (data.workflow) {
        if (!workflowSuccess) {
          console.warn('[ChatInterface] Workflow generation returned but failed:', data.workflow.error || data.workflow.message);
          // Show demo workflow clearly labeled
          workflowData = generateDemoWorkflow();
          isDemo = true;
        }
      }

      // Use the natural language response from /api/chat
      // This includes tool recommendations, dataset suggestions, etc.
      let workflowInfo: string = data.response || '';

      // If workflow was generated, append workflow-specific info
      if (workflowSuccess && workflowData) {
        // Response already contains helpful context from Claude
        if (!workflowInfo.toLowerCase().includes('workflow')) {
          workflowInfo += '\n\n✅ I\'ve generated a workflow for you based on your request.';
        }
      } else if (isDemo) {
        workflowInfo = data.response + `\n\n⚠️ **Note:** Could not generate a real workflow. Showing a demo workflow for reference.`;
        workflowData = { ...workflowData, _isDemo: true, annotation: '[DEMO] ' + (workflowData?.annotation || 'Sample workflow for preview') };
      } else if (!workflowInfo) {
        workflowInfo = 'I can help you with bioinformatics analysis!';
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
        id: (Date.now() + 1).toString(),
        content: workflowInfo,
        role: "assistant",
        timestamp: new Date(),
        // Include invocationId from API response to trigger output viewers
        invocationId: data.invocationId,
        // Use suggestions from /api/chat or fallbacks
        suggestions: data.suggestions || (workflowSuccess
          ? ["Open in Workflow Builder", "Show details", "Generate another"]
          : isDemo
          ? ["Try again with different request", "Check server status", "View demo anyway"]
          : ["Tell me more", "Suggest tools", "Build workflow"]),
        metadata: {
          type: workflowSuccess ? 'workflow' : isDemo ? 'demo_workflow' : 'text',
          workflow: workflowData,
          steps: stepsArray,
          confidence: data.workflow?.confidence || data.metadata?.workflowSuggestion?.confidence,
          source: data.workflow?.source || (isDemo ? 'demo_fallback' : 'chat'),
          isDemo: isDemo,
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
      if (chatSession) {
        console.log('[ChatInterface] Adding message to existing session:', chatSession.id)
        const updatedSession = chatHistoryService.addMessage(chatSession.id, aiMessage)
        console.log('[ChatInterface] Updated session:', updatedSession?.messages.length, 'messages')

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
        onWorkflowGenerated(workflowData)
      }
    },
    onError: (error) => {
      console.error('[ChatInterface] API Error:', error)
      console.error('[ChatInterface] Error details:', {
        message: error.message,
        name: error.name,
        stack: error.stack
      })

      // Show CLEAR error message to user - no hiding the problem
      const errorMessage = error.message || 'Unknown error occurred';
      const isNetworkError = errorMessage.includes('fetch') || errorMessage.includes('network') || errorMessage.includes('Failed to fetch');

      let userFriendlyError: string;
      if (isNetworkError) {
        userFriendlyError = `⚠️ **Connection Error**\n\nCould not reach the workflow generation service. This might be because:\n\n• The server is temporarily unavailable\n• Your network connection is interrupted\n• The service is being updated\n\n**What you can do:**\n1. Check your internet connection\n2. Try again in a few moments\n3. Contact support if the issue persists`;
      } else {
        userFriendlyError = `❌ **Workflow Generation Failed**\n\n${errorMessage}\n\n**What you can do:**\n1. Try rephrasing your request\n2. Be more specific about your data type and analysis goal\n3. Try again in a few moments`;
      }

      // Show demo workflow but CLEARLY LABEL IT
      const demoWorkflow = generateDemoWorkflow();
      const demoNote = `\n\n---\n📋 **Demo Preview:** Below is a sample workflow to show you what a typical analysis might look like. This is for reference only and won't execute real analysis.`;

      const aiMessage: Message = {
        id: (Date.now() + 1).toString(),
        content: userFriendlyError + demoNote,
        role: "assistant",
        timestamp: new Date(),
        suggestions: ["Try again", "Refine my request", "Check server status", "Get help"],
        metadata: {
          type: 'error',
          errorType: isNetworkError ? 'network' : 'api',
          errorMessage: errorMessage,
          // Include demo workflow but mark it clearly
          workflow: { ...demoWorkflow, _isDemo: true, _isError: true },
        }
      }

      // Add error message to chat session
      if (chatSession) {
        const updatedSession = chatHistoryService.addMessage(chatSession.id, aiMessage)
        if (updatedSession && onChatUpdated) {
          onChatUpdated(updatedSession)
        }
      }
      setIsTypingLocal(false)

      // Pass demo workflow but marked as demo/error
      onWorkflowGenerated({ ...demoWorkflow, _isDemo: true, _isError: true })
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

  const handleSendMessage = (content: string, files?: File[]) => {
    // Handle attached files if present
    if (files && files.length > 0) {
      console.log('[ChatInterface] Files attached:', files.map(f => f.name))
      // TODO: Upload files to Galaxy and include dataset IDs in the message
      // For now, mention files in the message content
      const fileNames = files.map(f => f.name).join(', ')
      content = content + (content ? '\n\n' : '') + `[Attached files: ${fileNames}]`
    }

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

  return (
    <div className={`flex flex-col h-full ${className}`}>
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
        <div className="space-y-4">
          {displayMessages.map((message) => (
            <ChatMessage
              key={message.id}
              message={message}
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
              onParameterChange={onParameterChange}
              isWorkflowRunning={isWorkflowRunning}
              workflowProgress={workflowProgress}
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

      <ChatInput
        onSend={handleSendMessage}
        disabled={displayTyping}
      />

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