/**
 * Iterative Workflow Generator
 *
 * Builds bioinformatics workflows step-by-step with user clarification,
 * inspired by Claude Code's approach to task orchestration.
 *
 * Workflow Phases:
 * 1. CLARIFICATION - Ask questions to understand requirements
 * 2. DRAFT - Generate high-level workflow structure (4-6 steps)
 * 3. STEP_BY_STEP - Configure each step with detailed parameters
 * 4. VALIDATION - Pre-execution validation checks
 * 5. READY - Ready for execution
 */

import Anthropic from '@anthropic-ai/sdk';

// ============================================================================
// TYPES & ENUMS
// ============================================================================

export enum WorkflowPhase {
  CLARIFICATION = 'clarification',
  DRAFT = 'draft',
  STEP_BY_STEP = 'step_by_step',
  VALIDATION = 'validation',
  READY = 'ready'
}

export interface ClarificationQuestion {
  id: string;
  question: string;
  category: 'data_type' | 'organism' | 'analysis_goal' | 'technical' | 'other';
  required: boolean;
  options?: string[];
  canInfer: boolean;
  inferredValue?: any;
}

export interface WorkflowStep {
  stepId: string;
  name: string;
  purpose: string;
  suggestedTool: string;
  toolId?: string;
  inputRequirements?: string[];
  parameters?: Record<string, any>;
  expectedOutput?: string;
  warnings?: string[];
  configured: boolean;
}

export interface DraftWorkflow {
  workflowId: string;
  title: string;
  description: string;
  analysisType: string;
  steps: WorkflowStep[];
  estimatedDuration?: string;
  complexity: 'simple' | 'moderate' | 'complex';
}

export interface SessionContext {
  sessionId: string;
  conversationHistory: Array<{ role: string; content: string }>;
  userAnswers: Record<string, any>;
  inferredContext: Record<string, any>;
  openQuestions: ClarificationQuestion[];
  currentPhase: WorkflowPhase;
  currentStepIndex?: number;
}

export interface WorkflowGeneratorResponse {
  message: string;
  phase: WorkflowPhase;
  questions?: ClarificationQuestion[];
  workflow?: DraftWorkflow;
  currentStep?: WorkflowStep;
  validationResults?: ValidationResult[];
  suggestions?: string[];
}

export interface ValidationResult {
  type: 'error' | 'warning' | 'info';
  step?: string;
  message: string;
  canProceed: boolean;
}

// ============================================================================
// ITERATIVE WORKFLOW GENERATOR
// ============================================================================

export class IterativeWorkflowGenerator {
  private claude: Anthropic;
  private sessions: Map<string, SessionContext> = new Map();

  constructor(apiKey: string) {
    this.claude = new Anthropic({ apiKey });
  }

  /**
   * Process user message and advance through workflow phases
   */
  async processMessage(
    sessionId: string,
    message: string,
    context?: Partial<SessionContext>
  ): Promise<WorkflowGeneratorResponse> {

    // Get or create session
    let session = this.sessions.get(sessionId);
    if (!session) {
      session = this.createSession(sessionId, context);
      this.sessions.set(sessionId, session);
    }

    // Add message to history
    session.conversationHistory.push({
      role: 'user',
      content: message
    });

    console.log(`[IterativeWorkflow] Processing message in phase: ${session.currentPhase}`);

    // Route to appropriate phase handler
    let response: WorkflowGeneratorResponse;

    switch (session.currentPhase) {
      case WorkflowPhase.CLARIFICATION:
        response = await this.handleClarification(session, message);
        break;

      case WorkflowPhase.DRAFT:
        response = await this.handleDraftReview(session, message);
        break;

      case WorkflowPhase.STEP_BY_STEP:
        response = await this.handleStepConfiguration(session, message);
        break;

      case WorkflowPhase.VALIDATION:
        response = await this.handleValidation(session, message);
        break;

      case WorkflowPhase.READY:
        response = {
          message: 'Workflow is ready for execution. Would you like to run it now?',
          phase: WorkflowPhase.READY,
          suggestions: ['Execute workflow', 'Review workflow', 'Make changes']
        };
        break;

      default:
        response = await this.handleClarification(session, message);
    }

    // Add response to history
    session.conversationHistory.push({
      role: 'assistant',
      content: response.message
    });

    return response;
  }

