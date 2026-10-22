import React, { useState } from 'react'
import { Card, CardContent, CardHeader, CardTitle } from './ui/card'
import { Button } from './ui/button'
import { ChevronDown, ChevronUp, Download, MessageSquare, BookOpen } from 'lucide-react'
import { tOr } from '@/lib/i18n'

interface Citation {
  pmid: string
  title: string
  year: string
  relevance: string
}

interface KeyResult {
  metric: string
  value: string
  interpretation: string
  source_file?: string
}

interface FindingsData {
  status?: 'pending' | 'ready' | 'unavailable'
  summary?: string
  keyResults?: KeyResult[]
  /** snake_case alias from sidecar JSON */
  key_results?: KeyResult[]
  citations?: Citation[]
  caveats?: string[]
  nextSteps?: string[]
  /** snake_case alias from sidecar JSON */
  next_steps?: string[]
  reportUrl?: string
  /** Raw markdown from findings_report.md */
  reportMd?: string
  message?: string
}

interface FindingsCardProps {
  runId: string | null | undefined
  onContinueAnalysis?: (suggestion: string) => void
  executionStatus?: string
  /**
   * §7.8 — called when the user clicks a numeric claim in the findings prose
   * that resolves to a known output. `ref` is the output reference (typically a
   * source_file path) the number was read from, so the parent can open it.
   */
  onOpenOutput?: (ref: string) => void
}

/**
 * §7.8 findings-as-links. Best-effort: split the summary prose on numbers and,
 * for each number that appears (as a substring) in a KeyResult's value, turn it
 * into a link that fires onOpenOutput with that result's source_file. Numbers
 * with no resolvable output stay plain text — we never fabricate a link.
 */
export function linkifyFindings(
  text: string,
  keyResults: KeyResult[],
  onOpenOutput?: (ref: string) => void,
): React.ReactNode[] {
  if (!text) return [text]
  // Build a lookup from the numeric token inside each result value → source_file.
  const numToRef = new Map<string, string>()
  for (const r of keyResults) {
    if (!r.source_file || !r.value) continue
    const m = String(r.value).match(/-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?/g)
    if (!m) continue
    for (const tok of m) {
      if (!numToRef.has(tok)) numToRef.set(tok, r.source_file)
    }
  }
  // Split, keeping the numeric tokens as separate captured segments.
  const parts = text.split(/(-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?%?)/g)
  return parts.map((part, i) => {
    if (i % 2 === 0) return part // non-numeric segment
    const bareNum = part.replace(/%$/, '')
    const ref = numToRef.get(bareNum)
    if (ref && onOpenOutput) {
      return (
        <button
          key={i}
          type="button"
          data-testid="finding-number-link"
          data-output-ref={ref}
          onClick={() => onOpenOutput(ref)}
          className="underline decoration-dotted text-blue-700 dark:text-blue-400 hover:text-blue-900 hover:decoration-solid font-mono"
          title={`Open source: ${ref}`}
        >
          {part}
        </button>
      )
    }
    return part
  })
}

