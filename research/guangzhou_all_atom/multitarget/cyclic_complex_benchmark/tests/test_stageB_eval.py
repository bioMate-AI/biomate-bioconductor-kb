"""Evaluator tests on synthetic data (no real Stage B data touched): detects a planted selection signal, does NOT claim 'best' when there is none,
keeps the CI paired/clustered, and marks the novel-receptor subset. Run: python3 tests/test_stageB_eval.py"""
import csv, json, os, random, sys, tempfile
import numpy as np
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "scripts"))
import stageB_eval as E

def make(tmp, signal, n_train=60, n_test=50, n=25, seed=0):
    rng = np.random.RandomState(seed); man = []; paths = {}
    for split, nc in (("train", n_train), ("test", n_test)):
        rows = []
        for i in range(nc):
            cid = f"{split}_{i}"; cl = f"{split}cl{i // 2}"
            man.append(dict(complex_id=cid, receptor_cluster40=cl, runnable_strict=str(int(i % 2))))
            if split == "test" and i % 3 == 0: man[-1]["receptor_cluster40"] = f"novel{i}"
            elif split == "test": man[-1]["receptor_cluster40"] = f"traincl{i // 2}"      # shares a receptor cluster with TRAIN
            base = rng.uniform(0.0, 0.5)
            for j in range(n):
                good = rng.rand() < 0.25
                sig = good * signal + rng.randn()
                rows.append(dict(complex_id=cid, sample=j, dockq=0.6 if good else base * 0.3,
                                 confidence_score=rng.randn() * 3 + rng.uniform(-5, 5), iptm=rng.randn(), ptm=rng.randn(), if_plddt=rng.randn(),
                                 ring_strain=rng.rand(), clash_count=float(rng.randint(0, 5)),
                                 cons_nbr=float(sig) * 2 + rng.uniform(-5, 5)))
        paths[split] = os.path.join(tmp, f"{split}.jsonl")
        with open(paths[split], "w") as f:
            for r in rows: f.write(json.dumps(r) + "\n")
    mp = os.path.join(tmp, "man.csv")
    with open(mp, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["complex_id", "receptor_cluster40", "runnable_strict"]); w.writeheader(); w.writerows(man)
    return paths, mp

def test_detects_planted_signal():
    tmp = tempfile.mkdtemp(); paths, mp = make(tmp, signal=2.5)
    r = E.run(paths["train"], paths["test"], mp, os.path.join(tmp, "o.json"))
    a = r["all_thr0.23"]
    assert a["S_minus_strongest"]["value"] > 0.15 and a["S_minus_strongest"]["ci95"][0] > 0, a
    assert r["CLAIM_S_best_all_and_novel_at_0.23"] is True
    assert "novel_receptor_thr0.23" in r

def test_no_claim_without_signal():
    tmp = tempfile.mkdtemp(); paths, mp = make(tmp, signal=0.0, seed=3)
    r = E.run(paths["train"], paths["test"], mp, os.path.join(tmp, "o.json"))
    a = r["all_thr0.23"]
    assert a["S_minus_strongest"]["ci95"][0] <= 0 and r["CLAIM_S_best_all_and_novel_at_0.23"] is False, a

def test_oracle_is_upper_bound_and_random_is_between():
    tmp = tempfile.mkdtemp(); paths, mp = make(tmp, signal=1.0, seed=5)
    a = E.run(paths["train"], paths["test"], mp, os.path.join(tmp, "o.json"))["all_thr0.23"]["success"]
    assert a["oracle"] >= max(a[m] for m in ("default", "iptm", "ptm", "if_plddt", "ring_strain", "clash_count", "S")) and 0 <= a["random"] <= a["oracle"]

if __name__ == "__main__":
    n = 0
    for k, f in sorted(globals().items()):
        if k.startswith("test_"): f(); n += 1; print("PASS", k)
    print(f"{n} tests passed")
