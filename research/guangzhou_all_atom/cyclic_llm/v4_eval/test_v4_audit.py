"""Positive-control / invariant tests for the v4 unified LLM evaluation path (production run() on synthetic data).
Run: cd cyclic_llm && python3 -m pytest -q v4_eval/test_v4_audit.py"""
import os, sys, gzip, json, random, argparse, tempfile
import numpy as np
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import unified_cyclic_llm as U

AA = list("ACDEFGHIKLMNPQRSTVWY")


def make_world(tmp, planted=True, seed=0, n_per_target=4000, n_bind=800):
    rng = random.Random(seed)
    # CycPeptMPDB-like file (monomer lists + permeability)
    with open(f"{tmp}/cyc.csv", "w") as f:
        f.write("Sequence,Permeability\n")
        for _ in range(700):
            m = [rng.choice(AA + ["meL", "dP", "Sar"]) for _ in range(rng.randint(4, 10))]
            f.write(f"\"{m}\",{rng.uniform(-8, -4.5)}\n")
    rows = []
    for i in range(n_per_target):
        L = rng.randint(7, 12); s = [rng.choice(AA) for _ in range(L)]
        binder = i < n_bind
        if binder and planted:
            p = rng.randrange(0, L - 2); s[p:p + 3] = list("RGD")
        elif (not binder) and planted:
            # decoys never contain the RGD motif
            for p in range(L - 2):
                if "".join(s[p:p + 3]) == "RGD": s[p] = "A"
        enr = rng.uniform(2.6, 4.5) if binder else rng.choice([rng.uniform(-1, 0), rng.uniform(0, 1.2)])
        rows.append(("PADI4", "".join(s), enr, 1 if binder else 0))
    if not planted:   # labels independent of sequence: shuffle label/enrichment columns
        lab = [(r[2], r[3]) for r in rows]; rng.shuffle(lab); rows = [(r[0], r[1], l[0], l[1]) for r, l in zip(rows, lab)]
    rng.shuffle(rows)
    with gzip.open(f"{tmp}/disp.csv.gz", "wt") as f:
        f.write("target,sequence,n_residues,round_or_io,count,enrichment_log2fc,cyclization,display_type,source_accession,is_binder\n")
        for t, s, e, b in rows: f.write(f"{t},{s},{len(s)},R,10,{e},cyc,mrna,x,{b}\n")
    json.dump({"PADI4": {"seq": "MAQGTLIRVTPEQPTHAVCVLGTLTQLDIC" * 5}}, open(f"{tmp}/t.json", "w"))


def run_v4(tmp, steps=900):
    a = argparse.Namespace(cycpept=f"{tmp}/cyc.csv", display=f"{tmp}/disp.csv.gz", targets=f"{tmp}/t.json", max_len=16, max_steps=steps, batch=64,
                           block=40, d_model=64, n_layer=2, n_head=4, lr=1e-3, oversample_hi=2, n_sample=20, temp=1.0, max_test=800, out=None, ckpt=None)
    return U.run(a)


def test_planted_signal_is_detected():
    with tempfile.TemporaryDirectory() as tmp:
        make_world(tmp, planted=True); res = run_v4(tmp)
        auc = res["B_multitarget_binding_AUC"]["PADI4"]["AUC"]
        assert auc > 0.9, f"v4 pipeline failed to detect a planted RGD motif (AUC={auc})"


def test_shuffled_labels_give_chance():
    with tempfile.TemporaryDirectory() as tmp:
        make_world(tmp, planted=False); res = run_v4(tmp)
        auc = res["B_multitarget_binding_AUC"]["PADI4"]["AUC"]
        assert 0.40 < auc < 0.60, f"AUC {auc} on label-shuffled data should be ~0.5"


def test_scoring_alignment_matches_training_alignment():
    """Training uses logits[:, :-1] vs X (position i predicts token i because of the target prefix at position 0); scoring must use the same."""
    import torch
    from train_cyclic_llm_v3 import make_model, TFEAT_DIM
    torch.manual_seed(0)
    V = 30; m = make_model(V, TFEAT_DIM, d_model=32, n_layer=2, n_head=4, block=20).eval()
    X = torch.randint(3, V, (1, 9)); tf = torch.randn(1, TFEAT_DIM)
    with torch.no_grad(): lg = m(X, tf)
    ce = torch.nn.functional.cross_entropy(lg[:, :-1].reshape(-1, V), X.reshape(-1), reduction="sum")
    lp = torch.log_softmax(lg[0], -1); score = -float(lp[torch.arange(X.shape[1]), X[0]].sum())
    assert abs(float(ce) - score) < 1e-4


def test_split_invariants_on_synthetic():
    """Documented property (audit finding): every is_binder row goes to the TEST side when #binders <= nte//2; assert so a silent change is noticed."""
    rng = random.Random(0)
    rs = [{"is_binder": i < 100, "x": i} for i in range(5000)]; rng.shuffle(rs)
    nte = min(3000, max(200, int(len(rs) * 0.2)))
    bind = [r for r in rs if r["is_binder"]]; non = [r for r in rs if not r["is_binder"]]
    te = bind[:nte // 2] + non[:nte - len(bind[:nte // 2])]; teset = {id(r) for r in te}
    tr = [r for r in rs if id(r) not in teset]
    assert sum(r["is_binder"] for r in tr) == 0 and sum(r["is_binder"] for r in te) == 100
