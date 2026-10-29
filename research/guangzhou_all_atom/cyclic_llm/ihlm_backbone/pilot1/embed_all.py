"""Pilot 1 step: mean-pooled final-norm hidden states of PeptideCLM-2 (our re-implementation) for every CycPeptMPDB labelled peptide.
Pooling (fixed, A2): hidden state after the final LayerNorm, mean over tokens excluding [CLS] and [SEP]. No fine-tuning. usage: python3 embed_all.py small|base OUT.npz"""
import os, sys, time, hashlib
import numpy as np, torch
HERE = os.path.dirname(os.path.abspath(__file__)); BB = os.path.abspath(f"{HERE}/.."); sys.path.insert(0, BB)
sys.path.insert(0, os.path.abspath(f"{HERE}/../../stratification"))
from fetch_weights import fetch
from pclm_encoder import PClmMLM
from pclm_tokenizer import PClmTokenizer
import common as C
size, out = sys.argv[1], sys.argv[2]
torch.set_num_threads(int(os.environ.get("NT", "4")))
d = C.load_labelled(); smi = d.SMILES.values; idx = d.index.values
wd = fetch(size); tk = PClmTokenizer(os.path.join(wd, "tokenizer.json"), max_len=512); m, cfg, res = PClmMLM.from_dir(wd); m.eval()
enc = [tk.encode(s) for s in smi]; order = np.argsort([len(e) for e in enc]); E = np.zeros((len(smi), cfg["embed_dim"]), np.float32); t0 = time.time(); B = 32
with torch.no_grad():
    for b in range(0, len(order), B):
        ii = order[b:b + B]; L = max(len(enc[i]) for i in ii); X = torch.zeros((len(ii), L), dtype=torch.long); M = torch.zeros((len(ii), L), dtype=torch.long)
        for j, i in enumerate(ii): X[j, :len(enc[i])] = torch.tensor(enc[i]); M[j, :len(enc[i])] = 1
        _, h = m(X, M, return_hidden=True)
        for j, i in enumerate(ii): E[i] = h[j, 1:len(enc[i]) - 1].mean(0).numpy()
        if (b // B) % 40 == 0: print(size, b, len(order), round(time.time() - t0), "s", flush=True)
n_trunc = int(sum(len(e) >= 512 for e in enc))
np.savez(out, E=E, index=idx, n_truncated=n_trunc, weights_sha=open(os.path.join(wd, "config.json")).read()[:0])
print("done", size, E.shape, "truncated", n_trunc, "finite", bool(np.isfinite(E).all()), "sha256", hashlib.sha256(E.tobytes()).hexdigest(), round(time.time() - t0), "s")
