// Safe parse for SSE `event.data`. A single malformed or flush-truncated frame
// must not throw inside an EventSource listener — the browser swallows the throw
// and that state transition is lost silently (a step card never flips to
// completed, a workflow_state:error is never shown). Returns null on bad JSON so
// the listener can bail cleanly instead of crashing.
export function parseSSEData<T = any>(raw: unknown): T | null {
  if (typeof raw !== 'string' || raw.length === 0) return null;
  try {
    return JSON.parse(raw) as T;
  } catch {
    // eslint-disable-next-line no-console
    console.warn('[sse] dropped a malformed/truncated frame');
    return null;
  }
}
