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
  reRank,
  classifyRejection,
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

  // ---- §5.4 Pareto / trade-off view ---------------------------------------
  it("renders a Pareto trade-off view with front points highlighted (§5.4)", async () => {
    await runToCompletion(makeClient(COMPLETED))
    const pareto = screen.getByTestId("pareto-view")
    expect(pareto).toBeTruthy()
    expect(within(pareto).getByTestId("pareto-svg")).toBeTruthy()
    // Every candidate is plotted, including the gate-rejected one (stays visible).
    expect(within(pareto).getByTestId("pareto-point-BM-0001")).toBeTruthy()
    expect(within(pareto).getByTestId("pareto-point-BM-0002")).toBeTruthy()
    // The pareto member (CCO == BM-0001) is flagged on-front; the other is not.
    expect(within(pareto).getByTestId("pareto-point-BM-0001").getAttribute("data-on-front")).toBe("true")
    expect(within(pareto).getByTestId("pareto-point-BM-0002").getAttribute("data-on-front")).toBe("false")
  })

  it("shows an honest empty Pareto state when fewer than two objectives", async () => {
    const oneObj: GenerationRun = {
      ...COMPLETED,
      objectives: [{ name: "drug_like", unit: "QED", direction: "maximize" }],
      candidates: [
        {
          ...COMPLETED.candidates![0],
          objectives: [{ name: "drug_like", value: 0.91, unit: "QED", target: null, direction: "maximize" }],
        },
      ],
      rejected: [],
    }
    await runToCompletion(makeClient(oneObj))
    expect(screen.getByTestId("pareto-empty").textContent).toMatch(/needs two objectives/i)
  })

  // ---- §5.5 editable criteria/weights strip (re-rank without re-running) ---
  it("renders an editable criteria/weights strip that states the criteria (§5.5)", async () => {
    await runToCompletion(makeClient(COMPLETED))
    const strip = screen.getByTestId("criteria-strip")
    expect(within(strip).getByTestId("criteria-row-drug_like")).toBeTruthy()
    expect(within(strip).getByTestId("criteria-weight-drug_like")).toBeTruthy()
    // Weights are stated on the ranking.
    expect(screen.getByTestId("criteria-stated").textContent).toMatch(/w=/)
  })

  it("re-ranks client-side when a weight changes, WITHOUT re-running (§5.4)", async () => {
    const client = makeClient(COMPLETED)
    await runToCompletion(client)
    const pollCallsBefore = (client.poll as any).mock.calls.length
    // Zero out drug_like so property_envelope (both 1.0) dominates — order is a
    // pure client-side re-sort; no new poll/start is issued.
    fireEvent.change(screen.getByTestId("criteria-weight-drug_like"), { target: { value: "0" } })
    // No extra backend call fired by editing a weight.
    expect((client.poll as any).mock.calls.length).toBe(pollCallsBefore)
    expect((client.start as any).mock.calls.length).toBe(1)
    expect(screen.getByTestId("mobj-row-BM-0001")).toBeTruthy()
  })

  it("reRank sorts by weighted desirability and pushes held candidates last", () => {
    const mk = (id: string, qed: number, verdict = "accepted") => ({
      id,
      smiles: id,
      score: qed,
      confidence: "high",
      herg: "gate",
      drugLike: `QED ${qed}`,
      verdict,
      objectives: [{ name: "drug_like", value: qed, unit: "QED", target: null, direction: "maximize" }],
    })
    const cands = [mk("low", 0.3), mk("held", 0.99, "held"), mk("high", 0.9)]
    const ranked = reRank(cands as any, { drug_like: { target: null, weight: 1 } })
    expect(ranked.map((c) => c.id)).toEqual(["high", "low", "held"])
  })

  // ---- §5.2 rejection profile by cause ------------------------------------
  it("shows the rejection profile broken down by cause (§5.2)", async () => {
    const multiReject: GenerationRun = {
      ...COMPLETED,
      rejected: [
        { id: "BM-0002", smiles: "x", reason: "structural alert: nitro_group", objectives: [] },
        { id: "BM-0003", smiles: "y", reason: "banned moiety: [N+](=O)[O-]", objectives: [] },
        { id: "BM-0004", smiles: "z", reason: "invalid structure (unparseable)", objectives: [] },
      ],
    }
    await runToCompletion(makeClient(multiReject))
    const prof = screen.getByTestId("rejection-profile")
    expect(within(prof).getByTestId("rejection-cause-structural_alert")).toBeTruthy()
    expect(within(prof).getByTestId("rejection-cause-banned_moiety")).toBeTruthy()
    expect(within(prof).getByTestId("rejection-cause-valence")).toBeTruthy()
    expect(within(prof).getByTestId("rejection-count-structural_alert").textContent).toBe("1")
  })

  it("classifyRejection buckets backend reason strings by cause", () => {
    expect(classifyRejection("structural alert: nitro_group")).toBe("structural_alert")
    expect(classifyRejection("banned moiety: [N+]")).toBe("banned_moiety")
    expect(classifyRejection("invalid structure (unparseable)")).toBe("valence")
    expect(classifyRejection("synthetic accessibility below floor")).toBe("sa_floor")
    expect(classifyRejection("something else")).toBe("other")
  })

  // ---- §5.3/§5.5 per-row "why?" drill-in ----------------------------------
  it("opens a per-row why? with model/version/confidence + honest analogue (§5.3)", async () => {
    await runToCompletion(makeClient(COMPLETED))
    fireEvent.click(screen.getByTestId("why-toggle-BM-0001"))
    await waitFor(() => expect(screen.getByTestId("why-detail-BM-0001")).toBeTruthy())
    // Model version names the deterministic generator; confidence is surfaced.
    expect(screen.getByTestId("why-version-BM-0001").textContent).toMatch(/deterministic/i)
    expect(screen.getByTestId("why-confidence-BM-0001").textContent).toMatch(/high/i)
    // Honest: no nearest measured analogue in the backend contract, so it says so.
    expect(screen.getByTestId("why-analogue-BM-0001").textContent).toMatch(/not available/i)
  })
})
