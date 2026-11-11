import { t } from "@/lib/i18n";
/**
 * Benchmark Evidence Component
 *
 * Displays benchmark evidence for tool recommendations from the BenchmarkKnowledgeDB.
 * Shows ranked tools, performance metrics, and source studies with DOI links.
 * Integrates with the ResearchAgent for literature-backed tool comparisons.
 */

import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Tooltip, TooltipContent, TooltipTrigger, TooltipProvider } from "@/components/ui/tooltip";
import {
  BarChart3,
  Trophy,
  ExternalLink,
  ChevronRight,
  ChevronDown,
  BookOpen,
  Beaker,
  Info,
  Award,
  TrendingUp,
  Clock,
  Zap,
} from "lucide-react";
import { cn } from "@/lib/utils";
import { useState } from "react";
import { CitationPanel } from "@/components/citation-panel";
import type { EvidenceCitation } from "@/components/source-reader-pane";

// Types for benchmark evidence data
export interface BenchmarkToolResult {
  tool_name: string;
  galaxy_tool_id?: string;
  rank: number;
  metric_name: string;
  metric_value: number | string;
  metric_unit?: string;
  evidence_text?: string;
  context_notes?: string;
}

export interface BenchmarkStudy {
  study_name: string;
  doi?: string;
  pmid?: string;
  year?: number;
  dataset_name?: string;
  dataset_type?: string;
}

export interface BenchmarkComparison {
  query?: string;
  task?: string;
  best_tool?: string;
  winner?: string;
  evidence?: string;
  recommendation?: string;
  results: BenchmarkToolResult[];
  study?: BenchmarkStudy;
  comparison?: Record<string, Record<string, number | string>>;
}

interface BenchmarkEvidenceProps {
  benchmarkData: BenchmarkComparison;
  onToolClick?: (toolName: string, galaxyToolId?: string) => void;
  className?: string;
}

