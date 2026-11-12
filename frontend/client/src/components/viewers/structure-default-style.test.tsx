/**
 * Cartoon draws only protein / nucleic-acid backbones: a crystal or small molecule (Si.cif in the
 * 2026-11-11 format matrix) rendered a blank canvas. Without CA/P atoms the viewer shows spheres.
 */
import React from "react"
import { describe, it, expect, vi, beforeEach } from "vitest"
import { render, waitFor } from "@testing-library/react"

const styles: unknown[] = []
let backbone: unknown[] = []
vi.mock("3dmol", () => ({
  default: {
    createViewer: () => ({
      addModel: () => {}, removeAllModels: () => {},
      selectedAtoms: () => backbone,
      setStyle: (_sel: unknown, st: unknown) => { styles.push(st) },
      zoomTo: () => {}, render: () => {},
    }),
  },
}))
import { InlineStructureViewer } from "./inline-content-viewers"

beforeEach(() => { styles.length = 0 })

describe("InlineStructureViewer default style", () => {
  it("no CA/P atoms → spheres (not an empty cartoon)", async () => {
    backbone = []
    render(<InlineStructureViewer text={"data_Si\n"} ext="cif" />)
    await waitFor(() => expect(styles).toContainEqual({ sphere: { scale: 0.4 } }))
    expect(styles).not.toContainEqual({ cartoon: { color: "spectrum" } })
  })
  it("a protein keeps the cartoon", async () => {
    backbone = [{ atom: "CA" }]
    render(<InlineStructureViewer text={"ATOM      1  CA  ALA A   1\n"} ext="pdb" />)
    await waitFor(() => expect(styles).toContainEqual({ cartoon: { color: "spectrum" } }))
  })
})
