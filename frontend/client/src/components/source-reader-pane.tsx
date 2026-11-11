import { useEffect, useState } from "react"
import { t } from "@/lib/i18n"
import { api } from "@/lib/api"
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
  SheetDescription,
} from "@/components/ui/sheet"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { ChevronLeft, ChevronRight, ExternalLink, BookOpen, Loader2 } from "lucide-react"
import { cn } from "@/lib/utils"
import type { Citation } from "@shared/schema"

// Spec 01 §1.2 / §1.3.2: source locus + recency travel on the citation. These
// are optional evidence-anatomy fields the retrieval path MAY populate; the
// shared Citation type does not (yet) declare them, so we widen it locally
// rather than editing the shared schema. Absent fields simply do not render —
// no fabrication.
export type EvidenceCitation = Citation & {
  pmcid?: string | null
  excerpt?: string | null
  locus?: string | null
  retrieval_date?: string | null
  corpus_version?: string | null
}

/** Shape returned by GET /api/literature/fulltext (server/literature-fulltext-routes.ts). */
export interface ReaderFulltext {
  found: boolean
  title: string | null
  journal: string | null
  year: string | null
  authors: string | null
  abstract: string | null
  openAccess: boolean
  license: string | null
  fullTextStatus: "available" | "not_open_access" | "unavailable" | "not_found"
  sections: Array<{ heading: string | null; paragraphs: string[] }>
  truncated: boolean
  links: { publisher: string | null; europepmc: string | null }
}

interface SourceReaderPaneProps {
  /** Ordered source list backing next/prev navigation. */
  sources: EvidenceCitation[]
  /** Index of the source currently open, or null when the pane is closed. */
  index: number | null
  onIndexChange: (index: number | null) => void
  className?: string
}

function cleanDoi(doi?: string | null): string {
  return (doi || "").trim().replace(/^(?:https?:\/\/(?:dx\.)?doi\.org\/|doi:\s*)/i, "")
}

