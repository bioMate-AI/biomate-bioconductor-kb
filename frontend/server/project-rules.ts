/**
 * Project instructions ("rules") as every LLM consumer receives them.
 *
 * Instruction-panel committee audit (2026-11-12) found the rules were injected as "Research goal:
 * <text>" under a note calling them "background context", above a "highest priority" block that
 * could override them; never reached intent analysis (so "always use GRCh38" / "FDR 0.01" never
 * became parameter values); were not delimited (a rule could close the <project_context> tag); and
 * two invisible sources (legacy `instructions`, promoted knowledge rows) were injected too.
 * One renderer, one source (what the Instructions page shows), one precedence statement.
 */

const MAX_RULES = 50;
const MAX_RULE_CHARS = 500;
const MAX_TOTAL_CHARS = 8000;

/** User text never becomes markup in a system prompt: a "<" that would open or close a tag
 *  ("<project_context>", "</x>", "<!--") is neutralised; comparisons ("FDR < 0.05", "p<0.01")
 *  are scientific content and stay exact. */
export function neutralizeMarkup(text: string): string {
  return String(text ?? '').replace(/<(?=[\/!A-Za-z])/g, '‹');
}

/** The rules the Instructions page shows: research_goal (one rule per line), falling back to the
 *  legacy `instructions` column only when that is all the project has (never both). */
export function projectRulesFrom(row: { research_goal?: string | null; instructions?: string | null }): string[] {
  const source = (row.research_goal && row.research_goal.trim()) ? row.research_goal : (row.instructions || '');
  const out: string[] = [];
  let total = 0;
  for (const line of String(source).split(/\r?\n/)) {
    const rule = neutralizeMarkup(line.trim()).slice(0, MAX_RULE_CHARS);
    if (!rule) continue;
    if (out.length >= MAX_RULES || total + rule.length > MAX_TOTAL_CHARS) break;
    out.push(rule);
    total += rule.length;
  }
  return out;
}

export const PROJECT_RULES_PRECEDENCE =
  "Precedence: BioMate's safety, data-integrity and privacy rules come first; then the user's current message; then these project rules; then your defaults.";

/** The <project_context> body: who the project is, then its rules as numbered directives. */
export function renderProjectContext(p: { name?: string | null; description?: string | null }, rules: string[]): string {
  const parts: string[] = [];
  if (p.name) parts.push(`Project: ${neutralizeMarkup(p.name)}`);
  if (p.description) parts.push(`Description: ${neutralizeMarkup(p.description)}`);
  if (rules.length) {
    parts.push(`Project instructions set by the project's members — follow them in every reply and when choosing workflows and parameter values:\n${rules.map((r, i) => `${i + 1}. ${r}`).join('\n')}`);
  }
  return parts.join('\n');
}

/** Note printed after the <project_context> block in the response prompt. */
export const PROJECT_CONTEXT_NOTE =
  `Note: the block above is the user's active project. Its numbered project instructions are standing directives from the user — apply them to this reply (and to any workflow, parameter or analysis you propose). ${PROJECT_RULES_PRECEDENCE}`;

/** Block for the intent analyzer: rules that should shape extracted parameter values. */
export function intentRulesBlock(rules: string[] | undefined): string {
  if (!rules?.length) return '';
  return `<project_instructions>\nThe user set these standing instructions for this project. When you extract inlineParameters, apply any that set a parameter value (e.g. reference genome, significance threshold, organism) unless the current message explicitly says otherwise. They never change WHAT the user asked for.\n${rules.map((r, i) => `${i + 1}. ${r}`).join('\n')}\n</project_instructions>\n\n`;
}
