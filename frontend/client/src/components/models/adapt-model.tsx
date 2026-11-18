/**
 * Adapt a model — the general model-adaptation flow.
 *
 * Pick one of your registered models and adapt it to new data or requirements via the
 * real ml_training methods (SFT / DPO / RL(GRPO) / rule-following). It launches through
 * the ordinary training plan→execute path, tagged as an adaptation, and the result
 * registers as the base model's NEXT VERSION (the backend forces the output name to the
 * base's so versioning keys on it). HONEST scope: LLM DPO/GRPO/SFT run on the verified
 * CPU/small-model path today; large/GPU-scale adaptation is a separate, deferred tier —
 * the copy says so and never implies otherwise.
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

export function AdaptModel({ project }: { project?: string }) {
  const ctx = useActiveProjectSafe()
  const projectId = project || ctx?.activeProjectId || ""
  const models = useModels()
  const [baseId, setBaseId] = useState("")

  // Adaptable = models you can version: your own registered/custom models. Hosted
  // BioNeMo models are inference-only pretrained artifacts — not adaptable here.
  const adaptable = (models.data ?? []).filter((m) => m.origin === "custom")

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
          {models.isPending ? (
            <p role="status" className="text-fs-xs text-muted-foreground">{t("models.activity_loading")}</p>
          ) : adaptable.length === 0 ? (
            <p className="text-fs-xs text-muted-foreground" data-testid="adapt-model-empty">
              {t("models.adapt_model_empty")}
            </p>
          ) : (
            <label className="block text-xs">
              {t("models.adapt_model_base")}
              <select
                className={SELECT}
                value={baseId}
                data-testid="adapt-model-base"
                onChange={(e) => setBaseId(e.target.value)}
              >
                <option value="">{t("models.adapt_model_choose")}</option>
                {adaptable.map((m) => (
                  <option key={m.id} value={m.id}>
                    {m.name} (v{m.version})
                  </option>
                ))}
              </select>
            </label>
          )}
        </CardContent>
      </Card>

      {/* Once a base is chosen, the launcher drives data upload + method + launch,
          threading adapt_of so the result versions that model. */}
      {baseId && <TrainingLauncher family="general" adaptOf={baseId} />}
    </div>
  )
}
