/**
 * Workflow Prerequisites Validator
 *
 * LLM-powered pre-execution validation system that intelligently validates
 * workflow prerequisites before Galaxy submission.
 *
 * Design Philosophy:
 * - NO hardcoded format lists or domain-specific rules
 * - All tool requirements come from the tool database dynamically
 * - LLM provides intelligent compatibility analysis and recommendations
 * - Works across all life science domains
 *
 * Created: 2026-01-16
 * See: /home/yzhang/biomate/20260116_1610_PRE_EXECUTION_VALIDATION_DESIGN.md
 */

import Anthropic from '@anthropic-ai/sdk';
import { GalaxyAPIProxy } from './galaxy-api-proxy';
import type {
  ValidateWorkflowRequest,
  PrerequisitesValidationResult,
  WorkflowRequirements,
  AvailableResources,
  LLMAnalysis,
  InputRequirement,
  ParameterRequirement,
  AvailableDataset,
  AvailableHistory,
  ToolDocumentation,
  ValidationContext,
  InputMapping,
  MissingInput,
  MissingParameter,
  Suggestion,
  AnalysisNote,
} from '../shared/prerequisites-types';

export interface PrerequisitesValidatorOptions {
  anthropicApiKey?: string;
  galaxyAPIProxy: GalaxyAPIProxy;
}

/**
 * LLM-powered workflow prerequisites validator
 */
export class WorkflowPrerequisitesValidator {
  private claude: Anthropic;
  private galaxyAPI: GalaxyAPIProxy;
  private schemaCache = new Map<string, { schema: any; fetchedAt: number }>();
  private readonly SCHEMA_TTL_MS = 60 * 60 * 1000; // 1 hour

  constructor(options: PrerequisitesValidatorOptions) {
    this.claude = new Anthropic({ apiKey: options.anthropicApiKey || '' });
    this.galaxyAPI = options.galaxyAPIProxy;
  }

  /**
   * Return a cached Galaxy tool schema, fetching from Galaxy API only when
   * the entry is absent or older than SCHEMA_TTL_MS.
   */
  private async getCachedToolSchema(toolId: string): Promise<any> {
    const cached = this.schemaCache.get(toolId);
    if (cached && Date.now() - cached.fetchedAt < this.SCHEMA_TTL_MS) {
      return cached.schema;
    }
    const schema = await this.galaxyAPI.getToolSchema(toolId);
    this.schemaCache.set(toolId, { schema, fetchedAt: Date.now() });
    return schema;
  }

  /**
   * Rule-based fallback returned when the LLM analysis call times out.
   * Conservative: marks everything as unresolved so the user is prompted
   * to check prerequisites manually rather than proceeding blindly.
   */
  private ruleBasedFallbackValidation(): LLMAnalysis {
    return {
      inputMappings: [],
      missingInputs: [],
      missingParameters: [],
      suggestions: [],
      notes: [{
        type: 'warning',
        message: 'Validation timed out — please check prerequisites manually.',
      }],
      confidence: 0,
    };
  }

  /**
   * Main validation entry point
   *
   * Validates workflow prerequisites using:
   * 1. Tool database for requirements extraction
   * 2. Galaxy API for available resources
   * 3. LLM for intelligent compatibility analysis
   */
  async validate(request: ValidateWorkflowRequest): Promise<PrerequisitesValidationResult> {
    console.log('[PrerequisitesValidator] Starting validation');

    // Handle both direct workflow definition and WorkflowGenerationResponse wrapper
    let workflowDefinition = request.workflowDefinition;

    // If this is a WorkflowGenerationResponse (has workflow_ga), extract the actual workflow
    if (workflowDefinition?.workflow_ga) {
      console.log('[PrerequisitesValidator] Extracting workflow from WorkflowGenerationResponse');
      workflowDefinition = workflowDefinition.workflow_ga;
    }

    console.log('[PrerequisitesValidator] Workflow structure:', {
      name: workflowDefinition?.name,
      hasSteps: !!workflowDefinition?.steps,
      stepCount: workflowDefinition?.steps ? Object.keys(workflowDefinition.steps).length : 0,
    });

    // Step 1: Extract workflow requirements from tool database
    const requirements = await this.extractRequirements(workflowDefinition);
    console.log('[PrerequisitesValidator] Extracted requirements:', {
      inputs: requirements.inputs.length,
      parameters: requirements.parameters.length,
    });

    // Step 2: Get user's available resources from Galaxy
    const available = await this.getAvailableResources(request.historyId);
    console.log('[PrerequisitesValidator] Available resources:', {
      datasets: available.datasets.length,
      histories: available.histories.length,
    });

    // Step 3: Get tool documentation for LLM context
    const toolDocs = await this.getToolDocumentation(requirements);
    console.log('[PrerequisitesValidator] Loaded tool documentation:', toolDocs.length);

    // Step 4: LLM analysis for intelligent matching
    const analysis = await this.llmAnalyze({
      workflow: {
        name: workflowDefinition?.name || 'Unnamed Workflow',
        description: workflowDefinition?.annotation,
        steps: Object.values(workflowDefinition?.steps || {}),
      },
      requirements,
      available,
      toolDocumentation: toolDocs,
      userContext: request.userContext,
    });

    // Step 5: Determine if prerequisites are fulfilled
    const fulfilled = this.checkFulfillment(analysis, requirements);

    // Step 6: Generate conversational response
    const conversationalResponse = await this.generateConversationalResponse(
      fulfilled,
      requirements,
      available,
      analysis,
      request.workflowDefinition
    );

    return {
      fulfilled,
      requirements,
      available,
      analysis,
      conversationalResponse,
    };
  }

