/**
 * ModelsPanel — the 5-track Models surface:
 *
 *   Train · Adapt · Optimise · Run a pre-trained model · Registry
 *
 * A model is presented like a dataset (identity · evidence · lineage · used-by
 * · interface · versions), never a leaderboard. The Registry track lists the
 * live account catalog (GET /api/models) and opens a ModelObject on click. The
 * "Run a pre-trained model" track submits inference and renders the result with
 * the wave-1 viewers by evidence class.
 *
 * Train / Adapt / Optimise are project-scoped surfaces with no WS1 read
 * endpoint in this wave; they render descriptive track content (no fabricated
 * data). Any live data they receive arrives via props.
 */

import { useState } from "react"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs"
import { Skeleton } from "@/components/ui/skeleton"
import { GraduationCap, Wand2, Repeat, Rocket, Library, ChevronRight } from "lucide-react"
import { useModels } from "./models-api"
import { ModelObjectLoader } from "./model-object"
import { RunPretrained } from "./run-pretrained"
import type { ModelSummary } from "./types"

export const MODELS_TRACKS = [
  "Train",
  "Adapt",
  "Optimise",
  "Run a pre-trained model",
  "Registry",
] as const

// ── Registry track ───────────────────────────────────────────────────────────
function RegistryTrack({ onOpenModel }: { onOpenModel: (id: string) => void }) {
  const { data: models, isLoading, isError } = useModels()

  if (isLoading) {
    return (
      <div className="space-y-2" data-testid="registry-loading">
        <Skeleton className="h-8 w-full" />
        <Skeleton className="h-8 w-full" />
        <Skeleton className="h-8 w-full" />
      </div>
    )
  }
  if (isError) {
    return (
      <p className="text-xs text-destructive" data-testid="registry-error">
        Could not load the model registry.
      </p>
    )
  }
  const rows: ModelSummary[] = models ?? []
  if (!rows.length) {
    return (
      <p className="text-xs text-muted-foreground" data-testid="registry-empty">
        No models registered in this account yet. A model trained in one project — or a pre-trained
        model you run — becomes a callable object listed here.
      </p>
    )
  }
  return (
    <div className="space-y-2" data-testid="registry-track">
      <p className="text-[10px] text-muted-foreground">
        Account-level · a model trained in one project is callable from any. A row opens the model
        object — evidence, lineage, consumers, interface, versions.
      </p>
      <div className="rounded border text-xs" data-testid="registry-table">
        <div className="grid grid-cols-[1.4fr_1fr_0.8fr_0.8fr_auto] gap-2 bg-muted px-2 py-1 font-semibold">
          <span>Model</span>
          <span>Family</span>
          <span>Origin</span>
          <span>Used by</span>
          <span />
        </div>
        {rows.map((m) => (
          <button
            key={m.id}
            type="button"
            className="grid grid-cols-[1.4fr_1fr_0.8fr_0.8fr_auto] gap-2 px-2 py-1.5 items-center w-full text-left border-t hover:bg-muted/40"
            data-testid={`registry-row-${m.id}`}
            onClick={() => onOpenModel(m.id)}
          >
            <span className="font-mono font-semibold truncate">
              {m.name} <span className="text-muted-foreground">{m.version}</span>
            </span>
            <span className="text-muted-foreground truncate">{m.family}</span>
            <span className="text-muted-foreground truncate">{m.origin}</span>
            <span className="text-muted-foreground">{m.usedByCount}</span>
            <ChevronRight className="h-3.5 w-3.5 text-muted-foreground" />
          </button>
        ))}
      </div>
    </div>
  )
}

// ── Descriptive track (Train / Adapt / Optimise) ─────────────────────────────
function DescriptiveTrack({
  title,
  lead,
  bullets,
  testid,
}: {
  title: string
  lead: string
  bullets: string[]
  testid: string
}) {
  return (
    <Card data-testid={testid}>
      <CardHeader className="pb-2">
        <CardTitle className="text-sm">{title}</CardTitle>
      </CardHeader>
      <CardContent className="space-y-2">
        <p className="text-xs text-muted-foreground">{lead}</p>
        <ul className="space-y-1">
          {bullets.map((b) => (
            <li key={b} className="text-[11px] flex items-start gap-1.5">
              <span className="mt-1 inline-block h-1 w-1 rounded-full bg-muted-foreground shrink-0" />
              <span>{b}</span>
            </li>
          ))}
        </ul>
      </CardContent>
    </Card>
  )
}

