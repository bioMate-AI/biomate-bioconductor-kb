/**
 * Galaxy Recommendations Component
 *
 * Displays tool and dataset recommendations from Galaxy Assistant
 * Shows relevance scores, reasoning, and allows user to explore/select items
 */

import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Separator } from "@/components/ui/separator";
import {
  Wrench,
  Database,
  ChevronRight,
  ExternalLink,
  Info,
  Sparkles,
} from "lucide-react";
import { cn } from "@/lib/utils";
import { useState } from "react";

interface ToolRecommendation {
  tool: {
    tool_id: string;
    name: string;
    category?: string;
    keywords?: string;
    help_text?: {
      function_info?: {
        operation_type?: string;
        is_primary_function?: boolean;
        wrapper_function?: string;
      };
    };
  };
  relevanceScore: number;
  reasoning: string;
}

interface DatasetRecommendation {
  dataset: {
    id: string;
    name: string;
    type?: string;
    size_mb?: number;
  };
  relevanceScore: number;
  reasoning: string;
}

interface GalaxyRecommendationsProps {
  tools?: ToolRecommendation[];
  datasets?: DatasetRecommendation[];
  onToolClick?: (tool: ToolRecommendation) => void;
  onDatasetClick?: (dataset: DatasetRecommendation) => void;
}

