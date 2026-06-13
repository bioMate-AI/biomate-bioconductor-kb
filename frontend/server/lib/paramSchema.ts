/**
 * paramSchema.ts — adapter from backend workflow_ga param entries to the
 * extractor's WorkflowSchema shape.
 *
 * The backend (backend/lib/galaxy/ai/ai_assistant.py:_get_workflow_params)
 * already parses nextflow_schema.json (nf-core) and falls back to .nf inline
 * `params.X = '…' // comment` declarations. It ships rich metadata on every
 * workflow_ga response:
 *   { name, label, description, type, default, group, required,
 *     options: [{label, value}], minimum?, maximum?, pattern? }
 *
 * This module does NOT re-parse anything — it just reshapes that metadata
 * for the LLM prompt and the rule pass.
 *
 * Pure functions; no I/O.
 */

export type BackendParamEntry = {
  name: string;
  label?: string;
  description?: string;
  type?: string;
  default?: unknown;
  group?: string;
  required?: boolean;
  options?: Array<{ label?: string; value: unknown }>;
  minimum?: number;
  maximum?: number;
  pattern?: string;
};

export type ParamSpec = {
  name: string;
  default?: string;
  type: "enum" | "number" | "boolean" | "string" | "file";
  enum?: string[];
  description?: string;
  required: boolean;
};

export type WorkflowSchema = {
  workflowName: string;
  params: ParamSpec[];
  /** Diagnostic: where the schema came from. */
  source: "workflow_ga" | "annotation-only" | "empty";
};

/**
 * Build a WorkflowSchema from a workflow_ga's required_params + optional_params
 * arrays. These are produced by backend `_get_workflow_params()` and contain
 * full metadata (descriptions, enums, types). Falls back to bare-name handling
 * when entries are strings instead of objects (older annotation rows).
 */
export function buildSchemaFromWorkflowGa(args: {
  workflowName: string;
  requiredParams?: Array<BackendParamEntry | string> | null;
  optionalParams?: Array<BackendParamEntry | string> | null;
}): WorkflowSchema {
  const { workflowName, requiredParams, optionalParams } = args;
  const params: ParamSpec[] = [];
  let sawRichEntry = false;

  const consume = (
    entries: Array<BackendParamEntry | string> | null | undefined,
    isRequired: boolean,
  ) => {
    if (!entries) return;
    for (const e of entries) {
      if (typeof e === "string") {
        params.push({ name: e, type: "string", required: isRequired });
        continue;
      }
      if (!e || typeof e !== "object" || !e.name) continue;
      sawRichEntry = true;
      const spec: ParamSpec = {
        name: e.name,
        type: normalizeType(e.type, e.options),
        required: typeof e.required === "boolean" ? e.required : isRequired,
      };
      if (e.default !== undefined && e.default !== null && e.default !== "")
        spec.default = String(e.default);
      if (e.description) spec.description = e.description;
      if (e.options && e.options.length > 0) {
        spec.enum = e.options.map((o) => String(o.value));
      }
      params.push(spec);
    }
  };
  consume(requiredParams, true);
  consume(optionalParams, false);

  const source: WorkflowSchema["source"] =
    params.length === 0
      ? "empty"
      : sawRichEntry
        ? "workflow_ga"
        : "annotation-only";
  return { workflowName, params, source };
}

function normalizeType(
  type: string | undefined,
  options: BackendParamEntry["options"],
): ParamSpec["type"] {
  if (options && options.length > 0) return "enum";
  if (!type) return "string";
  const t = type.toLowerCase();
  if (t.includes("number") || t === "integer" || t === "int" || t === "float") return "number";
  if (t === "boolean" || t === "bool") return "boolean";
  if (t.includes("file") || t.includes("path") || t.includes("directory")) return "file";
  return "string";
}

/**
 * Render the schema as a compact prompt block for the LLM resolver.
 * Filters optional params to those whose name / description tokens appear in
 * the user query, capped at `maxOptional` (keeps prompt small for nf-core
 * schemas with 80+ params).
 */
export function renderSchemaForPrompt(
  schema: WorkflowSchema,
  userQuery: string,
  opts: { maxOptional?: number } = {},
): string {
  const maxOptional = opts.maxOptional ?? 25;
  const required = schema.params.filter((p) => p.required);
  const optional = schema.params.filter((p) => !p.required);
  const q = userQuery.toLowerCase();
  const optionalRanked = optional
    .map((p) => ({ p, score: keywordScore(p, q) }))
    .sort((a, b) => b.score - a.score);
  const optionalFiltered = optionalRanked
    .filter((x, idx) => x.score > 0 || idx < maxOptional)
    .slice(0, maxOptional)
    .map((x) => x.p);
  const all = [...required, ...optionalFiltered];
  return all.map(formatParamLine).join("\n");
}

function keywordScore(p: ParamSpec, q: string): number {
  let s = 0;
  if (q.includes(p.name.toLowerCase())) s += 3;
  for (const tok of p.name.toLowerCase().split("_")) {
    if (tok.length >= 4 && q.includes(tok)) s += 1;
  }
  if (p.enum) {
    for (const v of p.enum) {
      if (q.includes(String(v).toLowerCase())) s += 2;
    }
  }
  if (p.description) {
    // Light bag-of-words match — every description token that's in the query
    // counts once. Cheap, good-enough heuristic.
    for (const tok of p.description.toLowerCase().split(/\W+/)) {
      if (tok.length >= 5 && q.includes(tok)) s += 1;
    }
  }
  return s;
}

function formatParamLine(p: ParamSpec): string {
  let s = `- ${p.name}`;
  if (p.required) s += " *required*";
  if (p.enum) s += ` (allowed: ${p.enum.join(" | ")})`;
  else if (p.type !== "string") s += ` (type: ${p.type})`;
  if (p.description) s += ` — ${truncate(p.description, 100)}`;
  return s;
}

function truncate(s: string, n: number): string {
  return s.length > n ? s.slice(0, n - 1) + "…" : s;
}