// ── Panel ────────────────────────────────────────────────────────────────────
export interface ModelsPanelProps {
  /** Project name shown in the crumb. */
  project?: string
  /** Controlled selected track index (0–4). */
  tab?: number
  onTabChange?: (tab: number) => void
  className?: string
}

const TRACK_ICONS = [GraduationCap, Wand2, Repeat, Rocket, Library]

export function ModelsPanel({ project = "Project", tab, onTabChange, className }: ModelsPanelProps) {
  const [internalTab, setInternalTab] = useState(0)
  const activeTab = tab ?? internalTab
  const setTab = (i: number) => {
    setInternalTab(i)
    onTabChange?.(i)
  }

  const { data: models } = useModels()
  const [openModelId, setOpenModelId] = useState<string | null>(null)

  // A model object takes over the whole surface, like the prototype.
  if (openModelId) {
    return (
      <div className={className} data-testid="models-panel">
        <ModelObjectLoader modelId={openModelId} onBack={() => setOpenModelId(null)} />
      </div>
    )
  }

  return (
    <div className={className} data-testid="models-panel">
      <Card>
        <CardHeader className="pb-2">
          <div className="flex items-center gap-2 text-xs text-muted-foreground">
            <span>{project}</span>
            <span>/</span>
            <span>Models</span>
          </div>
          <div className="flex items-center gap-2 flex-wrap">
            <CardTitle className="text-base">Models</CardTitle>
            <Badge variant="outline" className="text-[10px]" data-testid="models-count">
              {(models?.length ?? 0)} registered
            </Badge>
          </div>
        </CardHeader>
        <CardContent>
          {/* Uncontrolled Radix Tabs (defaultValue) so in-panel switching works
              without a controlled value; the `key` remounts when a caller drives
              the `tab` prop, and onValueChange still notifies onTabChange. */}
          <Tabs
            key={tab ?? "uncontrolled"}
            defaultValue={String(activeTab)}
            onValueChange={(v) => setTab(Number(v))}
          >
            <TabsList className="mb-3 flex-wrap h-auto" data-testid="models-tabs">
              {MODELS_TRACKS.map((t, i) => {
                const Icon = TRACK_ICONS[i]
                return (
                  <TabsTrigger
                    key={t}
                    value={String(i)}
                    className="text-xs"
                    data-testid={`models-track-${i}`}
                  >
                    <Icon className="h-3 w-3 mr-1" />
                    {t}
                  </TabsTrigger>
                )
              })}
            </TabsList>

            <TabsContent value="0">
              <DescriptiveTrack
                testid="track-train"
                title="Train"
                lead="Training reuses the run language — same compute, same gates, same tracking as a workflow run. The only two new decisions are which dataset, and whether to register."
                bullets={[
                  "Dataset → Train → Quality gate (held-out floor, not a leaderboard) → Tracking → Register.",
                  "A passing model is offered for registration, never registered silently.",
                  "Model families: language, tabular AutoML, diffusion, molecular property.",
                ]}
              />
            </TabsContent>

            <TabsContent value="1">
              <DescriptiveTrack
                testid="track-adapt"
                title="Adapt"
                lead="Adaptation is a list of switchable things, not an opaque model change. When you correct BioMate's output, the before→after pair is queued; every learned rule is visible and can be switched off."
                bullets={[
                  "Cheapest first: a prompt rule is preferred over a few-shot index, and an index over a trained adapter.",
                  "The level in use is visible, because it changes what \"forget this\" means.",
                  "Re-training on your edits runs as a tracked training run with its own quality gate.",
                ]}
              />
            </TabsContent>

            <TabsContent value="2">
              <DescriptiveTrack
                testid="track-optimise"
                title="Optimise"
                lead="The closed loop, as rounds: design · make · test · analyse. A surrogate proposes, the bench measures, and a refit runs as a tracked training run — nothing about the loop is exempt from the evidence rules."
                bullets={[
                  "Every proposal is accounted for; a candidate that produced no number still returns a reason.",
                  "Censored values stay censored (IC50 > 30 µM is fitted as an inequality, never as 30).",
                  "A rejected proposal stays on the list with its reason.",
                ]}
              />
            </TabsContent>

            <TabsContent value="3">
              <RunPretrained onOpenModel={setOpenModelId} />
            </TabsContent>

            <TabsContent value="4">
              <RegistryTrack onOpenModel={setOpenModelId} />
            </TabsContent>
          </Tabs>
        </CardContent>
      </Card>
    </div>
  )
}
