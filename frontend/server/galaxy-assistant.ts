/**
 * Galaxy Assistant Service
 *
 * Hybrid intelligence system combining:
 * - Claude Sonnet 4.5 for natural language understanding (with prompt caching)
 * - Galaxy Tool Search (2,177 indexed tools)
 * - BioMNI Dataset RAG (100+ GB data lake)
 * - Galaxy Workflow Generator (LLM-based with tool validation)
 *
 * Architecture:
 * User Query → NLU (Claude) → Tool Search + Dataset RAG → Workflow Generation
 */

import Anthropic from '@anthropic-ai/sdk';
import { GalaxyAPIProxy } from './galaxy-api-proxy';
import { userPatternsService, type UserContext } from './user-patterns-service';
import { thinkingDetector, type ThinkingDetectionResult } from './thinking-detector';
import type {
  GalaxyTool,
  BioMNIDataset,
  WorkflowGenerationRequest,
  WorkflowGenerationResponse,
} from '../shared/galaxy-types';

/**
 * Model configuration for different AI tasks
 *
 * Recommended configurations:
 * - Intent analysis: Fast model (haiku) - simple classification task
 * - Tool ranking: Medium model (haiku/sonnet) - needs domain knowledge
 * - Response generation: Best model (sonnet) - user-facing, quality matters
 *
 * When to use Thinking Mode:
 * -------------------------
 * RECOMMENDED for:
 * - Complex multi-step workflow planning (e.g., "design a metagenomics pipeline")
 * - Comparative analysis requiring trade-off evaluation (e.g., "BWA vs Bowtie2")
 * - Technical explanations requiring accuracy (e.g., statistical interpretation)
 * - Troubleshooting complex issues (e.g., "why did my alignment fail")
 *
 * NOT NECESSARY for:
 * - Simple greetings and general questions ("Hello", "What can you do?")
 * - Intent classification (simple JSON classification task)
 * - Tool ranking (structured output task)
 * - Short factual responses (e.g., "What format does BWA accept?")
 *
 * Performance impact:
 * - Thinking adds ~2-5 seconds latency
 * - Thinking uses additional tokens (budget_tokens parameter)
 * - Quality improvement is most noticeable for complex tasks
 */
export interface ModelConfig {
  /** Model for intent classification (default: claude-sonnet-4-5, can use haiku for speed) */
  intentModel: string;
  /** Model for tool ranking (default: claude-sonnet-4-5, can use haiku for speed) */
  toolRankingModel: string;
  /** Model for response generation (default: claude-sonnet-4-5) */
  responseModel: string;
  /** Whether to enable thinking mode for response generation */
  enableThinking: boolean;
  /** Token budget for thinking mode (default: 2000) */
  thinkingBudget: number;
}

/**
 * Determine if thinking mode should be enabled based on the query complexity.
 * Can be used for adaptive thinking mode (enable only when beneficial).
 */
export function shouldEnableThinking(message: string, intent: string): boolean {
  // Complex workflow requests benefit from thinking
  const complexPatterns = [
    /design\s+(a\s+)?.*pipeline/i,
    /create\s+(a\s+)?.*workflow/i,
    /compare\s+.*\s+(vs|versus|or)\s+/i,
    /trade-?offs?\s+(of|between)/i,
    /explain\s+(the\s+)?(difference|comparison)/i,
    /troubleshoot/i,
    /debug/i,
    /why\s+(did|does|is)/i,
    /interpret\s+(my|the|these)/i,
    /what\s+(are\s+)?the\s+(best|optimal|recommended)/i,
  ];

  // Simple patterns that don't need thinking
  const simplePatterns = [
    /^(hello|hi|hey)/i,
    /what\s+(can\s+)?you\s+do/i,
    /^(thanks|thank\s+you)/i,
    /what\s+(is|are)\s+\w+$/i, // Simple definitional questions
  ];

  // Check for simple patterns first
  if (simplePatterns.some(p => p.test(message))) {
    return false;
  }

  // Check for complex patterns
  if (complexPatterns.some(p => p.test(message))) {
    return true;
  }

  // Default: enable for workflow generation, disable otherwise
  return intent === 'workflow_generation';
}

export const DEFAULT_MODEL_CONFIG: ModelConfig = {
  intentModel: 'claude-haiku-4-5',       // Haiku: same 94% accuracy, 2x faster, 11.5x cheaper
  toolRankingModel: 'claude-haiku-4-5',  // Haiku: 1.4x faster for ranking
  responseModel: 'claude-sonnet-4-6',    // Default to Sonnet 4.6
  enableThinking: false,                 // Disable thinking by default for lower latency
  thinkingBudget: 2000,
};

export interface GalaxyAssistantOptions {
  anthropicApiKey: string;
  galaxyAPIProxy: GalaxyAPIProxy;
  /** Model configuration - uses defaults if not provided */
  modelConfig?: Partial<ModelConfig>;
}

export interface ChatContext {
  previousMessages?: Array<{ role: 'user' | 'assistant'; content: string }>;
  currentWorkflow?: any;
  selectedDatasets?: string[];
  userId?: number; // For fetching user patterns
  sessionId?: string;
  enableThinking?: boolean;
  /** Accumulated facts from prior turns, passed so the LLM can decide supersession */
  accumulatedFacts?: Array<{ id: string; category: string; value: string }>;
  /** Current conversation turn number */
  turnIndex?: number;
}

export interface ToolRecommendation {
  tool: GalaxyTool;
  relevanceScore: number;
  reasoning: string;
}

export interface DatasetRecommendation {
  dataset: BioMNIDataset;
  relevanceScore: number;
  reasoning: string;
}

export interface WorkflowSuggestion {
  shouldGenerate: boolean;
  userIntent: string;
  confidence: number;
  reasoning: string;
}

export interface ExtractedFact {
  id: string;
  category: 'sequence' | 'gene' | 'organism' | 'data_type' | 'parameter' | 'file_reference' | 'tool_preference' | 'domain' | 'analysis_goal' | 'other';
  value: string;
  source: { type: 'user_message' | 'clarification_response' | 'inferred'; turnIndex: number };
  confidence: number;
  /** ID of an existing fact that this new fact replaces (LLM-determined) */
  supersedes?: string;
  supersededBy?: string;
}

// ============================================================================
// Multi-Intent Decomposition Types
// ============================================================================

export type IntentType =
  | 'workflow_generation'
  | 'research_question'
  | 'tool_search'
  | 'result_comparison'
  | 'benchmark_query'
  | 'dataset_inquiry'
  | 'general_question'
  | 'workflow_modification';

export interface ActionCategories {
  needsToolSearch: boolean;
  needsWorkflowGeneration: boolean;
  needsWorkflowModification: boolean;
  needsResearchAgent: boolean;
  needsBenchmarkAgent: boolean;
  needsDatasetAccess: boolean;
  needsLLMReasoning: boolean;
}

/**
 * Infer action categories from a type string. Known types get established
 * mappings; unknown types default to LLM reasoning only.
 */
export function inferActionsFromType(type: string): ActionCategories {
  const defaults: Record<string, Partial<ActionCategories>> = {
    'workflow_generation': { needsToolSearch: true, needsWorkflowGeneration: true, needsLLMReasoning: true },
    'research_question': { needsResearchAgent: true, needsLLMReasoning: true },
    'result_comparison': { needsToolSearch: true, needsBenchmarkAgent: true, needsLLMReasoning: true },
    'benchmark_query': { needsBenchmarkAgent: true, needsLLMReasoning: true },
    'tool_search': { needsToolSearch: true, needsLLMReasoning: true },
    'dataset_inquiry': { needsDatasetAccess: true, needsLLMReasoning: true },
    'general_question': { needsLLMReasoning: true },
    'workflow_modification': { needsToolSearch: true, needsWorkflowModification: true, needsLLMReasoning: true },
    // Novel information need types from flexible intent brainstorm
    'troubleshooting': { needsResearchAgent: true, needsToolSearch: true, needsLLMReasoning: true },
    'experiment_design': { needsResearchAgent: true, needsLLMReasoning: true },
    'data_interpretation': { needsResearchAgent: true, needsLLMReasoning: true },
    'protocol_guidance': { needsResearchAgent: true, needsLLMReasoning: true },
    'parameter_optimization': { needsBenchmarkAgent: true, needsResearchAgent: true, needsToolSearch: true, needsLLMReasoning: true },
    'data_format_conversion': { needsToolSearch: true, needsWorkflowGeneration: true, needsLLMReasoning: true },
    'external_db_retrieval': { needsToolSearch: true, needsWorkflowGeneration: true, needsLLMReasoning: true },
    'teaching_explanation': { needsLLMReasoning: true },
    'methods_writing': { needsResearchAgent: true, needsLLMReasoning: true },
    'visualization': { needsToolSearch: true, needsWorkflowGeneration: true, needsLLMReasoning: true },
    'comparative_methodology': { needsResearchAgent: true, needsBenchmarkAgent: true, needsLLMReasoning: true },
    'regulatory_compliance': { needsResearchAgent: true, needsLLMReasoning: true },
    'cost_estimation': { needsBenchmarkAgent: true, needsLLMReasoning: true },
    'multi_step_procedure': { needsToolSearch: true, needsWorkflowGeneration: true, needsLLMReasoning: true },
  };
  return {
    needsToolSearch: false,
    needsWorkflowGeneration: false,
    needsWorkflowModification: false,
    needsResearchAgent: false,
    needsBenchmarkAgent: false,
    needsDatasetAccess: false,
    needsLLMReasoning: true,
    ...defaults[type],
  };
}

export interface DecomposedIntent {
  id: string;
  type: string; // Open-vocabulary: 'workflow_generation', 'troubleshooting', etc.
  subQuery: string;
  keywords: string[];
  inlineParameters: Record<string, string>;
  needsToolSearch: boolean;
  needsDatasets: boolean;
  confidence: number;
  facts: Array<{ category: string; value: string; confidence: number; supersedes?: string }>;
  dependsOn: string[];
  actions: ActionCategories; // Which backend agents to invoke
}

export interface IntentDecomposition {
  intents: DecomposedIntent[];
  isMultiIntent: boolean;
  primaryIntent: DecomposedIntent;
}

export interface SubIntentResult {
  intentId: string;
  intentType: string;
  subQuery: string;
  message?: string;
  recommendedTools?: ToolRecommendation[];
  generatedWorkflow?: any;
  researchResponse?: any;
  benchmarkEvidence?: any;
  status: 'success' | 'error';
  error?: string;
}

export interface GalaxyAssistantResponse {
  // Natural language response
  message: string;

  // Classified intent type (aligned with backend ai_assistant.py)
  intentType?: string;
  intentConfidence?: number;

  // Extracted inline parameters from user message
  inlineParameters?: Record<string, string>;

  // Extracted typed facts from user message (for ConversationState)
  extractedFacts?: ExtractedFact[];

  // Tool recommendations
  recommendedTools?: ToolRecommendation[];

  // Dataset recommendations
  recommendedDatasets?: DatasetRecommendation[];

  // Workflow suggestion
  workflowSuggestion?: WorkflowSuggestion;

  // Generated workflow (if requested)
  generatedWorkflow?: any;

  // Additional parallel workflows for multi-intent queries (e.g. "RNA-seq AND ATAC-seq")
  additionalWorkflows?: any[];

  // Suggested follow-up questions
  suggestions: string[];

  // Thinking mode support
  thinking_content?: string;
  thinking_level?: 'none' | 'brief' | 'detailed';
  truncated?: boolean;

