/** UI language is a display preference, never a workflow/parameter translation instruction. */
export function normalizeUiLanguage(value: unknown): 'en' | 'zh' | undefined {
  return value === 'en' || value === 'zh' ? value : undefined;
}

export function responseLanguageDirective(value: unknown): string {
  const language = normalizeUiLanguage(value);
  if (!language) return '';
  const target = language === 'zh' ? 'Simplified Chinese (简体中文)' : 'English';
  return `\n\nRESPONSE LANGUAGE: The user's interface language is ${target}. Write explanatory prose, summaries, and findings in ${target} by default. If the user explicitly requests another reply language, honor that request. Keep code, SMILES, file paths, parameter names and values, accession IDs, tool/pipeline proper names, and quoted source text unchanged. This instruction affects the narrative only; never translate tool arguments, routing identifiers, or execution parameters.`;
}
