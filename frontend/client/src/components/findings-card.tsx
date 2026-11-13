import React, { useState } from 'react'
import { Card, CardContent, CardHeader, CardTitle } from './ui/card'
import { Button } from './ui/button'
import { ChevronDown, ChevronUp, Download, MessageSquare, BookOpen, Sparkles } from 'lucide-react'
import { tOr } from '@/lib/i18n'
import type { LegacyKeyResult } from '@shared/findings'

interface Citation {
  pmid: string
  title: string
  year: string
  relevance: string
}

/** The flat findings row shape — now the single shared definition (see
 *  docs/20261025_FINDINGS_PROVENANCE_FRAMEWORK.md; `FindingRecord` is the structured
 *  migration target). */
type KeyResult = LegacyKeyResult

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
  /**
   * Chat vs panel. In `preview` mode (the chat stream) the card is a PREVIEW:
   * verdict + headline chips + the deep-links to the full result in Outputs/Summary —
   * the full Key Results table stays collapsed (the authoritative table lives in the
   * panel). Default (panel) shows the full table expanded. (User: "preview in chat,
   * link to full result in output".)
   */
  preview?: boolean
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

/**
 * Per-entity results identify their entity either in `r.entity` or as a leading
 * "(identity) …" prefix in the interpretation prose. When the identity is a raw
 * SMILES (or any long token) it must NOT be shown verbatim — the design renders a
 * short ordinal "(Compound N)" and keeps the full identity on hover. These helpers
 * assign the ordinals and reshape each row's interpretation for display.
 */
const SHORT_ENTITY = /^(compound|entity|sample|ligand|mol(?:ecule)?)\s*\d+$/i

/**
 * Strip a leading balanced "(…)" group. A SMILES contains nested parentheses
 * (e.g. "CC(=O)O…"), so a regex that stops at the first ")" chops a fragment —
 * we must match parens by depth. Returns the inner content and the remaining
 * prose, or inner=null when there is no leading balanced group.
 */
function stripLeadingParen(raw: string): { inner: string | null; rest: string } {
  const s = raw.replace(/^\s+/, '')
  if (s[0] !== '(') return { inner: null, rest: raw }
  let depth = 0
  for (let i = 0; i < s.length; i++) {
    if (s[i] === '(') depth++
    else if (s[i] === ')') {
      depth--
      if (depth === 0) return { inner: s.slice(1, i), rest: s.slice(i + 1).replace(/^\s+/, '') }
    }
  }
  return { inner: null, rest: raw } // unbalanced — leave as-is
}

function rowIdentity(r: KeyResult): string | undefined {
  if (r.entity?.trim()) return r.entity.trim()
  const { inner } = stripLeadingParen(r.interpretation || '')
  return inner?.trim() || undefined
}

export function entityOrdinals(rows: KeyResult[]): Map<string, string> {
  const order: string[] = []
  const seen = new Set<string>()
  for (const r of rows) {
    const id = rowIdentity(r)
    if (id && !seen.has(id)) { seen.add(id); order.push(id) }
  }
  const map = new Map<string, string>()
  order.forEach((id, i) => map.set(id, SHORT_ENTITY.test(id) ? id : `Compound ${i + 1}`))
  return map
}

export function displayInterp(r: KeyResult, ord: Map<string, string>): { label?: string; text: string; title?: string } {
  const identity = rowIdentity(r)
  if (!identity) return { text: r.interpretation || '' }
  // Drop the leading "(identity)" tag from the prose (balanced, so a SMILES with
  // nested parens is removed whole) — the ordinal label carries the attribution.
  const { inner, rest } = stripLeadingParen(r.interpretation || '')
  const text = inner != null ? rest : (r.interpretation || '')
  const label = ord.get(identity) || identity
  const shortened = label !== identity // we replaced a long identity with an ordinal
  return { label, text, title: shortened ? identity : undefined }
}

