"""Model (c): conformer-ensemble 3D features. RDKit ETKDGv3 (macrocycle torsions) + MMFF94s, K conformers/peptide.
Per-peptide summaries over the ensemble: 3D PSA (polar SASA, Shrake-Rupley via rdFreeSASA), total SASA, radius of gyration,
asphericity, number of intramolecular backbone N-H...O=C H-bonds (H...O<2.5A, N-H...O angle>120), MMFF energy spread.
Resumable jsonl cache keyed by pid; per-molecule hard timeout. Usage: conf_features.py WORKERS K [LIMIT]"""
import sys, json, time, signal, numpy as np, pandas as pd
from concurrent.futures import ProcessPoolExecutor, as_completed
from rdkit import Chem, RDLogger
from rdkit.Chem import AllChem, Descriptors3D, rdFreeSASA, rdMolTransforms
from common import *
RDLogger.DisableLog("rdApp.*")
CACHE = os.path.join(SCRATCH, "conf_cache.jsonl")
FINAL = os.path.join(HERE, "data/conf_features.csv")
TMO = 90

class TO(Exception): pass
def _h(*a): raise TO()

def featurize(args):
    pid, smi, K = args
    signal.signal(signal.SIGALRM, _h); signal.alarm(TMO)
    t0 = time.time()
    try:
        m = Chem.AddHs(Chem.MolFromSmiles(smi))
        ps = AllChem.ETKDGv3(); ps.randomSeed = 7; ps.numThreads = 1; ps.useRandomCoords = True; ps.maxIterations = 200
        cids = list(AllChem.EmbedMultipleConfs(m, K, ps))
        if not cids: return {"pid": pid, "fail": "embed"}
        res = AllChem.MMFFOptimizeMoleculeConfs(m, maxIters=500, numThreads=1)
        en = np.array([e for _, e in res])
        radii = rdFreeSASA.classifyAtoms(m)
        polar = np.array([a.GetSymbol() in ("N", "O") or (a.GetSymbol() == "H" and a.GetNeighbors()[0].GetSymbol() in ("N", "O")) for a in m.GetAtoms()])
        donorH = [(a.GetIdx(), a.GetNeighbors()[0].GetIdx()) for a in m.GetAtoms() if a.GetSymbol() == "H" and a.GetNeighbors()[0].GetSymbol() == "N"]
        acc = [a.GetIdx() for a in m.GetAtoms() if a.GetSymbol() == "O" and a.GetDegree() == 1]
        rows = []
        for i, cid in enumerate(cids):
            sasa = rdFreeSASA.CalcSASA(m, radii, confIdx=cid)
            at = np.array([float(a.GetProp("SASA")) for a in m.GetAtoms()])
            conf = m.GetConformer(cid); pos = conf.GetPositions()
            nhb = 0
            for h, n in donorH:
                for o in acc:
                    if o == n: continue
                    dho = np.linalg.norm(pos[h] - pos[o])
                    if dho < 2.5:
                        v1 = pos[n] - pos[h]; v2 = pos[o] - pos[h]
                        ang = np.degrees(np.arccos(np.dot(v1, v2) / (np.linalg.norm(v1) * np.linalg.norm(v2) + 1e-9)))
                        if ang > 120: nhb += 1; break
            rows.append([at[polar].sum(), sasa, Descriptors3D.RadiusOfGyration(m, confId=cid), Descriptors3D.Asphericity(m, confId=cid), nhb])
        R = np.array(rows); w = np.exp(-(en - en.min()) / 2.5); w /= w.sum()   # Boltzmann at ~kT=2.5 kJ-ish units of MMFF kcal (coarse)
        out = {"pid": pid, "nconf": len(cids), "sec": time.time() - t0}
        for j, nm in enumerate(["psa3d", "sasa", "rg", "asph", "nhb"]):
            out[nm + "_min"] = float(R[:, j].min()); out[nm + "_mean"] = float(R[:, j].mean()); out[nm + "_max"] = float(R[:, j].max()); out[nm + "_boltz"] = float((w * R[:, j]).sum())
        out["psa3d_range"] = out["psa3d_max"] - out["psa3d_min"]; out["e_spread"] = float(en.max() - en.min())
        out["psa_frac_min"] = float((R[:, 0] / R[:, 1]).min())
        return out
    except TO:
        return {"pid": pid, "fail": "timeout"}
    except Exception as e:
        return {"pid": pid, "fail": repr(e)[:80]}
    finally:
        signal.alarm(0)

if __name__ == "__main__":
    W = int(sys.argv[1]); K = int(sys.argv[2]); LIM = int(sys.argv[3]) if len(sys.argv) > 3 else None
    c = pd.read_csv(CLEAN).drop_duplicates("pid")
    done = set()
    if os.path.exists(CACHE):
        for l in open(CACHE): done.add(json.loads(l)["pid"])
    todo = [(r.pid, r.can, K) for r in c.itertuples() if r.pid not in done]
    import random; random.Random(0).shuffle(todo)   # random order => any prefix is a random sample
    if LIM: todo = todo[:LIM]
    print(f"{len(done)} cached, {len(todo)} todo", flush=True)
    t0 = time.time(); n = 0
    with ProcessPoolExecutor(W) as ex, open(CACHE, "a") as fh:
        futs = [ex.submit(featurize, a) for a in todo]
        for f in as_completed(futs):
            fh.write(json.dumps(f.result()) + "\n"); fh.flush(); n += 1
            if n % 100 == 0: print(n, f"{(time.time()-t0)/n:.2f}s/mol-wall", flush=True)
    rows = [json.loads(l) for l in open(CACHE)]
    ok = pd.DataFrame([r for r in rows if "fail" not in r]).drop_duplicates("pid")
    ok.to_csv(FINAL, index=False); print("ok", len(ok), "fail", sum("fail" in r for r in rows))
