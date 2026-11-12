/**
 * Camera fit for the inline 3D structure viewer.
 *
 * 3Dmol's `zoomTo` fits a SPHERE around the selection (twice the farthest atom's distance from
 * the box centre) and keeps the model's file orientation. An elongated molecule seen end-on (the
 * 5e5z peptide in the 2026-11-12 walkthrough: 8 × 5.5 × 18 Å, viewed down its long axis) then
 * fills a fraction of the frame — a speck in a wide panel. The fit here instead:
 *
 *  1. orients the model on its principal axes — longest along the screen's x, the frame being
 *     wide — so the projection is the largest the molecule offers;
 *  2. centres the projected bounding box, not the sphere;
 *  3. sets the camera distance so that projected box fills `fill` of the frame (width AND height,
 *     honouring the aspect ratio), adding half the depth so the nearest atoms are not clipped by
 *     perspective;
 *  4. floors the half-extent at `minHalfExtent` Å so a single atom or ion is not blown up to fill
 *     the screen.
 *
 * All pure: the component reads the atoms from 3Dmol and applies the returned view with
 * `viewer.setView` (3Dmol's [modelPos.x, .y, .z, rotationGroup.z, qx, qy, qz, qw] layout).
 */

export interface XYZ { x: number; y: number; z: number }

export interface FitAtom extends XYZ { resn?: string; hetflag?: boolean; atom?: string; ss?: string }

export interface StructureFit {
  /** Model-space point at the centre of the frame. */
  center: XYZ
  /** Rotation (x, y, z, w) taking model axes to screen axes. */
  quaternion: [number, number, number, number]
  /** Camera-to-centre distance, Å. */
  distance: number
  /** Projected extents (Å) of the fitted atoms in the fitted orientation: screen x, y and depth. */
  extent: XYZ
}

const SOLVENT = new Set(['HOH', 'WAT', 'DOD', 'H2O', 'SOL', 'TIP', 'TIP3', 'SPC'])

/**
 * The atoms the frame should hold. A cartoon draws only the polymer, so ligands and waters must
 * not set the zoom; any other style draws every atom but solvent (scattered crystal waters) still
 * must not shrink the molecule — unless the file is ONLY solvent / hetero atoms.
 */
export function atomsToFit<T extends FitAtom>(atoms: T[], polymerOnly: boolean): T[] {
  const finite = atoms.filter((a) => Number.isFinite(a.x) && Number.isFinite(a.y) && Number.isFinite(a.z))
  if (polymerOnly) {
    const polymer = finite.filter((a) => !a.hetflag)
    if (polymer.length > 0) return polymer
  }
  const nonSolvent = finite.filter((a) => !SOLVENT.has(String(a.resn ?? '').trim().toUpperCase()))
  return nonSolvent.length > 0 ? nonSolvent : finite
}

// 3Dmol's cartoon half-widths (3Dmol.js drawStrand: coilWidth / helixSheetWidth / nucleicAcidWidth),
// Å either side of the backbone trace.
const CARTOON_COIL_HALF_WIDTH = 0.5
const CARTOON_HELIX_SHEET_HALF_WIDTH = 1.3
const CARTOON_NUCLEIC_HALF_WIDTH = 0.8

/**
 * What a cartoon actually draws: a ribbon along the backbone TRACE (CA of each residue, P of each
 * nucleotide), as wide as the secondary structure's half-width either side — not the side chains.
 * Fitting the frame to every polymer atom left the 5e5z cartoon at 58% of the frame (its side chains
 * set the zoom, 2026-11-12 round 5). Returns the trace and that half-width as the fit's padding; a
 * model without atom names (no trace found) falls back to the polymer atoms, unpadded.
 */
export function cartoonFitAtoms<T extends FitAtom>(atoms: T[]): { atoms: T[]; pad: number } {
  const polymer = atomsToFit(atoms, true)
  const trace = polymer.filter((a) => !a.hetflag && (a.atom === 'CA' || a.atom === 'P'))
  if (trace.length === 0) return { atoms: polymer, pad: 0 }
  const pad = Math.max(...trace.map((a) =>
    a.ss === 'h' || a.ss === 's' ? CARTOON_HELIX_SHEET_HALF_WIDTH
    : a.atom === 'P' ? CARTOON_NUCLEIC_HALF_WIDTH
    : CARTOON_COIL_HALF_WIDTH))
  return { atoms: trace, pad }
}

