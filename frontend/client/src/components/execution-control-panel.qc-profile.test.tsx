import React from "react";
import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { ExecutionControlPanel } from "./execution-control-panel";

describe("ExecutionControlPanel QC profile wiring", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
  });

  it("fetches QC profiles and includes qcOverrides in execute config", async () => {
    const fetchMock = vi
      .spyOn(global, "fetch")
      .mockResolvedValue({
        ok: true,
        json: async () => ({
          profiles: [
            {
              id: "rnaseq_ribodepleted",
              description: "Lower alignment threshold for ribodepleted RNA-seq.",
              domain_hint: "rnaseq",
            },
          ],
        }),
      } as Response);

    const onExecute = vi.fn().mockResolvedValue(undefined);

    render(
      <ExecutionControlPanel
        workflowName="RNA workflow"
        totalSamples={100}
        totalSteps={6}
        onExecute={onExecute}
      />
    );

    await waitFor(() => {
      expect(fetchMock).toHaveBeenCalledWith("/api/qc/profiles");
    });

    fireEvent.click(screen.getByText("QC Settings"));

    expect(screen.getByText("Threshold Overrides")).toBeInTheDocument();

    fireEvent.change(screen.getByPlaceholderText("metric_key"), {
      target: { value: "alignment_rate" },
    });
    fireEvent.change(screen.getByPlaceholderText("value"), {
      target: { value: "50" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Add" }));

    fireEvent.click(screen.getByRole("button", { name: /Run 10%/i }));

    await waitFor(() => expect(onExecute).toHaveBeenCalledTimes(1));

    const executeConfig = onExecute.mock.calls[0][0];
    expect(executeConfig.qcOverrides).toEqual({ alignment_rate: 50 });
    expect(executeConfig.dataScope.sampledIds).toEqual([]);
    expect(executeConfig.tracking.milestonePercentages).toEqual([25, 50, 75, 100]);
  });
});

