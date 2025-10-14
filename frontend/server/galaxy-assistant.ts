/**
 * Galaxy Assistant Service
 *
 * Hybrid intelligence system combining:
 * - OpenAI GPT-4 for natural language understanding
 * - Galaxy Tool Search (2,177 indexed tools)
 * - BioMNI Dataset RAG (100+ GB data lake)
 * - Galaxy Workflow Generator (LLM-based with tool validation)
 *
 * Architecture:
 * User Query → NLU (GPT-4) → Tool Search + Dataset RAG → Workflow Generation
 */

import OpenAI from 'openai';
import { GalaxyAPIProxy } from './galaxy-api-proxy';
import type {
  GalaxyTool,
  BioMNIDataset,
  WorkflowGenerationRequest,
  WorkflowGenerationResponse,
} from '../../shared/galaxy-types';

export interface GalaxyAssistantOptions {
  openaiApiKey: string;
  galaxyAPIProxy: GalaxyAPIProxy;
}

export interface ChatContext {
  previousMessages?: Array<{ role: 'user' | 'assistant'; content: string }>;
  currentWorkflow?: any;
  selectedDatasets?: string[];
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

  // Metadata
  sources: {
    toolSearchUsed: boolean;
    datasetRAGUsed: boolean;
    workflowGenerated: boolean;
  };
}

export class GalaxyAssistant {
  private openai: OpenAI;
  private galaxyAPI: GalaxyAPIProxy;

  constructor(options: GalaxyAssistantOptions) {
    this.openai = new OpenAI({ apiKey: options.openaiApiKey });
    this.galaxyAPI = options.galaxyAPIProxy;
  }