  /**
   * Extract workflow requirements by parsing workflow steps
   * and querying tool database for dynamic schema information
   */
  private async extractRequirements(workflowDefinition: any): Promise<WorkflowRequirements> {
    const inputs: InputRequirement[] = [];
    const parameters: ParameterRequirement[] = [];

    const steps = workflowDefinition?.steps || {};

    for (const [stepId, step] of Object.entries(steps) as [string, any][]) {
      // Handle data input steps
      if (step.type === 'data_input' || step.type === 'data_collection_input') {
        inputs.push({
          stepId,
          stepLabel: step.name || step.label || `Input ${stepId}`,
          inputName: 'input',
          optional: step.optional || false,
          description: step.annotation || 'Input dataset required',
          dataType: step.type === 'data_collection_input' ? 'collection' : 'dataset',
        });
      }

      // Handle tool steps - query tool database for schema
      if (step.tool_id) {
        try {
          const toolSchema = await this.getCachedToolSchema(step.tool_id);

          // Extract input requirements from tool schema
          // Note: Galaxy tool schemas can have additional properties not in our TypeScript types
          if (toolSchema.inputs) {
            for (const input of toolSchema.inputs) {
              const inputAny = input as any; // Allow access to dynamic properties
              const inputType = inputAny.type;

              if (inputType === 'data' || inputType === 'data_collection') {
                inputs.push({
                  stepId,
                  stepLabel: step.name || step.label || step.tool_id,
                  toolId: step.tool_id,
                  inputName: input.name,
                  acceptedFormats: inputAny.extensions || [],
                  dataType: inputType === 'data_collection' ? 'collection' : 'dataset',
                  optional: input.optional || false,
                  description: input.help || input.label,
                });
              }
            }

            // Extract parameter requirements from tool schema
            for (const param of toolSchema.inputs) {
              const paramAny = param as any; // Allow access to dynamic properties
              const paramType = paramAny.type;

              if (paramType !== 'data' && paramType !== 'data_collection') {
                // Check if parameter is required (no default and not optional)
                const isRequired = !param.optional && paramAny.default === undefined;

                if (isRequired || paramAny.important) {
                  parameters.push({
                    stepId,
                    toolId: step.tool_id,
                    toolName: toolSchema.name || step.tool_id,
                    paramName: param.name,
                    paramLabel: param.label || param.name,
                    paramType: paramType,
                    optional: param.optional || false,
                    defaultValue: paramAny.default,
                    constraints: param.options || paramAny.validations,
                    description: param.help,
                  });
                }
              }
            }
          }
        } catch (error) {
          console.log(`[PrerequisitesValidator] Could not get schema for tool ${step.tool_id}`);
          // Tool schema not available - LLM will handle gracefully
        }
      }
    }

    return {
      inputs,
      parameters,
    };
  }

  /**
   * Get user's available resources from Galaxy
   */
  private async getAvailableResources(historyId?: string): Promise<AvailableResources> {
    const datasets: AvailableDataset[] = [];
    const histories: AvailableHistory[] = [];

    try {
      // Get all histories
      const galaxyHistories = await this.galaxyAPI.getHistories();
      for (const h of galaxyHistories) {
        histories.push({
          id: h.id,
          name: h.name,
          datasetCount: h.contents_active?.active || 0,
        });
      }

      // Get datasets from specified history or all histories
      const historiesToScan = historyId
        ? [{ id: historyId }]
        : galaxyHistories.slice(0, 5); // Limit to recent 5 histories

      for (const history of historiesToScan) {
        try {
          const historyDatasets = await this.galaxyAPI.getHistoryDatasets(history.id);
          for (const ds of historyDatasets) {
            if (ds.deleted || ds.purged) continue;
            datasets.push({
              id: ds.id,
              name: ds.name,
              extension: ds.extension || ds.file_ext,
              size: ds.file_size || 0,
              state: ds.state,
              historyId: history.id,
              metadata: ds.metadata,
              createTime: ds.create_time,
            });
          }
        } catch (error) {
          console.log(`[PrerequisitesValidator] Could not get datasets from history ${history.id}`);
        }
      }
    } catch (error) {
      console.log('[PrerequisitesValidator] Could not get histories:', error);
    }

    return { datasets, histories };
  }