  // Multi-intent results (populated when message contains multiple distinct tasks)
  subIntentResults?: SubIntentResult[];
  isMultiIntent?: boolean;

  // Research and benchmark results (populated for research/benchmark intents)
  researchResponse?: any;
  benchmarkEvidence?: any;

  // Metadata
  sources: {
    toolSearchUsed: boolean;
    datasetRAGUsed: boolean;
    workflowGenerated: boolean;
    thinkingUsed: boolean;
    researchAgentUsed?: boolean;
    benchmarkAgentUsed?: boolean;
  };
}

export class GalaxyAssistant {
  private claude: Anthropic;
  private galaxyAPI: GalaxyAPIProxy;
  private modelConfig: ModelConfig;

  constructor(options: GalaxyAssistantOptions) {
    this.claude = new Anthropic({ apiKey: options.anthropicApiKey });
    this.galaxyAPI = options.galaxyAPIProxy;
    this.modelConfig = { ...DEFAULT_MODEL_CONFIG, ...options.modelConfig };
    console.log('[GalaxyAssistant] Initialized with model config:', this.modelConfig);
  }

  /** Get current model configuration (for testing/debugging) */
  getModelConfig(): ModelConfig {
    return { ...this.modelConfig };
  }

  /**
   * Generate a contextual clarifying question using Claude Haiku.
   * Falls back to the staticFallback string if the LLM call fails.
   */
  private async _generateClarificationQuestion(
    userMessage: string,
    ambiguityType: string,
    staticFallback: string
  ): Promise<string> {
    try {
      const resp = await this.claude.messages.create({
        model: 'claude-haiku-4-5-20251001',
        max_tokens: 200,
        system: `You are a bioinformatics expert assistant. A user has sent a query that is ambiguous for workflow selection. Generate a single concise clarifying question tailored to their SPECIFIC query. Use **bold** for key options. Keep it under 70 words. Never repeat the user's exact phrasing verbatim.

Ambiguity type → what to ask about:
- variant_type: germline (inherited disease, single patient) vs somatic (tumor mutations, matched samples)
- rnaseq_type: bulk RNA-seq (differential expression) vs single-cell RNA-seq (cell clustering)
- assembly_type: de novo assembly (no reference) vs reference-guided assembly
- peak_calling_type: ChIP-seq (antibody + input control) vs ATAC-seq (transposase, no antibody)
- chip_target: transcription factor (narrow peaks) vs histone modification (broad peaks)
- proteomics_type: DDA (MaxQuant) vs DIA (DIA-NN / Spectronaut)
- cryoem_type: single-particle analysis (SPA, purified protein) vs cryo-ET (tomography, in-situ)
- cryoem_sample: globular particle (standard) vs filamentous assembly (helical reconstruction)
- somatic_paired: matched tumor-normal vs tumor-only (panel of normals)
- metagenomics_type: 16S amplicon (QIIME2/DADA2) vs shotgun metagenomics (Kraken2/MetaPhlAn)
- docking_type: blind docking (DiffDock) vs site-directed docking (AutoDock Vina)`,
        messages: [{
          role: 'user',
          content: `User query: "${userMessage}"\nAmbiguity type: ${ambiguityType}\nGenerate the clarifying question:`
        }]
      });
      const text = resp.content[0].type === 'text' ? resp.content[0].text.trim() : '';
      return text || staticFallback;
    } catch {
      return staticFallback;
    }
  }

  /**
   * Infer the bioinformatics domain of a query using Claude Haiku.
   * Returns a domain string like 'cryo_em', 'rna_seq', 'variant_calling_germline', etc.
   * Returns undefined if the domain cannot be determined.
   */
  private async _inferDomainWithLLM(
    userIntent: string,
    currentWorkflowText?: string
  ): Promise<string | undefined> {
    const VALID_DOMAINS = [
      'cryo_em', 'rna_seq', 'variant_calling_germline', 'variant_calling_somatic',
      'single_cell', 'epigenomics_chip', 'epigenomics_atac', 'proteomics',
      'drug_discovery', 'metagenomics_16s', 'metagenomics_shotgun',
      'methylation', 'genome_assembly', 'structural_biology',
    ];
    try {
      const contextLine = currentWorkflowText
        ? `\nActive workflow context: "${currentWorkflowText}"`
        : '';
      const resp = await this.claude.messages.create({
        model: 'claude-haiku-4-5-20251001',
        max_tokens: 30,
        system: `Classify the bioinformatics domain of a query. Respond with ONLY one of these exact strings (no punctuation, no explanation):
cryo_em | rna_seq | variant_calling_germline | variant_calling_somatic | single_cell | epigenomics_chip | epigenomics_atac | proteomics | drug_discovery | metagenomics_16s | metagenomics_shotgun | methylation | genome_assembly | structural_biology | other | unknown

Rules:
- cryo_em: cryo-EM, CryoSPARC, RELION, SPA, micrograph, CTF, tomography, tilt series
- rna_seq: RNA-seq, DESeq2, edgeR, limma, salmon, kallisto, STAR, transcriptomics (bulk, not single-cell)
- variant_calling_germline: germline, inherited disease, rare disease, HaplotypeCaller, no tumor
- variant_calling_somatic: somatic, tumor-normal, MuTect2, cancer mutations, matched tumor
- single_cell: scRNA-seq, Seurat, Scanpy, 10x Genomics, cell atlas, UMAP clustering
- epigenomics_chip: ChIP-seq, histone modification, transcription factor binding, MACS2
- epigenomics_atac: ATAC-seq, chromatin accessibility, open chromatin
- proteomics: mass spectrometry, DIA-NN, MaxQuant, proteome, TMT
- drug_discovery: ADMET, docking, DiffDock, AutoDock, pharmacokinetics, NCA, SMILES, HERG, DILI
- metagenomics_16s: 16S rRNA, amplicon, QIIME2, DADA2, OTU, taxonomic profiling
- metagenomics_shotgun: shotgun metagenomics, Kraken2, MetaPhlAn, whole metagenome
- methylation: bisulfite, WGBS, RRBS, DNA methylation, methylseq
- genome_assembly: de novo assembly, SPAdes, Flye, genome sequencing assembly
- structural_biology: AlphaFold, protein structure prediction, molecular dynamics (non-cryo-EM)
- other: recognised bioinformatics domain not listed above
- unknown: insufficient information`,
        messages: [{
          role: 'user',
          content: `Query: "${userIntent}"${contextLine}`
        }]
      });
      const domain = resp.content[0].type === 'text' ? resp.content[0].text.trim() : 'unknown';
      if (VALID_DOMAINS.includes(domain)) return domain;
      return undefined; // 'other' or 'unknown' → no restriction
    } catch {
      return undefined;
    }
  }

  /** Update model configuration at runtime */
  setModelConfig(config: Partial<ModelConfig>): void {
    this.modelConfig = { ...this.modelConfig, ...config };
    console.log('[GalaxyAssistant] Model config updated:', this.modelConfig);
  }

