# BioMate V2.0 Platform: REVISED Implementation Roadmap
## Integrating Claude Code Orchestration + ACE Learning

**Document Created:** 2025-10-31 (REVISED)
**Status:** Ready for Execution
**Critical Update:** Adds proactive orchestration features (iterative generation, validation, context management)

---

## Executive Summary

**Previous Roadmap Gap**: Focused only on ACE learning (reactive, learns from failures after execution) but missed Claude Code-inspired orchestration (proactive, prevents failures before execution).

**Revised Approach**: Integrate BOTH systems for comprehensive workflow intelligence.

### Two Complementary Systems

**System 1: Proactive Orchestration** (Claude Code-inspired)
- Iterative workflow generation with user clarification
- Multi-layer validation BEFORE execution
- Context compression (auto-summarize conversations)
- MD files for knowledge storage
- Workflow modes (Plan/Auto-accept/YOLO)
- Sub-agents for specialized tasks

**System 2: Reactive Learning** (ACE-inspired)
- Learn from execution failures
- Update playbook with proven rules
- Continuous improvement over time
- Evidence-based confidence scoring

**Combined Impact**: 80-85% workflow success rate (vs 70% baseline)
- Proactive: +5-8% (catch errors before execution)
- Reactive: +5-7% (learn from failures)

---

## Revised 18-Week Implementation Plan

### Phase 0: Critical Missing Features (Weeks 1-3) 🆕

This phase was COMPLETELY MISSING from original roadmap.

#### Week 1: Context Management + User Profiles

**Goal**: Enable memory across sessions

```typescript
// File: backend/services/session-context.ts

interface UserProfile {
  userId: string;
  expertiseLevel: 'beginner' | 'intermediate' | 'advanced';
  researchDomain: {
    primary: string;
    subdomains: string[];
    organisms: string[];
  };
  toolPreferences: Array<{
    task: string;
    preferredTool: string;
    reason: string;
    confidence: number;
  }>;
  correctionLog: Array<{
    timestamp: Date;
    mistakeTool: string;
    correctTool: string;
    context: Record<string, any>;
    explanation: string;
  }>;
}

class SessionContext {
  private conversationHistory: Message[] = [];
  private decisions: Decision[] = [];

  async compactHistory() {
    // Auto-compress when context > 80% of limit
    if (this.estimateTokens() > 160000) { // 80% of 200K
      const oldMessages = this.conversationHistory.slice(0, -10);
      const summary = await this.summarizeMessages(oldMessages);

      this.conversationHistory = [
        {
          role: 'system',
          content: `Previous conversation summary: ${summary}`
        },
        ...this.conversationHistory.slice(-10)
      ];

      console.log('✅ Context compressed');
    }
  }

  private async summarizeMessages(messages: Message[]): Promise<string> {
    // Use Claude to summarize old messages
    const response = await this.claudeClient.messages.create({
      model: 'claude-3-haiku-20240307', // Fast, cheap
      max_tokens: 1000,
      messages: [{
        role: 'user',
        content: `Summarize this conversation focusing on:
        - User's research goal
        - Data type and organism
        - Key decisions made
        - Tools selected

        Messages: ${JSON.stringify(messages)}`
      }]
    });

    return response.content[0].text;
  }

  getContextSummary(): string {
    return `
User Research Context:
- Goal: ${this.inferGoal()}
- Data Type: ${this.inferDataType()}
- Organism: ${this.inferOrganism()}
- Key Decisions: ${this.decisions.map(d => d.summary).join(', ')}
- Open Questions: ${this.getOpenQuestions()}
    `.trim();
  }
}

// File: backend/storage/user-profiles.json (MD alternative)
// Store user profiles as JSON (can be markdown too)
{
  "user_123": {
    "expertise_level": "intermediate",
    "research_domain": {
      "primary": "proteomics",
      "subdomains": ["phosphoproteomics", "DIA"],
      "organisms": ["mouse", "human"]
    },
    "tool_preferences": [
      {
        "task": "database_search",
        "preferred_tool": "dia_nn",
        "reason": "User explicitly chose DIA-NN over MaxQuant (2025-10-15)",
        "confidence": 1.0
      }
    ],
    "correction_log": [
      {
        "timestamp": "2025-10-20T14:30:00Z",
        "mistake_tool": "maxquant",
        "correct_tool": "dia_nn",
        "context": {"data_type": "DIA"},
        "explanation": "MaxQuant doesn't work for DIA data"
      }
    ]
  }
}

Deliverable: Context management operational, user profiles stored ✅
Timeline: 5 days
Cost: $15K-20K
```

---

#### Week 2: Iterative Workflow Generation

**Goal**: Build workflows step-by-step with user clarification

