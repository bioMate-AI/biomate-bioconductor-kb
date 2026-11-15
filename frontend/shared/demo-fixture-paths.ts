/**
 * Cold-start / demo seed paths that must never appear as raw s3:// in client
 * bundles, public demo JSON, or chat copy. The UI and Prepared-inputs blocks
 * carry a `fixture:<id>` token; execute-time code expands it to the real URI.
 */

export const DEMO_FIXTURE_PATHS: Record<string, string> = {
  // Cryo-EM EMPIAR-10028 tutorial subset (20 movies) staged for Batch runs.
  "empiar-10028-movies": "s3://biomate-cryo-data/empiar-10028/Micrographs/",
  // GSE227835 MG pseudobulk demo (nf-core/differentialabundance + enrichGO follow-up).
  "mg-demo-samplesheet":
    "s3://biomate-nextflow-work/demo/mg_demo/sample_metadata.csv",
  "mg-demo-matrix":
    "s3://biomate-nextflow-work/demo/mg_demo/counts_matrix.csv",
  "mg-demo-contrasts":
    "s3://biomate-nextflow-work/demo/mg_demo/contrasts.csv",
  "mg-demo-gene-list":
    "s3://biomate-nextflow-work/demo/mg_demo/de_genes.txt",
};

/** Friendly label when a fixture token is shown in the param strip. */
export const DEMO_FIXTURE_LABELS: Record<string, string> = {
  "empiar-10028-movies": "EMPIAR-10028 movies",
  "mg-demo-samplesheet": "MG demo samplesheet",
  "mg-demo-matrix": "MG demo count matrix",
  "mg-demo-contrasts": "MG demo contrasts",
  "mg-demo-gene-list": "MG demo DE gene list",
};

const FIXTURE_RE = /^fixture:([A-Za-z0-9_-]+)$/i;

export function isDemoFixtureToken(value: unknown): boolean {
  return typeof value === "string" && FIXTURE_RE.test(value.trim());
}

/** Expand `fixture:<id>` → real storage URI; leave other values unchanged. */
export function resolveDemoFixtureValue(value: string): string {
  const m = FIXTURE_RE.exec(String(value || "").trim());
  if (!m) return value;
  const resolved = DEMO_FIXTURE_PATHS[m[1].toLowerCase()];
  return resolved ?? value;
}

/** Expand fixture tokens in a flat params map (mutates in place; returns map). */
export function resolveDemoFixtureParams(
  params: Record<string, unknown>,
): Record<string, unknown> {
  for (const [k, v] of Object.entries(params)) {
    if (typeof v === "string" && isDemoFixtureToken(v)) {
      params[k] = resolveDemoFixtureValue(v);
    }
  }
  return params;
}

export function demoFixtureLabel(value: string): string | null {
  const m = FIXTURE_RE.exec(String(value || "").trim());
  if (!m) return null;
  return DEMO_FIXTURE_LABELS[m[1].toLowerCase()] || m[1];
}