  /**
   * Phase 1: CLARIFICATION - Ask questions to understand requirements
   */
  private async handleClarification(
    session: SessionContext,
    message: string
  ): Promise<WorkflowGeneratorResponse> {

    console.log('[IterativeWorkflow] Phase 1: Clarification');

    // Analyze user intent and generate questions
    const intent = await this.analyzeIntent(message);
    const allQuestions = this.generateClarificationQuestions(intent, session);

    // Filter out questions we can infer from context
    const necessaryQuestions = allQuestions.filter(q => !q.canInfer);

    if (necessaryQuestions.length > 0) {
      session.openQuestions = necessaryQuestions;

      return {
        message: this.formatClarificationMessage(necessaryQuestions),
        phase: WorkflowPhase.CLARIFICATION,
        questions: necessaryQuestions,
        suggestions: ['Answer questions', 'Skip and generate draft']
      };
    } else {
      // All questions answered or can be inferred - move to draft
      console.log('[IterativeWorkflow] All questions answered, moving to draft');
      session.currentPhase = WorkflowPhase.DRAFT;
      return await this.generateDraft(session);
    }
  }

  /**
   * Phase 2: DRAFT - Generate high-level workflow structure
   */
  private async generateDraft(
    session: SessionContext
  ): Promise<WorkflowGeneratorResponse> {

    console.log('[IterativeWorkflow] Phase 2: Generating draft workflow');

    const systemPrompt = this.buildDraftSystemPrompt(session);

    const response = await this.claude.messages.create({
      model: 'claude-sonnet-4-5',
      max_tokens: 3000,
      temperature: 0,
      system: systemPrompt,
      messages: [{
        role: 'user',
        content: 'Generate a high-level workflow structure based on the requirements.'
      }]
    });

    const workflowText = response.content[0].type === 'text'
      ? response.content[0].text
      : '';

    const draftWorkflow = this.parseDraftWorkflow(workflowText, session);
    session.inferredContext.draftWorkflow = draftWorkflow;

    return {
      message: this.formatDraftMessage(draftWorkflow),
      phase: WorkflowPhase.DRAFT,
      workflow: draftWorkflow,
      suggestions: [
        'Yes, looks good - continue',
        'Modify workflow structure',
        'Start over with different approach'
      ]
    };
  }

  /**
   * Phase 2: Handle user feedback on draft workflow
   */
  private async handleDraftReview(
    session: SessionContext,
    message: string
  ): Promise<WorkflowGeneratorResponse> {

    console.log('[IterativeWorkflow] Phase 2: Reviewing draft feedback');

    const messageLower = message.toLowerCase();

    // Check if user approves
    if (messageLower.includes('yes') || messageLower.includes('looks good') ||
        messageLower.includes('continue') || messageLower.includes('proceed')) {

      // Move to step-by-step configuration
      session.currentPhase = WorkflowPhase.STEP_BY_STEP;
      session.currentStepIndex = 0;

      return await this.configureNextStep(session);
    }

    // User wants modifications
    if (messageLower.includes('modify') || messageLower.includes('change') ||
        messageLower.includes('different')) {

      // Regenerate draft with modifications
      session.conversationHistory.push({
        role: 'user',
        content: `User requested modifications: ${message}`
      });

      return await this.generateDraft(session);
    }

    // Default: ask for clarification
    return {
      message: `I understand you have feedback on the workflow. Could you specify:
- Which steps need to be changed?
- What would you like to add or remove?
- Any specific tools you prefer?

Or simply say "continue" if the workflow looks good.`,
      phase: WorkflowPhase.DRAFT,
      workflow: session.inferredContext.draftWorkflow,
      suggestions: ['Continue', 'Modify step X', 'Add step for Y']
    };
  }

