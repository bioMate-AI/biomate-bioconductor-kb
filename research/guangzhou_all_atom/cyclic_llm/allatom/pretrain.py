#!/usr/bin/env python3
"""Pretrain / benchmark the atom-level LM on the filtered corpus (allatom/PREREG.md G0-G1). Resumable: pulls the latest checkpoint from S3 on start, pushes every ckpt-every steps.
usage: pretrain.py --corpus C.smi.gz --folds-dir DIR --out DIR [--bench] [--steps N] [--batch 128] [--d 512 --layers 8 --heads 8] [--s3 s3://bucket/prefix] [--limit N]"""
import argparse, gzip, json, os, subprocess, sys, time, multiprocessing as mp
import numpy as np, torch
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import atom_lm as A


def _macro(s):
    try: return A.has_macrocycle(s)
    except Exception: return False


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--corpus"); ap.add_argument("--folds-dir"); ap.add_argument("--out", default="/w/out"); ap.add_argument("--bench", action="store_true")
    ap.add_argument("--steps", type=int, default=20000); ap.add_argument("--batch", type=int, default=128); ap.add_argument("--d", type=int, default=512); ap.add_argument("--layers", type=int, default=8); ap.add_argument("--heads", type=int, default=8)
    ap.add_argument("--max-len", type=int, default=256); ap.add_argument("--lr", type=float, default=3e-4); ap.add_argument("--upsample", type=float, default=10.0); ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--ckpt-every", type=int, default=500); ap.add_argument("--s3", default=""); ap.add_argument("--procs", type=int, default=8); a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True); dev = "cuda" if torch.cuda.is_available() else "cpu"; t0 = time.time()
    smiles = [l.strip() for l in gzip.open(a.corpus, "rt") if l.strip()]
    if a.limit: smiles = smiles[:a.limit]
    pep = []
    if a.folds_dir:
        import csv
        for f in range(4): pep += [r["smiles"] for r in csv.DictReader(open(f"{a.folds_dir}/fold{f}_heldout.csv"))]       # vocabulary only (tokens), not training data
    vocab = A.Vocab.build(smiles + pep, max_vocab=800); print("vocab", len(vocab), "molecules", len(smiles), f"({time.time()-t0:.0f}s)", flush=True)
    enc, keep = [], []
    for i, s in enumerate(smiles):
        e = vocab.encode(s)
        if len(e) <= a.max_len: enc.append(np.array(e, np.int16)); keep.append(s)
    with mp.get_context("fork").Pool(a.procs) as p: macro = np.array(p.map(_macro, keep, chunksize=5000))
    print("encoded", len(enc), "macrocycles", int(macro.sum()), f"({time.time()-t0:.0f}s)", flush=True)
    w = A.sampling_weights(macro, a.upsample); json.dump(vocab.itos, open(f"{a.out}/vocab.json", "w"))
    model = A.GPT(len(vocab), d=a.d, layers=a.layers, heads=a.heads, max_len=a.max_len); npar = sum(p.numel() for p in model.parameters()); print("params", npar, "device", dev, flush=True)
    ck = f"{a.out}/ckpt.pt"
    if a.s3 and not a.bench: subprocess.run(["aws", "s3", "cp", f"{a.s3}/ckpt.pt", ck, "--only-show-errors"], capture_output=True)
    resume = os.path.exists(ck) and not a.bench
    def up(path, step):
        if a.s3 and not a.bench: subprocess.run(["aws", "s3", "cp", path, f"{a.s3}/ckpt.pt", "--only-show-errors"]); print("uploaded ckpt step", step, flush=True)
    steps = 150 if a.bench else a.steps; enc_l = [e.astype(np.int64).tolist() for e in enc] if len(enc) <= 300000 else [e.tolist() for e in enc]
    torch.cuda.reset_peak_memory_stats() if dev == "cuda" else None; t1 = time.time()
    A.train(model, enc_l, vocab, steps=steps, batch_size=a.batch, lr=a.lr, seed=0, ckpt=ck, ckpt_every=a.ckpt_every, resume=resume, device=dev, weights=w, log_every=25 if a.bench else 200, amp=True, on_ckpt=up, pool_mult=32)
    dt = time.time() - t1; mean_len = float(np.mean([len(e) for e in enc[:20000]])); tok = steps * a.batch * mean_len
    info = dict(params=npar, device=dev, steps=steps, seconds=round(dt, 1), sec_per_step=round(dt / steps, 4), approx_tokens_per_sec=round(tok / dt), mean_len=round(mean_len, 1), peak_mem_gb=round(torch.cuda.max_memory_allocated() / 1e9, 2) if dev == "cuda" else None,
                n_molecules=len(enc), n_macrocycles=int(macro.sum()))
    json.dump(info, open(f"{a.out}/{'bench' if a.bench else 'pretrain'}.json", "w"), indent=1); print(json.dumps(info), flush=True)


if __name__ == "__main__":
    main()
