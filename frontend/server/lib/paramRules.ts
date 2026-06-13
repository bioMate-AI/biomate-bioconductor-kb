/**
 * paramRules.ts — Stage 3a: rule-based parameter extraction.
 *
 * Runs BEFORE the LLM resolver. Cheap, deterministic, testable. Catches:
 *   - direct key hits (raw has the canonical name already)
 *   - global synonym graph (disease ≡ indication ≡ condition ≡ disease_area)
 *   - enum normalization ("T cells" → "T_cell" when an enum has T_cell)
 *
 * Note: accession-ID and genome-build extraction are DELIBERATELY NOT here.
 * The backend (backend/lib/galaxy/ai/ai_assistant.py:_extract_sra_accession,
 * _extract_genome_build, _inject_sra_into_params) already runs these on
 * user_intent BEFORE returning workflow_ga, populating param defaults. The
 * extractor sees those pre-filled defaults via the schema and treats them
 * as already-resolved.
 *
 * The synonym graph is intentionally small. The LLM handles the long tail
 * using the schema's own descriptions.
 */

import type { ParamSpec, WorkflowSchema } from "./paramSchema.js";

/**
 * Global synonym graph. Each entry is a set of equivalent concept names.
 * Lookup: if any synonym appears in the raw bag AND the workflow declares
 * any other synonym from the same set as a param, the value moves there.
 *
 * Keep small. The LLM uses param descriptions for the long tail.
 */
const SYNONYM_GROUPS: string[][] = [
  ["indication", "disease", "condition", "disease_area", "therapeutic_area"],
  ["delivery_cell", "cell_type", "cells", "target_cells", "cell"],
  ["target_gene", "gene", "target_protein"],
  ["car_target", "target_antigen", "antigen"],
  ["lnp_targeting", "delivery_vehicle", "targeting_ligand", "lnp_target"],
  ["target_a", "target_1", "first_target", "targeta"],
  ["target_b", "target_2", "second_target", "targetb"],
  ["edit_goal", "goal", "editing_strategy", "edit_type", "edit"],
];

export type RulePassResult = {
  canonicalParams: Record<string, string | string[]>;
  unresolvedRaw: Record<string, string | string[]>;
  notes: Array<{ canonicalKey: string; source: string; rule: string }>;
};

export function runRulePass(args: {
  schema: WorkflowSchema;
  rawParams: Record<string, unknown>;
}): RulePassResult {
  const { schema, rawParams } = args;
  const canonical: Record<string, string | string[]> = {};
  const unresolved: Record<string, string | string[]> = {};
  const notes: RulePassResult["notes"] = [];
  const schemaKeySet = new Set(schema.params.map((p) => p.name));
  const synonymIndex = buildSynonymIndex();

  for (const [rawKey, rawValRaw] of Object.entries(rawParams)) {
    const v = coerceValue(rawValRaw);
    if (v === undefined) continue;

    // 1. Direct hit — raw key matches a schema param.
    if (schemaKeySet.has(rawKey)) {
      const normalized = normalizeForSchema(v, rawKey, schema);
      canonical[rawKey] = normalized.value;
      notes.push({ canonicalKey: rawKey, source: rawKey, rule: "direct" });
      continue;
    }

    // 2. Case-insensitive direct hit.
    const ciHit = [...schemaKeySet].find(
      (k) => k.toLowerCase() === rawKey.toLowerCase(),
    );
    if (ciHit) {
      const normalized = normalizeForSchema(v, ciHit, schema);
      canonical[ciHit] = normalized.value;
      notes.push({
        canonicalKey: ciHit,
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
        const normalized = normalizeForSchema(v, schemaMember, schema);
        canonical[schemaMember] = normalized.value;
        notes.push({
          canonicalKey: schemaMember,
          source: rawKey,
          rule: `synonym(${group[0]})`,
        });
        continue;
      }
    }

    unresolved[rawKey] = v;
  }

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
    const lit = spec.enum.find(
      (e) => e.toLowerCase() === value.toLowerCase(),
    );
    if (lit) return lit;
    const norm = value.replace(/[\s-]+/g, "_");
    const lit2 = spec.enum.find(
      (e) => e.toLowerCase() === norm.toLowerCase(),
    );
    if (lit2) return lit2;
    if (norm.endsWith("s")) {
      const sing = norm.slice(0, -1);
      const lit3 = spec.enum.find(
        (e) => e.toLowerCase() === sing.toLowerCase(),
      );
      if (lit3) return lit3;
    }
    return value;
  }
  if (spec.type === "boolean") {
    const t = value.toLowerCase();
    if (["true", "yes", "y", "1"].includes(t)) return "true";
    if (["false", "no", "n", "0"].includes(t)) return "false";
  }
  return value;
}

/**
 * Validate a final params dict against the schema. Returns enum violations
 * and missing required params. Does NOT modify the dict.
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
  const unknownKeys = Object.keys(params).filter((k) => !schemaKeySet.has(k));
  return { enumViolations, missingRequired, unknownKeys };
}
