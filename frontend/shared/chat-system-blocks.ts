/**
 * System blocks the composer appends to a user's chat message so the backend
 * can resolve attached data, e.g.
 *
 *   [BioMate dataset: epar.jsonl (id: 1b2c…)]
 *   [Attached files: a.csv, b.csv]
 *   [Uploaded datasets: a.csv: dataset_id=…]
 *   [Galaxy dataset: …] / [Dataset: name (id: …)]
 *   [Paper content: ref]\n<extracted paper text to end of message>
 *
 * They are machine context, not the user's words. Anything user-facing that
 * is derived from message text (the user bubble, the chat title) must strip
 * them first — otherwise a chat is titled "[BioMate dataset: epar.jsonl (id:".
 * One definition, used by the client bubble, the client title fallback and
 * the server title route.
 */

const BLOCK_LABELS = "BioMate dataset|Galaxy dataset|Dataset|Attached files|Uploaded datasets?";

/** `[Label: …]` blocks (single bracketed run, no nesting). */
const LABELLED_BLOCK = new RegExp(`\\n?\\[(?:${BLOCK_LABELS})\\s*:[^\\]]*\\]`, "gi");
/** `[Paper content: …]` carries the paper body after it — strip to the end. */
const PAPER_BLOCK = /\n?\[Paper content:[^\]]*\][\s\S]*$/i;
/** A block cut off mid-way (e.g. by an upstream slice) — strip from its start. */
const TRUNCATED_BLOCK = new RegExp(`\\[(?:${BLOCK_LABELS}|Paper content)\\s*:[^\\]]*$`, "i");

/** The user's own words, with every system block removed. */
export function stripSystemBlocks(text: string | null | undefined): string {
  if (!text) return "";
  return String(text)
    .replace(PAPER_BLOCK, "")
    .replace(LABELLED_BLOCK, "")
    .replace(TRUNCATED_BLOCK, "")
    .replace(/[ \t]+\n/g, "\n")
    .trim();
}

/** File / dataset names referenced by the system blocks (for attachment chips). */
export function attachedNamesFromBlocks(text: string | null | undefined): string[] {
  const raw = String(text || "");
  const names: string[] = [];
  const push = (n?: string) => {
    const name = n?.trim();
    if (name && !names.includes(name)) names.push(name);
  };
  const attached = raw.match(/\[Attached files:\s*([^\]]+)\]/i)?.[1] ?? "";
  attached.split(",").forEach((n) => push(n));
  // No closing "]" required: a block truncated by an upstream slice (legacy
  // titles like "[BioMate dataset: epar.jsonl (id:") still yields its name.
  for (const m of raw.matchAll(/\[(?:BioMate dataset|Uploaded datasets?|Dataset):\s*([^:(\]]+)/gi)) {
    push(m[1]);
  }
  return names;
}

/**
 * Text to derive a chat title from. Prefers the user's words; a message that
 * is ONLY attachments ("[BioMate dataset: x.csv …]") titles after the files
 * rather than after the raw block.
 */
export function titleSourceText(text: string | null | undefined): string {
  const words = stripSystemBlocks(text);
  if (words) return words;
  return attachedNamesFromBlocks(text).join(", ");
}

/** Deterministic short title: first ~6 words (or ~24 CJK chars), ≤50 chars. */
export function fallbackTitle(text: string | null | undefined): string {
  const src = titleSourceText(text).replace(/\s+/g, " ").trim();
  if (!src) return "";
  const isCjk = /[㐀-鿿]/.test(src) && !/\s/.test(src.slice(0, 24));
  const short = isCjk ? src.slice(0, 24) : src.split(" ").slice(0, 6).join(" ");
  const clipped = short.length > 50 ? short.slice(0, 47) + "..." : short;
  return clipped.length < src.length && !clipped.endsWith("...") && isCjk ? clipped + "…" : clipped;
}

/** True when a stored title still contains a raw system block (legacy data). */
export function titleHasSystemBlock(title: string | null | undefined): boolean {
  return /\[(?:BioMate dataset|Galaxy dataset|Dataset|Attached files|Uploaded datasets?|Paper content)\s*:/i.test(String(title || ""));
}
