/**
 * Conversation State Graph
 *
 * Manages progressive state accumulation across conversation turns.
 * Facts are extracted from each user message, accumulated across turns,
 * and gradually mapped to tool-specific parameters as the conversation progresses.
 *
 * Inspired by OpenClaw's pre-compaction memory flush pattern:
 * state is persisted to Postgres every turn to survive context compression.
 */

import { db, ltmSchema } from './db';
import { eq } from 'drizzle-orm';
import { randomUUID } from 'crypto';

// ============================================================================
// Core Types
// ============================================================================

export type ConversationPhase =
  | 'gathering'       // Collecting initial information
  | 'clarifying'      // Asking user to resolve ambiguity
  | 'tool_selection'  // Identifying candidate tools
  | 'parameterizing'  // Mapping facts to tool parameters
  | 'ready'           // All required parameters present
  | 'generated'       // Workflow has been generated
  | 'executing';      // Workflow is running

export type FactCategory =
  | 'sequence'
  | 'gene'
  | 'organism'
  | 'data_type'
  | 'parameter'
  | 'file_reference'
  | 'tool_preference'
  | 'domain'
  | 'analysis_goal'
  | 'other';

export type FactSourceType =
  | 'user_message'
  | 'clarification_response'
  | 'inferred';

export type ClarificationType =
  | 'ambiguous_intent'
  | 'missing_required_param'
  | 'missing_input_data'
  | 'parameter_confirmation'
  | 'tool_selection';

export interface RawFact {
  id: string;
  category: FactCategory;
  value: string;
  source: {
    type: FactSourceType;
    turnIndex: number;
  };
  confidence: number;
  supersededBy?: string;
}

export interface IntentSnapshot {
  type: string;
  confidence: number;
  turnIndex: number;
}

export interface CandidateTool {
  toolId: string;
  toolName: string;
  relevanceScore: number;
  source: 'search' | 'memory' | 'user_specified';
}

export interface ParameterMapping {
  factId: string;
  toolId: string;
  parameterName: string;
  parameterValue: any;
  mappingConfidence: number;
  requiresConfirmation: boolean;
}

export interface ClarificationRequest {
  id: string;
  type: ClarificationType;
  question: string;
  options?: string[];
  status: 'pending' | 'answered' | 'skipped';
  answer?: string;
  turnIndex: number;
}

export interface ReadinessAssessment {
  score: number;
  missingRequired: string[];
  missingOptional: string[];
}

export interface TaskArc {
  id: string;
  intentType: string;
  subQuery: string;
  phase: ConversationPhase;
  facts: RawFact[];
  readiness: ReadinessAssessment;
  status: 'pending' | 'in_progress' | 'completed' | 'failed';
  resultSummary?: string;
  dependsOn: string[];
  actions?: import('./galaxy-assistant').ActionCategories;
}

export interface DoomLoopDetection {
  detected: boolean;
  intentType?: string;
  occurrences?: number;
  suggestion?: string;
}

/**
 * Records one step in a multi-workflow pipeline chain.
 * Persisted inside ConversationState → PostgreSQL so the chain survives
 * context compression and browser refresh.
 */
export interface WorkflowStepRecord {
  stepIndex: number;
  workflowId: string;       // DB workflows.id (stringified)
  workflowName: string;     // e.g. "nf-core/rnaseq"
  domain: string;
  inputTypes: string[];     // from DB workflows.input_types
  outputTypes: string[];    // from DB workflows.output_types
  runId?: string;           // set once Nextflow job is launched
  status: 'planned' | 'running' | 'completed' | 'failed';
  compatibilityWarnings: string[];  // populated by checkStepCompatibility
  turnIndex: number;        // which conversation turn added this step
}

export interface PipelineCompatibilityResult {
  compatible: boolean;
  warnings: string[];
  suggestions: string[];
}

/**
 * Check whether the output types of step N satisfy the input types of step N+1.
 * Uses semantic type matching — e.g. "bam" satisfies "input_bam", "bam_file".
 */
