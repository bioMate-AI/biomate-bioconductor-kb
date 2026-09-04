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

// ── verdict → colour ─────────────────────────────────────────────────────────
function verdictColor(verdict: string): string {
  if (verdict === "pass") return "#22c55e"
  if (verdict === "fail") return "#ef4444"
  return "#94a3b8" // not_evaluated / unknown
}

function GateVerdict({ verdict }: { verdict: string }) {
  return (
    <Badge
      variant="outline"
      className="text-[10px] gap-1"
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

interface ModelObjectProps {
  detail: ModelDetail
  modelId: string
  onBack?: () => void
  className?: string
}

export function ModelObject({ detail, modelId, onBack, className }: ModelObjectProps) {
  const { identity, evidence, lineage, consumers, versions } = detail
  const gate: ModelGate = evidence.gate

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
          <Badge variant="outline" className="text-[10px]">{identity.family}</Badge>
          {identity.confidenceBand && (
            <Badge variant="outline" className="text-[10px]">{identity.confidenceBand} confidence</Badge>
          )}
          <span className="text-[10px] text-muted-foreground ml-auto">{identity.origin}</span>
        </div>
      </CardHeader>

      <CardContent>
        <Tabs defaultValue="evidence">
          <TabsList className="mb-3 flex-wrap h-auto">
            <TabsTrigger value="evidence" className="text-xs" data-testid="model-tab-evidence">
              <ShieldCheck className="h-3 w-3 mr-1" />Evidence
            </TabsTrigger>
            <TabsTrigger value="lineage" className="text-xs" data-testid="model-tab-lineage">
              <GitBranch className="h-3 w-3 mr-1" />Lineage
            </TabsTrigger>
            <TabsTrigger value="used" className="text-xs" data-testid="model-tab-used">
              <Boxes className="h-3 w-3 mr-1" />Used by
            </TabsTrigger>
            <TabsTrigger value="iface" className="text-xs" data-testid="model-tab-iface">
              <Plug className="h-3 w-3 mr-1" />Interface
            </TabsTrigger>
            <TabsTrigger value="versions" className="text-xs" data-testid="model-tab-versions">
              <History className="h-3 w-3 mr-1" />Versions
            </TabsTrigger>
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
              <p className="text-[11px]">
                Calibration error: <span className="font-mono">{fmt(evidence.calibration)}</span>
              </p>
            )}
            {evidence.evalSetId && (
              <p className="text-[11px] text-muted-foreground">
                Held-out set: <span className="font-mono">{evidence.evalSetId}</span>
              </p>
            )}
            <p className="text-[10px] text-muted-foreground">
              A floor, not a ranking. Clearing it by more does not make a model better, and there is
              no leaderboard to climb. Outside its applicability region, a prediction is reported with
              low confidence and does not satisfy a gate.
            </p>
          </TabsContent>

          {/* ── Lineage: where it came from ── */}
          <TabsContent value="lineage" className="space-y-1 text-xs" data-testid="model-lineage">
            <div className="grid grid-cols-[8rem_1fr] gap-1 py-1 border-b">
              <span className="text-muted-foreground">Dataset</span>
              <span className="font-mono">{fmt(lineage.datasetVersion)}</span>
            </div>
            <div className="grid grid-cols-[8rem_1fr] gap-1 py-1 border-b">
              <span className="text-muted-foreground">Training run</span>
              <span className="font-mono">{fmt(lineage.trainingRunId)}</span>
            </div>
            <div className="grid grid-cols-[8rem_1fr] gap-1 py-1">
              <span className="text-muted-foreground">Prior versions</span>
              <span className="font-mono">
                {lineage.priorVersions.length ? lineage.priorVersions.join(" · ") : "—"}
              </span>
            </div>
            <p className="text-[10px] text-muted-foreground pt-1">
              Same lineage discipline as a dataset: the training run and the dataset version are
              objects, not strings in a description.
            </p>
          </TabsContent>

          {/* ── Used by: the blast radius ── */}
          <TabsContent value="used" className="space-y-1" data-testid="model-used">
            {consumers.length ? (
              consumers.map((c) => (
                <div
                  key={c}
                  className="flex items-center gap-2 rounded border px-2 py-1 text-xs"
                  data-testid={`model-consumer-${c}`}
                >
                  <Badge variant="outline" className="text-[10px]">consumer</Badge>
                  <span className="font-mono truncate">{c}</span>
                </div>
              ))
            ) : (
              <p className="text-[11px] text-muted-foreground" data-testid="model-no-consumers">
                No consumers yet — nothing in the account calls this model.
              </p>
            )}
            <p className="text-[10px] text-muted-foreground pt-1">
              Because consumers are listed, superseding is a decision with a visible cost rather than
              a silent change under a running campaign.
            </p>
          </TabsContent>

          {/* ── Interface: how it is called ── */}
          <TabsContent value="iface" className="space-y-2 text-xs" data-testid="model-iface">
            <div className="flex items-center gap-2 flex-wrap">
              <span className="text-muted-foreground">Called as</span>
              <Badge variant="outline" className="text-[10px] capitalize" data-testid="model-iface-kind">
                {detail.interface.kind}
              </Badge>
            </div>
            <p className="text-[10px] text-muted-foreground">
              The pipeline calls the registry, not the implementation — so a lab's own model
              (python function · container · REST endpoint) drops in without rewriting a workflow.
            </p>
          </TabsContent>

          {/* ── Versions ── */}
          <TabsContent value="versions" className="space-y-1" data-testid="model-versions">
            {versions.map((v) => (
              <div
                key={v.v}
                className="flex items-center gap-2 rounded border px-2 py-1 text-xs"
                data-testid={`model-version-${v.v}`}
              >
                <span className="font-mono font-semibold">{v.v}</span>
                <GateVerdict verdict={v.verdict} />
              </div>
            ))}
            <p className="text-[10px] text-muted-foreground pt-1">
              Superseding never deletes. A completed run keeps the exact version it called, so an old
              report stays reproducible.
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
}

export function ModelObjectLoader({ modelId, onBack, className }: ModelObjectLoaderProps) {
  const { data, isLoading, isError, error } = useModel(modelId)

  if (isLoading) {
    return (
      <Card className={className} data-testid="model-object-loading">
        <CardContent className="py-4 space-y-2">
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
  return <ModelObject detail={data} modelId={modelId} onBack={onBack} className={className} />
}
