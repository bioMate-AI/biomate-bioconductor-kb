/**
 * N1 (2026-11-12 walkthrough): the 5e5z peptide rendered as a speck (~5% of the frame) in both
 * cartoon and stick. 3Dmol's zoomTo fits a sphere in the file's orientation; an 8 × 5.5 × 18 Å
 * peptide seen down its long axis fills a fraction of a wide frame.
 *
 * The fake viewer below answers `selectedAtoms` from a real atom list (an elongated peptide plus a
 * crystal water) and records the view the fit applies; the assertions project the atoms through
 * that view and measure how much of the frame they fill.
 */
import { describe, it, expect } from "vitest"
import { fitStructure } from "./inline-content-viewers"
import { atomsToFit, computeStructureFit, projectedFill, rotateByQuaternion, THREEDMOL_CAMERA_Z, type FitAtom } from "./structure-fit"

// A peptide strand running along the file's z axis (the viewing axis): 18 Å long, ~5 Å across.
const PEPTIDE: FitAtom[] = Array.from({ length: 46 }, (_, i) => ({
  x: 4 + 2.5 * Math.cos(i * 1.7),
  y: 0.5 + 2 * Math.sin(i * 1.3),
  z: -5.7 + (17.6 * i) / 45,
  resn: "LEU", hetflag: false,
}))
const WATER: FitAtom = { x: 30, y: -25, z: 40, resn: "HOH", hetflag: true }

function fakeViewer(atoms: FitAtom[]) {
  const calls: { setView?: number[]; zoomTo: unknown[] } = { zoomTo: [] }
  return {
    calls,
    viewer: {
      resize: () => {},
      selectedAtoms: (sel: Record<string, unknown> = {}) =>
        atoms.filter((a) => !("hetflag" in sel) || a.hetflag === sel.hetflag),
      zoomTo: (sel: unknown) => { calls.zoomTo.push(sel) },
      setView: (v: number[]) => { calls.setView = v },
      render: () => {},
    },
  }
}

/** Fraction of the frame filled by `atoms` under a 3Dmol view array. */
function fillUnderView(atoms: FitAtom[], view: number[], aspect: number) {
  const center = { x: -view[0], y: -view[1], z: -view[2] }
  const distance = THREEDMOL_CAMERA_Z - view[3]
  const quaternion = view.slice(4, 8) as [number, number, number, number]
  return projectedFill(atoms, { center, quaternion, distance }, aspect)
}

describe("fitStructure — the structure fills the frame", () => {
  it("a small elongated peptide in a wide frame fills most of it (not a speck)", () => {
    const { viewer, calls } = fakeViewer([...PEPTIDE, WATER])
    fitStructure(viewer, true, { width: 834, height: 320 })
    expect(calls.setView).toBeDefined()
    const fill = fillUnderView(PEPTIDE, calls.setView!, 834 / 320)
    // Wide frame: the long axis lies across it and fills ~80% of the width.
    expect(Math.max(fill.w, fill.h)).toBeGreaterThan(0.7)
    expect(fill.w).toBeLessThanOrEqual(0.9)
    expect(fill.h).toBeLessThanOrEqual(0.9)
  })

  it("stick style (all atoms) still ignores scattered crystal water", () => {
    const { viewer, calls } = fakeViewer([...PEPTIDE, WATER])
    fitStructure(viewer, false, { width: 834, height: 320 })
    const fill = fillUnderView(PEPTIDE, calls.setView!, 834 / 320)
    expect(Math.max(fill.w, fill.h)).toBeGreaterThan(0.7)
  })

  it("the fit depends on the frame's size: a narrow frame turns the long axis vertical", () => {
    const { viewer, calls } = fakeViewer(PEPTIDE)
    fitStructure(viewer, true, { width: 300, height: 320 })
    const fill = fillUnderView(PEPTIDE, calls.setView!, 300 / 320)
    expect(Math.max(fill.w, fill.h)).toBeGreaterThan(0.7)
    expect(Math.max(fill.w, fill.h)).toBeLessThanOrEqual(0.9)
  })
})

describe("computeStructureFit", () => {
  it("a lone atom is not blown up to fill the screen (minimum extent)", () => {
    const fit = computeStructureFit([{ x: 1, y: 2, z: 3 }], { aspect: 2 })!
    expect(fit.center).toEqual({ x: 1, y: 2, z: 3 })
    // A 3 Å floor at 82% fill with fov 20° in a 2:1 frame → ~10 Å away, not ~0.
    expect(fit.distance).toBeGreaterThan(8)
  })
  it("the rotation is proper (orthonormal, det +1): lengths are preserved", () => {
    const fit = computeStructureFit(PEPTIDE, { aspect: 2.6 })!
    const v = rotateByQuaternion({ x: 3, y: -4, z: 12 }, fit.quaternion)
    expect(Math.hypot(v.x, v.y, v.z)).toBeCloseTo(13, 6)
    // The longest principal axis maps to screen x in a wide frame.
    expect(fit.extent.x).toBeGreaterThan(fit.extent.y)
    expect(fit.extent.x).toBeGreaterThan(15)
  })
  it("atomsToFit: polymer for a cartoon, no solvent otherwise, everything when that is all there is", () => {
    const lig: FitAtom = { x: 0, y: 0, z: 0, resn: "ATP", hetflag: true }
    expect(atomsToFit([...PEPTIDE, WATER, lig], true)).toHaveLength(PEPTIDE.length)
    expect(atomsToFit([...PEPTIDE, WATER, lig], false)).toHaveLength(PEPTIDE.length + 1)
    expect(atomsToFit([WATER], false)).toHaveLength(1)
  })
})
