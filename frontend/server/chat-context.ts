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

  const normalized = value.trim().slice(0, MAX_COMPOSER_INSTRUCTIONS_LENGTH);
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
  const prompt = (outputRequirementsPrompt ?? "").trim();
  if (!prompt) return projectContext;

  const composer = normalizeComposerInstructions(composerInstructions) ?? "";
  if (composer.includes(prompt)) return projectContext; // client already threaded it
  if (projectContext && projectContext.includes(prompt)) return projectContext; // idempotent

  return [projectContext, prompt].filter(Boolean).join("\n\n");
}
