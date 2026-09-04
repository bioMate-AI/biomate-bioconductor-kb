/**
 * DesignGenerate — RTL coverage for the Spec 05 design commitments.
 *
 * Uses an INJECTED client (no network) so the test drives the real component
 * logic — the constraint composer, the poll loop, the HitGrid mapping, the
 * multi-objective view, and safety-as-a-gate — against a fixed backend shape.
 */
import React from "react"
import { describe, it, expect, vi } from "vitest"
import { render, screen, fireEvent, waitFor, within } from "@testing-library/react"
import {
  DesignGenerate,
  type GenerateClient,
  type GenerationRun,
} from "./DesignGenerate"

function makeClient(final: GenerationRun): GenerateClient {
  return {
    start: vi.fn(async () => ({ run_id: final.run_id, status: "running" })),
    poll: vi.fn(async () => final),
  }
}

const COMPLETED: GenerationRun = {
  run_id: "gen_test",
  status: "completed",
  generator: "rdkit_brics_enumeration",
  generator_is_learned: false,
  n_generated: 42,
  n_scored: 20,
  objectives: [
    { name: "drug_like", unit: "QED", direction: "maximize" },
    { name: "property_envelope", unit: "fraction-in-window", direction: "maximize" },
  ],
  candidates: [
    {
      id: "BM-0001",
      smiles: "CCO",
      score: 0.72,
      confidence: "high",
      herg: "structural-alert gate",
      drugLike: "QED 0.91",
      verdict: "accepted",
      objectives: [
        { name: "drug_like", value: 0.91, unit: "QED", target: null, direction: "maximize" },
        { name: "property_envelope", value: 1.0, unit: "fraction-in-window", target: 1.0, direction: "maximize" },
      ],
    },
    {
      id: "BM-0002",
      smiles: "c1ccccc1[N+](=O)[O-]",
      score: 0.88,
      confidence: "high",
      herg: "structural-alert gate",
      drugLike: "QED 0.60",
      verdict: "rejected", // most potent-looking, but gate-rejected — stays visible
      objectives: [
        { name: "drug_like", value: 0.6, unit: "QED", target: null, direction: "maximize" },
        { name: "property_envelope", value: 1.0, unit: "fraction-in-window", target: 1.0, direction: "maximize" },
      ],
    },
  ],
  rejected: [
    {
      id: "BM-0002",
      smiles: "c1ccccc1[N+](=O)[O-]",
      reason: "structural alert: nitro_group",
      objectives: [],
    },
  ],
  pareto: ["CCO"],
  notes: ["objective 'affinity' has no honest molecule-derived predictor wired; skipped (not fabricated)"],
}

async function runToCompletion(client: GenerateClient) {
  render(<DesignGenerate client={client} />)
  fireEvent.click(screen.getByTestId("dg-run"))
  await waitFor(() => expect(screen.getByTestId("dg-status")).toHaveAttribute) // status appears
  await screen.findByTestId("hit-grid")
}

describe("DesignGenerate", () => {
  it("renders the constraints composer with all Spec-05 constraints", () => {
    render(<DesignGenerate client={makeClient(COMPLETED)} />)
    expect(screen.getByTestId("constraints-composer")).toBeTruthy()
    expect(screen.getByTestId("dg-seed-smiles")).toBeTruthy()
    expect(screen.getByTestId("dg-scaffold-policy")).toBeTruthy()
    expect(screen.getByTestId("dg-envelope")).toBeTruthy()
    expect(screen.getByTestId("dg-exclusions")).toBeTruthy()
    expect(screen.getByTestId("dg-count")).toBeTruthy()
    // Count is stated WITH compute cost shown before the run (§5.2).
    expect(screen.getByTestId("dg-cost").textContent).toMatch(/compute unit/i)
  })

  it("sends resolved constraints to the backend on run", async () => {
    const client = makeClient(COMPLETED)
    render(<DesignGenerate client={client} />)
    fireEvent.change(screen.getByTestId("dg-seed-smiles"), { target: { value: "CCO" } })
    fireEvent.click(screen.getByTestId("dg-policy-hop"))
    fireEvent.change(screen.getByTestId("dg-exclusions"), { target: { value: "[N+](=O)[O-]" } })
    fireEvent.click(screen.getByTestId("dg-run"))
    await waitFor(() => expect(client.start).toHaveBeenCalled())
    const body = (client.start as any).mock.calls[0][0]
    expect(body.constraints.seed_smiles).toBe("CCO")
    expect(body.constraints.scaffold_policy).toBe("hop")
    expect(body.constraints.exclusions).toEqual(["[N+](=O)[O-]"])
    expect(body.objectives).toContain("drug_like")
  })

  it("ranks candidates via the wave-1 HitGrid", async () => {
    await runToCompletion(makeClient(COMPLETED))
    const grid = screen.getByTestId("hit-grid")
    expect(within(grid).getByTestId("hit-row-BM-0001")).toBeTruthy()
    // Rejected candidate is STILL present in the grid (never filtered out).
    expect(within(grid).getByTestId("hit-row-BM-0002")).toBeTruthy()
  })

  it("shows a multi-objective view with per-objective UNITS and no composite", async () => {
    await runToCompletion(makeClient(COMPLETED))
    const mobj = screen.getByTestId("multi-objective-view")
    expect(mobj.textContent).toMatch(/no single blended number/i)
    // Own units surface for each objective.
    expect(mobj.textContent).toContain("QED")
    expect(mobj.textContent).toContain("fraction-in-window")
    expect(within(mobj).getByTestId("mobj-row-BM-0001")).toBeTruthy()
  })

  it("keeps gate-rejected candidates VISIBLE with their reason (safety as a gate)", async () => {
    await runToCompletion(makeClient(COMPLETED))
    const rej = screen.getByTestId("rejected-set")
    fireEvent.click(within(rej).getByText(/Rejected by a gate/i))
    await waitFor(() =>
      expect(screen.getByTestId("rejected-reason-BM-0002").textContent).toMatch(/nitro_group/),
    )
  })

  it("reports the honest failure profile when no candidates clear", async () => {
    const empty: GenerationRun = {
      run_id: "gen_empty",
      status: "completed",
      generator: "rdkit_brics_enumeration",
      generator_is_learned: false,
      n_generated: 0,
      n_scored: 0,
      objectives: [],
      candidates: [],
      rejected: [],
      pareto: [],
      notes: ["no candidates: no_seed_smiles"],
    }
    render(<DesignGenerate client={makeClient(empty)} />)
    fireEvent.click(screen.getByTestId("dg-run"))
    await screen.findByTestId("dg-empty")
    expect(screen.getByTestId("dg-notes").textContent).toMatch(/no_seed_smiles/)
    // Nothing fabricated to fill a shortlist.
    expect(screen.getByTestId("dg-empty").textContent).toMatch(/nothing was fabricated/i)
  })

  it("surfaces the honest 'affinity skipped, not fabricated' note", async () => {
    await runToCompletion(makeClient(COMPLETED))
    expect(screen.getByTestId("dg-notes").textContent).toMatch(/not fabricated/i)
  })
})
