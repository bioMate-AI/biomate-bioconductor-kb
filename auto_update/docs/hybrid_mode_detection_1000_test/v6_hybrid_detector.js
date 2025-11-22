/**
 * V6 HYBRID MODE DETECTOR - JavaScript Implementation
 *
 * Translated from TypeScript for testing purposes
 * Uses Anthropic SDK to analyze ambiguous queries
 */

const Anthropic = require('@anthropic-ai/sdk');

class HybridModeDetector {
  constructor(apiKey) {
    this.anthropic = new Anthropic({ apiKey });
    this.cache = new Map();
    this.systemPrompt = this.getSystemPrompt();

    // Statistics
    this.stats = {
      totalQueries: 0,
      fastRuleDecisions: 0,
      llmDecisions: 0,
      cacheHits: 0
    };
  }

  /**
   * Main entry point: Determine workflow mode using hybrid approach
   */
  async determineMode(query, context = {}) {
    this.stats.totalQueries++;

    // Stage 1: Try fast rules first
    const ruleDecision = this.applyFastRules(query, context);

    if (ruleDecision.confidence === 'HIGH') {
      // Obvious case - use rule decision
      this.stats.fastRuleDecisions++;
      return ruleDecision;
    }

    // Stage 2: Use LLM for ambiguous cases
    const llmDecision = await this.llmIntentAnalysis(query, context);
    this.stats.llmDecisions++;

    return llmDecision;
  }

  // ==========================================================================
  // STAGE 1: Fast Rule-Based Filtering
  // ==========================================================================

  /**
   * Fast rules for obvious cases (~60% coverage, <1ms, $0 cost)
   */
  applyFastRules(query, context = {}) {
    const lower = query.toLowerCase();

    // Rule 1: Obvious informational questions
    if (/^(what|how|why|when|where) (is|are|does|do|did|can|will)/i.test(query.trim())) {
      return {
        mode: 'legacy',
        confidence: 'HIGH',
        reason: 'Obvious informational question',
        method: 'fast_rule',
        intentType: 'informational_question'
      };
    }

    // Rule 2: Obvious modifications
    if (/modify|edit|change|update.*existing|adjust.*existing|my.*workflow|current workflow/i.test(query)) {
      return {
        mode: 'legacy',
        confidence: 'HIGH',
        reason: 'Modification of existing workflow',
        method: 'fast_rule',
        intentType: 'workflow_modification'
      };
    }

    // Rule 3: Very specific (tool + multiple parameters)
    const hasSpecificParams = /--[\w-]+|=[\w\.]+|-[a-z]\s+\w+|PAM\s+\w+|GRCh\d+|mm\d+|hg\d+/i.test(query);
    const hasSpecificTool = /(using|with)\s+(HISAT2|STAR|Kallisto|Salmon|DESeq2|edgeR|GATK4|Mutect2|Strelka2|FreeBayes|QIIME2|Kraken2|Seurat|Scanpy)/i.test(query);

    if (hasSpecificParams && hasSpecificTool) {
      return {
        mode: 'legacy',
        confidence: 'HIGH',
        reason: 'Very specific request with tool and parameters',
        method: 'fast_rule',
        intentType: 'workflow_generation'
      };
    }

    // Rule 4: Obvious comparisons
    if (/compare.*(and|vs|versus)|compare\s+\w+,\s+\w+/i.test(query)) {
      return {
        mode: 'iterative',
        confidence: 'HIGH',
        reason: 'Tool comparison requires clarification',
        method: 'fast_rule',
        intentType: 'tool_comparison'
      };
    }

    // Rule 5: Obvious help requests
    if (/(help me|not sure|don't know|don't understand|need guidance|need help|can you help)/i.test(query)) {
      return {
        mode: 'iterative',
        confidence: 'HIGH',
        reason: 'Explicit help request',
        method: 'fast_rule',
        intentType: 'help_request'
      };
    }

    // Rule 6: Continuing iterative session
    if (context.workflowMode === 'iterative' && context.sessionId) {
      return {
        mode: 'iterative',
        confidence: 'HIGH',
        reason: 'Continuing iterative session',
        method: 'fast_rule',
        intentType: 'session_continuation'
      };
    }

    // Rule 7: Multiple/various/several indicators
    if (/(multiple|several|various|different).*\b(tool|method|approach|option|way|file|sample|dataset)/i.test(query)) {
      return {
        mode: 'iterative',
        confidence: 'HIGH',
        reason: 'Multiple items require clarification',
        method: 'fast_rule',
        intentType: 'complex_multi_item'
      };
    }

    // Ambiguous - needs LLM analysis
    return {
      mode: 'legacy', // placeholder
      confidence: 'LOW',
      reason: 'Ambiguous - requires LLM analysis',
      method: 'fast_rule',
      intentType: 'ambiguous'
    };
  }

