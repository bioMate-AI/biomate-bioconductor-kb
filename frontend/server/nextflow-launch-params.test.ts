import { describe, expect, it } from "vitest";
import { buildNextflowLaunchParameters } from "./nextflow-launch-params";

describe("buildNextflowLaunchParameters", () => {
  it("includes the public params-map override in the executor launch payload", () => {
    const parameters = buildNextflowLaunchParameters(
      {
        parameters: { profile: "aws", retries: 1 },
        required_params: [
          { name: "smiles", default: null },
          { name: "assay", default: "cyp" },
        ],
        optional_params: [{ name: "include_metabolites", default: true }],
      },
      {
        smiles: "CC(=O)Oc1ccccc1C(=O)O",
        retries: 3,
        include_metabolites: false,
      },
    );

    expect(parameters).toEqual({
      smiles: "CC(=O)Oc1ccccc1C(=O)O",
      assay: "cyp",
      include_metabolites: false,
      profile: "aws",
      retries: 3,
    });
  });

  it("uses structured row values when a caller does not provide an override", () => {
    const parameters = buildNextflowLaunchParameters(
      {
        required_params: [{ name: "smiles", value: "COC1=CC=CC=C1" }],
        optional_params: [
          { name: "batch_size", value: 0 },
          { name: "dry_run", value: false },
        ],
      },
      undefined,
    );

    expect(parameters).toEqual({
      smiles: "COC1=CC=CC=C1",
      batch_size: 0,
      dry_run: false,
    });
  });

  it("does not turn null or blank schema defaults into executor parameters", () => {
    expect(
      buildNextflowLaunchParameters(
        {
          required_params: [
            { name: "smiles", default: null },
            { name: "comment", default: "" },
          ],
        },
        {},
      ),
    ).toEqual({});
  });

  it("does not let a blank API override erase a validated schema value", () => {
    expect(
      buildNextflowLaunchParameters(
        { required_params: [{ name: "smiles", default: "CCO" }] },
        { smiles: "   ", retries: 0, dry_run: false },
      ),
    ).toEqual({ smiles: "CCO", retries: 0, dry_run: false });
  });

  it("does not let generic workflow maps erase a structured required value", () => {
    expect(
      buildNextflowLaunchParameters(
        {
          required_params: [{ name: "smiles", value: "CCO" }],
          inline_parameters: { smiles: null, threads: 2 },
          parameters: { smiles: "", threads: 4 },
        },
        undefined,
      ),
    ).toEqual({ smiles: "CCO", threads: 4 });
  });

  it("mirrors samplesheet ↔ input aliases for differentialabundance", () => {
    expect(
      buildNextflowLaunchParameters(
        { optional_params: [{ name: "samplesheet", value: "s3://b/sample_metadata.csv" }] },
        undefined,
      ),
    ).toEqual({
      samplesheet: "s3://b/sample_metadata.csv",
      input: "s3://b/sample_metadata.csv",
    });
    expect(
      buildNextflowLaunchParameters(
        { parameters: { input: "s3://b/meta.csv", matrix: "s3://b/counts.csv" } },
        undefined,
      ),
    ).toEqual({
      input: "s3://b/meta.csv",
      samplesheet: "s3://b/meta.csv",
      matrix: "s3://b/counts.csv",
    });
  });
});
