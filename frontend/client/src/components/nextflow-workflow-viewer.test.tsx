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

describe("NextflowWorkflowViewer step execution controls", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  it("runs and reruns a step while updating status metadata", async () => {
    const fetchSpy = vi.spyOn(global, "fetch").mockImplementation(async (input) => {
      const url = String(input);
      if (url === "/api/workflow/step/execute") {
        return {
          ok: true,
          json: async () => ({ job_id: "job-1", state: "queued" }),
        } as Response;
      }
      if (url === "/api/workflow/step/s1/status") {
        return {
          ok: true,
          json: async () => ({ step_id: "s1", job_id: "job-1", state: "ok", outputs: ["out1"] }),
        } as Response;
      }
      throw new Error(`Unexpected fetch URL: ${url}`);
    });

    render(
      <NextflowWorkflowViewer
        workflowId="wf-1"
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
        "/api/workflow/step/execute",
        expect.objectContaining({
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            step_id: "s1",
            tool_id: "toolshed.g2.bx.psu.edu/repos/devteam/trimmomatic/trimmomatic/0.38.0",
            parameters: { quality: 20 },
            inputs: {},
          }),
        })
      )
    );
    await waitFor(() => expect(fetchSpy).toHaveBeenCalledWith("/api/workflow/step/s1/status"));
    await waitFor(() => expect(screen.getByTestId("phase-backend-state-s1")).toHaveTextContent("ok"));
    expect(screen.getByTestId("phase-run-count-s1")).toHaveTextContent("1");
    expect(screen.getByTestId("phase-last-run-s1")).not.toHaveTextContent("n/a");
    expect(screen.getByTestId("phase-started-at-s1")).not.toHaveTextContent("n/a");
    expect(screen.getByTestId("button-run-step-s1")).toHaveTextContent("Rerun Step");

    fireEvent.click(screen.getByTestId("button-run-step-s1"));

    await waitFor(() => {
      const executeCalls = fetchSpy.mock.calls.filter(([url]) => String(url) === "/api/workflow/step/execute");
      expect(executeCalls.length).toBe(2);
    });
    await waitFor(() => expect(screen.getByTestId("phase-run-count-s1")).toHaveTextContent("2"));

    fireEvent.click(screen.getByTestId("button-run-step-s1"));
    await waitFor(() => {
      const executeCalls = fetchSpy.mock.calls.filter(([url]) => String(url) === "/api/workflow/step/execute");
      expect(executeCalls.length).toBe(3);
    });
    await waitFor(() => expect(screen.getByTestId("phase-run-count-s1")).toHaveTextContent("3"));
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
