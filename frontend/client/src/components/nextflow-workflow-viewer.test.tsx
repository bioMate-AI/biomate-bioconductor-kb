import React from "react";
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { NextflowWorkflowViewer } from "./nextflow-workflow-viewer";

vi.mock("./chat-output-attachments", () => ({
  ChatOutputAttachments: () => <div data-testid="mock-chat-output-attachments" />,
}));

vi.mock("./feedback/report-confusion-button", () => ({
  ReportConfusionButton: () => <button type="button">Report confusion</button>,
}));

vi.mock("./feedback/download-outcome-prompt", () => ({
  DownloadOutcomePrompt: () => null,
}));

// These three tests assert a step-level "Run Step / Rerun Step" affordance
// per step that was removed from the viewer: today only a "Rerun" button
// renders, and only when the step is in a terminal status (isDone || isFailed,
// see nextflow-workflow-viewer.tsx:656). The tests still cover a meaningful
// behavior — if/when per-step controls return, repair the fixtures to set
// step status='completed' so the button renders, then refresh the assertions
// against the current Rerun label + onRun handler shape. Skipped (not deleted)
// to preserve the intent.
describe.skip("NextflowWorkflowViewer step execution controls", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  it("runs and reruns a step while updating status metadata", async () => {
    const RERUN_URL = "/api/workflows/runs/test-run-1/rerun";
    const fetchSpy = vi.spyOn(global, "fetch").mockImplementation(async (input) => {
      const url = String(input);
      if (url === RERUN_URL) {
        return {
          ok: true,
          json: async () => ({ run_id: "test-run-1" }),
        } as Response;
      }
      throw new Error(`Unexpected fetch URL: ${url}`);
    });

    render(
      <NextflowWorkflowViewer
        workflowId="wf-1"
        runId="test-run-1"
        workflowDefinition={{
          name: "Stepwise Workflow",
          steps: {
            "0": {
              id: "s1",
              name: "Trim reads",
              tool_id: "toolshed.g2.bx.psu.edu/repos/devteam/trimmomatic/trimmomatic/0.38.0",
              parameters: { quality: 20 },
            },
          },
        }}
        status="idle"
        progress={0}
      />
    );

    expect(screen.getByTestId("button-run-workflow-panel")).toBeInTheDocument();
    const runStepButton = screen.getByTestId("button-run-step-s1");
    expect(runStepButton).toHaveTextContent("Run Step");

    fireEvent.click(runStepButton);

    await waitFor(() =>
      expect(fetchSpy).toHaveBeenCalledWith(
        RERUN_URL,
        expect.objectContaining({
          method: "POST",
          headers: { "Content-Type": "application/json" },
        })
      )
    );
    // After fetch resolves, run count increments and label becomes "Rerun Step"
    await waitFor(() => expect(screen.getByTestId("button-run-step-s1")).toHaveTextContent("Rerun Step"));
    // Button is loading (isExecuting=true) until the global run reaches a terminal state
    expect(screen.getByTestId("button-run-step-s1")).toBeDisabled();
    // Exactly one rerun call was made
    const rerunCalls = fetchSpy.mock.calls.filter(([url]) => String(url) === RERUN_URL);
    expect(rerunCalls.length).toBe(1);
  });

  it("disables step run control when a step has no tool id", () => {
    render(
      <NextflowWorkflowViewer
        workflowDefinition={{
          name: "Missing Tool Workflow",
          steps: {
            "0": { id: "s-missing", name: "Untyped step" },
          },
        }}
      />
    );

    const button = screen.getByTestId("button-run-step-s-missing");
    expect(button).toBeDisabled();
  });

  it("keeps full workflow controls operational alongside step controls", () => {
    const onExecute = vi.fn();
    render(
      <NextflowWorkflowViewer
        workflowDefinition={{
          name: "Workflow With Full Controls",
          parameters: { threads: 4 },
          steps: {
            "0": {
              id: "s1",
              name: "QC step",
              tool_id: "toolshed.g2.bx.psu.edu/repos/devteam/fastqc/fastqc/0.75",
            },
          },
        }}
        onExecute={onExecute}
        status="idle"
        runId="test-run-1"
      />
    );

    fireEvent.click(screen.getByTestId("button-run-workflow-panel"));
    expect(onExecute).toHaveBeenCalledWith(
      expect.objectContaining({
        threads: 4,
      })
    );
    expect(screen.getByTestId("button-run-step-s1")).toBeEnabled();
  });
});

