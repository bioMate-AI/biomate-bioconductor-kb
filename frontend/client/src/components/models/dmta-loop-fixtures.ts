/**
 * Cold-start Models Optimise (`loop`) fixtures → campaign ingest + virtual library.
 *
 * bace_assays.csv is a ML train table (smiles, compound_id, pIC50, IC50_nM, split),
 * not the assay-ingestion schema (compound_id, assay_type, value, unit, assay_date).
 * We map Train-split IC50_nM rows so first propose/refit is not stuck on empty assays.
 *
 * candidate_library.csv → virtual_library_smiles for POST …/virtual-library.
 */

export const LOOP_ASSAY_DEMO_URL = "/demo/cold-start/bace_assays.csv"
export const LOOP_LIBRARY_DEMO_URL = "/demo/cold-start/candidate_library.csv"

/** Map bace_assays.csv text → assay-ingestion CSV (Train split, IC50_nM). */
export function baceAssaysToIngestCsv(raw: string, assayDate = "2024-01-01"): string {
  const lines = raw.replace(/^\uFEFF/, "").split(/\r?\n/).filter((l) => l.trim())
  if (lines.length < 2) return "compound_id,smiles,assay_type,value,unit,assay_date\n"
  const header = splitCsvLine(lines[0]).map((h) => h.trim().toLowerCase())
  const idx = (name: string) => header.indexOf(name)
  const iId = idx("compound_id")
  const iSmiles = idx("smiles")
  const iIc50 = idx("ic50_nm")
  const iSplit = idx("split")
  if (iId < 0 || iIc50 < 0) {
    throw new Error("bace_assays.csv missing compound_id or IC50_nM")
  }
  const out = ["compound_id,smiles,assay_type,value,unit,assay_date"]
  for (let i = 1; i < lines.length; i++) {
    const cols = splitCsvLine(lines[i])
    if (iSplit >= 0 && String(cols[iSplit] || "").trim() !== "Train") continue
    const id = String(cols[iId] || "").trim()
    const value = String(cols[iIc50] || "").trim()
    if (!id || !value || !Number.isFinite(Number(value))) continue
    const smiles = iSmiles >= 0 ? String(cols[iSmiles] || "").trim() : ""
    out.push([csvEscape(id), csvEscape(smiles), "IC50", value, "nM", assayDate].join(","))
  }
  return out.join("\n") + "\n"
}

/** Parse candidate_library.csv → SMILES list (skips header / blank). */
export function candidateLibraryToSmiles(raw: string): string[] {
  const lines = raw.replace(/^\uFEFF/, "").split(/\r?\n/).filter((l) => l.trim())
  if (lines.length < 2) return []
  const header = splitCsvLine(lines[0]).map((h) => h.trim().toLowerCase())
  const iSmiles = header.indexOf("smiles")
  if (iSmiles < 0) throw new Error("candidate_library.csv missing smiles column")
  const smiles: string[] = []
  for (let i = 1; i < lines.length; i++) {
    const cols = splitCsvLine(lines[i])
    const s = String(cols[iSmiles] || "").trim()
    if (s && !s.toLowerCase().startsWith("smiles")) smiles.push(s)
  }
  return smiles
}

/** Minimal CSV splitter that respects double-quoted fields. */
export function splitCsvLine(line: string): string[] {
  const out: string[] = []
  let cur = ""
  let inQuotes = false
  for (let i = 0; i < line.length; i++) {
    const ch = line[i]
    if (inQuotes) {
      if (ch === '"') {
        if (line[i + 1] === '"') { cur += '"'; i++ }
        else inQuotes = false
      } else cur += ch
    } else if (ch === '"') {
      inQuotes = true
    } else if (ch === ",") {
      out.push(cur)
      cur = ""
    } else {
      cur += ch
    }
  }
  out.push(cur)
  return out
}

function csvEscape(v: string): string {
  if (/[",\n\r]/.test(v)) return `"${v.replace(/"/g, '""')}"`
  return v
}

export type SeedLoopResult = {
  assaysIngested: number
  librarySize: number
  warnings: string[]
}

/**
 * Fetch demo fixtures, ingest Train-split assays, cache virtual library.
 * Call after campaign create so retrain/trigger is not stuck on empty state.
 */
export async function seedLoopFixturesForCampaign(
  campaignId: string,
  fetchImpl: typeof fetch = fetch,
): Promise<SeedLoopResult> {
  const warnings: string[] = []
  const [assayRes, libRes] = await Promise.all([
    fetchImpl(LOOP_ASSAY_DEMO_URL, { credentials: "include" }),
    fetchImpl(LOOP_LIBRARY_DEMO_URL, { credentials: "include" }),
  ])
  if (!assayRes.ok) throw new Error(`Failed to load ${LOOP_ASSAY_DEMO_URL}: HTTP ${assayRes.status}`)
  if (!libRes.ok) throw new Error(`Failed to load ${LOOP_LIBRARY_DEMO_URL}: HTTP ${libRes.status}`)

  const assayCsv = baceAssaysToIngestCsv(await assayRes.text())
  const smiles = candidateLibraryToSmiles(await libRes.text())
  if (!smiles.length) throw new Error("candidate_library.csv produced no SMILES")

  const form = new FormData()
  form.append("file", new Blob([assayCsv], { type: "text/csv" }), "bace_assays_train_ic50.csv")
  const ingestRes = await fetchImpl(
    `/api/drug-discovery/${encodeURIComponent(campaignId)}/ingest-assay`,
    { method: "POST", credentials: "include", body: form },
  )
  const ingestBody = await ingestRes.json().catch(() => ({})) as {
    ingested?: number; errors?: string[]; detail?: string
  }
  if (!ingestRes.ok) {
    throw new Error(
      typeof ingestBody.detail === "string"
        ? ingestBody.detail
        : `ingest-assay HTTP ${ingestRes.status}`,
    )
  }
  const assaysIngested = Number(ingestBody.ingested ?? 0)
  if (Array.isArray(ingestBody.errors) && ingestBody.errors.length) {
    warnings.push(...ingestBody.errors.slice(0, 5).map(String))
  }
  if (assaysIngested < 1) {
    throw new Error("ingest-assay returned 0 rows — propose would still 422")
  }

  const vlRes = await fetchImpl(
    `/api/drug-discovery/${encodeURIComponent(campaignId)}/virtual-library`,
    {
      method: "POST",
      credentials: "include",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        virtual_library_smiles: smiles,
        n_propose: 10,
        diversity_weight: 0.2,
      }),
    },
  )
  if (!vlRes.ok) {
    const body = await vlRes.json().catch(() => ({})) as { detail?: string }
    throw new Error(typeof body.detail === "string" ? body.detail : `virtual-library HTTP ${vlRes.status}`)
  }

  return { assaysIngested, librarySize: smiles.length, warnings }
}