export function GalaxyRecommendations({
  tools,
  datasets,
  onToolClick,
  onDatasetClick,
}: GalaxyRecommendationsProps) {
  const [expandedTools, setExpandedTools] = useState<Set<string>>(new Set());
  const [expandedDatasets, setExpandedDatasets] = useState<Set<string>>(new Set());

  if (!tools && !datasets) {
    return null;
  }

  const toggleToolExpanded = (toolId: string) => {
    const newExpanded = new Set(expandedTools);
    if (newExpanded.has(toolId)) {
      newExpanded.delete(toolId);
    } else {
      newExpanded.add(toolId);
    }
    setExpandedTools(newExpanded);
  };

  const toggleDatasetExpanded = (datasetId: string) => {
    const newExpanded = new Set(expandedDatasets);
    if (newExpanded.has(datasetId)) {
      newExpanded.delete(datasetId);
    } else {
      newExpanded.add(datasetId);
    }
    setExpandedDatasets(newExpanded);
  };

  const getRelevanceColor = (score: number) => {
    if (score >= 0.8) return "text-green-600 dark:text-green-400";
    if (score >= 0.6) return "text-blue-600 dark:text-blue-400";
    if (score >= 0.4) return "text-yellow-600 dark:text-yellow-400";
    return "text-muted-foreground";
  };

  const getRelevanceBadge = (score: number) => {
    const percentage = Math.round(score * 100);
    if (score >= 0.8) return { label: `${percentage}% Match`, variant: "default" as const };
    if (score >= 0.6) return { label: `${percentage}% Match`, variant: "secondary" as const };
    return { label: `${percentage}% Match`, variant: "outline" as const };
  };

  return (
    <div className="space-y-3">
      {/* Tool Recommendations */}
      {tools && tools.length > 0 && (
        <Card className="border-blue-200 dark:border-blue-800 bg-blue-50/50 dark:bg-blue-950/20">
          <CardHeader className="pb-3">
            <CardTitle className="text-sm flex items-center gap-2">
              <Wrench className="h-4 w-4" />
              Recommended Tools ({tools.length})
              <Badge variant="outline" className="text-xs">
                <Sparkles className="h-3 w-3 mr-1" />
                Galaxy
              </Badge>
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-2">
            {tools.map((toolRec, index) => {
              const isExpanded = expandedTools.has(toolRec.tool.tool_id);
              const badge = getRelevanceBadge(toolRec.relevanceScore);

              return (
                <div
                  key={toolRec.tool.tool_id || index}
                  className="border rounded-lg p-3 bg-background hover:bg-accent/50 transition-colors"
                >
                  <div className="flex items-start justify-between gap-2">
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2 mb-1">
                        <button
                          onClick={() => toggleToolExpanded(toolRec.tool.tool_id)}
                          className="font-medium text-sm hover:underline text-left"
                        >
                          {toolRec.tool.name}
                        </button>
                        <Badge variant={badge.variant} className="text-xs">
                          {badge.label}
                        </Badge>
                        {/* NEW: Show operation type badge for non-primary functions */}
                        {toolRec.tool.help_text?.function_info?.operation_type &&
                         !toolRec.tool.help_text?.function_info?.is_primary_function && (
                          <Badge
                            variant="outline"
                            className={`text-xs ${
                              toolRec.tool.help_text.function_info.operation_type === 'post_processing'
                                ? 'bg-purple-50 text-purple-700 border-purple-200 dark:bg-purple-900/20 dark:text-purple-300 dark:border-purple-700'
                                : toolRec.tool.help_text.function_info.operation_type === 'visualization'
                                ? 'bg-green-50 text-green-700 border-green-200 dark:bg-green-900/20 dark:text-green-300 dark:border-green-700'
                                : toolRec.tool.help_text.function_info.operation_type === 'format_conversion'
                                ? 'bg-orange-50 text-orange-700 border-orange-200 dark:bg-orange-900/20 dark:text-orange-300 dark:border-orange-700'
                                : 'bg-gray-50 text-gray-700 border-gray-200 dark:bg-gray-900/20 dark:text-gray-300 dark:border-gray-700'
                            }`}
                          >
                            {toolRec.tool.help_text.function_info.operation_type === 'post_processing' ? 'Post-processing' :
                             toolRec.tool.help_text.function_info.operation_type === 'visualization' ? 'Visualization' :
                             toolRec.tool.help_text.function_info.operation_type === 'format_conversion' ? 'Conversion' :
                             toolRec.tool.help_text.function_info.operation_type === 'batch_processing' ? 'Batch' :
                             toolRec.tool.help_text.function_info.operation_type === 'data_manipulation' ? 'Filter/Edit' :
                             toolRec.tool.help_text.function_info.operation_type}
                          </Badge>
                        )}
                      </div>

                      {/* NEW: Show wrapper function description instead of just category */}
                      {toolRec.tool.help_text?.function_info?.wrapper_function ? (
                        <p className="text-xs text-muted-foreground italic">
                          {toolRec.tool.help_text.function_info.wrapper_function}
                        </p>
                      ) : toolRec.tool.category && (
                        <p className="text-xs text-muted-foreground">
                          Category: {toolRec.tool.category}
                        </p>
                      )}

                      {isExpanded && (
                        <div className="mt-2 space-y-2">
                          <div className="text-xs bg-muted/50 p-2 rounded">
                            <div className="flex items-start gap-1">
                              <Info className="h-3 w-3 mt-0.5 flex-shrink-0 text-blue-500" />
                              <span>{toolRec.reasoning}</span>
                            </div>
                          </div>

                          {toolRec.tool.keywords && (
                            <div className="flex items-center gap-1 flex-wrap">
                              {toolRec.tool.keywords.split(',').slice(0, 5).map((keyword, i) => (
                                <Badge key={i} variant="outline" className="text-xs">
                                  {keyword.trim()}
                                </Badge>
                              ))}
                            </div>
                          )}

                          {onToolClick && (
                            <Button
                              size="sm"
                              variant="outline"
                              className="text-xs"
                              onClick={() => onToolClick(toolRec)}
                            >
                              <ExternalLink className="h-3 w-3 mr-1" />
                              View Details
                            </Button>
                          )}
                        </div>
                      )}
                    </div>

                    <Button
                      size="sm"
                      variant="ghost"
                      onClick={() => toggleToolExpanded(toolRec.tool.tool_id)}
                      className="flex-shrink-0"
                    >
                      <ChevronRight
                        className={cn(
                          "h-4 w-4 transition-transform",
                          isExpanded && "rotate-90"
                        )}
                      />
                    </Button>
                  </div>
                </div>
              );
            })}
          </CardContent>
        </Card>
      )}

      {/* Dataset Recommendations */}
      {datasets && datasets.length > 0 && (
        <Card className="border-green-200 dark:border-green-800 bg-green-50/50 dark:bg-green-950/20">
          <CardHeader className="pb-3">
            <CardTitle className="text-sm flex items-center gap-2">
              <Database className="h-4 w-4" />
              Recommended Datasets ({datasets.length})
              <Badge variant="outline" className="text-xs">
                <Sparkles className="h-3 w-3 mr-1" />
                BioMNI
              </Badge>
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-2">
            {datasets.map((datasetRec, index) => {
              const isExpanded = expandedDatasets.has(datasetRec.dataset.id);
              const badge = getRelevanceBadge(datasetRec.relevanceScore);

              return (
                <div
                  key={datasetRec.dataset.id || index}
                  className="border rounded-lg p-3 bg-background hover:bg-accent/50 transition-colors"
                >
                  <div className="flex items-start justify-between gap-2">
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2 mb-1">
                        <button
                          onClick={() => toggleDatasetExpanded(datasetRec.dataset.id)}
                          className="font-medium text-sm hover:underline text-left"
                        >
                          {datasetRec.dataset.name}
                        </button>
                        <Badge variant={badge.variant} className="text-xs">
                          {badge.label}
                        </Badge>
                      </div>

                      <div className="flex items-center gap-2 text-xs text-muted-foreground">
                        {datasetRec.dataset.type && (
                          <span>Type: {datasetRec.dataset.type}</span>
                        )}
                        {datasetRec.dataset.size_mb && (
                          <span>• {datasetRec.dataset.size_mb} MB</span>
                        )}
                      </div>

                      {isExpanded && (
                        <div className="mt-2 space-y-2">
                          <div className="text-xs bg-muted/50 p-2 rounded">
                            <div className="flex items-start gap-1">
                              <Info className="h-3 w-3 mt-0.5 flex-shrink-0 text-green-500" />
                              <span>{datasetRec.reasoning}</span>
                            </div>
                          </div>

                          {onDatasetClick && (
                            <Button
                              size="sm"
                              variant="outline"
                              className="text-xs"
                              onClick={() => onDatasetClick(datasetRec)}
                            >
                              <ExternalLink className="h-3 w-3 mr-1" />
                              View Details
                            </Button>
                          )}
                        </div>
                      )}
                    </div>

                    <Button
                      size="sm"
                      variant="ghost"
                      onClick={() => toggleDatasetExpanded(datasetRec.dataset.id)}
                      className="flex-shrink-0"
                    >
                      <ChevronRight
                        className={cn(
                          "h-4 w-4 transition-transform",
                          isExpanded && "rotate-90"
                        )}
                      />
                    </Button>
                  </div>
                </div>
              );
            })}
          </CardContent>
        </Card>
      )}
    </div>
  );
}
