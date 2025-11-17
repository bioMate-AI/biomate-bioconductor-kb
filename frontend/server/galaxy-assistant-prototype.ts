/**
 * PROTOTYPE: Galaxy Assistant with Iterative Workflow Integration
 *
 * This is a minimal prototype to validate the hybrid mode approach:
 * - Legacy Mode: Direct workflow generation (existing behavior)
 * - Iterative Mode: Step-by-step with clarification (new behavior)
 *
 * Purpose: Test integration strategy before modifying production code
 */

import Anthropic from '@anthropic-ai/sdk';
import { GalaxyAPIProxy } from './galaxy-api-proxy';
import { IterativeWorkflowGenerator, WorkflowPhase } from './iterative-workflow-generator';
import type { GalaxyAssistantResponse, ChatContext, ToolRecommendation, DatasetRecommendation, WorkflowSuggestion } from './galaxy-assistant';

// ============================================================================
// EXTENDED TYPES FOR PROTOTYPE
// ============================================================================

interface PrototypeChatContext extends ChatContext {
  // Iterative workflow extensions
  sessionId?: string;
  workflowMode?: 'legacy' | 'iterative';
  workflowPhase?: WorkflowPhase;
}

interface PrototypeResponse extends GalaxyAssistantResponse {
  // Iterative workflow fields
  workflowPhase?: WorkflowPhase;
  clarificationQuestions?: any[];
  currentWorkflowStep?: any;
  draftWorkflow?: any;
  validationResults?: any[];

  // Debug info
  debug?: {
    modeUsed: 'legacy' | 'iterative';
    modeReason: string;
    sessionId?: string;
    phase?: WorkflowPhase;
  };
}

// ============================================================================
// PROTOTYPE GALAXY ASSISTANT
// ============================================================================

export class GalaxyAssistantPrototype {
  private claude: Anthropic;
  private galaxyAPI: GalaxyAPIProxy;
  private workflowGenerator: IterativeWorkflowGenerator;

  // Session storage (in-memory for prototype)
  private sessions: Map<string, any> = new Map();

  constructor(anthropicApiKey: string, galaxyAPI: GalaxyAPIProxy) {
    this.claude = new Anthropic({ apiKey: anthropicApiKey });
    this.galaxyAPI = galaxyAPI;
    this.workflowGenerator = new IterativeWorkflowGenerator(anthropicApiKey);
  }

  /**
   * PROTOTYPE: Simplified processMessage with hybrid mode
   */
  async processMessage(
    message: string,
    context: PrototypeChatContext = {}
  ): Promise<PrototypeResponse> {

    console.log('\n========================================');
    console.log('🧪 PROTOTYPE: Processing message');
    console.log('Message:', message);
    console.log('Context:', context);
    console.log('========================================\n');

    // Step 1: Quick intent analysis (simplified)
    const intent = this.quickIntentAnalysis(message);
    console.log('[Prototype] Intent:', intent);

    // Step 2: Determine workflow mode
    const { mode, reason } = this.determineWorkflowMode(message, intent, context);
    console.log(`[Prototype] Mode Decision: ${mode.toUpperCase()}`);
    console.log(`[Prototype] Reason: ${reason}`);

    // Step 3: Route to appropriate handler
    let response: PrototypeResponse;

    if (mode === 'iterative') {
      response = await this.handleIterativeMode(message, intent, context);
    } else {
      response = await this.handleLegacyMode(message, intent, context);
    }

    // Add debug info
    response.debug = {
      modeUsed: mode,
      modeReason: reason,
      sessionId: context.sessionId,
      phase: response.workflowPhase
    };

    console.log('\n[Prototype] Response:', {
      mode: response.debug.modeUsed,
      phase: response.workflowPhase,
      hasQuestions: !!response.clarificationQuestions,
      hasWorkflow: !!response.generatedWorkflow
    });

    return response;
  }

  /**
   * Quick intent analysis (simplified version)
   */
  private quickIntentAnalysis(message: string): any {
    const lower = message.toLowerCase();

    return {
      type: lower.includes('workflow') || lower.includes('pipeline') || lower.includes('build')
        ? 'workflow_generation'
        : 'general_question',

      keywords: this.extractKeywords(message),

      needsToolSearch: /tool|software|package|program/i.test(message),
      needsDatasets: /data|dataset|sample|file/i.test(message),

      confidence: lower.includes('workflow') ? 0.9 : 0.5,

      // Complexity indicators
      isComplex: /help|not sure|multiple|several|different options/i.test(message),
      isSimple: /quick|simple|basic|just.*workflow/i.test(message)
    };
  }

  /**
   * Extract keywords from message (simplified)
   */
  private extractKeywords(message: string): string[] {
    const keywords: string[] = [];

    // Common bioinformatics terms
    const terms = [
      'rna-seq', 'proteomics', 'genomics', 'metabolomics',
      'differential expression', 'variant calling', 'alignment',
      'quality control', 'trimming', 'assembly'
    ];

    terms.forEach(term => {
      if (message.toLowerCase().includes(term)) {
        keywords.push(term);
      }
    });

    return keywords;
  }

