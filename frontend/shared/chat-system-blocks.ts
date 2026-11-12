/**
 * System blocks the composer appends to a user's chat message so the backend
 * can resolve attached data, e.g.
 *
 *   [BioMate dataset: epar.jsonl (id: 1b2c…)]
 *   [Attached files: a.csv, b.csv]
 *   [Uploaded datasets: a.csv: dataset_id=…]
 *   [Galaxy dataset: …] / [Dataset: name (id: …)]
 *   [Paper content: ref]\n<extracted paper text to end of message>
 *   [Prepared inputs: …]  (model-facing notes for a cold-start example's files)
 *
 * They are machine context, not the user's words. Anything user-facing that
 * is derived from message text (the user bubble, the chat title) must strip
 * them first — otherwise a chat is titled "[BioMate dataset: epar.jsonl (id:".
 * One definition, used by the client bubble, the client title fallback and
 * the server title route.
 */

const BLOCK_LABELS = "BioMate dataset|Galaxy dataset|Dataset|Attached files|Uploaded datasets?|Prepared inputs";

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

/**
 * Redact internal storage references the model must never surface to a user —
 * the Galaxy dataset id and its "galaxy" keyword, in the JSON, key=value and
 * prose forms the model tends to echo from the "[Uploaded datasets: …]" context
 * into its run_code and replies. DISPLAY-ONLY: the wire protocol still carries
 * galaxy_dataset_id; this only hides it from anything shown to the user. Apply
 * to assistant content at render, and to anything copied/downloaded.
 */
export function redactInternalRefs(text: string | null | undefined): string {
  if (!text) return "";
  return String(text)
    // ── galaxy_dataset_id (keyword / JSON / key=value / prose) ──
    // JSON:  "galaxy_dataset_id": "uuid"  (drop the whole pair + a leading comma)
    .replace(/,?\s*"galaxy_dataset_id"\s*:\s*"[^"]*"/gi, "")
    // key=value:  galaxy_dataset_id=uuid
    .replace(/,?\s*\bgalaxy_dataset_id\s*=\s*[^\s,}\])]+/gi, "")
    // prose colon:  galaxy_dataset_id: uuid
    .replace(/,?\s*\bgalaxy_dataset_id\s*:\s*[^\s,}\])]+/gi, "")
    // any bare keyword left over → neutral, never the word "galaxy"
    .replace(/\bgalaxy_dataset_id\b/gi, "data_id")
    // ── internal run_code staging paths → the clean filename the model is told
    // to prefer. These prefixes (/work/input, /work/output, /tmp/biomate_code,
    // $DATA_DIR, the os.environ['DATA_DIR'] join) are BioMate-internal and never
    // appear in legitimate content, so collapsing them to the basename is safe.
    // os.path.join(os.environ['DATA_DIR'], '<id>', '<file>') → INPUT_FILES['<file>']
    .replace(/os\.path\.join\(\s*os\.environ\[['"]DATA_DIR['"]\]\s*,\s*['"][^'"]+['"]\s*,\s*['"]([^'"]+)['"]\s*\)/g, "INPUT_FILES['$1']")
    // R:  file.path(Sys.getenv("DATA_DIR"), "<id>", "<file>") → INPUT_FILES[["<file>"]]
    .replace(/file\.path\(\s*Sys\.getenv\(['"]DATA_DIR['"]\)\s*,\s*['"][^'"]+['"]\s*,\s*['"]([^'"]+)['"]\s*\)/g, 'INPUT_FILES[["$1"]]')
    // absolute staged paths → basename:  /work/input/<id>/<file>, /work/output/…, /tmp/biomate_code/…/<file>
    .replace(/(?:\/work\/(?:input|output)|\/tmp\/biomate_code)\/[^\s'"`)\]]*\/([^\/\s'"`)\]]+)/g, "$1")
    // $DATA_DIR/<id>/<file>  (shell/string form) → <file>
    .replace(/\$\{?DATA_DIR\}?\/[^\/\s'"`)\]]+\/([^\/\s'"`)\]]+)/g, "$1")
    // ── s3 references (from the same [Uploaded datasets] block) — never show an
    // s3:// URI or bucket/key to the user (no-S3-in-user-text rule). ──
    // s3_uri JSON / key=value → drop the pair
    .replace(/,?\s*"s3_uri"\s*:\s*"[^"]*"/gi, "")
    .replace(/,?\s*\bs3_uri\s*=\s*[^\s,}\])]+/gi, "")
    // bare s3://bucket/key/<file> → the filename only
    .replace(/\bs3:\/\/[^\s'"`)\],]+\/([^\/\s'"`)\],]+)/gi, "$1")
    // s3://bucket with no key → neutral
    .replace(/\bs3:\/\/[^\s'"`)\],]+/gi, "a data file")
    // tidy JSON wreckage the removals can leave: {} / {, / ,} / ,,
    .replace(/\{\s*\}/g, "")
    .replace(/\{\s*,/g, "{")
    .replace(/,\s*}/g, "}")
    .replace(/,\s*,/g, ",");
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
const TITLE_MAX = 50;

/** A title from the message's first sentence: whole when it fits, else cut at a word boundary and
 *  marked "…". (A fixed six-word cut titled "x.tsv: run quality control (QC) on this file …" as
 *  "x.tsv: run quality control (QC) on" — mid-sentence, with nothing saying it was cut.) */
export function fallbackTitle(text: string | null | undefined): string {
  const src = titleSourceText(text).replace(/\s+/g, " ").trim();
  if (!src) return "";
  // A sentence ends at . ! ? before a space, or at a CJK full stop — not at the dot in "a.csv".
  const sentence = src.split(/(?<=[.!?])\s|[。！？]/)[0].replace(/[.!?]$/, "").trim() || src;
  if (sentence.length <= TITLE_MAX) return sentence;
  if (/[㐀-鿿]/.test(sentence) && !/\s/.test(sentence.slice(0, 24))) return sentence.slice(0, 24) + "…";
  const cut = sentence.slice(0, TITLE_MAX);
  const space = cut.lastIndexOf(" ");
  return (space > 20 ? cut.slice(0, space) : cut).replace(/[\s,;:–—-]+$/, "") + "…";
}

/** True when a stored title still contains a raw system block (legacy data). */
export function titleHasSystemBlock(title: string | null | undefined): boolean {
  return /\[(?:BioMate dataset|Galaxy dataset|Dataset|Attached files|Uploaded datasets?|Paper content)\s*:/i.test(String(title || ""));
}
