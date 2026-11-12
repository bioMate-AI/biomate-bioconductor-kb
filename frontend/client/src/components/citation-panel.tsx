import { useState } from "react"
import { Card, CardContent, CardHeader } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible"
import { Separator } from "@/components/ui/separator"
import { Textarea } from "@/components/ui/textarea"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from "@/components/ui/tooltip"
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select"
import {
  ChevronDown,
  ChevronRight,
  Copy,
  Download,
  BookOpen,
  ExternalLink,
  Check,
  FileText,
  RefreshCw,
  Loader2,
  Flag,
  MapPin,
} from "lucide-react"
import { cn } from "@/lib/utils"
import { t } from "@/lib/i18n"
import {
  exportCitationsBibTeX,
  generateMethodsSection,
  downloadAsFile,
} from "@/lib/ai-assistant-api"
import type { Citation, MethodsSection } from "@shared/schema"
import { SourceReaderPane, sourceUrl, readerCanFetch, type EvidenceCitation } from "@/components/source-reader-pane"

/**
 * Retrieval transparency (v2 Spec 09, "How this was searched").
 * One row per source the retrieval path queried, carrying how many records
 * were found vs. kept. ONLY rendered when the retrieval path supplies real
 * counts — never fabricated, never inferred from the citation list. Absent →
 * nothing renders (honest-empty). Shown as a one-line footnote with the
 * per-source breakdown in a tooltip — not a section of its own.
 */
export interface RetrievalSource {
  /** Source name, e.g. "PubMed", "Europe PMC", "bioRxiv". */
  name: string
  /** Records the source returned for the query. */
  found: number
  /** Records kept after filtering (years/species/relevance). */
  kept: number
}

// Spec 01 §1.3.2: a materially-disagreeing pair of findings, surfaced honestly.
// Only rendered when the retrieval path marks a conflict — never fabricated.
export interface CitationConflict {
  /** Short label for the disagreement, e.g. "Effect at physiological dose". */
  topic?: string
  /** The two (or more) positions in tension, each with the source it rests on. */
  positions: Array<{ claim: string; source?: string }>
}

interface CitationPanelProps {
  /**
   * "literature" — a research answer's sources: a quiet "N sources" line that
   * expands into a numbered reference list (title · journal · year → link,
   * plus Read). "workflow" — tool citations + the Methods-section generator.
   */
  kind?: "workflow" | "literature"
  citations: Citation[]
  methodsSection?: MethodsSection
  workflow?: Record<string, any>  // Galaxy workflow for API calls
  /** Spec 01 §1.3.2 conflict affordance. Omit / empty → row never renders. */
  conflicts?: CitationConflict[]
  /** Spec 09 retrieval transparency. Omit / empty → footnote never renders. */
  retrieval?: RetrievalSource[]
  /** The answer this source set backs (kept for callers; not rendered). */
  answerText?: string
  isCollapsed?: boolean
  onCopy?: (text: string, format: 'apa' | 'bibtex' | 'short') => void
  onExportBibTeX?: () => void
  onMethodsSectionUpdated?: (newSection: MethodsSection) => void
  className?: string
}

/** Keep only well-formed per-source rows (never derive counts client-side). */
function validRetrieval(retrieval?: RetrievalSource[]): RetrievalSource[] {
  return (retrieval || []).filter(
    s => s && s.name && Number.isFinite(s.found) && Number.isFinite(s.kept) && s.found >= 0 && s.kept >= 0 && s.kept <= s.found,
  )
}

export function CitationPanel(props: CitationPanelProps) {
  return props.kind === "literature" ? <LiteratureSources {...props} /> : <WorkflowCitationPanel {...props} />
}

// ─── Literature: one quiet line → numbered references ─────────────────────

