import { useState } from "react"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
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
  StickyNote,
  Pin
} from "lucide-react"
import { cn } from "@/lib/utils"
import {
  exportCitationsBibTeX,
  generateMethodsSection,
  downloadAsFile,
  copyToClipboard
} from "@/lib/ai-assistant-api"
import { api } from "@/lib/api"
import { useActiveProjectIdSafe } from "@/contexts/active-project-context"
import { useToast } from "@/hooks/use-toast"
import type { Citation, MethodsSection } from "@shared/schema"
import { SourceReaderPane, sourceUrl, type EvidenceCitation } from "@/components/source-reader-pane"

// Spec 01 §1.3.2: a materially-disagreeing pair of findings, surfaced honestly.
/**
 * Retrieval transparency (v2 Spec 09, "How this was searched").
 * One row per source the retrieval path queried, carrying how many records
 * were found vs. kept. ONLY rendered when the retrieval path supplies real
 * counts — never fabricated, never inferred from the citation list. Absent →
 * the section does not render (honest-empty).
 */
export interface RetrievalSource {
  /** Source name, e.g. "PubMed", "Europe PMC", "bioRxiv". */
  name: string
  /** Records the source returned for the query. */
  found: number
  /** Records kept after filtering (years/species/relevance). */
  kept: number
}

// Only rendered when the retrieval path marks a conflict — never fabricated.
export interface CitationConflict {
  /** Short label for the disagreement, e.g. "Effect at physiological dose". */
  topic?: string
  /** The two (or more) positions in tension, each with the source it rests on. */
  positions: Array<{ claim: string; source?: string }>
}

interface CitationPanelProps {
  kind?: "workflow" | "literature"
  citations: Citation[]
  methodsSection?: MethodsSection
  workflow?: Record<string, any>  // Galaxy workflow for API calls
  /**
   * Spec 01 §1.3.2 conflict affordance. When the retrieval path detects that
   * sources materially disagree, it passes the conflicting positions here and
   * a "Sources disagree" row is shown. Omit / empty → row never renders.
   */
  conflicts?: CitationConflict[]
  /**
   * Spec 09 — retrieval transparency. When the retrieval path reports how many
   * records each source returned and how many survived filtering, a "How this
   * was searched" section is shown (per-source found · kept + a "N of M kept"
   * summary). Omit / empty → the section never renders (no fabrication).
   */
  retrieval?: RetrievalSource[]
  /**
   * Spec 01 §1.3.2 / §1.5 — the synthesised answer body this citation set
   * backs. When present it is included verbatim in the "Save to project
   * notes" payload so provenance (claim + its sources) travels together. If
   * absent, only the source list is saved.
   */
  answerText?: string
  isCollapsed?: boolean
  onCopy?: (text: string, format: 'apa' | 'bibtex' | 'short') => void
  onExportBibTeX?: () => void
  onMethodsSectionUpdated?: (newSection: MethodsSection) => void
  className?: string
}