```typescript
// File: frontend/server/iterative-workflow-generator.ts

enum WorkflowPhase {
  CLARIFICATION = 'clarification',
  DRAFT = 'draft',
  STEP_BY_STEP = 'step_by_step',
  VALIDATION = 'validation',
  READY = 'ready'
}

class IterativeWorkflowGenerator {
  private phase: WorkflowPhase = WorkflowPhase.CLARIFICATION;
  private draftWorkflow: Workflow | null = null;
  private openQuestions: Question[] = [];

  async processUserMessage(
    message: string,
    sessionContext: SessionContext
  ): Promise<Response> {

    switch (this.phase) {
      case WorkflowPhase.CLARIFICATION:
        return this.handleClarification(message, sessionContext);

      case WorkflowPhase.DRAFT:
        return this.handleDraftReview(message);

      case WorkflowPhase.STEP_BY_STEP:
        return this.handleStepConfiguration(message);

      case WorkflowPhase.VALIDATION:
        return this.handleValidation(message);
    }
  }

  private async handleClarification(
    message: string,
    context: SessionContext
  ): Promise<Response> {
    // Phase 1: Ask clarifying questions

    const intent = await this.analyzeIntent(message);
    const questions = this.generateQuestions(intent, context);

    // Skip questions we can infer
    const necessaryQuestions = questions.filter(q =>
      !this.canInfer(q, context)
    );

    if (necessaryQuestions.length > 0) {
      return {
        message: `I'll help you build a workflow. First, let me understand your data:

${necessaryQuestions.map((q, i) => `${i+1}. ${q.question}`).join('\n')}`,
        questions: necessaryQuestions,
        phase: WorkflowPhase.CLARIFICATION
      };
    } else {
      // All questions answered, move to draft
      this.phase = WorkflowPhase.DRAFT;
      return this.generateDraft(context);
    }
  }

  private async generateDraft(context: SessionContext): Promise<Response> {
    // Phase 2: Generate high-level workflow structure

    const systemPrompt = `
You are a proteomics workflow assistant.

User Context:
${context.getContextSummary()}

Generate a HIGH-LEVEL workflow structure (4-6 major steps only).
For each step, provide:
- Step name
- Purpose (why this step is needed)
- Tool suggestion

DO NOT provide detailed parameters yet.
    `;

    const response = await this.claudeClient.messages.create({
      model: 'claude-3-5-sonnet-20241022',
      max_tokens: 2000,
      messages: [{
        role: 'user',
        content: 'Generate workflow draft'
      }],
      system: systemPrompt
    });

    this.draftWorkflow = this.parseDraftWorkflow(response.content[0].text);

    return {
      message: `Here's a draft workflow structure:

${this.draftWorkflow.steps.map((step, i) => `
Step ${i+1}: ${step.name}
Purpose: ${step.purpose}
Tool: ${step.suggestedTool}
`).join('\n')}

Does this high-level flow make sense for your needs?
○ Yes, continue to detailed configuration
○ No, I need [specify changes]`,
      workflow: this.draftWorkflow,
      phase: WorkflowPhase.DRAFT
    };
  }

  private async handleStepConfiguration(
    message: string
  ): Promise<Response> {
    // Phase 3: Configure each step in detail

    const currentStepIndex = this.getCurrentStepIndex();
    const step = this.draftWorkflow!.steps[currentStepIndex];

    const systemPrompt = `
You are configuring step ${currentStepIndex + 1}: ${step.name}

Tool: ${step.suggestedTool}

Provide:
1. Input requirements
2. Key parameters with explanations
3. Expected output
4. Common mistakes to avoid