function LiteratureSources({ citations, conflicts, retrieval, isCollapsed = true, className }: CitationPanelProps) {
  const [isExpanded, setIsExpanded] = useState(!isCollapsed)
  const [conflictsExpanded, setConflictsExpanded] = useState(false)
  const [readerIndex, setReaderIndex] = useState<number | null>(null)

  const sources = citations.filter(c => c.doi || c.pmid || c.title) as EvidenceCitation[]
  const activeConflicts = (conflicts || []).filter(c => c.positions && c.positions.length > 0)
  const retrievalSources = validRetrieval(retrieval)
  const kept = retrievalSources.reduce((n, s) => n + s.kept, 0)
  const found = retrievalSources.reduce((n, s) => n + s.found, 0)
  const searchDetail = retrievalSources
    .map(s => t('citations.search_source_row', { name: s.name, found: s.found, kept: s.kept }))
    .join(' · ')

  if (sources.length === 0) return null

  return (
    <div className={cn("text-sm", className)} data-testid="literature-sources">
      <div className="flex flex-wrap items-center gap-x-3 gap-y-1">
        <button
          type="button"
          onClick={() => setIsExpanded(v => !v)}
          aria-expanded={isExpanded}
          data-testid="citations-toggle"
          className="inline-flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground transition-colors"
        >
          {isExpanded ? <ChevronDown className="h-3.5 w-3.5" /> : <ChevronRight className="h-3.5 w-3.5" />}
          <BookOpen className="h-3.5 w-3.5" />
          <span>{t('citations.sources_count', { count: sources.length })}</span>
        </button>
        {/* Spec 09 — "How this was searched", reduced to a footnote. The
            per-source breakdown lives in the tooltip (and aria-label). */}
        {retrievalSources.length > 0 && (
          <TooltipProvider>
            <Tooltip>
              <TooltipTrigger asChild>
                <span
                  tabIndex={0}
                  className="text-xs text-muted-foreground/80 underline decoration-dotted underline-offset-2 cursor-help"
                  data-testid="retrieval-transparency"
                  aria-label={`${t('citations.search_summary', { kept, found })} — ${searchDetail}`}
                >
                  <span data-testid="retrieval-summary">{t('citations.search_summary', { kept, found })}</span>
                </span>
              </TooltipTrigger>
              <TooltipContent className="max-w-xs text-xs">
                {retrievalSources.map(s => (
                  <p key={s.name} data-testid={`retrieval-source-${s.name}`}>
                    {t('citations.search_source_row', { name: s.name, found: s.found, kept: s.kept })}
                  </p>
                ))}
              </TooltipContent>
            </Tooltip>
          </TooltipProvider>
        )}
      </div>

      {isExpanded && (
        <div className="mt-2 space-y-2">
          {activeConflicts.length > 0 && (
            <ConflictRow
              conflicts={activeConflicts}
              isExpanded={conflictsExpanded}
              onToggle={() => setConflictsExpanded(prev => !prev)}
            />
          )}
          <ol className="space-y-1.5" data-testid="reference-list">
            {sources.map((c, idx) => (
              <LiteratureReference key={c.tool_id || idx} citation={c} index={idx} onRead={() => setReaderIndex(idx)} />
            ))}
          </ol>
        </div>
      )}

      <SourceReaderPane sources={sources} index={readerIndex} onIndexChange={setReaderIndex} />
    </div>
  )
}

function LiteratureReference({ citation, index, onRead }: { citation: EvidenceCitation; index: number; onRead: () => void }) {
  const url = sourceUrl(citation)
  const label = citation.title || citation.tool_name
  const meta = [citation.journal, citation.year ? String(citation.year) : null].filter(Boolean).join(' · ')
  const canRead = readerCanFetch(citation) || Boolean(citation.abstract?.trim() || citation.excerpt?.trim())
  return (
    <li className="flex items-baseline gap-2 text-xs leading-relaxed" data-testid={`reference-${index}`}>
      <span className="shrink-0 tabular-nums text-muted-foreground">[{index + 1}]</span>
      <span className="min-w-0 flex-1 break-words">
        {url ? (
          <a href={url} target="_blank" rel="noopener noreferrer" className="text-foreground hover:underline underline-offset-2">
            {label}
          </a>
        ) : (
          <span className="text-foreground">{label}</span>
        )}
        {meta && <span className="text-muted-foreground"> · {meta}</span>}
        {canRead && (
          <button
            type="button"
            onClick={onRead}
            data-testid={`source-read-${index}`}
            className="ml-2 text-primary/90 hover:text-primary hover:underline underline-offset-2"
            aria-label={t('citations.read_aria', { n: index + 1 })}
          >
            {t('citations.read')}
          </button>
        )}
      </span>
    </li>
  )
}

// ─── Workflow: tool citations + methods section ───────────────────────────

