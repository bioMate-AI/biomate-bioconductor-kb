/**
 * Unit tests for coerceIdeationPlan — the guard that decides whether the
 * <IdeationPlan> card renders or the honest empty state shows. It must NEVER
 * fabricate a plan: all three load-bearing fields (hypothesis, baseline,
 * falsification) are required, or it returns null.
 */

import { describe, it, expect } from "vitest";
import { coerceIdeationPlan } from "./ideation-rigor-section";
import { FULL_PLAN, MINIMAL_PLAN } from "./ideation-plan.fixtures";

describe("coerceIdeationPlan", () => {
  it("returns null for missing / non-object input", () => {
    expect(coerceIdeationPlan(undefined)).toBeNull();
    expect(coerceIdeationPlan(null)).toBeNull();
    expect(coerceIdeationPlan("not an object")).toBeNull();
    expect(coerceIdeationPlan(42)).toBeNull();
    expect(coerceIdeationPlan({})).toBeNull();
  });

  it("returns null when any required field is missing or blank", () => {
    expect(coerceIdeationPlan({ hypothesis: "h", baseline: "b" })).toBeNull();
    expect(coerceIdeationPlan({ hypothesis: "h", falsification: "f" })).toBeNull();
    expect(coerceIdeationPlan({ hypothesis: "  ", baseline: "b", falsification: "f" })).toBeNull();
  });

  it("accepts the full and minimal fixtures", () => {
    const full = coerceIdeationPlan(FULL_PLAN);
    expect(full).not.toBeNull();
    expect(full!.ablations?.length).toBe(2);
    expect(full!.noveltyClaim?.downgraded).toMatch(/less-discussed/i);

    const min = coerceIdeationPlan(MINIMAL_PLAN);
    expect(min).not.toBeNull();
    expect(min!.ablations).toBeUndefined();
    expect(min!.noveltyClaim).toBeUndefined();
  });

  it("drops a malformed novelty claim rather than passing a half object", () => {
    const r = coerceIdeationPlan({
      hypothesis: "h",
      baseline: "b",
      falsification: "f",
      noveltyClaim: { raw: "only raw, no downgraded" },
    });
    expect(r).not.toBeNull();
    expect(r!.noveltyClaim).toBeUndefined();
  });

  it("filters non-string / empty ablation entries", () => {
    const r = coerceIdeationPlan({
      hypothesis: "h",
      baseline: "b",
      falsification: "f",
      ablations: ["keep me", "", 5, null, "keep me too"],
    });
    expect(r!.ablations).toEqual(["keep me", "keep me too"]);
  });
});
