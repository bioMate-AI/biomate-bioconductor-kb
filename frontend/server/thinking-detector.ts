/**
 * Thinking Mode Detector
 *
 * Detects and parses thinking content from Claude's responses.
 * Supports extended thinking mode with <thinking> and <answer> tags.
 *
 * When Claude uses extended thinking, responses look like:
 * <thinking>
 * [AI's internal reasoning process...]
 * </thinking>
 *
 * <answer>
 * [The actual response to show the user...]
 * </answer>
 */

export interface ThinkingDetectionResult {
  hasThinking: boolean;
  thinkingContent: string | null;
  answerContent: string;
  thinkingLevel: 'none' | 'brief' | 'detailed';
  rawContent: string;
  thinkingWordCount?: number;
  thinkingTokenCount?: number;
}

export class ThinkingDetector {
  // Regex patterns for thinking tags
  private readonly THINKING_TAG_PATTERN = /<thinking>([\s\S]*?)<\/thinking>/;
  private readonly ANSWER_TAG_PATTERN = /<answer>([\s\S]*?)<\/answer>/;
  private readonly THINKING_GLOBAL_PATTERN = /<thinking>[\s\S]*?<\/thinking>/g;
  private readonly ANSWER_GLOBAL_PATTERN = /<answer>[\s\S]*?<\/answer>/g;

  // Thresholds for thinking level classification
  private readonly BRIEF_THINKING_WORDS = 50;
  private readonly DETAILED_THINKING_WORDS = 200;

  /**
   * Detect and parse thinking content from Claude's response
   */
  detectThinking(content: string): ThinkingDetectionResult {
    console.log('[ThinkingDetector] Analyzing content for thinking tags...');

    // Check if content contains thinking tags
    const hasThinkingTag = this.THINKING_TAG_PATTERN.test(content);
    const hasAnswerTag = this.ANSWER_TAG_PATTERN.test(content);

    if (!hasThinkingTag) {
      console.log('[ThinkingDetector] No thinking tags found');
      return {
        hasThinking: false,
        thinkingContent: null,
        answerContent: content,
        thinkingLevel: 'none',
        rawContent: content
      };
    }

    // Extract thinking content
    const thinkingMatch = content.match(this.THINKING_TAG_PATTERN);
    const answerMatch = content.match(this.ANSWER_TAG_PATTERN);

    const thinkingContent = thinkingMatch ? thinkingMatch[1].trim() : null;
    let answerContent: string;

    if (hasAnswerTag && answerMatch) {
      // Use answer tag content
      answerContent = answerMatch[1].trim();
    } else {
      // Remove thinking tags and use remaining content as answer
      answerContent = content
        .replace(this.THINKING_GLOBAL_PATTERN, '')
        .trim();
    }

    // If no explicit answer content, try to extract after thinking tags
    if (!answerContent && thinkingContent) {
      // Look for content after all thinking tags
      const afterThinking = content.split('</thinking>').pop()?.trim() || '';
      answerContent = afterThinking.replace(this.ANSWER_GLOBAL_PATTERN, '').trim();
    }

    // Fallback: if still no answer, use the whole content minus thinking
    if (!answerContent) {
      answerContent = content.replace(this.THINKING_GLOBAL_PATTERN, '').trim();
    }

    // Determine thinking level
    const wordCount = thinkingContent ? this.countWords(thinkingContent) : 0;
    const thinkingLevel = this.determineThinkingLevel(wordCount);

    // Estimate token count (rough heuristic: ~0.75 tokens per word)
    const tokenCount = Math.ceil(wordCount * 0.75);

    console.log('[ThinkingDetector] Thinking detected:', {
      hasThinking: true,
      wordCount,
      tokenCount,
      thinkingLevel,
      answerLength: answerContent.length
    });

    return {
      hasThinking: true,
      thinkingContent,
      answerContent,
      thinkingLevel,
      rawContent: content,
      thinkingWordCount: wordCount,
      thinkingTokenCount: tokenCount
    };
  }

  /**
   * Extract just the answer content (remove thinking tags)
   */
  extractAnswer(content: string): string {
    const result = this.detectThinking(content);
    return result.answerContent;
  }