  // ==========================================================================
  // STAGE 2: LLM Intent Analysis
  // ==========================================================================

  /**
   * Use LLM for nuanced intent understanding (~40% coverage, ~500ms, ~$0.0001)
   */
  async llmIntentAnalysis(query, context = {}) {
    // Check cache first
    const cacheKey = this.getCacheKey(query, context);
    if (this.cache.has(cacheKey)) {
      this.stats.cacheHits++;
      return { ...this.cache.get(cacheKey), method: 'llm_analysis' };
    }

    try {
      // Build prompt with context
      const userPrompt = this.buildUserPrompt(query, context);

      // Call Claude with caching
      const response = await this.anthropic.messages.create({
        model: 'claude-sonnet-4-20250514',
        max_tokens: 300,
        system: [
          {
            type: 'text',
            text: this.systemPrompt,
            cache_control: { type: 'ephemeral' } // Cache system prompt
          }
        ],
        messages: [
          {
            role: 'user',
            content: userPrompt
          }
        ]
      });

      // Parse LLM response
      const decision = this.parseLLMResponse(response.content[0].text);

      // Cache result
      this.cache.set(cacheKey, decision);

      // Clean old cache entries (keep last 1000)
      if (this.cache.size > 1000) {
        const firstKey = this.cache.keys().next().value;
        this.cache.delete(firstKey);
      }

      return decision;

    } catch (error) {
      console.error('LLM analysis failed:', error.message);

      // Fallback to conservative iterative mode
      return {
        mode: 'iterative',
        confidence: 'LOW',
        reason: 'LLM analysis failed - defaulting to iterative for safety',
        method: 'llm_analysis'
      };
    }
  }

  /**
   * Build user prompt with context
   */
  buildUserPrompt(query, context = {}) {
    const expertise = context.expertise || 'unknown';
    const recentQueries = (context.recentQueries || []).slice(-3);

    return `Analyze this bioinformatics workflow request:

**Query:** "${query}"

**User Context:**
- Expertise Level: ${expertise}
- Recent Queries: ${recentQueries.length > 0 ? recentQueries.join('; ') : 'None'}
- Preferred Mode: ${context.preferredMode || 'None'}

**Determine the appropriate workflow mode:**

**Iterative Mode** - Use when:
- Query is complex or ambiguous
- User needs clarification or guidance
- Comparison or design decisions needed
- Exploration or optimization requested
- Beginner users (need more support)
- Verbs like: "design", "optimize", "compare", "explore", "help"

**Legacy Mode** - Use when:
- Query is simple and specific
- Clear tool and parameters provided
- Informational question
- Workflow modification
- Expert with clear intent
- Verbs like: "run", "quick", "modify", "standard with tool"

**Consider:**
1. Semantic meaning and verb intent
2. User expertise (beginners need more guidance)
3. Query completeness and specificity
4. Ambiguity and need for clarification
5. Session context and patterns

**Respond in JSON format:**
\`\`\`json
{
  "mode": "iterative" | "legacy",
  "confidence": 0.0-1.0,
  "reasoning": "brief explanation",
  "key_signals": ["signal1", "signal2", "signal3"]
}
\`\`\``;
  }

