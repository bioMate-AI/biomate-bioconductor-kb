/**
 * ModelCase — the Spec 10 worked-case page. One spine for all four Models
 * tracks (Run a model / Train / Tune on our data / Propose & test in rounds),
 * so a pre-trained inference and a closed loop read alike:
 *
 *   header + model chip
 *   → WHAT THIS WAS GIVEN (+ stage chips)
 *   → WHAT CAME BACK (headline + labelled blocks, one always the honest one)
 *   → BOUNDARY (what the result is NOT evidence for)
 *   → MEASURED AGAINST A FLOOR (metric · value · threshold · verdict)
 *   → WHAT IT LEFT BEHIND (each artefact is a file)
 *   → WHAT TO DO NEXT (decisions, never automatic actions)
 *
 * The honesty contract (§10.4): this component renders the SHAPE from props and
 * nothing more. It never fabricates a metric, a verdict, a headline, or a
 * result block. Where a section's data is absent it shows an honest-empty
 * state ("No worked cases yet" / "No result yet …") rather than an invented
 * number. Every value on screen came from the `case_` prop.
 *
 * Route wiring is DEFERRED: there is no obvious honest entry point in App.tsx
 * yet (the Models tracks do not carry a "worked example" click target, and the
 * two registry additions in §10.5 — fold-predict v2.3, molgen v4.1 — are not
 * seeded). This is a self-contained, prop-driven, tested component. When a
 * Models track gains a worked-example affordance and the registry additions
 * land, mount <ModelCase case_={modelCaseFor(id)} /> behind that click.
 */

import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { ChevronLeft, FileText, Download, Boxes } from "lucide-react"
import type {
  ModelCase,
  ModelCaseArtefact,
  ModelCaseFloorRow,
  ModelCaseNextStep,
} from "./types"

// ── verdict → colour (matches model-object.tsx) ──────────────────────────────
function verdictColor(verdict: string): string {
  if (verdict === "pass") return "var(--bm-ok)"
  if (verdict === "fail") return "var(--bm-err)"
  if (verdict === "flag") return "var(--bm-warn)"
  return "var(--bm-text-dim)" // not_evaluated / unknown
}

function VerdictBadge({ verdict }: { verdict: string }) {
  return (
    <Badge
      variant="outline"
      className="text-fs-xs gap-1"
      style={{ color: verdictColor(verdict) }}
      data-testid="model-case-floor-verdict"
    >
      <span
        className="inline-block h-1.5 w-1.5 rounded-full"
        style={{ background: verdictColor(verdict) }}
      />
      {verdict}
    </Badge>
  )
}

// A small labelled section heading in the fixed spine order.
function SectionLabel({ children }: { children: React.ReactNode }) {
  return (
    <div className="text-fs-xs font-semibold uppercase tracking-wide text-muted-foreground">
      {children}
    </div>
  )
}

interface ModelCaseProps {
  /** The worked case to render. Named `case_` — `case` is a reserved word. */
  case_: ModelCase
  className?: string
  onBack?: () => void
  /** Open the model object for the chip (only if the model exists in registry). */
  onOpenModel?: (modelId: string) => void
  /** Open an artefact in Files. */
  onOpenArtefact?: (artefact: ModelCaseArtefact) => void
  /** Open & edit a report artefact. */
  onEditReport?: (artefact: ModelCaseArtefact) => void
  /** Download an artefact. */
  onDownloadArtefact?: (artefact: ModelCaseArtefact) => void
  /** A WHAT TO DO NEXT decision was taken (register / open object / fix upstream). */
  onNextStep?: (step: ModelCaseNextStep) => void
}

