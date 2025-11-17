/**
 * Thinking Display Component
 *
 * Shows Claude's reasoning process in a collapsible, visually distinct section.
 * Supports brief and detailed thinking modes with appropriate styling.
 */

import { useState } from 'react';
import { Card } from './ui/card';
import { Badge } from './ui/badge';
import { Button } from './ui/button';
import { ChevronDown, ChevronRight, Brain, Zap, Code2 } from 'lucide-react';
import { cn } from '@/lib/utils';

export interface ThinkingDisplayProps {
  thinkingContent: string;
  thinkingLevel?: 'none' | 'brief' | 'detailed';
  wordCount?: number;
  tokenCount?: number;
  summary?: string;
  className?: string;
  defaultExpanded?: boolean;
}

export function ThinkingDisplay({
  thinkingContent,
  thinkingLevel = 'brief',
  wordCount,
  tokenCount,
  summary,
  className,
  defaultExpanded = false
}: ThinkingDisplayProps) {
  const [isExpanded, setIsExpanded] = useState(defaultExpanded);

  if (!thinkingContent || thinkingLevel === 'none') {
    return null;
  }

  const getLevelIcon = () => {
    switch (thinkingLevel) {
      case 'brief':
        return <Zap className="h-4 w-4" />;
      case 'detailed':
        return <Brain className="h-4 w-4" />;
      default:
        return <Code2 className="h-4 w-4" />;
    }
  };

  const getLevelColor = () => {
    switch (thinkingLevel) {
      case 'brief':
        return 'text-blue-600 dark:text-blue-400';
      case 'detailed':
        return 'text-purple-600 dark:text-purple-400';
      default:
        return 'text-gray-600 dark:text-gray-400';
    }
  };

  const getLevelBgColor = () => {
    switch (thinkingLevel) {
      case 'brief':
        return 'bg-blue-50 dark:bg-blue-950/30 border-blue-200 dark:border-blue-800';
      case 'detailed':
        return 'bg-purple-50 dark:bg-purple-950/30 border-purple-200 dark:border-purple-800';
      default:
        return 'bg-gray-50 dark:bg-gray-950/30 border-gray-200 dark:border-gray-800';
    }
  };

  const displaySummary = summary || (thinkingContent.split('\n')[0].substring(0, 100) + '...');

  return (
    <Card
      className={cn(
        'border-l-4 transition-all duration-200',
        getLevelBgColor(),
        className
      )}
    >
      {/* Header - Always visible */}
      <div
        className="flex items-start gap-3 p-4 cursor-pointer hover:opacity-80 transition-opacity"
        onClick={() => setIsExpanded(!isExpanded)}
      >
        {/* Icon */}
        <div className={cn('mt-0.5', getLevelColor())}>
          {getLevelIcon()}
        </div>

        {/* Content */}
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 mb-1">
            <span className="text-sm font-medium text-foreground">
              {isExpanded ? 'AI Reasoning Process' : 'View AI Reasoning'}
            </span>
            <Badge variant="secondary" className="text-xs">
              {thinkingLevel}
            </Badge>
            {wordCount && (
              <span className="text-xs text-muted-foreground">
                {wordCount} words
              </span>
            )}
            {tokenCount && (
              <span className="text-xs text-muted-foreground">
                • ~{tokenCount} tokens
              </span>
            )}
          </div>

          {/* Summary when collapsed */}
          {!isExpanded && (
            <p className="text-sm text-muted-foreground line-clamp-2">
              {displaySummary}
            </p>
          )}
        </div>

        {/* Expand/Collapse button */}
        <Button
          variant="ghost"
          size="sm"
          className="ml-auto"
          onClick={(e) => {
            e.stopPropagation();
            setIsExpanded(!isExpanded);
          }}
        >
          {isExpanded ? (
            <ChevronDown className="h-4 w-4" />
          ) : (
            <ChevronRight className="h-4 w-4" />
          )}
        </Button>
      </div>

      {/* Expanded Content */}
      {isExpanded && (
        <div className="px-4 pb-4 pt-0">
          <div className="border-t border-border/50 pt-3">
            <div className="prose prose-sm dark:prose-invert max-w-none">
              <div className="text-sm text-foreground whitespace-pre-wrap font-mono leading-relaxed">
                {thinkingContent}
              </div>
            </div>
          </div>

          {/* Footer with stats */}
          <div className="flex items-center gap-4 mt-3 pt-3 border-t border-border/50 text-xs text-muted-foreground">
            <div className="flex items-center gap-1">
              <Brain className="h-3 w-3" />
              <span>Extended Thinking Mode</span>
            </div>
            {wordCount && (
              <span>{wordCount.toLocaleString()} words</span>
            )}
            {tokenCount && (
              <span>~{tokenCount.toLocaleString()} tokens</span>
            )}
          </div>
        </div>
      )}
    </Card>
  );
}

/**
 * Compact Thinking Indicator
 * Shows a small badge indicating thinking was used
 */
export interface ThinkingIndicatorProps {
  thinkingLevel: 'brief' | 'detailed';
  onClick?: () => void;
  className?: string;
}

export function ThinkingIndicator({
  thinkingLevel,
  onClick,
  className
}: ThinkingIndicatorProps) {
  const icon = thinkingLevel === 'brief' ? <Zap className="h-3 w-3" /> : <Brain className="h-3 w-3" />;
  const variant = thinkingLevel === 'brief' ? 'outline' : 'secondary';

  return (
    <Badge
      variant={variant}
      className={cn(
        'cursor-pointer hover:opacity-80 transition-opacity',
        className
      )}
      onClick={onClick}
    >
      {icon}
      <span className="ml-1 text-xs">Thinking</span>
    </Badge>
  );
}

/**
 * Thinking Stats Component
 * Shows aggregated thinking stats for a session
 */
export interface ThinkingStatsProps {
  totalThinkingMessages: number;
  totalThinkingWords: number;
  totalThinkingTokens: number;
  averageThinkingWords: number;
  className?: string;
}

export function ThinkingStats({
  totalThinkingMessages,
  totalThinkingWords,
  totalThinkingTokens,
  averageThinkingWords,
  className
}: ThinkingStatsProps) {
  return (
    <Card className={cn('p-4', className)}>
      <div className="flex items-center gap-2 mb-3">
        <Brain className="h-5 w-5 text-purple-600" />
        <h3 className="font-medium">Thinking Mode Statistics</h3>
      </div>

      <div className="grid grid-cols-2 gap-4">
        <div>
          <div className="text-2xl font-bold text-foreground">
            {totalThinkingMessages}
          </div>
          <div className="text-xs text-muted-foreground">
            Messages with thinking
          </div>
        </div>

        <div>
          <div className="text-2xl font-bold text-foreground">
            {totalThinkingWords.toLocaleString()}
          </div>
          <div className="text-xs text-muted-foreground">
            Total thinking words
          </div>
        </div>

        <div>
          <div className="text-2xl font-bold text-foreground">
            ~{totalThinkingTokens.toLocaleString()}
          </div>
          <div className="text-xs text-muted-foreground">
            Thinking tokens used
          </div>
        </div>

        <div>
          <div className="text-2xl font-bold text-foreground">
            {Math.round(averageThinkingWords)}
          </div>
          <div className="text-xs text-muted-foreground">
            Avg. words per thinking
          </div>
        </div>
      </div>

      <div className="mt-4 p-3 bg-muted rounded-md">
        <p className="text-xs text-muted-foreground">
          <Brain className="h-3 w-3 inline mr-1" />
          Thinking mode helps Claude reason through complex problems by showing its thought process.
        </p>
      </div>
    </Card>
  );
}
