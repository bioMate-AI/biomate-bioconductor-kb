/**
 * ParameterDialog — RTL coverage for required-field validation gate.
 *
 * Before this commit, handleSave called onSave unconditionally, so a user
 * could click "Save Changes" with empty required fields and the workflow
 * would launch (and then fail in Nextflow with a cryptic input error).
 * The new gate blocks save and surfaces a banner + per-field error styling
 * until required fields are filled.
 */
import React from "react";
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { ParameterDialog } from "./parameter-dialog";

// Block the GalaxyDatasetBrowser dialog — it tries to fetch histories on mount.
vi.mock("./galaxy-dataset-browser", () => ({
  GalaxyDatasetBrowser: () => null,
}));

const step = {
  id: "step-1",
  name: "Trim reads",
  tool: "trimmomatic/0.38.0",
  parameters: {},
};

beforeEach(() => {
  vi.restoreAllMocks();
  // The dialog fetches schema from /api/galaxy/tools/.../schema. Return a
  // schema with two required fields and one optional.
  vi.spyOn(global, "fetch").mockResolvedValue({
    ok: true,
    json: async () => ({
      inputs: [
        { name: "reads_fwd", type: "data", optional: false, format: "fastq" },
        { name: "min_length", type: "integer", optional: false, default: 36 },
        { name: "trailing_q", type: "integer", optional: true, default: 20 },
      ],
    }),
  } as Response);
});
afterEach(() => { vi.clearAllMocks(); });

describe("ParameterDialog — required-field validation", () => {
  it("blocks save and shows the missing-required banner when required fields are empty", async () => {
    const onSave = vi.fn();
    render(
      <ParameterDialog open onOpenChange={() => {}} step={step as any} onSave={onSave} />
    );

    // Wait for schema to render
    await waitFor(() => {
      expect(screen.getByText("reads_fwd")).toBeInTheDocument();
    });

    // Clear the required text field (Galaxy sometimes prefills empty string anyway)
    fireEvent.click(screen.getByRole("button", { name: /Save Changes/i }));

    await waitFor(() => {
      expect(screen.getByTestId("param-dialog-missing-required")).toBeInTheDocument();
    });
    expect(onSave).not.toHaveBeenCalled();
  });

  it("allows save once all required fields are filled", async () => {
    const onSave = vi.fn();
    render(
      <ParameterDialog open onOpenChange={() => {}} step={step as any} onSave={onSave} />
    );

    await waitFor(() => expect(screen.getByText("reads_fwd")).toBeInTheDocument());

    // Fill the required file path
    const readsInput = screen.getByPlaceholderText(/Dataset \(fastq\)/i);
    fireEvent.change(readsInput, { target: { value: "/data/sample.fastq" } });

    // min_length already has default=36, so it's filled.
    fireEvent.click(screen.getByRole("button", { name: /Save Changes/i }));

    await waitFor(() => {
      expect(onSave).toHaveBeenCalledTimes(1);
    });
    expect(onSave.mock.calls[0][0]).toBe("step-1");
    expect(onSave.mock.calls[0][1].reads_fwd).toBe("/data/sample.fastq");
  });

  it("clears the missing-required flag once the user types into the offending field", async () => {
    const onSave = vi.fn();
    render(
      <ParameterDialog open onOpenChange={() => {}} step={step as any} onSave={onSave} />
    );
    await waitFor(() => expect(screen.getByText("reads_fwd")).toBeInTheDocument());

    fireEvent.click(screen.getByRole("button", { name: /Save Changes/i }));
    await waitFor(() => {
      expect(screen.getByTestId("param-dialog-missing-required")).toHaveTextContent("reads_fwd");
    });

    // Type into reads_fwd — it was the only missing field, so the banner
    // disappears entirely once the set empties.
    const readsInput = screen.getByPlaceholderText(/Dataset \(fastq\)/i);
    fireEvent.change(readsInput, { target: { value: "/x" } });

    await waitFor(() => {
      expect(screen.queryByTestId("param-dialog-missing-required")).toBeNull();
    });
  });

  it("shows the file-format hint in the placeholder", async () => {
    render(<ParameterDialog open onOpenChange={() => {}} step={step as any} onSave={() => {}} />);
    await waitFor(() => {
      expect(screen.getByPlaceholderText("Dataset (fastq)")).toBeInTheDocument();
    });
  });
});