  /**
   * Main entry point: Process user message with full Galaxy intelligence
   */
  async processMessage(
    message: string,
    context: ChatContext = {}
  ): Promise<GalaxyAssistantResponse> {
    console.log('[GalaxyAssistant] Processing message:', message);

    // Step 1: Analyze user intent with NLU
    const intent = await this.analyzeIntent(message, context);
    console.log('[GalaxyAssistant] Intent analysis:', intent);

    // Step 2: Search for relevant tools
    let recommendedTools: ToolRecommendation[] = [];
    let toolSearchUsed = false;
    if (intent.needsToolSearch) {
      recommendedTools = await this.searchRelevantTools(message, intent.keywords);
      toolSearchUsed = true;
      console.log(`[GalaxyAssistant] Found ${recommendedTools.length} relevant tools`);
    }

    // Step 3: Search for relevant datasets
    let recommendedDatasets: DatasetRecommendation[] = [];
    let datasetRAGUsed = false;
    if (intent.needsDatasets) {
      recommendedDatasets = await this.searchRelevantDatasets(message, intent.keywords);
      datasetRAGUsed = true;
      console.log(`[GalaxyAssistant] Found ${recommendedDatasets.length} relevant datasets`);
    }

    // Step 4: Determine if workflow generation is needed
    const workflowSuggestion = await this.analyzeWorkflowNeed(
      message,
      intent,
      recommendedTools
    );

    // Step 5: Generate workflow if requested
    let generatedWorkflow = null;
    let workflowGenerated = false;
    if (workflowSuggestion.shouldGenerate && workflowSuggestion.confidence > 0.7) {
      try {
        generatedWorkflow = await this.generateWorkflow(
          workflowSuggestion.userIntent,
          recommendedDatasets.map(d => d.dataset)
        );
        workflowGenerated = true;
        console.log('[GalaxyAssistant] Workflow generated successfully');
      } catch (error: any) {
        console.error('[GalaxyAssistant] Workflow generation failed:', error);
      }
    }

    // Step 6: Generate natural language response
    const response = await this.generateResponse(
      message,
      intent,
      recommendedTools,
      recommendedDatasets,
      workflowSuggestion,
      generatedWorkflow,
      context
    );

    // Step 7: Generate follow-up suggestions
    const suggestions = this.generateSuggestions(
      message,
      intent,
      recommendedTools,
      workflowSuggestion
    );

    return {
      message: response,
      recommendedTools: recommendedTools.length > 0 ? recommendedTools : undefined,
      recommendedDatasets: recommendedDatasets.length > 0 ? recommendedDatasets : undefined,
      workflowSuggestion,
      generatedWorkflow,
      suggestions,
      sources: {
        toolSearchUsed,
        datasetRAGUsed,
        workflowGenerated,
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

Respond in JSON format:
{
  "type": "workflow_generation",
  "keywords": ["rna-seq", "differential expression", "alignment"],
  "needsToolSearch": true,
  "needsDatasets": true,
  "confidence": 0.95
}`;

    try {
      const completion = await this.openai.chat.completions.create({
        model: 'gpt-4-turbo-preview',
        messages: [
          { role: 'system', content: systemPrompt },
          { role: 'user', content: message },
        ],
        response_format: { type: 'json_object' },
        max_tokens: 200,
        temperature: 0.3,
      });

      const result = JSON.parse(completion.choices[0]?.message?.content || '{}');
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
    keywords: string[]
  ): Promise<ToolRecommendation[]> {
    try {
      // Build search query from keywords
      const query = keywords.join(' OR ');
      console.log('[GalaxyAssistant] Tool search query:', query);

      // Search Galaxy tool index
      const toolSearchResponse = await this.galaxyAPI.searchTools(query, undefined, 10);

      if (!toolSearchResponse.success || !toolSearchResponse.tools) {
        return [];
      }

      // Use LLM to rank tools by relevance
      const rankedTools = await this.rankToolsByRelevance(
        userMessage,
        toolSearchResponse.tools
      );

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
    tools: GalaxyTool[]
  ): Promise<ToolRecommendation[]> {
    const systemPrompt = `You are a bioinformatics tool expert. Rank the provided tools by relevance to the user's request.
For each tool, provide:
1. Relevance score (0-1)
2. Brief reasoning

Respond in JSON format:
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
      const completion = await this.openai.chat.completions.create({
        model: 'gpt-4-turbo-preview',
        messages: [
          { role: 'system', content: systemPrompt },
          {
            role: 'user',
            content: `User request: ${userMessage}\n\nAvailable tools:\n${toolCatalog}`,
          },
        ],
        response_format: { type: 'json_object' },
        max_tokens: 500,
        temperature: 0.3,
      });

      const rankings = JSON.parse(completion.choices[0]?.message?.content || '{"rankings":[]}');
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
      'workflow',
      'pipeline',
      'analysis',
      'process',
      'analyze',
      'build',
      'create',
      'generate',
    ];

    const hasWorkflowIntent =
      intent.type === 'workflow_generation' ||
      triggerWords.some((word) => message.toLowerCase().includes(word));

    const hasEnoughTools = recommendedTools.length >= 2;

    return {
      shouldGenerate: hasWorkflowIntent && hasEnoughTools,
      userIntent: message,
      confidence: hasWorkflowIntent && hasEnoughTools ? 0.9 : 0.3,
      reasoning: hasWorkflowIntent
        ? hasEnoughTools
          ? 'User requested workflow and relevant tools were found'
          : 'User requested workflow but insufficient tools found'
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
  ): Promise<string> {
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
      const completion = await this.openai.chat.completions.create({
        model: 'gpt-4-turbo-preview',
        messages: [
          { role: 'system', content: systemPrompt },
          ...(context.previousMessages || []),
          { role: 'user', content: userPrompt },
        ],
        max_tokens: 600,
        temperature: 0.7,
      });

      return completion.choices[0]?.message?.content || 'I can help you with that!';
    } catch (error) {
      console.error('[GalaxyAssistant] Response generation failed:', error);
      return 'I found some relevant tools and datasets for your analysis. How would you like to proceed?';
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