export function checkStepCompatibility(
  prevOutputTypes: string[],
  nextInputTypes: string[],
  prevWorkflowName = '',
  nextWorkflowName = '',
): PipelineCompatibilityResult {
  if (!nextInputTypes.length || !prevOutputTypes.length) {
    return { compatible: true, warnings: [], suggestions: [] };
  }

  // Semantic type aliases — a key satisfies any value in the list
  const TYPE_ALIASES: Record<string, string[]> = {
    bam:          ['bam', 'input_bam', 'alignments', 'reads_bam', 'input'],
    vcf:          ['vcf', 'input_vcf', 'variants', 'variant_file'],
    fastq:        ['fastq', 'reads', 'input', 'samplesheet'],
    counts_matrix:['counts_matrix', 'counts', 'matrix', 'input', 'samplesheet'],
    tpm_matrix:   ['tpm_matrix', 'tpm', 'expression_matrix', 'counts_matrix'],
    bed_peaks:    ['bed_peaks', 'peaks', 'bed', 'input'],
    fasta:        ['fasta', 'genome', 'reference', 'input'],
    fasta_assembly:['fasta_assembly', 'fasta', 'assembly', 'input'],
    tsv_taxonomy: ['tsv_taxonomy', 'taxonomy', 'tsv', 'input'],
    h5ad:         ['h5ad', 'anndata', 'input'],
    csv:          ['csv', 'samplesheet', 'input'],
    tsv_proteins: ['tsv_proteins', 'protein_groups', 'input'],
  };

  const satisfies = (outType: string, inType: string): boolean => {
    if (outType === inType) return true;
    const aliases = TYPE_ALIASES[outType] ?? [outType];
    return aliases.some(a => a === inType || inType.includes(a) || a.includes(inType));
  };

  const unmatched = nextInputTypes.filter(
    inType => !prevOutputTypes.some(outType => satisfies(outType, inType))
  );

  if (unmatched.length === 0) {
    return { compatible: true, warnings: [], suggestions: [] };
  }

  const warnings = [
    `${prevWorkflowName || 'Previous step'} produces [${prevOutputTypes.join(', ')}] ` +
    `but ${nextWorkflowName || 'next step'} requires [${unmatched.join(', ')}].`,
  ];
  const suggestions = [
    `Consider adding an intermediate conversion step, or verify that the output ` +
    `directory from ${prevWorkflowName} contains the required input files.`,
  ];
  return { compatible: false, warnings, suggestions };
}

export interface IntentHistorySummary {
  [intentType: string]: number;
}

export interface ConversationState {
  sessionId: string;
  userId?: string;
  projectId?: string;
  currentTurn: number;
  phase: ConversationPhase;

  // Accumulated facts from all turns
  facts: RawFact[];

  // Intent evolution across turns
  intent: {
    primaryType: string;
    confidence: number;
    history: IntentSnapshot[];
    /** Summarized counts of older intents (after compaction) */
    historySummary?: IntentHistorySummary;
  };

  // Candidate and selected tools
  candidateTools: CandidateTool[];
  selectedTool?: {
    toolId: string;
    confirmedByUser: boolean;
  };

  // Parameter mappings (populated once tools are identified)
  parameterMappings: ParameterMapping[];

  // Clarification queue
  pendingClarifications: ClarificationRequest[];

  // Readiness assessment
  readiness: ReadinessAssessment;

  // Per-intent task arcs (populated for multi-intent messages)
  taskArcs?: TaskArc[];
  activeArcId?: string;

  // Multi-workflow pipeline chain — persisted so output→input wiring survives
  // context compression and browser refresh (stored in PostgreSQL via saveState)
  workflowSteps: WorkflowStepRecord[];

  // Timestamp
  updatedAt: string;
}

// ============================================================================
// Factory
// ============================================================================

