import { originLabel } from "./model-origin"
/**
 * ModelObject — a model presented like a dataset: identity, evidence, lineage,
 * consumers (blast radius), interface, versions. Never a leaderboard, never a
 * loss curve.
 *
 * Data arrives via the `detail` prop (already fetched by the parent, or the
 * companion `ModelObjectLoader` which fetches by id). The evidence gate is the
 * measured · threshold · verdict triple from the WS1 contract; the WS1 thin
 * layer reports `not_evaluated` when there is no measured gate, which is shown
 * honestly rather than as a fabricated pass.
 */

import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs"
import { Skeleton } from "@/components/ui/skeleton"
import { ChevronLeft, ShieldCheck, GitBranch, Boxes, Plug, History } from "lucide-react"
import { useModel } from "./models-api"
import type { ModelDetail, ModelGate } from "./types"
import { tOr } from "@/lib/i18n"
import { HintTabsTrigger } from "@/components/ui/hint-tip"

// ── verdict → colour ─────────────────────────────────────────────────────────
function verdictColor(verdict: string): string {
  // Design tokens (global --bm-* oklch, dark-adaptive) instead of fixed Tailwind hex.
  if (verdict === "pass") return "var(--bm-ok)"
  if (verdict === "fail") return "var(--bm-err)"
  return "var(--bm-text-dim)" // not_evaluated / unknown
}

function GateVerdict({ verdict }: { verdict: string }) {
  return (
    <Badge
      variant="outline"
      className="text-fs-xs gap-1"
      style={{ color: verdictColor(verdict) }}
      data-testid="model-gate-verdict"
    >
      <span
        className="inline-block h-1.5 w-1.5 rounded-full"
        style={{ background: verdictColor(verdict) }}
      />
      {verdict}
    </Badge>
  )
}

function fmt(v: string | number | null): string {
  return v === null || v === undefined ? "—" : String(v)
}

/**
 * The interface `signature` line (e.g. `scored(smiles) -> list[float]`) is a
 * call-shape descriptor, not a measured number. The WS1 thin layer exposes only
 * `interface.kind`; a richer detail may carry an optional `signature`. When the
 * backend does not supply one we derive an honest generic shape from the kind —
 * never a fabricated per-model signature.
 */
function ifaceSignature(iface: ModelDetail["interface"]): string {
  const sig = (iface as { signature?: string | null }).signature
  if (sig) return sig
  switch (iface.kind) {
    case "python":
      return "call(inputs) -> result"
    case "container":
      return "run(inputs) -> result"
    case "rest":
      return "POST /infer {inputs} -> result"
    default:
      return "call(inputs) -> result"
  }
}

interface ModelObjectProps {
  detail: ModelDetail
  modelId: string
  onBack?: () => void
  className?: string
  /** Open the lineage dataset version object. */
  onOpenData?: (datasetVersion: string) => void
  /** Open the lineage training-run object. */
  onOpenRun?: (trainingRunId: string) => void
  /** Open another version / model object (prior version, consumer, etc.). */
  onOpenModel?: (ref: string) => void
  /** Open the surface that consumes this model (a run's gate, a score column, a loop). */
  onOpenConsumer?: (consumer: string) => void
  /** Compare a version against the current one on the same held-out set. */
  onCompareVersion?: (version: string) => void
  /** Call this model from a workflow gate, a score column, or an optimisation loop. */
  onUseInRun?: (modelId: string) => void
  /** Train a new version; the current one stays callable until consumers move. */
  onSupersede?: (modelId: string) => void
}

