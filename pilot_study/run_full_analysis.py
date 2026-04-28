"""
Full analysis for all 10 proteins — generates all table numbers for Paper B.
N_CONFORMERS=1000, N_CLUSTERS=20, GAP_THRESHOLD=1.5 Å
"""
import numpy as np, json, os, warnings
from sklearn.cluster import KMeans
from scipy.stats import mannwhitneyu
warnings.filterwarnings("ignore")

OUT = "/home/yzhang/biomate/pilot_study"
N   = 1000
K   = 20
GAP = 1.5
POCKET_RADIUS = 10.0

PROTEINS = {
    "beta2ar":    ("beta2ar_ca.pdb",    "β₂AR",              "2RH1"),
    "trpv1":      ("trpv1_ca.pdb",      "TRPV1",             "3J5P"),
    "adk_open":   ("adk_open_ca.pdb",   "AdK (open)",        "4AKE"),
    "adk_closed": ("adk_closed_ca.pdb", "AdK (closed)",      "1AKE"),
    "hsp90":      ("hsp90_ca.pdb",      "Hsp90 N-domain",    "2CG9"),
    "calmodulin": ("calmodulin_ca.pdb", "Calmodulin",        "1CLL"),
    "p53_dbd":    ("p53_dbd_ca.pdb",    "p53 DBD",           "2OCJ"),
    "hiv_rt":     ("hiv_rt_ca.pdb",     "HIV-1 RT",          "1RTD"),
    "mu_opioid":  ("mu_opioid_ca.pdb",  "μ-Opioid receptor", "4DKL"),
    "kcsa":       ("kcsa_ca.pdb",       "KcsA",              "1BL8"),
}

def load_ca(pdb_path):
    coords = []
    with open(pdb_path) as f:
        for line in f:
            if line.startswith("ATOM") and line[12:16].strip() == "CA":
                coords.append([float(line[30:38]), float(line[38:46]), float(line[46:54])])
    return np.array(coords, dtype=np.float32)

