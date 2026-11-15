/**
 * Deterministic cold-start / prepared-input param seeding.
 *
 * Cold-start demos put explicit assignments in the hidden
 * `[Prepared inputs: …]` block (and sometimes in the user prompt), e.g.
 *   movies_path=fixture:empiar-10028-movies
 *   analysis=screening
 *   ligand_a=imatinib.sdf
 *
 * Seed paths use `fixture:<id>` tokens — never raw s3:// URIs in client copy.
 * Execute-time code expands fixtures via resolveDemoFixtureValue.
 *
 * The LLM / schema-grounded extractor often leaves those required slots empty
 * even when the assignment is already in the message — Confirm stays blocked
 * and a "Which <param>?" card appears. Parse the assignments with a rule so
 * the param strip can fill without force-Confirm.
 *
 * Values may be bare tokens or double-quoted (for spaces). Trailing
 * sentence punctuation is stripped. Only keys that appear in `paramNames`
 * (when provided) are returned — never invent schema params.
 */

const PREPARED_BLOCK =
  /\[Prepared inputs:\s*([^\]]*)\]/gi;

/** `name=value` or `name="value with spaces"` — word-boundary on the key.
 *  Unquoted values stop at whitespace, comma, semicolon, or a closing `]`
 *  (Prepared inputs block terminator) so `ligand_b=x.sdf]` never leaks. */
const KV_RE =
  /\b([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(?:"([^"]*)"|([^\s,;\]]+))/g;

function stripTrailingPunct(value: string): string {
  return value.replace(/[.,;:)\]\}]+$/g, "").trim();
}

/**
 * All explicit key=value assignments in the message (Prepared inputs first,
 * then the rest of the text). Later mentions of the same key win.
 */
export function parsePreparedInputParams(
  message: string,
  paramNames?: Iterable<string>,
): Record<string, string> {
  const text = String(message || "");
  if (!text.trim()) return {};

  const allow = paramNames
    ? new Set([...paramNames].map((n) => String(n).toLowerCase()))
    : null;

  const out: Record<string, string> = {};
  const apply = (chunk: string) => {
    KV_RE.lastIndex = 0;
    let m: RegExpExecArray | null;
    while ((m = KV_RE.exec(chunk)) !== null) {
      const key = m[1];
      const raw = m[2] !== undefined ? m[2] : m[3] || "";
      const value = stripTrailingPunct(raw);
      if (!key || !value) continue;
      if (allow && !allow.has(key.toLowerCase())) continue;
      // Resolve to the canonical casing from the allow-list when present.
      const canonical =
        allow == null
          ? key
          : ([...paramNames!].find((n) => n.toLowerCase() === key.toLowerCase()) || key);
      out[canonical] = value;
    }
  };

  for (const block of text.matchAll(PREPARED_BLOCK)) {
    apply(block[1] || "");
  }
  // Also scan the full message so prompt-level `movies_path=…` (E2E / typed)
  // works even when the Prepared inputs block was dropped (upload failure).
  apply(text);
  return out;
}

/**
 * Apply prepared-input assignments onto workflow_ga required/optional rows and
 * inline_parameters. Does not overwrite a non-empty existing value.
 * Returns the keys that were newly seeded.
 */
export function applyPreparedInputParamsToWorkflow(
  workflowGa: any,
  message: string,
): string[] {
  if (!workflowGa || typeof workflowGa !== "object") return [];
  const specs: any[] = [
    ...(workflowGa.required_params || []),
    ...(workflowGa.optional_params || []),
  ];
  const names = specs.map((p) => p?.name).filter(Boolean);
  const parsed = parsePreparedInputParams(message, names);
  if (Object.keys(parsed).length === 0) return [];

  if (!workflowGa.inline_parameters || typeof workflowGa.inline_parameters !== "object") {
    workflowGa.inline_parameters = {};
  }
  const seeded: string[] = [];
  for (const [name, value] of Object.entries(parsed)) {
    const p = specs.find((s) => String(s?.name) === name);
    if (!p) continue;
    const existing = p.value ?? p.default ?? workflowGa.inline_parameters[name];
    if (existing != null && String(existing).trim() !== "") continue;
    p.value = value;
    p.autoFilled = true;
    workflowGa.inline_parameters[name] = value;
    seeded.push(name);
  }
  return seeded;
}
