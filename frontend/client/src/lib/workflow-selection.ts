/**
 * Explicit workflow selection — carries "the user chose THIS catalog workflow" from a picker
 * (e.g. Workflows library "Run") to the chat request as structured
 * `context.selectedWorkflow`, so the server builds exactly that workflow instead of re-running
 * intent routing + catalog search on a text prompt (doc §7.2).
 *
 * The library seeds the composer through a navigation (/?draft=<sentence>, reviewed before
 * sending), so the selection is parked in sessionStorage next to that draft and taken by the
 * next send. The visible message stays a short natural sentence; ids/paths never appear in it.
 */

export interface WorkflowSelection {
  /** Catalog workflow name (e.g. "nf-core/rnaseq"). */
  name: string;
  /** Catalog workflow file path, when the picker knows it. */
  nextflow_path?: string;
  /** Catalog workflow id, when the picker knows it. */
  id?: number | string;
  source?: string;
  type?: string;
  /** Name as shown to the user (display name), when it differs from `name`. Client-only. */
  label?: string;
}

const STORAGE_KEY = 'biomate.pendingWorkflowSelection';

/** Park a selection for the next chat send (the composer was seeded with a sentence naming it). */
export function stashWorkflowSelection(selection: WorkflowSelection): void {
  try {
    sessionStorage.setItem(STORAGE_KEY, JSON.stringify(selection));
  } catch { /* storage unavailable: the seeded sentence still names the workflow */ }
}

/**
 * One-shot: return the parked selection for this outgoing message and clear it. The selection
 * applies only while the message still names the chosen workflow — if the user replaced the
 * seeded sentence with a different request, it is dropped and the message routes normally.
 */
export function takeWorkflowSelection(content: string): WorkflowSelection | undefined {
  let raw: string | null = null;
  try {
    raw = sessionStorage.getItem(STORAGE_KEY);
    if (raw !== null) sessionStorage.removeItem(STORAGE_KEY);
  } catch { return undefined; }
  if (!raw) return undefined;
  try {
    const selection = JSON.parse(raw) as WorkflowSelection;
    if (!selection?.name) return undefined;
    const text = (content || '').toLowerCase();
    const names = [selection.label, selection.name].filter(Boolean).map(n => String(n).toLowerCase());
    return names.some(n => text.includes(n)) ? selection : undefined;
  } catch {
    return undefined;
  }
}

/** The pending library selection (not consumed) — the chat shows an input reminder while it waits. */
export function peekWorkflowSelection(): WorkflowSelection | undefined {
  try {
    const raw = sessionStorage.getItem(STORAGE_KEY);
    const s = raw ? (JSON.parse(raw) as WorkflowSelection) : undefined;
    return s?.name ? s : undefined;
  } catch { return undefined; }
}
