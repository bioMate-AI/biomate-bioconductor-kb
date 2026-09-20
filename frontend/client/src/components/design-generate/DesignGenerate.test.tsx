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
  buildOrderSheetCsv,
  isContradiction,
  modalityOf,
  MODALITY_META,
  ENTRY_ROUTE_TARGETS,
  type GenerateClient,
  type GenerationRun,
  type MeasuredResult,
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
  await waitFor(() => expect(screen.getByTestId("dg-status")).toBeInTheDocument()) // status appears
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
    // Pre-run cost estimation removed from the UI (no cost estimates anywhere —
    // consistent with the workflow panel; cost lives on the billing page).
    expect(screen.queryByTestId("dg-cost")).toBeNull()
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

  // ---- §5.6 entry routes ("start from…") ----------------------------------
  it("renders the entry-routes strip with all three routes (§5.6)", () => {
    render(<DesignGenerate client={makeClient(COMPLETED)} />)
    const strip = screen.getByTestId("entry-routes")
    // Spec-05 §5.6 canonical testids.
    expect(within(strip).getByTestId("design-entry-dataset")).toBeTruthy()
    expect(within(strip).getByTestId("design-entry-models")).toBeTruthy()
    expect(within(strip).getByTestId("design-entry-search")).toBeTruthy()
    // Legacy aliases preserved as a data attribute so older selectors resolve.
    expect(within(strip).getByTestId("design-entry-dataset").getAttribute("data-legacy-testid")).toBe(
      "entry-dataset",
    )
  })

  it("navigates to the real in-app surface for each entry route by default (§5.6)", () => {
    // No callback props wired → the chips perform REAL router navigation (not
    // no-ops). wouter's default navigation calls window.history.pushState; spy
    // on it and assert the target path per chip.
    const pushSpy = vi.spyOn(window.history, "pushState")
    render(<DesignGenerate client={makeClient(COMPLETED)} />)

    fireEvent.click(screen.getByTestId("design-entry-dataset"))
    expect(pushSpy).toHaveBeenLastCalledWith(null, "", ENTRY_ROUTE_TARGETS.dataset)
    expect(ENTRY_ROUTE_TARGETS.dataset).toMatch(/^\/files/)

    fireEvent.click(screen.getByTestId("design-entry-models"))
    expect(pushSpy).toHaveBeenLastCalledWith(null, "", ENTRY_ROUTE_TARGETS.model)
    expect(ENTRY_ROUTE_TARGETS.model).toMatch(/^\/models/)

    fireEvent.click(screen.getByTestId("design-entry-search"))
    expect(pushSpy).toHaveBeenLastCalledWith(null, "", ENTRY_ROUTE_TARGETS.search)
    expect(ENTRY_ROUTE_TARGETS.search).toMatch(/^\/\?from=design/)

    pushSpy.mockRestore()
  })

  it("lets a host override an entry route with a callback instead of navigating (§5.6)", () => {
    const onStartFromDataset = vi.fn()
    const onStartFromModel = vi.fn()
    const onPromoteFromSearch = vi.fn()
    const pushSpy = vi.spyOn(window.history, "pushState")
    render(
      <DesignGenerate
        client={makeClient(COMPLETED)}
        onStartFromDataset={onStartFromDataset}
        onStartFromModel={onStartFromModel}
        onPromoteFromSearch={onPromoteFromSearch}
      />,
    )
    const pushesBefore = pushSpy.mock.calls.length
    fireEvent.click(screen.getByTestId("design-entry-dataset"))
    fireEvent.click(screen.getByTestId("design-entry-models"))
    fireEvent.click(screen.getByTestId("design-entry-search"))
    expect(onStartFromDataset).toHaveBeenCalledTimes(1)
    expect(onStartFromModel).toHaveBeenCalledTimes(1)
    expect(onPromoteFromSearch).toHaveBeenCalledTimes(1)
    // The host callback takes precedence — no router navigation fired.
    expect(pushSpy.mock.calls.length).toBe(pushesBefore)
    pushSpy.mockRestore()
  })

  // ---- §5.5/§5.7 export order sheet ---------------------------------------
  it("offers an 'Export order sheet' control once candidates exist (§5.5)", async () => {
    await runToCompletion(makeClient(COMPLETED))
    expect(screen.getByTestId("dg-export-order")).toBeTruthy()
  })

  it("buildOrderSheetCsv pairs candidate + registry ids and carries objective values", () => {
    const csv = buildOrderSheetCsv(COMPLETED.candidates!, COMPLETED.objectives!)
    const lines = csv.split("\n")
    // Header names both id columns and one column per objective with its unit.
    expect(lines[0]).toContain("candidate_id")
    expect(lines[0]).toContain("registry_id")
    expect(lines[0]).toContain("drug_like (QED)")
    // First data row pairs the platform id with a REG- registry id + its value.
    expect(lines[1]).toContain("BM-0001")
    expect(lines[1]).toContain("REG-BM-0001")
    expect(lines[1]).toContain("0.91")
    // Every candidate is exported, including the gate-rejected one (stays visible).
    expect(csv).toContain("BM-0002")
  })

  it("clicking export triggers a client-side CSV blob download", async () => {
    const client = makeClient(COMPLETED)
    const createURL = vi.fn(() => "blob:order")
    const revokeURL = vi.fn()
    ;(URL as any).createObjectURL = createURL
    ;(URL as any).revokeObjectURL = revokeURL
    const clickSpy = vi.spyOn(HTMLAnchorElement.prototype, "click").mockImplementation(() => {})
    await runToCompletion(client)
    fireEvent.click(screen.getByTestId("dg-export-order"))
    expect(createURL).toHaveBeenCalledTimes(1)
    expect(clickSpy).toHaveBeenCalledTimes(1)
    expect(revokeURL).toHaveBeenCalledTimes(1)
    clickSpy.mockRestore()
  })

  // ---- §5.7 predicted-vs-measured -----------------------------------------
  it("shows an honest empty predicted-vs-measured state when no measurements (§5.7)", async () => {
    await runToCompletion(makeClient(COMPLETED))
    const pvm = screen.getByTestId("predicted-vs-measured")
    expect(within(pvm).getByTestId("pvm-empty").textContent).toMatch(/no measured results yet/i)
  })

  it("shows predicted-vs-measured per candidate and flags contradictions (§5.7)", async () => {
    const measured: MeasuredResult[] = [
      {
        id: "BM-0001",
        registryId: "REG-BM-0001",
        measured: [
          // matches prediction (0.91) closely — no contradiction
          { name: "drug_like", value: 0.9, unit: "QED" },
          // predicted 1.0, measured 0.1 — a large divergence → contradiction
          { name: "property_envelope", value: 0.1, unit: "fraction-in-window" },
        ],
      },
    ]
    render(<DesignGenerate client={makeClient(COMPLETED)} measuredResults={measured} />)
    fireEvent.click(screen.getByTestId("dg-run"))
    await screen.findByTestId("hit-grid")
    const pvm = screen.getByTestId("predicted-vs-measured")
    expect(within(pvm).getByTestId("pvm-row-BM-0001")).toBeTruthy()
    // drug_like agrees → not flagged; property_envelope diverges → flagged.
    expect(
      within(pvm).getByTestId("pvm-cell-BM-0001-drug_like").getAttribute("data-contradiction"),
    ).toBe("false")
    expect(
      within(pvm).getByTestId("pvm-cell-BM-0001-property_envelope").getAttribute("data-contradiction"),
    ).toBe("true")
    expect(within(pvm).getByTestId("pvm-flag-BM-0001-property_envelope")).toBeTruthy()
    expect(within(pvm).getByTestId("pvm-contradiction-count").textContent).toMatch(/1 flagged/)
  })

  it("isContradiction flags only large relative divergences", () => {
    expect(isContradiction(1.0, 0.9)).toBe(false) // 10% — within tolerance
    expect(isContradiction(1.0, 0.1)).toBe(true) // 90% — a contradiction
    expect(isContradiction(0, 0)).toBe(false) // near-zero, no divergence
  })

  // ---- §11 modality control (all-modalities design) -----------------------
  it("renders the modality control with all three chips, small molecule default (§11.2)", () => {
    render(<DesignGenerate client={makeClient(COMPLETED)} />)
    const mod = screen.getByTestId("dg-modality")
    expect(within(mod).getByTestId("dg-modality-small_molecule")).toBeTruthy()
    expect(within(mod).getByTestId("dg-modality-peptide")).toBeTruthy()
    expect(within(mod).getByTestId("dg-modality-protein")).toBeTruthy()
    // Small molecule is the default (selected) and shows the chemistry constraints.
    expect(screen.getByTestId("dg-modality-small_molecule").getAttribute("data-selected")).toBe("true")
    expect(screen.getByTestId("dg-constraints-small_molecule")).toBeTruthy()
    // The stay-on slot for small molecule is the scaffold.
    expect(screen.getByTestId("dg-modality-blurb").textContent).toMatch(/scaffold/i)
  })

  it("switching to Peptide swaps the constraint set to sequence + cyclisation (§11.3)", () => {
    render(<DesignGenerate client={makeClient(COMPLETED)} />)
    fireEvent.click(screen.getByTestId("dg-modality-peptide"))
    // Chemistry constraints hidden; peptide constraints shown.
    expect(screen.queryByTestId("dg-constraints-small_molecule")).toBeNull()
    expect(screen.getByTestId("dg-constraints-peptide")).toBeTruthy()
    expect(screen.getByTestId("dg-sequence")).toBeTruthy()
    expect(screen.getByTestId("dg-cyclization")).toBeTruthy()
    // Stay-on slot is the sequence motif.
    expect(screen.getByTestId("dg-modality-blurb").textContent).toMatch(/sequence motif/i)
  })

  it("switching to Protein shows the framework seed constraint (§11.3)", () => {
    render(<DesignGenerate client={makeClient(COMPLETED)} />)
    fireEvent.click(screen.getByTestId("dg-modality-protein"))
    expect(screen.getByTestId("dg-constraints-protein")).toBeTruthy()
    expect(screen.getByTestId("dg-framework")).toBeTruthy()
    expect(screen.getByTestId("dg-modality-blurb").textContent).toMatch(/framework/i)
  })

  it("gates the run for non-chemistry modalities with an HONEST generatorcoming state (§11.6)", () => {
    const client = makeClient(COMPLETED)
    render(<DesignGenerate client={client} />)
    fireEvent.click(screen.getByTestId("dg-modality-peptide"))
    // The run is disabled and the honest note is shown — no fabricated result.
    expect((screen.getByTestId("dg-run") as HTMLButtonElement).disabled).toBe(true)
    expect(screen.getByTestId("dg-modality-unrunnable").textContent).toMatch(/generator coming/i)
    // Clicking the disabled run fires no backend call.
    fireEvent.click(screen.getByTestId("dg-run"))
    expect(client.start).not.toHaveBeenCalled()
  })

  it("carries the selected modality + its constraints into the run payload for small molecule (§11.4)", async () => {
    const client = makeClient(COMPLETED)
    render(<DesignGenerate client={client} />)
    // Small molecule stays runnable; the modality travels with the request.
    fireEvent.change(screen.getByTestId("dg-seed-smiles"), { target: { value: "CCO" } })
    fireEvent.click(screen.getByTestId("dg-run"))
    await waitFor(() => expect(client.start).toHaveBeenCalled())
    const body = (client.start as any).mock.calls[0][0]
    expect(body.modality).toBe("small_molecule")
    expect(body.constraints.seed_smiles).toBe("CCO")
    // Peptide/protein-only fields are NOT cross-fed on a small-molecule run.
    expect(body.constraints.sequence).toBeUndefined()
    expect(body.constraints.framework).toBeUndefined()
  })

  it("modalityOf infers the modality from free text (§11.4)", () => {
    expect(modalityOf("cyclic peptide binders to an epitope")).toBe("peptide")
    expect(modalityOf("staple this helix")).toBe("peptide")
    expect(modalityOf("macrocyclise a linear binder")).toBe("peptide")
    expect(modalityOf("nanobody candidates against the target")).toBe("protein")
    expect(modalityOf("graft the CDRs onto a human framework")).toBe("protein")
    expect(modalityOf("enzyme active-site redesign, keep thermostability")).toBe("protein")
    expect(modalityOf("improve expression titre of the construct")).toBe("protein")
    expect(modalityOf("scaffold-hop the aspirin core")).toBe("small_molecule")
    expect(modalityOf("")).toBe("small_molecule")
  })

  it("exposes a stay-on slot per modality (§11.4)", () => {
    expect(MODALITY_META.small_molecule.stayOn).toMatch(/scaffold/i)
    expect(MODALITY_META.peptide.stayOn).toMatch(/sequence/i)
    expect(MODALITY_META.protein.stayOn).toMatch(/framework/i)
  })
})
