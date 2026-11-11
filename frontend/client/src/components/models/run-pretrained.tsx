/**
 * RunPretrained — the "Run a model" track (a pre-trained model, run for inference).
 *
 * Distinct from Train: these models arrive already fitted. You pick a domain
 * (structure · genomic · chemical), supply an input, submit inference, and the
 * result renders through the wave-1 viewers by evidence class.
 *
 * Flow (WS1 contract):
 *   POST /api/models/{id}/infer  {inputs} -> { run_id }
 *   poll GET /api/inference/{run_id}/result until status === 'completed'
 *
 * Model choice: the domain maps to an evidence class; the concrete model id is
 * chosen from the live catalog (first model whose family/evidence matches). If
 * no catalog model matches (e.g. BioNeMo not enumerated), the domain's default
 * BioNeMo id is used so the request still exercises the real endpoint — the
 * backend answers with a labelled stub when unreachable.
 */

import { useMemo, useState } from "react"
import { t } from "@/lib/i18n"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Textarea } from "@/components/ui/textarea"
import { Play, Loader2, Sparkles } from "lucide-react"
import { useModels, useInfer, useInferenceResult } from "./models-api"
import { InferenceResultView } from "./inference-result"
import type { EvidenceClass, ModelSummary } from "./types"

// ── Domain definitions ───────────────────────────────────────────────────────
interface Domain {
  id: EvidenceClass
  /** default catalog id if none matches the family filter. */
  defaultModelId: string
  /** which catalog family strings belong to this domain. */
  families: string[]
  inputKey: "sequence" | "smiles"
}


const DOMAINS: Domain[] = [
  {
    id: "structure",
    defaultModelId: "bionemo:boltz2",
    families: ["structure"],
    inputKey: "sequence",
  },
  {
    id: "genomic",
    defaultModelId: "bionemo:evo2_7b",
    families: ["genomic"],
    inputKey: "sequence",
  },
  {
    id: "chemical",
    defaultModelId: "",
    families: ["python", "docker", "rest", "custom", "chemical"],
    inputKey: "smiles",
  },
]

// Pick a concrete catalog model id for a domain, or the domain default.
function pickModelId(domain: Domain, catalog: ModelSummary[] | undefined): string {
  const match = (catalog ?? []).find((m) => domain.families.includes(m.family))
  return match?.id ?? domain.defaultModelId
}

interface RunPretrainedProps {
  onOpenModel?: (modelId: string) => void
  className?: string
}

