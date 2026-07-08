import React, { useState } from 'react'
import { Card, CardContent, CardHeader, CardTitle } from './ui/card'
import { Button } from './ui/button'
import { ChevronDown, ChevronUp, Download, MessageSquare, BookOpen } from 'lucide-react'

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
  status?: 'pending' | 'ready'
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
}

export function FindingsCard({ runId, onContinueAnalysis, executionStatus }: FindingsCardProps) {
  const [data, setData] = useState<FindingsData | null>(null)
  const [loading, setLoading] = useState(true)
  const [resultsExpanded, setResultsExpanded] = useState(false)
  const [citationsExpanded, setCitationsExpanded] = useState(false)

  const runFailed = executionStatus === 'failed' || executionStatus === 'error'

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
            if (json.status === 'pending' && !runFailed) {
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
  }, [runId, runFailed])

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
        Analyzing outputs…
      </div>
    )
  }

  if (!data) return null

  if (data.status === 'pending') {
    if (runFailed) {
      return (
        <div className="text-sm text-muted-foreground mt-2">
          Analysis not available — workflow did not complete successfully.
        </div>
      )
    }
    return (
      <div className="text-sm text-muted-foreground mt-2 flex items-center gap-2">
        <BookOpen className="h-3.5 w-3.5 animate-pulse" />
        Analysis in progress…
      </div>
    )
  }

  // If no summary extracted, don't render card
  if (!data.summary && !data.reportMd) return null

  const reportUrl = data.reportUrl || `/api/workflows/runs/${runId}/findings/report`

  const { summary, keyResults: kr, citations: cits, caveats: cavs, nextSteps: ns } = parsedData

  return (
    <Card data-testid="findings-card" className="mt-3 border-blue-200 bg-blue-50/30 dark:border-blue-900/40 dark:bg-blue-950/10">
      <CardHeader className="pb-2 pt-3 px-3">
        <CardTitle className="text-sm flex items-center gap-2">
          <BookOpen className="h-4 w-4 text-blue-600 dark:text-blue-400 shrink-0" />
          Findings Summary
        </CardTitle>
      </CardHeader>
      <CardContent className="px-3 pb-3 space-y-3">
        {summary && <p className="text-sm text-foreground/90">{summary}</p>}

        {kr && kr.length > 0 && (
          <div>
            <button
              className="text-xs text-muted-foreground flex items-center gap-1 mb-1 hover:text-foreground transition-colors"
              onClick={() => setResultsExpanded(e => !e)}
            >
              Key Results {resultsExpanded ? <ChevronUp className="h-3 w-3" /> : <ChevronDown className="h-3 w-3" />}
            </button>
            {resultsExpanded && (
              <div className="overflow-x-auto">
                <table className="text-xs w-full border-collapse">
                  <thead>
                    <tr className="border-b border-border/60">
                      <th className="text-left py-1 pr-3 font-medium">Metric</th>
                      <th className="text-left py-1 pr-3 font-medium">Value</th>
                      <th className="text-left py-1 pr-3 font-medium">Interpretation</th>
                      <th className="text-left py-1 font-medium">Source</th>
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
              Supporting Literature ({cits.length})
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
            <p className="font-medium mb-1">Caveats</p>
            <ul className="list-disc list-inside space-y-0.5">
              {cavs.map((c, i) => <li key={i}>{c}</li>)}
            </ul>
          </div>
        )}

        <div className="flex gap-2 flex-wrap pt-0.5">
          <Button variant="outline" size="sm" className="text-xs h-7" asChild>
            <a href={reportUrl} download>
              <Download className="h-3 w-3 mr-1" />
              Download report
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
              Continue analysis
            </Button>
          )}
        </div>
      </CardContent>
    </Card>
  )
}
