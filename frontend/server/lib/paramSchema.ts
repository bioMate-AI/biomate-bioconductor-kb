/**
 * paramSchema.ts — parse Nextflow .nf params declarations into structured schema.
 *
 * Source of truth: the .nf file's `params.X = 'default'  // comment` lines.
 * Comments are mined for enum values (`a | b | c`) and `alias for X` notes.
 *
 * Falls back to bare-name list when no .nf is available.
 *
 * Pure functions; no I/O of its own beyond reading the .nf file when given a path.
 */

import fs from "node:fs";
import path from "node:path";

export type ParamSpec = {
  /** Canonical key name as declared in the .nf params block. */
  name: string;
  /** Default literal (string-typed; type inference is downstream). */
  default?: string;
  /** Inferred type: 'enum' if comment has '|', 'number' if default parses, else 'string'. */
  type: "enum" | "number" | "boolean" | "string";
  /** Allowed values when type = 'enum'. */
  enum?: string[];
  /** When the param is an alias for another (e.g. `// alias for indication`). */
  aliasOf?: string;
  /** Trailing comment text minus enum/alias parsing. */
  note?: string;
  /** True when this param appears in workflow.required_params. */
  required: boolean;
};

export type WorkflowSchema = {
  workflowName: string;
  params: ParamSpec[];
  /** Source: 'nf' | 'annotation' | 'mixed'. */
  source: "nf" | "annotation" | "mixed";
};

const NUMBER_RE = /^-?\d+(\.\d+)?$/;
const BOOLEAN_VALUES = new Set(["true", "false"]);

/**
 * Parse a single .nf file's params block. Lines look like:
 *   params.target_gene = 'null'
 *   params.delivery_cell = 'T_cell'   // T_cell | NK_cell | macrophage
 *   params.disease = 'null'           // alias for indication
 *   params.n_steps = 1000              // simulation steps
 *
 * The regex is anchored at line start so we ignore in-process assignments
 * inside Groovy/Python blocks.
 */
export function parseNextflowParams(nfText: string): ParamSpec[] {
  const out: ParamSpec[] = [];
  const re = /^params\.(\w+)\s*=\s*(['"])([^'"]*)\2\s*(?:\/\/\s*(.*))?$/gm;
  let m: RegExpExecArray | null;
  while ((m = re.exec(nfText)) !== null) {
    const [, name, , def, rawComment] = m;
    if (name === "outdir") continue; // workflow infra, never user-set
    const comment = (rawComment ?? "").trim();
    const param: ParamSpec = {
      name,
      default: def,
      type: inferType(def, comment),
      required: false, // filled in by mergeWith()
    };
    if (comment) {
      const aliasMatch = comment.match(/^alias for\s+(\w+)/i);
      if (aliasMatch) {
        param.aliasOf = aliasMatch[1];
      } else if (comment.includes("|")) {
        param.type = "enum";
        param.enum = comment
          .split("|")
          .map((s) => s.trim())
          .filter(Boolean);
      } else {
        param.note = comment;
      }
    }
    out.push(param);
  }
  return out;
}

function inferType(def: string, comment: string): ParamSpec["type"] {
  if (comment.includes("|")) return "enum";
  if (BOOLEAN_VALUES.has(def.toLowerCase())) return "boolean";
  if (NUMBER_RE.test(def)) return "number";
  return "string";
}

/**
 * Merge .nf-parsed params with the workflow.annotation's required/optional name
 * lists. Annotation is the authority on which params are required.
 */
export function buildWorkflowSchema(args: {
  workflowName: string;
  nfText?: string | null;
  requiredParams?: string[] | null;
  optionalParams?: string[] | null;
}): WorkflowSchema {
  const { workflowName, nfText, requiredParams, optionalParams } = args;
  const required = new Set(requiredParams ?? []);
  const optional = new Set(optionalParams ?? []);
  let params: ParamSpec[] = [];
  let source: WorkflowSchema["source"] = "annotation";
  if (nfText) {
    params = parseNextflowParams(nfText);
    source = params.length > 0 ? "nf" : "annotation";
  }
  // Add any annotation-declared params that the .nf parser missed (e.g. params
  // assembled in code rather than statically declared).
  const seen = new Set(params.map((p) => p.name));
  for (const name of [...required, ...optional]) {
    if (!seen.has(name)) {
      params.push({ name, type: "string", required: required.has(name) });
      if (source === "nf") source = "mixed";
    }
  }
  // Mark required flag from annotation.
  for (const p of params) {
    if (required.has(p.name)) p.required = true;
  }
  return { workflowName, params, source };
}

/**
 * Convenience: build schema from a workflow's .nf file path.
 * Returns null if file does not exist.
 */
export function buildWorkflowSchemaFromFile(args: {
  workflowName: string;
  nfPath: string;
  requiredParams?: string[] | null;
  optionalParams?: string[] | null;
}): WorkflowSchema | null {
  let nfText: string | null = null;
  try {
    nfText = fs.readFileSync(args.nfPath, "utf8");
  } catch {
    return null;
  }
  return buildWorkflowSchema({
    workflowName: args.workflowName,
    nfText,
    requiredParams: args.requiredParams,
    optionalParams: args.optionalParams,
  });
}

/**
 * Render a schema as a compact prompt block for the LLM resolver.
 * Filters optional_params to those whose name or note keywords appear in the
 * user query (keeps prompt small for large workflows like nf-core/sarek).
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
  // Always include params with a hit; cap by maxOptional.
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
      if (q.includes(v.toLowerCase())) s += 2;
    }
  }
  if (p.note && q.includes(p.note.toLowerCase().slice(0, 20))) s += 1;
  return s;
}

function formatParamLine(p: ParamSpec): string {
  let s = `- ${p.name}`;
  if (p.required) s += " *required*";
  if (p.enum) {
    s += ` (allowed: ${p.enum.join(" | ")})`;
  } else if (p.type !== "string") {
    s += ` (type: ${p.type})`;
  }
  if (p.aliasOf) {
    s += ` — alias of ${p.aliasOf}; store value under ${p.aliasOf} instead`;
  } else if (p.note) {
    s += ` — ${p.note}`;
  }
  return s;
}

/**
 * Find the .nf file for a workflow given an nf-core-workflows search root.
 * Probes the conventional location used by biomate-ai-tools modules:
 *   {root}/modules/biomate-ai-tools/{name}/main.nf
 *   {root}/subworkflows/{*}/{name}/main.nf
 */
export function resolveNfPath(
  workflowName: string,
  roots: string[] = [],
): string | null {
  for (const root of roots) {
    const candidates = [
      path.join(root, "modules", "biomate-ai-tools", workflowName, "main.nf"),
      path.join(root, "subworkflows", workflowName, "main.nf"),
    ];
    for (const c of candidates) {
      try {
        fs.statSync(c);
        return c;
      } catch {
        // continue
      }
    }
  }
  return null;
}