export function RunPretrained({ onOpenModel, className }: RunPretrainedProps) {
  const [domainId, setDomainId] = useState<EvidenceClass>("structure")
  const [inputText, setInputText] = useState("")
  const [runId, setRunId] = useState<string | null>(null)

  const { data: catalog } = useModels()
  const infer = useInfer()
  const { data: result } = useInferenceResult(runId)

  const domain = useMemo(() => DOMAINS.find((d) => d.id === domainId)!, [domainId])
  const modelId = useMemo(() => pickModelId(domain, catalog), [domain, catalog])

  const canRun = inputText.trim().length > 0 && !!modelId && !infer.isPending
  const running = infer.isPending || result?.status === "running"

  const buildInputs = (): Record<string, unknown> => {
    if (domain.inputKey === "smiles") {
      const smiles = inputText.split(/\n+/).map((s) => s.trim()).filter(Boolean)
      return { smiles }
    }
    return { sequence: inputText.trim() }
  }

  const run = () => {
    setRunId(null)
    infer.mutate(
      { modelId, inputs: buildInputs() },
      { onSuccess: (res) => setRunId(res.run_id) },
    )
  }

  const selectDomain = (id: EvidenceClass) => {
    setDomainId(id)
    setRunId(null)
    setInputText("")
  }

  return (
    <div className={className} data-testid="run-pretrained">
      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-sm">{t("models.run_model_heading")}</CardTitle>
          <p className="text-fs-xs text-muted-foreground">{t("models.run_model_intro")}</p>
        </CardHeader>
        <CardContent className="space-y-3">
          {/* Domain picker */}
          <div className="flex items-center gap-1 flex-wrap" data-testid="domain-picker">
            {DOMAINS.map((d) => (
              <Button
                key={d.id}
                variant={domainId === d.id ? "default" : "outline"}
                size="sm"
                className="h-7 text-xs"
                data-testid={`domain-${d.id}`}
                onClick={() => selectDomain(d.id)}
              >
                {t(`models.domain_${d.id}`)}
              </Button>
            ))}
          </div>

          <div className="space-y-1">
            <p className="text-xs font-semibold">{t(`models.domain_goal_${domain.id}`)}</p>
            <div className="flex items-center gap-2 flex-wrap text-fs-xs">
              <Badge variant="outline">{domain.id}</Badge>
              {modelId ? (
                <button
                  type="button"
                  className="font-mono text-primary hover:underline"
                  data-testid="run-pretrained-model"
                  onClick={() => onOpenModel?.(modelId)}
                >
                  {modelId}
                </button>
              ) : (
                <span className="text-muted-foreground" data-testid="run-pretrained-no-model">
                  {t("models.no_model_for_domain")}
                </span>
              )}
              <span className="text-muted-foreground">{t(`models.domain_produces_${domain.id}`)}</span>
            </div>
            <button
              type="button"
              className="flex items-center gap-1 text-fs-xs text-muted-foreground hover:text-foreground"
              onClick={() => setInputText(t(`models.domain_example_${domain.id}`))}
              data-testid="run-pretrained-example"
            >
              <Sparkles className="h-3 w-3" />
              <span className="italic">{t("models.use_example_input")}</span>
            </button>
          </div>

          {/* Input */}
          <div className="space-y-1">
            <label className="text-fs-xs uppercase tracking-wide text-muted-foreground">
              {t(`models.domain_input_${domain.id}`)}
            </label>
            <Textarea
              value={inputText}
              onChange={(e) => setInputText(e.target.value)}
              placeholder={t(`models.domain_placeholder_${domain.id}`)}
              className="font-mono text-xs min-h-[80px]"
              data-testid="run-pretrained-input"
            />
          </div>

          <div className="flex items-center gap-2 flex-wrap">
            <Button
              size="sm"
              className="h-7 text-xs"
              disabled={!canRun}
              onClick={run}
              data-testid="run-pretrained-submit"
            >
              {running ? (
                <>
                  <Loader2 className="h-3 w-3 mr-1 animate-spin" />
                  {t("models.inference_running")}
                </>
              ) : (
                <>
                  <Play className="h-3 w-3 mr-1" />
                  {t("models.run_inference")}
                </>
              )}
            </Button>
            {infer.isError && (
              <span className="text-fs-xs text-destructive" data-testid="run-pretrained-error">
                {infer.error instanceof Error ? infer.error.message : t("models.inference_failed")}
              </span>
            )}
          </div>
        </CardContent>
      </Card>

      {/* Result */}
      {runId && (
        <Card className="mt-3" data-testid="run-pretrained-result-card">
          <CardHeader className="pb-2">
            <div className="flex items-center gap-2 flex-wrap">
              <CardTitle className="text-sm">{t("models.result_heading")}</CardTitle>
              {result?.status === "running" && (
                <Badge variant="outline" className="text-fs-xs gap-1" data-testid="result-status-running">
                  <Loader2 className="h-3 w-3 animate-spin" />
                  {t("models.run_status_running")}
                </Badge>
              )}
              {result?.status === "completed" && (
                <Badge variant="outline" className="text-fs-xs" data-testid="result-status-completed">
                  {t("models.run_status_completed")}
                </Badge>
              )}
              {result?.status === "failed" && (
                <Badge variant="destructive" className="text-fs-xs" data-testid="result-status-failed">
                  {t("models.run_status_failed")}
                </Badge>
              )}
              <span className="text-fs-xs font-mono text-muted-foreground ml-auto">{modelId}</span>
            </div>
          </CardHeader>
          <CardContent>
            {result?.status === "failed" && (
              <p className="text-xs text-destructive" data-testid="result-error">
                {result.error ?? t("models.inference_incomplete")}
              </p>
            )}
            {result?.status === "completed" && (
              <InferenceResultView
                result={result}
                evidenceClass={domainId}
                onOpenModel={onOpenModel}
              />
            )}
            {(!result || result.status === "running") && (
              <p className="text-xs text-muted-foreground" data-testid="result-pending">
                {t("models.inference_pending")}
              </p>
            )}
          </CardContent>
        </Card>
      )}
    </div>
  )
}
