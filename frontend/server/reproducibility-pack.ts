/**
 * Reproducibility pack — one zip of provenance artifacts for a completed run.
 *
 * Distinct from download-all (scientific outputs) and from the Galaxy
 * `/reproducibility` bundle (which only reads /tmp and is useless for Batch).
 * Assembles: run-record.json, methods.md (deterministic), software.json,
 * citations.json, run-level ro-crate-metadata.json, MANIFEST.md.
 */

import type { ReproducibilityRecord } from "./reproducibility-record";

export type PackMember = { name: string; body: string | Buffer; note?: string };

export function assembleRunRoCrate(record: ReproducibilityRecord): Record<string, unknown> {
  const outputs = (record.outputs || []).map((o) => ({
    "@type": "File",
    name: o.name,
    ...(o.id ? { identifier: o.id } : {}),
    ...(o.fileType ? { encodingFormat: o.fileType } : {}),
    ...(typeof o.sizeBytes === "number" ? { contentSize: String(o.sizeBytes) } : {}),
    ...(o.sha256 ? { sha256: o.sha256 } : {}),
  }));
  return {
    "@context": "https://w3id.org/ro/crate/1.1/context",
    "@graph": [
      {
        "@type": "CreativeWork",
        "@id": "ro-crate-metadata.json",
        conformsTo: { "@id": "https://w3id.org/ro/crate/1.1" },
        about: { "@id": "./" },
      },
      {
        "@id": "./",
        "@type": "Dataset",
        name: record.workflowName || "BioMate run",
        identifier: record.runId,
        dateCreated: record.createdAt,
        datePublished: record.completedAt,
        description:
          "Run-level RO-Crate assembled from BioMate's reproducibility record " +
          "(workflow identity, parameters, inputs, outputs). Not a full Galaxy history export.",
        hasPart: outputs.map((o) => ({ "@id": `#output-${encodeURIComponent(o.name)}` })),
      },
      {
        "@id": `#run-${record.runId}`,
        "@type": "CreateAction",
        name: record.workflowName,
        instrument: { "@id": `#workflow-${encodeURIComponent(record.workflowName)}` },
        object: (record.inputBindings || []).map((_, i) => ({ "@id": `#input-${i}` })),
        result: outputs.map((o) => ({ "@id": `#output-${encodeURIComponent(o.name)}` })),
        actionStatus: record.status,
      },
      {
        "@id": `#workflow-${encodeURIComponent(record.workflowName)}`,
        "@type": "SoftwareApplication",
        name: record.workflowName,
      },
      ...outputs.map((o) => ({
        ...o,
        "@id": `#output-${encodeURIComponent(o.name)}`,
      })),
    ],
  };
}

/** Deterministic methods snapshot — not the LLM publication report. */
export function assembleMethodsMarkdown(record: ReproducibilityRecord): string {
  const lines: string[] = [
    `# Methods snapshot — ${record.workflowName}`,
    "",
    "> Deterministic provenance snapshot from BioMate. For the AI publication-style",
    "> report, use the panel **Report** download (`/methods-report`).",
    "",
    "## Run",
    "",
    `- **Run ID:** \`${record.runId}\``,
    `- **Status:** ${record.status}`,
    `- **Started:** ${record.createdAt ?? "n/a"}`,
    `- **Completed:** ${record.completedAt ?? "n/a"}`,
    "",
    "## Parameters",
    "",
    "```json",
    JSON.stringify(record.parameters ?? {}, null, 2),
    "```",
    "",
    "## Inputs",
    "",
  ];
  if (!record.inputBindings?.length) {
    lines.push("_No input bindings recorded._", "");
  } else {
    for (const b of record.inputBindings) {
      lines.push(`- \`${JSON.stringify(b)}\``);
    }
    lines.push("");
  }
  lines.push("## Outputs", "");
  if (!record.outputs?.length) {
    lines.push("_No outputs registered._", "");
  } else {
    for (const o of record.outputs) {
      const bits = [o.name];
      if (o.fileType) bits.push(o.fileType);
      if (typeof o.sizeBytes === "number") bits.push(`${o.sizeBytes} B`);
      if (o.sha256) bits.push(`sha256:${o.sha256.slice(0, 12)}…`);
      lines.push(`- ${bits.join(" · ")}`);
    }
    lines.push("");
  }
  return lines.join("\n");
}

export function assembleManifest(notes: string[]): string {
  const body = [
    "# BioMate reproducibility pack",
    "",
    "This archive is **provenance**, not scientific outputs.",
    "Use **Download all** / download-all ZIP for result files.",
    "",
    "## Members",
    "",
    "- `run-record.json` — structured reproducibility record",
    "- `methods.md` — deterministic methods snapshot (not LLM report)",
    "- `software.json` — tool versions when available",
    "- `citations.json` — workflow citations when available",
    "- `ro-crate-metadata.json` — run-level RO-Crate 1.1",
    "- `MANIFEST.md` — this file",
    "",
  ];
  if (notes.length) {
    body.push("## Notes", "", ...notes.map((n) => `- ${n}`), "");
  }
  return body.join("\n");
}

export function buildReproducibilityPackMembers(opts: {
  record: ReproducibilityRecord;
  software: unknown;
  citations: unknown;
  softwareNote?: string;
  citationsNote?: string;
}): PackMember[] {
  const notes: string[] = [];
  if (opts.softwareNote) notes.push(opts.softwareNote);
  if (opts.citationsNote) notes.push(opts.citationsNote);

  const softwareEmpty =
    !opts.software ||
    (typeof opts.software === "object" &&
      opts.software !== null &&
      !Array.isArray(opts.software) &&
      Object.keys(opts.software as object).length === 0) ||
    (Array.isArray(opts.software) && opts.software.length === 0);
  const citationsArr = Array.isArray(opts.citations)
    ? opts.citations
    : (opts.citations as any)?.citations;
  const citationsEmpty = !citationsArr || (Array.isArray(citationsArr) && citationsArr.length === 0);
  if (softwareEmpty && !opts.softwareNote) {
    notes.push("software.json is empty — versions.yml not found for this run");
  }
  if (citationsEmpty && !opts.citationsNote) {
    notes.push("citations.json has no entries for this workflow name");
  }

  return [
    { name: "run-record.json", body: JSON.stringify(opts.record, null, 2) },
    { name: "methods.md", body: assembleMethodsMarkdown(opts.record) },
    { name: "software.json", body: JSON.stringify(opts.software ?? { versions: {}, count: 0 }, null, 2) },
    {
      name: "citations.json",
      body: JSON.stringify(
        Array.isArray(opts.citations)
          ? { citations: opts.citations, count: opts.citations.length }
          : opts.citations ?? { citations: [], count: 0 },
        null,
        2,
      ),
    },
    {
      name: "ro-crate-metadata.json",
      body: JSON.stringify(assembleRunRoCrate(opts.record), null, 2),
    },
    { name: "MANIFEST.md", body: assembleManifest(notes) },
  ];
}
