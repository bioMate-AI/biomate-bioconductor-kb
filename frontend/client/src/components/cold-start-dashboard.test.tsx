/**
 * RTL tests for <ColdStartDashboard> — the cold-start function-module
 * dashboard + intent router (spec 00 §0.4/§0.5).
 *
 * Verifies: the four function-module cards render (collapsed); clicking a card
 * expands it (body + tracks + examples visible) and collapses on a second
 * click; opening a second card closes the first (single-open); switching a
 * track swaps the shown examples; the Data analysis → Validated workflows
 * track's domain chips swap examples for that domain's shapes; clicking an
 * example intent (or a shape) seeds the composer via onSeed (not send); the
 * intent bar's router shows a route-box (lane + domain) on matching text and
 * stays hidden for short text; and the honesty contract — no fabricated
 * inventory counts on the cards.
 */
import { describe, it, expect, vi } from "vitest";
import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { ColdStartDashboard, COLD_MODULES, COLD_DOMAINS, COLD_MODALITIES, readIntent, seedWithModality, landingModules, coldCopyKey } from "./cold-start-dashboard";
import en from "@/locales/en/common.json";
import zh from "@/locales/zh/common.json";

/** The card element for a given module id. */
function cardFor(moduleId: string): HTMLElement {
  const cards = screen.getAllByTestId("cold-module-card");
  const card = cards.find((c) => c.getAttribute("data-module-id") === moduleId);
  if (!card) throw new Error(`no card for module ${moduleId}`);
  return card;
}

/** The expand/collapse header button for a given module id. */
function headerFor(moduleId: string): HTMLElement {
  return within(cardFor(moduleId)).getByTestId("cold-module-expand");
}

