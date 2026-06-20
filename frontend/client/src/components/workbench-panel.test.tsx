/**
 * WorkbenchPanel — RTL coverage for the Stream-A pinboard surface.
 *
 * Covers: empty state, list rendering, tab open on click, unpin DELETE +
 * removal, and the Pin button POST on the embedded step-output-preview
 * header. StepOutputPreview is stubbed so we don't pull viewer internals
 * (3Dmol, density, etc.) into the test.
 */
import React from "react";
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { WorkbenchPanel } from "./workbench-panel";
import {
  PinToWorkbenchButton,
} from "./step-output-preview";

// Stub the heavy preview so we don't drag the viewer dispatcher into the test.
vi.mock("@/components/step-output-preview", async () => {
  // Keep PinToWorkbenchButton real (we test it in the last case).
  const actual = await vi.importActual<any>("./step-output-preview");
  return {
    ...actual,
    StepOutputPreview: (props: any) => (
      <div data-testid={`mock-preview-${props.file.name}`}>{props.file.name}</div>
    ),
  };
});

// Stub the toast hook so we don't need a Toaster mount.
vi.mock("@/hooks/use-toast", () => ({
  useToast: () => ({ toast: vi.fn() }),
}));

function renderWithQuery(ui: React.ReactNode) {
  const client = new QueryClient({
    defaultOptions: { queries: { retry: false, gcTime: 0, staleTime: 0 } },
  });
  return render(<QueryClientProvider client={client}>{ui}</QueryClientProvider>);
}

const samplePins = [
  {
    id: 1,
    runId: "run-abc",
    filePath: "/out/a.png",
    fileName: "plot.png",
    createdAt: "2026-06-19T10:00:00.000Z",
  },
  {
    id: 2,
    runId: "run-abc",
    filePath: "/out/de.tsv",
    fileName: "de.tsv",
    createdAt: "2026-06-19T11:00:00.000Z",
  },
];

beforeEach(() => {
  vi.restoreAllMocks();
});

afterEach(() => {
  vi.restoreAllMocks();
});

describe("WorkbenchPanel", () => {
  it("renders the empty state when GET returns no pins", async () => {
    vi.spyOn(global, "fetch").mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: async () => ({ pins: [] }),
    } as unknown as Response);

    renderWithQuery(<WorkbenchPanel projectId="proj-xyz" />);

    await waitFor(() => {
      expect(screen.getByTestId("workbench-empty")).toBeInTheDocument();
    });
    expect(screen.getByTestId("workbench-empty").textContent).toMatch(/Pin to Workbench/i);
  });

  it("renders the pin list when GET returns pins", async () => {
    vi.spyOn(global, "fetch").mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: async () => ({ pins: samplePins }),
    } as unknown as Response);

    renderWithQuery(<WorkbenchPanel projectId="proj-xyz" />);

    await waitFor(() => {
      expect(screen.getByTestId("workbench-pin-1")).toBeInTheDocument();
    });
    expect(screen.getByTestId("workbench-pin-2")).toBeInTheDocument();
    expect(screen.getByText("plot.png")).toBeInTheDocument();
    expect(screen.getByText("de.tsv")).toBeInTheDocument();
  });

  it("opens a tab and shows the preview when a sidebar pin is clicked", async () => {
    vi.spyOn(global, "fetch").mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: async () => ({ pins: samplePins }),
    } as unknown as Response);

    renderWithQuery(<WorkbenchPanel projectId="proj-xyz" />);

    const sidebarItem = await screen.findByTestId("workbench-pin-1");
    // Empty pane state initially
    expect(screen.getByTestId("workbench-pane-empty")).toBeInTheDocument();

    fireEvent.click(sidebarItem);

    await waitFor(() => {
      expect(screen.getByTestId("workbench-tab-1")).toBeInTheDocument();
    });
    expect(screen.getByTestId("mock-preview-plot.png")).toBeInTheDocument();
    expect(screen.queryByTestId("workbench-pane-empty")).not.toBeInTheDocument();
  });

  it("DELETEs and removes a pin when the unpin button is clicked", async () => {
    const fetchSpy = vi.spyOn(global, "fetch");
    // 1. Initial GET
    fetchSpy.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: async () => ({ pins: samplePins }),
    } as unknown as Response);
    // 2. DELETE
    fetchSpy.mockResolvedValueOnce({
      ok: true,
      status: 204,
      json: async () => ({}),
    } as unknown as Response);
    // 3. Re-fetch after invalidate
    fetchSpy.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: async () => ({ pins: [samplePins[1]] }),
    } as unknown as Response);

    renderWithQuery(<WorkbenchPanel projectId="proj-xyz" />);

    const unpinBtn = await screen.findByTestId("workbench-pin-1-unpin");
    fireEvent.click(unpinBtn);

    await waitFor(() => {
      expect(screen.queryByTestId("workbench-pin-1")).not.toBeInTheDocument();
    });

    // 2nd call: DELETE
    const [delUrl, delOpts] = fetchSpy.mock.calls[1];
    expect(String(delUrl)).toBe("/api/projects/proj-xyz/workbench/pins/1");
    expect((delOpts as any)?.method).toBe("DELETE");
  });
});

describe("PinToWorkbenchButton", () => {
  it("POSTs to /workbench/pins with the file payload when clicked", async () => {
    const fetchSpy = vi.spyOn(global, "fetch").mockResolvedValueOnce({
      ok: true,
      status: 201,
      json: async () => ({ pin: { id: 99, runId: "r", filePath: "/p", fileName: "x.png" } }),
      text: async () => "",
    } as unknown as Response);

    render(
      <PinToWorkbenchButton
        runId="run-1"
        file={{ name: "x.png", path: "/p", extension: "png" }}
        projectId="proj-abc"
      />,
    );

    const btn = screen.getByTestId("button-pin-to-workbench");
    fireEvent.click(btn);

    await waitFor(() => expect(fetchSpy).toHaveBeenCalledTimes(1));
    const [url, opts] = fetchSpy.mock.calls[0];
    expect(String(url)).toBe("/api/projects/proj-abc/workbench/pins");
    expect((opts as any).method).toBe("POST");
    const body = JSON.parse((opts as any).body);
    expect(body).toEqual({ runId: "run-1", filePath: "/p", fileName: "x.png" });
  });

  it("renders nothing when projectId is absent", () => {
    const { container } = render(
      <PinToWorkbenchButton
        runId="run-1"
        file={{ name: "x.png", path: "/p", extension: "png" }}
        projectId={null}
      />,
    );
    expect(container.firstChild).toBeNull();
  });
});
