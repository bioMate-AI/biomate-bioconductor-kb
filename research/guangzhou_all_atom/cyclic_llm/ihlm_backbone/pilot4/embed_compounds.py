"""Pilot 4 step: mean-pooled final-norm hidden states of PeptideCLM-2 small (our re-implementation) for every compound in retro_recovery/data/compounds.csv.gz.
Pooling fixed as in pilot 1 (A2): final LayerNorm hidden state, mean over tokens excluding [CLS]/[SEP]. No fine-tuning. usage: python3 embed_compounds.py OUT.npz"""
import os, sys, time, hashlib
import numpy as np, torch, pandas as pd
HERE = os.path.dirname(os.path.abspath(__file__)); BB = os.path.abspath(f"{HERE}/.."); sys.path.insert(0, BB)
from fetch_weights import fetch
from pclm_encoder import PClmMLM
from pclm_tokenizer import PClmTokenizer
out = sys.argv[1]; torch.set_num_threads(int(os.environ.get("NT", "4")))
CP = os.path.abspath(f"{HERE}/../../../multitarget/integrin_chembl/retro_recovery/data/compounds.csv.gz")
c = pd.read_csv(CP); smi = c.iso_smiles.values; cid = c.compound_id.values
wd = fetch("small"); tk = PClmTokenizer(os.path.join(wd, "tokenizer.json"), max_len=512); m, cfg, res = PClmMLM.from_dir(wd); m.eval()
enc = [tk.encode(s) for s in smi]; order = np.argsort([len(e) for e in enc]); E = np.zeros((len(smi), cfg["embed_dim"]), np.float32); t0 = time.time(); B = 32
with torch.no_grad():
    for b in range(0, len(order), B):
        ii = order[b:b + B]; L = max(len(enc[i]) for i in ii); X = torch.zeros((len(ii), L), dtype=torch.long); M = torch.zeros((len(ii), L), dtype=torch.long)
        for j, i in enumerate(ii): X[j, :len(enc[i])] = torch.tensor(enc[i]); M[j, :len(enc[i])] = 1
        _, h = m(X, M, return_hidden=True)
        for j, i in enumerate(ii): E[i] = h[j, 1:len(enc[i]) - 1].mean(0).numpy()
        if (b // B) % 40 == 0: print(b, len(order), round(time.time() - t0), "s", flush=True)
n_trunc = int(sum(len(e) >= 512 for e in enc))
np.savez(out, E=E, compound_id=cid, n_truncated=n_trunc)
print("done", E.shape, "truncated", n_trunc, "finite", bool(np.isfinite(E).all()), "sha256", hashlib.sha256(E.tobytes()).hexdigest(), round(time.time() - t0), "s")
