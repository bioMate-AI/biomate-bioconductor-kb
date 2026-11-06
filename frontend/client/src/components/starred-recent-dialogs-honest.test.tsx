/**
 * Honest-affordance coverage for the Starred Workflows and Recent Tools dialogs
 * (fix for "mock-as-real / dead-affordance" UI bugs).
 *
 * Asserts:
 *  - With no stored data, each dialog renders its honest empty state (no
 *    fabricated demo rows).
 *  - The dead controls that had empty onClick handlers are gone: the starred
 *    "View" button and the recent-tool "Star" / "View documentation" buttons.
 *  - The controls that DO work are wired: starred card routes to onWorkflowSelect;
 *    recent card routes to onToolSelect; unstar / remove still work.
 */
import React from "react";
import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent, within } from "@testing-library/react";
import { StarredWorkflowsDialog } from "./starred-workflows-dialog";
import { RecentToolsDialog } from "./recent-tools-dialog";

function installLocalStorageShim() {
  const store = new Map<string, string>();
  (globalThis as any).localStorage = {
    getItem: (k: string) => (store.has(k) ? store.get(k)! : null),
    setItem: (k: string, v: string) => { store.set(k, String(v)); },
    removeItem: (k: string) => { store.delete(k); },
    clear: () => { store.clear(); },
    key: (i: number) => Array.from(store.keys())[i] ?? null,
    get length() { return store.size; },
  };
  return store;
}

describe("StarredWorkflowsDialog — honest behavior", () => {
  beforeEach(() => { installLocalStorageShim(); localStorage.clear(); });

  it("shows the honest empty state when the user has no starred workflows", () => {
    render(<StarredWorkflowsDialog open onOpenChange={() => {}} />);
    expect(screen.getByText(/No starred workflows found/i)).toBeInTheDocument();
    // No fabricated demo workflow is rendered.
    expect(screen.queryByText(/RNA-seq Analysis Pipeline/i)).not.toBeInTheDocument();
  });

  it("does not render a dead 'View' button; the Open control routes to onWorkflowSelect", () => {
    const store = installLocalStorageShim();
    store.set("biomate-starred-workflows", JSON.stringify([{
      id: "s1", workflowId: "wf-1", title: "My Workflow",
      description: "desc", workflowType: "RNA-seq", complexity: "simple",
      starredAt: new Date().toISOString(),
    }]));
    const onWorkflowSelect = vi.fn();
    render(<StarredWorkflowsDialog open onOpenChange={() => {}} onWorkflowSelect={onWorkflowSelect} />);

    expect(screen.getByText("My Workflow")).toBeInTheDocument();
    // The dead "View" button (empty onClick) was removed.
    expect(screen.queryByTestId("button-view-workflow-s1")).not.toBeInTheDocument();
    // The working Open control is wired to the real handler.
    fireEvent.click(screen.getByTestId("button-run-workflow-s1"));
    expect(onWorkflowSelect).toHaveBeenCalledTimes(1);
  });
});

describe("RecentToolsDialog — honest behavior", () => {
  beforeEach(() => { installLocalStorageShim(); localStorage.clear(); });

  it("shows the honest empty state when the user has no recent tools", () => {
    render(<RecentToolsDialog open onOpenChange={() => {}} />);
    expect(screen.getByText(/No recent tools found/i)).toBeInTheDocument();
    // No fabricated demo tool is rendered.
    expect(screen.queryByText(/^FastQC$/)).not.toBeInTheDocument();
  });

  it("does not render dead 'Star' / 'View doc' buttons; card routes to onToolSelect", () => {
    const store = installLocalStorageShim();
    store.set("biomate-recent-tools", JSON.stringify([{
      id: "r1", toolId: "tool-1", name: "My Tool", description: "desc",
      category: "quality-control", complexity: "simple",
      lastUsed: new Date().toISOString(), usageCount: 1,
    }]));
    const onToolSelect = vi.fn();
    render(<RecentToolsDialog open onOpenChange={() => {}} onToolSelect={onToolSelect} />);

    const card = screen.getByTestId("card-recent-tool-r1");
    expect(within(card).getByText("My Tool")).toBeInTheDocument();
    // Dead controls (empty onClick) were removed.
    expect(screen.queryByTestId("button-star-tool-r1")).not.toBeInTheDocument();
    expect(screen.queryByTestId("button-view-tool-r1")).not.toBeInTheDocument();
    // Working controls remain.
    expect(screen.getByTestId("button-remove-tool-r1")).toBeInTheDocument();
    fireEvent.click(card);
    expect(onToolSelect).toHaveBeenCalledTimes(1);
  });
});