export function ModelCase({
  case_,
  className,
  onBack,
  onOpenModel,
  onOpenArtefact,
  onEditReport,
  onDownloadArtefact,
  onNextStep,
}: ModelCaseProps) {
  const c = case_
  const { model } = c
  const canOpenModel = !!model.modelId && !!onOpenModel

  return (
    <Card className={className} data-testid="model-case" data-case-id={c.id}>
      <CardHeader className="pb-2 space-y-2">
        {/* Breadcrumb */}
        <div
          className="flex items-center gap-2 text-xs text-muted-foreground flex-wrap"
          data-testid="model-case-breadcrumb"
        >
          {onBack && (
            <button
              type="button"
              className="inline-flex items-center gap-1 hover:text-foreground"
              onClick={onBack}
              data-testid="model-case-back"
            >
              <ChevronLeft className="h-3 w-3" />
              Back
            </button>
          )}
          {c.breadcrumb.map((crumb, i) => (
            <span key={`${crumb}-${i}`} className="flex items-center gap-2">
              {(i > 0 || onBack) && <span>/</span>}
              <span>{crumb}</span>
            </span>
          ))}
        </div>

        {/* The case question, verbatim */}
        <CardTitle className="text-base leading-snug" data-testid="model-case-question">
          {c.question}
        </CardTitle>

        {/* Model chip + lane / origin */}
        <div className="flex items-center gap-2 flex-wrap">
          {canOpenModel ? (
            <button
              type="button"
              className="font-mono text-sm text-primary hover:underline"
              onClick={() => onOpenModel?.(model.modelId as string)}
              data-testid="model-case-model-chip"
            >
              {model.name} <span className="text-muted-foreground">{model.version}</span>
              {model.qualifier ? (
                <span className="text-muted-foreground"> ({model.qualifier})</span>
              ) : null}
            </button>
          ) : (
            <span className="font-mono text-sm" data-testid="model-case-model-chip">
              {model.name} <span className="text-muted-foreground">{model.version}</span>
              {model.qualifier ? (
                <span className="text-muted-foreground"> ({model.qualifier})</span>
              ) : null}
            </span>
          )}
          {c.origin && (
            <span className="text-fs-xs text-muted-foreground" data-testid="model-case-origin">
              {c.origin}
            </span>
          )}
          {c.lane && (
            <Badge variant="outline" className="text-fs-xs ml-auto" data-testid="model-case-lane">
              {c.lane}
            </Badge>
          )}
        </div>
      </CardHeader>

      <CardContent className="space-y-4">
        {/* ── Track 1: WHAT THIS WAS GIVEN ── */}
        <section data-testid="model-case-track-1" className="space-y-2">
          <SectionLabel>What this was given</SectionLabel>
          {c.given.length ? (
            <div className="rounded border divide-y text-xs" data-testid="model-case-given">
              {c.given.map((row, i) => (
                <div
                  key={`${row.label}-${i}`}
                  className="grid grid-cols-[9rem_1fr] gap-2 px-2 py-1"
                  data-testid={`model-case-given-row-${i}`}
                >
                  <span className="text-muted-foreground">{row.label}</span>
                  <span className="flex items-baseline gap-2 flex-wrap">
                    <span className="font-mono">{row.value}</span>
                    {row.note && (
                      <span className="text-fs-xs italic text-muted-foreground">{row.note}</span>
                    )}
                  </span>
                </div>
              ))}
            </div>
          ) : (
            <p className="text-fs-xs text-muted-foreground" data-testid="model-case-given-empty">
              No inputs recorded yet.
            </p>
          )}

          {/* Stage chips */}
          {c.stages.length > 0 && (
            <div className="flex items-center gap-1.5 flex-wrap" data-testid="model-case-stages">
              {c.stages.map((s, i) => (
                <Badge
                  key={`${s.label}-${i}`}
                  variant="outline"
                  className={
                    "text-fs-xs gap-1 " +
                    (s.status === "waiting" ? "text-muted-foreground opacity-70" : "")
                  }
                  data-testid={`model-case-stage-${i}`}
                  data-status={s.status}
                >
                  <span className="inline-block h-1.5 w-1.5 rounded-full"
                    style={{ background: s.status === "done" ? "var(--bm-ok)" : "var(--bm-border-strong)" }} />
                  {s.label}
                  {s.status === "waiting" && <span className="italic"> · waiting</span>}
                </Badge>
              ))}
            </div>
          )}
        </section>

        {/* ── Track 2: WHAT CAME BACK ── */}
        <section data-testid="model-case-track-2" className="space-y-2">
          <div className="flex items-center gap-2 flex-wrap">
            <SectionLabel>What came back</SectionLabel>
            {c.confidence && (
              <Badge variant="outline" className="text-fs-xs" data-testid="model-case-confidence">
                {c.confidence} confidence
              </Badge>
            )}
            {typeof c.flaggedCount === "number" && c.flaggedCount > 0 && (
              <Badge
                variant="outline"
                className="text-fs-xs"
                style={{ color: verdictColor("flag") }}
                data-testid="model-case-flagged"
              >
                {c.flaggedCount} flagged
              </Badge>
            )}
          </div>

          {c.headline ? (
            <p className="text-sm" data-testid="model-case-headline">{c.headline}</p>
          ) : (
            <p className="text-fs-xs text-muted-foreground" data-testid="model-case-result-empty">
              No result yet — nothing is reported until the evaluation stage finishes.
            </p>
          )}

          {c.resultBlocks.length > 0 && (
            <div className="space-y-1.5" data-testid="model-case-result-blocks">
              {c.resultBlocks.map((b, i) => (
                <div
                  key={`${b.label}-${i}`}
                  className={
                    "rounded border px-2 py-1.5 text-xs " +
                    (b.honest ? "border-amber-400/60 bg-amber-50/40" : "")
                  }
                  data-testid={`model-case-result-block-${i}`}
                  data-honest={b.honest ? "true" : "false"}
                >
                  <div className="text-fs-xs font-semibold uppercase tracking-wide text-muted-foreground">
                    {b.label}
                  </div>
                  <div>{b.body}</div>
                </div>
              ))}
            </div>
          )}

          {/* BOUNDARY — what the result is NOT evidence for */}
          {c.boundary && (
            <div className="rounded border border-dashed px-2 py-1.5 text-xs" data-testid="model-case-boundary">
              <div className="text-fs-xs font-semibold uppercase tracking-wide text-muted-foreground">
                Boundary
              </div>
              <div className="text-muted-foreground">{c.boundary}</div>
            </div>
          )}
        </section>

        {/* ── Track 3: MEASURED AGAINST A FLOOR ── */}
        <section data-testid="model-case-track-3" className="space-y-2">
          <SectionLabel>Measured against a floor</SectionLabel>
          {c.floor.length ? (
            <div className="rounded border text-xs" data-testid="model-case-floor">
              <div className="grid grid-cols-4 gap-2 bg-muted px-2 py-1 font-semibold">
                <span>Metric</span>
                <span>Value</span>
                <span>Threshold</span>
                <span>Verdict</span>
              </div>
              {c.floor.map((row: ModelCaseFloorRow, i) => (
                <div
                  key={`${row.metric}-${i}`}
                  className="grid grid-cols-4 gap-2 px-2 py-1 items-center border-t"
                  data-testid={`model-case-floor-row-${i}`}
                >
                  <span className="text-muted-foreground">{row.metric}</span>
                  <span className="font-mono">{row.value}</span>
                  <span className="text-muted-foreground">{row.threshold}</span>
                  <VerdictBadge verdict={row.verdict} />
                </div>
              ))}
            </div>
          ) : (
            <p className="text-fs-xs text-muted-foreground" data-testid="model-case-floor-empty">
              No floor evaluated yet.
            </p>
          )}
          <p className="text-fs-xs text-muted-foreground">
            A floor, not a ranking. Clearing it by more does not make a model better.
          </p>
        </section>

        {/* ── Track 4: WHAT IT LEFT BEHIND ── */}
        <section data-testid="model-case-track-4" className="space-y-2">
          <div className="flex items-center gap-2">
            <SectionLabel>What it left behind</SectionLabel>
            <span className="text-fs-xs text-muted-foreground">every artefact is a file</span>
          </div>
          {c.artefacts.length ? (
            <div className="rounded border divide-y text-xs" data-testid="model-case-artefacts">
              {c.artefacts.map((a, i) => {
                const isReport = a.kind === "report"
                const Icon = isReport ? FileText : Boxes
                return (
                  <div
                    key={`${a.name}-${i}`}
                    className="flex items-center gap-2 px-2 py-1"
                    data-testid={`model-case-artefact-${i}`}
                  >
                    <Icon className="h-3 w-3 text-muted-foreground shrink-0" />
                    <span className="font-mono truncate">{a.name}</span>
                    <Badge variant="outline" className="text-fs-xs shrink-0">{a.kind}</Badge>
                    <div className="ml-auto flex items-center gap-1 shrink-0">
                      {isReport ? (
                        <>
                          <Button
                            variant="outline"
                            size="sm"
                            className="h-6 text-fs-xs px-2"
                            onClick={() => onEditReport?.(a)}
                            data-testid={`model-case-artefact-edit-${i}`}
                          >
                            Open &amp; edit
                          </Button>
                          <Button
                            variant="ghost"
                            size="sm"
                            className="h-6 w-6 p-0"
                            aria-label="Download"
                            onClick={() => onDownloadArtefact?.(a)}
                            data-testid={`model-case-artefact-download-${i}`}
                          >
                            <Download className="h-3 w-3" />
                          </Button>
                        </>
                      ) : (
                        <Button
                          variant="outline"
                          size="sm"
                          className="h-6 text-fs-xs px-2"
                          onClick={() => onOpenArtefact?.(a)}
                          data-testid={`model-case-artefact-open-${i}`}
                        >
                          Open in Files
                        </Button>
                      )}
                    </div>
                  </div>
                )
              })}
            </div>
          ) : (
            <p className="text-fs-xs text-muted-foreground" data-testid="model-case-artefacts-empty">
              No artefacts yet.
            </p>
          )}
          {c.reportName && (
            <p className="text-fs-xs text-muted-foreground" data-testid="model-case-report-name">
              Report: <span className="font-mono">runs/models/{c.reportName}</span>
            </p>
          )}
        </section>

        {/* ── WHAT TO DO NEXT — decisions, never automatic actions ── */}
        <section data-testid="model-case-next" className="space-y-2">
          <SectionLabel>What to do next</SectionLabel>
          {c.nextSteps.length ? (
            <div className="flex items-center gap-2 flex-wrap">
              {c.nextSteps.map((step, i) => (
                <Button
                  key={`${step.label}-${i}`}
                  variant={step.variant === "primary" ? "default" : "outline"}
                  size="sm"
                  className="h-7 text-fs-xs px-2.5"
                  onClick={() => onNextStep?.(step)}
                  data-testid={`model-case-next-step-${i}`}
                >
                  {step.label}
                </Button>
              ))}
            </div>
          ) : (
            <p className="text-fs-xs text-muted-foreground" data-testid="model-case-next-empty">
              No decisions available.
            </p>
          )}
        </section>
      </CardContent>
    </Card>
  )
}

/**
 * Honest-empty landing when there is no worked case to show — e.g. a track that
 * has produced no worked example yet. No fabricated case is ever rendered.
 */
export function ModelCaseEmpty({ className }: { className?: string }) {
  return (
    <Card className={className} data-testid="model-case-empty">
      <CardContent className="py-8 text-center">
        <p className="text-sm text-muted-foreground">No worked cases yet</p>
        <p className="text-fs-xs text-muted-foreground mt-1">
          Run a model, train, tune, or run a round to leave a worked case here.
        </p>
      </CardContent>
    </Card>
  )
}