Ask user if parameters look correct before proceeding to next step.
    `;

    const response = await this.claudeClient.messages.create({
      model: 'claude-3-5-sonnet-20241022',
      max_tokens: 1500,
      messages: [{
        role: 'user',
        content: message
      }],
      system: systemPrompt
    });

    return {
      message: response.content[0].text,
      currentStep: currentStepIndex,
      totalSteps: this.draftWorkflow!.steps.length,
      phase: WorkflowPhase.STEP_BY_STEP
    };
  }

  private generateQuestions(
    intent: Intent,
    context: SessionContext
  ): Question[] {
    const questions: Question[] = [];

    // Question 1: Data Type (if not clear)
    if (!intent.dataType && !context.hasDataType()) {
      questions.push({
        id: 'data_type',
        question: 'What type of proteomics data do you have?',
        type: 'single_choice',
        options: [
          {
            value: 'DDA',
            label: 'DDA (Data-Dependent Acquisition)',
            description: 'Traditional shotgun proteomics'
          },
          {
            value: 'DIA',
            label: 'DIA (Data-Independent Acquisition)',
            description: 'Newer method with SWATH patterns'
          },
          {
            value: 'unknown',
            label: "I'm not sure",
            description: 'I need help identifying my data type'
          }
        ],
        priority: 'high',
        impact: ['search_engine_selection', 'quantification_method']
      });
    }

    // Question 2: Analysis Goal
    if (!intent.goal) {
      questions.push({
        id: 'analysis_goal',
        question: "What's your primary analysis goal?",
        type: 'multiple_choice',
        options: [
          {
            value: 'identification',
            label: 'Protein Identification',
            description: 'Just identify what proteins are present'
          },
          {
            value: 'quantification',
            label: 'Quantitative Comparison',
            description: 'Compare protein levels between conditions'
          },
          {
            value: 'ptm',
            label: 'Post-Translational Modifications',
            description: 'Find phosphorylation, acetylation, etc.'
          }
        ],
        priority: 'high'
      });
    }

    // Question 3: Organism (if not in profile or dataset)
    if (!context.hasOrganism()) {
      questions.push({
        id: 'organism',
        question: 'What organism are your samples from?',
        type: 'autocomplete',
        commonOptions: ['Human', 'Mouse', 'Rat', 'Yeast', 'E. coli'],
        allowCustom: true,
        priority: 'high',
        impact: ['database_selection']
      });
    }

    return questions;
  }

  private canInfer(question: Question, context: SessionContext): boolean {
    // Skip question if we can infer from context

    if (question.id === 'organism') {
      // Check user profile
      if (context.userProfile?.researchDomain?.organisms?.length > 0) {
        return true;
      }
      // Check dataset metadata
      if (context.selectedDataset?.metadata?.organism) {
        return true;
      }
    }

    if (question.id === 'data_type') {
      // Try to detect from file names
      if (context.selectedDataset) {
        const detected = this.detectDataType(context.selectedDataset);
        if (detected !== 'unknown') {
          return true;
        }
      }
    }

    return false;
  }
}

Deliverable: Iterative generation operational ✅
Timeline: 5 days
Cost: $20K-25K
```

---

#### Week 3: Multi-Layer Validation

**Goal**: Validate workflows BEFORE execution (5 layers)