export function ModelObject({
  detail,
  modelId,
  onBack,
  className,
  onOpenData,
  onOpenRun,
  onOpenModel,
  onOpenConsumer,
  onCompareVersion,
  onUseInRun,
  onSupersede,
}: ModelObjectProps) {
  const { identity, evidence, lineage, consumers, versions } = detail
  const gate: ModelGate = evidence.gate
  const currentVersion = identity.version

  return (
    <Card className={className} data-testid="model-object">
      <CardHeader className="pb-2 space-y-2">
        <div className="flex items-center gap-2 text-xs text-muted-foreground">
          {onBack && (
            <button
              type="button"
              className="inline-flex items-center gap-1 hover:text-foreground"
              onClick={onBack}
              data-testid="model-object-back"
            >
              <ChevronLeft className="h-3 w-3" />
              Models
            </button>
          )}
          <span>/</span>
          <span>Registry</span>
          <span>/</span>
          <span className="font-mono" data-testid="model-object-id">{modelId}</span>
        </div>
        <div className="flex items-center gap-2 flex-wrap">
          <CardTitle className="text-base font-mono" data-testid="model-object-name">
            {identity.name} <span className="text-muted-foreground">{identity.version}</span>
          </CardTitle>
          <Badge variant="outline" className="text-fs-xs">{identity.family}</Badge>
          {identity.confidenceBand && (
            <Badge variant="outline" className="text-fs-xs">{identity.confidenceBand} confidence</Badge>
          )}
          <div className="ml-auto flex items-center gap-2">
            <span className="text-fs-xs text-muted-foreground">{originLabel(identity.origin)}</span>
            {/* Only render an action when its handler is wired — otherwise the
                button is an inert no-op in the live /models route. Supersede = make the
                next VERSION, which only applies to a model you own (origin 'custom'); a
                hosted BioNeMo model isn't yours to version. */}
            {onSupersede && identity.origin === "custom" && (
            <Button
              variant="outline"
              size="sm"
              className="h-6 text-fs-xs px-2"
              onClick={() => onSupersede(modelId)}
              data-testid="model-object-supersede"
            >
              Supersede
            </Button>
            )}
            {onUseInRun && (
            <Button
              size="sm"
              className="h-6 text-fs-xs px-2"
              onClick={() => onUseInRun(modelId)}
              data-testid="model-object-use-in-run"
            >
              Use in a run
            </Button>
            )}
          </div>
        </div>
      </CardHeader>

      <CardContent>
        <Tabs defaultValue="evidence">
          <TabsList className="mb-3 flex-wrap h-auto">
            <HintTabsTrigger hint={tOr('hint.model_obj.evidence', '')} value="evidence" className="text-xs" data-testid="model-tab-evidence">
              <ShieldCheck className="h-3 w-3 mr-1" />{tOr('model_obj.tab.evidence', 'Evidence')}
            </HintTabsTrigger>
            <HintTabsTrigger hint={tOr('hint.model_obj.lineage', '')} value="lineage" className="text-xs" data-testid="model-tab-lineage">
              <GitBranch className="h-3 w-3 mr-1" />{tOr('model_obj.tab.lineage', 'Built from')}
            </HintTabsTrigger>
            <HintTabsTrigger hint={tOr('hint.model_obj.used', '')} value="used" className="text-xs" data-testid="model-tab-used">
              <Boxes className="h-3 w-3 mr-1" />{tOr('model_obj.tab.used', 'Used by')}
            </HintTabsTrigger>
            <HintTabsTrigger hint={tOr('hint.model_obj.iface', '')} value="iface" className="text-xs" data-testid="model-tab-iface">
              <Plug className="h-3 w-3 mr-1" />{tOr('model_obj.tab.iface', 'Interface')}
            </HintTabsTrigger>
            <HintTabsTrigger hint={tOr('hint.model_obj.versions', '')} value="versions" className="text-xs" data-testid="model-tab-versions">
              <History className="h-3 w-3 mr-1" />{tOr('model_obj.tab.versions', 'Versions')}
            </HintTabsTrigger>
          </TabsList>

          {/* ── Evidence: the measured · threshold · verdict gate ── */}
          <TabsContent value="evidence" className="space-y-2" data-testid="model-evidence">
            <div className="rounded border text-xs" data-testid="model-gate-row">
              <div className="grid grid-cols-4 gap-2 bg-muted px-2 py-1 font-semibold">
                <span>Held-out gate</span>
                <span>Measured</span>
                <span>Threshold</span>
                <span>Verdict</span>
              </div>
              <div className="grid grid-cols-4 gap-2 px-2 py-1 items-center">
                <span className="text-muted-foreground">quality gate</span>
                <span className="font-mono" data-testid="model-gate-measured">{fmt(gate.measured)}</span>
                <span className="text-muted-foreground" data-testid="model-gate-threshold">{fmt(gate.threshold)}</span>
                <GateVerdict verdict={gate.verdict} />
              </div>
            </div>
            {evidence.calibration != null && (
              <p className="text-fs-xs">
                Calibration error: <span className="font-mono">{fmt(evidence.calibration)}</span>
              </p>
            )}
            {evidence.evalSetId && (
              <p className="text-fs-xs text-muted-foreground">
                Held-out set: <span className="font-mono">{evidence.evalSetId}</span>
              </p>
            )}
            <p className="text-fs-xs text-muted-foreground">
              A floor, not a ranking. Clearing it by more does not make a model better, and there is
              no leaderboard to climb. Outside its applicability region, a prediction is reported with
              low confidence and does not satisfy a gate.
            </p>
          </TabsContent>

          {/* ── Lineage: where it came from — objects, not strings ── */}
          <TabsContent value="lineage" className="space-y-1 text-xs" data-testid="model-lineage">
            <div className="grid grid-cols-[8rem_1fr] gap-1 py-1 border-b">
              <span className="text-muted-foreground">Dataset</span>
              {lineage.datasetVersion && onOpenData ? (
                <button
                  type="button"
                  className="font-mono text-left text-primary hover:underline"
                  onClick={() => onOpenData(lineage.datasetVersion as string)}
                  data-testid="lineage-dataset-link"
                >
                  {lineage.datasetVersion}
                </button>
              ) : (
                <span className="font-mono">{fmt(lineage.datasetVersion)}</span>
              )}
            </div>
            <div className="grid grid-cols-[8rem_1fr] gap-1 py-1 border-b">
              <span className="text-muted-foreground">Training run</span>
              {lineage.trainingRunId && onOpenRun ? (
                <button
                  type="button"
                  className="font-mono text-left text-primary hover:underline"
                  onClick={() => onOpenRun(lineage.trainingRunId as string)}
                  data-testid="lineage-run-link"
                >
                  {lineage.trainingRunId}
                </button>
              ) : (
                <span className="font-mono">{fmt(lineage.trainingRunId)}</span>
              )}
            </div>
            <div className="grid grid-cols-[8rem_1fr] gap-1 py-1">
              <span className="text-muted-foreground">Prior versions</span>
              {lineage.priorVersions.length ? (
                <span className="font-mono flex flex-wrap gap-x-1 gap-y-0.5">
                  {lineage.priorVersions.map((pv, i) => (
                    <span key={pv} className="flex items-center gap-1">
                      {i > 0 && <span className="text-muted-foreground">·</span>}
                      {onOpenModel ? (
                        <button
                          type="button"
                          className="text-primary hover:underline"
                          onClick={() => onOpenModel(pv)}
                          data-testid={`lineage-prior-${pv}`}
                        >
                          {pv}
                        </button>
                      ) : (
                        <span>{pv}</span>
                      )}
                    </span>
                  ))}
                </span>
              ) : (
                <span className="font-mono">—</span>
              )}
            </div>
            <p className="text-fs-xs text-muted-foreground pt-1">
              Same lineage discipline as a dataset: the training run and the dataset version are
              objects, not strings in a description.
            </p>
          </TabsContent>

          {/* ── Used by: the blast radius, rendered kind · where · how ── */}
          <TabsContent value="used" className="space-y-1" data-testid="model-used">
            {consumers.length ? (
              consumers.map((c) => {
                // The WS1 layer gives a plain string; where it encodes a
                // "kind:where·how" shape we surface it, else the string is the
                // "where" and the kind is a generic "consumer". No value invented.
                const [head, ...howParts] = c.split("·")
                const how = howParts.join("·").trim()
                const kindMatch = head.match(/^([a-z ]+):(.+)$/i)
                const kind = kindMatch ? kindMatch[1].trim() : "consumer"
                const where = kindMatch ? kindMatch[2].trim() : head.trim()
                return (
                  <div
                    key={c}
                    className="flex items-center gap-2 rounded border px-2 py-1 text-xs"
                    data-testid={`model-consumer-${c}`}
                  >
                    <Badge variant="outline" className="text-fs-xs shrink-0">{kind}</Badge>
                    <span className="flex flex-col min-w-0">
                      <span className="font-mono truncate">{where}</span>
                      {how && <span className="text-fs-xs text-muted-foreground truncate">{how}</span>}
                    </span>
                    {onOpenConsumer && (
                    <button
                      type="button"
                      className="ml-auto shrink-0 text-primary hover:underline"
                      onClick={() => onOpenConsumer(c)}
                      data-testid={`model-consumer-open-${c}`}
                    >
                      open →
                    </button>
                    )}
                  </div>
                )
              })
            ) : (
              <p className="text-fs-xs text-muted-foreground" data-testid="model-no-consumers">
                No consumers yet — nothing in the account calls this model.
              </p>
            )}
            <p className="text-fs-xs text-muted-foreground pt-1">
              Because consumers are listed, superseding is a decision with a visible cost rather than
              a silent change under a running campaign.
            </p>
          </TabsContent>

          {/* ── Interface: how it is called, with the call signature ── */}
          <TabsContent value="iface" className="space-y-2 text-xs" data-testid="model-iface">
            <div className="flex items-center gap-2 flex-wrap">
              <span className="text-muted-foreground">Called as</span>
              <Badge variant="outline" className="text-fs-xs capitalize" data-testid="model-iface-kind">
                {detail.interface.kind}
              </Badge>
              <span className="font-mono text-fs-xs" data-testid="model-iface-signature">
                {ifaceSignature(detail.interface)}
              </span>
            </div>
            <p className="text-fs-xs text-muted-foreground">
              The pipeline calls the registry, not the implementation — so a lab's own model
              (python function · container · REST endpoint) drops in without rewriting a workflow.
            </p>
          </TabsContent>

          {/* ── Versions — with a compare affordance ── */}
          <TabsContent value="versions" className="space-y-1" data-testid="model-versions">
            {versions.map((v) => {
              const isCurrent = v.v === currentVersion
              return (
                <div
                  key={v.v}
                  className={
                    "flex items-center gap-2 rounded border px-2 py-1 text-xs" +
                    (isCurrent ? " border-primary/50 bg-muted/40" : "")
                  }
                  data-testid={`model-version-${v.v}`}
                >
                  <span className="font-mono font-semibold">{v.v}</span>
                  <GateVerdict verdict={v.verdict} />
                  {isCurrent && (
                    <Badge variant="outline" className="text-fs-xs">current</Badge>
                  )}
                  {!isCurrent && onCompareVersion && (
                    <button
                      type="button"
                      className="ml-auto text-primary hover:underline"
                      onClick={() => onCompareVersion(v.v)}
                      data-testid={`model-version-compare-${v.v}`}
                    >
                      compare
                    </button>
                  )}
                </div>
              )
            })}
            <p className="text-fs-xs text-muted-foreground pt-1">
              Superseding never deletes. A completed run keeps the exact version it called, so an old
              report stays reproducible. Compare weighs a version against the current one on the same
              held-out set.
            </p>
          </TabsContent>
        </Tabs>
      </CardContent>
    </Card>
  )
}

