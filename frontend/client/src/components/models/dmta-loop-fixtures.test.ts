import { describe, it, expect, vi } from "vitest"
import {
  baceAssaysToIngestCsv,
  candidateLibraryToSmiles,
  seedLoopFixturesForCampaign,
  LOOP_ASSAY_DEMO_URL,
  LOOP_LIBRARY_DEMO_URL,
} from "./dmta-loop-fixtures"

const BACE_SAMPLE = `smiles,compound_id,active,split,pIC50,molecular_weight,logP,IC50_nM
CCO,BACE_1,1,Train,9.1,46,0.1,0.7
CCN,BACE_2,1,Valid,8.0,45,0.2,1.4
CCC,BACE_3,1,Train,7.5,44,0.3,2.0
`

const LIB_SAMPLE = `compound_id,smiles
BACE_1,CCO
BACE_2,CCN
BACE_3,CCC
`

describe("dmta-loop-fixtures", () => {
  it("maps Train-split IC50_nM rows into assay-ingestion CSV", () => {
    const csv = baceAssaysToIngestCsv(BACE_SAMPLE, "2024-06-01")
    const lines = csv.trim().split("\n")
    expect(lines[0]).toBe("compound_id,smiles,assay_type,value,unit,assay_date")
    expect(lines).toHaveLength(3) // header + 2 Train rows (Valid skipped)
    expect(lines[1]).toContain("BACE_1")
    expect(lines[1]).toContain("IC50")
    expect(lines[1]).toContain("0.7")
    expect(lines[1]).toContain("nM")
    expect(csv).not.toContain("BACE_2") // Valid split
  })

  it("parses candidate_library SMILES", () => {
    expect(candidateLibraryToSmiles(LIB_SAMPLE)).toEqual(["CCO", "CCN", "CCC"])
  })

  it("seeds ingest-assay multipart + virtual_library_smiles (not invent4)", async () => {
    const calls: Array<{ url: string; init?: RequestInit }> = []
    const fetchImpl = vi.fn(async (url: string | URL | Request, init?: RequestInit) => {
      const u = String(url)
      calls.push({ url: u, init })
      if (u === LOOP_ASSAY_DEMO_URL) {
        return new Response(BACE_SAMPLE, { status: 200 })
      }
      if (u === LOOP_LIBRARY_DEMO_URL) {
        return new Response(LIB_SAMPLE, { status: 200 })
      }
      if (u.includes("/ingest-assay")) {
        expect(init?.method).toBe("POST")
        expect(init?.body).toBeInstanceOf(FormData)
        return new Response(JSON.stringify({ ingested: 2, errors: [] }), {
          status: 200,
          headers: { "Content-Type": "application/json" },
        })
      }
      if (u.includes("/virtual-library")) {
        const body = JSON.parse(String(init?.body || "{}"))
        expect(body.virtual_library_smiles).toEqual(["CCO", "CCN", "CCC"])
        expect(body).not.toHaveProperty("smiles")
        return new Response(JSON.stringify({ status: "cached", n_smiles: 3 }), {
          status: 200,
          headers: { "Content-Type": "application/json" },
        })
      }
      throw new Error(`unexpected fetch ${u}`)
    }) as unknown as typeof fetch

    const result = await seedLoopFixturesForCampaign("proj-1", fetchImpl)
    expect(result.assaysIngested).toBe(2)
    expect(result.librarySize).toBe(3)
    expect(calls.some((c) => c.url.includes("/ingest-assay"))).toBe(true)
    expect(calls.some((c) => c.url.includes("/virtual-library"))).toBe(true)
    expect(calls.every((c) => !/reinvent4/i.test(c.url))).toBe(true)
  })
})