export function FindingsCard({ runId, onContinueAnalysis, executionStatus, onOpenOutput }: FindingsCardProps) {
  const [data, setData] = useState<FindingsData | null>(null)
  const [loading, setLoading] = useState(true)
  // Preview the Key Results table by default (don't hide the content behind a
  // click) — users can still collapse it. The headline chips remain a fast glance.
  const [resultsExpanded, setResultsExpanded] = useState(true)
  const [citationsExpanded, setCitationsExpanded] = useState(false)

  const runFailed = executionStatus === 'failed' || executionStatus === 'error'
  // A paused run (QC-gate halt / user pause) is NOT failed and NOT progressing —
  // findings can't be generated until it resumes, so show a halted message and
  // stop polling (polling implies it's still working, which it isn't).
  const runPaused = executionStatus === 'paused'

  React.useEffect(() => {
    if (!runId) return;
    let cancelled = false
    let pollTimer: ReturnType<typeof setTimeout> | null = null

    const poll = async () => {
      try {
        const res = await fetch(`/api/workflows/runs/${runId}/findings`, { credentials: 'include' })
        if (!cancelled) {
          if (res.ok) {
            const json: FindingsData = await res.json()
            setData(json)
            setLoading(false)
            if (json.status === 'pending' && !runFailed && !runPaused) {
              // Retry after 5 seconds only while run is still active
              pollTimer = setTimeout(poll, 5000)
            }
          } else {
            setLoading(false)
          }
        }
      } catch {
        if (!cancelled) setLoading(false)
      }
    }

    poll()

    return () => {
      cancelled = true
      if (pollTimer) clearTimeout(pollTimer)
    }
  }, [runId, runFailed, runPaused])

  // useMemo MUST be called unconditionally (Rules of Hooks — no early returns before hooks).
  // We guard for null data by defaulting to empty values.
  const parsedData = React.useMemo(() => {
    if (!data || data.status === 'pending') {
      return { summary: undefined, keyResults: [], citations: [], caveats: [], nextSteps: [] }
    }
    const keyResults = data.keyResults || data.key_results || []
    const citations = data.citations || []
    const caveats = data.caveats || []
    const nextSteps = data.nextSteps || data.next_steps || []
    if (!data.reportMd) return { summary: data.summary, keyResults, citations, caveats, nextSteps }
    const md = data.reportMd
    // Extract summary from ## Findings Summary section
    const summaryMatch = md.match(/## Findings Summary\s*\n+([\s\S]*?)(?=\n##|\s*$)/)
    const parsedSummary = summaryMatch ? summaryMatch[1].trim() : data.summary
    // Extract caveats
    const caveatsMatch = md.match(/## Caveats\s*\n+([\s\S]*?)(?=\n##|\s*$)/)
    const parsedCaveats = caveatsMatch
      ? caveatsMatch[1].trim().split('\n').filter(l => l.startsWith('- ')).map(l => l.replace(/^- /, ''))
      : caveats
    // Extract next steps
    const nextMatch = md.match(/## Recommended Next Steps\s*\n+([\s\S]*?)(?=\n##|\s*$)/)
    const parsedNextSteps = nextMatch
      ? nextMatch[1].trim().split('\n').filter(l => /^\d+\./.test(l)).map(l => l.replace(/^\d+\.\s*/, ''))
      : nextSteps
    return {
      summary: parsedSummary || data.summary,
      keyResults,
      citations,
      caveats: parsedCaveats,
      nextSteps: parsedNextSteps,
    }
  }, [data])

  if (loading) {
    return (
      <div className="text-sm text-muted-foreground mt-2 flex items-center gap-2">
        <BookOpen className="h-3.5 w-3.5 animate-pulse" />
        {tOr('panel.findings.analyzing', 'Analyzing outputs…')}
      </div>
    )
  }

  if (!data) return null

  if (data.status === 'pending') {
    if (runPaused) {
      return (
        <div className="text-sm text-muted-foreground mt-2">
          {tOr('panel.findings.paused', 'Paused at a QC gate — resume the run to continue the analysis.')}
        </div>
      )
    }
    if (runFailed) {
      return (
        <div className="text-sm text-muted-foreground mt-2">
          {tOr('panel.findings.not_available_failed', 'Analysis not available — workflow did not complete successfully.')}
        </div>
      )
    }
    return (
      <div className="text-sm text-muted-foreground mt-2 flex items-center gap-2">
        <BookOpen className="h-3.5 w-3.5 animate-pulse" />
        {tOr('panel.findings.in_progress', 'Analysis in progress…')}
      </div>
    )
  }

  if (data.status === 'unavailable') {
    return (
      <div data-testid="findings-unavailable" className="text-sm text-amber-800 dark:text-amber-300 mt-2">
        {data.message || tOr('panel.findings.unavailable_fallback', 'Findings are unavailable because workflow outputs could not be read. Repair output access and try again.')}
      </div>
    )
  }

  // If no summary extracted, don't render card
  if (!data.summary && !data.reportMd) return null

  const reportUrl = data.reportUrl || `/api/workflows/runs/${runId}/findings/report`

  const { summary, keyResults: kr, citations: cits, caveats: cavs, nextSteps: ns } = parsedData

  // When a run assessed multiple entities (e.g. several compounds) the backend
  // tags each key result "(Compound N)" in its interpretation. The 3 headline
  // chips would then show only the FIRST entity's values with no attribution —
  // which reads as if those numbers are "the" result. In that case we drop the
  // chips and surface the full, per-entity Key Results table (which carries the
  // tags) instead, so it's always clear which entity a number belongs to.
  const multiEntity = (kr || []).some(r => /\((?:Compound|Entity|Sample) \d+\)/i.test(r.interpretation || ''))

  return (
    <Card data-testid="findings-card" className="mt-3 border-blue-200 bg-blue-50/30 dark:border-blue-900/40 dark:bg-blue-950/10">
      <CardHeader className="pb-2 pt-3 px-3">
        <CardTitle className="text-sm flex items-center gap-2">
          <BookOpen className="h-4 w-4 text-blue-600 dark:text-blue-400 shrink-0" />
          {tOr('panel.findings.summary_title', 'Findings Summary')}
        </CardTitle>
      </CardHeader>
      <CardContent className="px-3 pb-3 space-y-3">
        {summary && (
          <p className="text-sm text-foreground/90">
            {linkifyFindings(summary, kr || [], onOpenOutput)}
          </p>
        )}

        {/* §7.8 headline metrics — the top results as scannable chips so the
            answer is legible at a glance without expanding the table. Each chip
            with a known source opens that output (same path as the prose links). */}
        {kr && kr.length > 0 && !multiEntity && (
          <div className="flex flex-wrap gap-1.5" data-testid="findings-headline-metrics">
            {kr.slice(0, 3).map((r, i) => {
              const clickable = Boolean(r.source_file && onOpenOutput)
              return (
                <button
                  key={i}
                  type="button"
                  disabled={!clickable}
                  onClick={clickable ? () => onOpenOutput!(r.source_file!) : undefined}
                  data-testid="findings-headline-metric"
                  className={
                    "flex items-baseline gap-1.5 rounded-md border border-blue-200/70 dark:border-blue-900/50 bg-white/60 dark:bg-blue-950/20 px-2 py-1 text-left " +
                    (clickable ? "hover:border-blue-400 cursor-pointer" : "cursor-default")
                  }
                  title={r.source_file ? `Read from ${r.source_file}` : r.interpretation}
                >
                  <span className="text-[11px] text-muted-foreground">{r.metric}</span>
                  <span className="text-xs font-mono font-semibold text-blue-800 dark:text-blue-300">{r.value}</span>
                </button>
              )
            })}
          </div>
        )}

        {kr && kr.length > 0 && (
          <div>
            <button
              className="text-xs text-muted-foreground flex items-center gap-1 mb-1 hover:text-foreground transition-colors"
              onClick={() => setResultsExpanded(e => !e)}
            >
              {tOr('panel.findings.key_results', 'Key Results')}
              {multiEntity && <span className="opacity-70">{tOr('panel.findings.per_entity', '(per compound)')}</span>}
              {(resultsExpanded || multiEntity) ? <ChevronUp className="h-3 w-3" /> : <ChevronDown className="h-3 w-3" />}
            </button>
            {(resultsExpanded || multiEntity) && (
              <div className="overflow-x-auto">
                <table className="text-xs w-full border-collapse">
                  <thead>
                    <tr className="border-b border-border/60">
                      <th className="text-left py-1 pr-3 font-medium">{tOr('panel.findings.col_metric', 'Metric')}</th>
                      <th className="text-left py-1 pr-3 font-medium">{tOr('panel.findings.col_value', 'Value')}</th>
                      <th className="text-left py-1 pr-3 font-medium">{tOr('panel.findings.col_interpretation', 'Interpretation')}</th>
                      <th className="text-left py-1 font-medium">{tOr('panel.findings.col_source', 'Source')}</th>
                    </tr>
                  </thead>
                  <tbody>
                    {kr.map((r, i) => (
                      <tr key={i} className="border-b border-border/30">
                        <td className="py-1 pr-3 font-medium">{r.metric}</td>
                        <td className="py-1 pr-3 font-mono">{r.value}</td>
                        <td className="py-1 pr-3 text-muted-foreground">{r.interpretation}</td>
                        <td className="py-1 text-muted-foreground font-mono">
                          {r.source_file
                            ? <span title={`Read from ${r.source_file}`}>{r.source_file}</span>
                            : <span className="opacity-40">—</span>}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>
        )}

        {cits && cits.length > 0 && (
          <div>
            <button
              className="text-xs text-muted-foreground flex items-center gap-1 mb-1 hover:text-foreground transition-colors"
              onClick={() => setCitationsExpanded(e => !e)}
            >
              {tOr('panel.findings.supporting_literature', 'Supporting Literature')} ({cits.length})
              {citationsExpanded ? <ChevronUp className="h-3 w-3" /> : <ChevronDown className="h-3 w-3" />}
            </button>
            {citationsExpanded && (
              <ol className="text-xs space-y-1.5 list-decimal list-inside">
                {cits.map((c, i) => (
                  <li key={i}>
                    {c.pmid ? (
                      <a
                        href={`https://pubmed.ncbi.nlm.nih.gov/${c.pmid}/`}
                        target="_blank"
                        rel="noreferrer"
                        className="underline text-blue-700 dark:text-blue-400 hover:text-blue-900"
                      >
                        {c.title}
                      </a>
                    ) : (
                      <span>{c.title}</span>
                    )}
                    {c.year && <span className="text-muted-foreground"> ({c.year})</span>}
                    {c.relevance && <span className="text-muted-foreground"> — {c.relevance}</span>}
                  </li>
                ))}
              </ol>
            )}
          </div>
        )}

        {cavs && cavs.length > 0 && (
          <div className="text-xs text-amber-700 dark:text-amber-400 bg-amber-50 dark:bg-amber-950/20 rounded p-2 border border-amber-200/60 dark:border-amber-800/40">
            <p className="font-medium mb-1">{tOr('panel.findings.caveats', 'Caveats')}</p>
            <ul className="list-disc list-inside space-y-0.5">
              {cavs.map((c, i) => <li key={i}>{c}</li>)}
            </ul>
          </div>
        )}

        <div className="flex gap-2 flex-wrap pt-0.5">
          <Button variant="outline" size="sm" className="text-xs h-7" asChild>
            <a href={reportUrl} download>
              <Download className="h-3 w-3 mr-1" />
              {tOr('panel.findings.download_report', 'Download findings')}
            </a>
          </Button>
          {ns && ns.length > 0 && onContinueAnalysis && (
            <Button
              variant="outline"
              size="sm"
              className="text-xs h-7"
              onClick={() => onContinueAnalysis(ns[0])}
            >
              <MessageSquare className="h-3 w-3 mr-1" />
              {tOr('panel.findings.continue_analysis', 'Continue analysis')}
            </Button>
          )}
        </div>
      </CardContent>
    </Card>
  )
}
