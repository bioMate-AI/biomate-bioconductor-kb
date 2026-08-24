"""
Confident state call for SNAT2 via a HOLE-style pore profile centered on the Na+/substrate site (N82/T384).
Transparent, assumption-explicit: membrane normal = the principal axis that shows a real channel through the
substrate site; the OPEN side (large pore radius) names the state:
  open toward cytoplasm  -> inward-open ; open toward extracellular/lumen -> outward-open ; both closed -> occluded.
Pure mdtraj/numpy, featherweight. Provisional (home-grown pore metric); HOLE is the rigorous confirmation.
"""
import numpy as np, mdtraj as md
t = md.load("snat2.pdb")
top = t.topology
xyz = t.xyz[0] * 10.0  # nm -> Angstrom
heavy = np.array([a.index for a in top.atoms if a.element.symbol != "H"])
P = xyz[heavy]

def ca(resSeq):
    for a in top.atoms:
        if a.residue.resSeq == resSeq and a.name == "CA":
            return xyz[a.index]
    return None
site = np.mean([ca(82), ca(384)], axis=0)   # substrate/Na+ site center
print(f"substrate-site center (N82/T384 CA midpoint) = {site.round(1)}")

# principal axes of heavy atoms
c = P - P.mean(0)
_, _, Vt = np.linalg.svd(c, full_matrices=False)
axes = Vt  # rows = principal axes (1st = largest spread)

def pore_profile(axis, span=25, step=1.5, rmax=12.0):
    """Radius of the largest atom-free sphere centered on the (site + s*axis) line, per axial offset s."""
    prof = []
    for s in np.arange(-span, span + step, step):
        pt = site + s * axis
        d = np.linalg.norm(P - pt, axis=1).min()   # nearest heavy atom -> local clearance
        prof.append((float(s), float(min(d, rmax))))
    return np.array(prof)

# find which principal axis is the membrane normal = the one with a genuine channel (both ends leave the protein)
print("\naxis | side_A_open(minR over +offsets) | side_B_open(over -offsets) | mid(at site)")
best = None
for i, ax in enumerate(axes):
    pr = pore_profile(ax)
    neg = pr[pr[:,0] < -8][:,1]; pos = pr[pr[:,0] > 8][:,1]; mid = pr[np.abs(pr[:,0]) <= 3][:,1]
    print(f" PA{i+1} | +end min R={pos.min():4.1f} max R={pos.max():4.1f} | -end min R={neg.min():4.1f} max R={neg.max():4.1f} | mid min R={mid.min():4.1f}")
    # a channel: at least one end opens to bulk (max R hits rmax i.e. leaves protein)
    span_open = max(pos.max(), neg.max())
    if best is None or span_open > best[1]:
        best = (i, span_open, ax, pr)

i, _, ax, pr = best
print(f"\n=> membrane-normal candidate = PA{i+1}")
# orient: +axis end vs -axis end openness through the site
pos = pr[pr[:,0] > 5]; neg = pr[pr[:,0] < -5]
open_pos = (pos[:,1] > 6).mean(); open_neg = (neg[:,1] > 6).mean()   # fraction of that half that is 'open' (R>6A)
print(f"   + half openness (frac R>6A) = {open_pos:.2f}   - half openness = {open_neg:.2f}")
print("\nPORE PROFILE along membrane-normal (offset A : clearance R A):")
for s, r in pr:
    bar = "#" * int(r)
    mark = "  <-- SITE" if abs(s) <= 0.75 else ""
    print(f"  {s:+6.1f} : {r:4.1f} {bar}{mark}")
print("\nREADING: the more-open half is the side the substrate cavity is accessible from.")
print("(Which physical side that is — cytoplasmic=inward vs extracellular=outward — needs the membrane")
print(" orientation; confirm by superposing scaffold onto SLC38A9 6C08[inward]/7KGV, or via HOLE+OPM.)")