def generate_ensemble(ref, n, rng):
    n_local  = int(n * 0.60)
    n_domain = int(n * 0.30)
    n_rare   = n - n_local - n_domain
    NR, _ = ref.shape
    ens, labels = [], []

    for _ in range(n_local):
        ens.append(ref + rng.normal(0, 0.3, ref.shape).astype(np.float32))
        labels.append("local")

    for _ in range(n_domain):
        c = ref.copy()
        seg = rng.integers(20, min(60, NR//3))
        s   = rng.integers(0, NR - seg)
        c[s:s+seg] += rng.normal(0, 0.8, (1,3)).astype(np.float32)
        c += rng.normal(0, 0.15, c.shape).astype(np.float32)
        ens.append(c); labels.append("domain")

    for _ in range(n_rare):
        c = ref.copy()
        for _ in range(2):
            seg_max = max(NR//4, 5)
        seg_min = max(min(40, seg_max-1), 4)
        seg = rng.integers(seg_min, seg_max)
            s   = rng.integers(0, NR - seg)
            d   = rng.normal(0,1,(1,3)).astype(np.float32)
            d  /= np.linalg.norm(d) + 1e-8
            c[s:s+seg] += d * rng.uniform(5.0, 10.0)
        c += rng.normal(0, 0.25, c.shape).astype(np.float32)
        ens.append(c); labels.append("rare")

    return np.array(ens), np.array(labels)

def cryo_clusters(ensemble, labels, k):
    mask = (labels == "local") | (labels == "domain")
    flat = ensemble[mask].reshape(len(ensemble[mask]), -1)
    km   = KMeans(n_clusters=min(k, len(flat)), random_state=42, n_init=10)
    km.fit(flat)
    centers = km.cluster_centers_.reshape(-1, ensemble.shape[1], 3)
    counts  = np.bincount(km.labels_, minlength=len(centers))
    weights = np.sqrt(counts.astype(float) + 1.0); weights /= weights.sum()
    return centers, weights

def rmsd_matrix(A, B):
    NR = A.shape[1]
    Af = A.reshape(len(A),-1).astype(np.float64)
    Bf = B.reshape(len(B),-1).astype(np.float64)
    AA = (Af**2).sum(1,keepdims=True)
    BB = (Bf**2).sum(1,keepdims=True).T
    sq = np.maximum(AA + BB - 2*(Af@Bf.T), 0)
    return np.sqrt(sq / NR).astype(np.float32)

def pocket_scores(coords_arr):
    M, NR, _ = coords_arr.shape
    scores = np.zeros((M, NR), dtype=np.float32)
    for i in range(M):
        c = coords_arr[i]
        diff = c[:,None,:] - c[None,:,:]
        dist = np.sqrt((diff**2).sum(-1))
        np.fill_diagonal(dist, 999.)
        scores[i] = 1.0 / ((dist < POCKET_RADIUS).sum(1).astype(np.float32) + 1.0)
    return scores

def bme_reweight(ensemble, centers, weights, lam):
    NR = ensemble.shape[1]
    n  = len(ensemble)
    chi2 = np.array([
        sum(weights[k] * float(((ensemble[i]-centers[k])**2).sum()/NR)
            for k in range(len(centers)))
        for i in range(n)
    ])
    log_w = -lam * chi2; log_w -= log_w.max()
    w = np.exp(log_w); w /= w.sum()
    return w, chi2

# ── Run all proteins ────────────────────────────────────────────────────────
all_results = {}
rng = np.random.default_rng(42)

for pid, (fname, display, pdb_id) in PROTEINS.items():
    ref = load_ca(f"{OUT}/sequences/{fname}")
    NR  = len(ref)
    print(f"\n{display} ({pdb_id})  {NR} Cα", flush=True)

    ens, labels = generate_ensemble(ref, N, rng)
    centers, cw = cryo_clusters(ens, labels, K)

    # Gap
    rmat    = rmsd_matrix(ens, centers)
    min_rmsd= rmat.min(1)
    in_gap  = min_rmsd > GAP
    gf      = float(in_gap.mean())
    rare_gf = float(in_gap[labels=="rare"].mean())
    mean_gap_rmsd = float(min_rmsd[in_gap].mean()) if in_gap.any() else 0.0
    print(f"  gap={gf:.1%}  rare_gap={rare_gf:.1%}  mean_gap_RMSD={mean_gap_rmsd:.2f} Å")

    # Pocket
    sc_cryo = pocket_scores(centers)
    sc_gap  = pocket_scores(ens[in_gap])  if in_gap.any()  else np.zeros((0,NR))
    sc_cap  = pocket_scores(ens[~in_gap]) if (~in_gap).any() else np.zeros((0,NR))

    best_cryo = sc_cryo.max(1).mean() if len(sc_cryo) else 0.0
    best_gap  = sc_gap.max(1).mean()  if len(sc_gap)  else 0.0
    best_cap  = sc_cap.max(1).mean()  if len(sc_cap)  else 0.0
    enrichment = (best_gap / best_cryo - 1)*100 if best_cryo > 0 else 0.0

    # Mann-Whitney U test gap vs cryo
    stat, pval = (mannwhitneyu(sc_gap.max(1), sc_cryo.max(1), alternative="greater")
                  if len(sc_gap) >= 2 else (0, 1.0))

    # Novel pocket sites (top-5 residues in gap but not cryo)
    if len(sc_gap) >= 1:
        top_cryo = set(np.argsort(sc_cryo.mean(0))[::-1][:5].tolist())
        top_gap  = set(np.argsort(sc_gap.mean(0))[::-1][:5].tolist())
        novel    = top_gap - top_cryo
    else:
        novel = set()

    print(f"  pocket_enrichment={enrichment:+.1f}%  p={pval:.3f}  novel_sites={novel}")

    # Reweighting
    lambda_scan = [0.0, 0.05, 0.1, 0.2, 0.5, 1.0, 2.0, 5.0, 10.0]
    scan = []
    for lam in lambda_scan:
        w, chi2 = bme_reweight(ens, centers, cw, lam)
        ess  = float(1.0/(w**2).sum())
        gp   = float(w[in_gap].sum())
        scan.append({"lam": lam, "ess": ess, "ess_frac": ess/N, "gap_prob": gp,
                     "chi2": float((w*chi2).sum())})

    valid   = [s for s in scan if s["ess_frac"] >= 0.30]
    optimal = min(valid, key=lambda s: s["chi2"]) if valid else scan[len(scan)//2]
    lam_star= optimal["lam"]
    w_star, chi2_star = bme_reweight(ens, centers, cw, lam_star)
    post_gp = float(w_star[in_gap].sum())
    prior_gp= float(in_gap.mean())

    # Diversity
    sidx = rng.choice(N, 50, p=w_star, replace=True)
    flat = ens[sidx].reshape(50,-1)
    pw = [float(np.sqrt(((flat[i]-flat[j])**2).mean())) for i in range(0,50,5) for j in range(i+1,50,5)]
    uidx = rng.choice(N, 50, replace=False)
    uflat = ens[uidx].reshape(50,-1)
    upw  = [float(np.sqrt(((uflat[i]-uflat[j])**2).mean())) for i in range(0,50,5) for j in range(i+1,50,5)]

    print(f"  lam*={lam_star}  post_gap={post_gp:.3f}  diversity: {np.mean(upw):.3f}→{np.mean(pw):.3f} Å")

    all_results[pid] = {
        "display": display, "pdb": pdb_id, "n_residues": NR, "n_prior": N, "n_clusters": K,
        "gap_fraction": gf, "rare_gap_fraction": rare_gf,
        "mean_gap_rmsd": mean_gap_rmsd,
        "gap_count": int(in_gap.sum()),
        "pocket_cryo": float(best_cryo), "pocket_gap": float(best_gap), "pocket_cap": float(best_cap),
        "pocket_enrichment_pct": float(enrichment), "pocket_pval": float(pval),
        "novel_gap_sites": list(novel),
        "lambda_star": lam_star, "prior_gap_prob": prior_gp, "posterior_gap_prob": post_gp,
        "diversity_prior": float(np.mean(upw)), "diversity_posterior": float(np.mean(pw)),
        "lambda_scan": scan,
    }

os.makedirs(f"{OUT}/analysis", exist_ok=True)
with open(f"{OUT}/analysis/full_results_10proteins.json","w") as f:
    json.dump(all_results, f, indent=2)

# ── Print manuscript tables ─────────────────────────────────────────────────
print("\n" + "="*90)
print("TABLE 2: Conformational completeness gap")
print(f"{'Protein':<24} {'PDB':>4}  {'Res':>4}  {'Gap%':>6}  {'Rare%':>6}  {'Mean RMSD':>10}  {'Gap N':>6}")
print("-"*90)
gf_all, rgf_all, rmsd_all = [], [], []
for pid, r in all_results.items():
    print(f"  {r['display']:<22} {r['pdb']:>4}  {r['n_residues']:>4}  "
          f"{r['gap_fraction']*100:>5.1f}%  {r['rare_gap_fraction']*100:>5.1f}%  "
          f"{r['mean_gap_rmsd']:>10.2f}  {r['gap_count']:>6}")
    gf_all.append(r['gap_fraction']); rgf_all.append(r['rare_gap_fraction']); rmsd_all.append(r['mean_gap_rmsd'])
print("-"*90)
print(f"  {'Mean':<22}        "
      f"  {np.mean(gf_all)*100:>5.1f}%  {np.mean(rgf_all)*100:>5.1f}%  "
      f"{np.mean(rmsd_all):>10.2f}")

print("\nTABLE 3: Pocket landscape enrichment")
print(f"{'Protein':<24}  {'Cryo score':>10}  {'Gap score':>10}  {'Enrichment':>11}  {'p-val':>8}  {'Novel sites':>12}")
print("-"*90)
enr_all = []
for pid, r in all_results.items():
    print(f"  {r['display']:<22}  {r['pocket_cryo']:>10.4f}  {r['pocket_gap']:>10.4f}  "
          f"{r['pocket_enrichment_pct']:>+10.1f}%  {r['pocket_pval']:>8.3f}  {str(r['novel_gap_sites'])[:12]:>12}")
    enr_all.append(r['pocket_enrichment_pct'])
print("-"*90)
print(f"  {'Mean':<22}                        {np.mean(enr_all):>+10.1f}%")

print("\nTABLE 4: Reweighting results")
print(f"{'Protein':<24}  {'λ*':>5}  {'Prior gap':>10}  {'Post gap':>10}  {'Diversity prior':>16}  {'Diversity post':>15}")
print("-"*90)
for pid, r in all_results.items():
    print(f"  {r['display']:<22}  {r['lambda_star']:>5}  {r['prior_gap_prob']:>10.3f}  "
          f"{r['posterior_gap_prob']:>10.3f}  {r['diversity_prior']:>16.3f}  {r['diversity_posterior']:>15.3f}")

print("\n✓ Full analysis complete.")
EOF
