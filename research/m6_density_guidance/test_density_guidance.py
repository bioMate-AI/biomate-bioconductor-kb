"""
Engineering validation of the M6 density-guidance term against OM-TPS's REAL actions.py.
NOT a scientific proof (no real protein / no experimental kinetics) — this checks the CODE is
correct before spending on a GPU Batch run: (1) gradient correctness (finite-diff vs autograd),
(2) correct composition with the real TruncatedAction & HutchinsonAction, (3) the term measurably
moves the path toward the observed density and (ablation) barely moves it when the density agrees.
"""
import sys, torch
sys.path.insert(0, "/Users/kky/biomate/research/OM-TPS/two-for-one-diffusion")
from actions import TruncatedAction, HutchinsonAction   # the REAL OM-TPS code
import density_guidance as dg

torch.manual_seed(0)
torch.set_default_dtype(torch.float64)   # tight finite-diff checks

N = 6           # atoms
P = 8           # path frames
M = 64          # density grid points
SIGMA = 0.6
ok = True

# ---- a differentiable "experimental" density from a known target state ----
grid = (torch.rand(M, 3) - 0.5) * 6.0
x_target = torch.randn(N, 3)                    # the observed state
d_exp = dg.simulate_density(x_target, grid, SIGMA).detach()

# =====================================================================
print("="*70)
print("TEST 1 — gradient correctness of the density term (finite-diff vs autograd)")
print("="*70)
path = torch.randn(1, P, N, 3, requires_grad=True)
val = dg.density_term(path, grid, d_exp, SIGMA)
val.backward()
g_auto = path.grad.clone()

eps = 1e-6
g_fd = torch.zeros_like(path)
flat = path.detach().clone()
for idx in range(path.numel()):
    fp = flat.clone().view(-1); fp[idx] += eps
    vp = dg.density_term(fp.view(1, P, N, 3), grid, d_exp, SIGMA)
    fm = flat.clone().view(-1); fm[idx] -= eps
    vm = dg.density_term(fm.view(1, P, N, 3), grid, d_exp, SIGMA)
    g_fd.view(-1)[idx] = (vp - vm) / (2 * eps)
max_err = (g_auto - g_fd).abs().max().item()
rel = max_err / (g_fd.abs().max().item() + 1e-12)
print(f"  max|autograd - finite_diff| = {max_err:.3e}   (rel {rel:.3e})")
t1 = max_err < 1e-5
print(f"  -> {'PASS' if t1 else 'FAIL'} (autograd gradient is correct)"); ok &= t1

# =====================================================================
print("\n" + "="*70)
print("TEST 2 — composes with the REAL TruncatedAction & HutchinsonAction")
print("="*70)
# toy analytic force_func: double-well in x, harmonic in y,z  (F = -grad U)
def force_func(x):                       # x [*, N, 3]
    fx = -(4*x[..., 0:1]**3 - 4*x[..., 0:1])   # dU/dx of (x^2-1)^2
    fyz = -x[..., 1:3]
    return torch.cat([fx, fyz], dim=-1)

gamma = torch.ones(N)
for Action, kw, name in [(TruncatedAction, {}, "TruncatedAction"),
                         (HutchinsonAction, dict(D=1.0), "HutchinsonAction")]:
    act = Action(force_func, dt=0.01, gamma=gamma, **kw)
    p = torch.randn(1, P, N, 3, requires_grad=True)
    total, om = dg.guided_action(act, p, grid, d_exp, SIGMA, lam=0.0)
    total.backward()
    finite = torch.isfinite(p.grad).all().item() and torch.isfinite(total).item()
    # lam>0 must change the objective and the gradient
    p2 = p.detach().clone().requires_grad_(True)
    tot2, om2 = dg.guided_action(act, p2, grid, d_exp, SIGMA, lam=5.0)
    tot2.backward()
    changed = (abs((tot2 - om2).item()) > 1e-6) and ((p.grad - p2.grad).abs().max().item() > 1e-6)
    good = finite and changed
    print(f"  {name:18s}: OM={om.item():9.3f} finite_grads={finite} "
          f"density_changes_objective&grad={changed} -> {'PASS' if good else 'FAIL'}")
    ok &= good

