/**
 * WorkflowDisambiguationCard
 *
 * Rendered when the backend returns workflow_type='disambiguation' — i.e., when
 * multiple plausible workflows scored close to each other and the system cannot
 * confidently pick one automatically.
 *
 * The user clicks a workflow to submit "I want to use <display_name>" back into
 * the chat, which causes the backend to route directly to the selected workflow.
 */

import { cn } from "@/lib/utils"

export interface DisambigCandidate {
  name: string
  display_name: string
  description: string
  source: string
  format: string
  score: number
}

interface WorkflowDisambiguationCardProps {
  message: string
  candidates: DisambigCandidate[]
  onSelect: (candidate: DisambigCandidate) => void
  className?: string
}

const SOURCE_LABELS: Record<string, { label: string; color: string }> = {
  nfcore:           { label: "nf-core",        color: "bg-blue-100 text-blue-800 dark:bg-blue-900/40 dark:text-blue-300" },
  nfcore_subwf:     { label: "nf-core",        color: "bg-blue-100 text-blue-800 dark:bg-blue-900/40 dark:text-blue-300" },
  biomni_nextflow:  { label: "BioMate",        color: "bg-violet-100 text-violet-800 dark:bg-violet-900/40 dark:text-violet-300" },
  bioconductor:     { label: "Bioconductor",   color: "bg-green-100 text-green-700 dark:bg-green-900/40 dark:text-green-300" },
  biomate:          { label: "BioMate",        color: "bg-violet-100 text-violet-800 dark:bg-violet-900/40 dark:text-violet-300" },
  chain:            { label: "Pipeline",       color: "bg-amber-100 text-amber-800 dark:bg-amber-900/40 dark:text-amber-300" },
}

function SourceBadge({ source }: { source: string }) {
  const meta = SOURCE_LABELS[source] ?? { label: source, color: "bg-muted text-muted-foreground" }
  return (
    <span className={cn("inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-medium", meta.color)}>
      {meta.label}
    </span>
  )
}

export function WorkflowDisambiguationCard({
  message,
  candidates,
  onSelect,
  className,
}: WorkflowDisambiguationCardProps) {
  return (
    <div className={cn("rounded-lg border bg-card text-card-foreground shadow-sm", className)}>
      {/* Header */}
      <div className="px-4 pt-3 pb-2 border-b">
        <p className="text-sm text-muted-foreground">{message}</p>
      </div>

      {/* Candidate list */}
      <div className="divide-y">
        {candidates.map((c) => (
          <button
            key={c.name}
            data-testid={`disambig-candidate-${c.name}`}
            onClick={() => onSelect(c)}
            className={cn(
              "w-full text-left px-4 py-3 flex flex-col gap-1",
              "hover:bg-accent hover:text-accent-foreground transition-colors",
              "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
            )}
          >
            <div className="flex items-center gap-2">
              <span className="text-sm font-semibold leading-tight">
                {c.display_name}
              </span>
              <SourceBadge source={c.source} />
            </div>
            {c.description && (
              <p className="text-xs text-muted-foreground line-clamp-2 leading-snug">
                {c.description}
              </p>
            )}
          </button>
        ))}
      </div>

      {/* Footer hint */}
      <div className="px-4 py-2 border-t">
        <p className="text-[10px] text-muted-foreground">
          Select a workflow to continue — you can refine parameters in the next step.
        </p>
      </div>
    </div>
  )
}
