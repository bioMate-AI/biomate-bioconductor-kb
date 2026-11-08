/**
 * ConnectorsDialog — RTL coverage for spec 00 §0.9 additions:
 *   §0.9.3 Residency markers  — every row shows where it runs; honest
 *          "unspecified" when a connector declares no residency.
 *   §0.9.1 Declared facts     — needs / produces / where-it-runs, with an
 *          honest "not declared" where a fact is absent.
 *   §0.9.2 Three scopes       — Account / Project / Request selector per row,
 *          one library one state (persisted + read back).
 *
 * Also asserts the pre-existing behaviour (DB select toggle) is intact.
 */
import React from "react";
import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { render, screen, within, fireEvent } from "@testing-library/react";
import { ConnectorsDialog } from "./connectors-dialog";
import {
  residencyDisplay,
  RESIDENCY,
  RESIDENCY_UNSPECIFIED,
} from "./connector-residency";

function open() {
  return render(<ConnectorsDialog open onOpenChange={() => {}} />);
}

beforeEach(() => {
  localStorage.clear();
});
afterEach(() => {
  localStorage.clear();
});

describe("connector-residency model (pure)", () => {
  it("maps a known residency to its label + why", () => {
    const d = residencyDisplay("cloud");
    expect(d.known).toBe(true);
    expect(d.label).toBe(RESIDENCY.cloud.label);
    expect(d.why).toBe("data leaves the estate");
  });

  it("falls back to an honest 'unspecified' when residency is undeclared", () => {
    const d = residencyDisplay(undefined);
    expect(d.known).toBe(false);
    expect(d.label).toBe(RESIDENCY_UNSPECIFIED.label);
    expect(d.label).toMatch(/unspecified/);
  });
});

describe("<ConnectorsDialog> residency markers (§0.9.3)", () => {
  it("renders a residency legend covering all five values", () => {
    open();
    const legend = screen.getByTestId("residency-legend");
    ["cloud", "on-prem", "mounted", "this machine", "prompt only"].forEach(v =>
      expect(within(legend).getByText(new RegExp(v.replace(/[-]/g, "\\-"), "i"))).toBeInTheDocument(),
    );
  });

  it("marks a public database row as cloud (data leaves the estate)", () => {
    open();
    const row = screen.getByTestId("connector-row-UniProt / Swiss-Prot");
    const badge = within(row).getByTestId("residency-badge");
    expect(badge).toHaveAttribute("data-residency", "cloud");
    expect(badge).toHaveTextContent("cloud");
  });

  it("shows residency on EVERY row — no blank markers within a tab", () => {
    open();
    const table = screen.getByTestId("connector-table");
    const badges = within(table).getAllByTestId("residency-badge");
    const rows = within(table).getAllByTestId(/^connector-row-/);
    // one badge per row, none missing
    expect(badges.length).toBe(rows.length);
    badges.forEach(b => expect(b.getAttribute("data-residency")).toBeTruthy());
  });

  it("shows an honest 'unspecified' badge for a connector that declares no residency", () => {
    open();
    // Switch to the AI tab; Open-Claw declares no residency.
    fireEvent.click(screen.getByTestId("connector-tab-ai"));
    const row = screen.getByTestId("connector-row-Open-Claw");
    const badge = within(row).getByTestId("residency-badge");
    expect(badge).toHaveAttribute("data-residency", "unspecified");
    expect(badge).toHaveTextContent(/unspecified/i);
  });

  it("marks the self-hosted local runner as 'this machine'", () => {
    open();
    fireEvent.click(screen.getByTestId("connector-tab-ai"));
    const row = screen.getByTestId("connector-row-Ollama");
    const badge = within(row).getByTestId("residency-badge");
    expect(badge).toHaveAttribute("data-residency", "local");
    expect(badge).toHaveTextContent(/this machine/i);
  });
});

describe("<ConnectorsDialog> declared facts (§0.9.1)", () => {
  it("renders needs / produces / where-it-runs for a fully-declared connector", () => {
    open();
    fireEvent.click(screen.getByTestId("connector-tab-ai"));
    const row = screen.getByTestId("connector-row-Anthropic Claude");
    const needs = within(row).getByTestId("fact-needs");
    const produces = within(row).getByTestId("fact-produces");
    const runs = within(row).getByTestId("fact-where it runs");
    expect(needs).toHaveAttribute("data-declared", "yes");
    expect(needs).toHaveTextContent(/API key/);
    expect(produces).toHaveAttribute("data-declared", "yes");
    expect(runs).toHaveAttribute("data-declared", "yes");
  });

  it("renders an honest 'not declared' for facts a connector does not state", () => {
    open();
    // Public DB rows declare residency (cloud) but not needs/produces/runsIn.
    const row = screen.getByTestId("connector-row-UniProt / Swiss-Prot");
    const produces = within(row).getByTestId("fact-produces");
    expect(produces).toHaveAttribute("data-declared", "no");
    expect(produces).toHaveTextContent(/not declared/i);
  });
});

