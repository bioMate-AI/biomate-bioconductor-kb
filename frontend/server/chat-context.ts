/**
 * Request-scoped context helpers for the chat stream.
 *
 * Keeping this logic independent of Express makes the boundary between a
 * browser-supplied composer value and the assistant prompt testable without
 * starting the full API (or calling an LLM).
 */
export const MAX_COMPOSER_INSTRUCTIONS_LENGTH = 4_000;

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
