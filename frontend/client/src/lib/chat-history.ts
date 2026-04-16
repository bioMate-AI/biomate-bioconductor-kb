import type { ChatSession, Message, DatasetConfig, WorkflowStepWithDatasets } from '@shared/schema';

// Backend sync configuration
const BACKEND_SYNC_ENABLED = import.meta.env.VITE_ENABLE_BACKEND_SYNC !== 'false';
// Default to same-origin API to avoid browser CORS/CSP issues in dev/test.
const BACKEND_URL = (import.meta.env.VITE_BACKEND_URL || '').replace(/\/$/, '');
const API_KEY = import.meta.env.VITE_GALAXY_API_KEY || 'a7e9f73a7c25300e222d27c84efb10f6';

// Sync status type
type SyncStatus = 'idle' | 'syncing' | 'synced' | 'error';

// Chat history management service with backend persistence
class ChatHistoryService {
  private storageKey = 'biomate-chat-history';
  private syncQueue: Set<string> = new Set();
  private syncTimer: NodeJS.Timeout | null = null;
  private syncStatus: SyncStatus = 'idle';
  private lastSyncError: string | null = null;
  private backendSyncActive = false;
  private backendSyncBlocked = false;
  private loggedAuthBlock = false;

  // Get all chat sessions (from localStorage cache)
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

    // Sync to backend
    this.pushToBackend(newSession.id).catch(err => {
      console.error('[ChatHistory] Failed to sync new session:', err);
    });

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