export function CitationPanel({
  kind = "workflow",
  citations,
  methodsSection,
  workflow,
  conflicts,
  retrieval,
  answerText,
  isCollapsed = true,
  onCopy,
  onExportBibTeX,
  onMethodsSectionUpdated,
  className
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
  const [isSavingNote, setIsSavingNote] = useState(false)
  const [isSavingInstruction, setIsSavingInstruction] = useState(false)

  const activeProjectId = useActiveProjectIdSafe()
  const { toast } = useToast()

  const toolsWithCitations = citations.filter(c => c.doi || c.pmid || c.title) as EvidenceCitation[]
  const totalTools = citations.length
  // The top-level "Export BibTeX" can only produce a file when either a workflow
  // is present (server-side export) or at least one citation carries a
  // formatted_bibtex (local export). Literature answers have neither, so hide the
  // button rather than show one that silently emits nothing (a dead button).
  const canExportBibTeX = Boolean(workflow) || citations.some(c => c.formatted_bibtex?.trim())
  const activeConflicts = (conflicts || []).filter(c => c.positions && c.positions.length > 0)
  // Spec 09 — only surfaces when the retrieval path supplied real per-source
  // counts. We never derive these from the citation list (that would be a
  // fabricated "kept"); absent → section omitted.
  const retrievalSources = (retrieval || []).filter(
    s => s && s.name && Number.isFinite(s.found) && Number.isFinite(s.kept) && s.found >= 0 && s.kept >= 0 && s.kept <= s.found,
  )
  const retrievalKept = retrievalSources.reduce((n, s) => n + s.kept, 0)
  const retrievalFound = retrievalSources.reduce((n, s) => n + s.found, 0)

  const toggleCitationExpanded = (toolId: string) => {
    setExpandedCitations(prev => {
      const next = new Set(prev)
      if (next.has(toolId)) {
        next.delete(toolId)
      } else {
        next.add(toolId)
      }
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

  const handleExportAll = async () => {
    // If workflow is provided, use API for comprehensive export
    if (workflow) {
      setIsExporting(true)
      try {
        const response = await exportCitationsBibTeX(workflow, true)
        if (response.success && response.bibtex) {
          downloadAsFile(response.bibtex, 'workflow_citations.bib', 'application/x-bibtex')
          onExportBibTeX?.()
        }
      } catch (err) {
        console.error('Failed to export citations via API:', err)
        // Fallback to local export
        fallbackExport()
      } finally {
        setIsExporting(false)
      }
    } else {
      // Fallback: use local citation data
      fallbackExport()
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

  /**
   * Spec 01 §1.5 — "Save to project notes". Writes the answer, with its
   * sources, into the active project so provenance travels. Backed by the
   * real project-knowledge endpoint (POST /api/memory/projects/:id/knowledge)
   * with knowledgeType='notes_synthesis', which the Project Notes page reads.
   * Requires an active project — the button is disabled (with a tooltip)
   * when none is selected, never a fake success.
   */
  const buildNoteMarkdown = (): string => {
    const lines: string[] = []
    if (answerText && answerText.trim()) {
      lines.push(answerText.trim(), "")
    }
    if (toolsWithCitations.length > 0) {
      lines.push("## Sources", "")
      toolsWithCitations.forEach((c, i) => {
        const parts: string[] = []
        const label = c.title || c.tool_name || "Untitled source"
        const venueYear = [c.journal, c.year ? String(c.year) : null]
          .filter(Boolean)
          .join(" · ")
        parts.push(`${i + 1}. ${label}${venueYear ? ` — ${venueYear}` : ""}`)
        if (c.locus) parts.push(`   cited for: ${c.locus}`)
        const url = sourceUrl(c)
        if (url) parts.push(`   ${url}`)
        lines.push(parts.join("\n"))
      })
    }
    return lines.join("\n").trim()
  }

  const handleSaveToNotes = async () => {
    if (!activeProjectId || isSavingNote) return
    const content = buildNoteMarkdown()
    if (!content) {
      toast({
        title: "Nothing to save",
        description: "This answer has no cited sources yet.",
        variant: "destructive",
      })
      return
    }
    setIsSavingNote(true)
    try {
      await api.request(`/memory/projects/${activeProjectId}/knowledge`, {
        method: "POST",
        body: JSON.stringify({
          knowledgeType: "notes_synthesis",
          title: `Saved answer — ${new Date().toISOString().slice(0, 10)}`,
          content,
          source: "user_saved",
        }),
      })
      toast({
        title: "Saved to project notes",
        description: "The answer and its sources were added to this project.",
      })
    } catch (e: any) {
      console.error("[citations] save to notes failed:", e?.message ?? e)
      toast({
        title: "Could not save",
        description: e?.message || "Saving to project notes failed.",
        variant: "destructive",
      })
    } finally {
      setIsSavingNote(false)
    }
  }

  /**
   * Spec 01 §1.5 — "Make a project instruction". Promotes this answer to a
   * standing project instruction the assistant applies in future chats
   * (consumed server-side into <project_context>). Saves a CONCISE, bounded
   * directive (not the whole answer) as a discrete project_instruction row, so
   * the injected instruction list stays selective and can't flood the prompt.
   */
  const handleMakeInstruction = async () => {
    if (!activeProjectId || isSavingInstruction) return
    const src = (answerText || "").replace(/\s+/g, " ").trim()
    if (!src) {
      toast({
        title: "Nothing to promote",
        description: "This answer is empty.",
        variant: "destructive",
      })
      return
    }
    // A standing instruction is a short directive — bound to ~300 chars and
    // avoid a mid-word cut.
    let directive = src.slice(0, 300)
    if (directive.length < src.length) directive = directive.replace(/\s+\S*$/, "") + "…"
    setIsSavingInstruction(true)
    try {
      await api.request(`/memory/projects/${activeProjectId}/knowledge`, {
        method: "POST",
        body: JSON.stringify({
          knowledgeType: "project_instruction",
          title: `Instruction — ${new Date().toISOString().slice(0, 10)}`,
          content: directive,
          source: "user_saved",
        }),
      })
      toast({
        title: "Saved as a project instruction",
        description: "The assistant will apply this in this project's chats when relevant.",
      })
    } catch (e: any) {
      console.error("[citations] make instruction failed:", e?.message ?? e)
      toast({
        title: "Could not save",
        description: e?.message || "Saving the instruction failed.",
        variant: "destructive",
      })
    } finally {
      setIsSavingInstruction(false)
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

  // Use local state for methods section (allows regeneration updates)
  const displayMethodsSection = localMethodsSection || methodsSection

  // Don't render if no citations and no methods section (unless we have workflow to generate one)
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
                  {isExpanded ? (
                    <ChevronDown className="h-4 w-4" />
                  ) : (
                    <ChevronRight className="h-4 w-4" />
                  )}
                  <BookOpen className="h-4 w-4 text-primary" />
                  <span className="font-medium text-sm">Citations</span>
                </div>
              </Button>
            </CollapsibleTrigger>

            <div className="flex items-center gap-2">
              <Badge variant="secondary" className="text-xs">
                {kind === "literature" ? `${toolsWithCitations.length} sources` : `${toolsWithCitations.length}/${totalTools} tools`}
              </Badge>

              {/* Spec 01 §1.5 — answer→project exits. Two sanctioned exits
                  from the search module into the rest of the product. */}
              <TooltipProvider>
                <Tooltip>
                  <TooltipTrigger asChild>
                    {/* span wrapper: a disabled button does not fire pointer
                        events, so the tooltip needs a live element to hover. */}
                    <span tabIndex={activeProjectId ? -1 : 0}>
                      <Button
                        size="sm"
                        variant="outline"
                        className="h-7 text-xs"
                        onClick={handleSaveToNotes}
                        disabled={!activeProjectId || isSavingNote}
                        data-testid="answer-save-notes"
                      >
                        {isSavingNote ? (
                          <Loader2 className="h-3 w-3 mr-1 animate-spin" />
                        ) : (
                          <StickyNote className="h-3 w-3 mr-1" />
                        )}
                        Save to notes
                      </Button>
                    </span>
                  </TooltipTrigger>
                  <TooltipContent>
                    {activeProjectId
                      ? "Save this answer and its sources to the project's notes"
                      : "Select a project to save this answer to its notes"}
                  </TooltipContent>
                </Tooltip>
              </TooltipProvider>

              {/* Spec 01 §1.5 — "Make a project instruction" promotes a finding
                  to a standing instruction the assistant applies in this
                  project's future chats (consumed into <project_context>). */}
              <TooltipProvider>
                <Tooltip>
                  <TooltipTrigger asChild>
                    <span tabIndex={activeProjectId ? -1 : 0}>
                      <Button
                        size="sm"
                        variant="outline"
                        className="h-7 text-xs"
                        onClick={handleMakeInstruction}
                        disabled={!activeProjectId || isSavingInstruction}
                        data-testid="answer-make-instruction"
                      >
                        {isSavingInstruction ? (
                          <Loader2 className="h-3 w-3 mr-1 animate-spin" />
                        ) : (
                          <Pin className="h-3 w-3 mr-1" />
                        )}
                        Make instruction
                      </Button>
                    </span>
                  </TooltipTrigger>
                  <TooltipContent>
                    {activeProjectId
                      ? "Promote this answer to a standing instruction for this project"
                      : "Select a project to save a standing instruction"}
                  </TooltipContent>
                </Tooltip>
              </TooltipProvider>

              {toolsWithCitations.length > 0 && canExportBibTeX && (
                <Button
                  size="sm"
                  variant="outline"
                  className="h-7 text-xs"
                  onClick={handleExportAll}
                  disabled={isExporting}
                >
                  {isExporting ? (
                    <Loader2 className="h-3 w-3 mr-1 animate-spin" />
                  ) : (
                    <Download className="h-3 w-3 mr-1" />
                  )}
                  Export BibTeX
                </Button>
              )}
            </div>
          </div>
        </CardHeader>

        <CollapsibleContent>
          <CardContent className="p-3 pt-0">
            <Tabs value={activeTab} onValueChange={setActiveTab}>
              {kind === "workflow" && (!!displayMethodsSection || !!workflow) && <TabsList className="grid w-full grid-cols-2 h-auto min-h-8">
                <TabsTrigger value="citations" className="text-xs">
                  Tool Citations
                </TabsTrigger>
                <TabsTrigger value="methods" className="text-xs" disabled={!displayMethodsSection && !workflow}>
                  Methods Section
                </TabsTrigger>
              </TabsList>}

              <TabsContent value="citations" className="mt-3 space-y-2">
                {/* Spec 09 — "How this was searched". Retrieval transparency:
                    per-source found · kept. Only rendered when the retrieval
                    path supplied real counts (honest-empty otherwise). */}
                {retrievalSources.length > 0 && (
                  <details
                    className="rounded-md bg-muted/30 p-2.5 space-y-1.5"
                    data-testid="retrieval-transparency"
                  >
                    <summary className="cursor-pointer text-xs font-medium flex flex-wrap items-center gap-2">
                      <span>How this was searched</span>
                      <span className="flex-1" />
                      <Badge
                        variant="secondary"
                        className="text-fs-xs font-normal"
                        data-testid="retrieval-summary"
                      >
                        {retrievalKept} of {retrievalFound} kept
                      </Badge>
                    </summary>
                    <div className="space-y-1">
                      {retrievalSources.map((s) => (
                        <p key={s.name} className="text-fs-xs leading-relaxed break-words" data-testid={`retrieval-source-${s.name}`}>
                          {s.name}: {s.found} found · <span className="font-medium">{s.kept} kept</span>
                        </p>
                      ))}
                    </div>
                  </details>
                )}

                {/* Spec 01 §1.3.2 — conflict affordance. Never smooth
                    disagreement into a single confident sentence. */}
                {activeConflicts.length > 0 && (
                  <ConflictRow
                    conflicts={activeConflicts}
                    isExpanded={conflictsExpanded}
                    onToggle={() => setConflictsExpanded(prev => !prev)}
                  />
                )}

                {toolsWithCitations.length === 0 ? (
                  <p className="text-xs text-muted-foreground text-center py-4">
                    No citations available for tools in this workflow
                  </p>
                ) : (
                  toolsWithCitations.map((citation, idx) => (
                    <CitationItem
                      key={citation.tool_id}
                      citation={citation}
                      index={idx}
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
                      <strong>Missing citations:</strong> {displayMethodsSection.tools_missing_citations.join(', ')}
                    </p>
                  </div>
                )}
              </TabsContent>

              <TabsContent value="methods" className="mt-3">
                {displayMethodsSection ? (
                  <div className="space-y-3">
                    <div className="flex items-center justify-between gap-2">
                      <div className="flex items-center gap-2">
                        <span className="text-xs text-muted-foreground">Style:</span>
                        <Select
                          value={citationStyle}
                          onValueChange={(value: 'short' | 'apa' | 'numbered') => {
                            setCitationStyle(value)
                            if (workflow) {
                              handleRegenerateMethodsSection(value)
                            }
                          }}
                          disabled={isRegenerating || !workflow}
                        >
                          <SelectTrigger className="h-7 w-[100px] text-xs">
                            <SelectValue />
                          </SelectTrigger>
                          <SelectContent>
                            <SelectItem value="short">Short</SelectItem>
                            <SelectItem value="apa">APA</SelectItem>
                            <SelectItem value="numbered">Numbered</SelectItem>
                          </SelectContent>
                        </Select>
                        {isRegenerating && (
                          <Loader2 className="h-3 w-3 animate-spin text-muted-foreground" />
                        )}
                      </div>
                      <div className="flex items-center gap-1">
                        {workflow && (
                          <Button
                            size="sm"
                            variant="ghost"
                            className="h-7 text-xs"
                            onClick={() => handleRegenerateMethodsSection(citationStyle)}
                            disabled={isRegenerating}
                          >
                            <RefreshCw className={cn("h-3 w-3 mr-1", isRegenerating && "animate-spin")} />
                            Regenerate
                          </Button>
                        )}
                        <Button
                          size="sm"
                          variant="ghost"
                          className="h-7 text-xs"
                          onClick={() => handleCopy(displayMethodsSection.text, 'methods', 'apa')}
                        >
                          {copiedId === 'methods' ? (
                            <Check className="h-3 w-3 mr-1 text-green-500" />
                          ) : (
                            <Copy className="h-3 w-3 mr-1" />
                          )}
                          Copy
                        </Button>
                      </div>
                    </div>
                    <Textarea
                      value={displayMethodsSection.text}
                      readOnly
                      className="min-h-[200px] text-xs font-mono resize-y"
                    />
                    <div className="flex items-center justify-between text-xs text-muted-foreground">
                      <span>{displayMethodsSection.tools_cited.length} tool(s) cited</span>
                      {displayMethodsSection.tools_missing_citations && displayMethodsSection.tools_missing_citations.length > 0 && (
                        <span className="text-yellow-600 dark:text-yellow-400">
                          {displayMethodsSection.tools_missing_citations.length} tool(s) missing citations
                        </span>
                      )}
                    </div>
                  </div>
                ) : workflow ? (
                  <div className="text-center py-4 space-y-2">
                    <p className="text-xs text-muted-foreground">
                      Generate a methods section for your publication
                    </p>
                    <Button
                      size="sm"
                      variant="outline"
                      onClick={() => handleRegenerateMethodsSection('short')}
                      disabled={isRegenerating}
                    >
                      {isRegenerating ? (
                        <Loader2 className="h-3 w-3 mr-1 animate-spin" />
                      ) : (
                        <FileText className="h-3 w-3 mr-1" />
                      )}
                      Generate Methods Section
                    </Button>
                  </div>
                ) : (
                  <p className="text-xs text-muted-foreground text-center py-4">
                    Methods section not available
                  </p>
                )}
              </TabsContent>
            </Tabs>
          </CardContent>
        </CollapsibleContent>
      </Collapsible>

      {/* Spec 01 §1.3.3 — right-hand source reader with next/prev navigation. */}
      <SourceReaderPane
        sources={toolsWithCitations}
        index={readerIndex}
        onIndexChange={setReaderIndex}
      />
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
    <div
      className="border border-amber-500/40 rounded-md bg-amber-500/5"
      data-testid="conflict-row"
    >
      <button
        onClick={onToggle}
        className="w-full p-2 flex items-center justify-between text-left hover:bg-amber-500/10 transition-colors rounded-md"
      >
        <div className="flex items-center gap-2 min-w-0">
          <Flag className="h-3.5 w-3.5 text-amber-600 dark:text-amber-400 flex-shrink-0" />
          <span className="text-xs font-medium text-amber-700 dark:text-amber-300 truncate">
            Sources disagree — {count} conflicting finding{count === 1 ? '' : 's'}
          </span>
        </div>
        {isExpanded ? (
          <ChevronDown className="h-3.5 w-3.5 flex-shrink-0 text-amber-600 dark:text-amber-400" />
        ) : (
          <ChevronRight className="h-3.5 w-3.5 flex-shrink-0 text-amber-600 dark:text-amber-400" />
        )}
      </button>

      {isExpanded && (
        <div className="px-3 pb-3 pt-1 space-y-3">
          {conflicts.map((conflict, ci) => (
            <div key={ci} className="space-y-1.5">
              {conflict.topic && (
                <p className="text-xs font-medium text-muted-foreground">{conflict.topic}</p>
              )}
              <div className="grid gap-2">
                {conflict.positions.map((pos, pi) => (
                  <div
                    key={pi}
                    className="text-xs p-2 rounded border bg-background/60"
                  >
                    <p>{pos.claim}</p>
                    {pos.source && (
                      <p className="mt-1 text-fs-xs text-muted-foreground">— {pos.source}</p>
                    )}
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
  /** Position in the answer's source list — backs the reader's next/prev. */
  index: number
  isExpanded: boolean
  onToggle: () => void
  onCopy: (text: string, id: string, format: 'apa' | 'bibtex' | 'short') => void
  copiedId: string | null
  onRead?: () => void
}

function CitationItem({ citation, index, isExpanded, onToggle, onCopy, copiedId, onRead }: CitationItemProps) {
  const hasRecency = Boolean(citation.retrieval_date || citation.corpus_version)
  return (
    <div className="border rounded-md">
      <div className="w-full p-2 flex items-center justify-between hover:bg-muted/50 transition-colors">
        <button
          onClick={onToggle}
          className="flex items-center gap-2 flex-1 min-w-0 text-left"
        >
          {isExpanded ? (
            <ChevronDown className="h-3 w-3 flex-shrink-0" />
          ) : (
            <ChevronRight className="h-3 w-3 flex-shrink-0" />
          )}
          <span className="text-sm font-medium break-words">{citation.tool_name}</span>
        </button>
        <div className="flex items-center gap-1.5 flex-shrink-0">
          {citation.locus && (
            <Badge variant="outline" className="text-fs-xs px-1 py-0 hidden sm:inline-flex">
              {citation.locus}
            </Badge>
          )}
          {citation.doi && (
            <Badge variant="outline" className="text-fs-xs px-1 py-0">DOI</Badge>
          )}
          {citation.pmid && (
            <Badge variant="outline" className="text-fs-xs px-1 py-0">PMID</Badge>
          )}
          {/* Spec 01 §1.3.2 answer anatomy — an inline "open ▸" per source
              that opens the right-hand reader pane at this source. */}
          {onRead && (
            <Button
              size="sm"
              variant="ghost"
              className="h-6 px-1.5 text-fs-xs"
              onClick={onRead}
              data-testid={`source-open-${index}`}
              aria-label={`Open source ${index + 1} in reader`}
            >
              open
              <ChevronRight className="h-3 w-3 ml-0.5" />
            </Button>
          )}
        </div>
      </div>

      {isExpanded && (
        <div className="px-3 pb-3 pt-1 border-t bg-muted/30">
          {(citation.authors?.length || citation.year || citation.journal) ? <p className="text-xs text-muted-foreground mb-2">
            {[citation.authors?.join(', '), citation.year, citation.journal].filter(Boolean).join(' · ')}
          </p> : null}

          {citation.title && citation.title !== citation.tool_name && <p className="text-xs mb-2">{citation.title}</p>}
          {citation.abstract?.trim() && <p className="text-xs mb-2 line-clamp-3" data-testid="citation-abstract">{citation.abstract}</p>}

          {/* Spec 01 §1.3.2 — the locus relied on, not a bare DOI list. */}
          {citation.locus && (
            <p
              className="text-xs mb-2 flex items-center gap-1 text-primary"
              data-testid="citation-locus"
            >
              <MapPin className="h-3 w-3 flex-shrink-0" />
              <span className="text-muted-foreground">cited for:</span> {citation.locus}
            </p>
          )}

          {/* Spec 01 §1.4.2 — recency is stated, not implied. */}
          {hasRecency && (
            <p
              className="text-fs-xs mb-2 text-muted-foreground"
              data-testid="citation-recency"
            >
              {citation.retrieval_date && <span>Retrieved {citation.retrieval_date}</span>}
              {citation.retrieval_date && citation.corpus_version && <span> · </span>}
              {citation.corpus_version && <span>{citation.corpus_version}</span>}
            </p>
          )}

          <div className="flex flex-wrap gap-2 mb-2">
            {citation.doi && (
              <a
                href={`https://doi.org/${citation.doi}`}
                target="_blank"
                rel="noopener noreferrer"
                className="text-xs text-primary hover:underline flex items-center gap-1"
              >
                DOI: {citation.doi}
                <ExternalLink className="h-3 w-3" />
              </a>
            )}
            {citation.pmid && (
              <a
                href={`https://pubmed.ncbi.nlm.nih.gov/${citation.pmid}`}
                target="_blank"
                rel="noopener noreferrer"
                className="text-xs text-primary hover:underline flex items-center gap-1"
              >
                PMID: {citation.pmid}
                <ExternalLink className="h-3 w-3" />
              </a>
            )}
          </div>

          <Separator className="my-2" />

          <div className="flex gap-2">
            {onRead && (
              <Button
                size="sm"
                variant="ghost"
                className="h-6 text-xs flex-1"
                onClick={onRead}
                data-testid={`read-${citation.tool_id}`}
              >
                <BookOpen className="h-3 w-3 mr-1" />
                Read
              </Button>
            )}
            {citation.formatted_apa?.trim() && <Button
              size="sm"
              variant="ghost"
              className="h-6 text-xs flex-1"
              onClick={() => onCopy(citation.formatted_apa || citation.formatted_short || '', `apa-${citation.tool_id}`, 'apa')}
            >
              {copiedId === `apa-${citation.tool_id}` ? (
                <Check className="h-3 w-3 mr-1 text-green-500" />
              ) : (
                <Copy className="h-3 w-3 mr-1" />
              )}
              APA
            </Button>}
            {citation.formatted_bibtex?.trim() && <Button
              size="sm"
              variant="ghost"
              className="h-6 text-xs flex-1"
              onClick={() => onCopy(citation.formatted_bibtex || '', `bib-${citation.tool_id}`, 'bibtex')}
              disabled={!citation.formatted_bibtex}
            >
              {copiedId === `bib-${citation.tool_id}` ? (
                <Check className="h-3 w-3 mr-1 text-green-500" />
              ) : (
                <FileText className="h-3 w-3 mr-1" />
              )}
              BibTeX
            </Button>}
          </div>
        </div>
      )}
    </div>
  )
}
