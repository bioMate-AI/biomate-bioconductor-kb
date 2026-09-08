/**
 * RTL tests for <ColdStartDashboard> — the cold-start function-module
 * dashboard + intent router (spec 00 §0.4/§0.5).
 *
 * Verifies: the four function-module cards render; clicking an example intent
 * seeds the composer (via onSeed, not send); the intent bar's router shows a
 * route-box (lane + domain) on matching text and stays hidden for short text;
 * and the honesty contract — no fabricated inventory counts on the cards.
 */
import { describe, it, expect, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { ColdStartDashboard, COLD_MODULES, readIntent } from "./cold-start-dashboard";

describe("<ColdStartDashboard>", () => {
  it("renders all four function-module cards", () => {
    render(<ColdStartDashboard onSeed={() => {}} />);
    expect(screen.getByTestId("cold-start-dashboard")).toBeInTheDocument();
    for (const m of COLD_MODULES) {
      expect(screen.getByTestId(`cold-module-${m.id}`)).toBeInTheDocument();
    }
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

  it("seeds the composer (not send) when an example intent is clicked", async () => {
    const user = userEvent.setup();
    const onSeed = vi.fn();
    render(<ColdStartDashboard onSeed={onSeed} />);

    const first = COLD_MODULES[0].ex[0];
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
    expect(screen.getByTestId("cold-intent-route-lane").textContent).toBeTruthy();
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

  it("no fabricated inventory count appears on any card (no-inventory rule §0.15.1)", () => {
    const { container } = render(<ColdStartDashboard onSeed={() => {}} />);
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
});
