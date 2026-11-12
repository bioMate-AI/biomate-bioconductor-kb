/**
 * Dataset panel round-2 seams (2026-11-12), behaviour through the dataset object:
 *  - the rows response's `delimiter` goes back in the edit payload (with headerRows / skipLines /
 *    rowFrom / baseVersion), so the server splits the file the same way the rows reader did;
 *  - a refused edit says WHY (over 10 MiB, not plain UTF-8, not an editable kind, bad request),
 *    not "Could not save edits (413)";
 *  - the profile's `structure` evidence reaches the structure viewer (pLDDT chart decision);
 *  - the format chip shows the backend's label for the file, not another label of its extension.
 * Our own endpoints are faked at fetch.
 */
import React from "react"
import { describe, it, expect, vi, beforeEach } from "vitest"
import { render, screen, fireEvent, waitFor } from "@testing-library/react"
import { QueryClient, QueryClientProvider } from "@tanstack/react-query"

vi.mock("3dmol", () => ({
  default: {
    createViewer: () => ({
      addModel: () => {}, removeAllModels: () => {}, selectedAtoms: () => [{ atom: "CA" }],
      setStyle: () => {}, zoomTo: () => {}, render: () => {},
    }),
  },
}))
import { DatasetObject } from "./dataset-object"
import { DatasetFilePreview } from "./dataset-file-preview"

let profileBody: Record<string, unknown> = {}
let rowsBody: unknown = {}
let rowsStatus = 200
let editResponse: { status: number; body: unknown } = { status: 200, body: { file: { version_no: 3 } } }
let editBodies: any[] = []
let fileText = ""

function stream(text: string) {
  const value = new TextEncoder().encode(text)
  let done = false
  return {
    getReader: () => ({
      read: async () => (done ? { done: true } : ((done = true), { value, done: false })),
      cancel: async () => {}, releaseLock: () => {},
    }),
  }
}

beforeEach(() => {
  editBodies = []
  rowsStatus = 200
  editResponse = { status: 200, body: { file: { version_no: 3 } } }
  global.fetch = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
    const raw = String(input)
    const res = (status: number, body: unknown) =>
      ({ ok: status < 400, status, json: async () => body, text: async () => "" }) as unknown as Response
    if (raw.startsWith("https://files.example/")) return { ok: true, status: 200, body: stream(fileText) } as unknown as Response
    const url = new URL(raw, "http://x")
    if (url.pathname.endsWith("/rows")) return res(rowsStatus, rowsBody)
    if (url.pathname.endsWith("/edit")) { editBodies.push(JSON.parse(String(init?.body))); return res(editResponse.status, editResponse.body) }
    if (url.pathname.endsWith("/versions")) return res(200, { versions: [] })
    if (url.pathname.endsWith("/url")) return res(200, { url: "https://files.example/x" })
    if (url.pathname === "/api/perception/profile") return res(200, profileBody)
    return res(200, {})
  }) as unknown as typeof fetch
})

const qc = () => new QueryClient({ defaultOptions: { queries: { retry: false, gcTime: 0 } } })
function renderObj(name: string, preview?: React.ReactNode) {
  return render(
    <QueryClientProvider client={qc()}>
      <DatasetObject
        projectId="p1"
        dataset={{ id: `id-${name}`, name, ref: `projects/p1/inputs/${name}`, size: 1000, source: "upload" }}
        onRunQC={() => {}} onDownload={() => {}}
        preview={preview}
      />
    </QueryClientProvider>,
  )
}

const SEMI_TABLE = {
  profile: { shape: { rows: 2, cols: 2 }, quality: "good", notes: [], viewKind: "table", columns: ["g", "v"], sampleRows: [["a", "1"], ["b", "1"]],
    format: { ext: "csv", label: "CSV (semicolon-separated)", source: "biomate" } },
  rows: { columns: ["g", "v"], rows: [["a", "1"], ["b", "1"]], totalRows: 2, offset: 0, limit: 200, headerRow: true, version: 4, skipLines: 0, delimiter: ";" },
}

async function editOneCell(name = "semi.csv") {
  profileBody = SEMI_TABLE.profile
  rowsBody = SEMI_TABLE.rows
  renderObj(name)
  fireEvent.click(await screen.findByTestId("dataset-preview-toggle-edit"))
  fireEvent.change(await screen.findByTestId("dataset-edit-cell-1-1"), { target: { value: "7" } })
  fireEvent.click(screen.getByTestId("dataset-edit-save"))
}

describe("edit payload carries the rows reader's delimiter", () => {
  it("a semicolon CSV's edit sends delimiter ';' with headerRows, skipLines, rowFrom and baseVersion", async () => {
    await editOneCell()
    await waitFor(() => expect(editBodies).toHaveLength(1))
    expect(editBodies[0]).toEqual({
      edits: [{ row: 1, col: 1, from: "1", value: "7", rowFrom: ["b", "1"] }],
      headerRows: 1, baseVersion: 4, skipLines: 0, delimiter: ";",
    })
  })
})