export function createEmptyState(sessionId: string, userId?: string, projectId?: string): ConversationState {
  return {
    sessionId,
    userId,
    projectId,
    currentTurn: 0,
    phase: 'gathering',
    facts: [],
    intent: {
      primaryType: 'general_question',
      confidence: 0,
      history: [],
    },
    candidateTools: [],
    parameterMappings: [],
    pendingClarifications: [],
    readiness: {
      score: 0,
      missingRequired: [],
      missingOptional: [],
    },
    workflowSteps: [],
    updatedAt: new Date().toISOString(),
  };
}

// ============================================================================
// State Manager
// ============================================================================

export class ConversationStateManager {

  /**
   * Load conversation state from the sessions table.
   * Returns empty state if none exists.
   */
  async loadState(sessionId: string): Promise<ConversationState> {
    try {
      const result = await db
        .select({ conversationState: ltmSchema.sessions.conversationState })
        .from(ltmSchema.sessions)
        .where(eq(ltmSchema.sessions.id, sessionId))
        .limit(1);

      if (result.length > 0 && result[0].conversationState) {
        return result[0].conversationState as unknown as ConversationState;
      }
    } catch (error) {
      console.warn('[ConversationState] Failed to load state, using empty:', error);
    }

    return createEmptyState(sessionId);
  }

  /**
   * Persist conversation state to the sessions table (pre-compaction flush).
   * Called after every turn to ensure state survives context compression.
   */
  async saveState(state: ConversationState): Promise<void> {
    state.updatedAt = new Date().toISOString();
    try {
      await db
        .update(ltmSchema.sessions)
        .set({ conversationState: state as any })
        .where(eq(ltmSchema.sessions.id, state.sessionId));
    } catch (error) {
      console.warn('[ConversationState] Failed to save state:', error);
    }
  }

  /**
   * Add new facts to the state, applying LLM-determined supersession.
   *
   * The LLM decides supersession, not hardcoded category rules. When the LLM
   * sees existing facts and determines a new fact replaces an old one
   * (e.g., user corrects "mouse" to "human"), it sets `supersedes` on the
   * new fact pointing to the old fact's ID. This method applies those decisions.
   */
  addFacts(state: ConversationState, newFacts: RawFact[]): void {
    const activeFacts = this.getActiveFacts(state);

    for (const fact of newFacts) {
      // If the LLM indicated this fact supersedes an existing one, mark it
      if ((fact as any).supersedes) {
        const oldFact = state.facts.find(f => f.id === (fact as any).supersedes && !f.supersededBy);
        if (oldFact) {
          oldFact.supersededBy = fact.id;
        }
      }

      // Skip duplicate: same category + same value (case-insensitive) already active
      const isDuplicate = activeFacts.some(
        existing => existing.category === fact.category &&
          existing.value.toLowerCase() === fact.value.toLowerCase()
      );
      if (isDuplicate) {
        continue;
      }

      state.facts.push(fact);
      // Update active list so subsequent facts in this batch can be checked
      activeFacts.push(fact);
    }
  }

  /**
   * Update intent, preserving history for stability analysis.
   * Recent intents are weighted higher than older ones.
   */
  updateIntent(
    state: ConversationState,
    newType: string,
    newConfidence: number,
  ): void {
    // Record in history
    state.intent.history.push({
      type: newType,
      confidence: newConfidence,
      turnIndex: state.currentTurn,
    });

    // Intent stability: to override the existing intent, the new classification
    // must have HIGHER confidence than the existing one. This prevents follow-up
    // fragments like "from human samples" (low confidence) from flipping a clear
    // "workflow_generation" intent (high confidence).
    const isDifferent = newType !== state.intent.primaryType;
    const hasHistory = state.intent.history.length > 1;

    if (isDifferent && hasHistory && newConfidence <= state.intent.confidence) {
      // New intent has equal or lower confidence — keep existing
      return;
    }

    state.intent.primaryType = newType;
    state.intent.confidence = newConfidence;
  }