```typescript
// File: backend/services/workflow-validator.ts

interface ValidationIssue {
  severity: 'critical' | 'high' | 'medium' | 'low';
  type: 'incompatibility' | 'scientific_error' | 'redundancy' | 'parameter_issue';
  step?: number;
  description: string;
  suggestion: string;
  autoFixable: boolean;
  fixAction?: () => void;
}

class WorkflowValidator {
  async validate(
    workflow: Workflow,
    context: WorkflowContext
  ): Promise<ValidationReport> {
    const issues: ValidationIssue[] = [];

    // Layer 1: Structural Validation
    issues.push(...this.validateStructure(workflow));

    // Layer 2: Tool Chain Compatibility
    issues.push(...this.validateToolChain(workflow));

    // Layer 3: Parameter Validation
    issues.push(...this.validateParameters(workflow, context));

    // Layer 4: Scientific Validity
    issues.push(...this.validateScientificLogic(workflow, context));

    // Layer 5: Resource Availability
    issues.push(...this.validateResources(workflow));

    return {
      valid: issues.filter(i => i.severity === 'critical').length === 0,
      canExecute: issues.filter(i => i.severity === 'critical').length === 0,
      issues: issues,
      summary: this.generateSummary(issues)
    };
  }

  private validateToolChain(workflow: Workflow): ValidationIssue[] {
    const issues: ValidationIssue[] = [];

    for (let i = 0; i < workflow.steps.length - 1; i++) {
      const currentStep = workflow.steps[i];
      const nextStep = workflow.steps[i + 1];

      const currentOutputs = this.getOutputFormats(currentStep.tool);
      const nextInputs = this.getInputFormats(nextStep.tool);

      if (!this.formatsCompatible(currentOutputs, nextInputs)) {
        // Try to find bridging tool
        const bridge = this.findFormatConverter(currentOutputs, nextInputs);

        if (bridge) {
          issues.push({
            severity: 'medium',
            type: 'incompatibility',
            step: i,
            description: `Format mismatch between step ${i} (${currentStep.tool.name}) and step ${i+1} (${nextStep.tool.name})`,
            suggestion: `Add format conversion step: ${bridge.name}`,
            autoFixable: true,
            fixAction: () => workflow.insertStep(i + 1, bridge)
          });
        } else {
          issues.push({
            severity: 'critical',
            type: 'incompatibility',
            step: i,
            description: `Step ${i} outputs ${currentOutputs.join(', ')} but step ${i+1} requires ${nextInputs.join(', ')}`,
            suggestion: 'These tools cannot be chained. Please select compatible tools.',
            autoFixable: false
          });
        }
      }
    }

    return issues;
  }

  private validateScientificLogic(
    workflow: Workflow,
    context: WorkflowContext
  ): ValidationIssue[] {
    const issues: ValidationIssue[] = [];

    // Rule 1: DIA data should not use DDA tools
    if (context.dataType === 'DIA') {
      const ddaOnlyTools = ['maxquant', 'proteome_discoverer', 'msgf_plus'];

      for (const step of workflow.steps) {
        if (ddaOnlyTools.includes(step.tool.id)) {
          issues.push({
            severity: 'critical',
            type: 'scientific_error',
            step: step.index,
            description: `${step.tool.name} is designed for DDA data, but you have DIA data`,
            suggestion: `Replace with DIA-specific tool like DIA-NN or Spectronaut`,
            autoFixable: true,
            fixAction: () => {
              const alternative = this.findAlternative(step.tool, {
                dataType: 'DIA'
              });
              workflow.replaceStep(step.index, alternative);
            }
          });
        }
      }
    }

    // Rule 2: TMT/iTRAQ experiments need reporter ion quantification
    if (context.hasIsobaricLabeling) {
      const hasReporterQuant = workflow.steps.some(
        step => step.tool.category === 'isobaric_quantification'
      );

      if (!hasReporterQuant) {
        issues.push({
          severity: 'high',
          type: 'scientific_error',
          description: 'TMT/iTRAQ experiment detected but no reporter ion quantification step',
          suggestion: 'Add reporter ion quantification step after database search',
          autoFixable: true,
          fixAction: () => {
            const reporterTool = this.findTool('reporter_ion_quant');
            const searchStepIndex = workflow.steps.findIndex(
              s => s.tool.category === 'database_search'
            );
            workflow.insertStep(searchStepIndex + 1, reporterTool);
          }
        });
      }
    }

    // Rule 3: Check for redundant normalization
    const normalizationSteps = workflow.steps.filter(
      step => step.tool.category === 'normalization'
    );

    if (normalizationSteps.length > 1) {
      issues.push({
        severity: 'medium',
        type: 'redundancy',
        description: `Multiple normalization steps detected: ${normalizationSteps.map(s => s.tool.name).join(', ')}`,
        suggestion: 'Typically only one normalization method is needed. Consider removing redundant steps.',
        autoFixable: false
      });
    }

    // Rule 4: Statistical analysis needs replicates
    const statsSteps = workflow.steps.filter(
      step => step.tool.category === 'statistical_analysis'
    );

    if (statsSteps.length > 0 && context.numReplicates < 2) {
      issues.push({
        severity: 'high',
        type: 'scientific_error',
        description: 'Statistical analysis requires replicates, but only 1 sample per condition detected',
        suggestion: 'Statistical tests are not meaningful with n=1. Consider removing statistical analysis or confirming you have replicates.',
        autoFixable: false
      });
    }

    return issues;
  }

  private validateParameters(
    workflow: Workflow,
    context: WorkflowContext
  ): ValidationIssue[] {
    const issues: ValidationIssue[] = [];

    for (const step of workflow.steps) {
      const tool = step.tool;
      const params = step.parameters;

      // Check each parameter
      for (const [paramName, paramValue] of Object.entries(params)) {
        const paramDef = tool.parameters[paramName];

        if (!paramDef) continue;

        // Check range
        if (paramDef.range) {
          const [min, max] = paramDef.range;
          if (paramValue < min || paramValue > max) {
            issues.push({
              severity: 'high',
              type: 'parameter_issue',
              step: step.index,
              description: `Parameter '${paramName}' value ${paramValue} is outside valid range [${min}, ${max}]`,
              suggestion: `Use recommended value: ${paramDef.default}`,
              autoFixable: true,
              fixAction: () => {
                step.parameters[paramName] = paramDef.default;
              }
            });
          }
        }

        // Check instrument-specific parameters
        if (paramDef.instrumentDependent && context.instrument) {
          const recommendedValue = paramDef.instrumentDependent[context.instrument];
          if (recommendedValue && Math.abs(paramValue - recommendedValue) > recommendedValue * 0.5) {
            issues.push({
              severity: 'medium',
              type: 'parameter_issue',
              step: step.index,
              description: `Parameter '${paramName}' (${paramValue}) may not be optimal for ${context.instrument}`,
              suggestion: `Recommended value for ${context.instrument}: ${recommendedValue}`,
              autoFixable: true,
              fixAction: () => {
                step.parameters[paramName] = recommendedValue;
              }
            });
          }
        }
      }
    }

    return issues;
  }
}

Deliverable: Multi-layer validation operational ✅
Expected: Catch 80-90% of errors before execution
Timeline: 5 days
Cost: $20K-30K
```

---

