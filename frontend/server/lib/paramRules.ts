/**
 * paramRules.ts — Stage 3a: rule-based parameter extraction.
 *
 * Runs BEFORE the LLM resolver. Cheap, deterministic, testable. Catches:
 *   - direct key hits (raw has the canonical name already)
 *   - global synonym graph (disease ≡ indication ≡ condition ≡ disease_area)
 *   - file paths and accession IDs (regex)
 *   - boolean negation ("don't keep duplicates" → remove_duplicates=true)
 *   - enum normalization ("T cells" → "T_cell" when an enum has T_cell)
 *
 * The rule pass NEVER invents data; if no clean signal exists, the key stays
 * unset and Stage 3b (the LLM) gets a chance.
 */

import type { ParamSpec, WorkflowSchema } from "./paramSchema.js";

/**
 * Global synonym graph. Each entry lists synonyms for a canonical concept.
 * Lookups are bidirectional: if any synonym appears in the raw bag AND the
 * workflow declares any other synonym from the same entry as a param, the
 * value is moved to that canonical key.
 *
 * Keep this small. The LLM handles the long tail.
 */
const SYNONYM_GROUPS: string[][] = [
  // disease / condition
  ["indication", "disease", "condition", "disease_area", "therapeutic_area"],
  // cell type
  ["delivery_cell", "cell_type", "cells", "target_cells", "cell"],
  // gene/target (most common LLM mistake: "target" or "gene")
  ["target_gene", "gene", "target_protein"],
  ["car_target", "target_antigen", "antigen"],
  ["target_mrna", "target_transcript"],
  // delivery
  ["lnp_targeting", "delivery_vehicle", "targeting_ligand", "lnp_target"],
  ["route_of_administration", "route", "administration_route"],
  // bispecific
  ["target_a", "target_1", "first_target", "targeta"],
  ["target_b", "target_2", "second_target", "targetb"],
  // editing
  ["edit_goal", "goal", "editing_strategy", "edit_type", "edit"],
  // sequencing
  ["reads", "fastq", "fastq_files", "reads_file"],
  ["sample_sheet", "samplesheet", "sample_csv"],
];

/**
 * Result of the rule pass.
 *   - canonicalParams: keys are guaranteed to be workflow-canonical names.
 *   - unresolvedRaw: raw bag keys that we couldn't map (LLM resolver sees these).
 *   - notes: human-readable explanations of each rule firing (for debugging
 *     and the "from your message" UI hint badge).
 */
export type RulePassResult = {
  canonicalParams: Record<string, string | string[]>;
  unresolvedRaw: Record<string, string | string[]>;
  notes: Array<{ canonicalKey: string; source: string; rule: string }>;
};

export function runRulePass(args: {
  schema: WorkflowSchema;
  rawParams: Record<string, unknown>;
  userQuery: string;
}): RulePassResult {
  const { schema, rawParams, userQuery } = args;
  const canonical: Record<string, string | string[]> = {};
  const unresolved: Record<string, string | string[]> = {};
  const notes: RulePassResult["notes"] = [];
  const schemaKeySet = new Set(schema.params.map((p) => p.name));
  const aliasOfMap = new Map<string, string>();
  for (const p of schema.params) {
    if (p.aliasOf) aliasOfMap.set(p.name, p.aliasOf);
  }
  const synonymIndex = buildSynonymIndex();

  for (const [rawKey, rawValRaw] of Object.entries(rawParams)) {
    const v = coerceValue(rawValRaw);
    if (v === undefined) continue;

    // 1. Direct hit — raw key matches a schema param.
    if (schemaKeySet.has(rawKey)) {
      const target = aliasOfMap.get(rawKey) ?? rawKey;
      const normalized = normalizeForSchema(v, target, schema);
      canonical[target] = normalized.value;
      notes.push({
        canonicalKey: target,
        source: rawKey,
        rule: target !== rawKey ? "direct + alias-of" : "direct",
      });
      continue;
    }

    // 2. Case-insensitive direct hit.
    const ciHit = [...schemaKeySet].find(
      (k) => k.toLowerCase() === rawKey.toLowerCase(),
    );
    if (ciHit) {
      const target = aliasOfMap.get(ciHit) ?? ciHit;
      const normalized = normalizeForSchema(v, target, schema);
      canonical[target] = normalized.value;
      notes.push({
        canonicalKey: target,
        source: rawKey,
        rule: "case-insensitive direct",
      });
      continue;
    }

    // 3. Synonym graph — does any schema key share a group with rawKey?
    const group = synonymIndex.get(rawKey.toLowerCase());
    if (group) {
      const schemaMember = group.find((g) => schemaKeySet.has(g));
      if (schemaMember) {
        const target = aliasOfMap.get(schemaMember) ?? schemaMember;
        const normalized = normalizeForSchema(v, target, schema);
        canonical[target] = normalized.value;
        notes.push({
          canonicalKey: target,
          source: rawKey,
          rule: `synonym(${group[0]})`,
        });
        continue;
      }
    }

    // No rule fired; leave for LLM.
    unresolved[rawKey] = v;
  }

  // 4. Free-text regex sweeps over userQuery for things the raw bag missed.
  applyAccessionSweeps({ schema, userQuery, canonical, notes });

  return { canonicalParams: canonical, unresolvedRaw: unresolved, notes };
}

function buildSynonymIndex(): Map<string, string[]> {
  const idx = new Map<string, string[]>();
  for (const group of SYNONYM_GROUPS) {
    for (const member of group) {
      idx.set(member.toLowerCase(), group);
    }
  }
  return idx;
}