/** Symmetric 3×3 eigen-decomposition (Jacobi). Returns eigenvectors as columns, sorted by eigenvalue desc. */
function principalAxes(cov: number[][]): [number[], number[], number[]] {
  const a = cov.map((r) => r.slice())
  const v = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
  for (let sweep = 0; sweep < 50; sweep++) {
    let off = 0
    for (let p = 0; p < 3; p++) for (let q = p + 1; q < 3; q++) off += a[p][q] * a[p][q]
    if (off < 1e-18) break
    for (let p = 0; p < 3; p++) {
      for (let q = p + 1; q < 3; q++) {
        if (Math.abs(a[p][q]) < 1e-15) continue
        const theta = (a[q][q] - a[p][p]) / (2 * a[p][q])
        const t = Math.sign(theta || 1) / (Math.abs(theta) + Math.sqrt(theta * theta + 1))
        const c = 1 / Math.sqrt(t * t + 1)
        const s = t * c
        for (let k = 0; k < 3; k++) {
          const akp = a[k][p], akq = a[k][q]
          a[k][p] = c * akp - s * akq
          a[k][q] = s * akp + c * akq
        }
        for (let k = 0; k < 3; k++) {
          const apk = a[p][k], aqk = a[q][k]
          a[p][k] = c * apk - s * aqk
          a[q][k] = s * apk + c * aqk
        }
        for (let k = 0; k < 3; k++) {
          const vkp = v[k][p], vkq = v[k][q]
          v[k][p] = c * vkp - s * vkq
          v[k][q] = s * vkp + c * vkq
        }
      }
    }
  }
  const order = [0, 1, 2].sort((i, j) => a[j][j] - a[i][i])
  const col = (i: number) => [v[0][i], v[1][i], v[2][i]]
  return [col(order[0]), col(order[1]), col(order[2])]
}

const dot = (a: number[], b: number[]) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
const cross = (a: number[], b: number[]) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]

/** Quaternion (x, y, z, w) of a rotation matrix given by its rows. */
function quaternionFromRows(r: number[][]): [number, number, number, number] {
  const [m11, m12, m13] = r[0], [m21, m22, m23] = r[1], [m31, m32, m33] = r[2]
  const trace = m11 + m22 + m33
  if (trace > 0) {
    const s = 0.5 / Math.sqrt(trace + 1)
    return [(m32 - m23) * s, (m13 - m31) * s, (m21 - m12) * s, 0.25 / s]
  }
  if (m11 > m22 && m11 > m33) {
    const s = 2 * Math.sqrt(1 + m11 - m22 - m33)
    return [0.25 * s, (m12 + m21) / s, (m13 + m31) / s, (m32 - m23) / s]
  }
  if (m22 > m33) {
    const s = 2 * Math.sqrt(1 + m22 - m11 - m33)
    return [(m12 + m21) / s, 0.25 * s, (m23 + m32) / s, (m13 - m31) / s]
  }
  const s = 2 * Math.sqrt(1 + m33 - m11 - m22)
  return [(m13 + m31) / s, (m23 + m32) / s, 0.25 * s, (m21 - m12) / s]
}

/** Rotate v by quaternion q (x, y, z, w). */
export function rotateByQuaternion(v: XYZ, q: [number, number, number, number]): XYZ {
  const [qx, qy, qz, qw] = q
  const tx = 2 * (qy * v.z - qz * v.y), ty = 2 * (qz * v.x - qx * v.z), tz = 2 * (qx * v.y - qy * v.x)
  return {
    x: v.x + qw * tx + (qy * tz - qz * ty),
    y: v.y + qw * ty + (qz * tx - qx * tz),
    z: v.z + qw * tz + (qx * ty - qy * tx),
  }
}

export interface FitOptions {
  /** Frame width / height. */
  aspect: number
  /** Vertical field of view, degrees (3Dmol's default is 20). */
  fovDeg?: number
  /** Fraction of the frame the projected box should fill. */
  fill?: number
  /** Smallest half-extent fitted, Å — keeps a lone atom from filling the screen. */
  minHalfExtent?: number
  /** Å the drawn geometry reaches beyond the fitted points on every side (a cartoon's ribbon
   *  half-width around its trace): added to the extents so the drawing, not the points, fills. */
  pad?: number
}

