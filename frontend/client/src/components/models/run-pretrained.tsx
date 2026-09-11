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
  label: string
  goal: string
  /** default catalog id if none matches the family filter. */
  defaultModelId: string
  /** which catalog family strings belong to this domain. */
  families: string[]
  inputKey: "sequence" | "smiles"
  inputLabel: string
  placeholder: string
  examples: string[]
  produces: string
}

const DOMAINS: Domain[] = [
  {
    id: "structure",
    label: "Structure",
    goal: "Predict a protein structure with per-residue confidence and pairwise error.",
    defaultModelId: "bionemo:boltz2",
    families: ["structure"],
    inputKey: "sequence",
    inputLabel: "Protein sequence (one-letter)",
    placeholder: "MKTAYIAKQR...",
    examples: ["Fold this sequence and show me which loops to trust"],
    produces: "a 3D structure, pLDDT and PAE",
  },
  {
    id: "genomic",
    label: "Genomic",
    goal: "Score / generate over a genomic locus and flag the actionable intervals.",
    defaultModelId: "bionemo:evo2_7b",
    families: ["genomic"],
    inputKey: "sequence",
    inputLabel: "Nucleotide sequence",
    placeholder: "ACGTACGTACGT...",
    examples: ["Score this locus and flag the intervals worth reviewing"],
    produces: "score tracks and flagged intervals",
  },
  {
    id: "chemical",
    label: "Chemical",
    goal: "Score a set of candidate molecules for a property, ranked with confidence.",
    defaultModelId: "",
    families: ["python", "docker", "rest", "custom", "chemical"],
    inputKey: "smiles",
    inputLabel: "SMILES (one per line)",
    placeholder: "CC1=CC(=NO1)C(=O)Nc1ccc(F)cc1\nCOc1ccc(cc1)...",
    examples: ["Rank these candidates and tell me which are out-of-domain"],
    produces: "ranked hits by score, confidence and verdict",
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
          <CardTitle className="text-sm">Run a model</CardTitle>
          <p className="text-[10px] text-muted-foreground">
            A pre-trained, integrated open-source model · nothing of yours is trained. You supply an input and get
            an inference — so the questions are what it can speak to and how much of its answer to
            trust, not what it learned.
          </p>
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
                {d.label}
              </Button>
            ))}
          </div>

          <div className="space-y-1">
            <p className="text-xs font-semibold">{domain.goal}</p>
            <div className="flex items-center gap-2 flex-wrap text-[10px]">
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
                  no {domain.id} model registered
                </span>
              )}
              <span className="text-muted-foreground">produces {domain.produces}</span>
            </div>
            {domain.examples.map((e) => (
              <button
                key={e}
                type="button"
                className="flex items-center gap-1 text-[11px] text-muted-foreground hover:text-foreground"
                onClick={() => setInputText(domain.placeholder.split("\n")[0])}
                data-testid="run-pretrained-example"
              >
                <Sparkles className="h-3 w-3" />
                <span className="italic">"{e}"</span>
              </button>
            ))}
          </div>

          {/* Input */}
          <div className="space-y-1">
            <label className="text-[10px] uppercase tracking-wide text-muted-foreground">
              {domain.inputLabel}
            </label>
            <Textarea
              value={inputText}
              onChange={(e) => setInputText(e.target.value)}
              placeholder={domain.placeholder}
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
                  Running…
                </>
              ) : (
                <>
                  <Play className="h-3 w-3 mr-1" />
                  Run inference
                </>
              )}
            </Button>
            {infer.isError && (
              <span className="text-[11px] text-destructive" data-testid="run-pretrained-error">
                {infer.error instanceof Error ? infer.error.message : "Inference failed"}
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
              <CardTitle className="text-sm">Result</CardTitle>
              {result?.status === "running" && (
                <Badge variant="outline" className="text-[10px] gap-1" data-testid="result-status-running">
                  <Loader2 className="h-3 w-3 animate-spin" />
                  running
                </Badge>
              )}
              {result?.status === "completed" && (
                <Badge variant="outline" className="text-[10px]" data-testid="result-status-completed">
                  completed
                </Badge>
              )}
              {result?.status === "failed" && (
                <Badge variant="destructive" className="text-[10px]" data-testid="result-status-failed">
                  failed
                </Badge>
              )}
              <span className="text-[10px] font-mono text-muted-foreground ml-auto">{modelId}</span>
            </div>
          </CardHeader>
          <CardContent>
            {result?.status === "failed" && (
              <p className="text-xs text-destructive" data-testid="result-error">
                {result.error ?? "Inference did not complete."}
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
                Inference is running — the result renders here when it completes.
              </p>
            )}
          </CardContent>
        </Card>
      )}
    </div>
  )
}
