import { useCallback, useEffect, useRef, useState } from "react"

/**
 * One-shot URL payloads (e.g. `?draft=` from "Analyze with BioMate" / data-panel
 * "Run full QC") must be delivered to the composer exactly ONCE.
 *
 * Bug this closes (2026-11-10): opening `/?project=…&attachFile=…&draft=…` and
 * sending left the draft text in the composer. Root cause: the draft lived in
 * RootRoute state for the whole page life, while ChatWithArtifacts is keyed by
 * the chat session id. The first send turns the "new" chat into a real session,
 * the key changes, ChatWithArtifacts remounts with a fresh "applied" ref — and
 * re-applied the still-present draft into the composer the user had just sent
 * from. The payload is now consumed at its source.
 */

/** Read `name` from the current URL and strip ONLY that param (others, e.g. ?project=&attachFile=, stay). */
export function readAndStripUrlParam(name: string): string | undefined {
  if (typeof window === "undefined") return undefined
  const params = new URLSearchParams(window.location.search)
  const value = params.get(name)
  if (!value) return undefined
  params.delete(name)
  const rest = params.toString()
  window.history.replaceState(null, "", window.location.pathname + (rest ? `?${rest}` : ""))
  return value // URLSearchParams already decoded it; a literal % stays literal.
}

/** `[value, consume]` — value is read once from the URL; consume() clears it for good. */
export function useOneShotUrlParam(name: string): [string | undefined, () => void] {
  const [value, setValue] = useState<string | undefined>(() => readAndStripUrlParam(name))
  const consume = useCallback(() => setValue(undefined), [])
  return [value, consume]
}

/** How a draft is put into the composer: `send` = submit it once its attached files are linked
 *  (a one-click action such as "Run full QC"); otherwise it waits for the user to review it. */
export interface DraftOptions { send?: boolean }

/**
 * Apply an initial draft into the composer once the composer's setter is ready,
 * then report consumption so the owner drops the payload (a remount must not
 * re-apply it).
 */
export function useApplyInitialDraft(
  draft: string | undefined,
  getSetter: () => ((draft: string, opts?: DraftOptions) => void) | undefined,
  readyKey: unknown,
  onConsumed?: () => void,
  opts?: DraftOptions,
) {
  const appliedRef = useRef(false)
  useEffect(() => {
    const setter = getSetter()
    if (!draft || appliedRef.current || !setter) return
    appliedRef.current = true
    if (opts?.send) setter(draft, { send: true })
    else setter(draft)
    onConsumed?.()
  }, [readyKey, draft]) // eslint-disable-line react-hooks/exhaustive-deps
}
