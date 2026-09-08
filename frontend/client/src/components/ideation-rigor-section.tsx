/**
 * IdeationRigorSection — collapsible "rigor" wrapper that mounts <IdeationPlan>
 * (gap 10) on a workflow card, before a Cloud run confirms.
 *
 * The orphaned-but-tested <IdeationPlan> card (hypothesis / baseline-null /
 * planned ablations / falsification criteria / novelty-downgrade) is a
 * PRESENTATIONAL surface that requires a full plan. The backend ideation gates
 * produce that plan; this wrapper renders it when present (metadata.ideationPlan)
 * and shows an HONEST empty state when it is not — it never fabricates a plan.
 *
 * Mirrors the collapse pattern of <WorkflowRationale> so it reads as a peer
 * "expandable rigor section" on the same card.
 *
 * Ref: docs/20260903_DESIGN_VS_PLAN_DISCREPANCY_AND_UPDATE_BRIEF.md (gap 10).
 */

import { useState } from "react";
import { cn } from "@/lib/utils";
import { ChevronDown, ShieldCheck } from "lucide-react";
import { Button } from "@/components/ui/button";
import { IdeationPlan, type IdeationPlanProps } from "./ideation-plan";

/** Narrow an unknown metadata blob into IdeationPlanProps, or null. */
export function coerceIdeationPlan(raw: unknown): IdeationPlanProps | null {
  if (!raw || typeof raw !== "object") return null;
  const r = raw as Record<string, unknown>;
  const hypothesis = typeof r.hypothesis === "string" ? r.hypothesis.trim() : "";
  const baseline = typeof r.baseline === "string" ? r.baseline.trim() : "";
  const falsification = typeof r.falsification === "string" ? r.falsification.trim() : "";
  // The three required, load-bearing fields must all be present.
  if (!hypothesis || !baseline || !falsification) return null;

  const ablations = Array.isArray(r.ablations)
    ? r.ablations.filter((a): a is string => typeof a === "string" && a.trim().length > 0)
    : undefined;

  let noveltyClaim: IdeationPlanProps["noveltyClaim"];
  const nc = r.noveltyClaim as Record<string, unknown> | undefined;
  if (nc && typeof nc.raw === "string" && typeof nc.downgraded === "string") {
    noveltyClaim = { raw: nc.raw, downgraded: nc.downgraded };
  }

  return { hypothesis, baseline, falsification, ablations, noveltyClaim };
}

interface IdeationRigorSectionProps {
  /** Raw ideation-plan blob from message.metadata.ideationPlan (may be absent). */
  plan?: unknown;
  className?: string;
}

export function IdeationRigorSection({ plan, className }: IdeationRigorSectionProps) {
  const [open, setOpen] = useState(false);
  const coerced = coerceIdeationPlan(plan);

  return (
    <div
      data-testid="ideation-rigor-section"
      className={cn("rounded-md border border-border/60 overflow-hidden mt-2", className)}
    >
      <Button
        variant="ghost"
        size="sm"
        onClick={() => setOpen((v) => !v)}
        className="w-full flex items-center justify-between px-3 py-2 h-auto rounded-none text-xs font-medium text-muted-foreground hover:text-foreground hover:bg-muted/40"
        aria-expanded={open}
        data-testid="ideation-rigor-toggle"
      >
        <span className="flex items-center gap-1.5">
          <ShieldCheck className="h-3.5 w-3.5" />
          Rigor &amp; plan before we run
        </span>
        <ChevronDown className={cn("h-3.5 w-3.5 transition-transform duration-200", open && "rotate-180")} />
      </Button>

      {open && (
        <div className="px-3 pb-3 pt-2 border-t border-border/40 bg-muted/10">
          {coerced ? (
            <IdeationPlan {...coerced} className="border-0 shadow-none p-0" />
          ) : (
            <p
              data-testid="ideation-rigor-empty"
              className="text-xs leading-relaxed text-muted-foreground"
            >
              No pre-run plan for this workflow yet. When the ideation gates run,
              the falsifiable hypothesis, the baseline/null it is measured against,
              the planned ablations and the falsification criteria appear here — so
              the rigor is visible before anything runs.
            </p>
          )}
        </div>
      )}
    </div>
  );
}
