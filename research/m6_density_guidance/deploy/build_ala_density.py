"""Build an M6 cryo-EM-style density anchor for alanine dipeptide, in the model's frame
(center_zeroed physical coords, 22 all-atoms). Anchors on a GT INTERMEDIATE conformation
(dihedral-space midpoint of the two densest basins) -> constrains the PATH, not just endpoints.
Writes $M6_DENSITY_NPZ (default /tmp/ala_density.npz): {grid, d_exp, sigma}.

Dihedrals via the pipeline's method: 5 CG atoms [4,6,8,14,16] + ala2_cg.pdb topology +
md.compute_dihedrals([[0,1,2,3],[1,2,3,4]])  (naming-independent, matches evaluators_CGflowmatching.get_torsions).
"""
import os, numpy as np, torch, mdtraj as md

SIGMA = float(os.environ.get("M6_SIGMA", "1.5"))
GT   = os.environ.get("M6_GT",  "/data/sanjeevr/Ala2Train/trajectories1000.0K.pt")
CGPDB= os.environ.get("M6_CGPDB", "datasets/folded_pdbs/ala2_cg.pdb")
OUT  = os.environ.get("M6_DENSITY_NPZ", "/tmp/ala_density.npz")

xyz = torch.load(GT, weights_only=True).reshape(-1, 22, 3).numpy().astype("float32")
cg  = xyz[:, [4, 6, 8, 14, 16]]                        # backbone CG atoms (as the code does)
cg_top = md.load_topology(CGPDB)
dih = md.compute_dihedrals(md.Trajectory(cg, cg_top), [[0, 1, 2, 3], [1, 2, 3, 4]])  # [N,2] phi,psi (rad)

# use the pipeline's OWN endpoint clusters (what the baseline path connects): clusters [0,1]
CENTERS = os.environ.get("M6_CENTERS", "evaluate/saved_references/saved_cluster_centers_alanine_dipeptide.npy")
cc = np.load(CENTERS)                                   # [5,2] (phi,psi) cluster centers
A, B = cc[0], cc[1]                                     # CLUSTER_ENDPOINTS_ALA = [0,1]
def wrap(d): return (d + np.pi) % (2*np.pi) - np.pi
mid = wrap(A + 0.5 * wrap(B - A))                       # periodic midpoint = transition intermediate
d = np.sqrt(wrap(dih[:, 0]-mid[0])**2 + wrap(dih[:, 1]-mid[1])**2)
idx = np.argsort(d)[:50]

target = xyz[idx].mean(0)                               # averaged intermediate, 22x3
target = target - target.mean(0)                        # center_zero (match noised_xs*norm_factor)

lo = target.min(0) - 3*SIGMA; hi = target.max(0) + 3*SIGMA
axes = [np.linspace(lo[k], hi[k], 16) for k in range(3)]
gx, gy, gz = np.meshgrid(*axes, indexing="ij")
grid = np.stack([gx.ravel(), gy.ravel(), gz.ravel()], 1).astype("float32")
t = torch.tensor(target); g = torch.tensor(grid)
d2 = ((g[:, None, :] - t[None, :, :])**2).sum(-1)
d_exp = torch.exp(-d2/(2*SIGMA*SIGMA)).sum(-1).numpy().astype("float32")

np.savez(OUT, grid=grid, d_exp=d_exp, sigma=np.float32(SIGMA))
print(f"[density] basins A={A.round(2)} B={B.round(2)} -> intermediate mid={mid.round(2)} rad; "
      f"{len(idx)} GT frames; grid{grid.shape} sigma={SIGMA}; d_exp[min,max]=[{d_exp.min():.2f},{d_exp.max():.2f}]; saved {OUT}")
