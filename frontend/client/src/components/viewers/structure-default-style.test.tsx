/**
 * Cartoon draws only protein / nucleic-acid backbones: a crystal or small molecule (Si.cif in the
 * 2026-11-11 format matrix) rendered a blank canvas. Without CA/P atoms the viewer shows spheres.
 *
 * The fake viewer holds a real atom list and answers `selectedAtoms(sel)` by filtering it with the
 * selector it is given — so the test checks WHAT the component asks for (backbone atoms CA and P),
 * not just what a stub returns.
 */
import React from "react"
import { describe, it, expect, vi, beforeEach } from "vitest"
import { render, waitFor } from "@testing-library/react"

const styles: unknown[] = []
const selectors: unknown[] = []
let atoms: Array<{ atom: string }> = []
vi.mock("3dmol", () => ({
  default: {
    createViewer: () => ({
      addModel: () => {}, removeAllModels: () => {},
      selectedAtoms: (sel: { atom?: string | string[] } = {}) => {
        selectors.push(sel)
        const want = sel.atom === undefined ? null : ([] as string[]).concat(sel.atom)
        return atoms.filter((a) => want === null || want.includes(a.atom))
      },
      setStyle: (_sel: unknown, st: unknown) => { styles.push(st) },
      zoomTo: () => {}, render: () => {},
    }),
  },
}))
import { InlineStructureViewer } from "./inline-content-viewers"

beforeEach(() => { styles.length = 0; selectors.length = 0 })

const CARTOON = { cartoon: { color: "spectrum" } }
const SPHERES = { sphere: { scale: 0.4 } }

describe("InlineStructureViewer default style", () => {
  it("asks the viewer for backbone atoms by name: CA (protein) and P (nucleic acid)", async () => {
    atoms = [{ atom: "N" }, { atom: "CA" }, { atom: "C" }]
    render(<InlineStructureViewer text={"ATOM      1  CA  ALA A   1\n"} ext="pdb" />)
    await waitFor(() => expect(styles).toContainEqual(CARTOON))
    const atomSel = selectors.map((s) => (s as { atom?: unknown }).atom).find((a) => a !== undefined)
    expect(([] as unknown[]).concat(atomSel).sort()).toEqual(["CA", "P"])
  })
  it("no CA/P atoms (a crystal / small molecule) → spheres, not an empty cartoon", async () => {
    atoms = [{ atom: "Si" }, { atom: "C1" }, { atom: "O2" }]
    render(<InlineStructureViewer text={"data_Si\n"} ext="cif" />)
    await waitFor(() => expect(styles).toContainEqual(SPHERES))
    expect(styles).not.toContainEqual(CARTOON)
  })
  it("a protein keeps the cartoon", async () => {
    atoms = [{ atom: "N" }, { atom: "CA" }]
    render(<InlineStructureViewer text={"ATOM      1  CA  ALA A   1\n"} ext="pdb" />)
    await waitFor(() => expect(styles).toContainEqual(CARTOON))
    expect(styles).not.toContainEqual(SPHERES)
  })
  it("a nucleic acid (P backbone, no CA) keeps the cartoon", async () => {
    atoms = [{ atom: "P" }, { atom: "OP1" }, { atom: "C4'" }]
    render(<InlineStructureViewer text={"ATOM      1  P     DA A   1\n"} ext="pdb" />)
    await waitFor(() => expect(styles).toContainEqual(CARTOON))
    expect(styles).not.toContainEqual(SPHERES)
  })
})