describe("<ConnectorsDialog> three scopes (§0.9.2)", () => {
  it("defaults every connector to Account scope (connected, not switched on)", () => {
    open();
    const row = screen.getByTestId("connector-row-UniProt / Swiss-Prot");
    const selector = within(row).getByTestId("scope-selector");
    expect(selector).toHaveAttribute("data-scope", "account");
  });

  it("lets a row switch scope to Project and persists it (one library, one state)", () => {
    open();
    const name = "UniProt / Swiss-Prot";
    const row = screen.getByTestId(`connector-row-${name}`);
    fireEvent.click(within(row).getByTestId(`scope-${name}-project`));
    expect(within(row).getByTestId("scope-selector")).toHaveAttribute("data-scope", "project");
    // persisted to the shared store
    const stored = JSON.parse(localStorage.getItem("biomate-connector-scopes") || "{}");
    expect(stored[name]).toBe("project");
  });

  it("reads scope back from the shared store on mount (one state)", () => {
    localStorage.setItem(
      "biomate-connector-scopes",
      JSON.stringify({ "UniProt / Swiss-Prot": "request" }),
    );
    open();
    const row = screen.getByTestId("connector-row-UniProt / Swiss-Prot");
    expect(within(row).getByTestId("scope-selector")).toHaveAttribute("data-scope", "request");
  });

  it("changing scope does not toggle the row's selected state (independent controls)", () => {
    localStorage.setItem("biomate-active-databases", JSON.stringify([]));
    open();
    const name = "UniProt / Swiss-Prot";
    const row = screen.getByTestId(`connector-row-${name}`);
    // clicking the scope button must not select the DB
    fireEvent.click(within(row).getByTestId(`scope-${name}-project`));
    const selected = JSON.parse(localStorage.getItem("biomate-active-databases") || "[]");
    expect(selected).not.toContain(name);
  });
});

describe("<ConnectorsDialog> existing behaviour intact", () => {
  it("toggles a database's selected state on row click", () => {
    localStorage.setItem("biomate-active-databases", JSON.stringify([]));
    open();
    const row = screen.getByTestId("connector-row-UniProt / Swiss-Prot");
    fireEvent.click(row); // row click toggles selection
    const selected = JSON.parse(localStorage.getItem("biomate-active-databases") || "[]");
    expect(selected).toContain("UniProt / Swiss-Prot");
  });
});


describe("Workspace Connections panel", () => {
  it("renders in the workspace without a modal and exposes the real connection surfaces", () => {
    render(<ConnectorsDialog embedded open onOpenChange={() => {}} />);
    expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "Connectors" })).toBeInTheDocument();
    for (const tab of ["databases", "ai", "skills", "mcp"]) {
      expect(screen.getByTestId(`connector-tab-${tab}`)).toBeInTheDocument();
    }
  });
});

 describe('embedded connector navigation', () => {
  it('keeps a real Close action separate from cancelling the add flow', () => {
   const close = vi.fn(); render(<ConnectorsDialog embedded open onOpenChange={close} />);
   fireEvent.click(screen.getByText('Add a connector'));
   expect(screen.getByTestId('add-connector-flow')).toBeInTheDocument();
   fireEvent.click(screen.getByText('Cancel adding'));
   expect(screen.queryByTestId('add-connector-flow')).toBeNull();
   expect(close).not.toHaveBeenCalled();
   fireEvent.click(screen.getByTestId('connectors-close'));
   expect(close).toHaveBeenCalledWith(false);
  });
  it('keeps long add forms inside a bounded scroll body and preserves persistent close', () => {
   render(<ConnectorsDialog embedded open onOpenChange={() => {}} />);
   fireEvent.click(screen.getByText('Add a connector'));
   const scroll = screen.getByTestId('connectors-scroll');
   expect(scroll).toContainElement(screen.getByTestId('add-connector-flow'));
   expect(scroll.style.minHeight).toBe('0');
   expect(scroll.style.overflowY).toBe('auto');
   expect(scroll).not.toContainElement(screen.getByTestId('connectors-close'));
  });
 });

describe('connector setup navigation', () => {
  it('returns from a chosen setup to the picker, then cancels back to the original tab', () => {
    const close = vi.fn();
    render(<ConnectorsDialog open embedded onOpenChange={close} />);
    fireEvent.click(screen.getByTestId('connector-tab-ai'));
    fireEvent.click(screen.getByRole('button', {name: 'Add a connector'}));
    expect(screen.queryByTestId('connector-row-Ollama')).not.toBeInTheDocument();
    expect(screen.queryByText('Configure model providers and API keys')).not.toBeInTheDocument();
    fireEvent.click(screen.getByTestId('add-kind-setup-database'));
    expect(screen.getByTestId('connector-setup-back')).toBeInTheDocument();
    expect(screen.getByTestId('private-db-section')).toBeInTheDocument();
    fireEvent.click(screen.getByTestId('connector-setup-back'));
    expect(screen.getByTestId('add-connector-flow')).toBeInTheDocument();
    expect(screen.queryByTestId('private-db-section')).not.toBeInTheDocument();
    expect(screen.queryByText('Configure model providers and API keys')).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', {name: 'Cancel adding'}));
    expect(screen.queryByTestId('add-connector-flow')).not.toBeInTheDocument();
    expect(screen.getByTestId('connector-row-Ollama')).toBeInTheDocument();
    fireEvent.click(screen.getByTestId('connectors-close'));
    expect(close).toHaveBeenCalledWith(false);
  });
});