  /**
   * Phase 3: STEP_BY_STEP - Configure each step with parameters
   */
  private async handleStepConfiguration(
    session: SessionContext,
    message: string
  ): Promise<WorkflowGeneratorResponse> {

    console.log(`[IterativeWorkflow] Phase 3: Configuring step ${session.currentStepIndex}`);

    const messageLower = message.toLowerCase();

    // Check if user approves current step
    if (messageLower.includes('yes') || messageLower.includes('looks good') ||
        messageLower.includes('continue') || messageLower.includes('next')) {

      // Mark current step as configured
      const draft = session.inferredContext.draftWorkflow as DraftWorkflow;
      if (draft && session.currentStepIndex !== undefined) {
        draft.steps[session.currentStepIndex].configured = true;
      }

      // Move to next step or validation
      session.currentStepIndex!++;

      if (session.currentStepIndex! >= draft.steps.length) {
        // All steps configured - move to validation
        session.currentPhase = WorkflowPhase.VALIDATION;
        return await this.validateWorkflow(session);
      } else {
        // Configure next step
        return await this.configureNextStep(session);
      }
    }

    // User wants to modify parameters
    // Handle parameter modifications here
    return await this.modifyStepParameters(session, message);
  }

  /**
   * Configure next step in the workflow
   */
  private async configureNextStep(
    session: SessionContext
  ): Promise<WorkflowGeneratorResponse> {

    const draft = session.inferredContext.draftWorkflow as DraftWorkflow;
    const stepIndex = session.currentStepIndex!;
    const step = draft.steps[stepIndex];

    const systemPrompt = `You are configuring step ${stepIndex + 1} of ${draft.steps.length}: ${step.name}

Tool: ${step.suggestedTool}
Purpose: ${step.purpose}

Provide detailed configuration for this step:
1. Input requirements (what files/data needed)
2. Key parameters with explanations
3. Recommended parameter values
4. Expected output
5. Common mistakes to avoid

Format as a clear, structured explanation that a user can review.`;

    const response = await this.claude.messages.create({
      model: 'claude-sonnet-4-5',
      max_tokens: 2000,
      temperature: 0,
      system: systemPrompt,
      messages: [{
        role: 'user',
        content: 'Configure this step'
      }]
    });

    const stepConfig = response.content[0].type === 'text'
      ? response.content[0].text
      : '';

    // Parse step configuration
    this.parseStepConfiguration(step, stepConfig);

    return {
      message: `**Step ${stepIndex + 1}/${draft.steps.length}: ${step.name}**

${stepConfig}

Does this configuration look correct?
○ Yes, continue to next step
○ Modify parameters`,
      phase: WorkflowPhase.STEP_BY_STEP,
      currentStep: step,
      suggestions: ['Yes, continue', 'Modify parameters', 'Skip this step']
    };
  }

  /**
   * Phase 4: VALIDATION - Pre-execution validation
   */
  private async handleValidation(
    session: SessionContext,
    message: string
  ): Promise<WorkflowGeneratorResponse> {

    console.log('[IterativeWorkflow] Phase 4: Handling validation feedback');

    const messageLower = message.toLowerCase();

    if (messageLower.includes('yes') || messageLower.includes('execute') ||
        messageLower.includes('run') || messageLower.includes('proceed')) {

      session.currentPhase = WorkflowPhase.READY;

      return {
        message: '✅ Workflow validated and ready for execution!\n\nYour workflow is now ready to run. Execute it from the workflow builder.',
        phase: WorkflowPhase.READY,
        workflow: session.inferredContext.draftWorkflow,
        suggestions: ['Execute now', 'Save for later', 'Export workflow']
      };
    }

    // User wants to make changes
    return {
      message: 'Which step would you like to modify?',
      phase: WorkflowPhase.VALIDATION,
      workflow: session.inferredContext.draftWorkflow,
      suggestions: session.inferredContext.draftWorkflow.steps.map((s: WorkflowStep, i: number) =>
        `Modify Step ${i + 1}: ${s.name}`
      )
    };
  }

