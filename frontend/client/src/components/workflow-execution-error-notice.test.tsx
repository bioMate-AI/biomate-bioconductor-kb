import { describe, expect, it } from "vitest";
import { render, screen } from "@testing-library/react";
import { WorkflowExecutionErrorNotice } from "./workflow-execution-error-notice";

describe("WorkflowExecutionErrorNotice", () => {
  it("renders missing parameter labels and a concrete correction", () => {
    render(<WorkflowExecutionErrorNotice error={{
      code: "missing_required_params", message: "missing", missing: [{ name: "smiles", label: "Compound SMILES" }],
    }} />);
    expect(screen.getByTestId("execution-error-title")).toHaveTextContent("Complete required parameters");
    expect(screen.getByTestId("execution-error-missing-params")).toHaveTextContent("Compound SMILES");
    expect(screen.getByTestId("execution-error-action")).toHaveTextContent("fill the listed values");
  });

  it("renders input-required as an attach-data action", () => {
    render(<WorkflowExecutionErrorNotice error={{ code: "inputs_required", message: "missing", inputStepsCount: 2 }} />);
    expect(screen.getByTestId("execution-error-title")).toHaveTextContent("Attach input data before running");
    expect(screen.getByTestId("execution-error-detail")).toHaveTextContent("2 input steps");
  });

  it("renders unsupported Nextflow binding without a false retry promise", () => {
    render(<WorkflowExecutionErrorNotice error={{ code: "nextflow_inputs_not_supported", message: "unsupported" }} />);
    expect(screen.getByTestId("execution-error-title")).toHaveTextContent("not supported yet");
    expect(screen.getByTestId("execution-error-detail")).toHaveTextContent("No compute was started");
    expect(screen.getByTestId("execution-error-action")).toHaveTextContent("Choose a workflow that accepts parameterized dataset paths");
  });

  it("tells users to re-select invalid dataset bindings without claiming compute ran", () => {
    render(<WorkflowExecutionErrorNotice error={{ code: "invalid_workflow_inputs", message: "invalid inputs" }} />);
    expect(screen.getByTestId("execution-error-title")).toHaveTextContent("Re-select valid dataset bindings");
    expect(screen.getByTestId("execution-error-detail")).toHaveTextContent("No compute was started");
    expect(screen.getByTestId("execution-error-action")).toHaveTextContent("Select a valid dataset for each required input");
  });
});
