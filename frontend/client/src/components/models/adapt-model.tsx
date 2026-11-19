/**
 * Adapt a model — the general model-adaptation flow (always usable).
 *
 * Start from a BUILT-IN base model (always available, so the tab functions out of the
 * box even before you've trained anything) OR one of your own registered models, add
 * new data / requirements, and fine-tune via the real ml_training methods
 * (SFT / DPO / RL(GRPO)). Adapting YOUR model registers its NEXT VERSION (the backend
 * forces the output name to the base's so versioning keys on it); a built-in base
 * trains a new specialized model (it has no prior version to increment).
 *
 * HONEST scope: runs on the verified CPU / small-model path today (SmolLM2-135M);
 * large / GPU-scale adaptation is a separate, deferred tier — the copy says so.
 *
 * Reuses the catalog (useModels) + the existing TrainingLauncher (with an adaptOf prop),
 * so the data upload, method selection and launch are the tested launcher machinery.
 */
import { useState } from "react"
import { t } from "@/lib/i18n"
import { useActiveProjectSafe } from "@/contexts/active-project-context"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { useModels } from "./models-api"
import { TrainingLauncher } from "./training-launcher"

const SELECT = "mt-1 w-full rounded border bg-background px-2 py-1 text-xs"

// Built-in starting points you can fine-tune — always available so the tab is usable
// even before you've registered any models of your own. Only the verified CPU/small
// model is offered; larger bases arrive with the GPU tier (kept honest, not implied).
const BUILT_IN_BASES = [{ id: "base:llm-small", labelKey: "adapt_base_llm_small" }]

export function AdaptModel({ project }: { project?: string }) {
  const ctx = useActiveProjectSafe()
  const projectId = project || ctx?.activeProjectId || ""
  const models = useModels()
  const [baseId, setBaseId] = useState("")

  // Your own registered models can be versioned; hosted BioNeMo models are inference-only.
  const owned = (models.data ?? []).filter((m) => m.origin === "custom")
  const isBuiltIn = baseId.startsWith("base:")
  // Only your own models thread adapt_of (→ next version). A built-in base trains fresh.
  const adaptOf = baseId && !isBuiltIn ? baseId : undefined

  return (
    <div className="space-y-2" data-testid="adapt-model">
      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-sm">{t("models.adapt_model_heading")}</CardTitle>
        </CardHeader>
        <CardContent className="space-y-2">
          <p className="text-fs-xs text-muted-foreground" data-testid="adapt-model-intro">
            {t("models.adapt_model_intro")}
          </p>
          <p className="text-fs-xs text-muted-foreground/70" data-testid="adapt-model-scope">
            {t("models.adapt_model_scope_note")}
          </p>
          <label className="block text-xs">
            {t("models.adapt_model_base")}
            <select
              className={SELECT}
              value={baseId}
              data-testid="adapt-model-base"
              onChange={(e) => setBaseId(e.target.value)}
            >
              <option value="">{t("models.adapt_model_choose")}</option>
              <optgroup label={t("models.adapt_model_group_base")}>
                {BUILT_IN_BASES.map((b) => (
                  <option key={b.id} value={b.id}>
                    {t(`models.${b.labelKey}`)}
                  </option>
                ))}
              </optgroup>
              <optgroup label={t("models.adapt_model_group_yours")}>
                {owned.length > 0 ? (
                  owned.map((m) => (
                    <option key={m.id} value={m.id}>
                      {m.name} (v{m.version})
                    </option>
                  ))
                ) : (
                  <option value="" disabled>
                    {t("models.adapt_model_none_yet")}
                  </option>
                )}
              </optgroup>
            </select>
          </label>
          {/* How a model gets here — so the picker isn't a dead end when empty. */}
          <p className="text-fs-xs text-muted-foreground/70" data-testid="adapt-model-source">
            {t("models.adapt_model_source_hint")}
          </p>
          {baseId && (
            <p className="text-fs-xs text-muted-foreground/70" data-testid="adapt-model-mode">
              {isBuiltIn ? t("models.adapt_model_mode_base") : t("models.adapt_model_mode_version")}
            </p>
          )}
        </CardContent>
      </Card>

      {/* Once a base is chosen, the launcher drives data upload + method + launch.
          adaptOf is set only for your own models, so they version; a base trains fresh. */}
      {baseId && <TrainingLauncher family="general" adaptOf={adaptOf} llmOnly={isBuiltIn} />}
    </div>
  )
}