  /**
   * Validate entire workflow before execution
   */
  private async validateWorkflow(
    session: SessionContext
  ): Promise<WorkflowGeneratorResponse> {

    console.log('[IterativeWorkflow] Validating complete workflow');

    const draft = session.inferredContext.draftWorkflow as DraftWorkflow;
    const validationResults: ValidationResult[] = [];

    // Basic validations
    draft.steps.forEach((step, idx) => {
      if (!step.configured) {
        validationResults.push({
          type: 'warning',
          step: step.name,
          message: `Step ${idx + 1} "${step.name}" is not fully configured`,
          canProceed: true
        });
      }

      if (!step.toolId && !step.suggestedTool) {
        validationResults.push({
          type: 'error',
          step: step.name,
          message: `Step ${idx + 1} "${step.name}" has no tool specified`,
          canProceed: false
        });
      }
    });

    const hasErrors = validationResults.some(v => v.type === 'error');

    let message = '## Workflow Validation\n\n';

    if (validationResults.length === 0) {
      message += '✅ All checks passed! Your workflow is ready for execution.\n\n';
    } else {
      message += '### Validation Results:\n\n';
      validationResults.forEach(v => {
        const icon = v.type === 'error' ? '❌' : v.type === 'warning' ? '⚠️' : 'ℹ️';
        message += `${icon} ${v.message}\n`;
      });
      message += '\n';
    }

    message += hasErrors
      ? 'Please fix errors before proceeding.'
      : 'Ready to execute?';

    return {
      message,
      phase: WorkflowPhase.VALIDATION,
      workflow: draft,
      validationResults,
      suggestions: hasErrors
        ? ['Fix errors', 'Review workflow']
        : ['Yes, execute', 'Review workflow', 'Make changes']
    };
  }

  // ============================================================================
  // HELPER METHODS
  // ============================================================================

  private createSession(sessionId: string, context?: Partial<SessionContext>): SessionContext {
    return {
      sessionId,
      conversationHistory: [],
      userAnswers: {},
      inferredContext: {},
      openQuestions: [],
      currentPhase: WorkflowPhase.CLARIFICATION,
      ...context
    };
  }

  private async analyzeIntent(message: string): Promise<Record<string, any>> {
    // Simple intent analysis - can be enhanced with Claude
    const intent: Record<string, any> = {
      mentionsDataType: /rna-?seq|proteomics|chip-seq|variant|genome/i.test(message),
      mentionsOrganism: /human|mouse|rat|drosophila|e\.?\s*coli/i.test(message),
      mentionsGoal: /differential|expression|variant|alignment|assembly/i.test(message),
    };

    return intent;
  }

  private generateClarificationQuestions(
    intent: Record<string, any>,
    session: SessionContext
  ): ClarificationQuestion[] {

    const questions: ClarificationQuestion[] = [];

    // Data type question
    if (!intent.mentionsDataType && !session.inferredContext.dataType) {
      questions.push({
        id: 'data_type',
        question: 'What type of data are you working with?',
        category: 'data_type',
        required: true,
        options: ['RNA-seq', 'Proteomics', 'ChIP-seq', 'Variant calling', 'Genome assembly'],
        canInfer: false
      });
    }

    // Organism question
    if (!intent.mentionsOrganism && !session.inferredContext.organism) {
      questions.push({
        id: 'organism',
        question: 'What organism are you studying?',
        category: 'organism',
        required: true,
        options: ['Human', 'Mouse', 'Rat', 'Drosophila', 'E. coli', 'Other'],
        canInfer: false
      });
    }

    // Analysis goal
    if (!intent.mentionsGoal && !session.inferredContext.analysisGoal) {
      questions.push({
        id: 'analysis_goal',
        question: 'What is your analysis goal?',
        category: 'analysis_goal',
        required: true,
        canInfer: false
      });
    }

    return questions;
  }

  private formatClarificationMessage(questions: ClarificationQuestion[]): string {
    let message = "I'll help you build a workflow. First, let me understand your requirements:\n\n";

    questions.forEach((q, i) => {
      message += `**${i + 1}. ${q.question}**\n`;
      if (q.options) {
        message += `Options: ${q.options.join(', ')}\n`;
      }
      message += '\n';
    });

    message += 'Please answer these questions, and I\'ll generate a workflow tailored to your needs.';

    return message;
  }