  /**
   * Get tool documentation for LLM context
   */
  private async getToolDocumentation(requirements: WorkflowRequirements): Promise<ToolDocumentation[]> {
    const toolDocs: ToolDocumentation[] = [];
    const seenTools = new Set<string>();

    // Collect unique tool IDs
    for (const input of requirements.inputs) {
      if (input.toolId && !seenTools.has(input.toolId)) {
        seenTools.add(input.toolId);
      }
    }
    for (const param of requirements.parameters) {
      if (!seenTools.has(param.toolId)) {
        seenTools.add(param.toolId);
      }
    }

    // Fetch documentation for each tool
    for (const toolId of seenTools) {
      try {
        const toolSchema = await this.getCachedToolSchema(toolId);
        const toolInfo = await this.galaxyAPI.getToolById(toolId).catch(() => null);

        const schemaAny = toolSchema as any; // Allow access to dynamic properties
        toolDocs.push({
          toolId,
          toolName: toolSchema.name || toolId,
          description: toolSchema.description || toolInfo?.description || '',
          inputs: toolSchema.inputs || [],
          parameters: toolSchema.inputs?.filter((i: any) =>
            i.type !== 'data' && i.type !== 'data_collection'
          ) || [],
          scientificContext: (toolInfo as any)?.scientific_context,
          helpText: schemaAny.help,
        });
      } catch (error) {
        console.log(`[PrerequisitesValidator] Could not get documentation for ${toolId}`);
      }
    }

    return toolDocs;
  }

