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

import { useEffect, useMemo, useState } from "react"
import { t } from "@/lib/i18n"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Textarea } from "@/components/ui/textarea"
import { Play, Loader2, Sparkles } from "lucide-react"
import { useModels, useInfer, useInferenceResult, useRunStatus, launchFold, TrainingLaunchError } from "./models-api"
import { TERMINAL_STATUSES, openRunManager, runStatusLabel } from "./training-logic"
import { InferenceResultView } from "./inference-result"
import type { EvidenceClass, ModelSummary } from "./types"
import { originLabel } from "./model-origin"

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
    // Evo2 has no BioMate-owned execution path yet (NVIDIA-hosted only), so it is
    // not advertised — no default model until it runs on our own Batch. The domain
    // then honestly shows "no model for this domain" (founder: no NVIDIA-hosted).
    id: "genomic",
    defaultModelId: "",
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
  /** A model id to preselect (from the detail view's "Use in a run"). Its domain
   *  is selected so the user lands on the right run surface. */
  initialModelId?: string
}

export function RunPretrained({ onOpenModel, className, initialModelId }: RunPretrainedProps) {
  const [domainId, setDomainId] = useState<EvidenceClass>("structure")
  const [inputText, setInputText] = useState("")
  const [runId, setRunId] = useState<string | null>(null)
  // Structure folds run on OUR AWS Batch (Boltz-2) as a tracked workflow run,
  // not NVIDIA's hosted API — launchFold → /api/workflows/execute → poll status.
  const [foldRunId, setFoldRunId] = useState<string | null>(null)
  const [foldBusy, setFoldBusy] = useState(false)
  const [foldError, setFoldError] = useState("")
  const isStructure = domainId === "structure"
  const foldStatus = useRunStatus(foldRunId, (sx) => TERMINAL_STATUSES.has(String(sx).toLowerCase()))
  const foldState = String(foldStatus.data?.status ?? "").toLowerCase()
  const foldDone = TERMINAL_STATUSES.has(foldState)

  const { data: catalog } = useModels()
  const infer = useInfer()
  const { data: result } = useInferenceResult(runId)

  const domain = useMemo(() => DOMAINS.find((d) => d.id === domainId)!, [domainId])
  const modelId = useMemo(() => pickModelId(domain, catalog), [domain, catalog])
  // The catalog row for the resolved model, for an honest name + execution origin
  // (Boltz-2 reports "BioMate compute", not NVIDIA, since it folds on our Batch).
  const catalogModel = useMemo(() => (catalog ?? []).find((m) => m.id === modelId), [catalog, modelId])

  // "Use in a run" from the model detail view: switch to the domain whose family
  // matches the chosen model, so the user lands on the right run surface.
  useEffect(() => {
    if (!initialModelId || !catalog) return
    const chosen = catalog.find((m) => m.id === initialModelId)
    const dom = chosen ? DOMAINS.find((d) => d.families.includes(chosen.family)) : undefined
    if (dom) setDomainId(dom.id as EvidenceClass)
  }, [initialModelId, catalog])

  const canRun = inputText.trim().length > 0 && (isStructure
    ? !foldBusy && !(foldRunId && !foldDone)
    : (!!modelId && !infer.isPending))
  const running = isStructure
    ? (foldBusy || (!!foldRunId && !foldDone))
    : (infer.isPending || result?.status === "running")

  const buildInputs = (): Record<string, unknown> => {
    if (domain.inputKey === "smiles") {
      const smiles = inputText.split(/\n+/).map((s) => s.trim()).filter(Boolean)
      return { smiles }
    }
    return { sequence: inputText.trim() }
  }

  const run = () => {
    if (isStructure) {
      setFoldRunId(null); setFoldError(""); setFoldBusy(true)
      launchFold({ sequence: inputText.trim() })
        .then(({ runId: id }) => setFoldRunId(id))
        .catch((cause) => setFoldError(
          cause instanceof TrainingLaunchError
            ? t("models.fold_launch_failed", { detail: cause.detail })
            : (cause instanceof Error ? cause.message : String(cause)),
        ))
        .finally(() => setFoldBusy(false))
      return
    }
    setRunId(null)
    infer.mutate(
      { modelId, inputs: buildInputs() },
      { onSuccess: (res) => setRunId(res.run_id) },
    )
  }

  const selectDomain = (id: EvidenceClass) => {
    setDomainId(id)
    setRunId(null)
    setFoldRunId(null); setFoldError("")
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
              <Badge variant="outline">{t(`models.domain_${domain.id}`)}</Badge>
              {modelId ? (
                <button
                  type="button"
                  className="text-primary hover:underline"
                  data-testid="run-pretrained-model"
                  onClick={() => onOpenModel?.(modelId)}
                >
                  {catalogModel?.name ?? modelId}
                </button>
              ) : (
                <span className="text-muted-foreground" data-testid="run-pretrained-no-model">
                  {domain.id === "genomic"
                    ? t("models.no_model_genomic")
                    : domain.id === "chemical"
                      ? t("models.no_model_chemical")
                      : t("models.no_model_for_domain")}
                </span>
              )}
              {catalogModel?.origin && (
                <Badge variant="outline" className="text-fs-xs" data-testid="run-pretrained-origin">
                  {originLabel(catalogModel.origin)}
                </Badge>
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
            {isStructure && foldError && (
              <span className="text-fs-xs text-destructive" data-testid="run-pretrained-error">{foldError}</span>
            )}
            {!isStructure && infer.isError && (
              <span className="text-fs-xs text-destructive" data-testid="run-pretrained-error">
                {infer.error instanceof Error ? infer.error.message : t("models.inference_failed")}
              </span>
            )}
          </div>
        </CardContent>
      </Card>

      {/* Structure fold result — a tracked Batch run (our own Boltz-2). */}
      {isStructure && foldRunId && (
        <Card className="mt-3" data-testid="fold-run-card">
          <CardHeader className="pb-2">
            <div className="flex items-center gap-2 flex-wrap">
              <CardTitle className="text-sm">{t("models.fold_run_heading")}</CardTitle>
              <Badge variant={foldState === "failed" ? "destructive" : "outline"} className="text-fs-xs gap-1" data-testid="fold-run-status">
                {!foldDone && <Loader2 className="h-3 w-3 animate-spin" />}
                {foldState ? runStatusLabel(foldState) : t("models.run_status_running")}
              </Badge>
              <span className="text-fs-xs text-muted-foreground ml-auto">{t("models.fold_compute_badge")}</span>
            </div>
          </CardHeader>
          <CardContent className="space-y-2">
            <p className="text-xs text-muted-foreground" data-testid="fold-run-note">
              {foldDone && foldState !== "failed"
                ? t("models.fold_done_note")
                : foldState === "failed"
                  ? (foldStatus.data?.errorMessage || t("models.fold_failed_note"))
                  : t("models.fold_running_note")}
            </p>
            <Button size="sm" variant="outline" className="h-7 text-xs" data-testid="fold-run-open"
              onClick={() => openRunManager()}>
              {t("models.fold_open_run")}
            </Button>
          </CardContent>
        </Card>
      )}

      {/* Result */}
      {!isStructure && runId && (
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
