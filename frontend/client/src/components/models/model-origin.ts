import { t, tOr } from "@/lib/i18n"

/**
 * Localized label for a model's backend origin. The catalog reports the REAL
 * backend (models_inference._bionemo_catalog): "self_host" when a self-host NIM
 * URL is set, "hosted_nvidia" when it falls back to NVIDIA's hosted API,
 * "unconfigured" when no backend is reachable, "custom" for a registered model.
 * An unknown code renders verbatim (never a bare i18n key).
 */
const KNOWN = new Set(["self_host", "hosted_nvidia", "unconfigured", "custom", "aws_batch"])
export function originLabel(origin: string | null | undefined): string {
  const code = (origin || "").trim()
  if (!code) return tOr("models.origin_unconfigured", "Not configured")
  return KNOWN.has(code) ? t(`models.origin_${code}`) : code
}
