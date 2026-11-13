import { neutralizeMarkup } from "./project-rules";
/**
 * Request-scoped context helpers for the chat stream.
 *
 * Keeping this logic independent of Express makes the boundary between a
 * browser-supplied composer value and the assistant prompt testable without
 * starting the full API (or calling an LLM).
 */
export const MAX_COMPOSER_INSTRUCTIONS_LENGTH = 24_000;

export function normalizeComposerInstructions(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;

  // User text in a system prompt never becomes markup (project-rules.ts neutralizeMarkup).
  const normalized = neutralizeMarkup(value.trim().slice(0, MAX_COMPOSER_INSTRUCTIONS_LENGTH));
  return normalized || undefined;
}

/**
 * Adds one-turn composer guidance after durable project background. The
 * caller owns persistence; this function deliberately has no side effects.
 */
export function appendComposerInstructions(
  projectContext: string | undefined,
  composerInstructions: unknown,
): { projectContext: string | undefined; composerInstructions: string | undefined } {
  const normalized = normalizeComposerInstructions(composerInstructions);
  if (!normalized) {
    return { projectContext, composerInstructions: undefined };
  }

  return {
    projectContext: [
      projectContext,
      `Composer instructions for this chat:\n${normalized}`,
    ].filter(Boolean).join("\n\n"),
    composerInstructions: normalized,
  };
}

/**
 * Merge the project's server-loaded output-requirements prompt into the project
 * context so persisted output formats shape the answer even when the request did
 * NOT come from the chat composer (MCP / programmatic / other clients that never
 * thread `composerInstructions`).
 *
 * Dedupe: the browser composer (chat-input.tsx) already folds
 * `outputRequirementsToPrompt(...)` into `composerInstructions`, which
 * `appendComposerInstructions` injects separately. When that exact block is
 * present we must NOT inject a second copy — so this skips when the normalized
 * composer value already contains the prompt (and is idempotent against a
 * projectContext that already carries it). Empty prompt ⇒ unchanged context.
 */
export function appendProjectOutputRequirements(
  projectContext: string | undefined,
  outputRequirementsPrompt: string | null | undefined,
  composerInstructions: unknown,
): string | undefined {
  const prompt = neutralizeMarkup((outputRequirementsPrompt ?? "").trim());
  if (!prompt) return projectContext;

  const composer = normalizeComposerInstructions(composerInstructions) ?? "";
  if (composer.includes(prompt)) return projectContext; // client already threaded it
  if (projectContext && projectContext.includes(prompt)) return projectContext; // idempotent

  return [projectContext, prompt].filter(Boolean).join("\n\n");
}

/**
 * The scope at which a deliverable generator applies the project's output
 * requirements. Each scope frames the SAME rendered requirements prompt with the
 * directive wording appropriate to that deliverable, so the application is ONE
 * mechanism instead of three hand-rolled concatenations.
 *
 *  - `report`            — a full downloadable methods/results report (methods-report, IND docx).
 *  - `findings-summary`  — the short narrative `summary` prose of a findings JSON object.
 *  - `figure`            — a figure-producing step (dpi / palette / vector guidance).
 */
export type OutputRequirementsScope = "report" | "findings-summary" | "figure";

/**
 * Pure composer for the output-requirements chokepoint. Given an LLM prompt and
 * the project's ALREADY-RENDERED requirements block (from
 * `outputRequirementsToPrompt` / `loadProjectOutputRequirementsPrompt`), it
 * appends the scope-appropriate directive. Empty requirements ⇒ the prompt is
 * returned UNCHANGED (behavior unchanged when nothing is configured).
 *
 * This is the single place that frames requirements for an LLM deliverable; the
 * async `applyOutputRequirements` wrapper (project-instruction-settings.ts) loads
 * the block and delegates here. Kept pure (no DB / Express) so it is unit-testable.
 */
export function appendOutputRequirementsBlock(
  prompt: string,
  requirementsPrompt: string | null | undefined,
  scope: OutputRequirementsScope,
): string {
  const block = (requirementsPrompt ?? "").trim();
  if (!block) return prompt;
  // Idempotent: never append a second identical block.
  if (prompt.includes(block)) return prompt;

  let directive: string;
  switch (scope) {
    case "findings-summary":
      directive = `PROJECT OUTPUT REQUIREMENTS — apply to the "summary" prose (length, ordering, emphasis) where they fit a short findings narrative; NEVER fabricate numbers or restructure the JSON to satisfy them:\n${block}`;
      break;
    case "figure":
      directive = `=== PROJECT OUTPUT REQUIREMENTS (apply to figures: resolution, palette, labels; never invent data to satisfy a format) ===\n${block}`;
      break;
    case "report":
    default:
      directive = `=== PROJECT OUTPUT REQUIREMENTS (apply to this deliverable; do not fabricate data to satisfy a format) ===\n${block}`;
      break;
  }
  return `${prompt}\n\n${directive}`;
}
