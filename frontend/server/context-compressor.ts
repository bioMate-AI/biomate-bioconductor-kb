/**
 * Context Compression Service
 *
 * Compresses long conversation contexts using Claude to generate summaries.
 * Implements the strategy: Keep recent N messages + summary of older messages.
 *
 * This prevents hitting Claude's 200k token context limit while preserving
 * important conversation context.
 */

import Anthropic from '@anthropic-ai/sdk';
import type { Message } from '../shared/schema';

export interface CompressionOptions {
  keepRecentCount?: number;  // Number of recent messages to keep (default: 3)
  maxSummaryTokens?: number; // Max tokens for summary (default: 2000)
}

export interface CompressionResult {
  // The generated summary
  summary: string;

  // Compressed message list (summary + recent messages)
  compressedMessages: Message[];

  // Metrics
  messagesBeforeCount: number;
  messagesAfterCount: number;
  tokensBeforeCount: number;
  tokensAfterCount: number;
  compressionRatio: number;

  // Timestamp
  compressedAt: Date;
}

export interface CompressionAnalysis {
  shouldCompress: boolean;
  reason: string;
  currentTokens: number;
  projectedTokensAfterCompression: number;
  recommendedAction: 'compress_now' | 'compress_soon' | 'no_action';
}

export class ContextCompressor {
  private claude: Anthropic;
  private defaultKeepRecentCount = 3;
  private defaultMaxSummaryTokens = 2000;

  // Compression thresholds
  private readonly COMPRESSION_THRESHOLD = 160000;  // 80% of 200k
  private readonly WARNING_THRESHOLD = 140000;      // 70% of 200k

  constructor(apiKey: string) {
    this.claude = new Anthropic({ apiKey });
  }

  /**
   * Analyze whether compression is needed
   */
  analyzeCompressionNeeds(messages: Message[]): CompressionAnalysis {
    const currentTokens = this.estimateTokens(messages);

    if (currentTokens >= this.COMPRESSION_THRESHOLD) {
      return {
        shouldCompress: true,
        reason: `Context at ${currentTokens.toLocaleString()} tokens (${((currentTokens / 200000) * 100).toFixed(1)}%). Compression strongly recommended.`,
        currentTokens,
        projectedTokensAfterCompression: Math.ceil(currentTokens * 0.35), // ~65% reduction
        recommendedAction: 'compress_now'
      };
    } else if (currentTokens >= this.WARNING_THRESHOLD) {
      return {
        shouldCompress: false,
        reason: `Context at ${currentTokens.toLocaleString()} tokens (${((currentTokens / 200000) * 100).toFixed(1)}%). Consider compressing soon.`,
        currentTokens,
        projectedTokensAfterCompression: Math.ceil(currentTokens * 0.35),
        recommendedAction: 'compress_soon'
      };
    }

    return {
      shouldCompress: false,
      reason: `Context at ${currentTokens.toLocaleString()} tokens (${((currentTokens / 200000) * 100).toFixed(1)}%). No compression needed.`,
      currentTokens,
      projectedTokensAfterCompression: currentTokens,
      recommendedAction: 'no_action'
    };
  }