describe("a refused edit says why", () => {
  const cases: Array<[number, unknown, RegExp]> = [
    [413, { error: "File exceeds the 10 MiB in-place-edit limit." }, /larger than the 10 MiB limit/],
    [422, { error: "This file is not plain UTF-8 text…" }, /not plain UTF-8 text/],
    [400, { error: "Only tabular files (csv/tsv) can be edited in place.", code: "not_tabular" }, /only tables \(CSV \/ TSV\) can be edited here/],
    [415, {}, /only tables \(CSV \/ TSV\) can be edited here/],
    [400, { error: "None of the edits matched a cell." }, /could not apply these edits/],
  ]
  for (const [status, body, message] of cases) {
    it(`${status} ${JSON.stringify(body).slice(0, 40)} → a specific message, not "Edit failed (${status})"`, async () => {
      editResponse = { status, body }
      await editOneCell()
      const err = await screen.findByTestId("dataset-edit-error")
      expect(err).toHaveTextContent(message)
      expect(err).not.toHaveTextContent(`(${status})`)
    })
  }
})

describe("format chip", () => {
  it("shows the backend's label for this file — a text document is 'Text', not 'Text (one value per line)'", async () => {
    profileBody = { shape: { rows: 0, cols: 0 }, quality: "unassessed", notes: [], viewKind: "document",
      format: { ext: "txt", label: "Text", source: "biomate" } }
    renderObj("notes.txt", <div />)
    const chip = await screen.findByTestId("dataset-header-format")
    expect(chip).toHaveTextContent(/^Text$/)
  })
  it("keeps a qualified label the backend sends (semicolon CSV)", async () => {
    profileBody = SEMI_TABLE.profile
    rowsBody = SEMI_TABLE.rows
    renderObj("semi.csv")
    expect(await screen.findByTestId("dataset-header-format")).toHaveTextContent("CSV (semicolon-separated)")
  })
})

// Two residues whose atoms carry different B-factors: the text alone is NOT evidence of pLDDT.
const atom = (serial: number, name: string, res: number, b: number) =>
  `ATOM  ${String(serial).padStart(5)} ${name.padEnd(4)} ALA A${String(res).padStart(4)}    ` +
  `${"1.000".padStart(8)}${"2.000".padStart(8)}${"3.000".padStart(8)}${"1.00".padStart(6)}${b.toFixed(2).padStart(6)}           C`
const INCONCLUSIVE = [atom(1, "N", 1, 80.1), atom(2, "CA", 1, 82.5), atom(3, "N", 2, 60.4), atom(4, "CA", 2, 58.9)].join("\n")

describe("profile structure evidence reaches the viewer", () => {
  it("structure.predicted from the profile → the pLDDT chart is drawn for the file", async () => {
    fileText = INCONCLUSIVE
    profileBody = { shape: { rows: 0, cols: 0 }, quality: "good", notes: [], viewKind: "structure",
      format: { ext: "pdb", label: "PDB", source: "galaxy" },
      structure: { method: null, method_key: null, predicted: true, predictor: "ColabFold", bfactor: "confidence" } }
    renderObj("model.pdb", <DatasetFilePreview projectId="p1" fileId="id-model.pdb" name="model.pdb" />)
    await waitFor(() => expect(screen.getByTestId("plddt-chart")).toBeInTheDocument(), { timeout: 5000 })
  })
  it("an experimental method from the profile → no pLDDT chart", async () => {
    fileText = INCONCLUSIVE.replace(/80\.10|82\.50/g, "70.00").replace(/60\.40|58\.90/g, "50.00") // per-residue constant
    profileBody = { shape: { rows: 0, cols: 0 }, quality: "good", notes: [], viewKind: "structure",
      format: { ext: "pdb", label: "PDB", source: "galaxy" },
      structure: { method: "X-RAY DIFFRACTION", method_key: "xray", predicted: false, predictor: null, bfactor: "displacement" } }
    renderObj("xtal.pdb", <DatasetFilePreview projectId="p1" fileId="id-xtal.pdb" name="xtal.pdb" />)
    const v = await screen.findByTestId("inline-structure-viewer", {}, { timeout: 5000 })
    expect(v).toHaveAttribute("data-has-confidence", "false")
    expect(screen.queryByTestId("plddt-chart")).toBeNull()
  })
})

describe("an empty / blank file is an empty state, not a rows error or an endless load", () => {
  const profile = { shape: { rows: 0, cols: 0 }, quality: "blocked", notes: [], viewKind: "table",
    findings: [{ section: "note", code: "blank_content", level: "blocked", params: {} }] }
  it("415 {reason: empty, code: blank_content} → 'only blank lines'", async () => {
    profileBody = profile
    rowsStatus = 415
    rowsBody = { error: "not_tabular", kind: "unknown", viewKind: "unknown", tabular: false, reason: "empty", code: "blank_content" }
    renderObj("blank.csv")
    const empty = await screen.findByTestId("dataset-preview-empty")
    expect(empty).toHaveAttribute("data-empty-code", "blank_content")
    expect(empty).toHaveTextContent("only blank lines")
    expect(screen.getByTestId("dataset-preview")).toHaveAttribute("data-preview-kind", "none")
    expect(screen.queryByTestId("dataset-rows-error")).toBeNull()
    expect(screen.queryByTestId("dataset-preview-loading")).toBeNull()
  })
  it("200 {tabular: false, reason: empty, code: empty_file} → '0 bytes', never stuck loading", async () => {
    profileBody = profile
    rowsBody = { kind: "unknown", viewKind: "unknown", tabular: false, reason: "empty", code: "empty_file" }
    renderObj("empty.csv")
    expect(await screen.findByTestId("dataset-preview-empty")).toHaveTextContent("0 bytes")
    expect(screen.queryByTestId("dataset-preview-loading")).toBeNull()
    expect(screen.queryByTestId("dataset-rows-error")).toBeNull()
  })
})
