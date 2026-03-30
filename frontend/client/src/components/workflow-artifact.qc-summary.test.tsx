import React from "react";
import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { WorkflowArtifact } from "./workflow-artifact";

vi.mock("./parameter-dialog", () => ({
  ParameterDialog: () => null,
}));
vi.mock("./citation-panel", () => ({
  CitationPanel: () => null,
}));
vi.mock("./pilot-run-panel", () => ({
  PilotRunPanel: () => null,
}));
vi.mock("./execution-control-panel", () => ({
  ExecutionControlPanel: () => null,
}));
vi.mock("./workflow-report-viewer", () => ({
  WorkflowReportViewer: () => null,
}));
vi.mock("./interactive-launcher", () => ({
  InteractiveLauncher: () => null,
}));
vi.mock("./subworkflow-extractor", () => ({
  SubworkflowExtractor: () => null,
}));
vi.mock("./qc-gate-modal", () => ({
  QCGateModal: () => null,
}));

class MockEventSource {
  onopen: ((this: EventSource, ev: Event) => any) | null = null;
  onmessage: ((this: EventSource, ev: MessageEvent) => any) | null = null;
  onerror: ((this: EventSource, ev: Event) => any) | null = null;
  addEventListener() {}
  removeEventListener() {}
  close() {}
}

describe("WorkflowArtifact QC summary panel", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
    vi.stubGlobal("EventSource", MockEventSource as unknown as typeof EventSource);
    vi.stubGlobal("fetch", vi.fn(async (input: RequestInfo | URL) => {
      const url = String(input);
      if (url.includes("/api/invocations/inv-1/qc-events")) {
        return {
          ok: true,
          json: async () => ({
            gates_triggered: 1,
            warnings_emitted: 2,
            active_profile: "rnaseq_ribodepleted",
            events: [
              {
                type: "gate",
                process_name: "STAR_ALIGN",
                failures: [{ metric: "alignment_rate", value: 8, message: "Critical alignment failure" }],
              },
              {
                type: "warning",
                process_name: "FASTP",
                warnings: [{ metric: "reads_surviving_pct", value: 72, message: "Near-threshold warning" }],
              },
            ],
            methods_text: "QC was applied with rnaseq_ribodepleted profile.",
          }),
        } as Response;
      }
      return {
        ok: true,
        json: async () => ({}),
      } as Response;
    }) as unknown as typeof fetch);

    const clipboardWrite = vi.fn();
    vi.stubGlobal("navigator", {
      ...globalThis.navigator,
      clipboard: { writeText: clipboardWrite },
    });
  });

  it("renders QC summary and copies methods text", async () => {
    render(
      <WorkflowArtifact
        workflow={{ name: "RNA workflow" }}
        steps={[]}
        isCompleted={true}
        invocationId="inv-1"
      />
    );

    await waitFor(() => {
      expect(screen.getByText("QC Summary")).toBeInTheDocument();
    });

    expect(screen.getByText("1 gate")).toBeInTheDocument();
    expect(screen.getByText("2 warnings")).toBeInTheDocument();
    expect(screen.getByText(/profile: rnaseq ribodepleted/i)).toBeInTheDocument();

    fireEvent.click(screen.getByText("QC Summary"));

    await waitFor(() => {
      expect(screen.getByText(/Critical alignment failure/)).toBeInTheDocument();
      expect(screen.getByText(/Near-threshold warning/)).toBeInTheDocument();
      expect(screen.getByText(/QC was applied with rnaseq_ribodepleted profile\./)).toBeInTheDocument();
    });

    fireEvent.click(screen.getByText("Copy methods text"));
    expect(globalThis.navigator.clipboard.writeText).toHaveBeenCalledWith(
      "QC was applied with rnaseq_ribodepleted profile."
    );
  });
});

