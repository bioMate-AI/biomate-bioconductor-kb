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
import { ColdStartDashboard, COLD_MODULES, COLD_DOMAINS, readIntent } from "./cold-start-dashboard";

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
  it("renders all four function-module cards, collapsed", () => {
    render(<ColdStartDashboard onSeed={() => {}} />);
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

  it("shows the cold-start prompt heading and an intent bar", () => {
    render(<ColdStartDashboard onSeed={() => {}} />);
    expect(screen.getByText("What are you trying to do?")).toBeInTheDocument();
    expect(screen.getByTestId("cold-intent-bar")).toBeInTheDocument();
  });

  it("expands a card on click (body + tracks + examples visible) and collapses on a second click", async () => {
    const user = userEvent.setup();
    render(<ColdStartDashboard onSeed={() => {}} />);
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
    render(<ColdStartDashboard onSeed={() => {}} />);

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
    render(<ColdStartDashboard onSeed={() => {}} />);
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
    render(<ColdStartDashboard onSeed={onSeed} />);
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

  it("seeds the composer (not send) when an example intent is clicked", async () => {
    const user = userEvent.setup();
    const onSeed = vi.fn();
    render(<ColdStartDashboard onSeed={onSeed} />);

    // Examples live inside the open card.
    await user.click(headerFor("search"));
    const first = COLD_MODULES.find((m) => m.id === "search")!.tracks[0].ex[0];
    const btn = screen.getByText(`“${first}”`);
    await user.click(btn);

    expect(onSeed).toHaveBeenCalledTimes(1);
    expect(onSeed).toHaveBeenCalledWith(first);
  });

  it("intent bar seeds via Enter and via the send button", async () => {
    const user = userEvent.setup();
    const onSeed = vi.fn();
    render(<ColdStartDashboard onSeed={onSeed} />);

    const input = screen.getByTestId("cold-intent-input");
    await user.type(input, "screen these SMILES for hERG{Enter}");
    expect(onSeed).toHaveBeenCalledWith("screen these SMILES for hERG");

    onSeed.mockClear();
    await user.click(screen.getByTestId("cold-intent-send"));
    expect(onSeed).toHaveBeenCalledWith("screen these SMILES for hERG");
  });

  it("router shows a route-box with lane + domain on matching text", async () => {
    const user = userEvent.setup();
    render(<ColdStartDashboard onSeed={() => {}} />);

    // Short text: no verdict yet (>6 char gate).
    expect(screen.queryByTestId("cold-intent-route")).toBeNull();

    await user.type(screen.getByTestId("cold-intent-input"), "screen these SMILES for hERG liabilities");
    const route = screen.getByTestId("cold-intent-route");
    expect(route).toBeInTheDocument();
    expect(route).toHaveAttribute("data-lane", "cloud");
    expect(screen.getByTestId("cold-intent-route-domain")).toHaveTextContent("Drug discovery");
    // Lane label must match the lane (not merely be non-empty — a tautology).
    expect(screen.getByTestId("cold-intent-route-lane")).toHaveTextContent(/cloud/i);
  });

  it("routes an evidence question to the Instant lane", async () => {
    const user = userEvent.setup();
    render(<ColdStartDashboard onSeed={() => {}} />);
    await user.type(
      screen.getByTestId("cold-intent-input"),
      "what is the evidence linking this target to disease?",
    );
    const route = screen.getByTestId("cold-intent-route");
    expect(route).toHaveAttribute("data-lane", "instant");
    expect(screen.getByTestId("cold-intent-route-domain")).toHaveTextContent("Literature");
  });

  it("no fabricated inventory count appears on any card (no-inventory rule §0.9)", async () => {
    const user = userEvent.setup();
    const { container } = render(<ColdStartDashboard onSeed={() => {}} />);
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