export function computeStructureFit(atoms: XYZ[], opts: FitOptions): StructureFit | null {
  if (atoms.length === 0) return null
  const aspect = Number.isFinite(opts.aspect) && opts.aspect > 0 ? opts.aspect : 1
  const fov = ((opts.fovDeg ?? 20) * Math.PI) / 180
  const fill = opts.fill ?? 0.86
  const minHalf = opts.minHalfExtent ?? 3

  const n = atoms.length
  const mean = atoms.reduce((m, a) => [m[0] + a.x / n, m[1] + a.y / n, m[2] + a.z / n], [0, 0, 0])
  const cov = [[0, 0, 0], [0, 0, 0], [0, 0, 0]]
  for (const a of atoms) {
    const d = [a.x - mean[0], a.y - mean[1], a.z - mean[2]]
    for (let i = 0; i < 3; i++) for (let j = 0; j < 3; j++) cov[i][j] += (d[i] * d[j]) / n
  }
  const [e1, e2] = principalAxes(cov)
  // Long axis across the wider screen dimension; right-handed frame (a proper rotation).
  const [sx, sy] = aspect >= 1 ? [e1, e2] : [e2, e1]
  const sz = cross(sx, sy)
  const rows = [sx, sy, sz]
  const quaternion = quaternionFromRows(rows)

  const lo = [Infinity, Infinity, Infinity], hi = [-Infinity, -Infinity, -Infinity]
  for (const a of atoms) {
    const p = [a.x, a.y, a.z]
    for (let i = 0; i < 3; i++) {
      const c = dot(rows[i], p)
      if (c < lo[i]) lo[i] = c
      if (c > hi[i]) hi[i] = c
    }
  }
  const mid = [0, 1, 2].map((i) => (lo[i] + hi[i]) / 2)
  // Back to model space: rows are orthonormal, so the inverse is the transpose.
  const center = {
    x: rows[0][0] * mid[0] + rows[1][0] * mid[1] + rows[2][0] * mid[2],
    y: rows[0][1] * mid[0] + rows[1][1] * mid[1] + rows[2][1] * mid[2],
    z: rows[0][2] * mid[0] + rows[1][2] * mid[1] + rows[2][2] * mid[2],
  }
  const pad = Number.isFinite(opts.pad) && opts.pad! > 0 ? opts.pad! : 0
  const extent = { x: hi[0] - lo[0] + 2 * pad, y: hi[1] - lo[1] + 2 * pad, z: hi[2] - lo[2] + 2 * pad }
  // Half-height the frame must show: the box's half-height, or its half-width over the aspect.
  // A tiny model (a lone ion, a 2-atom ligand) is fitted as if its larger half-extent were
  // `minHalfExtent`, so it is shown at a sensible scale rather than magnified to fill the frame.
  const halfObj = Math.max(extent.x / 2, extent.y / 2)
  const grow = halfObj < minHalf ? (halfObj > 0 ? minHalf / halfObj : 1) : 1
  const halfH = (halfObj > 0 ? Math.max(extent.y / 2, extent.x / 2 / aspect) * grow : minHalf / Math.max(aspect, 1)) / fill
  const distance = halfH / Math.tan(fov / 2) + extent.z / 2
  return { center, quaternion, distance, extent }
}

/** Projected fraction of the frame (width, height) the fitted atoms occupy at the fitted view. */
export function projectedFill(atoms: XYZ[], fit: Pick<StructureFit, 'center' | 'quaternion' | 'distance'>, aspect: number, fovDeg = 20): { w: number; h: number } {
  const t = Math.tan((fovDeg * Math.PI) / 360)
  let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity
  for (const a of atoms) {
    const p = rotateByQuaternion({ x: a.x - fit.center.x, y: a.y - fit.center.y, z: a.z - fit.center.z }, fit.quaternion)
    const depth = fit.distance - p.z
    const nx = p.x / (depth * t * aspect), ny = p.y / (depth * t)
    minX = Math.min(minX, nx); maxX = Math.max(maxX, nx)
    minY = Math.min(minY, ny); maxY = Math.max(maxY, ny)
  }
  return { w: (maxX - minX) / 2, h: (maxY - minY) / 2 }
}

// 3Dmol's camera sits at z = CAMERA_Z (150) looking down −z; the model group is translated by
// modelPos and the rotation group placed at rotationGroup.z, so distance = CAMERA_Z − rotationGroup.z.
export const THREEDMOL_CAMERA_Z = 150

/** The 8-element array 3Dmol's `setView` takes. */
export function toThreeDmolView(fit: StructureFit, cameraZ = THREEDMOL_CAMERA_Z): number[] {
  return [-fit.center.x, -fit.center.y, -fit.center.z, cameraZ - fit.distance, ...fit.quaternion]
}