export function FindingsCard({ runId, onContinueAnalysis, executionStatus, onOpenOutput, preview }: FindingsCardProps) {
  const [data, setData] = useState<FindingsData | null>(null)
  const [loading, setLoading] = useState(true)
  // In the panel, preview the Key Results table expanded (the authoritative result).
  // In chat `preview` mode it starts COLLAPSED — chat shows verdict + chips + the
  // "Full table in Summary / Files in Outputs" links, not the full table.
  const [resultsExpanded, setResultsExpanded] = useState(!preview)
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
        {tOr('panel.findings.analyzing', 'Loading findings…')}
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
        {tOr('panel.findings.in_progress', 'Findings are not available yet.')}
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
  const entityOrd = entityOrdinals(kr || [])
  const multiEntity = entityOrd.size > 1 || (kr || []).some(r => Boolean(r.entity) || /\((?:Compound|Entity|Sample) \d+\)/i.test(r.interpretation || ''))

  return (
    <Card data-testid="findings-card" className="mt-3" style={{ border: '1px solid var(--border)', background: 'var(--bm-bg-elev, var(--bg-elev, #fff))' }}>
      <CardHeader className="pb-2 pt-3 px-3">
        <CardTitle className="text-sm flex items-center gap-2" style={{ fontWeight: 600 }}>
          <Sparkles className="h-3.5 w-3.5 shrink-0" style={{ color: 'var(--bm-text-dim, var(--text-dim))' }} />
          {tOr('panel.findings.summary_title', 'Findings · key scores from outputs')}
        </CardTitle>
      </CardHeader>
      <CardContent className="px-3 pb-3 space-y-3">
        {summary && (
          <p className="text-sm text-foreground/90">
            {linkifyFindings(summary, kr || [], onOpenOutput)}
          </p>
        )}

        {/* §7.8 headline metrics — the top results as scannable chips so the
            answer is legible at a glance without expanding the table. Prefer
            score rows over Gate · … so users see test/val MAE (etc.) first. */}
        {kr && kr.length > 0 && !multiEntity && (
          <div className="flex flex-wrap gap-1.5" data-testid="findings-headline-metrics">
            {[...kr].sort((a, b) => {
              const rank = (m: string) =>
                /^gate\b/i.test(m) ? 2
                : /test|val|mae|rmse|r²|r2|auc|accuracy|padj|log2|affinity|plddt|confident|impact|fsc|resolution|aligned|particles|coverage/i.test(m) ? 0
                : 1;
              return rank(a.metric || '') - rank(b.metric || '');
            }).slice(0, 3).map((r, i) => {
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
                  <span className="text-fs-xs text-muted-foreground">{r.metric}</span>
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
              data-testid="findings-key-results-toggle"
            >
              {tOr('panel.findings.key_results', 'Key Results')}
              <span className="opacity-70">({kr.length})</span>
              {multiEntity && <span className="opacity-70">{tOr('panel.findings.per_entity', '(per compound)')}</span>}
              {(resultsExpanded || (multiEntity && !preview) || !preview) ? <ChevronUp className="h-3 w-3" /> : <ChevronDown className="h-3 w-3" />}
            </button>
            {/* Panel (non-preview): always show the full Key Results table — this is
                where users expect the authoritative scores. Chat preview stays collapsed. */}
            {(resultsExpanded || (multiEntity && !preview) || !preview) && (
              <div className="overflow-x-auto">
                <table className="text-xs w-full border-collapse">
                  <thead>
                    <tr className="border-b border-border/60">
                      <th className="text-left py-1 pr-3 font-medium whitespace-nowrap">{tOr('panel.findings.col_metric', 'Metric')}</th>
                      <th className="text-left py-1 pr-3 font-medium whitespace-nowrap">{tOr('panel.findings.col_value', 'Value')}</th>
                      <th className="text-left py-1 pr-3 font-medium">{tOr('panel.findings.col_interpretation', 'Interpretation')}</th>
                      <th className="text-left py-1 font-medium whitespace-nowrap">{tOr('panel.findings.col_source', 'Source')}</th>
                    </tr>
                  </thead>
                  <tbody>
                    {kr.map((r, i) => (
                      <tr key={i} className="border-b border-border/30">
                        <td className="py-1 pr-3 font-medium whitespace-nowrap">{r.metric}</td>
                        <td className="py-1 pr-3 font-mono whitespace-nowrap tabular-nums">{r.value}</td>
                        <td className="py-1 pr-3 text-muted-foreground">
                          {(() => {
                            const { label, text, title } = displayInterp(r, entityOrd)
                            return (
                              <>
                                {label && (
                                  <span className="font-medium text-foreground" title={title}>({label}) </span>
                                )}
                                {text}
                              </>
                            )
                          })()}
                        </td>
                        <td className="py-1 text-muted-foreground font-mono">
                          {r.source_file
                            ? <span className="inline-block max-w-[150px] truncate align-bottom" title={`Read from ${r.source_file}`}>{r.source_file}</span>
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
