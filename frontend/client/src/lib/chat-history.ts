import type { ChatSession, Message, DatasetConfig, WorkflowStepWithDatasets } from '@shared/schema';

// Chat history management service
class ChatHistoryService {
  private storageKey = 'biomate-chat-history';
  
  // Get all chat sessions
  getAllSessions(): ChatSession[] {
    try {
      const stored = localStorage.getItem(this.storageKey);
      if (!stored) return this.getDefaultSessions();
      return JSON.parse(stored);
    } catch (error) {
      console.error('Error loading chat history:', error);
      return this.getDefaultSessions();
    }
  }
  
  // Get a specific chat session by ID
  getSession(id: string): ChatSession | null {
    const sessions = this.getAllSessions();
    return sessions.find(session => session.id === id) || null;
  }
  
  // Create a new chat session
  createNewSession(): ChatSession {
    const newSession: ChatSession = {
      id: `chat-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`,
      title: "New Chat",
      timestamp: new Date(),
      lastActivity: new Date(),
      messages: [{
        id: "welcome",
        content: "Hello! I'm your BioMate AI assistant. I can help you discover bioinformatics tools, build workflows, and analyze your data. What would you like to work on today?",
        role: "assistant",
        timestamp: new Date(),
        suggestions: [
          "Analyze RNA-seq data",
          "Find variant calling tools", 
          "Build a custom workflow",
          "Explore genomics tools"
        ]
      }],
      workflows: [],
      datasets: [],
      status: "active"
    };
    
    const sessions = this.getAllSessions();
    sessions.unshift(newSession); // Add to beginning
    this.saveSessions(sessions);
    
    return newSession;
  }
  
  // Update an existing session
  updateSession(sessionId: string, updates: Partial<ChatSession>): ChatSession | null {
    const sessions = this.getAllSessions();
    const sessionIndex = sessions.findIndex(s => s.id === sessionId);
    
    if (sessionIndex === -1) return null;
    
    sessions[sessionIndex] = {
      ...sessions[sessionIndex],
      ...updates,
      lastActivity: new Date()
    };
    
    // Update title if it's still "New Chat" and we have messages
    if (sessions[sessionIndex].title === "New Chat" && sessions[sessionIndex].messages.length > 1) {
      const firstUserMessage = sessions[sessionIndex].messages.find(m => m.role === "user");
      if (firstUserMessage) {
        sessions[sessionIndex].title = this.generateTitleFromMessage(firstUserMessage.content);
      }
    }
    
    this.saveSessions(sessions);
    return sessions[sessionIndex];
  }
  
  // Add a message to a session
  addMessage(sessionId: string, message: Message): ChatSession | null {
    const session = this.getSession(sessionId);
    if (!session) return null;
    
    const updatedMessages = [...session.messages, message];
    return this.updateSession(sessionId, { messages: updatedMessages });
  }
  
  // Add workflow to a session
  addWorkflow(sessionId: string, workflow: WorkflowStepWithDatasets[]): ChatSession | null {
    return this.updateSession(sessionId, { workflows: workflow });
  }
  
  // Add datasets to a session
  addDatasets(sessionId: string, datasets: DatasetConfig[]): ChatSession | null {
    const session = this.getSession(sessionId);
    if (!session) return null;
    
    const existingDatasets = session.datasets || [];
    const updatedDatasets = [...existingDatasets, ...datasets];
    return this.updateSession(sessionId, { datasets: updatedDatasets });
  }
  
  // Delete a session
  deleteSession(sessionId: string): boolean {
    const sessions = this.getAllSessions();
    const filteredSessions = sessions.filter(s => s.id !== sessionId);
    
    if (filteredSessions.length === sessions.length) return false;
    
    this.saveSessions(filteredSessions);
    return true;
  }
  
  // Get recent sessions (up to 10)
  getRecentSessions(): ChatSession[] {
    return this.getAllSessions()
      .sort((a, b) => new Date(b.lastActivity).getTime() - new Date(a.lastActivity).getTime())
      .slice(0, 10);
  }
  
  // Private methods
  private saveSessions(sessions: ChatSession[]): void {
    try {
      localStorage.setItem(this.storageKey, JSON.stringify(sessions));
    } catch (error) {
      console.error('Error saving chat history:', error);
    }
  }
  
  private generateTitleFromMessage(content: string): string {
    // Extract a meaningful title from the first user message
    const words = content.trim().split(' ');
    const title = words.slice(0, 6).join(' ');
    return title.length > 50 ? title.substring(0, 47) + '...' : title;
  }
  