    // Sync to backend
    this.pushToBackend(sessionId).catch(err => {
      console.error('[ChatHistory] Failed to sync updated session:', err);
    });

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
  async deleteSession(sessionId: string): Promise<boolean> {
    const sessions = this.getAllSessions();
    const filteredSessions = sessions.filter(s => s.id !== sessionId);

    if (filteredSessions.length === sessions.length) return false;

    this.saveSessions(filteredSessions);

    // Delete from backend
    if (BACKEND_SYNC_ENABLED && this.backendSyncActive) {
      try {
        const response = await fetch(`${BACKEND_URL}/api/sessions/${sessionId}`, {
          method: 'DELETE',
          credentials: 'include',
          headers: {
            'x-api-key': API_KEY,
            'Content-Type': 'application/json'
          }
        });

        if (!response.ok) {
          console.error('[ChatHistory] Failed to delete session from backend:', response.status);
        }
      } catch (error) {
        console.error('[ChatHistory] Failed to delete session from backend:', error);
      }
    }

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
  
  // ============================================================================
  // BACKEND SYNC METHODS
  // ============================================================================

  /**
   * Get sync status
   */
  getSyncStatus(): { status: SyncStatus; lastError: string | null } {
    return {
      status: this.syncStatus,
      lastError: this.lastSyncError
    };
  }

  /**
   * Enable/disable backend sync based on auth state.
   */
  setBackendSyncActive(active: boolean): void {
    this.backendSyncActive = active;

    if (!active) {
      if (this.syncTimer) {
        clearTimeout(this.syncTimer);
        this.syncTimer = null;
      }
      this.syncQueue.clear();
      this.syncStatus = 'idle';
      this.lastSyncError = null;
      return;
    }

    // Re-enable sync after login and attempt initial pull.
    this.backendSyncBlocked = false;
    this.loggedAuthBlock = false;
    this.initializeBackendSync().catch((error) => {
      console.error('[ChatHistory] Failed to initialize backend sync:', error);
    });
  }

  /**
   * Initialize and sync with backend on startup
   */
  async initializeBackendSync(): Promise<void> {
    if (!BACKEND_SYNC_ENABLED || !this.backendSyncActive) {
      console.log('[ChatHistory] Backend sync disabled');
      return;
    }

    try {
      console.log('[ChatHistory] Initializing backend sync...');
      await this.pullFromBackend();
      console.log('[ChatHistory] Backend sync initialized');
    } catch (error) {
      console.error('[ChatHistory] Failed to initialize backend sync:', error);
      this.syncStatus = 'error';
      this.lastSyncError = error instanceof Error ? error.message : 'Unknown error';
    }
  }

  /**
   * Pull sessions from backend and merge with localStorage
   */
  async pullFromBackend(): Promise<void> {
    if (!BACKEND_SYNC_ENABLED || !this.backendSyncActive || this.backendSyncBlocked) return;

    try {
      this.syncStatus = 'syncing';
      const response = await fetch(`${BACKEND_URL}/api/sessions`, {
        credentials: 'include',
        headers: {
          'x-api-key': API_KEY,
          'Content-Type': 'application/json'
        }
      });

      if (response.status === 401 || response.status === 403) {
        this.backendSyncBlocked = true;
      }
      if (!response.ok) {
        throw new Error(`Backend returned ${response.status}`);
      }

      const backendSessions = await response.json();

      // Convert backend format to frontend format
      const convertedSessions: ChatSession[] = backendSessions.map((bs: any) => ({
        id: bs.session_id,
        title: bs.title,
        timestamp: new Date(bs.created_at),
        lastActivity: new Date(bs.last_activity),
        status: bs.status as 'active' | 'archived',
        messages: [],
        workflows: [],
        datasets: []
      }));

      // Merge with local sessions (backend is source of truth)
      const localSessions = this.getAllSessions();
      const mergedSessions = this.mergeSessions(localSessions, convertedSessions);

      this.saveSessions(mergedSessions);
      this.syncStatus = 'synced';
      this.lastSyncError = null;
    } catch (error) {
      console.error('[ChatHistory] Pull from backend failed:', error);
      this.syncStatus = 'error';
      this.lastSyncError = error instanceof Error ? error.message : 'Unknown error';
    }
  }

  /**
   * Push a session to backend (debounced)
   */
  async pushToBackend(sessionId: string): Promise<void> {
    if (!BACKEND_SYNC_ENABLED || !this.backendSyncActive || this.backendSyncBlocked) return;

    // Add to sync queue
    this.syncQueue.add(sessionId);

    // Debounce: only sync after 2 seconds of inactivity
    if (this.syncTimer) {
      clearTimeout(this.syncTimer);
    }

    this.syncTimer = setTimeout(async () => {
      await this.flushSyncQueue();
    }, 2000);
  }

  /**
   * Flush the sync queue (sync all pending sessions)
   */
  private async flushSyncQueue(): Promise<void> {
    if (this.syncQueue.size === 0 || this.backendSyncBlocked) return;

    const sessionIds = Array.from(this.syncQueue);
    this.syncQueue.clear();

    for (const sessionId of sessionIds) {
      try {
        await this.syncSessionToBackend(sessionId);
      } catch (error) {
        // Auth failures are expected for anonymous sessions; disable noisy retries.
        if (this.backendSyncBlocked) {
          if (!this.loggedAuthBlock) {
            console.warn('[ChatHistory] Backend sync disabled: authentication required');
            this.loggedAuthBlock = true;
          }
          this.syncQueue.clear();
          return;
        }
        console.error(`[ChatHistory] Failed to sync session ${sessionId}:`, error);
        this.syncQueue.add(sessionId);
      }
    }
  }

  /**
   * Sync a single session to backend
   */
  private async syncSessionToBackend(sessionId: string): Promise<void> {
    if (!this.backendSyncActive || this.backendSyncBlocked) return;
    const session = this.getSession(sessionId);
    if (!session) return;

    this.syncStatus = 'syncing';

    try {
      // Check if session exists on backend
      const checkResponse = await fetch(`${BACKEND_URL}/api/sessions/${sessionId}`, {
        credentials: 'include',
        headers: {
          'x-api-key': API_KEY,
          'Content-Type': 'application/json'
        }
      });

      if (checkResponse.status === 401 || checkResponse.status === 403) {
        this.backendSyncBlocked = true;
        throw new Error(`Backend returned ${checkResponse.status}`);
      }

      const method = checkResponse.ok ? 'PUT' : 'POST';
      const url = checkResponse.ok
        ? `${BACKEND_URL}/api/sessions/${sessionId}`
        : `${BACKEND_URL}/api/sessions`;

      // Convert frontend format to backend format
      const backendPayload = this.convertToBackendFormat(session);

      const response = await fetch(url, {
        method,
        credentials: 'include',
        headers: {
          'x-api-key': API_KEY,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify(backendPayload)
      });

      if (response.status === 401 || response.status === 403) {
        this.backendSyncBlocked = true;
      }
      if (!response.ok) {
        throw new Error(`Backend returned ${response.status}`);
      }

      this.syncStatus = 'synced';
      this.lastSyncError = null;
      console.log(`[ChatHistory] Successfully synced session ${sessionId}`);
    } catch (error) {
      if (this.backendSyncBlocked) {
        this.syncStatus = 'error';
        this.lastSyncError = error instanceof Error ? error.message : 'Authentication required';
        throw error;
      }
      console.error(`[ChatHistory] Failed to sync session ${sessionId}:`, error);
      this.syncStatus = 'error';
      this.lastSyncError = error instanceof Error ? error.message : 'Unknown error';
      throw error;
    }
  }

  /**
   * Convert frontend ChatSession format to backend API format
   */
  private convertToBackendFormat(session: ChatSession): any {
    const asIsoString = (value: unknown): string => {
      if (value instanceof Date) return value.toISOString();
      if (typeof value === 'string' || typeof value === 'number') {
        const parsed = new Date(value);
        if (!Number.isNaN(parsed.getTime())) return parsed.toISOString();
      }
      return new Date().toISOString();
    };

    return {
      session_id: session.id,
      title: session.title,
      session_type: 'chat',
      status: session.status,
      message_count: session.messages.length,
      token_count: this.estimateTokenCount(session.messages),
      messages: session.messages.map(msg => ({
        message_id: msg.id,
        role: msg.role,
        content: msg.content,
        timestamp: asIsoString(msg.timestamp),
        token_count: this.estimateTokenCount([msg]),
        suggestions: msg.suggestions || null,
        workflow_id: msg.workflowId || null,
        thinking_content: msg.thinking_content || null,
        thinking_level: msg.thinking_level || null,
        error_code: null,
        error_message: null
      })),
      workflows: (session.workflows || []).map(wf => ({
        workflow_id: wf.id,
        workflow_name: wf.title,
        workflow_description: wf.description,
        invocation_id: null,
        status: wf.status,
        success: wf.status === 'completed' ? 1 : wf.status === 'error' ? 0 : null,
        error_message: null
      })),
      datasets: (session.datasets || []).map(ds => ({
        dataset_id: ds.id,
        dataset_name: ds.name,
        dataset_type: ds.type,
        storage_type: ds.storageType,
        storage_path: ds.localPath || ds.replitStoragePath || null,
        format: ds.format || null,
        size_bytes: ds.size || null,
        description: ds.description || null
      }))
    };
  }

  /**
   * Estimate token count for messages (rough approximation: 1 token ≈ 4 chars)
   * TODO: Use proper token counter from server/token-counter.ts for better accuracy
   */
  private estimateTokenCount(messages: Message[]): number {
    let totalTokens = 0;

    for (const msg of messages) {
      const contentChars = msg.content.length;

      // Heuristic token counting
      let tokensPerChar = 0.25; // Default: 1 token per 4 chars

      // If content looks like code (has lots of special chars)
      const specialChars = (msg.content.match(/[{}[\]();,<>=]/g) || []).length;
      if (specialChars / contentChars > 0.1) {
        tokensPerChar = 0.29; // Code: ~1 token per 3.5 chars
      }

      // Add tokens for message structure (~4 tokens per message)
      totalTokens += Math.ceil(contentChars * tokensPerChar) + 4;
    }

    return totalTokens;
  }

  /**
   * Merge local and backend sessions (backend takes precedence for conflicts)
   */
  private mergeSessions(local: ChatSession[], backend: ChatSession[]): ChatSession[] {
    const merged = new Map<string, ChatSession>();

    // Add all local sessions
    local.forEach(session => {
      merged.set(session.id, session);
    });

    // Override with backend sessions (backend is source of truth)
    backend.forEach(session => {
      merged.set(session.id, session);
    });

    return Array.from(merged.values())
      .sort((a, b) => new Date(b.lastActivity).getTime() - new Date(a.lastActivity).getTime());
  }

  // ============================================================================
  // PRIVATE HELPER METHODS
  // ============================================================================

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