export function BenchmarkEvidence({
  benchmarkData,
  onToolClick,
  className,
}: BenchmarkEvidenceProps) {
  const [isExpanded, setIsExpanded] = useState(false);
  const [expandedTools, setExpandedTools] = useState<Set<string>>(new Set());

  if (!benchmarkData || !benchmarkData.results || benchmarkData.results.length === 0) {
    return null;
  }

  const toggleToolExpanded = (toolName: string) => {
    const newExpanded = new Set(expandedTools);
    if (newExpanded.has(toolName)) {
      newExpanded.delete(toolName);
    } else {
      newExpanded.add(toolName);
    }
    setExpandedTools(newExpanded);
  };

  const getRankBadgeVariant = (rank: number): "default" | "secondary" | "outline" => {
    if (rank === 1) return "default";
    if (rank <= 3) return "secondary";
    return "outline";
  };

  const getRankIcon = (rank: number) => {
    if (rank === 1) return <Trophy className="h-3 w-3 text-yellow-500" />;
    if (rank === 2) return <Award className="h-3 w-3 text-gray-400" />;
    if (rank === 3) return <Award className="h-3 w-3 text-amber-600" />;
    return <span className="text-xs font-mono">{rank}</span>;
  };

  const formatMetricValue = (value: number | string, unit?: string): string => {
    if (typeof value === "number") {
      if (value < 0.01) return value.toExponential(2);
      if (value < 1) return value.toFixed(3);
      if (value > 1000) return value.toLocaleString();
      return value.toFixed(2);
    }
    return String(value);
  };

  const bestTool = benchmarkData.best_tool || benchmarkData.winner || benchmarkData.results[0]?.tool_name;

  return (
    <Card className={cn(
      "border-amber-200 dark:border-amber-800 bg-amber-50/50 dark:bg-amber-950/20",
      className
    )}>
      <CardHeader className="pb-3">
        <CardTitle className="text-sm flex items-center justify-between">
          <div className="flex items-center gap-2">
            <BarChart3 className="h-4 w-4" />
            {t("citations.benchmark.title")}
            <Badge variant="outline" className="text-xs">
              <Beaker className="h-3 w-3 mr-1" />
              {t("citations.benchmark.validated")}
            </Badge>
          </div>
          <Button
            size="sm"
            variant="ghost"
            onClick={() => setIsExpanded(!isExpanded)}
            className="h-6 px-2"
          >
            {isExpanded ? (
              <ChevronDown className="h-4 w-4" />
            ) : (
              <ChevronRight className="h-4 w-4" />
            )}
          </Button>
        </CardTitle>
      </CardHeader>

      <CardContent className="space-y-3">
        {/* Summary section - always visible */}
        <div className="flex items-center gap-2 p-2 bg-background rounded-lg border">
          <Trophy className="h-5 w-5 text-yellow-500 flex-shrink-0" />
          <div className="flex-1 min-w-0">
            <p className="text-sm font-medium">
              {t("citations.benchmark.recommended")} <span className="text-primary">{bestTool}</span>
            </p>
            {benchmarkData.evidence && (
              <p className="text-xs text-muted-foreground truncate">
                {benchmarkData.evidence}
              </p>
            )}
            {benchmarkData.recommendation && (
              <p className="text-xs text-muted-foreground">
                {benchmarkData.recommendation}
              </p>
            )}
          </div>
        </div>

        {/* Tool comparison - shown when expanded */}
        {isExpanded && (
          <>
            {/* Study source */}
            {benchmarkData.study && (
              <div className="p-2 bg-muted/50 rounded-lg text-xs">
                <div className="flex items-center gap-2 mb-1">
                  <BookOpen className="h-3 w-3" />
                  <span className="font-medium">{t("citations.benchmark.source_study")}</span>
                </div>
                <p className="text-muted-foreground">
                  {benchmarkData.study.study_name}
                  {benchmarkData.study.year && ` (${benchmarkData.study.year})`}
                </p>
                {benchmarkData.study.doi && (
                  <a
                    href={`https://doi.org/${benchmarkData.study.doi}`}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-blue-600 dark:text-blue-400 hover:underline flex items-center gap-1 mt-1"
                  >
                    <ExternalLink className="h-3 w-3" />
                    DOI: {benchmarkData.study.doi}
                  </a>
                )}
                {benchmarkData.study.pmid && (
                  <a
                    href={`https://pubmed.ncbi.nlm.nih.gov/${benchmarkData.study.pmid}`}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-blue-600 dark:text-blue-400 hover:underline flex items-center gap-1 mt-1"
                  >
                    <ExternalLink className="h-3 w-3" />
                    PMID: {benchmarkData.study.pmid}
                  </a>
                )}
              </div>
            )}

            {/* Tool rankings table */}
            <div className="space-y-2">
              <div className="flex items-center gap-2 text-xs font-medium text-muted-foreground">
                <TrendingUp className="h-3 w-3" />
                {t("citations.benchmark.tool_rankings")}
              </div>

              {benchmarkData.results.slice(0, 5).map((result, index) => {
                const isToolExpanded = expandedTools.has(result.tool_name);
                const isBest = result.tool_name === bestTool;

                return (
                  <div
                    key={result.tool_name}
                    className={cn(
                      "border rounded-lg p-2 transition-colors",
                      isBest
                        ? "bg-yellow-50/50 dark:bg-yellow-950/20 border-yellow-200 dark:border-yellow-800"
                        : "bg-background hover:bg-accent/50"
                    )}
                  >
                    <div className="flex items-center justify-between">
                      <div className="flex items-center gap-2">
                        <Badge
                          variant={getRankBadgeVariant(result.rank)}
                          className="w-6 h-6 p-0 flex items-center justify-center"
                        >
                          {getRankIcon(result.rank)}
                        </Badge>
                        <button
                          onClick={() => toggleToolExpanded(result.tool_name)}
                          className="font-medium text-sm hover:underline text-left"
                        >
                          {result.tool_name}
                        </button>
                        {isBest && (
                          <Badge variant="default" className="text-xs">
                            {t("citations.benchmark.best")}
                          </Badge>
                        )}
                      </div>

                      <div className="flex items-center gap-2">
                        {result.metric_value != null && result.metric_name !== 'benchmark_evidence' && (
                        <TooltipProvider>
                          <Tooltip>
                            <TooltipTrigger asChild>
                              <Badge variant="outline" className="text-xs font-mono">
                                {result.metric_name}: {formatMetricValue(result.metric_value, result.metric_unit)}
                                {result.metric_unit && ` ${result.metric_unit}`}
                              </Badge>
                            </TooltipTrigger>
                            <TooltipContent>
                              <p className="text-xs">{t("citations.benchmark.metric_tip", { metric: result.metric_name })}</p>
                            </TooltipContent>
                          </Tooltip>
                        </TooltipProvider>
                        )}

                        <Button
                          size="sm"
                          variant="ghost"
                          onClick={() => toggleToolExpanded(result.tool_name)}
                          className="h-6 w-6 p-0"
                        >
                          <ChevronRight
                            className={cn(
                              "h-4 w-4 transition-transform",
                              isToolExpanded && "rotate-90"
                            )}
                          />
                        </Button>
                      </div>
                    </div>

                    {/* Expanded tool details */}
                    {isToolExpanded && (
                      <div className="mt-2 pt-2 border-t space-y-2">
                        {result.evidence_text && (
                          <div className="text-xs bg-muted/50 p-2 rounded">
                            <div className="flex items-start gap-1">
                              <Info className="h-3 w-3 mt-0.5 flex-shrink-0 text-blue-500" />
                              <span>{result.evidence_text}</span>
                            </div>
                          </div>
                        )}

                        {result.context_notes && (
                          <div className="text-xs text-muted-foreground">
                            <Zap className="h-3 w-3 inline mr-1" />
                            {result.context_notes}
                          </div>
                        )}

                        {result.galaxy_tool_id && onToolClick && (
                          <Button
                            size="sm"
                            variant="outline"
                            className="text-xs"
                            onClick={() => onToolClick(result.tool_name, result.galaxy_tool_id)}
                          >
                            <ExternalLink className="h-3 w-3 mr-1" />
                            {t("citations.benchmark.view_tool")}
                          </Button>
                        )}
                      </div>
                    )}
                  </div>
                );
              })}

              {benchmarkData.results.length > 5 && (
                <p className="text-xs text-muted-foreground text-center">
                  {t("citations.benchmark.more_tools", { count: benchmarkData.results.length - 5 })}
                </p>
              )}
            </div>

            {/* Tool comparison table (if available) */}
            {benchmarkData.comparison && Object.keys(benchmarkData.comparison).length > 0 && (
              <div className="mt-3 pt-3 border-t">
                <div className="flex items-center gap-2 text-xs font-medium text-muted-foreground mb-2">
                  <BarChart3 className="h-3 w-3" />
                  {t("citations.benchmark.detailed_comparison")}
                </div>
                <div className="overflow-x-auto">
                  <table className="w-full text-xs">
                    <thead>
                      <tr className="border-b">
                        <th className="text-left p-1 font-medium">{t("citations.benchmark.tool")}</th>
                        {Object.keys(Object.values(benchmarkData.comparison)[0] || {}).map((metric) => (
                          <th key={metric} className="text-right p-1 font-medium">
                            {metric}
                          </th>
                        ))}
                      </tr>
                    </thead>
                    <tbody>
                      {Object.entries(benchmarkData.comparison).map(([tool, metrics]) => (
                        <tr key={tool} className="border-b last:border-0">
                          <td className="p-1 font-medium">{tool}</td>
                          {Object.values(metrics).map((value, i) => (
                            <td key={i} className="text-right p-1 font-mono">
                              {typeof value === "number" ? formatMetricValue(value) : value}
                            </td>
                          ))}
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </div>
            )}
          </>
        )}

        {/* Expand hint when collapsed */}
        {!isExpanded && benchmarkData.results.length > 1 && (
          <button
            onClick={() => setIsExpanded(true)}
            className="text-xs text-muted-foreground hover:text-foreground flex items-center gap-1"
          >
            <ChevronRight className="h-3 w-3" />
            {t("citations.benchmark.show_ranked", { count: benchmarkData.results.length })}
          </button>
        )}
      </CardContent>
    </Card>
  );
}

/**
 * Research Response Component
 *
 * Displays answers from the ResearchAgent with citations and benchmark evidence.
 */
export interface ResearchCitation {
  title: string;
  authors?: string[];
  year?: number;
  journal?: string;
  doi?: string;
  pmid?: string;
  /** PubMed Central id (PMC…) when the retrieval path knows it — lets the reader fetch OA full text directly. */
  pmcid?: string;
  /** Landing URL for sources with no DOI/PMID (preprint servers, databases). */
  url?: string;
  abstract?: string;
  relevance_score?: number;
  locus?: string;
  retrieval_date?: string;
  corpus_version?: string;
}

export interface ResearchResponseData {
  answer: string;
  citations: ResearchCitation[];
  confidence: number;
  follow_up_questions?: string[];
  methods_used?: string[];
  benchmark_evidence?: BenchmarkComparison;
  /** What this answer is NOT evidence for (spec 01: boundary is always present). */
  boundary?: string;
  /**
   * Retrieval transparency ("How this was searched"), keyed per source that was
   * genuinely queried. Emitted by the backend ONLY when real per-source counts
   * exist; absent → the panel renders no search footnote (honest-empty).
   */
  retrieval?: Array<{ name: string; found: number; kept: number }>;
  /**
   * Source disagreements ("Sources disagree"). Emitted by the backend ONLY when
   * the synthesis step reported genuinely conflicting sources; absent → no
   * conflict row renders. Never fabricated client-side.
   */
  conflicts?: Array<{ topic?: string; positions: Array<{ claim: string; source?: string }> }>;
}

interface ResearchResponseDisplayProps {
  response: ResearchResponseData;
  onFollowUpClick?: (question: string) => void;
  onToolClick?: (toolName: string, galaxyToolId?: string) => void;
  className?: string;
}

/**
 * Map a research-agent literature citation to the EvidenceCitation shape the
 * CitationPanel / SourceReaderPane expect. Every identifier the reader needs to
 * fetch real text travels: doi, pmid, pmcid and url (the reader resolves
 * abstract + open-access full text from Europe PMC by these ids).
 * tool_name := title (the panel's primary label); tool_id := a stable key
 * (doi > pmid > index) so React keys and the reader pane stay stable.
 */
export function toEvidenceCitations(citations: ResearchCitation[]): EvidenceCitation[] {
  return (citations || []).map((c, i) => ({
    tool_id: c.doi || c.pmid || c.pmcid || `cite-${i}`,
    tool_name: c.title || `#${i + 1}`,
    title: c.title || `#${i + 1}`,
    authors: c.authors || [],
    year: c.year,
    journal: c.journal,
    doi: c.doi,
    pmid: c.pmid,
    pmcid: c.pmcid,
    url: c.url,
    abstract: c.abstract,
    locus: c.locus,
    retrieval_date: c.retrieval_date,
    corpus_version: c.corpus_version,
    formatted_apa: "",
    formatted_short: "",
    formatted_bibtex: "",
  }));
}

export function ResearchResponseDisplay({
  response,
  onFollowUpClick,
  onToolClick,
  className,
}: ResearchResponseDisplayProps) {
  return (
    <div className={cn("space-y-3", className)}>
      {/* Benchmark evidence if available */}
      {response.benchmark_evidence && (
        <BenchmarkEvidence
          benchmarkData={response.benchmark_evidence}
          onToolClick={onToolClick}
        />
      )}

      {/* Sources — collapsed by default: one quiet "N sources" line under the
          answer; expanding shows a numbered reference list (title · journal ·
          year → link) with a Read action that opens the source reader. Search
          transparency ("N of M kept") and conflicts render only when the
          backend supplied real data. */}
      {response.citations && response.citations.length > 0 && (
        <CitationPanel
          kind="literature"
          citations={toEvidenceCitations(response.citations)}
          retrieval={response.retrieval}
          conflicts={response.conflicts}
          answerText={response.answer}
          isCollapsed={true}
        />
      )}

      {/* Follow-up questions — clicking one sends it as the next question. */}
      {onFollowUpClick && response.follow_up_questions && response.follow_up_questions.length > 0 && (
        <div className="flex flex-wrap gap-2" data-testid="research-follow-ups">
          {response.follow_up_questions.map((question, index) => (
            <Button
              key={index}
              variant="outline"
              size="sm"
              className="h-auto whitespace-normal text-left text-xs font-normal"
              onClick={() => onFollowUpClick(question)}
            >
              {question}
            </Button>
          ))}
        </div>
      )}

    </div>
  );
}