  private getDefaultSessions(): ChatSession[] {
    // Create some realistic mock chat history
    const now = new Date();
    const hoursAgo = (hours: number) => new Date(now.getTime() - hours * 60 * 60 * 1000);
    const daysAgo = (days: number) => new Date(now.getTime() - days * 24 * 60 * 60 * 1000);
    
    return [
      {
        id: "chat-1",
        title: "RNA-seq Analysis Pipeline",
        timestamp: hoursAgo(2),
        lastActivity: hoursAgo(2),
        status: "active",
        messages: [
          {
            id: "msg-1-1",
            content: "Hello! I'm your BioMate AI assistant. I can help you discover bioinformatics tools, build workflows, and analyze your data. What would you like to work on today?",
            role: "assistant",
            timestamp: hoursAgo(2.5),
            suggestions: ["Analyze RNA-seq data", "Find variant calling tools", "Build a custom workflow", "Explore genomics tools"]
          },
          {
            id: "msg-1-2",
            content: "I have RNA-seq data from a cancer study and need to perform differential expression analysis. Can you help me set up a complete pipeline?",
            role: "user",
            timestamp: hoursAgo(2.4)
          },
          {
            id: "msg-1-3",
            content: "Absolutely! I'll help you create a complete RNA-seq analysis pipeline for differential expression analysis. This will include quality control, alignment, quantification, and statistical analysis steps. Let me design a workflow for you.",
            role: "assistant",
            timestamp: hoursAgo(2.3),
            suggestions: ["Show me the workflow", "Explain each step", "Add quality control", "Customize parameters"],
            workflowId: "workflow-1"
          }
        ],
        workflows: [
          {
            id: "step1",
            title: "Quality Control",
            description: "Assess raw sequencing reads quality using FastQC",
            status: "completed",
            tool: "FastQC",
            complexity: "simple",
            estimatedTime: "5 min",
            inputs: [{
              id: "input-1",
              name: "Raw RNA-seq reads",
              type: "input",
              storageType: "local",
              localPath: "/data/raw_reads.fastq.gz",
              format: "FASTQ",
              description: "Paired-end RNA-seq reads from cancer samples",
              createdAt: hoursAgo(3)
            }],
            outputs: [{
              id: "output-1",
              name: "FastQC Quality Report",
              type: "output",
              storageType: "local",
              localPath: "/results/fastqc_report.html",
              format: "HTML",
              description: "Quality assessment report",
              createdAt: hoursAgo(2.8)
            }]
          },
          {
            id: "step2",
            title: "Read Alignment",
            description: "Align reads to reference genome using HISAT2",
            status: "completed",
            tool: "HISAT2",
            complexity: "intermediate",
            estimatedTime: "15 min"
          },
          {
            id: "step3",
            title: "Gene Expression Quantification",
            description: "Count reads mapping to genes using featureCounts",
            status: "completed",
            tool: "featureCounts",
            complexity: "complex",
            estimatedTime: "8 min"
          },
          {
            id: "step4",
            title: "Differential Expression Analysis",
            description: "Identify significant expression changes using DESeq2",
            status: "completed",
            tool: "DESeq2",
            complexity: "complex",
            estimatedTime: "12 min"
          }
        ],
        datasets: [
          {
            id: "dataset-1",
            name: "Cancer RNA-seq Dataset",
            type: "input",
            storageType: "s3",
            s3Config: {
              bucketName: "biomate-data",
              accessKeyId: "****",
              secretAccessKey: "****",
              region: "us-east-1",
              prefix: "rna-seq/cancer-study/"
            },
            format: "FASTQ",
            size: 15728640000, // 15GB
            description: "Paired-end RNA-seq data from 24 cancer samples and 12 normal controls",
            createdAt: hoursAgo(3)
          }
        ]
      },
      {
        id: "chat-2",
        title: "Variant Calling Workflow",
        timestamp: daysAgo(1),
        lastActivity: daysAgo(1),
        status: "active",
        messages: [
          {
            id: "msg-2-1",
            content: "Hello! I'm your BioMate AI assistant. I can help you discover bioinformatics tools, build workflows, and analyze your data. What would you like to work on today?",
            role: "assistant",
            timestamp: daysAgo(1.1),
            suggestions: ["Analyze RNA-seq data", "Find variant calling tools", "Build a custom workflow", "Explore genomics tools"]
          },
          {
            id: "msg-2-2",
            content: "I need to identify SNPs and indels from whole genome sequencing data. What's the best approach?",
            role: "user",
            timestamp: daysAgo(1.05)
          },
          {
            id: "msg-2-3",
            content: "For variant calling from WGS data, I recommend a GATK-based pipeline. This includes alignment with BWA-MEM, preprocessing steps, and variant calling with HaplotypeCaller. Let me create a comprehensive workflow for you.",
            role: "assistant",
            timestamp: daysAgo(1),
            suggestions: ["Show workflow details", "Explain GATK pipeline", "Add quality filters", "Include annotation"],
            workflowId: "workflow-2"
          }
        ],
        workflows: [
          {
            id: "variant-step1",
            title: "Quality Control",
            description: "Check raw sequencing data quality",
            status: "completed",
            tool: "FastQC",
            complexity: "simple",
            estimatedTime: "5 min"
          },
          {
            id: "variant-step2",
            title: "Read Alignment",
            description: "Align reads to reference genome",
            status: "completed",
            tool: "BWA-MEM",
            complexity: "intermediate",
            estimatedTime: "20 min"
          },
          {
            id: "variant-step3",
            title: "Variant Calling",
            description: "Call SNPs and indels using GATK",
            status: "completed",
            tool: "GATK",
            complexity: "complex",
            estimatedTime: "45 min"
          }
        ],
        datasets: [
          {
            id: "dataset-2",
            name: "WGS Trio Dataset",
            type: "input",
            storageType: "replit_storage",
            replitStoragePath: "/storage/wgs-trio/",
            format: "FASTQ",
            size: 85899345920, // 80GB
            description: "Whole genome sequencing data from father-mother-child trio",
            createdAt: daysAgo(1.2)
          }
        ]
      },
      {
        id: "chat-3",
        title: "ChIP-seq Data Processing",
        timestamp: daysAgo(3),
        lastActivity: daysAgo(3),
        status: "active",
        messages: [
          {
            id: "msg-3-1",
            content: "Hello! I'm your BioMate AI assistant. I can help you discover bioinformatics tools, build workflows, and analyze your data. What would you like to work on today?",
            role: "assistant",
            timestamp: daysAgo(3.1),
            suggestions: ["Analyze RNA-seq data", "Find variant calling tools", "Build a custom workflow", "Explore genomics tools"]
          },
          {
            id: "msg-3-2",
            content: "I have ChIP-seq data for histone modifications and need to identify enriched regions. How should I proceed?",
            role: "user",
            timestamp: daysAgo(3.05)
          },
          {
            id: "msg-3-3",
            content: "For ChIP-seq analysis, you'll need peak calling and enrichment analysis. I recommend using MACS2 for peak calling and deepTools for visualization. Let me set up a workflow for you.",
            role: "assistant",
            timestamp: daysAgo(3),
            suggestions: ["Create ChIP-seq workflow", "Explain peak calling", "Add visualization", "Compare conditions"]
          }
        ],
        workflows: [],
        datasets: []
      },
      {
        id: "chat-4",
        title: "Genome Assembly Help",
        timestamp: daysAgo(7),
        lastActivity: daysAgo(7),
        status: "active",
        messages: [
          {
            id: "msg-4-1",
            content: "Hello! I'm your BioMate AI assistant. I can help you discover bioinformatics tools, build workflows, and analyze your data. What would you like to work on today?",
            role: "assistant",
            timestamp: daysAgo(7.1),
            suggestions: ["Analyze RNA-seq data", "Find variant calling tools", "Build a custom workflow", "Explore genomics tools"]
          },
          {
            id: "msg-4-2",
            content: "I'm working on de novo genome assembly and need advice on choosing the right assembler for my long-read data.",
            role: "user",
            timestamp: daysAgo(7.05)
          },
          {
            id: "msg-4-3",
            content: "For long-read de novo assembly, I recommend considering Flye, Canu, or wtdbg2 depending on your data type and genome size. Let me help you choose the best approach based on your specific requirements.",
            role: "assistant",
            timestamp: daysAgo(7),
            suggestions: ["Compare assemblers", "Check data requirements", "Estimate resources", "Plan workflow"]
          }
        ],
        workflows: [],
        datasets: []
      }
    ];
  }
}

// Export singleton instance
export const chatHistoryService = new ChatHistoryService();