import { useState } from "react"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from "@/components/ui/tooltip"
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover"
import {
  Lightbulb,
  Check,
  Info,
  TrendingUp,
  Sparkles,
  FlaskConical,
  BookOpen
} from "lucide-react"
import { cn } from "@/lib/utils"
import type { ParameterRecommendation } from "@shared/schema"

interface ParameterRecommendationBadgeProps {
  recommendation: ParameterRecommendation
  onApply?: (value: any) => void
  isApplied?: boolean
  size?: 'sm' | 'md'
  className?: string
}

export function ParameterRecommendationBadge({
  recommendation,
  onApply,
  isApplied = false,
  size = 'sm',
  className
}: ParameterRecommendationBadgeProps) {
  const [isOpen, setIsOpen] = useState(false)

  const getSourceIcon = (source: string) => {
    switch (source) {
      case 'benchmark':
        return <FlaskConical className="h-3 w-3" />
      case 'protocol':
        return <BookOpen className="h-3 w-3" />
      case 'best_practice':
        return <TrendingUp className="h-3 w-3" />
      case 'llm_generated':
        return <Sparkles className="h-3 w-3" />
      default:
        return <Lightbulb className="h-3 w-3" />
    }
  }

  const getSourceLabel = (source: string) => {
    switch (source) {
      case 'benchmark':
        return 'From benchmark results'
      case 'protocol':
        return 'From protocol guidelines'
      case 'best_practice':
        return 'Best practice recommendation'
      case 'llm_generated':
        return 'AI-suggested value'
      default:
        return 'Recommendation'
    }
  }

  const confidenceColor = recommendation.confidence >= 0.8
    ? 'text-green-600 dark:text-green-400'
    : recommendation.confidence >= 0.6
    ? 'text-yellow-600 dark:text-yellow-400'
    : 'text-orange-600 dark:text-orange-400'

  const handleApply = () => {
    onApply?.(recommendation.recommended_value)
    setIsOpen(false)
  }

  if (isApplied) {
    return (
      <Badge
        variant="secondary"
        className={cn(
          "bg-green-500/10 text-green-600 dark:text-green-400 gap-1",
          size === 'sm' ? 'text-[10px] px-1.5 py-0' : 'text-xs px-2 py-0.5',
          className
        )}
      >
        <Check className="h-2.5 w-2.5" />
        Applied
      </Badge>
    )
  }

  return (
    <Popover open={isOpen} onOpenChange={setIsOpen}>
      <PopoverTrigger asChild>
        <Badge
          variant="outline"
          className={cn(
            "cursor-pointer hover:bg-primary/10 transition-colors gap-1 border-primary/30",
            size === 'sm' ? 'text-[10px] px-1.5 py-0' : 'text-xs px-2 py-0.5',
            className
          )}
        >
          <Lightbulb className="h-2.5 w-2.5 text-primary" />
          {String(recommendation.recommended_value)}
        </Badge>
      </PopoverTrigger>
      <PopoverContent className="w-64 p-3" align="start">
        <div className="space-y-3">
          <div className="flex items-center gap-2">
            {getSourceIcon(recommendation.source)}
            <span className="text-xs text-muted-foreground">
              {getSourceLabel(recommendation.source)}
            </span>
          </div>

          <div className="space-y-1">
            <div className="flex items-center justify-between">
              <span className="text-sm font-medium">{recommendation.parameter_name}</span>
              <span className={cn("text-xs", confidenceColor)}>
                {(recommendation.confidence * 100).toFixed(0)}% confidence
              </span>
            </div>

            {recommendation.current_value !== undefined && (
              <div className="flex items-center gap-2 text-xs">
                <span className="text-muted-foreground">Current:</span>
                <code className="px-1 bg-muted rounded">{String(recommendation.current_value)}</code>
                <span className="text-muted-foreground">→</span>
                <code className="px-1 bg-primary/10 text-primary rounded">{String(recommendation.recommended_value)}</code>
              </div>
            )}

            {recommendation.reason && (
              <p className="text-xs text-muted-foreground mt-2">
                {recommendation.reason}
              </p>
            )}
          </div>

          {onApply && (
            <Button
              size="sm"
              className="w-full h-7 text-xs"
              onClick={handleApply}
            >
              <Check className="h-3 w-3 mr-1" />
              Use Recommended Value
            </Button>
          )}
        </div>
      </PopoverContent>
    </Popover>
  )
}

// Inline version for use within parameter inputs
interface InlineRecommendationProps {
  recommendation: ParameterRecommendation
  onApply?: (value: any) => void
  isApplied?: boolean
}

export function InlineRecommendation({
  recommendation,
  onApply,
  isApplied = false
}: InlineRecommendationProps) {
  if (isApplied) {
    return (
      <span className="text-xs text-green-600 dark:text-green-400 flex items-center gap-1">
        <Check className="h-3 w-3" />
        Applied
      </span>
    )
  }

  return (
    <TooltipProvider>
      <Tooltip>
        <TooltipTrigger asChild>
          <button
            onClick={() => onApply?.(recommendation.recommended_value)}
            className="text-xs text-primary hover:underline flex items-center gap-1"
          >
            <Lightbulb className="h-3 w-3" />
            {String(recommendation.recommended_value)} recommended
          </button>
        </TooltipTrigger>
        <TooltipContent>
          <p className="text-xs max-w-[200px]">
            {recommendation.reason || `Recommended based on ${recommendation.source.replace('_', ' ')}`}
          </p>
        </TooltipContent>
      </Tooltip>
    </TooltipProvider>
  )
}