  /**
   * Main entry point: Process user message with full Galaxy intelligence
   *
   * For single-intent messages (the common case), the pipeline is unchanged:
   *   analyzeIntent → parallel search → workflowNeed → generateWorkflow → generateResponse
   *
   * For multi-intent messages, a fan-out processes each intent independently:
   *   analyzeIntent → parallel search (union keywords) → Promise.all(processSubIntent) → generateResponse
   */
  async processMessage(
    message: string,
    context: ChatContext = {},
    onResponseDelta?: (chunk: string) => void
  ): Promise<GalaxyAssistantResponse> {
    const startTime = Date.now();
    const log = (step: string) => console.log(`[GalaxyAssistant] [${Date.now() - startTime}ms] ${step}`);

    log('Processing message: ' + message.substring(0, 50));

    // Step 1: Analyze user intent with NLU (now supports multi-intent)
    log('Step 1: Analyzing intent');
    const decomposition = await this.analyzeIntent(message, context);
    const intent = decomposition.primaryIntent;
    log(`Step 1 complete - Intent: ${intent.type}, isMultiIntent: ${decomposition.isMultiIntent}, intents: ${decomposition.intents.length}`);

    // Multi-intent path: fan out to processSubIntent for each intent
    if (decomposition.isMultiIntent) {
      return this.processMultiIntent(decomposition, message, context, startTime, onResponseDelta);
    }

    // Single-intent path: unchanged from original pipeline
    // Steps 2 & 3: Search for tools and datasets IN PARALLEL
    let recommendedTools: ToolRecommendation[] = [];
    let recommendedDatasets: DatasetRecommendation[] = [];
    let toolSearchUsed = false;
    let datasetRAGUsed = false;

    const searchPromises: Promise<void>[] = [];

    // Search tools when action flags indicate it
    if (intent.actions.needsToolSearch) {
      searchPromises.push(
        this.searchRelevantTools(message, intent.keywords, context.userId)
          .then(tools => {
            recommendedTools = tools;
            toolSearchUsed = true;
            console.log(`[GalaxyAssistant] Found ${tools.length} relevant tools`);
          })
      );
    }

    // Search datasets when action flags indicate it or legacy flag is set
    if (intent.actions.needsDatasetAccess || intent.needsDatasets) {
      searchPromises.push(
        this.searchRelevantDatasets(message, intent.keywords)
          .then(datasets => {
            recommendedDatasets = datasets;
            datasetRAGUsed = true;
            console.log(`[GalaxyAssistant] Found ${datasets.length} relevant datasets`);
          })
      );
    }

    // Wait for all parallel searches to complete
    log('Steps 2-3: Starting parallel searches');
    if (searchPromises.length > 0) {
      await Promise.all(searchPromises);
      log('Steps 2-3 complete');
    }

    // Step 4: Determine if workflow generation is needed
    let workflowSuggestion: WorkflowSuggestion;
    let generatedWorkflow = null;
    let workflowGenerated = false;

    // Action-flag-based routing (replaces switch-on-type)
    let researchResponse: any = undefined;
    let benchmarkEvidence: any = undefined;
    const actions = intent.actions;

    // If the intent is ambiguous, return a clarifying question before generating
    const ambiguity = (intent as any).workflowAmbiguity;
    if (ambiguity && actions.needsWorkflowGeneration) {
      // Static fallback questions (used if Haiku call fails)
      const CLARIFICATION_FALLBACKS: Record<string, string> = {
        variant_type:
          "To generate the right workflow: is this **germline** variant calling " +
          "(inherited variants, single sample) or **somatic** variant calling " +
          "(tumor mutations — requires matched tumor + normal BAM)?",
        assembly_type:
          "For genome assembly: is this **de novo assembly** (no reference, e.g. SPAdes/Flye) " +
          "or **reference-guided assembly** (mapping reads to an existing reference)?",
        rnaseq_type:
          "To select the right pipeline: is this **bulk RNA-seq** (differential expression, e.g. DESeq2) " +
          "or **single-cell RNA-seq** (cell population profiling, e.g. Seurat/Scanpy)?",
        scrna_type:
          "For single-cell analysis: is this a **perturbation screen** (CRISPR KO library) " +
          "or a standard **cell atlas / clustering** analysis?",
        peak_calling_type:
          "For chromatin analysis: is this **ChIP-seq** (antibody + input control) or " +
          "**ATAC-seq** (transposase-accessible chromatin — no antibody needed)?",
        chip_target:
          "For ChIP-seq: are you profiling a **transcription factor** (narrow peaks) " +
          "or a **histone modification** (broad peaks, e.g. H3K27me3)?",
        rnaseq_focus:
          "For RNA analysis: is this **mRNA / differential expression** (bulk RNA-seq, DESeq2/edgeR) " +
          "or **small RNA / miRNA** (miRDeep2 — different library prep and references)?",
        flow_cytometry_type:
          "For flow cytometry: is the goal **immunophenotyping** (gating cell populations), " +
          "**cell sorting**, or **unsupervised clustering** (e.g. flowSOM)?",
        proteomics_type:
          "For proteomics: is this **DDA** (data-dependent acquisition, e.g. MaxQuant) or " +
          "**DIA** (data-independent acquisition, e.g. DIA-NN / Spectronaut)?",
        cryoem_type:
          "For cryo-EM: is this **single-particle analysis (SPA)** (purified protein → 3D reconstruction) " +
          "or **cryo-ET** (tomography — in-situ structures inside cells)?",
        cryoem_sample:
          "For cryo-EM SPA: is your sample a **globular particle** (standard CryoSPARC/RELION pipeline) " +
          "or a **filamentous assembly** (helical reconstruction needed)?",
        somatic_paired:
          "For somatic variant calling: do you have a **matched normal sample** " +
          "(tumor + normal BAM) or is this **tumor-only** calling (panel of normals)?",
        metagenomics_type:
          "For microbiome analysis: is this **16S amplicon sequencing** (QIIME2/DADA2) " +
          "or **shotgun metagenomics** (Kraken2/MetaPhlAn)?",
        docking_type:
          "For molecular docking: is this **blind docking** (binding site unknown, DiffDock) " +
          "or **site-directed docking** (known binding pocket, AutoDock Vina)?",
      };
      const fallback = CLARIFICATION_FALLBACKS[ambiguity];
      // Generate a contextual question with Haiku (falls back to static string on failure)
      const question = fallback
        ? await this._generateClarificationQuestion(message, ambiguity, fallback)
        : undefined;
      if (question) {
        log(`Step 4: Returning clarification question for ambiguity="${ambiguity}"`);
        // Return early — workflow generation deferred until user clarifies
        return {
          message: question,
          intentType: intent.type,
          intentConfidence: intent.confidence,
          recommendedTools: recommendedTools.length > 0 ? recommendedTools : undefined,
          recommendedDatasets: recommendedDatasets.length > 0 ? recommendedDatasets : undefined,
          workflowSuggestion: { shouldGenerate: false, userIntent: message, confidence: 0,
            reasoning: `Ambiguity "${ambiguity}" requires clarification before workflow generation` },
          generatedWorkflow: null,
          researchResponse: undefined,
          benchmarkEvidence: undefined,
          truncated: false,
          suggestions: [],
          sources: {
            toolSearchUsed: false,
            datasetRAGUsed: false,
            workflowGenerated: false,
            thinkingUsed: false,
            researchAgentUsed: false,
            benchmarkAgentUsed: false,
          },
        };
      }
    }

    // Workflow generation / modification
    if (actions.needsWorkflowGeneration || actions.needsWorkflowModification) {
      log('Step 4: Analyzing workflow need');
      workflowSuggestion = await this.analyzeWorkflowNeed(
        message,
        intent,
        recommendedTools
      );
      log('Step 4 complete - shouldGenerate: ' + workflowSuggestion.shouldGenerate);

      if (workflowSuggestion.shouldGenerate && workflowSuggestion.confidence > 0.7) {
        try {
          log('Step 5: Generating workflow');
          generatedWorkflow = await this.generateWorkflow(
            workflowSuggestion.userIntent,
            recommendedDatasets.map(d => d.dataset),
            intent.inlineParameters,
            context
          );
           workflowGenerated = !!(
             generatedWorkflow?.success &&
             !generatedWorkflow?.error &&
             (generatedWorkflow?.workflow_ga ||
              generatedWorkflow?.nextflow_path ||
              generatedWorkflow?.workflow_type === 'chain')
           );
          if (workflowGenerated) {
            log('Step 5 complete - Workflow generated');
          } else {
            log('Step 5 complete - Generation returned no runnable workflow');
          }
        } catch (error: any) {
          log('Step 5 failed: ' + error.message);
          console.error('[GalaxyAssistant] Workflow generation failed:', error);
        }
      } else {
        log('Step 5: Skipped (workflow not needed based on analysis)');
      }
    } else {
      workflowSuggestion = {
        shouldGenerate: false,
        userIntent: message,
        confidence: 0,
        reasoning: `Intent type "${intent.type}" — workflow generation not flagged`,
      };
    }

    // Research agent
    if (actions.needsResearchAgent) {
      log('Routing to research backend');
      try {
        researchResponse = await this.galaxyAPI.queryResearch({
          query: message,
          context: { information_need: intent.type },
          include_citations: true,
          include_benchmark_evidence: true,
        });
        log('Research response received');
      } catch (error: any) {
        log('Research query failed: ' + error.message);
      }
    }

    // Benchmark agent
    if (actions.needsBenchmarkAgent) {
      log('Routing to benchmark backend');
      try {
        benchmarkEvidence = await this.galaxyAPI.queryBenchmark({
          query: message,
        });
        log('Benchmark response received');
      } catch (error: any) {
        log('Benchmark query failed: ' + error.message);
      }
    }

    // Step 6: Generate natural language response
    log('Step 6: Generating response');
    const response = await this.generateResponse(
      message,
      intent,
      recommendedTools,
      recommendedDatasets,
      workflowSuggestion,
      generatedWorkflow,
      context,
      researchResponse,
      benchmarkEvidence,
      onResponseDelta
    );
    log('Step 6 complete');

    // Step 7: Generate follow-up suggestions
    log('Step 7: Generating suggestions');
    const suggestions = this.generateSuggestions(
      message,
      intent,
      recommendedTools,
      workflowSuggestion
    );
    log('Step 7 complete');
    log('Total processing time: ' + (Date.now() - startTime) + 'ms');

    // Convert intent facts to ExtractedFact format with unique IDs
    const turnIndex = context.turnIndex ?? 0;
    const extractedFacts: ExtractedFact[] = intent.facts.map((f, i) => ({
      id: `fact-${Date.now()}-${i}`,
      category: f.category as ExtractedFact['category'],
      value: f.value,
      source: { type: 'user_message' as const, turnIndex },
      confidence: f.confidence,
      supersedes: f.supersedes,
    }));

    return {
      message: response.message,
      intentType: intent.type,
      intentConfidence: intent.confidence,
      inlineParameters: Object.keys(intent.inlineParameters).length > 0 ? intent.inlineParameters : undefined,
      extractedFacts: extractedFacts.length > 0 ? extractedFacts : undefined,
      thinking_content: response.thinking?.thinkingContent ?? undefined,
      thinking_level: response.thinking?.thinkingLevel ?? undefined,
      recommendedTools: recommendedTools.length > 0 ? recommendedTools : undefined,
      recommendedDatasets: recommendedDatasets.length > 0 ? recommendedDatasets : undefined,
      workflowSuggestion,
      generatedWorkflow,
      researchResponse,
      benchmarkEvidence,
      isMultiIntent: false,
      truncated: response.truncated || false,
      suggestions,
      sources: {
        toolSearchUsed,
        datasetRAGUsed,
        workflowGenerated,
        thinkingUsed: response.thinking?.hasThinking || false,
        researchAgentUsed: !!researchResponse,
        benchmarkAgentUsed: !!benchmarkEvidence,
      },
    };
  }

  /**
   * Process a multi-intent message by fanning out to processSubIntent for each intent.
   * Results are collected and synthesized into a single response.
   */
  private async processMultiIntent(
    decomposition: IntentDecomposition,
    message: string,
    context: ChatContext,
    startTime: number,
    onResponseDelta?: (chunk: string) => void
  ): Promise<GalaxyAssistantResponse> {
    const log = (step: string) => console.log(`[GalaxyAssistant] [${Date.now() - startTime}ms] ${step}`);

    log(`Multi-intent processing: ${decomposition.intents.length} intents`);

    // Step 2-3: Parallel tool/dataset search using union of all keywords
    const allKeywords = Array.from(new Set(decomposition.intents.flatMap(i => i.keywords)));
    let recommendedTools: ToolRecommendation[] = [];
    let recommendedDatasets: DatasetRecommendation[] = [];
    let toolSearchUsed = false;
    let datasetRAGUsed = false;

    const needsToolSearch = decomposition.intents.some(i => i.actions.needsToolSearch);
    const needsDatasets = decomposition.intents.some(i =>
      i.actions.needsDatasetAccess || i.needsDatasets
    );

    const searchPromises: Promise<void>[] = [];

    if (needsToolSearch && allKeywords.length > 0) {
      searchPromises.push(
        this.searchRelevantTools(message, allKeywords, context.userId)
          .then(tools => {
            recommendedTools = tools;
            toolSearchUsed = true;
            log(`Multi-intent: Found ${tools.length} tools`);
          })
      );
    }

    if (needsDatasets) {
      searchPromises.push(
        this.searchRelevantDatasets(message, allKeywords)
          .then(datasets => {
            recommendedDatasets = datasets;
            datasetRAGUsed = true;
            log(`Multi-intent: Found ${datasets.length} datasets`);
          })
      );
    }

    log('Multi-intent Steps 2-3: Starting parallel searches');
    if (searchPromises.length > 0) {
      await Promise.all(searchPromises);
      log('Multi-intent Steps 2-3 complete');
    }

    // Step 4-5: Process each intent in parallel
    log('Multi-intent Steps 4-5: Processing sub-intents in parallel');
    const subIntentResults = await Promise.all(
      decomposition.intents.map(intent =>
        this.processSubIntent(intent, message, context, recommendedTools, recommendedDatasets)
      )
    );
    log(`Multi-intent Steps 4-5 complete: ${subIntentResults.length} results`);

    // Collect workflow and research/benchmark results.
    // Prefer sub-intents that returned a *runnable* workflow (valid .nf path or non-empty steps)
    // over ones that returned a junk galaxy_ga placeholder with empty steps.
    const isRunnableWf = (wf: any) => !!(
      wf?.success && !wf?.error && (
        (wf?.nextflow_path && String(wf.nextflow_path).toLowerCase().endsWith('.nf')) ||
        (wf?.workflow_ga?.steps && Object.keys(wf.workflow_ga.steps).length > 0)
      )
    );
    const workflowResult =
      subIntentResults.find(r => isRunnableWf(r.generatedWorkflow)) ??
      subIntentResults.find(r => r.generatedWorkflow);
    const researchResult = subIntentResults.find(r => r.researchResponse);
    const benchmarkResult = subIntentResults.find(r => r.benchmarkEvidence);
    const workflowGenerated = !!workflowResult?.generatedWorkflow;

    // Collect all ADDITIONAL runnable workflows (unique by nextflow_path or workflow_name)
    const primaryWfPath = workflowResult?.generatedWorkflow?.nextflow_path;
    const additionalWorkflows = subIntentResults
      .filter(r => r !== workflowResult && isRunnableWf(r.generatedWorkflow))
      .filter((r, i, arr) => {
        // deduplicate by path
        const p = r.generatedWorkflow?.nextflow_path;
        return p !== primaryWfPath && arr.findIndex(x => x.generatedWorkflow?.nextflow_path === p) === i;
      })
      .map(r => r.generatedWorkflow);

    // Step 6: Generate synthesized response
    log('Multi-intent Step 6: Generating synthesized response');
    const primaryIntent = decomposition.primaryIntent;
    const response = await this.generateResponse(
      message,
      primaryIntent,
      recommendedTools,
      recommendedDatasets,
      {
        shouldGenerate: workflowGenerated,
        userIntent: message,
        confidence: primaryIntent.confidence,
        reasoning: `Multi-intent: ${decomposition.intents.map(i => i.type).join(', ')}`,
      },
      workflowResult?.generatedWorkflow || null,
      context,
      researchResult?.researchResponse,
      benchmarkResult?.benchmarkEvidence,
      onResponseDelta
    );
    log('Multi-intent Step 6 complete');

    // Step 7: Suggestions
    log('Multi-intent Step 7: Generating suggestions');
    const suggestions = this.generateSuggestions(
      message,
      primaryIntent,
      recommendedTools,
      { shouldGenerate: workflowGenerated, userIntent: message, confidence: primaryIntent.confidence, reasoning: '' }
    );
    log('Multi-intent Step 7 complete');
    log('Multi-intent total processing time: ' + (Date.now() - startTime) + 'ms');

    // Collect all facts from all intents
    const turnIndex = context.turnIndex ?? 0;
    const allFacts = decomposition.intents.flatMap(intent => intent.facts);
    const extractedFacts: ExtractedFact[] = allFacts.map((f, i) => ({
      id: `fact-${Date.now()}-${i}`,
      category: f.category as ExtractedFact['category'],
      value: f.value,
      source: { type: 'user_message' as const, turnIndex },
      confidence: f.confidence,
      supersedes: f.supersedes,
    }));

    return {
      message: response.message,
      intentType: primaryIntent.type,
      intentConfidence: primaryIntent.confidence,
      inlineParameters: Object.keys(primaryIntent.inlineParameters).length > 0 ? primaryIntent.inlineParameters : undefined,
      extractedFacts: extractedFacts.length > 0 ? extractedFacts : undefined,
      thinking_content: response.thinking?.thinkingContent ?? undefined,
      thinking_level: response.thinking?.thinkingLevel ?? undefined,
      recommendedTools: recommendedTools.length > 0 ? recommendedTools : undefined,
      recommendedDatasets: recommendedDatasets.length > 0 ? recommendedDatasets : undefined,
      workflowSuggestion: {
        shouldGenerate: workflowGenerated,
        userIntent: message,
        confidence: primaryIntent.confidence,
        reasoning: `Multi-intent processing: ${decomposition.intents.map(i => i.type).join(', ')}`,
      },
      generatedWorkflow: workflowResult?.generatedWorkflow || null,
      additionalWorkflows: additionalWorkflows.length > 0 ? additionalWorkflows : undefined,
      researchResponse: researchResult?.researchResponse,
      benchmarkEvidence: benchmarkResult?.benchmarkEvidence,
      subIntentResults,
      isMultiIntent: true,
      suggestions,
      sources: {
        toolSearchUsed,
        datasetRAGUsed,
        workflowGenerated,
        thinkingUsed: response.thinking?.hasThinking || false,
        researchAgentUsed: !!researchResult?.researchResponse,
        benchmarkAgentUsed: !!benchmarkResult?.benchmarkEvidence,
      },
    };
  }