  /**
   * Check if the user's message answers a pending clarification.
   * Transitions phase out of 'clarifying' when no more pending clarifications remain.
   */
  resolveClarifications(state: ConversationState, message: string): ClarificationRequest | undefined {
    const pending = state.pendingClarifications.find(c => c.status === 'pending');
    if (!pending) return undefined;

    // Mark as answered
    pending.status = 'answered';
    pending.answer = message;

    // If no more pending clarifications, transition out of clarifying phase
    const stillPending = state.pendingClarifications.some(c => c.status === 'pending');
    if (!stillPending && state.phase === 'clarifying') {
      state.phase = 'gathering';
    }

    return pending;
  }

  /**
   * Create a clarification request and add it to the queue.
   */
  addClarification(
    state: ConversationState,
    type: ClarificationType,
    question: string,
    options?: string[],
  ): ClarificationRequest {
    const clarification: ClarificationRequest = {
      id: randomUUID(),
      type,
      question,
      options,
      status: 'pending',
      turnIndex: state.currentTurn,
    };

    state.pendingClarifications.push(clarification);
    state.phase = 'clarifying';

    return clarification;
  }

  /**
   * Get active (non-superseded) facts.
   */
  getActiveFacts(state: ConversationState): RawFact[] {
    return state.facts.filter(f => !f.supersededBy);
  }

  /**
   * Get active facts by category.
   */
  getFactsByCategory(state: ConversationState, category: FactCategory): RawFact[] {
    return this.getActiveFacts(state).filter(f => f.category === category);
  }

  /**
   * Update parameter mappings based on current facts and selected tools.
   */
  updateParameterMappings(state: ConversationState, mappings: ParameterMapping[]): void {
    state.parameterMappings = mappings;
  }

  /**
   * Evaluate readiness: are we ready to generate a workflow?
   */
  evaluateReadiness(state: ConversationState): void {
    const activeFacts = this.getActiveFacts(state);
    const hasPendingClarifications = state.pendingClarifications.some(c => c.status === 'pending');

    // Can't be ready if we're still clarifying
    if (hasPendingClarifications) {
      state.readiness = { score: 0, missingRequired: ['pending_clarification'], missingOptional: [] };
      return;
    }

    let score = 0;
    const missingRequired: string[] = [];
    const missingOptional: string[] = [];

    // Intent must be clear
    if (state.intent.primaryType !== 'general_question' && state.intent.confidence > 0.5) {
      score += 0.3;
    } else {
      missingRequired.push('clear_intent');
    }

    // Check if the current intent needs workflow generation (via action flags or known type)
    const needsWorkflow = state.intent.primaryType === 'workflow_generation' ||
      state.intent.primaryType === 'workflow_modification' ||
      state.intent.primaryType === 'data_format_conversion' ||
      state.intent.primaryType === 'visualization' ||
      state.intent.primaryType === 'multi_step_procedure' ||
      state.intent.primaryType === 'external_db_retrieval';

    if (needsWorkflow) {
      const hasRelevantData = activeFacts.some(f =>
        ['sequence', 'gene', 'data_type', 'file_reference', 'analysis_goal'].includes(f.category)
      );
      if (hasRelevantData) {
        score += 0.3;
      } else {
        missingOptional.push('input_data_or_parameters');
      }

      // Tool selection boosts readiness
      if (state.candidateTools.length > 0) {
        score += 0.2;
      }

      // Parameter mappings boost readiness
      if (state.parameterMappings.length > 0) {
        score += 0.2;
      } else {
        missingOptional.push('parameter_mappings');
      }
    } else {
      // For non-workflow intents, intent clarity is sufficient
      score += 0.4;
    }

    state.readiness = { score, missingRequired, missingOptional };

    // Update phase based on readiness
    if (score >= 0.8 && state.phase !== 'generated' && state.phase !== 'executing') {
      state.phase = 'ready';
    } else if (state.candidateTools.length > 0 && state.phase === 'gathering') {
      state.phase = 'tool_selection';
    } else if (state.parameterMappings.length > 0 && state.phase === 'tool_selection') {
      state.phase = 'parameterizing';
    }
  }

