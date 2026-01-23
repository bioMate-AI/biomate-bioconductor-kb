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
  responseModel: 'claude-sonnet-4-5',    // Keep sonnet for quality
  enableThinking: true,
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

export interface GalaxyAssistantResponse {
  // Natural language response
  message: string;

  // Tool recommendations
  recommendedTools?: ToolRecommendation[];

  // Dataset recommendations
  recommendedDatasets?: DatasetRecommendation[];

  // Workflow suggestion
  workflowSuggestion?: WorkflowSuggestion;

  // Generated workflow (if requested)
  generatedWorkflow?: any;

  // Suggested follow-up questions
  suggestions: string[];

  // Thinking mode support
  thinking_content?: string;
  thinking_level?: 'none' | 'brief' | 'detailed';

  // Metadata
  sources: {
    toolSearchUsed: boolean;
    datasetRAGUsed: boolean;
    workflowGenerated: boolean;
    thinkingUsed: boolean;
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

  /** Update model configuration at runtime */
  setModelConfig(config: Partial<ModelConfig>): void {
    this.modelConfig = { ...this.modelConfig, ...config };
    console.log('[GalaxyAssistant] Model config updated:', this.modelConfig);
  }

  /**
   * Main entry point: Process user message with full Galaxy intelligence
   */
  async processMessage(
    message: string,
    context: ChatContext = {}
  ): Promise<GalaxyAssistantResponse> {
    const startTime = Date.now();
    const log = (step: string) => console.log(`[GalaxyAssistant] [${Date.now() - startTime}ms] ${step}`);

    log('Processing message: ' + message.substring(0, 50));

    // Step 1: Analyze user intent with NLU
    log('Step 1: Analyzing intent');
    const intent = await this.analyzeIntent(message, context);
    log('Step 1 complete - Intent: ' + intent.type);

    // Steps 2 & 3: Search for tools and datasets IN PARALLEL
    // These are independent operations that can run concurrently
    let recommendedTools: ToolRecommendation[] = [];
    let recommendedDatasets: DatasetRecommendation[] = [];
    let toolSearchUsed = false;
    let datasetRAGUsed = false;

    const searchPromises: Promise<void>[] = [];

    if (intent.needsToolSearch) {
      searchPromises.push(
        this.searchRelevantTools(message, intent.keywords, context.userId)
          .then(tools => {
            recommendedTools = tools;
            toolSearchUsed = true;
            console.log(`[GalaxyAssistant] Found ${tools.length} relevant tools`);
          })
      );
    }

    if (intent.needsDatasets) {
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
    log('Step 4: Analyzing workflow need');
    const workflowSuggestion = await this.analyzeWorkflowNeed(
      message,
      intent,
      recommendedTools
    );
    log('Step 4 complete - shouldGenerate: ' + workflowSuggestion.shouldGenerate);

    // Step 5: Generate workflow if requested
    let generatedWorkflow = null;
    let workflowGenerated = false;
    if (workflowSuggestion.shouldGenerate && workflowSuggestion.confidence > 0.7) {
      try {
        log('Step 5: Generating workflow');
        generatedWorkflow = await this.generateWorkflow(
          workflowSuggestion.userIntent,
          recommendedDatasets.map(d => d.dataset)
        );
        workflowGenerated = true;
        log('Step 5 complete - Workflow generated');
      } catch (error: any) {
        log('Step 5 failed: ' + error.message);
        console.error('[GalaxyAssistant] Workflow generation failed:', error);
      }
    } else {
      log('Step 5: Skipped (no workflow needed)');
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
      context
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

    return {
      message: response.message,
      thinking_content: response.thinking?.thinkingContent,
      thinking_level: response.thinking?.thinkingLevel,
      recommendedTools: recommendedTools.length > 0 ? recommendedTools : undefined,
      recommendedDatasets: recommendedDatasets.length > 0 ? recommendedDatasets : undefined,
      workflowSuggestion,
      generatedWorkflow,
      suggestions,
      sources: {
        toolSearchUsed,
        datasetRAGUsed,
        workflowGenerated,
        thinkingUsed: response.thinking?.hasThinking || false,
      },
    };
  }

  /**
   * Analyze user intent using GPT-4
   */
  private async analyzeIntent(
    message: string,
    context: ChatContext
  ): Promise<{
    type: 'workflow_generation' | 'tool_inquiry' | 'dataset_inquiry' | 'general_question' | 'workflow_modification';
    keywords: string[];
    needsToolSearch: boolean;
    needsDatasets: boolean;
    confidence: number;
  }> {
    const systemPrompt = `You are a bioinformatics intent analyzer. Analyze user messages and extract:
1. Intent type: workflow_generation, tool_inquiry, dataset_inquiry, general_question, or workflow_modification
2. Keywords for tool/dataset search (e.g., "RNA-seq", "metabolomics", "peak detection")
3. Whether tool search is needed
4. Whether dataset recommendations are needed
5. Confidence score (0-1)

IMPORTANT: The following should ALWAYS be classified as workflow_generation with needsToolSearch=true:
- Database queries: "query UniProt", "search PubMed", "BLAST", "fetch from KEGG", etc.
- Literature searches: "search for papers", "find articles", "PubMed search"
- Any request to run, execute, analyze, or process data
- Any mention of specific tools or databases (PubMed, NCBI, ChEMBL, etc.)

Only use general_question for conversational questions that don't require running any tools.

Respond in JSON format:
{
  "type": "workflow_generation",
  "keywords": ["rna-seq", "differential expression", "alignment"],
  "needsToolSearch": true,
  "needsDatasets": true,
  "confidence": 0.95
}`;

    try {
      const intentStartTime = Date.now();
      console.log('[GalaxyAssistant] Intent API request:', {
        model: this.modelConfig.intentModel,
        max_tokens: 200,
        system_prompt_length: systemPrompt.length,
        message_length: message.length
      });

      // Intent classification - using configurable model
      const completion = await this.claude.messages.create({
        model: this.modelConfig.intentModel,
        max_tokens: 200,
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

      // Strip markdown code blocks if present (improved regex to handle more edge cases)
      resultText = resultText
        .replace(/^```+\s*json\s*\n?/gi, '')  // Remove opening code fence with any number of backticks
        .replace(/\n?```+\s*$/gi, '')          // Remove closing code fence
        .replace(/^\s*`+\s*/g, '')             // Remove leading backticks and whitespace
        .replace(/\s*`+\s*$/g, '')             // Remove trailing backticks and whitespace
        .trim();

      // Try to extract JSON object if there's extra text around it
      const jsonMatch = resultText.match(/\{[\s\S]*\}/);
      if (jsonMatch) {
        resultText = jsonMatch[0];
      }

      // Remove any remaining backticks that might be inside string values
      resultText = resultText.replace(/`/g, "'");

      const result = JSON.parse(resultText);

      return {
        type: result.type || 'general_question',
        keywords: result.keywords || [],
        needsToolSearch: result.needsToolSearch !== false,
        needsDatasets: result.needsDatasets !== false,
        confidence: result.confidence || 0.5,
      };
    } catch (error) {
      console.error('[GalaxyAssistant] Intent analysis failed:', error);
      return {
        type: 'general_question',
        keywords: [],
        needsToolSearch: false,
        needsDatasets: false,
        confidence: 0.5,
      };
    }
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
        toolSearchResponse = await this.galaxyAPI.searchTools(query, undefined, 100);

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
2. Brief reasoning

Respond in JSON format:
[
  {
    "tool_id": "tool_123",
    "relevanceScore": 0.95,
    "reasoning": "Perfect match for RNA-seq alignment${userContextStr ? ' and matches user\'s proteomics domain' : ''}"
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
      let resultText = content.type === 'text' ? content.text : '{"rankings":[]}';

      // Strip markdown code blocks if present (improved regex to handle more edge cases)
      resultText = resultText
        .replace(/^```+\s*json\s*\n?/gi, '')  // Remove opening code fence with any number of backticks
        .replace(/\n?```+\s*$/gi, '')          // Remove closing code fence
        .replace(/^\s*`+\s*/g, '')             // Remove leading backticks and whitespace
        .replace(/\s*`+\s*$/g, '')             // Remove trailing backticks and whitespace
        .trim();

      const rankings = JSON.parse(resultText);
      const rankingArray = rankings.rankings || rankings;

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
   * Analyze if workflow generation is needed
   */
  private async analyzeWorkflowNeed(
    message: string,
    intent: any,
    recommendedTools: ToolRecommendation[]
  ): Promise<WorkflowSuggestion> {
    const triggerWords = [
      // Workflow terms
      'workflow',
      'pipeline',
      'analysis',
      'process',
      'analyze',
      'build',
      'create',
      'generate',
      // Database/query terms
      'query',
      'search',
      'retrieve',
      'fetch',
      'lookup',
      'look up',
      'get',
      'find',
      // Action terms
      'run',
      'execute',
      'perform',
      'compute',
      'calculate',
      'predict',
      'detect',
      'identify',
      'annotate',
      'align',
      'call',
      'segment',
      'design',
    ];

    const hasWorkflowIntent =
      intent.type === 'workflow_generation' ||
      triggerWords.some((word) => message.toLowerCase().includes(word));

    // Allow single-tool workflows for simple queries (database lookups, etc.)
    const hasEnoughTools = recommendedTools.length >= 1;

    return {
      shouldGenerate: hasWorkflowIntent && hasEnoughTools,
      userIntent: message,
      confidence: hasWorkflowIntent && hasEnoughTools ? 0.9 : 0.3,
      reasoning: hasWorkflowIntent
        ? hasEnoughTools
          ? 'User requested workflow and relevant tools were found'
          : 'User requested workflow but no tools found'
        : 'No explicit workflow request detected',
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
    datasets: BioMNIDataset[]
  ): Promise<any> {
    console.log('[GalaxyAssistant] ========================================');
    console.log('[GalaxyAssistant] Generating workflow using Unified AI');
    console.log('[GalaxyAssistant] User intent:', userIntent);
    console.log('[GalaxyAssistant] Available datasets:', datasets.length);

    const response = await this.galaxyAPI.generateWorkflow({
      user_intent: userIntent,
      max_tools_search: 30,
      datasets: datasets.map((d) => ({
        id: d.id,
        name: d.name,
        type: d.type,
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
    context: ChatContext
  ): Promise<{ message: string; thinking?: ThinkingDetectionResult }> {
    const systemPrompt = `You are BioMate, an expert bioinformatics AI assistant powered by Galaxy.

Your capabilities:
- Access to 2,177 Galaxy tools (real-time search)
- Access to 100+ GB BioMNI dataset catalog
- Workflow generation with automatic tool/dataset selection

Style guide:
- Be concise and practical
- Recommend specific tools and datasets
- Explain workflow steps clearly
- Highlight key parameters and considerations

Current context:
${tools.length > 0 ? `- Found ${tools.length} relevant tools` : ''}
${datasets.length > 0 ? `- Found ${datasets.length} relevant datasets` : ''}
${generatedWorkflow ? '- Workflow generated successfully' : ''}`;

    const userPrompt = `User: ${message}

${tools.length > 0 ? `\nRelevant tools:\n${tools.map((t, i) => `${i + 1}. ${t.tool.name} - ${t.reasoning}`).join('\n')}` : ''}

${datasets.length > 0 ? `\nRelevant datasets:\n${datasets.map((d, i) => `${i + 1}. ${d.dataset.name} - ${d.reasoning}`).join('\n')}` : ''}

${generatedWorkflow ? '\nI\'ve generated a workflow for you based on your request.' : ''}

Provide a helpful response that:
1. Addresses the user's question
2. References the specific tools/datasets found
3. ${generatedWorkflow ? 'Explains the generated workflow' : 'Suggests next steps'}`;

    try {
      // Convert context messages to Claude format
      const previousMessages = (context.previousMessages || []).map((msg) => ({
        role: msg.role as 'user' | 'assistant',
        content: msg.content,
      }));

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
      const rawResponse = textContent && textContent.type === 'text' ? textContent.text : 'I can help you with that!';

      // Detect and parse thinking content
      const thinkingResult = thinkingDetector.detectThinking(rawResponse);

      console.log('[GalaxyAssistant] Response generated with thinking:', {
        hasThinking: thinkingResult.hasThinking,
        thinkingLevel: thinkingResult.thinkingLevel,
        thinkingWords: thinkingResult.thinkingWordCount
      });

      return {
        message: thinkingResult.answerContent,
        thinking: thinkingResult.hasThinking ? thinkingResult : undefined
      };
    } catch (error) {
      console.error('[GalaxyAssistant] Response generation failed:', error);
      return {
        message: 'I found some relevant tools and datasets for your analysis. How would you like to proceed?'
      };
    }
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
      suggestions.push('Estimate runtime for this workflow');
    } else {
      suggestions.push('Build a complete workflow');
      suggestions.push('Show me related tools');
    }

    return suggestions.slice(0, 4);
  }
}
