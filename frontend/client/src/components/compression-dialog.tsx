/**
 * Compression Dialog Component
 *
 * Shows when conversation context is approaching token limit.
 * Allows user to compress older messages while keeping recent ones intact.
 */

import React from 'react';
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from './ui/alert-dialog';
import { Badge } from './ui/badge';
import { Alert, AlertDescription } from './ui/alert';
import { Progress } from './ui/progress';
import { InfoIcon, AlertTriangleIcon, Sparkles } from 'lucide-react';

export interface CompressionDialogProps {
  open: boolean;
  currentTokens: number;
  tokenLimit: number;
  messageCount: number;
  estimatedTokensAfter?: number;
  compressionRatio?: number;
  isCompressing?: boolean;
  onCompress: () => void;
  onCancel: () => void;
}

export function CompressionDialog({
  open,
  currentTokens,
  tokenLimit,
  messageCount,
  estimatedTokensAfter,
  compressionRatio,
  isCompressing = false,
  onCompress,
  onCancel,
}: CompressionDialogProps) {
  const percentage = (currentTokens / tokenLimit) * 100;
  const estimatedAfter = estimatedTokensAfter ?? Math.ceil(currentTokens * 0.35);
  const estimatedPercentageAfter = (estimatedAfter / tokenLimit) * 100;
  const ratio = compressionRatio ?? 0.35;

  const getStatusColor = () => {
    if (percentage >= 80) return 'destructive';
    if (percentage >= 70) return 'warning';
    return 'default';
  };

  const getStatusText = () => {
    if (percentage >= 80) return 'Critical';
    if (percentage >= 70) return 'Warning';
    return 'Normal';
  };

  return (
    <AlertDialog open={open} onOpenChange={onCancel}>
      <AlertDialogContent className="max-w-2xl">
        <AlertDialogHeader>
          <AlertDialogTitle className="flex items-center gap-2">
            {percentage >= 80 ? (
              <AlertTriangleIcon className="h-5 w-5 text-destructive" />
            ) : (
              <InfoIcon className="h-5 w-5 text-warning" />
            )}
            Context Window Approaching Limit
          </AlertDialogTitle>
          <AlertDialogDescription className="text-left space-y-4">
            <p className="text-base">
              Your conversation is getting long and approaching Claude's context limit.
              Would you like to compress older messages to free up space?
            </p>

            {/* Current Status Card */}
            <div className="bg-muted rounded-lg p-4 space-y-3">
              <div className="flex items-center justify-between">
                <span className="text-sm font-medium">Current Status</span>
                <Badge variant={getStatusColor() as any}>
                  {getStatusText()}
                </Badge>
              </div>

              <div className="space-y-2">
                <div className="flex justify-between text-sm">
                  <span className="text-muted-foreground">Messages</span>
                  <span className="font-medium">{messageCount.toLocaleString()}</span>
                </div>

                <div className="space-y-1">
                  <div className="flex justify-between text-sm">
                    <span className="text-muted-foreground">Tokens Used</span>
                    <span className="font-medium">
                      {currentTokens.toLocaleString()} / {tokenLimit.toLocaleString()}
                    </span>
                  </div>
                  <Progress value={percentage} className="h-2" />
                  <div className="text-xs text-muted-foreground text-right">
                    {percentage.toFixed(1)}% of limit
                  </div>
                </div>
              </div>
            </div>

            {/* Projected After Compression */}
            <div className="bg-primary/5 rounded-lg p-4 space-y-3">
              <div className="flex items-center gap-2">
                <Sparkles className="h-4 w-4 text-primary" />
                <span className="text-sm font-medium">After Compression</span>
              </div>

              <div className="space-y-2">
                <div className="flex justify-between text-sm">
                  <span className="text-muted-foreground">Projected Tokens</span>
                  <span className="font-medium text-primary">
                    ~{estimatedAfter.toLocaleString()}
                  </span>
                </div>

                <div className="space-y-1">
                  <Progress value={estimatedPercentageAfter} className="h-2" />
                  <div className="text-xs text-muted-foreground text-right">
                    ~{estimatedPercentageAfter.toFixed(1)}% of limit
                  </div>
                </div>

                <div className="flex justify-between text-sm">
                  <span className="text-muted-foreground">Tokens Saved</span>
                  <span className="font-medium text-green-600">
                    ~{(currentTokens - estimatedAfter).toLocaleString()}
                    {' '}({((1 - ratio) * 100).toFixed(0)}% reduction)
                  </span>
                </div>
              </div>
            </div>

            {/* How Compression Works */}
            <Alert>
              <InfoIcon className="h-4 w-4" />
              <AlertDescription className="text-sm">
                <strong>How compression works:</strong>
                <ul className="mt-2 space-y-1 list-disc list-inside">
                  <li>Your <strong>3 most recent messages</strong> will be kept intact</li>
                  <li>Older messages will be <strong>summarized by AI</strong></li>
                  <li>All important context will be <strong>preserved</strong></li>
                  <li>The conversation will remain <strong>coherent</strong></li>
                  <li>You can continue chatting normally after compression</li>
                </ul>
              </AlertDescription>
            </Alert>

            {percentage >= 90 && (
              <Alert variant="destructive">
                <AlertTriangleIcon className="h-4 w-4" />
                <AlertDescription className="text-sm">
                  <strong>Action required:</strong> You're at {percentage.toFixed(1)}% of the context limit.
                  Compression is strongly recommended to avoid hitting the limit, which would
                  require starting a new conversation.
                </AlertDescription>
              </Alert>
            )}
          </AlertDialogDescription>
        </AlertDialogHeader>

        <AlertDialogFooter>
          <AlertDialogCancel disabled={isCompressing} onClick={onCancel}>
            Not Yet
          </AlertDialogCancel>
          <AlertDialogAction
            onClick={onCompress}
            disabled={isCompressing}
            className="bg-primary hover:bg-primary/90"
          >
            {isCompressing ? (
              <span className="flex items-center gap-2">
                <span className="animate-spin">⏳</span>
                Compressing...
              </span>
            ) : (
              <span className="flex items-center gap-2">
                <Sparkles className="h-4 w-4" />
                Compress Now
              </span>
            )}
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}

/**
 * Simple status badge for showing compression status in the UI
 */
export interface CompressionStatusBadgeProps {
  currentTokens: number;
  tokenLimit: number;
  className?: string;
}

export function CompressionStatusBadge({
  currentTokens,
  tokenLimit,
  className = ''
}: CompressionStatusBadgeProps) {
  const percentage = (currentTokens / tokenLimit) * 100;

  if (percentage < 70) {
    return null; // Don't show anything if usage is low
  }

  const getVariant = () => {
    if (percentage >= 80) return 'destructive';
    if (percentage >= 70) return 'warning';
    return 'default';
  };

  const getIcon = () => {
    if (percentage >= 80) return '🔴';
    if (percentage >= 70) return '⚠️';
    return '📊';
  };

  return (
    <Badge variant={getVariant() as any} className={className}>
      {getIcon()} {percentage.toFixed(0)}% context used
    </Badge>
  );
}