  /**
   * Persist facts from the current turn to the conversation_state_facts table
   * for cross-session analysis and procedure learning.
   * Only persists active facts added during the current turn to avoid duplicates.
   */
  async persistFacts(state: ConversationState): Promise<void> {
    const currentTurnFacts = this.getActiveFacts(state).filter(
      f => f.source.turnIndex === state.currentTurn
    );
    if (currentTurnFacts.length === 0) return;

    try {
      await db.insert(ltmSchema.conversationStateFacts).values(
        currentTurnFacts.map(fact => ({
          sessionId: state.sessionId,
          category: fact.category,
          value: fact.value,
          confidence: fact.confidence,
          turnIndex: fact.source.turnIndex,
          sourceType: fact.source.type,
        }))
      );
    } catch (error) {
      console.warn('[ConversationState] Failed to persist facts:', error);
    }
  }

  /**
   * Create a helper to generate a new fact.
   */
  createFact(
    category: FactCategory,
    value: string,
    turnIndex: number,
    sourceType: FactSourceType = 'user_message',
    confidence: number = 0.8,
  ): RawFact {
    return {
      id: randomUUID(),
      category,
      value,
      source: { type: sourceType, turnIndex },
      confidence,
    };
  }

  // ============================================================================
  // Long-Context Fact Consolidation (Phase 5)
  // ============================================================================

  /**
   * Consolidate facts to prevent unbounded growth in long conversations.
   *
   * Strategy (inspired by ACE Framework's delta-based updates):
   * 1. Keep all facts from the last `recentTurns` turns (recency)
   * 2. For older facts: keep highest-confidence per category
   * 3. Remove duplicates and low-confidence (<0.5) old facts
   * 4. Cap at `maxFacts`
   */
  consolidateFacts(state: ConversationState, maxFacts: number = 50, recentTurns: number = 5): void {
    const activeFacts = this.getActiveFacts(state);
    if (activeFacts.length <= maxFacts) return;

    const recentThreshold = state.currentTurn - recentTurns;

    // Partition into recent and old
    const recentFacts = activeFacts.filter(f => f.source.turnIndex >= recentThreshold);
    const oldFacts = activeFacts.filter(f => f.source.turnIndex < recentThreshold);

    // For old facts: keep highest-confidence per category, drop low-confidence
    const bestByCategory = new Map<string, RawFact>();
    for (const fact of oldFacts) {
      if (fact.confidence < 0.5) continue; // Drop low-confidence old facts
      const existing = bestByCategory.get(fact.category);
      if (!existing || fact.confidence > existing.confidence) {
        bestByCategory.set(fact.category, fact);
      }
    }

    const keptOldFacts = Array.from(bestByCategory.values());

    // Merge: recent facts + best-per-category old facts
    const consolidated = [...recentFacts, ...keptOldFacts];

    // If still over limit, drop lowest-confidence facts (not from recent turns)
    if (consolidated.length > maxFacts) {
      consolidated.sort((a, b) => {
        // Recent facts always come first
        const aRecent = a.source.turnIndex >= recentThreshold ? 1 : 0;
        const bRecent = b.source.turnIndex >= recentThreshold ? 1 : 0;
        if (aRecent !== bRecent) return bRecent - aRecent;
        return b.confidence - a.confidence;
      });
      consolidated.length = maxFacts;
    }

    // Mark facts not in consolidated as superseded
    const keptIds = new Set(consolidated.map(f => f.id));
    for (const fact of state.facts) {
      if (!fact.supersededBy && !keptIds.has(fact.id)) {
        fact.supersededBy = 'consolidated';
      }
    }

    console.log(`[ConversationState] Consolidated facts: ${activeFacts.length} → ${consolidated.length}`);
  }