  /**
   * Extract just the thinking content
   */
  extractThinking(content: string): string | null {
    const result = this.detectThinking(content);
    return result.thinkingContent;
  }

  /**
   * Check if content has thinking tags (fast check without full parsing)
   */
  hasThinkingTags(content: string): boolean {
    return this.THINKING_TAG_PATTERN.test(content);
  }

  /**
   * Determine thinking level based on word count
   */
  private determineThinkingLevel(wordCount: number): 'none' | 'brief' | 'detailed' {
    if (wordCount === 0) return 'none';
    if (wordCount <= this.BRIEF_THINKING_WORDS) return 'brief';
    if (wordCount <= this.DETAILED_THINKING_WORDS) return 'detailed';
    return 'detailed'; // Very long thinking is also detailed
  }

  /**
   * Count words in text
   */
  private countWords(text: string): number {
    return text.split(/\s+/).filter(word => word.length > 0).length;
  }

  /**
   * Format thinking content for display (add line breaks, clean up)
   */
  formatThinkingForDisplay(thinkingContent: string): string {
    return thinkingContent
      .trim()
      .replace(/\n{3,}/g, '\n\n') // Normalize multiple newlines
      .replace(/^\s+/gm, '') // Remove leading whitespace from lines
      .trim();
  }

  /**
   * Generate summary of thinking content (first few lines or key points)
   */
  generateThinkingSummary(thinkingContent: string, maxLength: number = 150): string {
    const formatted = this.formatThinkingForDisplay(thinkingContent);
    const lines = formatted.split('\n').filter(line => line.trim().length > 0);

    // Take first line or first N characters
    const firstLine = lines[0] || '';
    if (firstLine.length <= maxLength) {
      return firstLine;
    }

    return firstLine.substring(0, maxLength).trim() + '...';
  }

  /**
   * Analyze thinking patterns for insights
   * (Can be used for user patterns or debugging)
   */
  analyzeThinkingPatterns(thinkingContent: string): {
    hasCodeAnalysis: boolean;
    hasToolSelection: boolean;
    hasDatasetConsideration: boolean;
    hasErrorHandling: boolean;
    complexity: 'simple' | 'moderate' | 'complex';
  } {
    const lower = thinkingContent.toLowerCase();

    return {
      hasCodeAnalysis: /code|function|implement|algorithm/.test(lower),
      hasToolSelection: /tool|select|choose|recommend|compare/.test(lower),
      hasDatasetConsideration: /dataset|data|file|input|output/.test(lower),
      hasErrorHandling: /error|handle|exception|fail|fallback/.test(lower),
      complexity: this.determineComplexity(thinkingContent)
    };
  }

  /**
   * Determine complexity of thinking
   */
  private determineComplexity(thinkingContent: string): 'simple' | 'moderate' | 'complex' {
    const wordCount = this.countWords(thinkingContent);
    const lines = thinkingContent.split('\n').length;

    if (wordCount < 50 && lines < 5) return 'simple';
    if (wordCount < 200 && lines < 20) return 'moderate';
    return 'complex';
  }

  /**
   * Create a structured thinking object for storage
   */
  createThinkingData(detection: ThinkingDetectionResult) {
    if (!detection.hasThinking || !detection.thinkingContent) {
      return null;
    }

    const patterns = this.analyzeThinkingPatterns(detection.thinkingContent);

    return {
      content: detection.thinkingContent,
      level: detection.thinkingLevel,
      wordCount: detection.thinkingWordCount,
      tokenCount: detection.thinkingTokenCount,
      summary: this.generateThinkingSummary(detection.thinkingContent),
      patterns,
      timestamp: new Date()
    };
  }
}

// Export singleton instance
export const thinkingDetector = new ThinkingDetector();

// Export convenience functions
export function detectThinking(content: string): ThinkingDetectionResult {
  return thinkingDetector.detectThinking(content);
}

export function extractAnswer(content: string): string {
  return thinkingDetector.extractAnswer(content);
}

export function extractThinking(content: string): string | null {
  return thinkingDetector.extractThinking(content);
}

export function hasThinkingTags(content: string): boolean {
  return thinkingDetector.hasThinkingTags(content);
}
