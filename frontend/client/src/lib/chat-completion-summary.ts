/**
 * Build the inline FIND-style completion summary shown in chat when a run
 * finishes. Pure + isolated so the content contract is unit-tested without
 * mounting the chat component. Called repeatedly by the chat effect as it
 * watches the findings settle, so the message reports the run IN PROCESS:
 *  - Findings not ready yet → "complete … analyzing results…" (the caller keeps
 *    polling and re-invokes this to upgrade the message in place).
 *  - Findings ready → the real summary + up to 3 key results (never fabricated).
 *
 * Step count: this is only called for a run whose status is `completed`, so all
 * of its steps finished — we report `totalSteps` completed, never a stale live
 * counter that can read 0 at the completion instant (the "0/2 steps" bug).
 *
 * `data` is the parsed /api/workflows/runs/:id/findings response (or null on a
 * fetch error). Field names mirror that endpoint: {status, summary, key_results}.
 */
export function buildRunCompletionSummary(
  workflowName: string,
  data: any | null,
  totalSteps: number,
): string {
  const reportLink = `[Open the Findings panel](#findings) for full results, tables, and the downloadable report.`
  const stepLine =
    totalSteps > 0 ? `${totalSteps} step${totalSteps === 1 ? '' : 's'} completed` : 'run finished'
  const summary: string | undefined =
    typeof data?.summary === 'string' && data.summary.trim() ? data.summary.trim() : undefined
  const keyResults: any[] = Array.isArray(data?.key_results)
    ? data.key_results
    : Array.isArray(data?.keyResults)
      ? data.keyResults
      : []
  if (data?.status === 'ready' && (summary || keyResults.length > 0)) {
    const lines: string[] = [`**${workflowName} — complete.** ${stepLine}.`]
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
  // Findings still generating (or momentarily unavailable): report the run as
  // complete and signal analysis is in-process — the caller upgrades this to the
  // real values once the findings endpoint returns `ready`. No fabricated numbers.
  return `**${workflowName} — complete.** ${stepLine} — analyzing results… ${reportLink}`
}