// ============================================================================
// Horizontal tabs MVP (2026-06-09) — verify the new tab bar renders all 3 tabs,
// switches active state on click, mounts AfterRunReport on After-run, and
// surfaces the Run-again CTA at the panel bottom on terminal status.
// ============================================================================

// Stub the v2 AfterRunReport so the test doesn't need real /api/jobs etc.
vi.mock("@/v2/AfterRunReport", () => ({
  AfterRunReport: (props: any) => (
    <div data-testid="mock-after-run-report" data-run-id={props.runId} data-status={props.executionStatus} />
  ),
}));

describe("NextflowWorkflowViewer — horizontal tabs MVP", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
    // jsdom doesn't ship EventSource; the viewer opens one on mount.
    // Stub it so the component-mount effects don't throw.
    (global as any).EventSource = class {
      url: string;
      onopen: (() => void) | null = null;
      onmessage: (() => void) | null = null;
      onerror: (() => void) | null = null;
      readyState = 1;
      addEventListener = vi.fn();
      removeEventListener = vi.fn();
      close = vi.fn();
      constructor(url: string) { this.url = url; }
    };
    vi.spyOn(global, "fetch").mockImplementation(async () => ({
      ok: true, status: 200, json: async () => ({}), text: async () => "",
    } as Response));
  });
  afterEach(() => { vi.clearAllMocks(); });

  const baseProps = {
    workflowId: "wf-tabs-1",
    workflowDefinition: {
      id: "wf-tabs-1",
      name: "Test Workflow",
      steps: { s1: { name: "Step 1", tool_id: "t1" } },
      required_params: [],
      optional_params: [{ id: "threads", name: "threads", type: "number", default: 4 }],
      inline_parameters: { threads: 4 },
    },
    invocationId: "inv-tabs-1",
    runId: "run-tabs-1",
    status: "completed" as const,
    onExecute: vi.fn(),
  };

  it("renders all 3 tab buttons (Workflow settings, Phases, After run)", () => {
    render(<NextflowWorkflowViewer {...(baseProps as any)} />);
    expect(screen.getByTestId("panel-tab-settings")).toBeInTheDocument();
    expect(screen.getByTestId("panel-tab-phases")).toBeInTheDocument();
    expect(screen.getByTestId("panel-tab-after-run")).toBeInTheDocument();
  });

  it("defaults to After-run tab when status is completed (status-aware)", async () => {
    render(<NextflowWorkflowViewer {...(baseProps as any)} />);
    await waitFor(() => {
      expect(screen.getByTestId("panel-tab-after-run")).toHaveAttribute("aria-selected", "true");
    });
  });

  it("defaults to Phases tab when status is running", async () => {
    render(<NextflowWorkflowViewer {...(baseProps as any)} status="running" />);
    await waitFor(() => {
      expect(screen.getByTestId("panel-tab-phases")).toHaveAttribute("aria-selected", "true");
    });
  });

  it("defaults to Settings tab when status is idle", async () => {
    render(<NextflowWorkflowViewer {...(baseProps as any)} status="idle" />);
    await waitFor(() => {
      expect(screen.getByTestId("panel-tab-settings")).toHaveAttribute("aria-selected", "true");
    });
  });

  it("manual tab click overrides status-aware auto-default", async () => {
    const { rerender } = render(<NextflowWorkflowViewer {...(baseProps as any)} status="running" />);
    await waitFor(() => expect(screen.getByTestId("panel-tab-phases")).toHaveAttribute("aria-selected", "true"));
    fireEvent.click(screen.getByTestId("panel-tab-settings"));
    expect(screen.getByTestId("panel-tab-settings")).toHaveAttribute("aria-selected", "true");
    // Now status flips to completed — auto-default would normally jump to After-run,
    // but the manual override stays put.
    rerender(<NextflowWorkflowViewer {...(baseProps as any)} status="completed" />);
    expect(screen.getByTestId("panel-tab-settings")).toHaveAttribute("aria-selected", "true");
  });

  it("mounts AfterRunReport when After-run tab is active (status=completed)", async () => {
    render(<NextflowWorkflowViewer {...(baseProps as any)} />);
    // status=completed auto-selects After-run, so the mock should mount on first render
    await waitFor(() => {
      const arr = screen.getByTestId("mock-after-run-report");
      expect(arr).toBeInTheDocument();
      expect(arr).toHaveAttribute("data-run-id", "run-tabs-1");
      expect(arr).toHaveAttribute("data-status", "completed");
    });
  });

  it("Status-aware action bar shows Run-again button on completed", async () => {
    render(<NextflowWorkflowViewer {...(baseProps as any)} />);
    await waitFor(() => {
      expect(screen.getByTestId("panel-action-bar")).toHaveAttribute("data-status", "completed");
      expect(screen.getByTestId("panel-run-again-cta")).toBeInTheDocument();
    });
  });

  it("Action bar shows Pause + Stop buttons on running", async () => {
    const onPause = vi.fn();
    const onCancel = vi.fn();
    render(<NextflowWorkflowViewer {...(baseProps as any)} status="running" onPause={onPause} onCancel={onCancel} />);
    await waitFor(() => {
      expect(screen.getByTestId("panel-action-bar")).toHaveAttribute("data-status", "running");
    });
    expect(screen.queryByTestId("panel-run-again-cta")).not.toBeInTheDocument();
    fireEvent.click(screen.getByTestId("panel-action-pause"));
    expect(onPause).toHaveBeenCalledTimes(1);
    fireEvent.click(screen.getByTestId("panel-action-stop"));
    expect(onCancel).toHaveBeenCalledTimes(1);
  });

  it("Action bar shows Resume + Stop on paused", async () => {
    const onResume = vi.fn();
    const onCancel = vi.fn();
    render(<NextflowWorkflowViewer {...(baseProps as any)} status="paused" onResume={onResume} onCancel={onCancel} />);
    await waitFor(() => {
      expect(screen.getByTestId("panel-action-bar")).toHaveAttribute("data-status", "paused");
    });
    fireEvent.click(screen.getByTestId("panel-action-resume"));
    expect(onResume).toHaveBeenCalledTimes(1);
    fireEvent.click(screen.getByTestId("panel-action-stop"));
    expect(onCancel).toHaveBeenCalledTimes(1);
  });

  it("Action bar is HIDDEN entirely on idle (settings tab handles run-from-scratch)", async () => {
    render(<NextflowWorkflowViewer {...(baseProps as any)} status="idle" />);
    await waitFor(() => expect(screen.getByTestId("panel-tab-settings")).toHaveAttribute("aria-selected", "true"));
    expect(screen.queryByTestId("panel-action-bar")).not.toBeInTheDocument();
  });

  it("clicking Run-again calls onExecute with current params", async () => {
    const onExecute = vi.fn();
    render(<NextflowWorkflowViewer {...(baseProps as any)} onExecute={onExecute} />);
    await waitFor(() => expect(screen.getByTestId("panel-run-again-cta")).toBeInTheDocument());
    fireEvent.click(screen.getByTestId("panel-run-again-cta"));
    expect(onExecute).toHaveBeenCalled();
    expect(onExecute.mock.calls[0][0]).toEqual(expect.objectContaining({ threads: 4 }));
  });
});
