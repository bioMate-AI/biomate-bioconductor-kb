/**
 * Round 5 (2026-11-12 walkthrough): the 5e5z cartoon filled only 58% of the limiting axis of the
 * desktop frame (834 × 320) and 72% at 390 px (300 × 320). The fit used every polymer atom; a
 * cartoon draws only a ribbon along the CA trace, so the side chains set the zoom. The cartoon is
 * now fitted to its trace plus the ribbon half-width (3Dmol coilWidth 0.5 Å).
 *
 * The fake viewer answers selectedAtoms with 5e5z's real atoms (PDB 5e5z, LVHSSN + 1 water); the
 * drawn cartoon is modelled as the CA trace widened by the coil half-width in screen x and y.
 */
import { describe, it, expect } from "vitest"
import { fitStructure } from "./inline-content-viewers"
import { projectedFill, rotateByQuaternion, THREEDMOL_CAMERA_Z, type FitAtom, type XYZ } from "./structure-fit"

const RAW: Array<[string, number, number, number]> = [
  ["N", 6.078, -0.306, -5.753],
  ["CA", 5.166, -0.026, -4.647],
  ["C", 5.682, -0.642, -3.356],
  ["O", 6.056, -1.814, -3.322],
  ["CB", 3.755, -0.555, -4.967],
  ["CG", 2.596, -0.354, -3.975],
  ["CD1", 2.753, -1.182, -2.704],
  ["CD2", 2.404, 1.122, -3.638],
  ["N", 5.715, 0.161, -2.297],
  ["CA", 5.968, -0.352, -0.960],
  ["C", 4.976, 0.281, 0.000],
  ["O", 4.746, 1.489, -0.046],
  ["CB", 7.400, -0.027, -0.475],
  ["CG1", 7.566, -0.421, 0.993],
  ["CG2", 8.429, -0.722, -1.342],
  ["N", 4.367, -0.537, 0.850],
  ["CA", 3.603, -0.011, 1.971],
  ["C", 4.003, -0.675, 3.280],
  ["O", 4.208, -1.889, 3.338],
  ["CB", 2.095, -0.177, 1.781],
  ["CG", 1.324, 0.074, 3.040],
  ["ND1", 0.950, -0.937, 3.900],
  ["CD2", 0.921, 1.230, 3.620],
  ["CE1", 0.321, -0.417, 4.940],
  ["NE2", 0.290, 0.896, 4.794],
  ["N", 4.099, 0.141, 4.326],
  ["CA", 4.357, -0.330, 5.683],
  ["C", 3.814, 0.686, 6.681],
  ["O", 4.008, 1.889, 6.507],
  ["CB", 5.858, -0.513, 5.905],
  ["OG", 6.132, -0.771, 7.272],
  ["N", 3.138, 0.213, 7.725],
  ["CA", 2.651, 1.119, 8.765],
  ["C", 3.677, 1.311, 9.885],
  ["O", 3.411, 2.024, 10.851],
  ["CB", 1.318, 0.639, 9.350],
  ["OG", 1.478, -0.544, 10.117],
  ["N", 4.838, 0.672, 9.758],
  ["CA", 5.912, 0.838, 10.741],
  ["C", 6.574, 2.203, 10.638],
  ["O", 7.335, 2.594, 11.519],
  ["CB", 6.986, -0.243, 10.589],
  ["CG", 6.592, -1.558, 11.236],
  ["OD1", 5.576, -1.644, 11.923],
  ["ND2", 7.409, -2.588, 11.030],
  ["OXT", 6.383, 2.933, 9.667],
]
const ATOMS: FitAtom[] = [
  ...RAW.map(([atom, x, y, z]) => ({ atom, x, y, z, resn: "UNK", hetflag: false, ss: "c" })),
  { atom: "O", x: 8.203, y: 1.052, z: -4.564, resn: "HOH", hetflag: true },
]
const COIL_HALF_WIDTH = 0.5

function fakeViewer(atoms: FitAtom[]) {
  const calls: { setView?: number[] } = {}
  return {
    calls,
    viewer: {
      resize: () => {},
      selectedAtoms: (sel: Record<string, unknown> = {}) => atoms.filter((a) => !("hetflag" in sel) || a.hetflag === sel.hetflag),
      zoomTo: () => {},
      setView: (v: number[]) => { calls.setView = v },
      render: () => {},
    },
  }
}

/** The fraction of the frame the drawn cartoon fills (w, h) under a 3Dmol view array. */
function cartoonFill(view: number[], aspect: number) {
  const center = { x: -view[0], y: -view[1], z: -view[2] }
  const quaternion = view.slice(4, 8) as [number, number, number, number]
  const distance = THREEDMOL_CAMERA_Z - view[3]
  // The ribbon around each CA, widened in SCREEN x and y: rotate the CA into the view, offset, rotate back.
  const inv: [number, number, number, number] = [-quaternion[0], -quaternion[1], -quaternion[2], quaternion[3]]
  const pts: XYZ[] = []
  for (const a of ATOMS.filter((x) => x.atom === "CA")) {
    const p = rotateByQuaternion({ x: a.x - center.x, y: a.y - center.y, z: a.z - center.z }, quaternion)
    for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
      const q = rotateByQuaternion({ x: p.x + dx * COIL_HALF_WIDTH, y: p.y + dy * COIL_HALF_WIDTH, z: p.z }, inv)
      pts.push({ x: q.x + center.x, y: q.y + center.y, z: q.z + center.z })
    }
  }
  return projectedFill(pts, { center, quaternion, distance }, aspect)
}

describe("5e5z cartoon fills the frame on its limiting axis", () => {
  for (const [label, width, height] of [["desktop", 834, 320], ["390 px", 300, 320]] as const) {
    it(label, () => {
      const { viewer, calls } = fakeViewer(ATOMS)
      fitStructure(viewer, true, { width, height })
      const fill = cartoonFill(calls.setView!, width / height)
      // The limiting axis is the one the cartoon fills most; it must be ≥ 80% and not clipped.
      const limiting = Math.max(fill.w, fill.h)
      expect(limiting).toBeGreaterThanOrEqual(0.8)
      expect(limiting).toBeLessThanOrEqual(0.95)
      expect(Math.min(fill.w, fill.h)).toBeLessThanOrEqual(0.95)
    })
  }
})