  /**
   * Compress messages by summarizing old ones and keeping recent ones
   */
  async compressMessages(
    messages: Message[],
    options: CompressionOptions = {}
  ): Promise<CompressionResult> {
    const keepRecentCount = options.keepRecentCount ?? this.defaultKeepRecentCount;
    const maxSummaryTokens = options.maxSummaryTokens ?? this.defaultMaxSummaryTokens;

    // Validate inputs
    if (messages.length <= keepRecentCount) {
      throw new Error(
        `Too few messages to compress. Need at least ${keepRecentCount + 1} messages, got ${messages.length}.`
      );
    }

    console.log('[ContextCompressor] Starting compression:', {
      totalMessages: messages.length,
      keepRecentCount,
      messagesToSummarize: messages.length - keepRecentCount
    });

    // Calculate tokens before compression
    const tokensBeforeCount = this.estimateTokens(messages);

    // Split messages: old (to summarize) + recent (to keep)
    const oldMessages = messages.slice(0, -keepRecentCount);
    const recentMessages = messages.slice(-keepRecentCount);

    console.log('[ContextCompressor] Message split:', {
      oldMessages: oldMessages.length,
      recentMessages: recentMessages.length,
      tokensToSummarize: this.estimateTokens(oldMessages)
    });

    // Generate summary using Claude
    const summary = await this.generateSummary(oldMessages, maxSummaryTokens);

    // Create summary message
    const summaryMessage: Message = {
      id: `summary-${Date.now()}`,
      role: 'assistant',
      content: `**[Context Summary - ${oldMessages.length} messages compressed]**\n\n${summary}\n\n*[End of summary. Recent conversation continues below.]*`,
      timestamp: new Date(),
      // @ts-ignore - Add custom property to mark as summary
      isSummary: true,
      // @ts-ignore - Track what was compressed
      compressedMessageCount: oldMessages.length,
      compressedAt: new Date()
    };

    // Create compressed message list, then strip any tool_result blocks that
    // reference tool_use IDs no longer present (orphaned pairs cause API errors).
    const compressedMessages = this.sanitizeToolPairs([summaryMessage, ...recentMessages]);

    // Calculate tokens after compression
    const tokensAfterCount = this.estimateTokens(compressedMessages);
    const compressionRatio = tokensAfterCount / tokensBeforeCount;

    const result: CompressionResult = {
      summary,
      compressedMessages,
      messagesBeforeCount: messages.length,
      messagesAfterCount: compressedMessages.length,
      tokensBeforeCount,
      tokensAfterCount,
      compressionRatio,
      compressedAt: new Date()
    };

    console.log('[ContextCompressor] Compression complete:', {
      messagesReduction: `${messages.length} → ${compressedMessages.length}`,
      tokensReduction: `${tokensBeforeCount.toLocaleString()} → ${tokensAfterCount.toLocaleString()}`,
      compressionRatio: `${(compressionRatio * 100).toFixed(1)}%`,
      tokensSaved: (tokensBeforeCount - tokensAfterCount).toLocaleString()
    });

    return result;
  }

  /**
   * Generate a summary of old messages using Claude
   */
  private async generateSummary(
    messages: Message[],
    maxTokens: number
  ): Promise<string> {
    // Format conversation for summarization
    const conversation = messages
      .map(m => {
        const roleLabel = m.role === 'user' ? 'USER' : 'ASSISTANT';
        // Include thinking content if present
        const thinkingNote = (m as any).thinking_content
          ? `\n[Thinking: ${(m as any).thinking_content}]`
          : '';
        return `${roleLabel}: ${m.content}${thinkingNote}`;
      })
      .join('\n\n');

    const systemPrompt = `You are a conversation summarization expert. Your task is to create a concise but comprehensive summary of a bioinformatics assistant conversation.

CRITICAL REQUIREMENTS:
1. Preserve ALL important context for continuing the conversation
2. Include user's research goals, questions, and requirements
3. List all tool recommendations made and WHY they were recommended
4. Note data types, domains, and methodologies discussed
5. Track workflow decisions and any parameters specified
6. Include any errors, issues, or concerns raised
7. Preserve technical details that affect future recommendations

FORMAT:
Write a flowing narrative paragraph that captures the essence of the conversation.
DO NOT use bullet points or numbered lists - write prose.
Keep it concise but information-dense.

The summary will replace these older messages, and the user will continue their conversation below the summary. Ensure they have all the context needed.`;

    const userPrompt = `Summarize this conversation:\n\n${conversation}`;

    console.log('[ContextCompressor] Generating summary with Claude...', {
      messageCount: messages.length,
      conversationLength: conversation.length,
      maxTokens
    });

    try {
      const response = await this.claude.messages.create({
        model: 'claude-sonnet-4-5',
        max_tokens: maxTokens,
        temperature: 0.3, // Lower temperature for more focused summaries
        system: systemPrompt,
        messages: [{ role: 'user', content: userPrompt }]
      });

      const content = response.content[0];
      const summary = content.type === 'text' ? content.text : '';

      console.log('[ContextCompressor] Summary generated:', {
        summaryLength: summary.length,
        estimatedTokens: this.estimateTokens([{ content: summary } as Message])
      });

      return summary;
    } catch (error) {
      console.error('[ContextCompressor] Summary generation failed:', error);
      throw new Error(`Failed to generate summary: ${error instanceof Error ? error.message : 'Unknown error'}`);
    }
  }

