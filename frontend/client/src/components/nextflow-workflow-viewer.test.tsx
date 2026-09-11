import React, { act } from "react";
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { NextflowWorkflowViewer, buildStepDetailStep, deriveRunKind } from "./nextflow-workflow-viewer";

vi.mock("./chat-output-attachments", () => ({
  ChatOutputAttachments: () => <div data-testid="mock-chat-output-attachments" />,
}));

vi.mock("./feedback/report-confusion-button", () => ({
  ReportConfusionButton: () => <button type="button">Report confusion</button>,
}));

vi.mock("./feedback/download-outcome-prompt", () => ({
  DownloadOutcomePrompt: () => null,
}));

// Per-step execution controls — CURRENT behavior (rewritten 2026-09-11, was
// describe.skip). The old suite asserted an always-visible "Run Step / Rerun
// Step" affordance that was removed: today the per-step Rerun button
// (button-run-step-<id>) + full-view button render ONLY when the step is in a
// terminal status (isDone || isFailed, nextflow-workflow-viewer.tsx:768-781),
// and clicking Rerun POSTs /api/workflows/runs/<runId>/rerun (handleRunStep,
// L1389). These tests drive a step to terminal state via a live step_state SSE
// event (the real product path) and assert the affordance matrix + the rerun
// call — real coverage, no skip.
describe("NextflowWorkflowViewer — per-step execution controls (current affordance)", () => {
  let esHandlers: Record<string, (ev: MessageEvent) => void> = {};
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let fetchSpy: any;

  const dispatchSSE = (type: string, payload: unknown) => {
    const handler = esHandlers[type];
    if (!handler) throw new Error(`No SSE handler registered for "${type}"`);
    act(() => {
      handler({ data: JSON.stringify(payload) } as MessageEvent);
    });
  };

  const runningProps = {
    workflowId: "wf-step-1",
    workflowDefinition: {
      id: "wf-step-1",
      name: "Stepwise Workflow",
      // step keys become step ids; s2 is the later phase so it starts
      // genuinely pending under the running-status progress heuristic.
      steps: {
        s1: { name: "Align reads", tool_id: "t1" },
        s2: { name: "Quantify", tool_id: "t2", parameters: { threads: 4 } },
      },
      required_params: [],
      optional_params: [],
      inline_parameters: {},
    },
    invocationId: "inv-step-1", // SSE effect is gated on invocationId
    runId: "run-step-1",
    progress: 0,
    onExecute: vi.fn(),
  };

  beforeEach(() => {
    vi.restoreAllMocks();
    esHandlers = {};
    (global as any).EventSource = class {
      url: string;
      onopen: (() => void) | null = null;
      onmessage: (() => void) | null = null;
      onerror: (() => void) | null = null;
      readyState = 1;
      constructor(url: string) { this.url = url; }
      addEventListener(type: string, cb: (ev: MessageEvent) => void) { esHandlers[type] = cb; }
      removeEventListener = vi.fn();
      close = vi.fn();
    };
    fetchSpy = vi.spyOn(global, "fetch").mockImplementation(async () => ({
      ok: true, status: 200, json: async () => ({ run_id: "run-step-1" }), text: async () => "",
    } as Response));
  });
  afterEach(() => { vi.clearAllMocks(); });

  it("shows NO per-step Rerun/full-view button while a step is pending", async () => {
    render(<NextflowWorkflowViewer {...(runningProps as any)} status="running" />);
    // Phases tab auto-selected for running; s2 starts genuinely pending.
    const card = await screen.findByTestId("phase-card-s2");
    expect(card).toHaveAttribute("data-status", "pending");
    // The terminal-only affordances must be absent on a pending step.
    expect(screen.queryByTestId("button-run-step-s2")).toBeNull();
    expect(screen.queryByTestId("button-full-step-view-s2")).toBeNull();
  });

  it("reveals the Rerun + full-view affordance once a step reaches a terminal state", async () => {
    render(<NextflowWorkflowViewer {...(runningProps as any)} status="running" />);
    await screen.findByTestId("phase-card-s2");
    await waitFor(() => expect(typeof esHandlers["step_state"]).toBe("function"));

    // Live event drives s2 to completed — the only thing that moves it.
    dispatchSSE("step_state", { step_id: "s2", step_state: "completed" });

    const rerun = await screen.findByTestId("button-run-step-s2");
    expect(rerun).toHaveTextContent("Rerun");
    expect(rerun).toBeEnabled();
    expect(screen.getByTestId("button-full-step-view-s2")).toBeInTheDocument();
  });

  it("clicking Rerun on a terminal step POSTs /rerun exactly once", async () => {
    render(<NextflowWorkflowViewer {...(runningProps as any)} status="running" />);
    await screen.findByTestId("phase-card-s2");
    await waitFor(() => expect(typeof esHandlers["step_state"]).toBe("function"));
    dispatchSSE("step_state", { step_id: "s2", step_state: "completed" });

    const rerun = await screen.findByTestId("button-run-step-s2");
    const RERUN_URL = "/api/workflows/runs/run-step-1/rerun";
    // Ignore SSE/other fetches the component made on mount; count only /rerun.
    const before = fetchSpy.mock.calls.filter(([u]: any[]) => String(u) === RERUN_URL).length;
    fireEvent.click(rerun);
    await waitFor(() =>
      expect(fetchSpy).toHaveBeenCalledWith(
        RERUN_URL,
        expect.objectContaining({ method: "POST" })
      )
    );
    const after = fetchSpy.mock.calls.filter(([u]: any[]) => String(u) === RERUN_URL).length;
    expect(after - before).toBe(1);
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

  it("panel-foot shows Run-again button on completed (action-bar not rendered for terminal states)", async () => {
    render(<NextflowWorkflowViewer {...(baseProps as any)} />);
    await waitFor(() => {
      // panel-action-bar is only rendered for running/paused; completed state
      // moves the Run-again CTA into panel-foot instead.
      expect(screen.queryByTestId("panel-action-bar")).not.toBeInTheDocument();
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

// ─────────────────────────────────────────────────────────────────────────────
// Run-button hard gate on requiredUnfilled (audit fix, 2026-06-11)
// Idle/pending_review runs must NOT submit when any global required param is
// still empty. Re-runs of completed/failed runs ignore the gate (they re-use
// prior params, not the current empty inline strip).
// ─────────────────────────────────────────────────────────────────────────────
describe("NextflowWorkflowViewer — run-button hard gate", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
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

  const baseGated = {
    workflowId: "wf-gate-1",
    workflowDefinition: {
      id: "wf-gate-1",
      name: "Gate Test Workflow",
      steps: { s1: { name: "Step 1", tool_id: "t1" } },
      // One required global param + one optional with a default.
      required_params: [
        { id: "reads_fwd", name: "reads_fwd", required: true, type: "file" },
      ],
      optional_params: [
        { id: "threads", name: "threads", type: "number", default: 4 },
      ],
      // Required param NOT yet populated → inline_parameters omits it on purpose.
      inline_parameters: { threads: 4 },
    },
    invocationId: "inv-gate-1",
    runId: "run-gate-1",
    onExecute: vi.fn(),
  };

  it("disables the Run button on idle when a required global param is empty", async () => {
    render(<NextflowWorkflowViewer {...(baseGated as any)} status="idle" />);
    const btn = await screen.findByTestId("button-run-workflow-panel");
    expect(btn).toBeDisabled();
    expect(btn).toHaveAttribute("data-required-unfilled", "1");
    expect(btn).toHaveAttribute("title", expect.stringMatching(/Fill in 1 required parameter/i));
  });

  it("ENables the Run button once the required param is filled", async () => {
    const filled = {
      ...baseGated,
      workflowDefinition: {
        ...baseGated.workflowDefinition,
        inline_parameters: { threads: 4, reads_fwd: "/data/sample.fastq" },
      },
    };
    render(<NextflowWorkflowViewer {...(filled as any)} status="idle" />);
    const btn = await screen.findByTestId("button-run-workflow-panel");
    expect(btn).not.toBeDisabled();
    expect(btn).toHaveAttribute("data-required-unfilled", "0");
  });

  it("does not gate re-runs on completed (uses the prior run's params)", async () => {
    // Even with the required field empty in the inline strip, a completed run
    // should still allow Run-again (it re-submits the params from the previous run).
    render(<NextflowWorkflowViewer {...(baseGated as any)} status="completed" />);
    // On completed, the primary CTA is in the action bar (Run again), not the
    // sticky footer button. Verify the action-bar Run-again is enabled.
    await waitFor(() => expect(screen.getByTestId("panel-run-again-cta")).toBeInTheDocument());
    expect(screen.getByTestId("panel-run-again-cta")).not.toBeDisabled();
  });
});

// Full step view wiring (spec-08). buildStepDetailStep maps the viewer's real
// step objects onto StepDetailStep. The contract that matters: it passes real
// data through and OMITS fields the run does not report (rather than inventing
// them), so StepDetail can show its honest empty states.
describe("buildStepDetailStep — real-data mapping, no fabrication", () => {
  it("maps id/name/processName, scalar params, and outputFiles through unchanged", () => {
    const step = {
      id: "s1",
      name: "salmon_quant",
      processName: "NFCORE_RNASEQ:SALMON_QUANT",
      status: "completed",
      parameters: { libType: "A", numBootstraps: 100, threads: 4 },
      outputFiles: [
        { name: "quant.sf", path: "s1/quant.sf", extension: "tsv" },
        { name: "logs.txt", path: "s1/logs.txt", extension: "txt" },
      ],
    };
    const mapped = buildStepDetailStep(step);
    expect(mapped.id).toBe("s1");
    expect(mapped.name).toBe("salmon_quant");
    expect(mapped.processName).toBe("NFCORE_RNASEQ:SALMON_QUANT");
    expect(mapped.parameters).toEqual({ libType: "A", numBootstraps: 100, threads: 4 });
    expect(mapped.outputs).toEqual([
      { name: "quant.sf", path: "s1/quant.sf", extension: "tsv" },
      { name: "logs.txt", path: "s1/logs.txt", extension: "txt" },
    ]);
  });

  it("omits tool/toolVersion/duration/inputs — never fabricated (honest empty state)", () => {
    const mapped = buildStepDetailStep({ id: "s2", name: "step2", status: "failed" });
    expect(mapped.tool).toBeUndefined();
    expect(mapped.toolVersion).toBeUndefined();
    expect(mapped.duration).toBeUndefined();
    expect(mapped.inputs).toBeUndefined();
  });

  it("drops object-typed param metadata placeholders, keeping scalar runtime values", () => {
    const mapped = buildStepDetailStep({
      id: "s3",
      name: "step3",
      parameters: {
        threads: 8,                                   // scalar → kept
        keep: true,                                   // scalar → kept
        schemaMeta: { type: "integer", default: 30 }, // object placeholder → dropped
      },
    });
    expect(mapped.parameters).toEqual({ threads: 8, keep: true });
  });

  it("yields empty outputs and undefined parameters when the step reported neither", () => {
    const mapped = buildStepDetailStep({ id: "s4", name: "step4" });
    expect(mapped.outputs).toEqual([]);
    expect(mapped.parameters).toBeUndefined();
  });

  it("derives a missing extension from the file name rather than inventing one", () => {
    const mapped = buildStepDetailStep({
      id: "s5",
      name: "step5",
      outputFiles: [{ name: "report.html", path: "s5/report.html" }],
    });
    expect(mapped.outputs?.[0]?.extension).toBe("html");
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// Real-time SSE status tracking (CLAUDE.md CRITICAL; audit gap #2, 2026-09-09).
//
// The other suites above stub EventSource as an INERT object (addEventListener =
// vi.fn()) and hand the component a static `status`/step-`status` prop, then
// assert the final render. That cannot catch a stuck spinner or a missed
// terminal transition — a broken step_state handler ships green.
//
// This suite installs a LIVE-DISPATCH MockEventSource that stores each
// addEventListener handler by event type. A test then dispatches a real
// "step_state" MessageEvent and asserts the phase card's data-status attribute
// actually FLIPS pending → running (a real transition observed in the DOM, not
// a final-state prop). The step never starts running — the SSE event is the
// only thing that moves it — so if the step_state → setStepExecutionById →
// phase.status wiring breaks, this test fails.
// ─────────────────────────────────────────────────────────────────────────────
describe("NextflowWorkflowViewer — real-time SSE status transitions (live dispatch)", () => {
  // Captures the handlers registered on the EventSource the component opens.
  let esHandlers: Record<string, (ev: MessageEvent) => void> = {};
  let esInstances = 0;

  // Dispatch an SSE event to the component exactly the way the browser would:
  // the backend emits a named event, the browser invokes the matching
  // addEventListener handler with a MessageEvent whose `data` is a JSON string.
  const dispatchSSE = (type: string, payload: unknown) => {
    const handler = esHandlers[type];
    if (!handler) throw new Error(`No SSE handler registered for "${type}"`);
    act(() => {
      handler({ data: JSON.stringify(payload) } as MessageEvent);
    });
  };

  beforeEach(() => {
    vi.restoreAllMocks();
    esHandlers = {};
    esInstances = 0;
    (global as any).EventSource = class {
      url: string;
      onopen: (() => void) | null = null;
      onmessage: (() => void) | null = null;
      onerror: (() => void) | null = null;
      readyState = 1;
      constructor(url: string) {
        this.url = url;
        esInstances += 1;
      }
      // Store the real handler so the test can dispatch to it later.
      addEventListener(type: string, cb: (ev: MessageEvent) => void) {
        esHandlers[type] = cb;
      }
      removeEventListener = vi.fn();
      close = vi.fn();
    };
    vi.spyOn(global, "fetch").mockImplementation(async () => ({
      ok: true, status: 200, json: async () => ({}), text: async () => "",
    } as Response));
  });
  afterEach(() => { vi.clearAllMocks(); });

  // Two steps + progress=0. The viewer's progress heuristic (nextflow-workflow-
  // viewer.tsx L1472-1477) makes the FIRST phase "running" and every later phase
  // "pending" when status=running. So s2 starts genuinely pending — the ONLY
  // thing that can move it to "running" is a step_state SSE event for s2. That
  // makes the flip a real SSE-driven transition, not the status prop.
  const runningProps = {
    workflowId: "wf-sse-1",
    workflowDefinition: {
      id: "wf-sse-1",
      name: "SSE Workflow",
      // stepKeys become step ids (no explicit step.id) → step_state must
      // reference step_id "s2" to move the second card.
      steps: {
        s1: { name: "Align reads", tool_id: "t1" },
        s2: { name: "Quantify", tool_id: "t2" },
      },
      required_params: [],
      optional_params: [],
      inline_parameters: {},
    },
    invocationId: "inv-sse-1", // REQUIRED — SSE effect is gated on invocationId
    runId: "run-sse-1",
    progress: 0,
    onExecute: vi.fn(),
  };

  it("opens the SSE stream and registers a step_state listener", async () => {
    render(<NextflowWorkflowViewer {...(runningProps as any)} status="running" />);
    await waitFor(() => {
      expect(esInstances).toBeGreaterThan(0);
      expect(typeof esHandlers["step_state"]).toBe("function");
    });
  });

  it("flips a phase card data-status pending → running when a step_state SSE event arrives", async () => {
    render(<NextflowWorkflowViewer {...(runningProps as any)} status="running" />);

    // Phases tab is auto-selected for running status. s2 (the later phase) starts
    // genuinely pending — nothing but an SSE event can move it.
    const card = await screen.findByTestId("phase-card-s2");
    expect(card).toHaveAttribute("data-status", "pending");

    // Wait for the SSE listener to be wired before dispatching.
    await waitFor(() => expect(typeof esHandlers["step_state"]).toBe("function"));

    // Live event: backend reports step s2 has started running.
    dispatchSSE("step_state", { step_id: "s2", step_state: "running" });

    // The card must reflect the live transition — this is the assertion the
    // static-prop tests could never make.
    await waitFor(() => {
      expect(screen.getByTestId("phase-card-s2")).toHaveAttribute("data-status", "running");
    });
  });

  it("advances the same card running → completed on a terminal step_state event", async () => {
    render(<NextflowWorkflowViewer {...(runningProps as any)} status="running" />);
    const card = await screen.findByTestId("phase-card-s2");
    expect(card).toHaveAttribute("data-status", "pending");
    await waitFor(() => expect(typeof esHandlers["step_state"]).toBe("function"));

    dispatchSSE("step_state", { step_id: "s2", step_state: "running" });
    await waitFor(() =>
      expect(screen.getByTestId("phase-card-s2")).toHaveAttribute("data-status", "running")
    );

    dispatchSSE("step_state", { step_id: "s2", step_state: "completed" });
    await waitFor(() =>
      expect(screen.getByTestId("phase-card-s2")).toHaveAttribute("data-status", "completed")
    );
  });

  it("shows the Restart CTA and a failed overall badge when status=failed", async () => {
    render(<NextflowWorkflowViewer {...(runningProps as any)} status="failed" />);

    await waitFor(() => {
      expect(screen.getByTestId("workflow-overall-status-badge")).toHaveAttribute(
        "data-status",
        "failed"
      );
    });
    // No cached-failure metadata → not resumable → footer CTA reads "Restart".
    const cta = screen.getByTestId("button-run-workflow-panel");
    expect(cta).toHaveTextContent("Restart");
    // A failed run must NOT surface a "Run again" success CTA.
    expect(screen.queryByTestId("panel-run-again-cta")).not.toBeInTheDocument();
  });
});

// Spec 13 §13.4: the kicker's run KIND word must reflect what the run actually
// is — "Design run" / "Ad-hoc · sandbox" / "Training run" — and never read
// "Workflow" for a run that is not one. A genuine pipeline defaults to Workflow.
describe("deriveRunKind — run card kind by domain / mode (Spec 13 §13.4)", () => {
  it("defaults a routed pipeline to 'Workflow'", () => {
    expect(deriveRunKind({ domain: "transcriptomics" })).toBe("Workflow");
    expect(deriveRunKind({ domain: "genomics" })).toBe("Workflow");
    expect(deriveRunKind({ domain: "drug_discovery" })).toBe("Workflow");
    expect(deriveRunKind({})).toBe("Workflow");
    expect(deriveRunKind(undefined)).toBe("Workflow");
  });

  it("labels a design domain as 'Design run', not 'Workflow'", () => {
    expect(deriveRunKind({ domain: "design_generate" })).toBe("Design run");
    expect(deriveRunKind({ domain: "molecular_design" })).toBe("Design run");
  });

  it("labels an ad-hoc / data-analysis sandbox as 'Ad-hoc · sandbox'", () => {
    expect(deriveRunKind({ domain: "data_analysis" })).toBe("Ad-hoc · sandbox");
    expect(deriveRunKind({ mode: "sandbox" })).toBe("Ad-hoc · sandbox");
  });

  it("labels a model-training harness as 'Training run'", () => {
    expect(deriveRunKind({ domain: "model_training" })).toBe("Training run");
    expect(deriveRunKind({ run_kind: "training" })).toBe("Training run");
  });

  it("honours an explicit run_kind / kind / mode field over the domain", () => {
    // A design run filed under a chemistry domain must still read "Design run".
    expect(deriveRunKind({ domain: "drug_discovery", run_kind: "design" })).toBe("Design run");
    expect(deriveRunKind({ domain: "transcriptomics", kind: "sandbox" })).toBe("Ad-hoc · sandbox");
  });
});
