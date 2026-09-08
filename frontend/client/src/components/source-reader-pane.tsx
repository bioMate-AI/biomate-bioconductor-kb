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
  if (c.doi) return `https://doi.org/${c.doi}`
  if (c.pmid) return `https://pubmed.ncbi.nlm.nih.gov/${c.pmid}`
  return null
}

/**
 * Spec 01 §1.3.3 — Source reader.
 *
 * A right-hand pane (not a new tab) that shows a source's title / venue / year
 * and a "cited for" line naming the locus, with next/prev navigation so a
 * reader can audit a whole answer without leaving the thread.
 *
 * Full text is not available to us, so the body is an honest "open at source"
 * fallback to the DOI / PubMed URL rather than a faked passage.
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
        className={cn("w-full sm:max-w-md flex flex-col", className)}
        data-testid="source-reader-pane"
      >
        {source && (
          <>
            <SheetHeader className="space-y-2 text-left">
              <div className="flex items-center gap-2 text-xs text-muted-foreground">
                <BookOpen className="h-3.5 w-3.5" />
                <span>
                  Source {(index as number) + 1} of {sources.length}
                </span>
              </div>
              <SheetTitle className="text-base leading-snug">
                {source.title || source.tool_name || "Untitled source"}
              </SheetTitle>
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
                  <Badge variant="outline" className="text-[10px] px-1 py-0">
                    {source.locus}
                  </Badge>
                </div>
              )}
              {(source.retrieval_date || source.corpus_version) && (
                <div className="text-[11px] text-muted-foreground">
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

            <div className="flex-1 min-h-0 mt-4 rounded-md border bg-muted/30 p-4 flex flex-col items-center justify-center text-center gap-3">
              <p className="text-xs text-muted-foreground max-w-xs">
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
                  No DOI or PubMed link available for this source.
                </p>
              )}
            </div>

            <div className="mt-4 flex items-center justify-between border-t pt-3">
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
