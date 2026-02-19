/**
 * User Patterns Service
 *
 * Fetches and caches user behavioral patterns from the backend API.
 * Used to personalize tool recommendations and workflow suggestions.
 */

export interface UserPattern {
  pattern_id: number;
  user_id: number;
  pattern_type: string;
  pattern_data: any;
  confidence: number;
  evidence_count: number;
}

export interface UserInsights {
  user_id: number;
  patterns: UserPattern[];
  dominant_domain: string | null;
  dominant_domain_confidence: number | null;
  preferred_tools: Array<{
    tool_id: string;
    for_task: string;
    confidence: number;
  }>;
  total_interactions: number;
}

export interface UserContext {
  domain_preference?: string;
  domain_confidence?: number;
  preferred_tools?: string[];
  expertise_level?: string;
  data_types?: string[];
}

export class UserPatternsService {
  private backendUrl: string;
  private apiKey: string;
  private cache: Map<number, { insights: UserInsights; timestamp: number }> = new Map();
  private cacheTTL = 5 * 60 * 1000; // 5 minutes

  constructor(backendUrl: string = 'http://localhost:8081', apiKey: string = '') {
    this.backendUrl = backendUrl;
    this.apiKey = apiKey;
  }

  /**
   * Fetch user insights from backend (with caching)
   */
  async getUserInsights(userId?: number): Promise<UserInsights | null> {
    // If no userId specified, we can't fetch patterns
    if (!userId) {
      return null;
    }

    // Check cache
    const cached = this.cache.get(userId);
    if (cached && Date.now() - cached.timestamp < this.cacheTTL) {
      console.log('[UserPatterns] Using cached insights for user', userId);
      return cached.insights;
    }

    try {
      console.log('[UserPatterns] Fetching insights from backend for user', userId);
      const response = await fetch(`${this.backendUrl}/api/user-patterns/insights`, {
        headers: {
          'x-api-key': this.apiKey,
          'Content-Type': 'application/json'
        }
      });

      if (!response.ok) {
        console.error('[UserPatterns] Failed to fetch insights:', response.status);
        return null;
      }

      const insights: UserInsights = await response.json();

      // Cache the result
      this.cache.set(userId, {
        insights,
        timestamp: Date.now()
      });

      console.log('[UserPatterns] Fetched insights:', {
        dominant_domain: insights.dominant_domain,
        confidence: insights.dominant_domain_confidence,
        preferred_tools: insights.preferred_tools?.map(t => t.tool_id) || [],
        patterns_count: insights.patterns?.length || 0
      });

      return insights;
    } catch (error) {
      console.error('[UserPatterns] Failed to fetch insights:', error);
      return null;
    }
  }

  /**
   * Convert user insights to search context
   */
  extractUserContext(insights: UserInsights | null): UserContext {
    if (!insights) {
      return {};
    }

    const context: UserContext = {};

    // Extract domain preference
    if (insights.dominant_domain && insights.dominant_domain_confidence) {
      context.domain_preference = insights.dominant_domain;
      context.domain_confidence = insights.dominant_domain_confidence;
    }

    // Extract preferred tools
    if (insights.preferred_tools && insights.preferred_tools.length > 0) {
      context.preferred_tools = insights.preferred_tools
        .filter(t => t.confidence >= 0.7)
        .map(t => t.tool_id);
    }

    // Extract expertise level from patterns
    const complexityPattern = insights.patterns?.find(
      p => p.pattern_type === 'complexity_level'
    );
    if (complexityPattern) {
      context.expertise_level =
        complexityPattern.pattern_data.inferred_level ||
        complexityPattern.pattern_data.prefers ||
        'intermediate';
    }

    // Extract data types
    const dataTypePatterns = insights.patterns?.filter(
      p => p.pattern_type === 'data_type_pattern'
    ) || [];
    if (dataTypePatterns.length > 0) {
      context.data_types = dataTypePatterns.map(
        p => p.pattern_data.type || p.pattern_data.data_type
      );
    }

    return context;
  }

  /**
   * Format user context for LLM prompt
   */
  formatContextForPrompt(context: UserContext): string {
    if (Object.keys(context).length === 0) {
      return '';
    }

    const parts: string[] = [];

    if (context.domain_preference && context.domain_confidence) {
      parts.push(
        `User's primary research domain: ${context.domain_preference} ` +
        `(confidence: ${(context.domain_confidence * 100).toFixed(0)}%)`
      );
    }

    if (context.preferred_tools && context.preferred_tools.length > 0) {
      parts.push(
        `User has successfully used: ${context.preferred_tools.join(', ')}`
      );
    }

    if (context.expertise_level) {
      parts.push(`User's inferred expertise level: ${context.expertise_level}`);
    }

    if (context.data_types && context.data_types.length > 0) {
      parts.push(`User typically works with: ${context.data_types.join(', ')} data`);
    }

    if (parts.length === 0) {
      return '';
    }

    return '\n\nUser Profile:\n' + parts.map(p => `- ${p}`).join('\n');
  }

  /**
   * Check if tool matches user preferences (for ranking boost)
   */
  matchesUserPreferences(toolId: string, context: UserContext): {
    matches: boolean;
    boostReason?: string;
  } {
    // Check if tool is in user's preferred tools
    if (context.preferred_tools?.includes(toolId)) {
      return {
        matches: true,
        boostReason: 'User has successfully used this tool before'
      };
    }

    // Check if tool's domain matches user's domain
    // (This would need tool metadata with domain info)

    return { matches: false };
  }

  /**
   * Log user interaction for pattern learning
   */
  async logInteraction(data: {
    interaction_type: string;
    query?: string;
    selected_tool_id?: string;
    selected_rank?: number;
    workflow_success?: number;
  }): Promise<boolean> {
    try {
      const response = await fetch(`${this.backendUrl}/api/users/interactions`, {
        method: 'POST',
        headers: {
          'x-api-key': this.apiKey,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify(data)
      });

      if (!response.ok) {
        console.error('[UserPatterns] Failed to log interaction:', response.status);
        return false;
      }

      console.log('[UserPatterns] Logged interaction:', data.interaction_type);
      return true;
    } catch (error) {
      console.error('[UserPatterns] Failed to log interaction:', error);
      return false;
    }
  }

  /**
   * Invalidate cache for a user (call after profile updates)
   */
  invalidateCache(userId: number): void {
    this.cache.delete(userId);
    console.log('[UserPatterns] Cache invalidated for user', userId);
  }

  /**
   * Clear all cached patterns
   */
  clearCache(): void {
    this.cache.clear();
    console.log('[UserPatterns] All cache cleared');
  }
}

// Export singleton instance (will be configured with real API key in server)
export const userPatternsService = new UserPatternsService();

/**
 * Initialize the service with configuration
 */
export function initializeUserPatternsService(
  backendUrl: string,
  apiKey: string
): void {
  userPatternsService['backendUrl'] = backendUrl;
  userPatternsService['apiKey'] = apiKey;
  console.log('[UserPatterns] Service initialized');
}
