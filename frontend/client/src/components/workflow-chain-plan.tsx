import { ChevronDown, ArrowDown, Layers, CircleDot, Database } from "lucide-react"
import { useState } from "react"
import { cn } from "@/lib/utils"

interface ChainStep {
  order: number
  workflow_name: string
  role?: string
  params_template?: Record<string, any>
}

interface ChainConnection {
  from_step: number
  from_output: string
  to_step: number
  to_input: string
}

interface IOSpec {
  name: string
  type: string
  description?: string
}

interface WorkflowChainPlanProps {
  chainName: string
  displayName: string
  domain: string
  description: string
  steps: ChainStep[]
  connections: ChainConnection[]
  requiredInputs: IOSpec[]
  expectedOutputs: IOSpec[]
  onRunChain?: () => void
  className?: string
}

/** Badge for input/output type tokens */
function TypeBadge({ type }: { type: string }) {
  return (
    <span className="inline-block rounded px-1.5 py-0.5 text-[10px] font-mono bg-muted/60 text-muted-foreground border border-border/40">
      {type}
    </span>
  )
}

/** Connector arrow between steps, showing data-flow labels */
function StepConnector({ connections, fromStep, toStep }: {
  connections: ChainConnection[]
  fromStep: number
  toStep: number
}) {
  const relevant = connections.filter(c => c.from_step === fromStep && c.to_step === toStep)
  return (
    <div className="flex flex-col items-center py-1">
      <div className="w-px h-3 bg-border" />
      {relevant.length > 0 && (
        <div className="flex flex-wrap gap-1 px-2 py-1 rounded-full border border-border/60 bg-background text-[10px] text-muted-foreground max-w-[90%] justify-center">
          {relevant.map((c, i) => (
            <span key={i}>
              <span className="font-mono text-emerald-600 dark:text-emerald-400">{c.from_output}</span>
              <span className="mx-0.5">→</span>
              <span className="font-mono text-sky-600 dark:text-sky-400">{c.to_input}</span>
            </span>
          ))}
        </div>
      )}
      <ArrowDown className="h-3 w-3 text-muted-foreground" />
      <div className="w-px h-1 bg-border" />
    </div>
  )
}

export function WorkflowChainPlan({
  chainName,
  displayName,
  domain,
  description,
  steps,
  connections,
  requiredInputs,
  expectedOutputs,
  onRunChain,
  className,
}: WorkflowChainPlanProps) {
  const [expanded, setExpanded] = useState(true)

  const sortedSteps = [...steps].sort((a, b) => a.order - b.order)

  return (
    <div className={cn("rounded-lg border border-border bg-card text-card-foreground shadow-sm", className)}>
      {/* Header */}
      <button
        className="w-full flex items-center gap-3 px-4 py-3 text-left hover:bg-muted/30 transition-colors rounded-t-lg"
        onClick={() => setExpanded(e => !e)}
      >
        <Layers className="h-4 w-4 flex-shrink-0 text-primary" />
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 flex-wrap">
            <span className="font-semibold text-sm">{displayName}</span>
            <span className="text-[10px] px-1.5 py-0.5 rounded-full bg-primary/10 text-primary border border-primary/20">
              {domain.replace(/_/g, ' ')}
            </span>
            <span className="text-[10px] text-muted-foreground">
              {sortedSteps.length} steps
            </span>
          </div>
          {!expanded && (
            <p className="text-xs text-muted-foreground mt-0.5 truncate">{description}</p>
          )}
        </div>
        <ChevronDown className={cn("h-4 w-4 text-muted-foreground flex-shrink-0 transition-transform", expanded && "rotate-180")} />
      </button>

      {expanded && (
        <div className="px-4 pb-4 space-y-3">
          <p className="text-xs text-muted-foreground">{description}</p>

          {/* Required inputs */}
          {requiredInputs.length > 0 && (
            <div className="flex flex-wrap items-center gap-2">
              <Database className="h-3 w-3 text-muted-foreground flex-shrink-0" />
              <span className="text-[10px] text-muted-foreground font-medium uppercase tracking-wide">Inputs</span>
              {requiredInputs.map((inp, i) => (
                <span key={i} className="flex items-center gap-1">
                  <TypeBadge type={inp.type} />
                  {inp.description && (
                    <span className="text-[10px] text-muted-foreground">{inp.description}</span>
                  )}
                </span>
              ))}
            </div>
          )}

          {/* Step pipeline */}
          <div className="flex flex-col items-stretch">
            {sortedSteps.map((step, idx) => (
              <div key={step.order}>
                {/* Step card */}
                <div className="rounded-md border border-border bg-muted/20 px-3 py-2 flex items-start gap-3">
                  <div className="flex-shrink-0 w-5 h-5 rounded-full bg-primary/10 border border-primary/30 flex items-center justify-center text-[10px] font-bold text-primary">
                    {step.order}
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2 flex-wrap">
                      <span className="font-mono text-xs font-medium truncate">{step.workflow_name}</span>
                      {step.role && (
                        <span className="text-[10px] text-muted-foreground italic">{step.role}</span>
                      )}
                    </div>
                    {step.params_template && Object.keys(step.params_template).length > 0 && (
                      <div className="mt-1 flex flex-wrap gap-1">
                        {Object.entries(step.params_template).slice(0, 4).map(([k, v]) => (
                          <span key={k} className="text-[10px] font-mono bg-muted/60 border border-border/40 rounded px-1">
                            {k}={String(v)}
                          </span>
                        ))}
                      </div>
                    )}
                  </div>
                  <CircleDot className="h-3 w-3 flex-shrink-0 mt-0.5 text-muted-foreground/40" />
                </div>

                {/* Connector to next step */}
                {idx < sortedSteps.length - 1 && (
                  <StepConnector
                    connections={connections}
                    fromStep={step.order}
                    toStep={sortedSteps[idx + 1].order}
                  />
                )}
              </div>
            ))}
          </div>

          {/* Expected outputs */}
          {expectedOutputs.length > 0 && (
            <div className="flex flex-wrap items-center gap-2">
              <CircleDot className="h-3 w-3 text-emerald-500 flex-shrink-0" />
              <span className="text-[10px] text-muted-foreground font-medium uppercase tracking-wide">Outputs</span>
              {expectedOutputs.map((out, i) => (
                <span key={i} className="flex items-center gap-1">
                  <TypeBadge type={out.type} />
                  {out.description && (
                    <span className="text-[10px] text-muted-foreground">{out.description}</span>
                  )}
                </span>
              ))}
            </div>
          )}

          {onRunChain && (
            <button
              onClick={onRunChain}
              className="w-full mt-1 py-1.5 rounded-md bg-primary text-primary-foreground text-sm font-medium hover:bg-primary/90 transition-colors"
            >
              Run Pipeline
            </button>
          )}
        </div>
      )}
    </div>
  )
}