  /**
   * Compact intent history to prevent unbounded growth.
   *
   * Strategy:
   * 1. Keep the last `maxHistory` entries
   * 2. Summarize older entries as aggregate counts
   */
  compactIntentHistory(state: ConversationState, maxHistory: number = 20): void {
    if (state.intent.history.length <= maxHistory) return;

    // Summarize older entries
    const toSummarize = state.intent.history.slice(0, state.intent.history.length - maxHistory);
    const summary: IntentHistorySummary = state.intent.historySummary || {};

    for (const entry of toSummarize) {
      summary[entry.type] = (summary[entry.type] || 0) + 1;
    }

    // Keep only recent entries
    state.intent.history = state.intent.history.slice(-maxHistory);
    state.intent.historySummary = summary;

    console.log(`[ConversationState] Compacted intent history: kept ${maxHistory}, summarized ${toSummarize.length}`);
  }

  /**
   * Detect doom loops: same intent type repeated with no state progress.
   *
   * Pattern from OpenCode's DOOM_LOOP_THRESHOLD = 3:
   * If the same intent type appears 3+ times in the last 6 turns
   * with no new facts or phase progression, suggest clarification.
   */
  detectDoomLoop(state: ConversationState, threshold: number = 3, windowSize: number = 6): DoomLoopDetection {
    const history = state.intent.history;
    if (history.length < threshold) {
      return { detected: false };
    }

    // Look at the last `windowSize` intents
    const recentHistory = history.slice(-windowSize);

    // Count occurrences of each intent type
    const counts = new Map<string, number>();
    for (const entry of recentHistory) {
      counts.set(entry.type, (counts.get(entry.type) || 0) + 1);
    }

    // Find any intent type that appears >= threshold times
    for (const [intentType, count] of counts) {
      if (count >= threshold) {
        // Check if there's been state progress (new facts in this window)
        const windowStart = state.currentTurn - windowSize;
        const factsInWindow = this.getActiveFacts(state).filter(
          f => f.source.turnIndex >= windowStart
        );

        // If few or no new facts were added, it's a doom loop
        if (factsInWindow.length <= 1) {
          return {
            detected: true,
            intentType,
            occurrences: count,
            suggestion: this.getDoomLoopSuggestion(intentType),
          };
        }
      }
    }

    return { detected: false };
  }

  /**
   * Generate a helpful suggestion based on the doom loop intent type.
   */
  private getDoomLoopSuggestion(intentType: string): string {
    const suggestions: Record<string, string> = {
      'workflow_generation': 'It seems like you\'re trying to generate a workflow but something might be missing. Could you provide more specific details about your input data, organism, or analysis goal?',
      'research_question': 'I notice we\'ve been back and forth on research questions. Could you clarify the specific topic, time period, or type of evidence you\'re looking for?',
      'general_question': 'It seems like we might be going in circles. Could you rephrase your question or provide more context about what you\'re trying to achieve?',
      'troubleshooting': 'We seem to be stuck on this issue. Could you share the exact error message, the tool/step that failed, and what you\'ve already tried?',
      'parameter_optimization': 'We\'ve been back and forth on parameters. Could you specify which metric you want to optimize (accuracy, speed, sensitivity) and your data characteristics?',
      'experiment_design': 'To help design your experiment, could you clarify your hypothesis, the number of samples/replicates, and any constraints (budget, time, equipment)?',
    };
    const label = intentType.replace(/_/g, ' ');
    return suggestions[intentType] || `We seem to be repeating similar ${label} requests. Could you provide more specific details or try a different approach?`;
  }

  // ============================================================================
  // Task Arc Management (Phase 4)
  // ============================================================================

  /**
   * Create task arcs from decomposed intents.
   */
  createTaskArcs(
    state: ConversationState,
    intents: Array<{ id: string; type: string; subQuery: string; facts: any[]; dependsOn: string[]; actions?: import('./galaxy-assistant').ActionCategories }>
  ): void {
    state.taskArcs = intents.map(intent => ({
      id: intent.id,
      intentType: intent.type,
      subQuery: intent.subQuery,
      phase: 'gathering' as ConversationPhase,
      facts: [],
      readiness: { score: 0, missingRequired: [], missingOptional: [] },
      status: 'in_progress' as const,
      dependsOn: intent.dependsOn,
      actions: intent.actions,
    }));
  }

