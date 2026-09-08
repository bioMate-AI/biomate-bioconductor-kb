/**
 * IdeationPlan — gap 10 "ideation rigor" pre-run plan card.
 *
 * Surfaces, BEFORE a run, the ingredients OmniScientist's ideation gates
 * require: a falsifiable hypothesis, a stated baseline/null, planned
 * ablations, and the falsification criteria. Any over-strong novelty claim
 * ("first", "never studied") is rendered in its DOWNGRADED form
 * ("less-discussed in this search") with the raw claim struck through, so
 * the honest wording is what the user reads while the original stays visible.
 *
 * This is a PRESENTATIONAL surface only. The gates themselves — enforcing
 * ≥5 candidate hypotheses, the leakage / effective-N / class-balance checks,
 * and the actual novelty-downgrade decision — are BACKEND and OUT OF SCOPE.
 * This card renders the plan it is handed and never invents a field.
 *
 * Ref: docs/20260901_OMNISCIENTIST_GAP_ANALYSIS.md (Gap B),
 *      docs/20260903_DESIGN_VS_PLAN_DISCREPANCY_AND_UPDATE_BRIEF.md (gap 10).
 */

import type { ReactNode } from "react";
import { Lightbulb, Scale, GitBranch, TestTube2, ShieldAlert } from "lucide-react";
import { cn } from "@/lib/utils";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface NoveltyClaim {
  /** The over-strong claim as originally written, e.g. "first to show X". */
  raw: string;
  /** The downgraded, defensible wording, e.g. "less-discussed in this search". */
  downgraded: string;
}

export interface IdeationPlanProps {
  /** The one falsifiable, computable hypothesis the run tests. */
  hypothesis: string;
  /** The stated null / baseline the hypothesis is measured against. */
  baseline: string;
  /** Planned ablations / control variations, if any. */
  ablations?: string[];
  /** The criteria under which the hypothesis would be considered refuted. */
  falsification: string;
  /**
   * Optional novelty claim. When present, the raw over-strong wording is shown
   * struck-through and the downgraded wording is shown as the live claim.
   */
  noveltyClaim?: NoveltyClaim;
  className?: string;
}

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

export function IdeationPlan({
  hypothesis,
  baseline,
  ablations,
  falsification,
  noveltyClaim,
  className,
}: IdeationPlanProps) {
  const hasAblations = !!ablations && ablations.length > 0;

  return (
    <div
      data-testid="ideation-plan"
      className={cn(
        "shadcn-card rounded-xl border bg-card border-card-border text-card-foreground shadow-sm",
        "flex flex-col gap-4 p-5",
        className,
      )}
    >
      {/* Header */}
      <div className="flex items-center gap-2">
        <Lightbulb className="h-4 w-4 shrink-0 text-muted-foreground" aria-hidden />
        <div className="text-sm font-semibold leading-tight">Plan before we run</div>
        <span className="ml-auto whitespace-nowrap rounded-md border border-card-border bg-muted px-2 py-0.5 text-[11px] font-medium text-muted-foreground">
          pre-run
        </span>
      </div>

      {/* Hypothesis */}
      <Section
        icon={Lightbulb}
        label="Hypothesis"
        testId="ideation-hypothesis"
      >
        <p className="text-sm leading-snug text-foreground">{hypothesis}</p>
      </Section>

      {/* Baseline / null */}
      <Section icon={Scale} label="Baseline / null" testId="ideation-baseline">
        <p className="text-sm leading-snug text-foreground">{baseline}</p>
      </Section>

      {/* Ablations */}
      {hasAblations && (
        <Section icon={GitBranch} label="Planned ablations" testId="ideation-ablations">
          <ul className="flex flex-col gap-1">
            {ablations!.map((a, i) => (
              <li key={i} className="flex items-start gap-2 text-sm">
                <span className="mt-1.5 h-1 w-1 shrink-0 rounded-full bg-muted-foreground/60" />
                <span className="leading-snug text-foreground">{a}</span>
              </li>
            ))}
          </ul>
        </Section>
      )}

      {/* Falsification criteria */}
      <Section
        icon={TestTube2}
        label="Falsification criteria"
        testId="ideation-falsification"
      >
        <p className="text-sm leading-snug text-foreground">{falsification}</p>
      </Section>

      {/* Novelty claim — raw struck through, downgraded shown live. */}
      {noveltyClaim && (
        <div
          data-testid="ideation-novelty"
          className="flex flex-col gap-1.5 rounded-lg border border-amber-500/30 bg-amber-500/5 p-3"
        >
          <div className="flex items-center gap-1.5">
            <ShieldAlert className="h-3.5 w-3.5 shrink-0 text-amber-500" aria-hidden />
            <span className="text-xs font-semibold text-muted-foreground">Novelty claim</span>
          </div>
          <p className="text-sm leading-snug">
            <span
              data-testid="ideation-novelty-raw"
              className="text-muted-foreground line-through decoration-amber-500/70"
            >
              {noveltyClaim.raw}
            </span>{" "}
            <span
              data-testid="ideation-novelty-downgraded"
              className="font-medium text-foreground"
            >
              {noveltyClaim.downgraded}
            </span>
          </p>
          <span className="text-[11px] leading-snug text-muted-foreground/70">
            Over-strong novelty language is auto-downgraded to what the literature search can
            support.
          </span>
        </div>
      )}

      {/* Provenance note: gates are backend, this is a read surface. */}
      <div className="text-[11px] leading-snug text-muted-foreground/70">
        The ideation gates (≥5 candidate hypotheses, leakage / effective-N / class-balance
        checks, novelty downgrade) run in the backend. This card shows the plan that passed
        them.
      </div>
    </div>
  );
}

function Section({
  icon: Icon,
  label,
  testId,
  children,
}: {
  icon: typeof Lightbulb;
  label: string;
  testId?: string;
  children: ReactNode;
}) {
  return (
    <div className="flex flex-col gap-1.5" data-testid={testId}>
      <div className="flex items-center gap-1.5">
        <Icon className="h-3.5 w-3.5 shrink-0 text-muted-foreground" aria-hidden />
        <span className="text-xs font-semibold text-muted-foreground">{label}</span>
      </div>
      {children}
    </div>
  );
}
