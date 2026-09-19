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
  Save,
  FlaskConical,
  ShieldAlert,
} from "lucide-react";
import { cn } from "@/lib/utils";
import { useState } from "react";
import { api } from "@/lib/api";
import { useActiveProjectIdSafe } from "@/contexts/active-project-context";
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
            Benchmark Evidence
            <Badge variant="outline" className="text-xs">
              <Beaker className="h-3 w-3 mr-1" />
              Validated
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
              Recommended: <span className="text-primary">{bestTool}</span>
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
                  <span className="font-medium">Source Study</span>
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
                Tool Rankings
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
                            Best
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
                              <p className="text-xs">{result.metric_name} performance metric</p>
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
                            View tool
                          </Button>
                        )}
                      </div>
                    )}
                  </div>
                );
              })}

              {benchmarkData.results.length > 5 && (
                <p className="text-xs text-muted-foreground text-center">
                  + {benchmarkData.results.length - 5} more tools
                </p>
              )}
            </div>

            {/* Tool comparison table (if available) */}
            {benchmarkData.comparison && Object.keys(benchmarkData.comparison).length > 0 && (
              <div className="mt-3 pt-3 border-t">
                <div className="flex items-center gap-2 text-xs font-medium text-muted-foreground mb-2">
                  <BarChart3 className="h-3 w-3" />
                  Detailed Comparison
                </div>
                <div className="overflow-x-auto">
                  <table className="w-full text-xs">
                    <thead>
                      <tr className="border-b">
                        <th className="text-left p-1 font-medium">Tool</th>
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
            Show {benchmarkData.results.length} ranked tools and evidence
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
  abstract?: string;
  relevance_score?: number;
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
   * exist; absent → the rich panel renders no transparency section (honest-empty).
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
  /** "Check against our data" exit — turns the answer into a run on project data.
   *  Only rendered when supplied, so we never show an exit that does nothing. */
  onCheckAgainstData?: (answer: string) => void;
  className?: string;
}

/** Build the saved-answer document: the answer plus its cited sources, so the
 *  saved object carries its own provenance (not a bare paragraph). */
function buildAnswerMarkdown(response: ResearchResponseData): string {
  const lines: string[] = [response.answer?.trim() || ""];
  if (response.citations?.length) {
    lines.push("", "## Sources");
    response.citations.forEach((c, i) => {
      const bits = [
        `${i + 1}. ${c.title}`,
        c.authors?.length ? c.authors.slice(0, 3).join(", ") + (c.authors.length > 3 ? " et al." : "") : "",
        c.journal || "",
        c.year ? `(${c.year})` : "",
        c.doi ? `doi:${c.doi}` : "",
      ].filter(Boolean);
      lines.push(bits.join(" · "));
    });
  }
  if (response.boundary) lines.push("", `_Boundary: ${response.boundary}_`);
  return lines.join("\n").trim();
}

/**
 * Map a research-agent literature citation to the EvidenceCitation shape the rich
 * CitationPanel expects. Literature answers don't produce formatted_apa/bibtex, so
 * those are left empty — the per-item BibTeX button is already disabled when
 * formatted_bibtex is empty, and CitationPanel's top-level Export button is guarded
 * to only appear when at least one citation carries a formatted_bibtex.
 * tool_name := title (the panel's primary label); tool_id := a stable key
 * (doi > pmid > index) so React keys and the reader pane stay stable.
 */
function toEvidenceCitations(citations: ResearchCitation[]): EvidenceCitation[] {
  return (citations || []).map((c, i) => ({
    tool_id: c.doi || c.pmid || `cite-${i}`,
    tool_name: c.title || `Source ${i + 1}`,
    title: c.title || `Source ${i + 1}`,
    authors: c.authors || [],
    year: c.year,
    journal: c.journal,
    doi: c.doi,
    pmid: c.pmid,
    formatted_apa: "",
    formatted_short: "",
    formatted_bibtex: "",
  }));
}

export function ResearchResponseDisplay({
  response,
  onFollowUpClick,
  onToolClick,
  onCheckAgainstData,
  className,
}: ResearchResponseDisplayProps) {
  const [showCitations, setShowCitations] = useState(false);
  const activeProjectId = useActiveProjectIdSafe();
  const [saveState, setSaveState] = useState<"idle" | "saving" | "saved" | "error">("idle");

  // Save the answer (with its sources) as a persistent, reusable project object
  // via the real project-knowledge endpoint — the same one the workflow methods
  // panel uses. Makes an evidence answer non-ephemeral (L1), not lost with the chat.
  const handleSaveToProject = async () => {
    if (!activeProjectId || saveState === "saving") return;
    const content = buildAnswerMarkdown(response);
    if (!content) { setSaveState("error"); return; }
    setSaveState("saving");
    try {
      await api.request(`/memory/projects/${activeProjectId}/knowledge`, {
        method: "POST",
        body: JSON.stringify({
          knowledgeType: "notes_synthesis",
          title: `Saved answer — ${new Date().toISOString().slice(0, 10)}`,
          content,
          source: "user_saved",
        }),
      });
      setSaveState("saved");
    } catch (e: any) {
      console.error("[research] save to project failed:", e?.message ?? e);
      setSaveState("error");
    }
  };

  // Boundary is ALWAYS present (spec 01): a specific caveat when the agent
  // supplies one, else an honest standing caveat — never silently omitted.
  const boundaryText =
    response.boundary?.trim() ||
    "Synthesizes retrieved literature only — not validated against your project's data. Check against your own data before relying on it.";

  return (
    <div className={cn("space-y-3", className)}>
      {/* Benchmark evidence if available */}
      {response.benchmark_evidence && (
        <BenchmarkEvidence
          benchmarkData={response.benchmark_evidence}
          onToolClick={onToolClick}
        />
      )}

      {/* Citations — rich panel. Renders the source list PLUS retrieval
          transparency ("How this was searched") and conflict rows ("Sources
          disagree") when the backend supplied real data. Both sections are
          honest-empty otherwise (CitationPanel filters on Number.isFinite /
          non-empty positions), so an ordinary literature answer degrades to a
          plain source list. answerText travels so the panel's Save-to-notes
          payload carries the claim with its sources. */}
      {response.citations && response.citations.length > 0 && (
        <CitationPanel
          citations={toEvidenceCitations(response.citations)}
          retrieval={response.retrieval}
          conflicts={response.conflicts}
          answerText={response.answer}
          isCollapsed={!showCitations}
        />
      )}

      {/* Boundary — always present (spec 01): what this answer is NOT evidence for. */}
      <div
        data-testid="research-answer-boundary"
        className="flex items-start gap-2 rounded-md border border-amber-200 dark:border-amber-900/60 bg-amber-50/60 dark:bg-amber-950/20 p-2 text-xs text-amber-800 dark:text-amber-300"
      >
        <ShieldAlert className="h-3.5 w-3.5 mt-0.5 shrink-0" />
        <span><span className="font-medium">Boundary:</span> {boundaryText}</span>
      </div>

      {/* Exits — make the answer a reusable object, and turn it into a run. */}
      <div className="flex flex-wrap items-center gap-2">
        <Button
          size="sm"
          variant="outline"
          className="text-xs"
          data-testid="research-answer-save"
          disabled={!activeProjectId || saveState === "saving" || saveState === "saved"}
          title={!activeProjectId ? "Open a project to save this answer" : "Save this answer and its sources to the project"}
          onClick={handleSaveToProject}
        >
          <Save className="h-3.5 w-3.5 mr-1" />
          {saveState === "saving" ? "Saving…" : saveState === "saved" ? "Saved to project ✓" : saveState === "error" ? "Save failed — retry" : "Save to project"}
        </Button>
        {onCheckAgainstData && (
          <Button
            size="sm"
            variant="outline"
            className="text-xs"
            data-testid="research-answer-check-data"
            onClick={() => onCheckAgainstData(response.answer)}
          >
            <FlaskConical className="h-3.5 w-3.5 mr-1" />
            Check against our data
          </Button>
        )}
      </div>

      {/* Follow-up questions */}
      {response.follow_up_questions && response.follow_up_questions.length > 0 && (
        <div className="flex flex-wrap gap-2">
          {response.follow_up_questions.map((question, index) => (
            <Button
              key={index}
              variant="outline"
              size="sm"
              className="text-xs"
              onClick={() => onFollowUpClick?.(question)}
            >
              {question}
            </Button>
          ))}
        </div>
      )}

    </div>
  );
}
