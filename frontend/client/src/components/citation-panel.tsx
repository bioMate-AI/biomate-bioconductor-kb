import { useState } from "react"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible"
import { Separator } from "@/components/ui/separator"
import { Textarea } from "@/components/ui/textarea"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
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
  Loader2
} from "lucide-react"
import { cn } from "@/lib/utils"
import {
  exportCitationsBibTeX,
  generateMethodsSection,
  downloadAsFile,
  copyToClipboard
} from "@/lib/ai-assistant-api"
import type { Citation, MethodsSection } from "@shared/schema"

interface CitationPanelProps {
  citations: Citation[]
  methodsSection?: MethodsSection
  workflow?: Record<string, any>  // Galaxy workflow for API calls
  isCollapsed?: boolean
  onCopy?: (text: string, format: 'apa' | 'bibtex' | 'short') => void
  onExportBibTeX?: () => void
  onMethodsSectionUpdated?: (newSection: MethodsSection) => void
  className?: string
}

export function CitationPanel({
  citations,
  methodsSection,
  workflow,
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
  const [citationStyle, setCitationStyle] = useState<'short' | 'apa' | 'numbered'>('short')
  const [localMethodsSection, setLocalMethodsSection] = useState<MethodsSection | undefined>(methodsSection)

  const toolsWithCitations = citations.filter(c => c.doi || c.pmid || c.title)
  const totalTools = citations.length

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
      .filter(c => c.formatted_bibtex)
      .map(c => c.formatted_bibtex)
      .join('\n\n')

    if (bibtexContent) {
      downloadAsFile(bibtexContent, 'workflow_citations.bib', 'application/x-bibtex')
      onExportBibTeX?.()
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
          <div className="flex items-center justify-between">
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
                {toolsWithCitations.length}/{totalTools} tools
              </Badge>
              {toolsWithCitations.length > 0 && (
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
              <TabsList className="grid w-full grid-cols-2 h-8">
                <TabsTrigger value="citations" className="text-xs">
                  Tool Citations
                </TabsTrigger>
                <TabsTrigger value="methods" className="text-xs" disabled={!displayMethodsSection && !workflow}>
                  Methods Section
                </TabsTrigger>
              </TabsList>

              <TabsContent value="citations" className="mt-3 space-y-2">
                {toolsWithCitations.length === 0 ? (
                  <p className="text-xs text-muted-foreground text-center py-4">
                    No citations available for tools in this workflow
                  </p>
                ) : (
                  toolsWithCitations.map((citation) => (
                    <CitationItem
                      key={citation.tool_id}
                      citation={citation}
                      isExpanded={expandedCitations.has(citation.tool_id)}
                      onToggle={() => toggleCitationExpanded(citation.tool_id)}
                      onCopy={handleCopy}
                      copiedId={copiedId}
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
    </Card>
  )
}

interface CitationItemProps {
  citation: Citation
  isExpanded: boolean
  onToggle: () => void
  onCopy: (text: string, id: string, format: 'apa' | 'bibtex' | 'short') => void
  copiedId: string | null
}

function CitationItem({ citation, isExpanded, onToggle, onCopy, copiedId }: CitationItemProps) {
  return (
    <div className="border rounded-md">
      <button
        onClick={onToggle}
        className="w-full p-2 flex items-center justify-between text-left hover:bg-muted/50 transition-colors"
      >
        <div className="flex items-center gap-2 flex-1 min-w-0">
          {isExpanded ? (
            <ChevronDown className="h-3 w-3 flex-shrink-0" />
          ) : (
            <ChevronRight className="h-3 w-3 flex-shrink-0" />
          )}
          <span className="text-sm font-medium truncate">{citation.tool_name}</span>
        </div>
        <div className="flex items-center gap-1.5 flex-shrink-0">
          {citation.doi && (
            <Badge variant="outline" className="text-[10px] px-1 py-0">DOI</Badge>
          )}
          {citation.pmid && (
            <Badge variant="outline" className="text-[10px] px-1 py-0">PMID</Badge>
          )}
        </div>
      </button>

      {isExpanded && (
        <div className="px-3 pb-3 pt-1 border-t bg-muted/30">
          <p className="text-xs text-muted-foreground mb-2">
            {citation.formatted_short || `${citation.authors?.[0] || 'Unknown'} et al., ${citation.year || 'n.d.'}`}
          </p>

          {citation.title && (
            <p className="text-xs mb-2 line-clamp-2">{citation.title}</p>
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
            <Button
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
            </Button>
            <Button
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
            </Button>
          </div>
        </div>
      )}
    </div>
  )
}
