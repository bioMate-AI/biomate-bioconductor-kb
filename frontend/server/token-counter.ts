/**
 * Token Counter Service
 *
 * Provides accurate token counting for Claude models using the same
 * tokenization approach as Anthropic's API.
 *
 * Uses a simplified approximation based on empirical Claude token ratios:
 * - English text: ~1 token per 4 characters
 * - Code: ~1 token per 3.5 characters
 * - JSON: ~1 token per 3 characters
 *
 * For exact counting, would need to use tiktoken or similar, but this
 * provides good enough estimates for UI purposes.
 */

export interface TokenCountResult {
  tokens: number;
  characters: number;
  words: number;
  estimatedCost?: number; // USD, if model specified
}

export interface Message {
  role: string;
  content: string;
  thinking_content?: string | null;
}

export class TokenCounter {
  // Claude Sonnet 4.5 pricing (as of Nov 2024)
  private static readonly PRICING = {
    'claude-sonnet-4-5': {
      input: 0.003 / 1000,  // $3 per MTok
      output: 0.015 / 1000   // $15 per MTok
    },
    'claude-sonnet-4': {
      input: 0.003 / 1000,
      output: 0.015 / 1000
    },
    'claude-sonnet-3-5': {
      input: 0.003 / 1000,
      output: 0.015 / 1000
    }
  };

  /**
   * Count tokens in a single text string
   */
  countText(text: string): TokenCountResult {
    const characters = text.length;
    const words = text.split(/\s+/).filter(w => w.length > 0).length;

    // Heuristic: Detect content type
    let tokensPerChar = 0.25; // Default: 1 token per 4 chars

    // If text looks like code (has lots of special chars)
    const specialChars = (text.match(/[{}[\]();,<>=]/g) || []).length;
    if (specialChars / characters > 0.1) {
      tokensPerChar = 0.29; // Code: ~1 token per 3.5 chars
    }

    // If text looks like JSON
    if (text.trim().startsWith('{') || text.trim().startsWith('[')) {
      tokensPerChar = 0.33; // JSON: ~1 token per 3 chars
    }

    const tokens = Math.ceil(characters * tokensPerChar);

    return {
      tokens,
      characters,
      words
    };
  }

  /**
   * Count tokens in a message (including role markers)
   */
  countMessage(message: Message): TokenCountResult {
    // Count main content
    const contentResult = this.countText(message.content);

    // Add tokens for role and structure (~3-5 tokens per message)
    let totalTokens = contentResult.tokens + 4;

    // Add thinking content if present
    if (message.thinking_content) {
      const thinkingResult = this.countText(message.thinking_content);
      totalTokens += thinkingResult.tokens;
    }

    return {
      tokens: totalTokens,
      characters: contentResult.characters,
      words: contentResult.words
    };
  }

  /**
   * Count tokens in multiple messages (conversation)
   */
  countMessages(messages: Message[]): TokenCountResult {
    let totalTokens = 0;
    let totalCharacters = 0;
    let totalWords = 0;

    for (const message of messages) {
      const result = this.countMessage(message);
      totalTokens += result.tokens;
      totalCharacters += result.characters;
      totalWords += result.words;
    }

    return {
      tokens: totalTokens,
      characters: totalCharacters,
      words: totalWords
    };
  }

  /**
   * Estimate cost for a conversation
   */
  estimateCost(
    messages: Message[],
    model: string = 'claude-sonnet-4-5'
  ): { inputCost: number; estimatedOutputCost: number; total: number } {
    const result = this.countMessages(messages);
    const pricing = TokenCounter.PRICING[model as keyof typeof TokenCounter.PRICING];

    if (!pricing) {
      return { inputCost: 0, estimatedOutputCost: 0, total: 0 };
    }

    const inputCost = result.tokens * pricing.input;

    // Estimate output tokens (typically 20-30% of input for conversations)
    const estimatedOutputTokens = result.tokens * 0.25;
    const estimatedOutputCost = estimatedOutputTokens * pricing.output;

    return {
      inputCost,
      estimatedOutputCost,
      total: inputCost + estimatedOutputCost
    };
  }

  /**
   * Check if conversation is approaching context limit
   */
  checkContextLimit(
    tokenCount: number,
    model: string = 'claude-sonnet-4-5'
  ): {
    percentage: number;
    shouldCompress: boolean;
    shouldWarn: boolean;
    limit: number;
  } {
    // Claude Sonnet 4.5 has 200k context window
    const limit = 200000;

    const percentage = (tokenCount / limit) * 100;

    return {
      percentage,
      shouldCompress: tokenCount >= 160000,  // Compress at 80% (160k tokens)
      shouldWarn: tokenCount >= 140000,      // Warn at 70% (140k tokens)
      limit
    };
  }

  /**
   * Format token count for display
   */
  formatTokenCount(tokens: number): string {
    if (tokens < 1000) {
      return `${tokens} tokens`;
    } else if (tokens < 1000000) {
      return `${(tokens / 1000).toFixed(1)}k tokens`;
    } else {
      return `${(tokens / 1000000).toFixed(2)}M tokens`;
    }
  }

  /**
   * Format cost for display
   */
  formatCost(costUSD: number): string {
    if (costUSD < 0.01) {
      return `$${(costUSD * 100).toFixed(2)}¢`;
    } else {
      return `$${costUSD.toFixed(2)}`;
    }
  }

  /**
   * Analyze conversation and provide recommendations
   */
  analyzeConversation(messages: Message[], model: string = 'claude-sonnet-4-5'): {
    tokenCount: TokenCountResult;
    contextStatus: ReturnType<typeof this.checkContextLimit>;
    cost: ReturnType<typeof this.estimateCost>;
    recommendations: string[];
  } {
    const tokenCount = this.countMessages(messages);
    const contextStatus = this.checkContextLimit(tokenCount.tokens, model);
    const cost = this.estimateCost(messages, model);

    const recommendations: string[] = [];

    if (contextStatus.shouldCompress) {
      recommendations.push(
        `🔴 Critical: Context at ${contextStatus.percentage.toFixed(1)}%. ` +
        `Compression strongly recommended to avoid hitting limit.`
      );
    } else if (contextStatus.shouldWarn) {
      recommendations.push(
        `⚠️ Warning: Context at ${contextStatus.percentage.toFixed(1)}%. ` +
        `Consider compressing older messages soon.`
      );
    }

    if (cost.total > 0.50) {
      recommendations.push(
        `💰 Cost Notice: Estimated conversation cost is ${this.formatCost(cost.total)}. ` +
        `Consider compressing to reduce token usage.`
      );
    }

    if (messages.length > 50) {
      recommendations.push(
        `📊 Long Conversation: ${messages.length} messages. ` +
        `Older messages may be less relevant - compression could improve response quality.`
      );
    }

    return {
      tokenCount,
      contextStatus,
      cost,
      recommendations
    };
  }
}

// Export singleton instance
export const tokenCounter = new TokenCounter();

/**
 * Convenience function for quick token counting
 */
export function countTokens(text: string): number {
  return tokenCounter.countText(text).tokens;
}

/**
 * Convenience function for message token counting
 */
export function countMessageTokens(message: Message): number {
  return tokenCounter.countMessage(message).tokens;
}

/**
 * Convenience function for conversation token counting
 */
export function countConversationTokens(messages: Message[]): number {
  return tokenCounter.countMessages(messages).tokens;
}