  private buildDraftSystemPrompt(session: SessionContext): string {
    return `You are an expert bioinformatics workflow designer.

User Requirements:
${JSON.stringify(session.inferredContext, null, 2)}

Conversation History:
${session.conversationHistory.slice(-5).map(m => `${m.role}: ${m.content}`).join('\n')}

Generate a high-level workflow structure with 4-6 major steps.
For each step, provide:
- Step name (clear, descriptive)
- Purpose (why this step is needed)
- Suggested tool (specific bioinformatics tool name)

Format as JSON:
{
  "title": "Workflow Title",
  "description": "Brief description",
  "analysisType": "RNA-seq analysis",
  "steps": [
    {
      "name": "Quality Control",
      "purpose": "Assess read quality and identify issues",
      "suggestedTool": "FastQC"
    },
    ...
  ],
  "complexity": "moderate"
}`;
  }

  private parseDraftWorkflow(text: string, session: SessionContext): DraftWorkflow {
    try {
      // Try to parse as JSON first
      const jsonMatch = text.match(/\{[\s\S]*\}/);
      if (jsonMatch) {
        const parsed = JSON.parse(jsonMatch[0]);

        // Add IDs to steps
        parsed.steps = parsed.steps.map((step: any, idx: number) => ({
          ...step,
          stepId: `step-${idx + 1}`,
          configured: false
        }));

        parsed.workflowId = `workflow-${Date.now()}`;

        return parsed;
      }
    } catch (e) {
      console.error('[IterativeWorkflow] Failed to parse workflow JSON:', e);
    }

    // Fallback: create default workflow
    return {
      workflowId: `workflow-${Date.now()}`,
      title: 'Custom Workflow',
      description: 'Workflow generated from user requirements',
      analysisType: 'bioinformatics',
      complexity: 'moderate',
      steps: [
        {
          stepId: 'step-1',
          name: 'Quality Control',
          purpose: 'Assess data quality',
          suggestedTool: 'FastQC',
          configured: false
        }
      ]
    };
  }

  private formatDraftMessage(workflow: DraftWorkflow): string {
    let message = `## Draft Workflow: ${workflow.title}\n\n`;
    message += `${workflow.description}\n\n`;
    message += `**Complexity:** ${workflow.complexity}\n\n`;
    message += `### Workflow Steps:\n\n`;

    workflow.steps.forEach((step, idx) => {
      message += `**Step ${idx + 1}: ${step.name}**\n`;
      message += `- Purpose: ${step.purpose}\n`;
      message += `- Tool: ${step.suggestedTool}\n\n`;
    });

    message += 'Does this high-level workflow structure look good?\n';
    message += '○ Yes, continue to detailed configuration\n';
    message += '○ Modify workflow structure';

    return message;
  }

  private parseStepConfiguration(step: WorkflowStep, configText: string): void {
    // Extract parameters from configuration text
    // This is a simplified version - can be enhanced

    step.inputRequirements = [];
    step.parameters = {};
    step.expectedOutput = '';
    step.warnings = [];

    // Parse sections
    const lines = configText.split('\n');
    let currentSection = '';

    lines.forEach(line => {
      if (line.match(/input requirements?:/i)) {
        currentSection = 'input';
      } else if (line.match(/parameters?:/i)) {
        currentSection = 'parameters';
      } else if (line.match(/output:/i)) {
        currentSection = 'output';
      } else if (line.match(/warnings?|mistakes?:/i)) {
        currentSection = 'warnings';
      }

      // Add content to appropriate section
      if (currentSection === 'input' && line.trim() && !line.match(/^input/i)) {
        step.inputRequirements!.push(line.trim());
      } else if (currentSection === 'warnings' && line.trim() && !line.match(/^warnings?/i)) {
        step.warnings!.push(line.trim());
      }
    });
  }

  private async modifyStepParameters(
    session: SessionContext,
    message: string
  ): Promise<WorkflowGeneratorResponse> {

    const draft = session.inferredContext.draftWorkflow as DraftWorkflow;
    const stepIndex = session.currentStepIndex!;
    const step = draft.steps[stepIndex];

    return {
      message: `I'll update the parameters for ${step.name}. What would you like to change?`,
      phase: WorkflowPhase.STEP_BY_STEP,
      currentStep: step,
      suggestions: ['Change tool', 'Modify parameters', 'Continue with current settings']
    };
  }

  /**
   * Get session for inspection
   */
  getSession(sessionId: string): SessionContext | undefined {
    return this.sessions.get(sessionId);
  }

  /**
   * Clear session
   */
  clearSession(sessionId: string): void {
    this.sessions.delete(sessionId);
  }
}