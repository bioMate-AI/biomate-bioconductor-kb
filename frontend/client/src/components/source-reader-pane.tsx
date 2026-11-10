import { tOr } from "@/lib/i18n"
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
  SheetDescription,
} from "@/components/ui/sheet"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { ChevronLeft, ChevronRight, ExternalLink, BookOpen } from "lucide-react"
import { cn } from "@/lib/utils"
import type { Citation } from "@shared/schema"

// Spec 01 §1.2 / §1.3.2: source locus + recency travel on the citation. These
// are optional evidence-anatomy fields the retrieval path MAY populate; the
// shared Citation type does not (yet) declare them, so we widen it locally
// rather than editing the shared schema. Absent fields simply do not render —
// no fabrication.
export type EvidenceCitation = Citation & {
  excerpt?: string | null
  locus?: string | null
  retrieval_date?: string | null
  corpus_version?: string | null
}

interface SourceReaderPaneProps {
  /** Ordered source list backing next/prev navigation. */
  sources: EvidenceCitation[]
  /** Index of the source currently open, or null when the pane is closed. */
  index: number | null
  onIndexChange: (index: number | null) => void
  className?: string
}

/** Resolve the best external URL for a source (DOI preferred, then PubMed). */
export function sourceUrl(c: EvidenceCitation): string | null {
  const doi = c.doi?.trim().replace(/^(?:https?:\/\/(?:dx\.)?doi\.org\/|doi:\s*)/i, '');
  if (doi) return `https://doi.org/${doi}`
  const pmid = c.pmid?.trim();
  if (pmid && /^\d+$/.test(pmid)) return `https://pubmed.ncbi.nlm.nih.gov/${pmid}`
  if (c.url && /^https?:\/\//i.test(c.url.trim())) return c.url.trim()
  return null
}

/**
 * Spec 01 §1.3.3 — Source reader.
 *
 * A right-hand pane (not a new tab) that shows a source's title / venue / year
 * and a "cited for" line naming the locus, with next/prev navigation so a
 * reader can audit a whole answer without leaving the thread.
 *
 * Show the retrieved abstract when available, followed by an external link
 * for full text. Missing content uses a compact fallback without a blank panel.
 */
export function SourceReaderPane({
  sources,
  index,
  onIndexChange,
  className,
}: SourceReaderPaneProps) {
  const open = index !== null && index >= 0 && index < sources.length
  const source = open ? sources[index as number] : null

  const goPrev = () => {
    if (index === null) return
    if (index > 0) onIndexChange(index - 1)
  }
  const goNext = () => {
    if (index === null) return
    if (index < sources.length - 1) onIndexChange(index + 1)
  }

  const venueYear = source
    ? [source.journal, source.year ? String(source.year) : null]
        .filter(Boolean)
        .join(" · ")
    : ""
  const url = source ? sourceUrl(source) : null

  return (
    <Sheet
      open={open}
      onOpenChange={(isOpen) => {
        if (!isOpen) onIndexChange(null)
      }}
    >
      <SheetContent
        side="right"
        aria-describedby={undefined}
        className={cn("w-full sm:max-w-md flex flex-col", className)}
        data-testid="source-reader-pane"
      >
        {source && (
          <>
            <SheetHeader className="space-y-2 text-left shrink-0">
              <div className="flex items-center gap-2 text-xs text-muted-foreground">
                <BookOpen className="h-3.5 w-3.5" />
                <span>
                  Source {(index as number) + 1} of {sources.length}
                </span>
              </div>
              <SheetTitle className="text-base leading-snug">
                {source.title || source.tool_name || "Untitled source"}
              </SheetTitle>
              {source.authors?.filter(author => author.trim()).length > 0 && (
                <p className="text-xs text-muted-foreground" data-testid="reader-authors">{source.authors.filter(author => author.trim()).join(', ')}</p>
              )}
              {venueYear && (
                <SheetDescription className="text-xs">
                  {venueYear}
                </SheetDescription>
              )}
              {source.locus && (
                <div
                  className="text-xs text-primary flex items-center gap-1"
                  data-testid="reader-locus"
                >
                  <span className="text-muted-foreground">cited for:</span>
                  <Badge variant="outline" className="text-fs-xs px-1 py-0">
                    {source.locus}
                  </Badge>
                </div>
              )}
              {(source.retrieval_date || source.corpus_version) && (
                <div className="text-fs-xs text-muted-foreground">
                  {source.retrieval_date && (
                    <span>Retrieved {source.retrieval_date}</span>
                  )}
                  {source.retrieval_date && source.corpus_version && (
                    <span> · </span>
                  )}
                  {source.corpus_version && (
                    <span>{source.corpus_version}</span>
                  )}
                </div>
              )}
            </SheetHeader>

            <div className="flex-1 min-h-0 mt-4 overflow-y-auto space-y-4 text-sm leading-relaxed break-words">
              {source.abstract?.trim() && <section data-testid="reader-abstract"><h3 className="font-medium mb-2">Abstract</h3><p className="whitespace-pre-wrap">{source.abstract}</p></section>}
              {source.excerpt?.trim() && <section data-testid="reader-excerpt"><h3 className="font-medium mb-2">{tOr('citation_reader.retrieved_excerpt', 'Retrieved excerpt')}</h3><blockquote className="border-l-2 pl-3 whitespace-pre-wrap">{source.excerpt}</blockquote></section>}
              {!source.abstract?.trim() && !source.excerpt?.trim() && <p className="text-xs text-muted-foreground" data-testid="reader-no-content">{tOr('citation_reader.no_abstract_excerpt', 'No abstract or excerpt was supplied for this source.')}</p>}
              <p className="text-xs text-muted-foreground">
                Full text is not available in the reader for this source. Open it
                at the publisher to read
                {source.locus ? ` the ${source.locus}` : " the relied-on passage"}
                .
              </p>
              {url ? (
                <a href={url} target="_blank" rel="noopener noreferrer">
                  <Button size="sm" variant="outline" data-testid="reader-open-source">
                    Open at source
                    <ExternalLink className="h-3.5 w-3.5 ml-1.5" />
                  </Button>
                </a>
              ) : (
                <p className="text-xs text-muted-foreground italic">
                  {tOr('citation_reader.no_source_link', 'No source link was supplied.')}
                </p>
              )}
            </div>

            <div className="mt-4 shrink-0 flex items-center justify-between border-t pt-3">
              <Button
                size="sm"
                variant="ghost"
                className="h-8 text-xs"
                onClick={goPrev}
                disabled={index === 0}
                data-testid="reader-prev"
              >
                <ChevronLeft className="h-4 w-4 mr-1" />
                Previous source
              </Button>
              <Button
                size="sm"
                variant="ghost"
                className="h-8 text-xs"
                onClick={goNext}
                disabled={index === sources.length - 1}
                data-testid="reader-next"
              >
                Next source
                <ChevronRight className="h-4 w-4 ml-1" />
              </Button>
            </div>
          </>
        )}
      </SheetContent>
    </Sheet>
  )
}
