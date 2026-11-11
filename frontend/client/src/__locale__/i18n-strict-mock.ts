/** Strict single-bundle i18n for locale tests: no fallback to the other language. */
export function strictI18n(bundle: Record<string, any>, localeCode: "en" | "zh") {
  const look = (key: string) => key.split(".").reduce((v: any, p) => (v && typeof v === "object" ? v[p] : undefined), bundle)
  const fill = (s: string, vars?: Record<string, unknown>) => s.replace(/\{\{\s*(\w+)\s*\}\}/g, (m, k) => (vars && k in vars ? String(vars[k]) : m))
  const t = (key: string, vars?: Record<string, unknown>) => {
    const v = look(key)
    return typeof v === "string" ? fill(v, vars) : `⟦MISSING:${key}⟧`
  }
  return {
    locale: localeCode,
    t,
    tOr: (key: string, _fallback: string, vars?: Record<string, unknown>) => t(key, vars),
    tStatus: (s: string) => t(`workflow.status.${s}`),
    setLanguagePreference: () => {},
    normaliseLocale: () => localeCode,
    detectLocale: () => localeCode,
    readStoredLanguage: () => null,
    SUPPORTED_LOCALES: ["en", "zh", "ja", "es"],
    onPrem: false,
  }
}