function coerceValue(v: unknown): string | string[] | undefined {
  if (v === null || v === undefined) return undefined;
  if (typeof v === "string") {
    const t = v.trim();
    return t.length > 0 ? t : undefined;
  }
  if (typeof v === "number" || typeof v === "boolean") return String(v);
  if (Array.isArray(v)) {
    const items = v.map((x) => String(x)).filter((s) => s.length > 0);
    return items.length > 0 ? items : undefined;
  }
  return undefined;
}

/**
 * Normalize a value against the target param's spec.
 *   - For enum params: case-insensitive match, then space/dash → underscore.
 *   - For number params: cast.
 *   - For boolean: literal coercion.
 */
function normalizeForSchema(
  value: string | string[],
  paramName: string,
  schema: WorkflowSchema,
): { value: string | string[]; matched: boolean } {
  const spec = schema.params.find((p) => p.name === paramName);
  if (!spec) return { value, matched: false };
  if (Array.isArray(value)) {
    return {
      value: value.map((v) => normalizeSingle(v, spec)),
      matched: true,
    };
  }
  return { value: normalizeSingle(value, spec), matched: true };
}

function normalizeSingle(value: string, spec: ParamSpec): string {
  if (spec.type === "enum" && spec.enum) {
    // Direct case-insensitive match.
    const lit = spec.enum.find(
      (e) => e.toLowerCase() === value.toLowerCase(),
    );
    if (lit) return lit;
    // "T cells" → "T_cell", "anti CD8" → "anti_CD8"
    const norm = value.replace(/[\s-]+/g, "_");
    const lit2 = spec.enum.find(
      (e) => e.toLowerCase() === norm.toLowerCase(),
    );
    if (lit2) return lit2;
    // Singularize plural → e.g. "T_cells" → "T_cell"
    if (norm.endsWith("s")) {
      const sing = norm.slice(0, -1);
      const lit3 = spec.enum.find(
        (e) => e.toLowerCase() === sing.toLowerCase(),
      );
      if (lit3) return lit3;
    }
    return value; // hand to validation; flagged as enum violation downstream
  }
  if (spec.type === "boolean") {
    const t = value.toLowerCase();
    if (["true", "yes", "y", "1"].includes(t)) return "true";
    if (["false", "no", "n", "0"].includes(t)) return "false";
  }
  return value;
}

/**
 * Sweep the raw user query for common scientific identifiers and place them
 * in the matching workflow param if one exists and isn't already set.
 *
 * Conservative: only fires for unambiguous regex matches.
 */
const ACCESSION_PATTERNS: Array<{
  re: RegExp;
  paramHints: string[];
  rule: string;
}> = [
  { re: /\bSRR\d{6,}\b/, paramHints: ["reads", "fastq", "accession", "input"], rule: "sra-srr" },
  { re: /\bGSE\d{3,}\b/, paramHints: ["accession", "input", "geo"], rule: "geo-gse" },
  { re: /\bENSG\d{11}\b/, paramHints: ["gene", "target_gene"], rule: "ensembl-gene" },
  { re: /\bHP:\d{7}\b/, paramHints: ["hpo_term", "hpo_terms", "phenotype"], rule: "hpo-term" },
];

function applyAccessionSweeps(args: {
  schema: WorkflowSchema;
  userQuery: string;
  canonical: Record<string, string | string[]>;
  notes: RulePassResult["notes"];
}) {
  const { schema, userQuery, canonical, notes } = args;
  const schemaParamNames = new Set(schema.params.map((p) => p.name));
  for (const pat of ACCESSION_PATTERNS) {
    const matches = userQuery.match(new RegExp(pat.re, "g"));
    if (!matches || matches.length === 0) continue;
    const targetParam = pat.paramHints.find((h) => schemaParamNames.has(h));
    if (!targetParam) continue;
    if (canonical[targetParam] !== undefined) continue;
    canonical[targetParam] =
      matches.length === 1 ? matches[0] : Array.from(new Set(matches));
    notes.push({
      canonicalKey: targetParam,
      source: matches.join(","),
      rule: `regex(${pat.rule})`,
    });
  }
}

/**
 * Validate a final params dict against the schema. Returns invalid enum
 * violations and missing required params. Does NOT modify the dict.
 */
export type ValidationReport = {
  enumViolations: Array<{ key: string; value: string; allowed: string[] }>;
  missingRequired: string[];
  unknownKeys: string[];
};

export function validateAgainstSchema(
  params: Record<string, string | string[]>,
  schema: WorkflowSchema,
): ValidationReport {
  const schemaKeySet = new Set(schema.params.map((p) => p.name));
  const enumViolations: ValidationReport["enumViolations"] = [];
  for (const p of schema.params) {
    if (p.type !== "enum" || !p.enum) continue;
    const v = params[p.name];
    if (v === undefined) continue;
    const allowed = new Set(p.enum.map((s) => s.toLowerCase()));
    const values = Array.isArray(v) ? v : [v];
    for (const candidate of values) {
      if (!allowed.has(String(candidate).toLowerCase())) {
        enumViolations.push({
          key: p.name,
          value: String(candidate),
          allowed: p.enum,
        });
      }
    }
  }
  const missingRequired = schema.params
    .filter((p) => p.required && params[p.name] === undefined)
    .map((p) => p.name);
  const unknownKeys = Object.keys(params).filter(
    (k) => !schemaKeySet.has(k),
  );
  return { enumViolations, missingRequired, unknownKeys };
}
