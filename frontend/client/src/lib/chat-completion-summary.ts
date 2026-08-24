/**
 * Build the inline FIND-style completion summary shown in chat when a run
 * finishes. Pure + isolated so the content contract is unit-tested without
 * mounting the chat component:
 *  - Real values are surfaced ONLY when the findings payload is `ready` and
 *    carries a summary or key_results — never fabricated. Up to 3 key results.
 *  - Otherwise a concise, honest generic line pointing at the Findings panel.
 *
 * `data` is the parsed /api/workflows/runs/:id/findings response (or null on
 * fetch error). Field names mirror that endpoint: {status, summary, key_results}.
 */
export function buildRunCompletionSummary(
  workflowName: string,
  data: any | null,
  completedSteps: number,
  totalSteps: number,
): string {
  const reportLink = `[Open the Findings panel](#findings) for full results, tables, and the downloadable report.`
  const summary: string | undefined =
    typeof data?.summary === 'string' && data.summary.trim() ? data.summary.trim() : undefined
  const keyResults: any[] = Array.isArray(data?.key_results)
    ? data.key_results
    : Array.isArray(data?.keyResults)
      ? data.keyResults
      : []
  if (data?.status === 'ready' && (summary || keyResults.length > 0)) {
    const lines: string[] = [`**${workflowName} — complete.**`]
    if (summary) lines.push('', summary)
    const bullets = keyResults
      .slice(0, 3)
      .map((k: any) => {
        if (typeof k === 'string') return `- ${k}`
        const metric = k?.metric || k?.name || k?.label
        const value = k?.value ?? k?.result
        const interp = k?.interpretation || k?.significance
        if (metric && value !== undefined && value !== null) {
          return `- **${metric}:** ${value}${interp ? ` — ${interp}` : ''}`
        }
        if (k?.finding) {
          return `- ${k.finding}${k?.significance ? ` — ${k.significance}` : ''}`
        }
        return null
      })
      .filter(Boolean) as string[]
    if (bullets.length > 0) {
      lines.push('', '**Key results:**', ...bullets)
    }
    lines.push('', reportLink)
    return lines.join('\n')
  }
  const stepLine = totalSteps > 0 ? `${completedSteps}/${totalSteps} steps finished` : 'run finished'
  return `**${workflowName} — complete.** ${stepLine}. ${reportLink}`
}