  /**
   * Process a single sub-intent within a multi-intent message.
   * Routes to the appropriate backend(s) based on action category flags.
   */
  private async processSubIntent(
    intent: DecomposedIntent,
    originalMessage: string,
    context: ChatContext,
    recommendedTools: ToolRecommendation[],
    recommendedDatasets: DatasetRecommendation[]
  ): Promise<SubIntentResult> {
    const baseResult: SubIntentResult = {
      intentId: intent.id,
      intentType: intent.type,
      subQuery: intent.subQuery,
      status: 'success',
    };

    const actions = intent.actions;

    try {
      // Action-flag-based routing: multiple agents can be invoked per intent

      // Tool search results already available from parallel search
      if (actions.needsToolSearch && recommendedTools.length > 0) {
        baseResult.recommendedTools = recommendedTools;
      }

      // Workflow generation
      if ((actions.needsWorkflowGeneration || actions.needsWorkflowModification) && recommendedTools.length > 0) {
        const workflowSuggestion = await this.analyzeWorkflowNeed(
          intent.subQuery,
          intent,
          recommendedTools
        );
        if (workflowSuggestion.shouldGenerate && workflowSuggestion.confidence > 0.7) {
          // When this sub-intent is part of a multi-intent query, use the original full message
          // as the workflow intent so domain preference (e.g. drug/docking tokens) is preserved.
          // This prevents e.g. a "predict structure" sub-intent from losing the "docking/drug"
          // context that the full query carries, which would otherwise pick a microbiology tool.
          const effectiveIntent = (originalMessage && originalMessage !== intent.subQuery)
            ? originalMessage
            : workflowSuggestion.userIntent;
          const workflow = await this.generateWorkflow(
            effectiveIntent,
            recommendedDatasets.map(d => d.dataset),
            intent.inlineParameters,
            context
          );
          baseResult.generatedWorkflow = workflow;
          if (!baseResult.recommendedTools) baseResult.recommendedTools = recommendedTools;
        }
      }

      // Research agent
      if (actions.needsResearchAgent) {
        try {
          baseResult.researchResponse = await this.galaxyAPI.queryResearch({
            query: intent.subQuery,
            context: { information_need: intent.type },
            include_citations: true,
            include_benchmark_evidence: true,
          });
        } catch (error: any) {
          console.warn(`[GalaxyAssistant] Research query failed for ${intent.id}: ${error.message}`);
        }
      }

      // Benchmark agent
      if (actions.needsBenchmarkAgent) {
        try {
          baseResult.benchmarkEvidence = await this.galaxyAPI.queryBenchmark({
            query: intent.subQuery,
          });
        } catch (error: any) {
          console.warn(`[GalaxyAssistant] Benchmark query failed for ${intent.id}: ${error.message}`);
        }
      }

      return baseResult;
    } catch (error: any) {
      console.error(`[GalaxyAssistant] Sub-intent ${intent.id} (${intent.type}) failed:`, error.message);
      return { ...baseResult, status: 'error', error: error.message };
    }
  }