### Phase 1: ACE Learning System (Weeks 4-7)

This was the original Phase 1, now moved to week 4-7.

*(Keep all Week 1-4 content from original roadmap, but renumber to Week 4-7)*

**Week 4**: Scientific metadata + CRISPR tools + ACE database design
**Week 5**: PlaybookDatabase + Auto-update discovery
**Week 6**: ACE Reflector service
**Week 7**: ACE Curator service

---

### Phase 2: Integration (Weeks 8-11)

*(Original Phase 2, renumbered)*

**Week 8**: GalaxyAssistant integration with playbook + enhanced tool search
**Week 9**: GalaxyStatePoller integration with ACE feedback
**Week 10**: Use-case routing system
**Week 11**: Clinical reporting system (start)

---

### Phase 3: Workflow Modes + Sub-Agents (Weeks 12-13) 🆕

This phase was COMPLETELY MISSING.

#### Week 12: Workflow Modes

**Goal**: Implement Plan Mode / Auto-Accept / YOLO modes

```typescript
// File: frontend/server/workflow-modes.ts

enum WorkflowMode {
  PLAN = 'plan',           // User approves each step (safest)
  AUTO_ACCEPT = 'auto',    // Generate workflow, user reviews before execution
  YOLO = 'yolo'            // Generate and execute automatically (risky)
}

class WorkflowModeHandler {
  private mode: WorkflowMode;

  async generateWorkflow(
    userMessage: string,
    context: SessionContext
  ): Promise<WorkflowResponse> {

    switch (this.mode) {
      case WorkflowMode.PLAN:
        return this.handlePlanMode(userMessage, context);

      case WorkflowMode.AUTO_ACCEPT:
        return this.handleAutoAcceptMode(userMessage, context);

      case WorkflowMode.YOLO:
        return this.handleYoloMode(userMessage, context);
    }
  }

  private async handlePlanMode(
    userMessage: string,
    context: SessionContext
  ): Promise<WorkflowResponse> {
    // Generate workflow iteratively
    const generator = new IterativeWorkflowGenerator();
    const workflow = await generator.generateWithApproval(userMessage, context);

    // User must approve EACH step
    return {
      workflow: workflow,
      requiresApproval: true,
      message: `
Proposed workflow:

${workflow.steps.map((s, i) => `Step ${i+1}: ${s.name}`).join('\n')}

👤 Review each step:
${workflow.steps.map((s, i) => `
  Step ${i+1}: ${s.tool.name}
  [ ] Approve  [ ] Modify  [ ] Skip
`).join('\n')}

Approve to proceed?
      `
    };
  }

  private async handleAutoAcceptMode(
    userMessage: string,
    context: SessionContext
  ): Promise<WorkflowResponse> {
    // Generate workflow automatically
    const generator = new IterativeWorkflowGenerator();
    const workflow = await generator.generateQuick(userMessage, context);

    // Validate automatically
    const validator = new WorkflowValidator();
    const validation = await validator.validate(workflow, context);

    if (!validation.valid) {
      // Auto-fix if possible
      const autoFixer = new WorkflowAutoFixer();
      const fixes = await autoFixer.autoFix(workflow, validation.issues);

      return {
        workflow: workflow,
        validation: validation,
        autoFixes: fixes,
        message: `
Workflow generated with ${fixes.length} automatic fixes applied.

${fixes.map(f => `✓ ${f.fix}`).join('\n')}

${validation.issues.filter(i => i.severity === 'critical').length > 0 ?
  '⚠️ Critical issues remain - please review before executing' :
  '✅ Workflow ready to execute'}
        `
      };
    }

    return {
      workflow: workflow,
      validation: validation,
      message: '✅ Workflow generated and validated. Ready to execute!'
    };
  }

  private async handleYoloMode(
    userMessage: string,
    context: SessionContext
  ): Promise<WorkflowResponse> {
    // Generate AND execute automatically (risky!)

    console.warn('⚠️ YOLO mode: Generating and executing without review');

    const generator = new IterativeWorkflowGenerator();
    const workflow = await generator.generateQuick(userMessage, context);

    // Quick validation only
    const validator = new WorkflowValidator();
    const validation = await validator.validate(workflow, context);

    if (validation.issues.filter(i => i.severity === 'critical').length > 0) {
      // Abort if critical issues
      return {
        workflow: workflow,
        validation: validation,
        executed: false,
        message: '❌ Critical issues detected. Aborting automatic execution. Please review workflow.'
      };
    }

    // Execute immediately
    const executionId = await this.executeWorkflow(workflow);

    return {
      workflow: workflow,
      validation: validation,
      executionId: executionId,
      executed: true,
      message: `🚀 Workflow executing automatically (execution ID: ${executionId})`
    };
  }
}

Deliverable: Workflow modes operational ✅
Timeline: 5 days
Cost: $15K-20K
```

