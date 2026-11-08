/**
 * RTL tests for <IdeationPlan> (gap 10 ideation-rigor pre-run card).
 * Pure presentational: assert hypothesis/baseline/ablation/falsification
 * render, and that an over-strong novelty claim shows downgraded + raw
 * struck-through.
 */
import { describe, it, expect } from "vitest";
import { render, screen } from "@testing-library/react";
import { IdeationPlan } from "./ideation-plan";
import { FULL_PLAN, MINIMAL_PLAN } from "./ideation-plan.fixtures";

describe("<IdeationPlan>", () => {
  it("renders hypothesis, baseline, ablations, and falsification", () => {
    render(<IdeationPlan {...FULL_PLAN} />);
    expect(screen.getByTestId("ideation-hypothesis")).toHaveTextContent(/FOXA2/);
    expect(screen.getByTestId("ideation-baseline")).toHaveTextContent(/Random gene set/);
    const ablations = screen.getByTestId("ideation-ablations");
    expect(ablations).toHaveTextContent(/Permute condition labels/);
    expect(screen.getByTestId("ideation-falsification")).toHaveTextContent(/FDR > 0.1/);
  });

  it("shows a downgraded novelty claim with the raw claim struck through", () => {
    render(<IdeationPlan {...FULL_PLAN} />);
    const raw = screen.getByTestId("ideation-novelty-raw");
    expect(raw).toHaveTextContent("First study to link FOXA2 to EMT in this tissue.");
    expect(raw.className).toMatch(/line-through/);
    const downgraded = screen.getByTestId("ideation-novelty-downgraded");
    expect(downgraded).toHaveTextContent("Less-discussed in this literature search.");
    expect(downgraded.className).not.toMatch(/line-through/);
  });

  it("omits ablations and novelty sections when not provided", () => {
    render(<IdeationPlan {...MINIMAL_PLAN} />);
    expect(screen.getByTestId("ideation-hypothesis")).toHaveTextContent(/Compound X/);
    expect(screen.queryByTestId("ideation-ablations")).not.toBeInTheDocument();
    expect(screen.queryByTestId("ideation-novelty")).not.toBeInTheDocument();
    // required fields still render
    expect(screen.getByTestId("ideation-baseline")).toBeInTheDocument();
    expect(screen.getByTestId("ideation-falsification")).toBeInTheDocument();
  });

  it("notes the ideation gates run in the backend (read surface)", () => {
    render(<IdeationPlan {...MINIMAL_PLAN} />);
    expect(screen.getByText(/gates .* run in the backend/i)).toBeInTheDocument();
  });
});