function WorkflowCitationPanel({
  citations,
  methodsSection,
  workflow,
  conflicts,
  retrieval,
  isCollapsed = true,
  onCopy,
  onExportBibTeX,
  onMethodsSectionUpdated,
  className,
}: CitationPanelProps) {
  const [isExpanded, setIsExpanded] = useState(!isCollapsed)
  const [expandedCitations, setExpandedCitations] = useState<Set<string>>(new Set())
  const [copiedId, setCopiedId] = useState<string | null>(null)
  const [activeTab, setActiveTab] = useState<string>("citations")
  const [isExporting, setIsExporting] = useState(false)
  const [isRegenerating, setIsRegenerating] = useState(false)
  const [conflictsExpanded, setConflictsExpanded] = useState(false)
  const [readerIndex, setReaderIndex] = useState<number | null>(null)
  const [citationStyle, setCitationStyle] = useState<'short' | 'apa' | 'numbered'>('short')
  const [localMethodsSection, setLocalMethodsSection] = useState<MethodsSection | undefined>(methodsSection)

  const toolsWithCitations = citations.filter(c => c.doi || c.pmid || c.title) as EvidenceCitation[]
  const totalTools = citations.length
  // The top-level "Export BibTeX" can only produce a file when either a workflow
  // is present (server-side export) or at least one citation carries a
  // formatted_bibtex (local export) — otherwise it would be a dead button.
  const canExportBibTeX = Boolean(workflow) || citations.some(c => c.formatted_bibtex?.trim())
  const activeConflicts = (conflicts || []).filter(c => c.positions && c.positions.length > 0)
  const retrievalSources = validRetrieval(retrieval)

  const toggleCitationExpanded = (toolId: string) => {
    setExpandedCitations(prev => {
      const next = new Set(prev)
      if (next.has(toolId)) next.delete(toolId)
      else next.add(toolId)
      return next
    })
  }

  const handleCopy = async (text: string, id: string, format: 'apa' | 'bibtex' | 'short' = 'apa') => {
    try {
      await navigator.clipboard.writeText(text)
      setCopiedId(id)
      setTimeout(() => setCopiedId(null), 2000)
      onCopy?.(text, format)
    } catch (err) {
      console.error('Failed to copy:', err)
    }
  }

  const fallbackExport = () => {
    const bibtexContent = citations
      .filter(c => c.formatted_bibtex?.trim())
      .map(c => c.formatted_bibtex)
      .join('\n\n')
    if (bibtexContent) {
      downloadAsFile(bibtexContent, 'workflow_citations.bib', 'application/x-bibtex')
      onExportBibTeX?.()
    }
  }

  const handleExportAll = async () => {
    if (!workflow) { fallbackExport(); return }
    setIsExporting(true)
    try {
      const response = await exportCitationsBibTeX(workflow, true)
      if (response.success && response.bibtex) {
        downloadAsFile(response.bibtex, 'workflow_citations.bib', 'application/x-bibtex')
        onExportBibTeX?.()
      }
    } catch (err) {
      console.error('Failed to export citations via API:', err)
      fallbackExport()
    } finally {
      setIsExporting(false)
    }
  }

  const handleRegenerateMethodsSection = async (style: 'short' | 'apa' | 'numbered') => {
    if (!workflow) return
    setIsRegenerating(true)
    try {
      const response = await generateMethodsSection(workflow, style)
      if (response.success) {
        const newSection: MethodsSection = {
          text: response.methods_text,
          style: response.style as 'short' | 'apa' | 'numbered',
          tools_cited: response.tools_cited,
          tools_missing_citations: response.tools_missing_citations
        }
        setLocalMethodsSection(newSection)
        onMethodsSectionUpdated?.(newSection)
      }
    } catch (err) {
      console.error('Failed to regenerate methods section:', err)
    } finally {
      setIsRegenerating(false)
    }
  }

  const displayMethodsSection = localMethodsSection || methodsSection

  if (citations.length === 0 && !displayMethodsSection && !workflow) {
    return null
  }

  return (
    <Card className={cn("border border-muted", className)}>
      <Collapsible open={isExpanded} onOpenChange={setIsExpanded}>
        <CardHeader className="p-3 pb-2">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <CollapsibleTrigger asChild>
              <Button variant="ghost" className="p-0 h-auto hover:bg-transparent">
                <div className="flex items-center gap-2">
                  {isExpanded ? <ChevronDown className="h-4 w-4" /> : <ChevronRight className="h-4 w-4" />}
                  <BookOpen className="h-4 w-4 text-primary" />
                  <span className="font-medium text-sm">{t('citations.title')}</span>
                </div>
              </Button>
            </CollapsibleTrigger>

            <div className="flex items-center gap-2">
              <Badge variant="secondary" className="text-xs">
                {t('citations.tools_count', { cited: toolsWithCitations.length, total: totalTools })}
              </Badge>
              {toolsWithCitations.length > 0 && canExportBibTeX && (
                <Button size="sm" variant="outline" className="h-7 text-xs" onClick={handleExportAll} disabled={isExporting}>
                  {isExporting ? <Loader2 className="h-3 w-3 mr-1 animate-spin" /> : <Download className="h-3 w-3 mr-1" />}
                  {t('citations.export_bibtex')}
                </Button>
              )}
            </div>
          </div>
        </CardHeader>

        <CollapsibleContent>
          <CardContent className="p-3 pt-0">
            <Tabs value={activeTab} onValueChange={setActiveTab}>
              {(!!displayMethodsSection || !!workflow) && <TabsList className="grid w-full grid-cols-2 h-auto min-h-8">
                <TabsTrigger value="citations" className="text-xs">{t('citations.tab_tools')}</TabsTrigger>
                <TabsTrigger value="methods" className="text-xs" disabled={!displayMethodsSection && !workflow}>
                  {t('citations.tab_methods')}
                </TabsTrigger>
              </TabsList>}

              <TabsContent value="citations" className="mt-3 space-y-2">
                {retrievalSources.length > 0 && (
                  <p className="text-xs text-muted-foreground" data-testid="retrieval-transparency">
                    <span data-testid="retrieval-summary">
                      {t('citations.search_summary', {
                        kept: retrievalSources.reduce((n, s) => n + s.kept, 0),
                        found: retrievalSources.reduce((n, s) => n + s.found, 0),
                      })}
                    </span>
                  </p>
                )}

                {activeConflicts.length > 0 && (
                  <ConflictRow
                    conflicts={activeConflicts}
                    isExpanded={conflictsExpanded}
                    onToggle={() => setConflictsExpanded(prev => !prev)}
                  />
                )}

                {toolsWithCitations.length === 0 ? (
                  <p className="text-xs text-muted-foreground text-center py-4">{t('citations.no_tool_citations')}</p>
                ) : (
                  toolsWithCitations.map((citation, idx) => (
                    <CitationItem
                      key={citation.tool_id}
                      citation={citation}
                      isExpanded={expandedCitations.has(citation.tool_id)}
                      onToggle={() => toggleCitationExpanded(citation.tool_id)}
                      onCopy={handleCopy}
                      copiedId={copiedId}
                      onRead={() => setReaderIndex(idx)}
                    />
                  ))
                )}

                {displayMethodsSection?.tools_missing_citations && displayMethodsSection.tools_missing_citations.length > 0 && (
                  <div className="mt-3 p-2 bg-yellow-500/10 rounded-md">
                    <p className="text-xs text-yellow-600 dark:text-yellow-400">
                      <strong>{t('citations.missing_citations')}</strong> {displayMethodsSection.tools_missing_citations.join(', ')}
                    </p>
                  </div>
                )}
              </TabsContent>

              <TabsContent value="methods" className="mt-3">
                {displayMethodsSection ? (
                  <div className="space-y-3">
                    <div className="flex items-center justify-between gap-2">
                      <div className="flex items-center gap-2">
                        <span className="text-xs text-muted-foreground">{t('citations.style')}</span>
                        <Select
                          value={citationStyle}
                          onValueChange={(value: 'short' | 'apa' | 'numbered') => {
                            setCitationStyle(value)
                            if (workflow) handleRegenerateMethodsSection(value)
                          }}
                          disabled={isRegenerating || !workflow}
                        >
                          <SelectTrigger className="h-7 w-[100px] text-xs">
                            <SelectValue />
                          </SelectTrigger>
                          <SelectContent>
                            <SelectItem value="short">{t('citations.style_short')}</SelectItem>
                            <SelectItem value="apa">APA</SelectItem>
                            <SelectItem value="numbered">{t('citations.style_numbered')}</SelectItem>
                          </SelectContent>
                        </Select>
                        {isRegenerating && <Loader2 className="h-3 w-3 animate-spin text-muted-foreground" />}
                      </div>
                      <div className="flex items-center gap-1">
                        {workflow && (
                          <Button size="sm" variant="ghost" className="h-7 text-xs" onClick={() => handleRegenerateMethodsSection(citationStyle)} disabled={isRegenerating}>
                            <RefreshCw className={cn("h-3 w-3 mr-1", isRegenerating && "animate-spin")} />
                            {t('citations.regenerate')}
                          </Button>
                        )}
                        <Button size="sm" variant="ghost" className="h-7 text-xs" onClick={() => handleCopy(displayMethodsSection.text, 'methods', 'apa')}>
                          {copiedId === 'methods' ? <Check className="h-3 w-3 mr-1 text-green-500" /> : <Copy className="h-3 w-3 mr-1" />}
                          {t('citations.copy')}
                        </Button>
                      </div>
                    </div>
                    <Textarea value={displayMethodsSection.text} readOnly className="min-h-[200px] text-xs font-mono resize-y" />
                    <div className="flex items-center justify-between text-xs text-muted-foreground">
                      <span>{t('citations.tools_cited', { count: displayMethodsSection.tools_cited.length })}</span>
                      {displayMethodsSection.tools_missing_citations && displayMethodsSection.tools_missing_citations.length > 0 && (
                        <span className="text-yellow-600 dark:text-yellow-400">
                          {t('citations.tools_missing', { count: displayMethodsSection.tools_missing_citations.length })}
                        </span>
                      )}
                    </div>
                  </div>
                ) : workflow ? (
                  <div className="text-center py-4 space-y-2">
                    <p className="text-xs text-muted-foreground">{t('citations.methods_prompt')}</p>
                    <Button size="sm" variant="outline" onClick={() => handleRegenerateMethodsSection('short')} disabled={isRegenerating}>
                      {isRegenerating ? <Loader2 className="h-3 w-3 mr-1 animate-spin" /> : <FileText className="h-3 w-3 mr-1" />}
                      {t('citations.methods_generate')}
                    </Button>
                  </div>
                ) : (
                  <p className="text-xs text-muted-foreground text-center py-4">{t('citations.methods_unavailable')}</p>
                )}
              </TabsContent>
            </Tabs>
          </CardContent>
        </CollapsibleContent>
      </Collapsible>

      <SourceReaderPane sources={toolsWithCitations} index={readerIndex} onIndexChange={setReaderIndex} />
    </Card>
  )
}

