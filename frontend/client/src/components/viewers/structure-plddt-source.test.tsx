/**
 * R16: a pLDDT chart only for a PREDICTED structure. An X-ray / NMR / EM structure's B-factors
 * are temperature factors in the 0–100 range too — the chart used to present them as
 * confidence (5e5z.pdb in the 2026-11-12 audit).
 */
import React from "react"
import { describe, it, expect, vi } from "vitest"
import { render, screen, waitFor } from "@testing-library/react"

vi.mock("3dmol", () => ({
  default: {
    createViewer: () => ({
      addModel: () => {}, removeAllModels: () => {}, selectedAtoms: () => [{ atom: "CA" }],
      setStyle: () => {}, zoomTo: () => {}, render: () => {},
    }),
  },
}))
import { InlineStructureViewer, structureConfidenceSource } from "./inline-content-viewers"

const atom = (serial: number, name: string, res: number, b: number) =>
  `ATOM  ${String(serial).padStart(5)} ${name.padEnd(4)} ALA A${String(res).padStart(4)}    ` +
  `${"1.000".padStart(8)}${"2.000".padStart(8)}${"3.000".padStart(8)}${"1.00".padStart(6)}${b.toFixed(2).padStart(6)}           C`

// Two residues, atoms with DIFFERENT B-factors (temperature factors vary atom by atom).
const XRAY_ATOMS = [atom(1, "N", 1, 22.1), atom(2, "CA", 1, 21.5), atom(3, "N", 2, 30.4), atom(4, "CA", 2, 28.9)].join("\n")
const XRAY = [
  "HEADER    HYDROLASE                               01-JAN-15   5E5Z",
  "EXPDTA    X-RAY DIFFRACTION",
  "CRYST1   57.200   63.100   71.400  90.00  90.00  90.00 P 21 21 21    4",
  XRAY_ATOMS,
].join("\n")
const ALPHAFOLD = [
  "HEADER    PREDICTED MODEL",
  "TITLE     ALPHAFOLD MONOMER V2.0 PREDICTION FOR PROTEIN",
  [atom(1, "N", 1, 91.2), atom(2, "CA", 1, 91.2), atom(3, "N", 2, 55.0), atom(4, "CA", 2, 55.0)].join("\n"),
].join("\n")
// A ColabFold/ESMFold-style file: no header; one B-factor per residue.
const BARE_PREDICTION = [atom(1, "N", 1, 88.0), atom(2, "CA", 1, 88.0), atom(3, "N", 2, 42.5), atom(4, "CA", 2, 42.5)].join("\n")

describe("structureConfidenceSource", () => {
  it("reads the file's own evidence", () => {
    expect(structureConfidenceSource(XRAY)).toBe("experimental")
    expect(structureConfidenceSource(ALPHAFOLD)).toBe("predicted")
    expect(structureConfidenceSource(BARE_PREDICTION)).toBe("predicted")
    expect(structureConfidenceSource("EXPDTA    SOLUTION NMR\n" + XRAY_ATOMS)).toBe("experimental")
    expect(structureConfidenceSource("EXPDTA    ELECTRON MICROSCOPY\n" + XRAY_ATOMS)).toBe("experimental")
    // No header and atom-varying B-factors: not evidence of a confidence column.
    expect(structureConfidenceSource(XRAY_ATOMS)).toBe("unknown")
  })
})

describe("InlineStructureViewer pLDDT chart", () => {
  it("no pLDDT chart for an X-ray structure even though its B-factors are 0–100", async () => {
    render(<InlineStructureViewer text={XRAY} ext="pdb" />)
    const v = await screen.findByTestId("inline-structure-viewer")
    expect(v).toHaveAttribute("data-has-confidence", "false")
    expect(screen.queryByTestId("plddt-chart")).toBeNull()
  })
  it("a predicted model shows its pLDDT chart", async () => {
    render(<InlineStructureViewer text={ALPHAFOLD} ext="pdb" />)
    await waitFor(() => expect(screen.getByTestId("plddt-chart")).toBeInTheDocument())
    expect(screen.getByTestId("plddt-mean")).toHaveTextContent("73")
  })
  it("style buttons are localized strings, not hard-coded English", async () => {
    render(<InlineStructureViewer text={ALPHAFOLD} ext="pdb" />)
    const v = await screen.findByTestId("inline-structure-viewer")
    expect(v).toHaveTextContent("Style:")
    expect(v).toHaveTextContent("Cartoon")
  })
})

// Round 2 (2026-11-12): the profiler reads the WHOLE file and reports `structure: {method,
// method_key, predicted, predictor, bfactor}`; the preview only sees a prefix. When the profile
// carries it, it decides — the text heuristic is only for profiles without it.
const XRAY_EVIDENCE = { method: "X-RAY DIFFRACTION", method_key: "xray", predicted: false, predictor: null, bfactor: "displacement" } as const
const AF_EVIDENCE = { method: null, method_key: null, predicted: true, predictor: "AlphaFold", bfactor: "confidence" } as const
const UNDETERMINED = { method: null, method_key: null, predicted: null, predictor: null, bfactor: null } as const

describe("profile structure evidence decides the pLDDT chart", () => {
  it("structureConfidenceSource follows the evidence; the text only when there is none", () => {
    expect(structureConfidenceSource(XRAY_ATOMS, AF_EVIDENCE)).toBe("predicted")
    expect(structureConfidenceSource(XRAY_ATOMS, { bfactor: "confidence" })).toBe("predicted")
    expect(structureConfidenceSource(ALPHAFOLD, XRAY_EVIDENCE)).toBe("experimental")
    // an experimental method family wins even if another field disagrees
    expect(structureConfidenceSource(ALPHAFOLD, { method_key: "em", predicted: true })).toBe("experimental")
    // present but undetermined → no chart (no fallback to the prefix heuristic)
    expect(structureConfidenceSource(BARE_PREDICTION, UNDETERMINED)).toBe("unknown")
    // absent (an older profile / no profile): the file's own text decides, as before
    expect(structureConfidenceSource(ALPHAFOLD, null)).toBe("predicted")
    expect(structureConfidenceSource(ALPHAFOLD)).toBe("predicted")
  })
  it("predicted per the profile → chart, even when the text alone is inconclusive", async () => {
    render(<InlineStructureViewer text={XRAY_ATOMS} ext="pdb" structure={AF_EVIDENCE} />)
    await waitFor(() => expect(screen.getByTestId("plddt-chart")).toBeInTheDocument())
  })
  it("an experimental method per the profile → never a chart, even for an AlphaFold-looking header", async () => {
    render(<InlineStructureViewer text={ALPHAFOLD} ext="pdb" structure={{ ...XRAY_EVIDENCE, method: "ELECTRON MICROSCOPY", method_key: "em" }} />)
    const v = await screen.findByTestId("inline-structure-viewer")
    expect(v).toHaveAttribute("data-has-confidence", "false")
    expect(screen.queryByTestId("plddt-chart")).toBeNull()
  })
})
