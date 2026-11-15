import { describe, expect, it } from "vitest";
import {
  isDemoFixtureToken,
  resolveDemoFixtureParams,
  resolveDemoFixtureValue,
  demoFixtureLabel,
} from "./demo-fixture-paths";

describe("demo-fixture-paths", () => {
  it("recognizes and expands the cryo movies fixture", () => {
    expect(isDemoFixtureToken("fixture:empiar-10028-movies")).toBe(true);
    expect(resolveDemoFixtureValue("fixture:empiar-10028-movies")).toBe(
      "s3://biomate-cryo-data/empiar-10028/Micrographs/",
    );
    expect(demoFixtureLabel("fixture:empiar-10028-movies")).toBe("EMPIAR-10028 movies");
  });

  it("leaves ordinary values alone", () => {
    expect(resolveDemoFixtureValue("pilot_compounds.csv")).toBe("pilot_compounds.csv");
    expect(isDemoFixtureToken("s3://bucket/x")).toBe(false);
  });

  it("expands fixtures in a params map in place", () => {
    const params: Record<string, unknown> = {
      movies_path: "fixture:empiar-10028-movies",
      pixel_size: "0.885",
    };
    resolveDemoFixtureParams(params);
    expect(params.movies_path).toBe("s3://biomate-cryo-data/empiar-10028/Micrographs/");
    expect(params.pixel_size).toBe("0.885");
  });

  it("expands MG demo fixtures used by LLM GEO routing prompts", () => {
    expect(resolveDemoFixtureValue("fixture:mg-demo-samplesheet")).toContain(
      "sample_metadata.csv",
    );
    expect(resolveDemoFixtureValue("fixture:mg-demo-matrix")).toContain(
      "counts_matrix.csv",
    );
    expect(resolveDemoFixtureValue("fixture:mg-demo-contrasts")).toContain(
      "contrasts.csv",
    );
    expect(resolveDemoFixtureValue("fixture:mg-demo-gene-list")).toContain(
      "de_genes.txt",
    );
    expect(demoFixtureLabel("fixture:mg-demo-matrix")).toBe("MG demo count matrix");
  });
});