interface ConflictRowProps {
  conflicts: CitationConflict[]
  isExpanded: boolean
  onToggle: () => void
}

/**
 * Spec 01 §1.3.2 conflict row — "Sources disagree — N conflicting findings".
 * Expands to show each position side by side with the source it rests on.
 * Never resolved silently by preferring the newer or the more cited source.
 */
function ConflictRow({ conflicts, isExpanded, onToggle }: ConflictRowProps) {
  const count = conflicts.length
  return (
    <div className="border border-amber-500/40 rounded-md bg-amber-500/5" data-testid="conflict-row">
      <button
        onClick={onToggle}
        className="w-full p-2 flex items-center justify-between text-left hover:bg-amber-500/10 transition-colors rounded-md"
      >
        <div className="flex items-center gap-2 min-w-0">
          <Flag className="h-3.5 w-3.5 text-amber-600 dark:text-amber-400 flex-shrink-0" />
          <span className="text-xs font-medium text-amber-700 dark:text-amber-300 truncate">
            {t(count === 1 ? 'citations.conflicts_one' : 'citations.conflicts_many', { count })}
          </span>
        </div>
        {isExpanded
          ? <ChevronDown className="h-3.5 w-3.5 flex-shrink-0 text-amber-600 dark:text-amber-400" />
          : <ChevronRight className="h-3.5 w-3.5 flex-shrink-0 text-amber-600 dark:text-amber-400" />}
      </button>

      {isExpanded && (
        <div className="px-3 pb-3 pt-1 space-y-3">
          {conflicts.map((conflict, ci) => (
            <div key={ci} className="space-y-1.5">
              {conflict.topic && <p className="text-xs font-medium text-muted-foreground">{conflict.topic}</p>}
              <div className="grid gap-2">
                {conflict.positions.map((pos, pi) => (
                  <div key={pi} className="text-xs p-2 rounded border bg-background/60">
                    <p>{pos.claim}</p>
                    {pos.source && <p className="mt-1 text-fs-xs text-muted-foreground">— {pos.source}</p>}
                  </div>
                ))}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}

interface CitationItemProps {
  citation: EvidenceCitation
  isExpanded: boolean
  onToggle: () => void
  onCopy: (text: string, id: string, format: 'apa' | 'bibtex' | 'short') => void
  copiedId: string | null
  onRead?: () => void
}

/** Workflow tool citation — expandable for its APA / BibTeX copy actions. */
function CitationItem({ citation, isExpanded, onToggle, onCopy, copiedId, onRead }: CitationItemProps) {
  const hasRecency = Boolean(citation.retrieval_date || citation.corpus_version)
  const url = sourceUrl(citation)
  return (
    <div className="border rounded-md">
      <button onClick={onToggle} className="w-full p-2 flex items-center gap-2 text-left hover:bg-muted/50 transition-colors">
        {isExpanded ? <ChevronDown className="h-3 w-3 flex-shrink-0" /> : <ChevronRight className="h-3 w-3 flex-shrink-0" />}
        <span className="text-sm font-medium break-words">{citation.tool_name}</span>
      </button>

      {isExpanded && (
        <div className="px-3 pb-3 pt-1 border-t bg-muted/30">
          {(citation.authors?.length || citation.year || citation.journal) ? <p className="text-xs text-muted-foreground mb-2">
            {[citation.authors?.join(', '), citation.year, citation.journal].filter(Boolean).join(' · ')}
          </p> : null}

          {citation.title && citation.title !== citation.tool_name && <p className="text-xs mb-2">{citation.title}</p>}

          {citation.locus && (
            <p className="text-xs mb-2 flex items-center gap-1 text-primary" data-testid="citation-locus">
              <MapPin className="h-3 w-3 flex-shrink-0" />
              <span className="text-muted-foreground">{t('citations.cited_for')}</span> {citation.locus}
            </p>
          )}

          {hasRecency && (
            <p className="text-fs-xs mb-2 text-muted-foreground" data-testid="citation-recency">
              {[citation.retrieval_date && t('citations.retrieved_on', { date: citation.retrieval_date }), citation.corpus_version]
                .filter(Boolean).join(' · ')}
            </p>
          )}

          {url && (
            <a href={url} target="_blank" rel="noopener noreferrer" className="text-xs text-primary hover:underline inline-flex items-center gap-1 mb-2 break-all">
              {citation.doi ? `doi:${citation.doi}` : citation.pmid ? `PMID ${citation.pmid}` : url}
              <ExternalLink className="h-3 w-3" />
            </a>
          )}

          <Separator className="my-2" />

          <div className="flex gap-2">
            {onRead && (
              <Button size="sm" variant="ghost" className="h-6 text-xs flex-1" onClick={onRead} data-testid={`read-${citation.tool_id}`}>
                <BookOpen className="h-3 w-3 mr-1" />
                {t('citations.read')}
              </Button>
            )}
            {citation.formatted_apa?.trim() && <Button
              size="sm" variant="ghost" className="h-6 text-xs flex-1"
              onClick={() => onCopy(citation.formatted_apa || citation.formatted_short || '', `apa-${citation.tool_id}`, 'apa')}
            >
              {copiedId === `apa-${citation.tool_id}` ? <Check className="h-3 w-3 mr-1 text-green-500" /> : <Copy className="h-3 w-3 mr-1" />}
              APA
            </Button>}
            {citation.formatted_bibtex?.trim() && <Button
              size="sm" variant="ghost" className="h-6 text-xs flex-1"
              onClick={() => onCopy(citation.formatted_bibtex || '', `bib-${citation.tool_id}`, 'bibtex')}
            >
              {copiedId === `bib-${citation.tool_id}` ? <Check className="h-3 w-3 mr-1 text-green-500" /> : <FileText className="h-3 w-3 mr-1" />}
              BibTeX
            </Button>}
          </div>
        </div>
      )}
    </div>
  )
}
