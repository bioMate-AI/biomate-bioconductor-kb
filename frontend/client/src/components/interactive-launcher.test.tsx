/**
 * Interactive Launcher — RTL coverage for the panel's "Open in RStudio/Jupyter/CellxGene"
 * affordance.
 *
 * Covers:
 *  - All 3 tools render in the radio group with their package badges
 *  - Selecting a tool maps to the correct backend tool_id when launched
 *  - Successful launch surfaces the entry_point_url and "Open in new tab" CTA
 *  - Failed launch surfaces the server error message
 *  - Output checkbox selection is included in the launch payload
 */
import React from "react";
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { InteractiveLauncher } from "./interactive-launcher";

const OUTPUTS = [
  { id: "ds-1", name: "dds.rds", size: 1024 * 50 },
  { id: "ds-2", name: "counts.tsv", size: 1024 * 10 },
];

describe("InteractiveLauncher", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
  });
  afterEach(() => {
    vi.clearAllMocks();
  });

  it("renders all 3 interactive environments with package badges", () => {
    render(<InteractiveLauncher open onOpenChange={() => {}} outputs={OUTPUTS} historyId="h1" />);
    expect(screen.getByText("Jupyter Notebook")).toBeInTheDocument();
    expect(screen.getByText("RStudio")).toBeInTheDocument();
    expect(screen.getByText("CellxGene")).toBeInTheDocument();
    // package preview badges
    expect(screen.getByText("DESeq2")).toBeInTheDocument();
    expect(screen.getByText("pandas")).toBeInTheDocument();
    expect(screen.getByText("DESeq2")).toBeInTheDocument();
  });

  it("posts to /api/interactive/launch with interactive_tool_rstudio when RStudio is selected", async () => {
    const fetchMock = vi.spyOn(global, "fetch").mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({
        job_id: "job-1",
        entry_point_url: "https://galaxy.dev/ie/abc",
        state: "running",
      }),
    } as Response);

    render(<InteractiveLauncher open onOpenChange={() => {}} outputs={OUTPUTS} historyId="hist-42" />);

    // Select RStudio
    fireEvent.click(screen.getByText("RStudio"));

    // Row is now a <label htmlFor="..."> wrapping the Checkbox — clicking
    // the row text fires the checkbox once via native label association
    // (no double-bind on the parent).
    fireEvent.click(screen.getByText("dds.rds"));

    // Click launch
    fireEvent.click(screen.getByRole("button", { name: /Launch RStudio/ }));

    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(1));

    const [url, opts] = fetchMock.mock.calls[0] as [string, RequestInit];
    expect(url).toBe("/api/interactive/launch");
    expect(opts.method).toBe("POST");
    const body = JSON.parse(opts.body as string);
    expect(body.tool_id).toBe("interactive_tool_rstudio");
    expect(body.inputs.history_id).toBe("hist-42");
    expect(body.inputs.dataset_ids).toEqual(["ds-1"]);
  });

  it("posts interactive_tool_jupyter_notebook when Jupyter is selected (default)", async () => {
    const fetchMock = vi.spyOn(global, "fetch").mockResolvedValue({
      ok: true,
      json: async () => ({ job_id: "j", entry_point_url: "u", state: "running" }),
    } as Response);

    render(<InteractiveLauncher open onOpenChange={() => {}} outputs={OUTPUTS} historyId="h1" />);
    fireEvent.click(screen.getByRole("button", { name: /Launch Jupyter Notebook/ }));

    await waitFor(() => expect(fetchMock).toHaveBeenCalled());
    const body = JSON.parse((fetchMock.mock.calls[0][1] as RequestInit).body as string);
    expect(body.tool_id).toBe("interactive_tool_jupyter_notebook");
  });

  it("posts interactive_tool_cellxgene when CellxGene is selected", async () => {
    const fetchMock = vi.spyOn(global, "fetch").mockResolvedValue({
      ok: true,
      json: async () => ({ job_id: "j", entry_point_url: "u", state: "running" }),
    } as Response);

    render(<InteractiveLauncher open onOpenChange={() => {}} outputs={OUTPUTS} historyId="h1" />);
    fireEvent.click(screen.getByText("CellxGene"));
    fireEvent.click(screen.getByRole("button", { name: /Launch CellxGene/ }));

    await waitFor(() => expect(fetchMock).toHaveBeenCalled());
    const body = JSON.parse((fetchMock.mock.calls[0][1] as RequestInit).body as string);
    expect(body.tool_id).toBe("interactive_tool_cellxgene");
  });

  it("shows the session card with Open-in-new-tab CTA on success", async () => {
    vi.spyOn(global, "fetch").mockResolvedValue({
      ok: true,
      json: async () => ({
        job_id: "j-1",
        entry_point_url: "https://galaxy.dev/ie/xyz",
        state: "running",
      }),
    } as Response);

    render(<InteractiveLauncher open onOpenChange={() => {}} outputs={OUTPUTS} historyId="h1" />);
    fireEvent.click(screen.getByRole("button", { name: /Launch Jupyter Notebook/ }));

    await waitFor(() => {
      expect(screen.getByText(/Jupyter Notebook Session Active/i)).toBeInTheDocument();
      expect(screen.getByRole("button", { name: /Open Jupyter Notebook in New Tab/i })).toBeInTheDocument();
    });
  });

  it("shows the server error message when launch fails", async () => {
    vi.spyOn(global, "fetch").mockResolvedValue({
      ok: false,
      status: 500,
      json: async () => ({ message: "Tool not registered in toolbox" }),
    } as Response);

    render(<InteractiveLauncher open onOpenChange={() => {}} outputs={OUTPUTS} historyId="h1" />);
    fireEvent.click(screen.getByRole("button", { name: /Launch Jupyter Notebook/ }));

    await waitFor(() => {
      expect(screen.getByText("Tool not registered in toolbox")).toBeInTheDocument();
    });
  });
});