---

#### Week 13: Sub-Agents (Specialized Experts)

**Goal**: Implement specialized sub-agents for tool selection, parameter configuration, validation

```typescript
// File: backend/services/sub-agents/tool-selector.ts

class ToolSelectorAgent {
  /**
   * Specialized sub-agent for tool selection
   * Knowledge: DDA vs DIA, tool compatibility, alternatives
   * Tools: Read tool DB, scientific context metadata
   */

  async selectTools(
    task: string,
    context: WorkflowContext
  ): Promise<Tool[]> {
    const systemPrompt = `
You are a specialized tool selection expert for proteomics analysis.

Your ONLY job is to recommend the best tools for a given task and context.

Context:
- Data Type: ${context.dataType}
- Organism: ${context.organism}
- Analysis Goal: ${context.goal}

Tool Selection Rules:
1. DIA data → DIA-NN, Spectronaut, OpenSWATH (NEVER MaxQuant)
2. DDA data → MaxQuant, MSFragger, MSGF+ (NEVER DIA-NN)
3. TMT/iTRAQ → Tools with isobaric quantification support
4. Phosphoproteomics → Tools with PTM support

Available tools in database: ${this.getRelevantTools(task)}

Return top 3 tool recommendations with reasoning.
    `;

    const response = await this.claudeClient.messages.create({
      model: 'claude-3-5-sonnet-20241022',
      max_tokens: 1000,
      messages: [{
        role: 'user',
        content: `Select best tools for task: ${task}`
      }],
      system: systemPrompt
    });

    return this.parseToolRecommendations(response.content[0].text);
  }

  private getRelevantTools(task: string): Tool[] {
    // Read from tool database with scientific context
    return this.toolDB.search({
      task: task,
      includeScientificContext: true,
      includeAlternatives: true
    });
  }
}

// File: backend/services/sub-agents/parameter-expert.ts

class ParameterExpertAgent {
  /**
   * Specialized sub-agent for parameter configuration
   * Knowledge: Instrument-specific settings, FDR thresholds, charge states
   * Tools: Read tool parameter schemas, validation rules
   */

  async configureParameters(
    tool: Tool,
    context: WorkflowContext
  ): Promise<Parameters> {
    const systemPrompt = `
You are a specialized parameter configuration expert.

Tool: ${tool.name}
Context:
- Instrument: ${context.instrument}
- Data Type: ${context.dataType}
- Expertise Level: ${context.userProfile.expertiseLevel}

Parameter Constraints:
${JSON.stringify(tool.parameters, null, 2)}

For each parameter:
1. Set appropriate default based on instrument
2. Explain why this value is recommended
3. Warn about common mistakes

Return parameters with explanations.
    `;

    const response = await this.claudeClient.messages.create({
      model: 'claude-3-5-sonnet-20241022',
      max_tokens: 1500,
      messages: [{
        role: 'user',
        content: `Configure parameters for ${tool.name}`
      }],
      system: systemPrompt
    });

    return this.parseParameterConfig(response.content[0].text);
  }
}

// File: backend/services/sub-agents/orchestrator.ts

class MainOrchestrator {
  /**
   * Coordinates sub-agents and manages workflow generation
   */

  private toolSelector = new ToolSelectorAgent();
  private parameterExpert = new ParameterExpertAgent();
  private workflowValidator = new WorkflowValidator();

  async generateWorkflow(
    userMessage: string,
    context: SessionContext
  ): Promise<Workflow> {
    // 1. Understand intent
    const intent = await this.analyzeIntent(userMessage);

    // 2. Delegate to tool selector
    console.log('→ Delegating to $tool-selector');
    const tools = await this.toolSelector.selectTools(
      intent.task,
      context
    );

    // 3. Delegate to parameter expert for each tool
    const steps = [];
    for (const tool of tools) {
      console.log(`→ Delegating to $parameter-expert for ${tool.name}`);
      const parameters = await this.parameterExpert.configureParameters(
        tool,
        context
      );

      steps.push({
        tool: tool,
        parameters: parameters
      });
    }

    // 4. Build workflow
    const workflow = new Workflow(steps);

    // 5. Delegate to validator
    console.log('→ Delegating to $workflow-validator');
    const validation = await this.workflowValidator.validate(
      workflow,
      context
    );

    if (!validation.valid) {
      // Auto-fix if possible
      const autoFixer = new WorkflowAutoFixer();
      await autoFixer.autoFix(workflow, validation.issues);
    }

    return workflow;
  }
}

Deliverable: Sub-agents operational ✅
Expected: More focused, expert-level tool selection
Timeline: 5 days
Cost: $20K-30K
```