describe("<ColdStartDashboard>", () => {
  it("landing default shows every module, molecule design & generate included", () => {
    render(<ColdStartDashboard onSeed={() => {}} />);
    const ids = screen.getAllByTestId("cold-module-card").map((c) => c.getAttribute("data-module-id"));
    expect(ids).toEqual(landingModules().map((m) => m.id));
    expect(ids).toContain("design");
    expect(screen.getByText("Molecule design & generate")).toBeInTheDocument();
    expect(screen.getByText("What would you like to work on today?")).toBeInTheDocument();
  });

  it("every card label, track, example and shape has display copy in BOTH locale bundles", () => {
    const texts = new Set<string>();
    for (const m of COLD_MODULES) for (const tr of m.tracks) {
      texts.add(tr.k); tr.ex.forEach((x) => texts.add(x));
      if (tr.exBy) Object.values(tr.exBy).flat().forEach((x) => texts.add(x));
    }
    for (const d of COLD_DOMAINS) {
      texts.add(d.name);
      for (const sh of d.shapes) { texts.add(sh.t); texts.add(sh.needs); texts.add(sh.time); if (sh.sampleDataset) texts.add(sh.sampleDataset.label); }
    }
    for (const text of texts) {
      const key = coldCopyKey(text);
      expect((en as any).cold_start.copy[key], `en missing ${text}`).toBe(text);
      expect((zh as any).cold_start.copy[key], `zh missing ${text}`).toMatch(/[\u3400-\u9fff]|^[A-Za-z0-9 ()]+（示例）$|SMILES/);
    }
  });

  it("renders all four function-module cards, collapsed", () => {
    render(<ColdStartDashboard onSeed={() => {}} modules={COLD_MODULES} />);
    expect(screen.getByTestId("cold-start-dashboard")).toBeInTheDocument();
    const cards = screen.getAllByTestId("cold-module-card");
    expect(cards).toHaveLength(COLD_MODULES.length);
    for (const m of COLD_MODULES) {
      const card = cardFor(m.id);
      expect(card).toHaveAttribute("data-open", "false");
      // Collapsed: the header is there but the body / examples are not.
      expect(headerFor(m.id)).toHaveAttribute("aria-expanded", "false");
    }
    expect(screen.queryByTestId("cold-module-body")).toBeNull();
    expect(screen.queryByTestId("cold-example")).toBeNull();
    // Exactly the four categories, no more.
    expect(COLD_MODULES.map((m) => m.id).sort()).toEqual(
      ["analysis", "design", "models", "search"],
    );
  });

  it("shows the cold-start prompt heading but NOT a duplicate goal intent bar", () => {
    render(<ColdStartDashboard onSeed={() => {}} modules={COLD_MODULES} />);
    expect(screen.getByText("What would you like to work on today?")).toBeInTheDocument();
    // The "describe your goal" intent bar was removed 2026-11-09 — it duplicated the
    // always-present bottom composer (same onSeed→composer path). The cold-start now
    // guides via the module cards/example rows and leaves typing to the one composer.
    expect(screen.queryByTestId("cold-intent-bar")).toBeNull();
  });

  it("expands a card on click (body + tracks + examples visible) and collapses on a second click", async () => {
    const user = userEvent.setup();
    render(<ColdStartDashboard onSeed={() => {}} modules={COLD_MODULES} />);
    const header = headerFor("search");

    // Open.
    await user.click(header);
    expect(header).toHaveAttribute("aria-expanded", "true");
    expect(cardFor("search")).toHaveAttribute("data-open", "true");
    const body = within(cardFor("search")).getByTestId("cold-module-body");
    expect(body).toBeInTheDocument();
    // First track selected: its examples are shown.
    const firstTrack = COLD_MODULES.find((m) => m.id === "search")!.tracks[0];
    expect(within(body).getByText(`“${firstTrack.ex[0]}”`)).toBeInTheDocument();
    // Track tabs render.
    expect(within(body).getByTestId("cold-track-literature")).toBeInTheDocument();
    expect(within(body).getByTestId("cold-track-databases")).toBeInTheDocument();

    // Close.
    await user.click(header);
    expect(header).toHaveAttribute("aria-expanded", "false");
    expect(cardFor("search")).toHaveAttribute("data-open", "false");
    expect(within(cardFor("search")).queryByTestId("cold-module-body")).toBeNull();
  });

  it("opening a second card closes the first (single-open)", async () => {
    const user = userEvent.setup();
    render(<ColdStartDashboard onSeed={() => {}} modules={COLD_MODULES} />);

    await user.click(headerFor("search"));
    expect(cardFor("search")).toHaveAttribute("data-open", "true");

    await user.click(headerFor("design"));
    expect(cardFor("design")).toHaveAttribute("data-open", "true");
    // The first card is now closed.
    expect(cardFor("search")).toHaveAttribute("data-open", "false");
    // Exactly one body in the DOM.
    expect(screen.getAllByTestId("cold-module-body")).toHaveLength(1);
  });

  it("switching a track swaps the shown examples", async () => {
    const user = userEvent.setup();
    render(<ColdStartDashboard onSeed={() => {}} modules={COLD_MODULES} />);
    await user.click(headerFor("search"));
    const body = within(cardFor("search")).getByTestId("cold-module-body");

    const tracks = COLD_MODULES.find((m) => m.id === "search")!.tracks;
    const literature = tracks[0];
    const patents = tracks.find((t) => t.k === "Patents")!;

    // On Literature track by default.
    expect(within(body).getByText(`“${literature.ex[0]}”`)).toBeInTheDocument();
    expect(within(body).queryByText(`“${patents.ex[0]}”`)).toBeNull();

    // Switch to Patents.
    await user.click(within(body).getByTestId("cold-track-patents"));
    expect(within(body).getByText(`“${patents.ex[0]}”`)).toBeInTheDocument();
    expect(within(body).queryByText(`“${literature.ex[0]}”`)).toBeNull();
  });

  it("domain chips (Data analysis → Validated workflows) swap examples for that domain's shapes", async () => {
    const user = userEvent.setup();
    const onSeed = vi.fn();
    render(<ColdStartDashboard onSeed={onSeed} modules={COLD_MODULES} />);
    await user.click(headerFor("analysis"));
    const body = within(cardFor("analysis")).getByTestId("cold-module-body");

    // Go to the Validated workflows track — that's where domain chips live.
    await user.click(within(body).getByTestId("cold-track-validated-workflows"));
    const dd = COLD_DOMAINS.find((d) => d.id === "dd")!;
    // No shapes until a domain is chosen.
    expect(within(body).queryByTestId("cold-shape")).toBeNull();

    // Choose Drug discovery → its shapes appear.
    await user.click(within(body).getByTestId("cold-domain-dd"));
    const shapes = within(body).getAllByTestId("cold-shape");
    expect(shapes).toHaveLength(dd.shapes.length);
    expect(within(body).getByText(dd.shapes[0].t)).toBeInTheDocument();

    // Clicking a shape seeds the composer with its seed sentence.
    await user.click(shapes[0]);
    expect(onSeed).toHaveBeenCalledWith(dd.shapes[0].seed);
  });

  it("shows a 'sample' badge on examples that carry a provided sample dataset", async () => {
    const user = userEvent.setup();
    render(<ColdStartDashboard onSeed={() => {}} modules={COLD_MODULES} />);
    await user.click(headerFor("analysis"));
    const body = within(cardFor("analysis")).getByTestId("cold-module-body");
    await user.click(within(body).getByTestId("cold-track-validated-workflows"));

    // Drug discovery's ADMET shape carries an example-SMILES sample → badge shows;
    // one badge per shape that names a dataset, in shape order.
    await user.click(within(body).getByTestId("cold-domain-dd"));
    const dd = COLD_DOMAINS.find((d) => d.id === "dd")!;
    const badges = within(body).getAllByTestId("cold-shape-sample");
    expect(badges).toHaveLength(dd.shapes.filter((s) => s.sampleDataset).length);
    expect(badges[0]).toHaveTextContent(/example SMILES/i);

    // Data integrity: every attached sample has a real label + ref (no empty
    // "sample provided" that can't run), and the seed asks to run on it.
    for (const d of COLD_DOMAINS) {
      for (const s of d.shapes) {
        if (s.sampleDataset) {
          expect(s.sampleDataset.label).toBeTruthy();
          expect(s.sampleDataset.ref).toBeTruthy();
          expect(s.needs).toMatch(/sample provided/i);
        }
      }
    }
  });

  it("seeds the composer (not send) when an example intent is clicked", async () => {
    const user = userEvent.setup();
    const onSeed = vi.fn();
    render(<ColdStartDashboard onSeed={onSeed} modules={COLD_MODULES} />);

    // Examples live inside the open card.
    await user.click(headerFor("search"));
    const first = COLD_MODULES.find((m) => m.id === "search")!.tracks[0].ex[0];
    const btn = screen.getByText(`“${first}”`);
    await user.click(btn);

    expect(onSeed).toHaveBeenCalledTimes(1);
    expect(onSeed).toHaveBeenCalledWith(first);
  });

  // The centred IntentBar was removed (single-launcher resolution of the "double
  // composer", audit C1#2). Its routing coverage is preserved here against the
  // readIntent() logic directly (the bottom composer's LanePreview uses the same
  // read), rather than via the deleted UI.
  it("readIntent classifies a SMILES/ADMET query to the Cloud lane (Drug discovery)", () => {
    const r = readIntent("screen these SMILES for hERG liabilities");
    expect(r).not.toBeNull();
    expect(r!.lane).toBe("cloud");
    expect(r!.domain).toBe("Drug discovery");
  });

  it("readIntent routes an evidence question to the Instant lane (Literature)", () => {
    const r = readIntent("what is the evidence linking this target to disease?");
    expect(r).not.toBeNull();
    expect(r!.lane).toBe("instant");
    expect(r!.domain).toBe("Literature");
  });

  it("no fabricated inventory count appears on any card (no-inventory rule §0.9)", async () => {
    const user = userEvent.setup();
    const { container } = render(<ColdStartDashboard onSeed={() => {}} modules={COLD_MODULES} />);
    // Open every card + the domain chips so all copy is in the DOM.
    for (const m of COLD_MODULES) {
      await user.click(headerFor(m.id));
    }
    await user.click(headerFor("analysis"));
    const body = within(cardFor("analysis")).getByTestId("cold-module-body");
    await user.click(within(body).getByTestId("cold-track-validated-workflows"));
    for (const d of COLD_DOMAINS) {
      await user.click(within(body).getByTestId(`cold-domain-${d.id}`));
    }
    // No "N workflows" / "N tools" style claims anywhere in the dashboard.
    expect(container.textContent || "").not.toMatch(/\d+\s*(workflows?|tools?|pipelines?)\b/i);
  });

  describe("Design & generate — modality selector (spec ColdStart)", () => {
    it("the design card is retitled away from 'Propose molecules'", () => {
      const design = COLD_MODULES.find((m) => m.id === "design")!;
      expect(design.t).not.toMatch(/propose molecules/i);
      expect(design.t.toLowerCase()).toContain("molecules");
      expect(design.t.toLowerCase()).toContain("peptides");
      expect(design.t.toLowerCase()).toContain("proteins");
    });

    it("shows the modality chip row only on the design card", async () => {
      const user = userEvent.setup();
      render(<ColdStartDashboard onSeed={() => {}} modules={COLD_MODULES} />);
      // Not present on a non-modality module.
      await user.click(headerFor("search"));
      expect(within(cardFor("search")).queryByTestId("cold-modality-pep")).toBeNull();
      // Present on the design module, one chip per modality.
      await user.click(headerFor("design"));
      const body = within(cardFor("design")).getByTestId("cold-module-body");
      for (const [k] of COLD_MODALITIES) {
        expect(within(body).getByTestId(`cold-modality-${k}`)).toBeInTheDocument();
      }
    });

    it("switching modality swaps the shown examples", async () => {
      const user = userEvent.setup();
      render(<ColdStartDashboard onSeed={() => {}} modules={COLD_MODULES} />);
      await user.click(headerFor("design"));
      const body = within(cardFor("design")).getByTestId("cold-module-body");
      const design = COLD_MODULES.find((m) => m.id === "design")!;
      const genTrack = design.tracks[0];
      // Small molecule (default) shows the sm variant.
      expect(within(body).getByText(`“${genTrack.exBy!.sm[0]}”`)).toBeInTheDocument();
      // Switch to peptide → peptide examples show, sm ones gone.
      await user.click(within(body).getByTestId("cold-modality-pep"));
      expect(within(body).getByText(`“${genTrack.exBy!.pep[0]}”`)).toBeInTheDocument();
      expect(within(body).queryByText(`“${genTrack.exBy!.sm[0]}”`)).toBeNull();
    });

    it("seeds carry the modality: peptide/protein goals name the modality, small-molecule left as-is", async () => {
      const user = userEvent.setup();
      const onSeed = vi.fn();
      render(<ColdStartDashboard onSeed={onSeed} modules={COLD_MODULES} />);
      await user.click(headerFor("design"));
      const body = within(cardFor("design")).getByTestId("cold-module-body");
      const genTrack = COLD_MODULES.find((m) => m.id === "design")!.tracks[0];

      // Small molecule seed passes through unchanged.
      await user.click(within(body).getByText(`“${genTrack.exBy!.sm[0]}”`));
      expect(onSeed).toHaveBeenLastCalledWith(genTrack.exBy!.sm[0]);

      // Peptide seed already names "peptide"/"macrocycle" so it is not double-qualified.
      onSeed.mockClear();
      await user.click(within(body).getByTestId("cold-modality-pep"));
      await user.click(within(body).getByText(`“${genTrack.exBy!.pep[0]}”`));
      const arg = onSeed.mock.calls.at(-1)![0] as string;
      expect(arg).toMatch(/peptide|macrocyc/i);
    });

    it("seedWithModality is a no-op for small molecule and qualifies otherwise", () => {
      expect(seedWithModality("Rank these candidates", "sm")).toBe("Rank these candidates");
      // A goal with no modality word gets qualified.
      expect(seedWithModality("Rank these candidates", "pep")).toBe(
        "Rank these candidates (peptide design)",
      );
      expect(seedWithModality("Rank these candidates", "bio")).toBe(
        "Rank these candidates (protein design)",
      );
      // Already naming the modality → left alone (no double-qualify).
      expect(seedWithModality("Design nanobody candidates", "bio")).toBe(
        "Design nanobody candidates",
      );
    });

    it("router self-test covers every per-modality design example (all route to a lane)", () => {
      const design = COLD_MODULES.find((m) => m.id === "design")!;
      for (const ex of design.ex) {
        const r = readIntent(ex);
        expect(r, `design example did not route: ${ex}`).not.toBeNull();
      }
      // The peptide/protein design examples read as design (cloud), not instant.
      const pepEx = design.tracks[0].exBy!.pep[0];
      expect(readIntent(pepEx)!.lane).toBe("cloud");
    });

    it("surfaces the Fold & complex track (Boltz-2 cofold) and every variant reads as Structure prediction", () => {
      const design = COLD_MODULES.find((m) => m.id === "design")!;
      const fold = design.tracks.find((t) => t.k === "Fold & complex");
      expect(fold, "design module is missing the Fold & complex track").toBeTruthy();
      const variants = [...fold!.ex, ...Object.values(fold!.exBy!).flat()];
      for (const ex of variants) {
        const r = readIntent(ex);
        expect(r?.lane, `fold example not cloud: ${ex}`).toBe("cloud");
        expect(r?.domain, `fold example not Structure prediction: ${ex}`).toBe("Structure prediction");
      }
    });
  });

  describe("readIntent()", () => {
    it("returns null for short / empty text", () => {
      expect(readIntent("")).toBeNull();
      expect(readIntent("hERG")).toBeNull();
      expect(readIntent(null)).toBeNull();
    });
    it("classifies a design intent to the cloud lane with a domain", () => {
      const r = readIntent("generate candidates for this target with drug-like properties");
      expect(r).not.toBeNull();
      expect(r!.lane).toBe("cloud");
      expect(r!.domain).toBe("Molecular design");
    });
    it("classifies a patent question to the instant lane", () => {
      const r = readIntent("who holds composition-of-matter claims on this scaffold?");
      expect(r!.lane).toBe("instant");
      expect(r!.domain).toBe("Patents");
    });
  });

  describe("router self-test: every card example routes to a lane", () => {
    // Spec 00 §0.5 — the cards make a promise about what the router understands;
    // this test is what stops the promise drifting.
    for (const m of COLD_MODULES) {
      for (const ex of m.ex) {
        it(`routes "${ex}"`, () => {
          const r = readIntent(ex);
          expect(r, `example did not route: ${ex}`).not.toBeNull();
          expect(r!.lane === "instant" || r!.lane === "cloud").toBe(true);
        });
      }
    }
  });
});