  /**
   * CORE LOGIC: Determine which mode to use
   */
  private determineWorkflowMode(
    message: string,
    intent: any,
    context: PrototypeChatContext
  ): { mode: 'legacy' | 'iterative'; reason: string } {

    // Rule 1: If already in iterative session, continue in iterative mode
    if (context.workflowMode === 'iterative' && context.sessionId) {
      return {
        mode: 'iterative',
        reason: 'Continuing existing iterative session'
      };
    }

    // Rule 2: Complex query → iterative mode
    if (intent.isComplex) {
      return {
        mode: 'iterative',
        reason: 'Query contains complexity indicators (help, not sure, multiple)'
      };
    }

    // Rule 3: Low confidence → iterative mode
    if (intent.confidence < 0.9 && intent.type === 'workflow_generation') {
      return {
        mode: 'iterative',
        reason: `Low confidence (${intent.confidence}) - need clarification`
      };
    }

    // Rule 4: Explicit guidance request → iterative mode
    const needsGuidance = /help.*build|walk.*through|guide|step.*by.*step/i.test(message);
    if (needsGuidance) {
      return {
        mode: 'iterative',
        reason: 'User explicitly requested guidance'
      };
    }

    // Rule 5: Simple + high confidence → legacy mode
    if (intent.isSimple && intent.confidence >= 0.9) {
      return {
        mode: 'legacy',
        reason: 'Simple query with high confidence - direct generation is fine'
      };
    }

    // Rule 6: Default to iterative for workflow generation
    if (intent.type === 'workflow_generation') {
      return {
        mode: 'iterative',
        reason: 'Default: Workflow generation benefits from clarification'
      };
    }

    // Rule 7: Non-workflow questions → legacy
    return {
      mode: 'legacy',
      reason: 'Not a workflow generation request'
    };
  }

  /**
   * Handle ITERATIVE mode
   */
  private async handleIterativeMode(
    message: string,
    intent: any,
    context: PrototypeChatContext
  ): Promise<PrototypeResponse> {

    console.log('\n🔄 ITERATIVE MODE ACTIVATED');

    // Get or create session
    const sessionId = context.sessionId || `session-${Date.now()}`;

    // Call iterative workflow generator
    const iterativeResult = await this.workflowGenerator.processMessage(
      sessionId,
      message,
      {
        sessionId,
        conversationHistory: context.previousMessages || [],
        userAnswers: {},
        inferredContext: {
          keywords: intent.keywords,
          analysisType: intent.keywords[0] || 'bioinformatics'
        },
        openQuestions: [],
        currentPhase: context.workflowPhase || WorkflowPhase.CLARIFICATION
      }
    );

    console.log('[Iterative] Result:', {
      phase: iterativeResult.phase,
      hasQuestions: !!iterativeResult.questions,
      hasWorkflow: !!iterativeResult.workflow,
      hasSuggestions: !!iterativeResult.suggestions
    });

    // Determine if workflow is ready
    const workflowGenerated = iterativeResult.phase === WorkflowPhase.READY && !!iterativeResult.workflow;

    // Store session
    this.sessions.set(sessionId, {
      ...context,
      sessionId,
      workflowMode: 'iterative',
      workflowPhase: iterativeResult.phase,
      lastActivity: new Date()
    });

    return {
      message: iterativeResult.message,
      suggestions: iterativeResult.suggestions || [],

      // Workflow data
      generatedWorkflow: workflowGenerated ? iterativeResult.workflow : undefined,

      // Iterative-specific fields
      workflowPhase: iterativeResult.phase,
      clarificationQuestions: iterativeResult.questions,
      currentWorkflowStep: iterativeResult.currentStep,
      draftWorkflow: iterativeResult.workflow,
      validationResults: iterativeResult.validationResults,

      sources: {
        toolSearchUsed: false,
        datasetRAGUsed: false,
        workflowGenerated,
        thinkingUsed: false,
      }
    };
  }

  /**
   * Handle LEGACY mode (existing behavior)
   */
  private async handleLegacyMode(
    message: string,
    intent: any,
    context: PrototypeChatContext
  ): Promise<PrototypeResponse> {

    console.log('\n⚡ LEGACY MODE ACTIVATED');

    // Simulate legacy workflow generation
    const shouldGenerate = intent.type === 'workflow_generation' && intent.confidence > 0.7;

    let generatedWorkflow = null;
    if (shouldGenerate) {
      // For prototype: create mock workflow
      generatedWorkflow = {
        workflow_id: `workflow-${Date.now()}`,
        name: `${intent.keywords[0] || 'Analysis'} Workflow`,
        description: 'Auto-generated workflow',
        steps: [
          {
            step_id: 'step-1',
            name: 'Quality Control',
            tool_id: 'fastqc',
            position: 0
          },
          {
            step_id: 'step-2',
            name: 'Analysis',
            tool_id: intent.keywords[0] || 'analysis-tool',
            position: 1
          }
        ],
        source: 'legacy_generator',
        confidence: intent.confidence
      };

      console.log('[Legacy] Generated workflow:', generatedWorkflow.name);
    }

    return {
      message: shouldGenerate
        ? `I've generated a ${intent.keywords[0] || 'bioinformatics'} workflow for you. It includes quality control and analysis steps.`
        : `I can help you with ${intent.keywords.join(', ') || 'bioinformatics analysis'}. Would you like me to build a workflow?`,

      suggestions: shouldGenerate
        ? ['Customize parameters', 'Execute workflow', 'Explain steps']
        : ['Build workflow', 'Show available tools', 'Learn more'],

      generatedWorkflow,

      sources: {
        toolSearchUsed: false,
        datasetRAGUsed: false,
        workflowGenerated: !!generatedWorkflow,
        thinkingUsed: false,
      }
    };
  }

  /**
   * Get session info (for debugging)
   */
  getSession(sessionId: string): any {
    return this.sessions.get(sessionId);
  }

  /**
   * List all sessions (for debugging)
   */
  listSessions(): string[] {
    return Array.from(this.sessions.keys());
  }
}