/** Resolve the best external URL for a source (DOI preferred, then PubMed). */
export function sourceUrl(c: EvidenceCitation): string | null {
  const doi = cleanDoi(c.doi)
  if (doi) return `https://doi.org/${doi}`
  const pmid = c.pmid?.trim();
  if (pmid && /^\d+$/.test(pmid)) return `https://pubmed.ncbi.nlm.nih.gov/${pmid}`
  if (c.url && /^https?:\/\//i.test(c.url.trim())) return c.url.trim()
  return null
}

/** Query string for the reader route, or null when the source has no resolvable id. */
export function readerQuery(c: EvidenceCitation): string | null {
  const params = new URLSearchParams()
  const pmcid = c.pmcid?.trim()
  const pmid = c.pmid?.trim()
  const doi = cleanDoi(c.doi)
  if (pmcid && /^(PMC)?\d+$/i.test(pmcid)) params.set("pmcid", pmcid)
  if (pmid && /^\d+$/.test(pmid)) params.set("pmid", pmid)
  if (doi && /^10\.\d{1,9}\//.test(doi)) params.set("doi", doi)
  const qs = params.toString()
  return qs || null
}

/** True when the reader can look this source up (PMID / PMCID / DOI). */
export function readerCanFetch(c: EvidenceCitation): boolean {
  return readerQuery(c) !== null
}

type FetchState =
  | { status: "idle" }
  | { status: "loading" }
  | { status: "ready"; data: ReaderFulltext }
  | { status: "error" }

/** Fetch abstract + open-access full text for one source (one request per open). */
function useFulltext(source: EvidenceCitation | null): FetchState {
  const query = source ? readerQuery(source) : null
  const [state, setState] = useState<FetchState>({ status: "idle" })
  useEffect(() => {
    if (!query) { setState({ status: "idle" }); return }
    let cancelled = false
    setState({ status: "loading" })
    api.request<ReaderFulltext>(`/literature/fulltext?${query}`)
      .then(data => { if (!cancelled) setState({ status: "ready", data }) })
      .catch(() => { if (!cancelled) setState({ status: "error" }) })
    return () => { cancelled = true }
  }, [query])
  return state
}

/**
 * Spec 01 §1.3.3 — Source reader.
 *
 * A right-hand pane (not a new tab) that shows a source's title / venue / year
 * and a "cited for" line naming the locus, with next/prev navigation so a
 * reader can audit a whole answer without leaving the thread.
 *
 * Content is real or honestly absent: the pane fetches the abstract and — when
 * the article is open access — the full text from Europe PMC via
 * /api/literature/fulltext. A closed-access article says so and links to the
 * publisher; it never shows a placeholder body.
 */
export function SourceReaderPane({
  sources,
  index,
  onIndexChange,
  className,
}: SourceReaderPaneProps) {
  const open = index !== null && index >= 0 && index < sources.length
  const source = open ? sources[index as number] : null
  const remote = useFulltext(source)
  const data = remote.status === "ready" ? remote.data : null

  const goPrev = () => {
    if (index !== null && index > 0) onIndexChange(index - 1)
  }
  const goNext = () => {
    if (index !== null && index < sources.length - 1) onIndexChange(index + 1)
  }

  const venueYear = source
    ? [source.journal || data?.journal, source.year ? String(source.year) : data?.year]
        .filter(Boolean)
        .join(" · ")
    : ""
  const url = source ? sourceUrl(source) || data?.links.publisher || data?.links.europepmc || null : null
  const abstract = source?.abstract?.trim() || data?.abstract?.trim() || ""
  const authors = source?.authors?.filter(a => a.trim()).join(", ") || data?.authors || ""
  const statusText = !source
    ? null
    : !readerCanFetch(source)
    ? (abstract || source.excerpt?.trim() ? t('citations.reader.no_identifier') : t('citations.reader.no_content'))
    : remote.status === "error"
    ? t('citations.reader.fetch_failed')
    : data?.fullTextStatus === "not_open_access"
    ? t('citations.reader.not_open_access')
    : data?.fullTextStatus === "not_found"
    ? t('citations.reader.not_indexed')
    : data?.fullTextStatus === "unavailable"
    ? t('citations.reader.fulltext_unavailable')
    : null

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
        className={cn("w-full sm:max-w-xl flex flex-col", className)}
        data-testid="source-reader-pane"
      >
        {source && (
          <>
            <SheetHeader className="space-y-2 text-left shrink-0 pr-6">
              <div className="flex items-center gap-2 text-xs text-muted-foreground">
                <BookOpen className="h-3.5 w-3.5" />
                <span>{t('citations.reader.position', { n: (index as number) + 1, total: sources.length })}</span>
                {data?.openAccess && (
                  <Badge variant="outline" className="text-fs-xs px-1 py-0" data-testid="reader-oa-badge">
                    {t('citations.reader.open_access')}
                  </Badge>
                )}
              </div>
              <SheetTitle className="text-base leading-snug">
                {source.title || source.tool_name || data?.title || t('citations.reader.untitled')}
              </SheetTitle>
              {authors && <p className="text-xs text-muted-foreground" data-testid="reader-authors">{authors}</p>}
              {venueYear && <SheetDescription className="text-xs">{venueYear}</SheetDescription>}
              {source.locus && (
                <div className="text-xs text-primary flex items-center gap-1" data-testid="reader-locus">
                  <span className="text-muted-foreground">{t('citations.cited_for')}</span>
                  <Badge variant="outline" className="text-fs-xs px-1 py-0">{source.locus}</Badge>
                </div>
              )}
              {(source.retrieval_date || source.corpus_version) && (
                <div className="text-fs-xs text-muted-foreground">
                  {[source.retrieval_date && t('citations.retrieved_on', { date: source.retrieval_date }), source.corpus_version]
                    .filter(Boolean).join(" · ")}
                </div>
              )}
            </SheetHeader>

            <div className="flex-1 min-h-0 mt-4 overflow-y-auto space-y-5 text-sm leading-relaxed break-words pr-1">
              {abstract && (
                <section data-testid="reader-abstract">
                  <h3 className="font-medium mb-2">{t('citations.reader.abstract')}</h3>
                  <p className="whitespace-pre-wrap">{abstract}</p>
                </section>
              )}
              {source.excerpt?.trim() && (
                <section data-testid="reader-excerpt">
                  <h3 className="font-medium mb-2">{t('citations.reader.excerpt')}</h3>
                  <blockquote className="border-l-2 pl-3 whitespace-pre-wrap">{source.excerpt}</blockquote>
                </section>
              )}

              {remote.status === "loading" && (
                <p className="flex items-center gap-2 text-xs text-muted-foreground" data-testid="reader-loading">
                  <Loader2 className="h-3.5 w-3.5 animate-spin" />
                  {t('citations.reader.loading')}
                </p>
              )}

              {data?.fullTextStatus === "available" && data.sections.length > 0 && (
                <section data-testid="reader-fulltext" className="space-y-3 border-t pt-4">
                  <h3 className="font-medium">{t('citations.reader.full_text')}</h3>
                  {data.sections.map((sec, si) => (
                    <div key={si} className="space-y-2">
                      {sec.heading && <h4 className="text-sm font-semibold">{sec.heading}</h4>}
                      {sec.paragraphs.map((p, pi) => <p key={pi}>{p}</p>)}
                    </div>
                  ))}
                  {data.truncated && <p className="text-xs text-muted-foreground">{t('citations.reader.truncated')}</p>}
                  {data.license && <p className="text-xs text-muted-foreground">{t('citations.reader.license', { license: data.license })}</p>}
                </section>
              )}

              {/* Honest status line — what the reader could and could not get. */}
              {statusText && (
                <p className="text-xs text-muted-foreground" data-testid="reader-status">{statusText}</p>
              )}

              {url ? (
                <a href={url} target="_blank" rel="noopener noreferrer" className="inline-block">
                  <Button size="sm" variant="outline" data-testid="reader-open-source">
                    {t('citations.reader.open_at_source')}
                    <ExternalLink className="h-3.5 w-3.5 ml-1.5" />
                  </Button>
                </a>
              ) : (
                <p className="text-xs text-muted-foreground italic">{t('citations.reader.no_link')}</p>
              )}
            </div>

            <div className="mt-4 shrink-0 flex items-center justify-between border-t pt-3">
              <Button size="sm" variant="ghost" className="h-8 text-xs" onClick={goPrev} disabled={index === 0} data-testid="reader-prev">
                <ChevronLeft className="h-4 w-4 mr-1" />
                {t('citations.reader.prev')}
              </Button>
              <Button size="sm" variant="ghost" className="h-8 text-xs" onClick={goNext} disabled={index === sources.length - 1} data-testid="reader-next">
                {t('citations.reader.next')}
                <ChevronRight className="h-4 w-4 ml-1" />
              </Button>
            </div>
          </>
        )}
      </SheetContent>
    </Sheet>
  )
}