  /**
   * Get system prompt for LLM (cached for all requests)
   */
  getSystemPrompt() {
    return `You are an expert bioinformatics workflow intent classifier for Galaxy AI Assistant.

Your task is to determine whether a user query requires:
- **Iterative Mode**: Multi-step clarification dialog for complex/ambiguous requests
- **Legacy Mode**: Single-step workflow generation for clear/specific requests

# Classification Principles

## Iterative Mode Indicators
- **Ambiguity**: Unclear intent, missing information, vague phrasing
- **Complexity**: Multi-step workflows, design decisions, tool comparisons
- **Exploration**: "optimize", "design", "compare", "benchmark", "explore"
- **Help Requests**: "help me", "not sure", "which should I", "how do I"
- **Incomplete**: "I need to X for Y" without clear verb/tool
- **Expertise Context**: Beginners need guidance even for "simple" tasks

## Legacy Mode Indicators
- **Specificity**: Clear tool + parameters + data type
- **Informational**: "What is", "Explain", "Define" questions
- **Modification**: "Modify existing", "Update workflow", "Change parameters"
- **Execution**: "Run X with Y", "Quick Z using Tool", "Standard W"
- **Expert Clarity**: Expert users with specific, well-formed requests

## Important Nuances

### Expertise Context Matters
- **Beginner** + "Quick X with Tool" → Often iterative (needs help despite saying "quick")
- **Expert** + "Quick X with Tool" → Often legacy (knows exactly what they want)
- **Expert** + "Design/Optimize" → Iterative (wants to explore options)
- **Beginner** + "Standard workflow" → Legacy (wants defaults)
- **Expert** + "Standard workflow" → Could be iterative (wants to customize)

### Verb Semantics
- **Exploration verbs** → Iterative: optimize, design, compare, benchmark, explore, evaluate
- **Execution verbs** → Legacy: run, execute, quick, standard, modify, update
- **Ambiguous verbs** → Consider context: analyze, process, create, generate

### Phrasing Patterns
- **"I need to X for Y"** → Usually iterative (incomplete sentence, unclear action)
- **"I need to [run/use] X for Y"** → Legacy (clear action + tool)
- **"Generate standard X"** → Expertise-dependent
- **"Generate X workflow with Y tool"** → Legacy (specific)

## Response Format

You must respond with valid JSON only:

\`\`\`json
{
  "mode": "iterative" | "legacy",
  "confidence": 0.0-1.0,
  "reasoning": "Brief explanation focusing on key decision factors",
  "key_signals": ["signal1", "signal2", "signal3"]
}
\`\`\`

**Do not include any text outside the JSON block.**`;
  }

  /**
   * Parse LLM JSON response
   */
  parseLLMResponse(responseText) {
    try {
      // Extract JSON from markdown code block if present
      let jsonText = responseText.trim();
      const jsonMatch = jsonText.match(/```json\s*([\s\S]*?)\s*```/);
      if (jsonMatch) {
        jsonText = jsonMatch[1];
      }

      const data = JSON.parse(jsonText);

      // Validate required fields
      if (!data.mode || !['iterative', 'legacy'].includes(data.mode)) {
        throw new Error('Invalid mode in LLM response');
      }

      const confidence = data.confidence >= 0.8 ? 'HIGH' :
                        data.confidence >= 0.6 ? 'MEDIUM' : 'LOW';

      return {
        mode: data.mode,
        confidence,
        reason: data.reasoning || 'LLM analysis',
        method: 'llm_analysis',
        llmSignals: data.key_signals || []
      };

    } catch (error) {
      console.error('Failed to parse LLM response:', error.message);
      console.error('Response text:', responseText);

      // Fallback to conservative iterative
      return {
        mode: 'iterative',
        confidence: 'LOW',
        reason: 'Failed to parse LLM response - defaulting to iterative',
        method: 'llm_analysis'
      };
    }
  }

  /**
   * Generate cache key from query and context
   */
  getCacheKey(query, context = {}) {
    const expertise = context.expertise || 'unknown';
    const recentContext = (context.recentQueries || []).slice(-1)[0] || 'none';

    // Create deterministic cache key
    return `${query}:${expertise}:${recentContext}`;
  }

  /**
   * Get statistics
   */
  getStats() {
    return {
      ...this.stats,
      cacheHitRate: this.stats.llmDecisions > 0
        ? (this.stats.cacheHits / this.stats.llmDecisions * 100).toFixed(1) + '%'
        : '0%',
      fastRuleRate: this.stats.totalQueries > 0
        ? (this.stats.fastRuleDecisions / this.stats.totalQueries * 100).toFixed(1) + '%'
        : '0%',
      llmRate: this.stats.totalQueries > 0
        ? (this.stats.llmDecisions / this.stats.totalQueries * 100).toFixed(1) + '%'
        : '0%'
    };
  }

  /**
   * Clear cache
   */
  clearCache() {
    this.cache.clear();
  }
}

module.exports = { HybridModeDetector };