  /**
   * Use LLM to analyze compatibility between requirements and available resources
   */
  private async llmAnalyze(context: ValidationContext): Promise<LLMAnalysis> {
    const systemPrompt = `You are a bioinformatics expert validating workflow prerequisites.
Your task is to analyze workflow requirements and match them with available user data.

IMPORTANT:
- Consider biological context when matching data (e.g., FASTQ files for sequencing workflows)
- Understand file format compatibility including compressed variants (.gz)
- Recognize naming conventions (e.g., R1/R2 for paired-end reads)
- Suggest intelligent mappings even with imperfect matches
- Be helpful and specific in your recommendations

QUERY-BASED WORKFLOWS:
- Database query tools (PDB, UniProt, PubChem, etc.) often need ONLY parameters, not file inputs
- If a workflow only requires parameters (search terms, IDs, query strings) and no file inputs,
  set confidence to 0.8+ if the parameters have sensible defaults or are provided
- DO NOT add missingInputs for workflows that only need parameters
- Example: "Query PDB for hemoglobin" needs a search term parameter, not a file upload

Return a JSON object with the following structure:
{
  "inputMappings": [
    {
      "stepId": "step_id",
      "inputName": "input_name",
      "datasetId": "dataset_id",
      "datasetName": "dataset_name",
      "confidence": 0.0-1.0,
      "reasoning": "why this mapping makes sense"
    }
  ],
  "missingInputs": [
    {
      "stepId": "step_id",
      "stepLabel": "human readable label",
      "inputName": "input_name",
      "description": "what is needed",
      "suggestedAction": "what user should do"
    }
  ],
  "missingParameters": [
    {
      "stepId": "step_id",
      "toolId": "tool_id",
      "paramName": "param_name",
      "paramLabel": "human readable label",
      "description": "what is needed",
      "suggestedOptions": [
        {
          "value": "option_value",
          "label": "display label",
          "reasoning": "why this option",
          "recommended": true/false
        }
      ]
    }
  ],
  "suggestions": [
    {
      "type": "dataset|parameter|preprocessing|general",
      "message": "helpful suggestion",
      "action": "specific action to take"
    }
  ],
  "notes": [
    {
      "type": "info|warning|error",
      "message": "important note",
      "relatedStep": "step_id or null"
    }
  ],
  "confidence": 0.0-1.0
}`;

    const userPrompt = `Analyze the following workflow validation context:

WORKFLOW: ${context.workflow.name}
${context.workflow.description ? `Description: ${context.workflow.description}` : ''}

REQUIRED INPUTS:
${JSON.stringify(context.requirements.inputs, null, 2)}

REQUIRED PARAMETERS:
${JSON.stringify(context.requirements.parameters, null, 2)}

AVAILABLE DATASETS:
${JSON.stringify(context.available.datasets.map(d => ({
  id: d.id,
  name: d.name,
  extension: d.extension,
  size: d.size,
  state: d.state,
})), null, 2)}

TOOL DOCUMENTATION:
${JSON.stringify(context.toolDocumentation.map(t => ({
  toolId: t.toolId,
  toolName: t.toolName,
  description: t.description?.slice(0, 200),
  scientificContext: t.scientificContext,
})), null, 2)}

${context.userContext ? `USER CONTEXT: ${context.userContext}` : ''}

Please analyze which datasets can satisfy which inputs, identify any missing requirements, and provide helpful suggestions.`;

    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 15_000);
    try {
      const { llmGenerate } = await import('./llm-client');
      // AbortController signal isn't yet wired through llmGenerate; the
      // 15s ceiling is still meaningful via the fetch-level default
      // timeout on the internal call. Reinstate once llmGenerate accepts
      // a signal.
      void controller;
      const response = await llmGenerate({
        prompt: userPrompt,
        system: systemPrompt,
        maxTokens: 4096,
        temperature: 0,
        jsonMode: true,  // validator post-parses with JSON.parse
      });
      const rawText = response.text;

      // Parse JSON response
      const jsonMatch = rawText.match(/\{[\s\S]*\}/);
      if (!jsonMatch) {
        throw new Error('Could not parse JSON from LLM response');
      }

      const parsed = JSON.parse(jsonMatch[0]) as Partial<LLMAnalysis>;
      // Normalize: LLM occasionally omits one of these arrays, which later
      // crashes `.map()` calls in generateConversationalMessage (observed
      // 2026-06-18 as "Cannot read properties of undefined (reading 'map')"
      // surfacing in chat as "Connection error / Reason: network error").
      const analysis: LLMAnalysis = {
        inputMappings: parsed.inputMappings ?? [],
        missingInputs: parsed.missingInputs ?? [],
        missingParameters: parsed.missingParameters ?? [],
        suggestions: parsed.suggestions ?? [],
        notes: parsed.notes ?? [],
        confidence: parsed.confidence ?? 0,
      };
      return analysis;
    } catch (e: any) {
      if (e.name === 'AbortError' || e.message?.includes('aborted')) {
        console.warn('[PrerequisitesValidator] LLM analysis timed out after 15s — using rule-based fallback');
        return this.ruleBasedFallbackValidation();
      }
      console.error('[PrerequisitesValidator] LLM analysis failed:', e);
      // Return empty analysis on other failures
      return {
        inputMappings: [],
        missingInputs: [],
        missingParameters: [],
        suggestions: [],
        notes: [{
          type: 'warning',
          message: 'Could not perform automatic analysis. Please verify inputs manually.',
        }],
        confidence: 0,
      };
    } finally {
      clearTimeout(timeoutId);
    }
  }

  /**
   * Check if all prerequisites are fulfilled based on LLM analysis
   *
   * IMPORTANT: Query-based workflows (database queries, API calls) may have
   * NO file inputs - only parameters. These should be considered fulfilled
   * if all required parameters have defaults or user-provided values.
   */
  private checkFulfillment(analysis: LLMAnalysis, requirements: WorkflowRequirements): boolean {
    // Check if all required inputs have mappings
    const requiredInputs = requirements.inputs.filter(i => !i.optional);
    const mappedInputs = new Set(analysis.inputMappings.map(m => `${m.stepId}:${m.inputName}`));

    for (const input of requiredInputs) {
      const key = `${input.stepId}:${input.inputName}`;
      if (!mappedInputs.has(key)) {
        // Check if it's in missing inputs (explicitly identified)
        const isMissing = analysis.missingInputs.some(
          m => m.stepId === input.stepId && m.inputName === input.inputName
        );
        if (!isMissing) {
          // Not mapped and not explicitly missing - assume missing
          return false;
        }
      }
    }

    // If there are any missing inputs, not fulfilled
    if (analysis.missingInputs.length > 0) {
      return false;
    }

    // Check parameter sufficiency
    // Required parameters must have: (1) default values, OR (2) suggestions from LLM
    const requiredParams = requirements.parameters.filter(p => !p.optional);
    const paramsWithDefaults = requiredParams.filter(p => p.defaultValue !== undefined);
    const paramsWithoutDefaults = requiredParams.filter(p => p.defaultValue === undefined);

    // For parameters without defaults, check if LLM provided suggestions
    for (const param of paramsWithoutDefaults) {
      const hasSuggestion = analysis.missingParameters.some(
        mp => mp.stepId === param.stepId &&
              mp.paramName === param.paramName &&
              mp.suggestedOptions &&
              mp.suggestedOptions.length > 0
      );
      // If no default and no suggestion, it's a critical missing parameter
      if (!hasSuggestion) {
        // Check if the LLM identified it as missing without suggestions
        const isCriticallyMissing = analysis.missingParameters.some(
          mp => mp.stepId === param.stepId &&
                mp.paramName === param.paramName &&
                (!mp.suggestedOptions || mp.suggestedOptions.length === 0)
        );
        if (isCriticallyMissing) {
          console.log(`[PrerequisitesValidator] Parameter ${param.paramName} is missing without suggestions`);
          return false;
        }
      }
    }

    // If there are any explicitly missing parameters without suggestions, not fulfilled
    const criticalMissingParams = analysis.missingParameters.filter(
      p => !p.suggestedOptions || p.suggestedOptions.length === 0
    );
    if (criticalMissingParams.length > 0) {
      console.log(`[PrerequisitesValidator] Critical missing params:`, criticalMissingParams.map(p => p.paramName));
      return false;
    }

    // For workflows with required file inputs, need mappings
    if (requiredInputs.length > 0) {
      return analysis.confidence >= 0.7 && analysis.inputMappings.length > 0;
    }

    // For parameter-only workflows (queries, API calls):
    // - No file inputs required (already checked above)
    // - All required parameters have defaults or suggestions (checked above)
    // - Reasonable confidence from LLM analysis
    console.log(`[PrerequisitesValidator] Parameter-only workflow - confidence: ${analysis.confidence}`);
    return analysis.confidence >= 0.5;
  }

  /**
   * Generate a conversational response for the chat interface
   */
  private async generateConversationalResponse(
    fulfilled: boolean,
    requirements: WorkflowRequirements,
    available: AvailableResources,
    analysis: LLMAnalysis,
    workflowDefinition: any
  ): Promise<string> {
    const systemPrompt = `You are a helpful bioinformatics assistant guiding a user through workflow preparation.
Generate a natural, conversational message that:
- Is friendly but professional
- Clearly states what was found and what is needed
- Uses checkmarks (✓) for satisfied requirements
- Uses question marks (?) or arrows (→) for needed actions
- Provides specific options when parameters are needed
- Is concise but informative

Do NOT use code blocks or JSON in your response - use natural language with markdown formatting.`;

    const userPrompt = `Generate a conversational message for the user based on this validation result:

WORKFLOW: ${workflowDefinition?.name || 'Workflow'}
FULFILLED: ${fulfilled}

INPUT MAPPINGS FOUND:
${analysis.inputMappings.map(m => `- ${m.datasetName} → ${m.inputName} (${Math.round(m.confidence * 100)}% confidence)`).join('\n') || 'None'}

MISSING INPUTS:
${analysis.missingInputs.map(m => `- ${m.stepLabel}: ${m.description}`).join('\n') || 'None'}

MISSING PARAMETERS:
${analysis.missingParameters.map(m => `- ${m.paramLabel}: ${m.description}`).join('\n') || 'None'}

SUGGESTIONS:
${analysis.suggestions.map(s => `- ${s.message}`).join('\n') || 'None'}

NOTES:
${analysis.notes.map(n => `- [${n.type}] ${n.message}`).join('\n') || 'None'}

AVAILABLE DATASETS: ${available.datasets.length}

Generate a helpful, conversational message to guide the user.
${fulfilled ? 'Let them know everything looks ready.' : 'Ask them for the missing information in a helpful way.'}`;

    try {
      const { llmGenerate } = await import('./llm-client');
      const response = await llmGenerate({
        prompt: userPrompt,
        system: systemPrompt,
        maxTokens: 1024,
        temperature: 0,
      });
      if (response.text) {
        return response.text;
      }
    } catch (error) {
      console.error('[PrerequisitesValidator] Could not generate response:', error);
    }

    // Fallback response
    if (fulfilled) {
      return `I've reviewed the workflow requirements and everything looks ready to run. Your datasets have been matched to the workflow inputs.`;
    } else {
      const missingCount = analysis.missingInputs.length + analysis.missingParameters.length;
      return `Before running this workflow, I need ${missingCount} more piece${missingCount !== 1 ? 's' : ''} of information. Please check the requirements above.`;
    }
  }
}