---

### Phase 4: Use-Case Features (Weeks 14-15)

*(Condensed from original Phase 3, weeks 9-12)*

Parallel development of 4 specialized markets:
- Week 14: Drug Discovery + Synthetic Biology
- Week 15: Agricultural Genomics + Environmental Metagenomics

---

### Phase 5: Production Deployment (Weeks 16-18)

*(Original Phase 4, extended by 2 weeks)*

**Week 16**: Staging deployment + security audit
**Week 17**: Beta testing (50 users, now testing both systems)
**Week 18**: Canary → Full production launch

---

## Updated Architecture Diagram

```
┌────────────────────────────────────────────────────────────────┐
│                    USER INTERFACE LAYER                         │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐         │
│  │   Chat UI    │  │  Workflow    │  │  Validation  │         │
│  │  (Iterative) │  │   Builder    │  │   Report     │         │
│  └──────────────┘  └──────────────┘  └──────────────┘         │
│         ↓                  ↓                  ↓                 │
└────────────────────────────────────────────────────────────────┘
         ↓                  ↓                  ↓
┌────────────────────────────────────────────────────────────────┐
│            PROACTIVE ORCHESTRATION LAYER (NEW!)                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Main Orchestrator                                        │  │
│  │  ├─→ $tool-selector (specialized in tool compatibility)  │  │
│  │  ├─→ $parameter-expert (instrument-specific configs)     │  │
│  │  └─→ $workflow-validator (5-layer validation)            │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Context Management                                       │  │
│  │  - Auto-compress when context > 80%                      │  │
│  │  - User profiles (preferences, corrections)              │  │
│  │  - Session context (decisions, open questions)           │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Multi-Layer Validation (Before Execution)               │  │
│  │  1. Structural validation                                │  │
│  │  2. Tool chain compatibility                             │  │
│  │  3. Parameter validation                                 │  │
│  │  4. Scientific validity (DIA-NN for DIA, not MaxQuant)  │  │
│  │  5. Resource availability                                │  │
│  └──────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────┘
         ↓
┌────────────────────────────────────────────────────────────────┐
│          REACTIVE LEARNING LAYER (ACE System)                   │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  ACE Learning System (After Execution)                   │  │
│  │  ├─→ Reflector (analyzes failures)                       │  │
│  │  ├─→ Curator (updates playbook)                          │  │
│  │  └─→ Playbook DB (learned rules with confidence)         │  │
│  └──────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────┘
         ↓
┌────────────────────────────────────────────────────────────────┐
│              WORKFLOW EXECUTION & MONITORING                    │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  GalaxyStatePoller (Enhanced with ACE Feedback)          │  │
│  │  - Polls execution state every 2s                        │  │
│  │  - Detects failures → Sends to ACE Reflector             │  │
│  │  - Streams to frontend via SSE                           │  │
│  └──────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────┘
```

---

## Knowledge Storage: MD Files + PostgreSQL

**User Profiles** (JSON/MD files):
```
backend/user_profiles/
├── user_123/
│   ├── domain_knowledge.json
│   ├── tool_preferences.json
│   ├── correction_log.json
│   └── research_context.json
```

**Learned Rules** (PostgreSQL):
```sql
-- ACE Playbook (reactive learning)
ace_playbook_rules (
  rule_text, harmful_tools, recommended_tools,
  confidence, helpful_count, harmful_count
)

-- Context summaries (auto-compressed)
session_summaries (
  session_id, summary_text, created_at
)
```

**Why Both?**
- **MD/JSON**: Human-readable, version-controllable, easy to edit
- **PostgreSQL**: Fast querying, confidence scoring, evidence tracking

---

## Updated Success Metrics

### Proactive System (Weeks 1-3)
- **Validation catch rate**: >80% of errors caught before execution
- **User corrections**: <0.5 per workflow (vs 2-3 baseline)
- **Questions asked**: 2-4 per workflow (appropriate amount)
- **Context compression**: Triggered when >80% context used

### Reactive System (Weeks 4-7)
- **Rules learned**: 5-10/month initially, 20-30/month mature
- **Confidence scores**: Average >0.70
- **Rule precision**: >90%
- **False positive rate**: <5%

### Combined System (Weeks 8-18)
- **Workflow success rate**: 80-85% (vs 70% baseline)
  - Proactive contribution: +5-8%
  - Reactive contribution: +5-7%
- **Time to successful workflow**: -30-40%
- **User satisfaction**: NPS >50

---

## Updated Investment Summary

### Development Costs (One-Time)