  /**
   * Analyze user intent, detecting multiple intents if present.
   * Returns IntentDecomposition with one or more decomposed intents.
   */
  private async analyzeIntent(
    message: string,
    context: ChatContext
  ): Promise<IntentDecomposition> {
    const systemPrompt = `You are a bioinformatics intent analyzer. Classify user messages by their information need and declare which system agents should handle the request.

## Information Need Types

Describe the user's information need with a descriptive label. You may use these common labels or create a new one that better fits:

**workflow_generation** — Execute a computational task, run a tool, process data, perform an analysis.
**research_question** — Search/review scientific literature, papers, databases.
**result_comparison** — Compare tools, methods, or approaches with evidence.
**tool_search** — Find or learn about available tools and their capabilities.
**benchmark_query** — Get specific performance data or benchmarks.
**dataset_inquiry** — Find or learn about available datasets.
**general_question** — Conversational or conceptual question.
**workflow_modification** — Modify an existing workflow from the conversation.
**troubleshooting** — Diagnose a problem (e.g., low alignment rate, failed job).
**experiment_design** — Plan an experiment or analysis strategy.
**data_interpretation** — Help interpret analysis results.
**protocol_guidance** — Get step-by-step experimental protocols.
**parameter_optimization** — Optimize tool/analysis parameters.
**data_format_conversion** — Convert between file formats.
**teaching_explanation** — Educational explanation of concepts.
**methods_writing** — Help write a methods section for a paper.
**visualization** — Create plots, charts, or visual summaries.
**comparative_methodology** — Compare scientific methodologies with evidence.

You may also create a novel label if none of the above fit (e.g., "cost_estimation", "regulatory_compliance", "multi_step_procedure").

## Action Categories

For each intent, declare which system agents are needed (true/false):
- **needsToolSearch**: Search Galaxy's tool database for relevant tools
- **needsWorkflowGeneration**: Build a multi-step Galaxy workflow
- **needsWorkflowModification**: Modify an existing workflow
- **needsResearchAgent**: Scientific question answering (literature, evidence synthesis)
- **needsBenchmarkAgent**: Quantitative tool/method comparison with metrics
- **needsDatasetAccess**: Search Galaxy datasets
- **needsLLMReasoning**: Generate synthesized text response (almost always true)

## Multi-Intent Detection

A message may contain MULTIPLE DISTINCT tasks. Examples:
- "Run DE analysis on my RNA-seq data AND compare DESeq2 vs edgeR" → workflow_generation + result_comparison
- "Find papers on CRISPR delivery and also run off-target analysis on this guide RNA" → research_question + workflow_generation
- "What tools do variant calling, and show me their benchmarks" → tool_search + benchmark_query

Rules for multi-intent:
- Split into multiple intents when the message contains genuinely SEPARATE tasks requiring DIFFERENT backends
- Use conjunctions like "AND", "also", "plus", "as well as" as signals for multi-intent
- A single complex task (e.g., "design a pipeline that does QC then alignment then counting") is ONE workflow_generation intent, not three
- Clarifying details ("from human samples") attached to a prior task are NOT separate intents
- Each intent must have its own subQuery (the portion of the message relevant to that intent)
- Set dependsOn when one intent's output feeds into another (e.g., research findings used for workflow design)
- IMPORTANT: When in doubt between single-intent and multi-intent, prefer multi-intent if the user is asking for 2+ distinct outcomes (e.g., run an analysis AND compare tools AND search literature)

## Parameter Extraction

Extract any inline data or parameters the user provides directly in their message:
- DNA/RNA/protein sequences (e.g., "ATGCGATCG")
- Gene names (e.g., "TP53", "BRCA1")
- File paths or dataset references
- Numeric parameters (e.g., "p-value < 0.05", "top 100 genes")
- Species/organism (e.g., "human", "E. coli")

## Keyword Extraction

Extract keywords that describe the OPERATION or ANALYSIS, not generic terms:
- Good: "reverse complement", "differential expression", "variant calling"
- Bad: "DNA", "data", "analysis" (too generic)

## Fact Extraction

Extract structured facts from the message. Each fact MUST use one of these exact categories:
"sequence", "gene", "organism", "data_type", "parameter", "file_reference", "tool_preference", "domain", "analysis_goal", "other"

Category definitions:
- **sequence**: DNA/RNA/protein sequence literals (e.g., "ATGCGATCG")
- **gene**: Gene or protein names (e.g., "TP53", "BRCA1", "EGFR")
- **organism**: Species or organism (e.g., "human", "mouse", "E. coli", "Arabidopsis")
- **data_type**: Type of data mentioned (e.g., "RNA-seq", "ChIP-seq", "WGS", "proteomics")
- **parameter**: Specific parameters or thresholds (e.g., "p-value < 0.05", "hg38", "paired-end")
- **file_reference**: File paths, URLs, or dataset references
- **tool_preference**: Specific tool the user wants to use (e.g., "BWA", "DESeq2", "STAR")
- **domain**: Scientific domain (e.g., "genomics", "proteomics", "pharmacology")
- **analysis_goal**: What the user wants to achieve (e.g., "find differentially expressed genes", "identify variants")
- **other**: Any other relevant detail that doesn't fit the above categories

Assign confidence 0.0-1.0 based on how explicit the mention is. Direct mentions get 0.9+, inferred facts get 0.5-0.7.

## Fact Supersession

If EXISTING FACTS are provided below, check whether any new fact from the current message REPLACES or CORRECTS an existing fact. For example, if the user previously said "mouse" and now says "actually, human", the new organism fact supersedes the old one.

When a new fact replaces an old one, include "supersedes": "<id of the old fact>" in the new fact object. Only mark supersession when the user is clearly correcting or changing a previous statement — not when they are adding additional information.

${(() => {
  if (!context.accumulatedFacts || context.accumulatedFacts.length === 0) return '';
  const lines = context.accumulatedFacts.map(f => `- [id=${f.id}] ${f.category}: "${f.value}"`);
  return '\n## Existing Facts from Prior Turns\n' + lines.join('\n') + '\n';
})()}
## Ambiguity Detection

GENERAL RULE: When a workflow request could map to two or more pipelines with fundamentally
different inputs, tools, or scientific purposes — and the user has not provided enough context
to distinguish them — return "workflowAmbiguity" with the appropriate type. DO NOT guess.
Return null only when the user's message already contains enough specificity.

Known fork points (use the exact type string listed):

GENOMICS
- "variant_type": "variant calling" / "mutation analysis" / "SNP detection" without
  specifying "germline" (inherited, single sample → GATK HaplotypeCaller) vs
  "somatic" (tumor mutations, tumor+normal BAMs → GATK Mutect2)
- "assembly_type": "genome assembly" / "de novo assembly" without specifying
  "de novo" (no reference, e.g. SPAdes/Flye) vs "reference-guided" (e.g. GATK or BWA + polishing)

RNA-SEQ
- "rnaseq_type": "RNA-seq" / "transcriptomics" without specifying
  "bulk RNA-seq" (differential expression, DESeq2/edgeR) vs
  "single-cell RNA-seq" (cell clustering, Seurat/Scanpy)
- "scrna_type": single-cell RNA-seq without specifying
  "standard atlas/clustering" vs "perturbation screen" (CRISPR KO library, mixscape)

EPIGENOMICS
- "peak_calling_type": "peak calling" / "chromatin analysis" / "open chromatin" without
  specifying the assay — "ChIP-seq" (requires IP sample + input control, profiles specific
  proteins) vs "ATAC-seq" (transposase-based, no antibody, profiles accessible regions)
- "chip_target": "ChIP-seq" confirmed but target not specified:
  "transcription factor" (sharp peaks, MACS2 narrow) vs
  "histone modification" (broad peaks, e.g. H3K27me3, H3K4me1)

PROTEOMICS
- "proteomics_type": "proteomics" / "mass spectrometry" without specifying
  "DDA" (data-dependent acquisition, MaxQuant) vs "DIA" (data-independent, DIA-NN)

STRUCTURAL BIOLOGY
- "cryoem_type": "cryo-EM" / "electron microscopy" without specifying
  "single-particle analysis (SPA)" (isolated protein) vs
  "cryo-ET" (tomography, in-situ structures in cells)
- "cryoem_sample": cryo-EM SPA without specifying whether the sample is
  "globular particle" (standard SPA — CryoSPARC / RELION standard pipeline) vs
  "filamentous assembly" (actin, amyloid, microtubule, viral tube — requires
   helical reconstruction with rise/twist symmetry parameters)
  Only ask if the user mentioned a protein type that could be either.

GENOMICS (somatic sub-type)
- "somatic_paired": somatic variant calling requested but no indication whether
  "paired tumor+normal" (matched normal eliminates germline background, higher specificity) vs
  "tumor-only" (no matched normal, uses panel of normals — higher false-positive rate)

RNA-SEQ (sub-type)
- "rnaseq_focus": "RNA-seq" / "transcriptomics" but unclear if the goal is
  "mRNA / differential expression" (standard bulk pipeline, DESeq2/edgeR) vs
  "miRNA / small RNA" (miRDeep2/miRBase, completely different tools and reference databases)
  Only ask if the user mentioned "small RNA", "non-coding", "miRNA", or "regulatory RNA".

CELL BIOLOGY
- "flow_cytometry_type": "flow cytometry" / "FACS analysis" / "cell populations" without
  specifying the goal:
  "immunophenotyping / gating" (population statistics on cell subsets, % T/B cells) vs
  "cell sorting" (physical enrichment of cell fractions) vs
  "unsupervised clustering" (dimensionality reduction, flowSOM/flowMeans — no predefined gates)

METAGENOMICS
- "metagenomics_type": "metagenomics" / "microbiome" without specifying
  "16S amplicon" (amplicon sequencing, QIIME2/DADA2) vs
  "shotgun metagenomics" (whole-metagenome sequencing, Kraken2/MetaPhlAn)

DRUG DISCOVERY
- "docking_type": "molecular docking" without specifying
  "blind docking" (no binding site known, DiffDock) vs
  "site-directed docking" (known binding site, AutoDock Vina)

Return null if the user already specifies enough to unambiguously select one pipeline.

## Response Format

For SINGLE-intent messages (the common case), respond with a single JSON object:
{
  "type": "workflow_generation",
  "keywords": ["reverse complement"],
  "inlineParameters": {"sequence": "ATGCGATCG"},
  "needsToolSearch": true,
  "needsDatasets": false,
  "confidence": 0.95,
  "actions": {
    "needsToolSearch": true,
    "needsWorkflowGeneration": true,
    "needsWorkflowModification": false,
    "needsResearchAgent": false,
    "needsBenchmarkAgent": false,
    "needsDatasetAccess": false,
    "needsLLMReasoning": true
  },
  "facts": [
    {"category": "sequence", "value": "ATGCGATCG", "confidence": 1.0},
    {"category": "analysis_goal", "value": "reverse complement", "confidence": 0.95}
  ],
  "workflowAmbiguity": null
}

For MULTI-intent messages, respond with an "intents" array:
{
  "intents": [
    {
      "id": "intent_1",
      "type": "workflow_generation",
      "subQuery": "Run DE analysis on my RNA-seq data",
      "keywords": ["differential expression"],
      "inlineParameters": {},
      "needsToolSearch": true,
      "needsDatasets": true,
      "confidence": 0.9,
      "actions": {
        "needsToolSearch": true,
        "needsWorkflowGeneration": true,
        "needsWorkflowModification": false,
        "needsResearchAgent": false,
        "needsBenchmarkAgent": false,
        "needsDatasetAccess": false,
        "needsLLMReasoning": true
      },
      "facts": [{"category": "data_type", "value": "RNA-seq", "confidence": 0.95}],
      "dependsOn": []
    },
    {
      "id": "intent_2",
      "type": "result_comparison",
      "subQuery": "compare DESeq2 vs edgeR",
      "keywords": ["DESeq2", "edgeR", "comparison"],
      "inlineParameters": {},
      "needsToolSearch": true,
      "needsDatasets": false,
      "confidence": 0.85,
      "actions": {
        "needsToolSearch": false,
        "needsWorkflowGeneration": false,
        "needsWorkflowModification": false,
        "needsResearchAgent": false,
        "needsBenchmarkAgent": true,
        "needsDatasetAccess": false,
        "needsLLMReasoning": true
      },
      "facts": [{"category": "tool_preference", "value": "DESeq2", "confidence": 0.9}],
      "dependsOn": []
    }
  ]
}`;

    try {
      const intentStartTime = Date.now();
      console.log('[GalaxyAssistant] Intent API request:', {
        model: this.modelConfig.intentModel,
        max_tokens: 2500,
        system_prompt_length: systemPrompt.length,
        message_length: message.length
      });

      // Intent classification - using configurable model
      // 2500 tokens to accommodate multi-intent responses with full action objects
      const completion = await this.claude.messages.create({
        model: this.modelConfig.intentModel,
        max_tokens: 2500,
        temperature: 0.3,
        system: [
          {
            type: 'text',
            text: systemPrompt,
            cache_control: { type: 'ephemeral' },
          },
        ],
        messages: [{ role: 'user', content: message }],
      });

      console.log('[GalaxyAssistant] Intent API response:', {
        model: this.modelConfig.intentModel,
        time_ms: Date.now() - intentStartTime,
        usage: completion.usage
      });

      const content = completion.content[0];
      let resultText = content.type === 'text' ? content.text : '{}';

      // Strip markdown code blocks if present
      resultText = resultText
        .replace(/^```+\s*json\s*\n?/gi, '')
        .replace(/\n?```+\s*$/gi, '')
        .replace(/^\s*`+\s*/g, '')
        .replace(/\s*`+\s*$/g, '')
        .trim();

      // Try to extract JSON object if there's extra text around it
      const jsonMatch = resultText.match(/\{[\s\S]*\}/);
      if (jsonMatch) {
        resultText = jsonMatch[0];
      }

      // Remove any remaining backticks that might be inside string values
      resultText = resultText.replace(/`/g, "'");

      const result = JSON.parse(resultText);

      // Parse into IntentDecomposition
      return this.parseIntentResult(result, message);
    } catch (error) {
      console.error('[GalaxyAssistant] Intent analysis failed:', error);
      const fallback: DecomposedIntent = {
        id: 'intent_fallback',
        type: 'general_question',
        subQuery: message,
        keywords: [],
        inlineParameters: {},
        needsToolSearch: false,
        needsDatasets: false,
        confidence: 0.5,
        facts: [],
        dependsOn: [],
        actions: inferActionsFromType('general_question'),
      };
      return {
        intents: [fallback],
        isMultiIntent: false,
        primaryIntent: fallback,
      };
    }
  }

  /**
   * Parse the LLM's intent result into an IntentDecomposition.
   * Handles both single-intent (flat object) and multi-intent (intents array) formats.
   */
  private parseIntentResult(result: any, originalMessage: string): IntentDecomposition {
    const parseFacts = (rawFacts: any[]): Array<{ category: string; value: string; confidence: number; supersedes?: string }> => {
      if (!Array.isArray(rawFacts)) return [];
      return rawFacts
        .filter((f: any) => f && typeof f.category === 'string' && typeof f.value === 'string')
        .map((f: any) => ({
          category: f.category as string,
          value: f.value as string,
          confidence: typeof f.confidence === 'number' ? f.confidence : 0.8,
          supersedes: typeof f.supersedes === 'string' ? f.supersedes : undefined,
        }));
    };

    const parseActions = (raw: any, type: string): ActionCategories => {
      if (raw && typeof raw === 'object') {
        const base = inferActionsFromType(type);
        return {
          needsToolSearch: typeof raw.needsToolSearch === 'boolean' ? raw.needsToolSearch : base.needsToolSearch,
          needsWorkflowGeneration: typeof raw.needsWorkflowGeneration === 'boolean' ? raw.needsWorkflowGeneration : base.needsWorkflowGeneration,
          needsWorkflowModification: typeof raw.needsWorkflowModification === 'boolean' ? raw.needsWorkflowModification : base.needsWorkflowModification,
          needsResearchAgent: typeof raw.needsResearchAgent === 'boolean' ? raw.needsResearchAgent : base.needsResearchAgent,
          needsBenchmarkAgent: typeof raw.needsBenchmarkAgent === 'boolean' ? raw.needsBenchmarkAgent : base.needsBenchmarkAgent,
          needsDatasetAccess: typeof raw.needsDatasetAccess === 'boolean' ? raw.needsDatasetAccess : base.needsDatasetAccess,
          needsLLMReasoning: typeof raw.needsLLMReasoning === 'boolean' ? raw.needsLLMReasoning : base.needsLLMReasoning,
        };
      }
      return inferActionsFromType(type);
    };

    // Multi-intent format: { intents: [...] }
    if (Array.isArray(result.intents) && result.intents.length > 0) {
      const intents: DecomposedIntent[] = result.intents.map((intent: any, i: number) => ({
        id: intent.id || `intent_${i + 1}`,
        type: intent.type || 'general_question',
        subQuery: intent.subQuery || originalMessage,
        keywords: intent.keywords || [],
        inlineParameters: intent.inlineParameters || {},
        needsToolSearch: intent.needsToolSearch !== false,
        needsDatasets: intent.needsDatasets !== false,
        confidence: intent.confidence || 0.5,
        facts: parseFacts(intent.facts),
        dependsOn: Array.isArray(intent.dependsOn) ? intent.dependsOn : [],
        actions: parseActions(intent.actions, intent.type || 'general_question'),
      }));

      // Primary = highest confidence
      const primaryIntent = intents.reduce((best, current) =>
        current.confidence > best.confidence ? current : best
      );

      console.log(`[GalaxyAssistant] Multi-intent detected: ${intents.length} intents [${intents.map(i => i.type).join(', ')}]`);

      return {
        intents,
        isMultiIntent: intents.length > 1,
        primaryIntent,
      };
    }

    // Single-intent format: flat object with type, keywords, etc.
    const intentType = result.type || 'general_question';
    const singleIntent: DecomposedIntent = {
      id: 'intent_1',
      type: intentType,
      subQuery: originalMessage,
      keywords: result.keywords || [],
      inlineParameters: result.inlineParameters || {},
      needsToolSearch: result.needsToolSearch !== false,
      needsDatasets: result.needsDatasets !== false,
      confidence: result.confidence || 0.5,
      facts: parseFacts(result.facts),
      dependsOn: [],
      actions: parseActions(result.actions, intentType),
    };

    return {
      intents: [singleIntent],
      isMultiIntent: false,
      primaryIntent: singleIntent,
    };
  }

  /**
   * Search for relevant tools using Galaxy Tool Search Index
   */
  private async searchRelevantTools(
    userMessage: string,
    keywords: string[],
    userId?: number
  ): Promise<ToolRecommendation[]> {
    try {
      // Fetch user patterns for personalization
      let userContext: UserContext = {};
      if (userId) {
        const insights = await userPatternsService.getUserInsights(userId);
        userContext = userPatternsService.extractUserContext(insights);
        console.log('[GalaxyAssistant] User context:', userContext);
      }

      // Build search query from keywords
      // Try progressively simpler queries until we get results
      let toolSearchResponse: any = { tools: [] };
      let successfulQuery = '';

      // Try different query strategies: full query -> first 3 keywords -> first keyword
      const queriesToTry = [
        keywords.slice(0, 3).join(' '),  // First 3 keywords
        keywords[0],                       // Just first keyword
        keywords.join(' '),                // All keywords (least likely to match)
      ];

      for (const query of queriesToTry) {
        if (!query) continue;
        console.log('[GalaxyAssistant] Tool search query:', query);

        // Search Galaxy tool index
        // limit=20 for performance — limit=100 triggers a Galaxy DB bottleneck (~3 min)
        toolSearchResponse = await this.galaxyAPI.searchTools(query, undefined, 20);

        console.log('[GalaxyAssistant] Raw Galaxy API response:', {
          count: toolSearchResponse.count,
          toolsReturned: toolSearchResponse.tools?.length || 0,
          query: toolSearchResponse.query,
          tools: toolSearchResponse.tools?.slice(0, 5).map((t: any) => ({
            tool_id: t.tool_id,
            name: t.name,
            category: t.category
          })) || []
        });

        if (toolSearchResponse.tools && toolSearchResponse.tools.length > 0) {
          successfulQuery = query;
          break;
        }
      }

      if (!toolSearchResponse.tools || toolSearchResponse.tools.length === 0) {
        console.log('[GalaxyAssistant] No tools returned from any search query');
        return [];
      }

      console.log(`[GalaxyAssistant] Found tools with query: "${successfulQuery}"`);

      // Use LLM to rank tools by relevance (with user context)
      const rankedTools = await this.rankToolsByRelevance(
        userMessage,
        toolSearchResponse.tools,
        userContext
      );

      console.log('[GalaxyAssistant] After LLM ranking:', {
        totalToolsFromGalaxy: toolSearchResponse.tools.length,
        toolsAfterRanking: rankedTools.length,
        topRankedTools: rankedTools.slice(0, 3).map(r => ({
          tool_id: r.tool.tool_id,
          name: r.tool.name,
          relevanceScore: r.relevanceScore,
          reasoning: r.reasoning
        }))
      });

      return rankedTools;
    } catch (error) {
      console.error('[GalaxyAssistant] Tool search failed:', error);
      return [];
    }
  }

  /**
   * Rank tools by relevance using LLM
   */
  private async rankToolsByRelevance(
    userMessage: string,
    tools: GalaxyTool[],
    userContext?: UserContext
  ): Promise<ToolRecommendation[]> {
    // Build user context description for prompt
    const userContextStr = userContext ? userPatternsService.formatContextForPrompt(userContext) : '';

    const systemPrompt = `You are a bioinformatics tool expert. Rank the provided tools by relevance to the user's request.
${userContextStr ? userContextStr + '\n\nConsider the user profile when ranking tools. Give higher scores to tools that match their domain and previous successful tools.' : ''}
For each tool, provide:
1. Relevance score (0-1)
2. Brief reasoning (plain text, no backticks or markdown)

IMPORTANT: Return ONLY valid JSON array, no markdown, no backticks, no code fences. Keep reasoning brief (under 50 words).

[
  {
    "tool_id": "tool_123",
    "relevanceScore": 0.95,
    "reasoning": "Perfect match for RNA-seq alignment"
  }
]`;

    const toolCatalog = tools
      .map(
        (t, i) =>
          `${i + 1}. ${t.name} (${t.tool_id})
   Category: ${t.category || 'N/A'}
   Keywords: ${t.keywords || 'N/A'}`
      )
      .join('\n\n');

    try {
      console.log('[GalaxyAssistant] Tool ranking API request:', {
        model: this.modelConfig.toolRankingModel,
        max_tokens: 2000,
        tools_to_rank: tools.length
      });
      const rankStartTime = Date.now();

      const completion = await this.claude.messages.create({
        model: this.modelConfig.toolRankingModel,
        max_tokens: 2000, // Increased to handle ranking many tools
        temperature: 0.3,
        system: [
          {
            type: 'text',
            text: systemPrompt,
            cache_control: { type: 'ephemeral' },
          },
        ],
        messages: [
          {
            role: 'user',
            content: `User request: ${userMessage}\n\nAvailable tools:\n${toolCatalog}`,
          },
        ],
      });

      console.log('[GalaxyAssistant] Tool ranking API response:', {
        model: this.modelConfig.toolRankingModel,
        time_ms: Date.now() - rankStartTime,
        usage: completion.usage
      });

      const content = completion.content[0];
      let resultText = content.type === 'text' ? content.text : '[]';

      // Clean JSON response from LLM
      resultText = resultText
        .replace(/^```+\s*json\s*\n?/gi, '')  // Remove opening code fence
        .replace(/\n?```+\s*$/gi, '')          // Remove closing code fence
        .replace(/^\s*`+\s*/g, '')             // Remove leading backticks
        .replace(/\s*`+\s*$/g, '')             // Remove trailing backticks
        .trim();

      // Handle truncated JSON (incomplete response due to max_tokens)
      // Try to find the last complete object by balancing braces
      if (!resultText.endsWith(']') && !resultText.endsWith('}')) {
        // Find last complete object
        const lastCompleteObj = resultText.lastIndexOf('},');
        if (lastCompleteObj > 0) {
          resultText = resultText.slice(0, lastCompleteObj + 1) + ']';
        } else {
          // Can't salvage, return empty
          resultText = '[]';
        }
      }

      // Remove inline backticks from JSON strings (LLM sometimes uses `tool_name` in reasoning)
      // This regex finds backticks inside JSON string values and removes them
      resultText = resultText.replace(/`([^`]*)`/g, '$1');

      let rankings: any[];
      try {
        const parsed = JSON.parse(resultText);
        rankings = parsed.rankings || parsed;
      } catch (parseError) {
        // If still failing, try to extract individual tool rankings with regex
        console.warn('[GalaxyAssistant] JSON parse failed, attempting regex extraction');
        const toolMatches = resultText.matchAll(/"tool_id"\s*:\s*"([^"]+)"[^}]*"relevanceScore"\s*:\s*([\d.]+)/g);
        rankings = Array.from(toolMatches).map(m => ({
          tool_id: m[1],
          relevanceScore: parseFloat(m[2]),
          reasoning: 'Extracted from partial response'
        }));
        if (rankings.length === 0) throw parseError;
      }
      const rankingArray = rankings;

      return tools
        .map((tool) => {
          const ranking = rankingArray.find((r: any) => r.tool_id === tool.tool_id);
          return {
            tool,
            relevanceScore: ranking?.relevanceScore || 0.5,
            reasoning: ranking?.reasoning || 'Potentially relevant',
          };
        })
        .filter((r) => r.relevanceScore > 0.3)
        .sort((a, b) => b.relevanceScore - a.relevanceScore)
        .slice(0, 5);
    } catch (error) {
      console.error('[GalaxyAssistant] Tool ranking failed:', error);
      return tools.slice(0, 5).map((tool) => ({
        tool,
        relevanceScore: 0.5,
        reasoning: 'Retrieved from tool search',
      }));
    }
  }

  /**
   * Search for relevant datasets using BioMNI RAG
   */
  private async searchRelevantDatasets(
    userMessage: string,
    keywords: string[]
  ): Promise<DatasetRecommendation[]> {
    try {
      // Search BioMNI dataset catalog
      const datasetSearchResponse = await this.galaxyAPI.searchDatasets({
        query: keywords.join(' '),
        limit: 10,
      });

      if (!datasetSearchResponse.success || !datasetSearchResponse.datasets) {
        return [];
      }

      // Rank datasets by relevance
      const rankedDatasets = await this.rankDatasetsByRelevance(
        userMessage,
        datasetSearchResponse.datasets
      );

      return rankedDatasets;
    } catch (error) {
      console.error('[GalaxyAssistant] Dataset search failed:', error);
      return [];
    }
  }

  /**
   * Rank datasets by relevance using LLM
   */
  private async rankDatasetsByRelevance(
    userMessage: string,
    datasets: BioMNIDataset[]
  ): Promise<DatasetRecommendation[]> {
    // Similar to tool ranking but for datasets
    return datasets.slice(0, 5).map((dataset) => ({
      dataset,
      relevanceScore: 0.7,
      reasoning: 'Retrieved from BioMNI catalog',
    }));
  }

  /**
   * Analyze if workflow generation is needed.
   * Relies on LLM intent classification — no rigid keyword matching.
   */
  private async analyzeWorkflowNeed(
    message: string,
    intent: any,
    recommendedTools: ToolRecommendation[]
  ): Promise<WorkflowSuggestion> {
    // Use action flags (not hardcoded type) to decide if workflow generation is needed
    const hasWorkflowIntent = intent.actions?.needsWorkflowGeneration || intent.type === 'workflow_generation';

    // For Nextflow workflows: we always generate when intent is clear.
    // We no longer gate on Galaxy tool search — Nextflow workflow DB is queried by backend directly.
    const hasEnoughTools = recommendedTools.length >= 1;

    return {
      shouldGenerate: hasWorkflowIntent,  // Always attempt if intent is workflow generation
      userIntent: message,
      confidence: hasWorkflowIntent ? (hasEnoughTools ? 0.9 : 0.8) : 0.1,
      reasoning: hasWorkflowIntent
        ? hasEnoughTools
          ? `Workflow intent detected with ${recommendedTools.length} tool(s) found`
          : 'Workflow intent detected — searching Nextflow workflow library'
        : `Intent type is "${intent.type}", no workflow generation needed`,
    };
  }

  /**
   * Generate workflow using Galaxy AI Assistant (Unified Architecture)
   *
   * This calls the unified /api/ai_assistant/generate_workflow endpoint which:
   * 1. Searches existing templates first (WorkflowSearchRAG)
   * 2. Routes based on confidence:
   *    - High (>0.8): Reuses template directly
   *    - Medium (0.5-0.8): Adapts template
   *    - Low (<0.5): Generates from scratch with tool constraint
   * 3. Always assigns domain knowledge datasets (HMDB, KEGG, etc.)
   */
  private async generateWorkflow(
    userIntent: string,
    datasets: BioMNIDataset[],
    inlineParameters?: Record<string, string>,
    context?: ChatContext
  ): Promise<any> {
    // Build context text for domain inference (active workflow + recent turns)
    const currentWorkflowText = String(
      context?.currentWorkflow?.workflowDefinition?.name ||
        context?.currentWorkflow?.workflowDefinition?.nextflow_path ||
        context?.currentWorkflow?.name ||
        context?.currentWorkflow?.nextflow_path ||
        ''
    );
    const recentContext = (context?.previousMessages || [])
      .slice(-2)
      .map((m) => String(m.content || ''))
      .join(' ');
    const fullContextForDomain = [userIntent, currentWorkflowText, recentContext]
      .filter(Boolean)
      .join(' | ');

    // LLM-based domain classification (Claude Haiku, cached per query)
    const domainHint = await this._inferDomainWithLLM(userIntent, currentWorkflowText || recentContext || undefined);
    const mergedInlineParameters = {
      ...(inlineParameters || {}),
      ...(domainHint ? { domain_hint: domainHint } : {}),
    };

    console.log('[GalaxyAssistant] ========================================');
    console.log('[GalaxyAssistant] Generating workflow using Unified AI');
    console.log('[GalaxyAssistant] User intent:', userIntent);
    console.log('[GalaxyAssistant] Available datasets:', datasets.length);
    console.log('[GalaxyAssistant] Inline parameters:', JSON.stringify(mergedInlineParameters));

    const response = await this.galaxyAPI.generateWorkflow({
      user_intent: userIntent,
      max_tools_search: 30,
      inline_parameters: mergedInlineParameters,
      datasets: datasets.map((d) => ({
        id: d.id,
        name: d.name,
        type: d.type || 'unknown',
      })),
    });

    if (response.success) {
      console.log('[GalaxyAssistant] ✅ Workflow generated successfully!');
      console.log('[GalaxyAssistant] Generation strategy:', response.source);
      console.log('[GalaxyAssistant] Confidence score:', response.confidence?.toFixed(2));
      console.log('[GalaxyAssistant] Template match:', response.template_match_score?.toFixed(2));
      console.log('[GalaxyAssistant] Datasets assigned:', response.datasets_assigned);
      console.log('[GalaxyAssistant] Generated parameters:', response.generated_parameters?.length || 0);
      console.log('[GalaxyAssistant] Message:', response.message);
      console.log('[GalaxyAssistant] ========================================');
    } else {
      console.error('[GalaxyAssistant] ❌ Workflow generation failed');
      console.error('[GalaxyAssistant] Error:', response.error);
      console.log('[GalaxyAssistant] ========================================');
    }

    return response;
  }

  /**
   * Generate natural language response
   */
  private async generateResponse(
    message: string,
    intent: any,
    tools: ToolRecommendation[],
    datasets: DatasetRecommendation[],
    workflowSuggestion: WorkflowSuggestion,
    generatedWorkflow: any,
    context: ChatContext,
    researchResponse?: any,
    benchmarkEvidence?: any,
    onResponseDelta?: (chunk: string) => void
  ): Promise<{ message: string; thinking?: ThinkingDetectionResult; truncated?: boolean }> {
    const lowerMessage = (message || '').toLowerCase();
    const isDrugDevelopmentQuery = /(drug|admet|herg|dili|toxicity|docking|ligand|pk|pharmacokinetic|nca|auc|cmax|tmax|half[- ]?life|clinical)/i.test(
      lowerMessage
    );
    const runnableWorkflow = !!(
      generatedWorkflow?.success &&
      !generatedWorkflow?.error &&
      (generatedWorkflow?.workflow_ga ||
       generatedWorkflow?.nextflow_path ||
       generatedWorkflow?.workflow_type === 'chain')
    );
    const workflowGenerationFailed = !!generatedWorkflow && !runnableWorkflow;
    const workflowFailureSignals = workflowGenerationFailed
      ? {
          error: generatedWorkflow?.error || null,
          message: generatedWorkflow?.message || null,
          source: generatedWorkflow?.source || null,
          confidence: generatedWorkflow?.confidence ?? null,
          templateMatchScore: generatedWorkflow?.template_match_score ?? null,
          validationIssues: generatedWorkflow?.validation?.issues || [],
          failedTools: generatedWorkflow?.tool_installation?.failed_tools || [],
        }
      : null;

    const isResearchIntent = !!researchResponse;
    const systemPrompt = isResearchIntent
      ? `You are BioMate, an expert bioinformatics AI assistant with deep scientific knowledge.

Your role:
- Provide accurate, evidence-based answers to scientific questions
- Cite specific papers using [N] inline notation matching the numbered reference list provided
- Only cite papers from the provided list — never fabricate citations
- Structure answers clearly with headings and bullet points
- End with a ## References section listing only the papers you cited`
      : `You are BioMate, an expert bioinformatics AI assistant.

Your capabilities:
- Access to 2,177 bioinformatics tools (real-time search)
- Access to 100+ GB BioMNI dataset catalog
- Workflow generation with automatic tool/dataset selection

IMPORTANT RULES:
- NEVER compute or calculate results yourself (e.g., reverse complement, sequence alignment, etc.)
- ALWAYS recommend running the appropriate BioMate tool or workflow instead
- If a runnable workflow was generated, explain it and encourage the user to click "Run"
- If workflow generation failed, explicitly explain likely reasons using available diagnostics and process outputs (error details, confidence, template match, tool/runtime signals)
- If workflow generation failed, collaborate with the user by asking targeted follow-up questions and proposing concrete next recovery actions
- If no workflow but tools were found, explain which tool to use and suggest creating a workflow
- Only provide direct answers for conceptual questions (e.g., "what is RNA-seq?")
- When the user requests a workflow but has NOT mentioned any dataset (no file path, S3 URI, SRA/GSE/EMBL/PXD accession, or specific data file), ask what data they have and its format/location BEFORE generating the workflow — do NOT generate a workflow with empty input fields. Exception: if the user explicitly requests a "demo", "test", or "mock" workflow, generate it without requiring data.
- When the message contains an "[Uploaded datasets: ...]" block, it means the user has already provided their input data via the file attachment button. Parse it: the format is "filename: dataset_id=<ID>, galaxy_dataset_id=<GALAXY_ID>". Use the galaxy_dataset_id values as the workflow input parameters (e.g. input_bam, reads, input_vcf). Do NOT ask the user for data again — proceed directly to workflow generation using those IDs.
- When the message contains an "[Attached files: ...]" block without a corresponding "[Uploaded datasets: ...]" block, the upload failed. Tell the user which files failed and ask them to try again.
${isDrugDevelopmentQuery ? `- For drug-development requests, provide decision-grade guidance: list concrete workflow phases, critical safety/quality gates, required inputs, and explicit next actions` : ''}
${isDrugDevelopmentQuery ? `- For drug-development failures, include at least TWO distinct blocker categories (e.g., tool gap, input gap, domain mismatch) and ask at least TWO targeted follow-up questions` : ''}

Style guide:
- Be concise and practical
- When mentioning tools, use the primary user-facing name (e.g. "CryoSPARC", "BWA-MEM2", "GATK") — never use internal pipeline paths or tool IDs
- Explain workflow steps and expected outputs clearly
- Do NOT include a "Next Steps After This Workflow" section — suggest follow-up steps only after the user confirms execution is complete
${isDrugDevelopmentQuery ? `- Use section labels when possible: "Workflow phases", "Decision gates", "Required inputs", and "Next step"` : ''}

Current context:
${tools.length > 0 ? `- Found ${tools.length} relevant tools` : ''}
${datasets.length > 0 ? `- Found ${datasets.length} relevant datasets` : ''}
${runnableWorkflow ? '- Runnable workflow generated successfully - user can click Run to execute' : ''}
${workflowGenerationFailed ? '- Workflow generation attempt failed and needs collaborative recovery' : ''}`;

    // Build research/benchmark context sections
    const researchSection = researchResponse
      ? `\nResearch Results:\n${JSON.stringify(researchResponse, null, 2).slice(0, 2000)}`
      : '';
    const benchmarkSection = benchmarkEvidence
      ? `\nBenchmark Evidence:\n${JSON.stringify(benchmarkEvidence, null, 2).slice(0, 2000)}`
      : '';

    const userPrompt = `User: ${message}

${tools.length > 0 ? `\nRelevant tools:\n${tools.map((t, i) => `${i + 1}. ${t.tool.name} - ${t.reasoning}`).join('\n')}` : ''}

${datasets.length > 0 ? `\nRelevant datasets:\n${datasets.map((d, i) => `${i + 1}. ${d.dataset.name} - ${d.reasoning}`).join('\n')}` : ''}

${runnableWorkflow ? '\nA runnable workflow has been generated and is ready to run.' : ''}
${workflowGenerationFailed ? `\nWorkflow generation diagnostics:\n${JSON.stringify(workflowFailureSignals, null, 2).slice(0, 1600)}` : ''}${researchSection}${benchmarkSection}

Provide a helpful response that:
1. ${runnableWorkflow ? 'Briefly describes the generated workflow (steps, inputs, expected outputs). Do NOT say "click Run" — the Run button is already visible in the workflow panel rendered separately' : workflowGenerationFailed ? 'Explains why generation likely failed using the provided diagnostics and context' : researchResponse ? 'Presents the research findings with inline [N] citations referencing the numbered list' : benchmarkEvidence ? 'Presents the benchmark comparison with evidence' : tools.length > 0 ? 'Recommends the relevant tool(s) and explains how they will help' : 'Explains what tools or data would be needed'}
2. ${tools.length > 0 ? 'References the specific tools found and their capabilities' : researchResponse ? 'Includes relevant citations and sources' : benchmarkEvidence ? 'Provides structured comparison data' : 'Suggests what the user could search for or ask about'}
3. ${runnableWorkflow ? 'Describes what output to expect after running' : workflowGenerationFailed ? 'Asks 2-4 targeted follow-up questions and gives a concrete recovery plan the user can confirm or edit' : researchResponse ? 'Ends with a ## References section listing only the papers cited (numbered, with authors, title, journal, year, and URL/DOI where available)' : 'Suggests creating a workflow to accomplish the task'}
4. ${isResearchIntent ? 'Focus on scientific accuracy — only cite papers from the provided list, never fabricate citations' : 'DO NOT compute or calculate any results yourself - always recommend using BioMate tools'}
${isDrugDevelopmentQuery && !isResearchIntent ? `
5. If drug-development related:
   - Include at least 2 concrete workflow phases (e.g., target prep, docking, ADMET, hERG, PK/NCA).
   - Include at least 1 decision gate/criterion (e.g., ranking/cutoff/risk flag) or explicitly state why criterion cannot be provided.
   - If generation fails, provide at least 2 blocker categories plus at least 2 follow-up questions.` : ''}`;

    try {
      // Convert context messages to Claude format (trim to recent turns for latency)
      const allPreviousMessages = context.previousMessages || [];
      const CONTEXT_WINDOW = 6;
      const compressionTriggered = allPreviousMessages.length > CONTEXT_WINDOW;
      const previousMessages = allPreviousMessages
        .slice(-CONTEXT_WINDOW)
        .map((msg) => ({
        role: msg.role as 'user' | 'assistant',
        content: msg.content,
      }));

      // C3 — When context is compressed, generate and store a session summary (fire-and-forget)
      if (compressionTriggered && (context.sessionId || context.userId)) {
        const compressedMessages = allPreviousMessages.slice(0, -CONTEXT_WINDOW);
        this._triggerSessionSummary(compressedMessages, context.userId, context.sessionId).catch(
          (err) => console.warn('[GalaxyAssistant] Session summary failed (non-fatal):', err)
        );
      }

      // Log what we're sending to Claude
      const apiStartTime = Date.now();
      const useThinking = this.modelConfig.enableThinking;
      console.log('[GalaxyAssistant] Response API request:', {
        model: this.modelConfig.responseModel,
        max_tokens: 4096,
        thinking_enabled: useThinking,
        thinking_budget: useThinking ? this.modelConfig.thinkingBudget : null,
        system_prompt_length: systemPrompt.length,
        user_prompt_length: userPrompt.length,
        previous_messages: previousMessages.length,
        total_input_chars: systemPrompt.length + userPrompt.length + previousMessages.reduce((acc, m) => acc + m.content.length, 0)
      });

      // Build API request options - thinking mode is optional
      const apiOptions: any = {
        model: this.modelConfig.responseModel,
        max_tokens: 4096,
        system: [
          {
            type: 'text',
            text: systemPrompt,
            cache_control: { type: 'ephemeral' },
          },
        ],
        messages: [...previousMessages, { role: 'user', content: userPrompt }],
      };

      // Add thinking mode if enabled (not compatible with temperature)
      if (useThinking) {
        apiOptions.thinking = {
          type: 'enabled',
          budget_tokens: this.modelConfig.thinkingBudget
        };
      } else {
        apiOptions.temperature = 0.7;
      }

      let rawResponse = '';
      let lastStopReason: string | null = null;
      if (onResponseDelta) {
        const stream = await this.claude.messages.create({
          ...apiOptions,
          stream: true,
        } as any);
        for await (const event of stream as any) {
          if (event?.type === 'content_block_delta' && event?.delta?.type === 'text_delta') {
            const text = String(event.delta.text || '');
            if (text) {
              rawResponse += text;
              onResponseDelta(text);
            }
          } else if (event?.type === 'message_stop') {
            lastStopReason = String(event?.message?.stop_reason || '');
          }
        }
        console.log('[GalaxyAssistant] Response stream complete:', {
          model: this.modelConfig.responseModel,
          time_ms: Date.now() - apiStartTime,
          stop_reason: lastStopReason,
          streamed_chars: rawResponse.length,
        });
      } else {
        const completion = await this.claude.messages.create(apiOptions);

        console.log('[GalaxyAssistant] Response API response:', {
          model: this.modelConfig.responseModel,
          time_ms: Date.now() - apiStartTime,
          usage: completion.usage,
          stop_reason: completion.stop_reason,
          content_blocks: completion.content.length
        });

        // Find the text content block (thinking mode returns [thinking, text])
        const textContent = completion.content.find(c => c.type === 'text');
        rawResponse = textContent && textContent.type === 'text' ? textContent.text : 'I can help you with that!';
      }

      // Detect and parse thinking content
      const thinkingResult = thinkingDetector.detectThinking(rawResponse);

      console.log('[GalaxyAssistant] Response generated with thinking:', {
        hasThinking: thinkingResult.hasThinking,
        thinkingLevel: thinkingResult.thinkingLevel,
        thinkingWords: thinkingResult.thinkingWordCount
      });

      const qualityEnforcedMessage = this.enforceDrugDevelopmentResponseQuality({
        userMessage: message,
        assistantMessage: thinkingResult.answerContent,
        runnableWorkflow,
        workflowGenerationFailed,
        workflowFailureSignals,
      });

      const wasTruncated = lastStopReason === 'max_tokens';
      return {
        message: qualityEnforcedMessage,
        thinking: thinkingResult.hasThinking ? thinkingResult : undefined,
        truncated: wasTruncated,
      };
    } catch (error) {
      console.error('[GalaxyAssistant] Response generation failed:', error);
      return {
        message: 'I found some relevant tools and datasets for your analysis. How would you like to proceed?'
      };
    }
  }

  private enforceDrugDevelopmentResponseQuality(params: {
    userMessage: string;
    assistantMessage: string;
    runnableWorkflow: boolean;
    workflowGenerationFailed: boolean;
    workflowFailureSignals: any;
  }): string {
    const { userMessage, assistantMessage, runnableWorkflow, workflowGenerationFailed, workflowFailureSignals } = params;
    const isDrugDevelopmentQuery = /(drug|admet|herg|dili|toxicity|docking|ligand|pk|pharmacokinetic|nca|auc|cmax|tmax|half[- ]?life|clinical)/i.test(
      userMessage || ''
    );
    if (!isDrugDevelopmentQuery) {
      return assistantMessage;
    }

    const text = assistantMessage || '';
    const lower = text.toLowerCase();
    const additions: string[] = [];

    const hasWorkflowPhases = /(workflow phases|phase|target prep|docking|admet|herg|pk\/nca|nca)/i.test(lower);
    const hasDecisionGates = /(decision gate|gating|cutoff|threshold|risk flag|go\/no-go|go-no-go)/i.test(lower);
    const hasRequiredInputs = /(required inputs|input files|you provide|input data)/i.test(lower);
    const hasNextStep = /(next step|next steps|confirm or edit|please confirm|follow-up)/i.test(lower);

    if (!hasWorkflowPhases) {
      additions.push(
        '### Workflow phases\n- Target/assay context and data intake\n- Core analysis phase (e.g., docking, ADMET, or PK/NCA)\n- QC/safety review and report handoff'
      );
    }
    if (!hasDecisionGates) {
      additions.push(
        '### Decision gates\n- Define explicit cutoffs/thresholds for risk ranking (for example: toxicity risk flag, hERG gate, or PK acceptability criteria)\n- Use these gates as go/no-go checkpoints before advancing candidates'
      );
    }
    if (!hasRequiredInputs) {
      additions.push(
        '### Required inputs\n- Input data files (e.g., structures/SMILES, assay data, or concentration-time table)\n- Basic study metadata (condition, units, and endpoint definitions)'
      );
    }
    if (!hasNextStep) {
      additions.push('### Next step\n- Confirm the intended analysis priority and upload the required inputs so I can produce a runnable, decision-ready workflow.');
    }

    if (workflowGenerationFailed) {
      const errorBlob = JSON.stringify(workflowFailureSignals || {}).toLowerCase();
      const hasToolGap = /(not found|missing|unavailable|failed_tools|none found|tool)/i.test(errorBlob);
      const hasInputGap = /(input|dataset|file|required)/i.test(errorBlob);
      const hasDomainMismatch = /(domain|alignment|incompatible|mismatch)/i.test(errorBlob);

      const blockers: string[] = [];
      blockers.push(hasToolGap ? '- Tool gap: one or more required capabilities are missing or unavailable in the current runtime.' : '- Tool gap: verify that required tools are installed and accessible.');
      blockers.push(hasInputGap ? '- Input gap: required input files/datasets are missing or not yet mapped for execution.' : '- Input gap: provide required input files and metadata before execution.');
      if (hasDomainMismatch || (!hasToolGap && !hasInputGap)) {
        blockers.push('- Domain mismatch: the requested combined workflow spans incompatible domains and should be split into staged workflows.');
      }

      if (!/why generation failed|workflow generation failed|blocked/i.test(lower)) {
        additions.push(`### Why generation failed\n${blockers.join('\n')}`);
      } else if (!/tool gap|input gap|domain mismatch|incompatible/i.test(lower)) {
        additions.push(`### Blocker categories\n${blockers.join('\n')}`);
      }

      if (!/follow-up questions|please answer|which analysis|what input|confirm or edit/i.test(lower)) {
        additions.push(
          '### Targeted follow-up questions\n1. Which analysis should be prioritized first (docking, ADMET, or PK/NCA)?\n2. What exact input files do you have now (format + example filenames)?'
        );
      }
    }

    if (additions.length === 0) {
      return text;
    }

    console.log('[GalaxyAssistant] Applied drug-development quality guard:', {
      additions: additions.length,
      runnableWorkflow,
      workflowGenerationFailed,
    });
    return `${text}\n\n${additions.join('\n\n')}`;
  }

  /**
   * Generate follow-up suggestions
   */
  private generateSuggestions(
    message: string,
    intent: any,
    tools: ToolRecommendation[],
    workflowSuggestion: WorkflowSuggestion
  ): string[] {
    const suggestions: string[] = [];

    if (workflowSuggestion.shouldGenerate && !workflowSuggestion.confidence) {
      suggestions.push('Generate a workflow for this analysis');
    }

    if (tools.length > 0) {
      suggestions.push('Tell me more about the recommended tools');
      suggestions.push('Show me alternative tools');
    }

    if (intent.type === 'workflow_generation') {
      suggestions.push('Customize the workflow parameters');
      suggestions.push('What data formats do I need?');
    } else if (intent.type === 'research_question') {
      suggestions.push('Search for related papers');
      suggestions.push('Build a workflow from these findings');
    } else if (intent.type === 'result_comparison') {
      suggestions.push('Show benchmark data');
      suggestions.push('Run a comparison workflow');
    } else if (intent.type === 'tool_search') {
      suggestions.push('Build a workflow with this tool');
      suggestions.push('Show me alternative tools');
    } else {
      suggestions.push('Build a workflow');
      suggestions.push('Search for tools');
    }

    return suggestions.slice(0, 4);
  }

  /**
   * C3 — When context is compressed (> CONTEXT_WINDOW messages), generate a 2-3 sentence
   * summary of the dropped messages using Claude Haiku and store it via the session-summary API.
   * This is always called fire-and-forget; errors are caught by the caller.
   */
  private async _triggerSessionSummary(
    compressedMessages: Array<{ role: 'user' | 'assistant'; content: string }>,
    userId?: number,
    sessionId?: string,
  ): Promise<void> {
    if (!compressedMessages.length) return;

    const historyText = compressedMessages
      .map((m) => `${m.role.toUpperCase()}: ${m.content}`)
      .join('\n')
      .slice(0, 4000); // Keep prompt compact for Haiku

    const summaryResp = await this.claude.messages.create({
      model: 'claude-haiku-4-5',
      max_tokens: 256,
      messages: [
        {
          role: 'user',
          content:
            `Summarize the following conversation in 2-3 sentences, focusing on what the user was trying to accomplish and any decisions made:\n\n${historyText}`,
        },
      ],
    });

    const summary =
      summaryResp.content[0]?.type === 'text' ? summaryResp.content[0].text.trim() : '';

    if (!summary) return;

    // POST to /api/memory/session-summary (non-blocking; this server calls Galaxy backend)
    const body = JSON.stringify({ summary, sessionId, userId });
    await fetch('http://localhost:8080/api/memory/session-summary', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body,
    }).catch((err) => {
      console.warn('[GalaxyAssistant] session-summary POST failed:', err.message);
    });

    console.log(
      `[GalaxyAssistant] Session summary stored for session=${sessionId}, compressed ${compressedMessages.length} messages`,
    );
  }
}
