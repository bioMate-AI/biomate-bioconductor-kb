import { describe, expect, it } from "vitest";
import { assembleReproducibilityRecord } from "./reproducibility-record";
import {
  assembleMethodsMarkdown,
  assembleRunRoCrate,
  buildReproducibilityPackMembers,
} from "./reproducibility-pack";

describe("reproducibility pack", () => {
  const record = assembleReproducibilityRecord(
    {
      id: "run-1",
      workflowName: "admet_screening",
      execution: { status: "completed", completedAt: "2026-11-13T12:00:00Z" },
      createdAt: "2026-11-13T11:00:00Z",
      parameters: { smiles: "CCO" },
      inputBindings: [{ name: "smiles", datasetId: "d1" }],
    },
    [{ id: "o1", name: "results.csv", fileType: "csv", sizeBytes: 12 }],
  );

  it("builds RO-Crate with run identity and outputs", () => {
    const crate = assembleRunRoCrate(record);
    expect(crate["@context"]).toContain("ro/crate");
    const graph = crate["@graph"] as any[];
    expect(graph.some((n) => n["@id"] === "./" && n.identifier === "run-1")).toBe(true);
    expect(graph.some((n) => n.name === "results.csv")).toBe(true);
  });

  it("methods markdown includes params and outputs", () => {
    const md = assembleMethodsMarkdown(record);
    expect(md).toContain("admet_screening");
    expect(md).toContain("CCO");
    expect(md).toContain("results.csv");
    expect(md).toContain("Deterministic provenance");
  });

  it("pack members always include core files even when software/citations empty", () => {
    const members = buildReproducibilityPackMembers({
      record,
      software: {},
      citations: { citations: [], count: 0 },
    });
    const names = members.map((m) => m.name).sort();
    expect(names).toEqual([
      "MANIFEST.md",
      "citations.json",
      "methods.md",
      "ro-crate-metadata.json",
      "run-record.json",
      "software.json",
    ]);
    const manifest = members.find((m) => m.name === "MANIFEST.md")!.body.toString();
    expect(manifest).toContain("software.json is empty");
    expect(manifest).toContain("citations.json has no entries");
  });

  it("pack notes software when provided", () => {
    const members = buildReproducibilityPackMembers({
      record,
      software: { versions: { nextflow: "24.04" }, count: 1 },
      citations: [{ title: "Paper" }],
    });
    const manifest = members.find((m) => m.name === "MANIFEST.md")!.body.toString();
    expect(manifest).not.toContain("software.json is empty");
    expect(manifest).not.toContain("citations.json has no entries");
  });
});