// ── Loader: fetch by id, then render ─────────────────────────────────────────
interface ModelObjectLoaderProps {
  modelId: string
  onBack?: () => void
  className?: string
  onOpenData?: (datasetVersion: string) => void
  onOpenRun?: (trainingRunId: string) => void
  onOpenModel?: (ref: string) => void
  onOpenConsumer?: (consumer: string) => void
  onCompareVersion?: (version: string) => void
  onUseInRun?: (modelId: string) => void
  onSupersede?: (modelId: string) => void
}

export function ModelObjectLoader({
  modelId,
  onBack,
  className,
  ...actions
}: ModelObjectLoaderProps) {
  const { data, isLoading, isError, error } = useModel(modelId)

  if (isLoading) {
    return (
      <Card className={className} data-testid="model-object-loading">
        <CardContent className="py-4 space-y-2">
          {onBack && <Button variant="outline" size="sm" className="h-7 text-xs" onClick={onBack}>{tOr('actions.back', 'Back')}</Button>}
          <Skeleton className="h-5 w-48" />
          <Skeleton className="h-4 w-full" />
          <Skeleton className="h-4 w-2/3" />
        </CardContent>
      </Card>
    )
  }
  if (isError || !data) {
    return (
      <Card className={className} data-testid="model-object-error">
        <CardContent className="py-4">
          <p className="text-xs text-destructive">
            Could not load model {modelId}
            {error instanceof Error ? `: ${error.message}` : ""}.
          </p>
          {onBack && (
            <Button variant="outline" size="sm" className="mt-2 h-7 text-xs" onClick={onBack}>
              Back
            </Button>
          )}
        </CardContent>
      </Card>
    )
  }
  return (
    <ModelObject
      detail={data}
      modelId={modelId}
      onBack={onBack}
      className={className}
      {...actions}
    />
  )
}
