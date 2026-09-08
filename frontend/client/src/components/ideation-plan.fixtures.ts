/**
 * Fixtures for <IdeationPlan>. These stand in for a plan the BACKEND
 * ideation gates have already produced/approved; no gating logic here.
 */

import type { IdeationPlanProps } from "./ideation-plan";

/** A full plan with an over-strong novelty claim to be downgraded. */
export const FULL_PLAN: IdeationPlanProps = {
  hypothesis:
    "Knocking out gene FOXA2 shifts the treated-vs-control DE signature toward an EMT program.",
  baseline: "Random gene set of matched size and expression level (null: no EMT enrichment).",
  ablations: [
    "Drop FOXA2 targets, re-test enrichment.",
    "Permute condition labels 1,000× for an empirical p-value.",
  ],
  falsification:
    "Hypothesis is refuted if EMT enrichment FDR > 0.1 or the permutation p-value ≥ 0.05.",
  noveltyClaim: {
    raw: "First study to link FOXA2 to EMT in this tissue.",
    downgraded: "Less-discussed in this literature search.",
  },
};

/** A minimal plan — required fields only, no ablations, no novelty claim. */
export const MINIMAL_PLAN: IdeationPlanProps = {
  hypothesis: "Compound X lowers hERG liability relative to the parent scaffold.",
  baseline: "Parent scaffold measured hERG IC50 (null: no improvement).",
  falsification: "Refuted if predicted hERG IC50 is within 2× of the parent.",
};
