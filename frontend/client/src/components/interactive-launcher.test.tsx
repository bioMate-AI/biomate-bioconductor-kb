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
 *  - When an interactive tool isn't provisioned (availability probe says so),
 *    the Launch button is disabled with an honest note (no dead 400 click)
 *
 * NOTE: the launcher now probes GET /api/interactive/available on mount, so the
 * fetch mock branches by URL and assertions look up the launch call explicitly
 * (the availability probe is fetch call #0).
 */
import React from "react";
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { InteractiveLauncher } from "./interactive-launcher";
import { __resetInteractiveToolsCache } from "@/hooks/use-interactive-tools";

const OUTPUTS = [
  { id: "ds-1", name: "dds.rds", size: 1024 * 50 },
  { id: "ds-2", name: "counts.tsv", size: 1024 * 10 },
];

const AVAIL_ALL = { available: true, tools: { jupyter: true, rstudio: true, cellxgene: true } };
const AVAIL_NONE = { available: false, tools: { jupyter: false, rstudio: false, cellxgene: false } };

/** Mock fetch so GET /api/interactive/available returns `avail` and every other
 *  call (the launch POST) returns `launch`. Returns the spy. */
function mockFetch(launch: any, avail: any = AVAIL_ALL) {
  return vi.spyOn(global, "fetch").mockImplementation(async (input: any) => {
    const url = String(input);
    if (url.includes("/api/interactive/available")) {
      return { ok: true, status: 200, json: async () => avail } as Response;
    }
    return launch as Response;
  });
}

/** The launch POST call (fetch may also have been called for the availability probe). */
function launchCall(fetchMock: any) {
  return (fetchMock.mock.calls as any[]).find((c) => String(c[0]).includes("/api/interactive/launch"));
}

describe("InteractiveLauncher", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
    __resetInteractiveToolsCache();
  });
  afterEach(() => {
    vi.clearAllMocks();
    __resetInteractiveToolsCache();
  });

  it("renders all 3 interactive environments with package badges", () => {
    mockFetch({ ok: true, json: async () => ({}) });
    render(<InteractiveLauncher open onOpenChange={() => {}} outputs={OUTPUTS} historyId="h1" />);
    expect(screen.getByText("Jupyter Notebook")).toBeInTheDocument();
    expect(screen.getByText("RStudio")).toBeInTheDocument();
    expect(screen.getByText("CellxGene")).toBeInTheDocument();
    // package preview badges
    expect(screen.getByText("DESeq2")).toBeInTheDocument();
    expect(screen.getByText("pandas")).toBeInTheDocument();
  });

  it("posts to /api/interactive/launch with interactive_tool_rstudio when RStudio is selected", async () => {
    const fetchMock = mockFetch({
      ok: true,
      status: 200,
      json: async () => ({ job_id: "job-1", entry_point_url: "https://galaxy.dev/ie/abc", state: "running" }),
    });

    render(<InteractiveLauncher open onOpenChange={() => {}} outputs={OUTPUTS} historyId="hist-42" />);

    // Select RStudio
    fireEvent.click(screen.getByText("RStudio"));
    // Row is a <label> wrapping the Checkbox — clicking the text fires it once.
    fireEvent.click(screen.getByText("dds.rds"));
    // Launch enabled once availability resolves.
    await waitFor(() => expect(screen.getByRole("button", { name: /Launch RStudio/ })).not.toBeDisabled());
    fireEvent.click(screen.getByRole("button", { name: /Launch RStudio/ }));

    await waitFor(() => expect(launchCall(fetchMock)).toBeTruthy());
    const [url, opts] = launchCall(fetchMock) as [string, RequestInit];
    expect(url).toBe("/api/interactive/launch");
    expect(opts.method).toBe("POST");
    const body = JSON.parse(opts.body as string);
    expect(body.tool_id).toBe("interactive_tool_rstudio");
    expect(body.inputs.history_id).toBe("hist-42");
    expect(body.inputs.dataset_ids).toEqual(["ds-1"]);
  });

  it("posts interactive_tool_jupyter_notebook when Jupyter is selected (default)", async () => {
    const fetchMock = mockFetch({ ok: true, json: async () => ({ job_id: "j", entry_point_url: "u", state: "running" }) });

    render(<InteractiveLauncher open onOpenChange={() => {}} outputs={OUTPUTS} historyId="h1" />);
    await waitFor(() => expect(screen.getByRole("button", { name: /Launch Jupyter Notebook/ })).not.toBeDisabled());
    fireEvent.click(screen.getByRole("button", { name: /Launch Jupyter Notebook/ }));

    await waitFor(() => expect(launchCall(fetchMock)).toBeTruthy());
    const body = JSON.parse((launchCall(fetchMock)![1] as RequestInit).body as string);
    expect(body.tool_id).toBe("interactive_tool_jupyter_notebook");
  });

  it("posts interactive_tool_cellxgene when CellxGene is selected", async () => {
    const fetchMock = mockFetch({ ok: true, json: async () => ({ job_id: "j", entry_point_url: "u", state: "running" }) });

    render(<InteractiveLauncher open onOpenChange={() => {}} outputs={OUTPUTS} historyId="h1" />);
    fireEvent.click(screen.getByText("CellxGene"));
    await waitFor(() => expect(screen.getByRole("button", { name: /Launch CellxGene/ })).not.toBeDisabled());
    fireEvent.click(screen.getByRole("button", { name: /Launch CellxGene/ }));

    await waitFor(() => expect(launchCall(fetchMock)).toBeTruthy());
    const body = JSON.parse((launchCall(fetchMock)![1] as RequestInit).body as string);
    expect(body.tool_id).toBe("interactive_tool_cellxgene");
  });

  it("shows the session card with Open-in-new-tab CTA on success", async () => {
    mockFetch({
      ok: true,
      json: async () => ({ job_id: "j-1", entry_point_url: "https://galaxy.dev/ie/xyz", state: "running" }),
    });

    render(<InteractiveLauncher open onOpenChange={() => {}} outputs={OUTPUTS} historyId="h1" />);
    await waitFor(() => expect(screen.getByRole("button", { name: /Launch Jupyter Notebook/ })).not.toBeDisabled());
    fireEvent.click(screen.getByRole("button", { name: /Launch Jupyter Notebook/ }));

    await waitFor(() => {
      expect(screen.getByText(/Jupyter Notebook Session Active/i)).toBeInTheDocument();
      expect(screen.getByRole("button", { name: /Open Jupyter Notebook in New Tab/i })).toBeInTheDocument();
    });
  });

  it("shows the server error message when launch fails", async () => {
    mockFetch({ ok: false, status: 500, json: async () => ({ message: "Tool not registered in toolbox" }) });

    render(<InteractiveLauncher open onOpenChange={() => {}} outputs={OUTPUTS} historyId="h1" />);
    await waitFor(() => expect(screen.getByRole("button", { name: /Launch Jupyter Notebook/ })).not.toBeDisabled());
    fireEvent.click(screen.getByRole("button", { name: /Launch Jupyter Notebook/ }));

    await waitFor(() => {
      expect(screen.getByText("Tool not registered in toolbox")).toBeInTheDocument();
    });
  });

  it("disables Launch with an honest note when the tool isn't provisioned", async () => {
    mockFetch({ ok: true, json: async () => ({}) }, AVAIL_NONE);

    render(<InteractiveLauncher open onOpenChange={() => {}} outputs={OUTPUTS} historyId="h1" />);
    // Once the availability probe resolves to "none", Launch is disabled and an
    // honest note is shown — no dead 400 click.
    await waitFor(() => expect(screen.getByRole("button", { name: /Launch Jupyter Notebook/ })).toBeDisabled());
    expect(screen.getByText(/isn.t enabled in this environment/i)).toBeInTheDocument();
  });
});
