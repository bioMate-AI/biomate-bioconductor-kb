/**
 * Cap chat-attached dataset references to MAX_DATASET_REFS entries.
 *
 * Background: chat_sessions.datasets is a jsonb array of references
 * (~150 B per entry). We cap at 32 because:
 *   - The <session_datasets> prompt block already only renders the
 *     first 32 entries (galaxy-assistant.ts), so anything past that
 *     is invisible to the LLM anyway.
 *   - Typical legitimate use is 1-10 entries; 20-30 is power-user
 *     territory; >30 is almost always a runaway loop or someone
 *     attaching individual files instead of using a Galaxy collection.
 *   - 32 × ~150 B = ~5 KB per row's datasets column — comfortable for
 *     Postgres jsonb without performance hit.
 *
 * Policy on overflow: drop the OLDEST entries (FIFO). Most-recent
 * attachments are usually the most relevant for the current
 * conversation. The actual files in Galaxy / S3 are NEVER touched —
 * only the in-memory / DB reference rows.
 *
 * See docs/20260612_DATASET_STORAGE_AND_SESSION_BOUNDARIES.md.
 *
 * Orthogonal to the per-attachment 5 GB size limit (enforced at
 * upload time on each file / folder / zip). That limit bounds size;
 * THIS limit bounds count. They never substitute for each other:
 *   - A user with 1 × 5 GB FASTQ attached is fine (1 entry, 5 GB file).
 *   - A user with 100 × 10 KB CSVs hits this cap at 32 (file sizes ok).
 */

export const MAX_DATASET_REFS = 32;

/**
 * Return at most MAX_DATASET_REFS entries from arr, keeping the most
 * recent (slice from the end). Robust to non-array input.
 *
 * Pure function; no side effects.
 */
export function capDatasetReferences<T>(arr: T[] | undefined | null): T[] {
  if (!Array.isArray(arr)) return [];
  if (arr.length <= MAX_DATASET_REFS) return arr;
  return arr.slice(arr.length - MAX_DATASET_REFS);
}