  /**
   * Update a specific task arc's status and result.
   */
  updateTaskArc(
    state: ConversationState,
    arcId: string,
    update: Partial<Pick<TaskArc, 'status' | 'phase' | 'resultSummary'>>
  ): void {
    const arc = state.taskArcs?.find(a => a.id === arcId);
    if (!arc) return;
    Object.assign(arc, update);
  }

  /**
   * Find the most relevant task arc for a follow-up message.
   * Matches based on keyword overlap between the message and arc subQueries/facts.
   */
  findRelevantArc(state: ConversationState, message: string): TaskArc | undefined {
    if (!state.taskArcs || state.taskArcs.length === 0) return undefined;

    const messageLower = message.toLowerCase();
    let bestArc: TaskArc | undefined;
    let bestScore = 0;

    for (const arc of state.taskArcs) {
      if (arc.status === 'completed' || arc.status === 'failed') continue;

      let score = 0;
      // Check subQuery word overlap
      const subQueryWords = arc.subQuery.toLowerCase().split(/\s+/);
      for (const word of subQueryWords) {
        if (word.length > 3 && messageLower.includes(word)) {
          score += 1;
        }
      }
      // Check fact value overlap
      for (const fact of arc.facts) {
        if (messageLower.includes(fact.value.toLowerCase())) {
          score += 2;
        }
      }

      if (score > bestScore) {
        bestScore = score;
        bestArc = arc;
      }
    }

    return bestArc;
  }

  // ── Pipeline workflow step tracking ──────────────────────────────────────

  /**
   * Add a planned workflow step to the chain. Automatically checks compatibility
   * with the previous step's output types and stores warnings in the record.
   */
  addWorkflowStep(
    state: ConversationState,
    step: Omit<WorkflowStepRecord, 'stepIndex' | 'compatibilityWarnings'>,
  ): WorkflowStepRecord {
    if (!state.workflowSteps) state.workflowSteps = [];
    const stepIndex = state.workflowSteps.length;

    let compatibilityWarnings: string[] = [];
    if (stepIndex > 0) {
      const prev = state.workflowSteps[stepIndex - 1];
      const result = checkStepCompatibility(
        prev.outputTypes,
        step.inputTypes,
        prev.workflowName,
        step.workflowName,
      );
      if (!result.compatible) {
        compatibilityWarnings = [...result.warnings, ...result.suggestions];
      }
    }

    const record: WorkflowStepRecord = { ...step, stepIndex, compatibilityWarnings };
    state.workflowSteps.push(record);
    return record;
  }

  /**
   * Update a workflow step's status and runId once it's launched or completes.
   */
  updateWorkflowStep(
    state: ConversationState,
    stepIndex: number,
    update: Partial<Pick<WorkflowStepRecord, 'status' | 'runId' | 'outputTypes'>>,
  ): void {
    if (!state.workflowSteps) return;
    const step = state.workflowSteps[stepIndex];
    if (!step) return;
    Object.assign(step, update);

    // If outputTypes were updated after run completion, re-check compatibility
    // for the NEXT step and update its warnings
    if (update.outputTypes && stepIndex + 1 < state.workflowSteps.length) {
      const next = state.workflowSteps[stepIndex + 1];
      const result = checkStepCompatibility(
        update.outputTypes,
        next.inputTypes,
        step.workflowName,
        next.workflowName,
      );
      next.compatibilityWarnings = result.compatible
        ? []
        : [...result.warnings, ...result.suggestions];
    }
  }

  /**
   * Get all compatibility warnings across the current pipeline chain.
   */
  getPipelineWarnings(state: ConversationState): string[] {
    if (!state.workflowSteps) return [];
    return state.workflowSteps.flatMap(s => s.compatibilityWarnings);
  }

  /**
   * Clear the workflow step chain (e.g. when user starts a new pipeline).
   */
  clearWorkflowSteps(state: ConversationState): void {
    state.workflowSteps = [];
  }
}

// Singleton instance
export const conversationStateManager = new ConversationStateManager();