# =====================================================================
print("\n" + "="*70)
print("TEST 3 — the term MOVES the path to the observed state, and (ablation) NOT when it agrees")
print("="*70)
act = TruncatedAction(force_func, dt=0.01, gamma=gamma)
A = torch.full((N, 3), -1.0); B = torch.full((N, 3), 1.0)   # endpoints in the two wells (x=-1,+1)

def optimize(lam, d_target, steps=400):
    t = torch.linspace(0, 1, P)[:, None, None]
    inner = ((1 - t) * A + t * B)[1:-1].clone().requires_grad_(True)
    opt = torch.optim.Adam([inner], lr=0.02)
    for _ in range(steps):
        opt.zero_grad()
        path = torch.cat([A[None], inner, B[None]], 0)[None]
        tot, _ = dg.guided_action(act, path, grid, d_target, SIGMA, lam=lam)
        tot.backward(); opt.step()
    with torch.no_grad():
        path = torch.cat([A[None], inner.detach(), B[None]], 0)
    return path

base = optimize(lam=0.0, d_target=d_exp)
# informative anchor: a density at an off-path state (shift target far in +y)
x_off = x_target.clone(); x_off[:, 1] += 3.0
d_off = dg.simulate_density(x_off, grid, SIGMA).detach()
def closest(path, xt):   # min over frames of mean-atom distance to target coords
    return min(((path[k] - xt)**2).sum(-1).mean().sqrt().item() for k in range(path.shape[0]))
c0 = closest(base, x_off)
# lambda must be scaled to the OM-action magnitude (here OM ~ 1e3-1e4, density nll ~ O(1)).
# Sweep lambda; the informative anchor should pull the path toward the observed state as lambda grows.
print(f"  unguided closest-approach to off-path observed state = {c0:.3f}")
last = None
for lam in [0.0, 1e2, 1e3, 1e4]:
    g = optimize(lam=lam, d_target=d_off)
    last = g
    rmsd = (g - base).pow(2).sum(-1).mean().sqrt().item()
    print(f"    lam={lam:8.0f} | closest-approach={closest(g, x_off):.3f} | path RMSD vs unguided={rmsd:.3f}")
c1 = closest(last, x_off)
t3a = c1 < c0 - 0.1
print(f"  -> at sufficient lam the path moves toward the observed state: {'YES' if t3a else 'no'}")
ok &= t3a

# ablation at matched (large) lam: informative (off-path) vs agreeing (on-path) anchor
LAM = 1e4
x_on = base[P // 2].detach()
d_on = dg.simulate_density(x_on, grid, SIGMA).detach()
shift_off = (optimize(lam=LAM, d_target=d_off) - base).pow(2).sum(-1).mean().sqrt().item()
shift_on  = (optimize(lam=LAM, d_target=d_on)  - base).pow(2).sum(-1).mean().sqrt().item()
print(f"  ablation @ lam={LAM:.0f}:  informative anchor RMSD={shift_off:.3f}   agreeing anchor RMSD={shift_on:.3f}")
t3b = shift_off > shift_on
print(f"  -> informative anchor moves the path MORE than an agreeing one: "
      f"{'YES (ablation logic holds)' if t3b else 'no'}")
ok &= t3b

print("\n" + "="*70)
print(f"OVERALL: {'ALL PASS' if ok else 'FAILURE'}")
print("Scope: validates the density-guidance CODE (gradient + composition with real OM-TPS")
print("actions.py + expected path response). NOT scientific proof — that needs the real")
print("pretrained model + experimental kinetics on GPU/Batch.")
print("="*70)
sys.exit(0 if ok else 1)