```yaml
Phase 0: Proactive Orchestration (Weeks 1-3) 🆕
  Context management: $15K-20K
  Iterative generation: $20K-25K
  Multi-layer validation: $20K-30K
  Total Phase 0: $55K-75K

Phase 1: ACE Learning (Weeks 4-7)
  Scientific metadata: $40K-60K
  ACE database + services: $70K-105K
  Auto-update discovery: $30K-45K
  Total Phase 1: $140K-210K

Phase 2: Integration (Weeks 8-11)
  GalaxyAssistant + StatePoller: $50K-70K
  Use-case routing: $25K-35K
  Clinical reporting: $40K-60K
  Total Phase 2: $115K-165K

Phase 3: Workflow Modes + Sub-Agents (Weeks 12-13) 🆕
  Workflow modes: $15K-20K
  Sub-agents: $20K-30K
  Total Phase 3: $35K-50K

Phase 4: Use-Case Features (Weeks 14-15)
  Drug Discovery + Syn Bio: $170K-260K
  Ag Genomics + Environmental: $180K-275K
  Total Phase 4: $350K-535K

Phase 5: Deployment (Weeks 16-18)
  Security audit: $30K-50K
  Beta program: $20K-30K
  Production deployment: $40K-60K
  Total Phase 5: $90K-140K

TOTAL DEVELOPMENT: $785K-1,175K (was $650K-980K)
Additional investment: $135K-195K for proactive features
```

### ROI Impact

**Proactive features pay for themselves**:
- Additional cost: $135K-195K
- Expected improvement: +5-8% success rate → Fewer failed workflows
- Cost savings: $50K-100K/year in reduced support and re-execution
- Payback period: 18-24 months

---

## Critical Comparison: Before vs After

### Original Roadmap (Missing Proactive Features)

❌ No iterative workflow generation
❌ No multi-layer validation before execution
❌ No context compression
❌ No workflow modes (Plan/Auto/YOLO)
❌ No sub-agents
❌ No user profiles with correction logs

**Result**: 75-78% success rate (reactive learning only)

### Revised Roadmap (Proactive + Reactive)

✅ Iterative workflow generation with clarification
✅ Multi-layer validation (5 layers) before execution
✅ Context compression (auto-summarize)
✅ Workflow modes (user control)
✅ Sub-agents (specialized experts)
✅ User profiles with correction logs

**Result**: 80-85% success rate (proactive + reactive)

---

## Implementation Priority

**Must Have (Weeks 1-3)**: Proactive orchestration
- Without this, we're just learning from failures
- User experience is frustrating (fix, fail, fix, fail)
- Claude Code advantage comes from PREVENTION, not just learning

**Should Have (Weeks 4-7)**: ACE reactive learning
- Complements proactive system
- Continuous improvement over time
- Competitive moat (2-3 year lead)

**Nice to Have (Weeks 12-13)**: Sub-agents + modes
- Can be added after MVP
- Enhances but not critical
- Workflow modes especially useful for production users

---

## Next Actions (Revised)

### Week 0 (Immediately):
1. ✅ Review this REVISED roadmap
2. ✅ Approve additional $135K-195K for proactive features
3. ✅ Acknowledge this was a critical gap in original plan
4. ✅ Decide: Start with Week 1 (proactive) or Week 4 (ACE)?

### Recommendation: START WITH WEEK 1-3 (Proactive)
**Rationale**:
- Proactive features provide immediate value
- Prevent mistakes BEFORE they happen (better UX)
- ACE learning is useless if workflows keep failing
- Foundation for everything else

**Alternative**: Parallel tracks (higher risk)
- Track 1: Weeks 1-3 proactive (2 developers)
- Track 2: Weeks 4-7 ACE (2 developers)
- Merge in Week 8

---

## Conclusion

The **original roadmap was incomplete** because it focused only on reactive learning (ACE) and missed the Claude Code-inspired proactive orchestration features that prevent mistakes before execution.

**The revised roadmap integrates BOTH systems**:
1. **Proactive** (Weeks 1-3): Iterative generation, validation, context management
2. **Reactive** (Weeks 4-7): ACE learning from failures
3. **Combined** (Week 8+): Full integration for 80-85% success rate

This creates a **truly self-improving collaborative platform** where:
- Claude prevents mistakes through clarification and validation (proactive)
- Claude learns from remaining mistakes to improve over time (reactive)
- Users feel in control through workflow modes and iterative building
- Context is managed automatically (compression, user profiles)

**Investment**: $785K-1,175K (up from $650K-980K)
**Additional Cost**: $135K-195K for proactive features
**ROI**: Improved success rate pays back in 18-24 months

---

**Document Version**: 2.0 (REVISED)
**Status**: Ready for Executive Review
**Prepared By**: BioMate Platform Architecture Team
**Date**: 2025-10-31
**Recommendation**: **APPROVE REVISED PLAN** - Start with proactive features (Weeks 1-3)