  /**
   * Remove tool_result blocks whose tool_use_id has no matching tool_use block
   * in the message array. This prevents Anthropic API rejections after compression
   * discards the assistant turns that contained the original tool_use blocks.
   */
  private sanitizeToolPairs(messages: any[]): any[] {
    const toolUseIds = new Set<string>()
    for (const msg of messages) {
      const content = Array.isArray(msg.content) ? msg.content : []
      for (const block of content) {
        if (block.type === 'tool_use' && block.id) {
          toolUseIds.add(block.id)
        }
      }
    }
    return messages.map(msg => {
      if (!Array.isArray(msg.content)) return msg
      const filtered = msg.content.filter((block: any) =>
        block.type !== 'tool_result' || toolUseIds.has(block.tool_use_id)
      )
      return { ...msg, content: filtered }
    })
  }

  /**
   * Estimate tokens in messages using same heuristic as token-counter.ts
   */
  private estimateTokens(messages: Message[]): number {
    let totalTokens = 0;

    for (const msg of messages) {
      const contentChars = msg.content.length;

      // Heuristic token counting based on content type
      // TODO: replace with actual usage.input_tokens from Anthropic response when plumbed through
      let tokensPerChar = 0.25; // Default: 1 token per 4 chars

      // If content looks like code (has lots of special chars)
      const specialChars = (msg.content.match(/[{}[\]();,<>=]/g) || []).length;
      if (specialChars / contentChars > 0.1) {
        tokensPerChar = 0.29; // Code: ~1 token per 3.5 chars
      }

      // If content looks like JSON
      if (msg.content.trim().startsWith('{') || msg.content.trim().startsWith('[')) {
        tokensPerChar = 0.33; // JSON: ~1 token per 3 chars
      }

      // Add tokens for message structure (~4 tokens per message)
      totalTokens += Math.ceil(contentChars * tokensPerChar) + 4;

      // Add thinking content tokens if present
      if ((msg as any).thinking_content) {
        const thinkingChars = (msg as any).thinking_content.length;
        totalTokens += Math.ceil(thinkingChars * 0.25) + 2;
      }
    }

    return totalTokens;
  }

  /**
   * Check if a message is a summary (helper for UI)
   */
  static isSummaryMessage(message: Message): boolean {
    return (message as any).isSummary === true ||
           message.content.includes('[Context Summary') ||
           message.content.includes('[Previous Conversation Summary]');
  }

  /**
   * Extract summary text from a summary message
   */
  static extractSummaryText(message: Message): string | null {
    if (!this.isSummaryMessage(message)) {
      return null;
    }

    // Remove the wrapper text
    let text = message.content;
    text = text.replace(/\*\*\[Context Summary.*?\]\*\*/g, '');
    text = text.replace(/\*\[End of summary.*?\]\*/g, '');
    text = text.trim();

    return text;
  }
}

// Export singleton instance (will be initialized with API key)
let compressorInstance: ContextCompressor | null = null;

export function getContextCompressor(apiKey?: string): ContextCompressor {
  if (!compressorInstance) {
    if (!apiKey && !process.env.ANTHROPIC_API_KEY) {
      throw new Error('ANTHROPIC_API_KEY not provided');
    }
    compressorInstance = new ContextCompressor(
      apiKey || process.env.ANTHROPIC_API_KEY!
    );
  }
  return compressorInstance;
}

export const contextCompressor = {
  get: getContextCompressor
};
