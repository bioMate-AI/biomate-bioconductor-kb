#!/usr/bin/env python3
"""A3 replacement test, compute part (EC2 only). usage: bw_psa.py OUT.jsonl [--deadline-min 95] [--n-conf 60]
Boltzmann-weighted polar SASA over ETKDGv3 + MMFF94s conformers for ALL group-B (v2) peptides, ordered round-robin over B sources, one JSON line per peptide
(smiles, source, z, bw_psa, min_psa, n_conf_ok, neff) written as soon as it finishes. Per-molecule limit 120 s. Stops launching new work at the deadline."""
import argparse, json, os, signal, sys, time
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(HERE, ".."))
import verifiers_e as VE
from multiprocessing import get_context

KT = 0.0019872041 * 298.15       # kcal/mol


class _TO(Exception):
    pass


def _alarm(sig, frm):
    raise _TO()


def bw_psa(smiles, n_conf=60, seed=7):
    from rdkit import Chem
    from rdkit.Chem import AllChem, rdFreeSASA
    m = Chem.AddHs(Chem.MolFromSmiles(smiles))
    ps = AllChem.ETKDGv3(); ps.randomSeed = seed; ps.useMacrocycleTorsions = True; ps.useRandomCoords = True; ps.pruneRmsThresh = 0.5; ps.numThreads = 1
    cids = list(AllChem.EmbedMultipleConfs(m, n_conf, ps))
    if not cids:
        return None
    res = AllChem.MMFFOptimizeMoleculeConfs(m, maxIters=500, mmffVariant="MMFF94s", numThreads=1)
    E = np.array([e for _, e in res], float)
    if len(E) != len(cids) or not np.isfinite(E).all():
        return None
    w = np.exp(-(E - E.min()) / KT); w /= w.sum()
    radii = rdFreeSASA.classifyAtoms(m)
    polar = [a.GetIdx() for a in m.GetAtoms() if a.GetAtomicNum() in (7, 8) or (a.GetAtomicNum() == 1 and any(n.GetAtomicNum() in (7, 8) for n in a.GetNeighbors()))]
    psa = []
    for cid in cids:
        rdFreeSASA.CalcSASA(m, radii, confIdx=cid)
        psa.append(sum(float(m.GetAtomWithIdx(i).GetProp("SASA")) for i in polar))
    psa = np.array(psa)
    return dict(bw_psa=float((w * psa).sum()), min_psa=float(psa.min()), n_conf_ok=len(cids), neff=float(1.0 / (w ** 2).sum()))


def work(job):
    smi, src, z, n_conf, t_end, cid = job
    if time.time() > t_end:
        return None
    try:
        signal.signal(signal.SIGALRM, _alarm); signal.alarm(120)
        r = bw_psa(smi, n_conf)
        signal.alarm(0)
    except Exception:
        signal.alarm(0)
        r = None
    return dict(smiles=smi, source=src, z=float(z), cid=cid, **(r or {}), failed=r is None)


if __name__ == "__main__":
    ap = argparse.ArgumentParser(); ap.add_argument("out"); ap.add_argument("--deadline-min", type=float, default=95); ap.add_argument("--n-conf", type=int, default=60)
    a = ap.parse_args()
    d = VE.load_labelled(VE.ANN_DEFAULT); groups = VE.source_groups(d, "v2"); d["g"] = d["Source"].map(groups)
    B = d[d.g == 2].copy()
    rng = np.random.default_rng(2026)
    per = {s: list(g.sample(frac=1.0, random_state=int(rng.integers(1 << 30))).itertuples()) for s, g in B.groupby("Source")}
    order = []
    while any(per.values()):
        for s in sorted(per):
            if per[s]:
                order.append(per[s].pop())
    t_end = time.time() + 60 * a.deadline_min
    jobs = [(r.smiles, r.Source, r.z, a.n_conf, t_end, str(r.cid)) for r in order]
    print("B peptides", len(jobs), "deadline min", a.deadline_min, flush=True)
    done = 0
    with open(a.out, "w") as f, get_context("fork").Pool(max(1, os.cpu_count() or 2)) as pool:
        for r in pool.imap_unordered(work, jobs, chunksize=1):
            if r is None:
                continue
            f.write(json.dumps(r) + "\n"); f.flush(); done += 1
            if done % 25 == 0:
                print(f"[{done}] {time.strftime('%H:%M:%S')}", flush=True)
    print("finished", done, flush=True)
