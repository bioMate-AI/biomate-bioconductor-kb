"""Frozen PeptideCLM-2 (small) mean-pooled final-layer embeddings for every unique parent/edited SMILES of the pilot (labels never used)."""
import os, sys, numpy as np, pandas as pd, torch, time
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, os.path.join(HERE, "..", "ihlm_backbone"))
from fetch_weights import fetch
from pclm_tokenizer import PClmTokenizer
from pclm_encoder import PClmMLM
torch.set_num_threads(int(os.environ.get("NT", "4")))
size = sys.argv[1] if len(sys.argv) > 1 else "small"
d = fetch(size); tk = PClmTokenizer(os.path.join(d, "tokenizer.json")); m, cfg, res = PClmMLM.from_dir(d); m.eval()
smi = sorted(set(sum([list(pd.read_csv(os.path.join(HERE, "data", f"pairs_{k}.csv"))[c]) for k in ("nme", "dflip") for c in ("smi_parent", "smi_edit")], [])))
ids = [tk.encode(s) for s in smi]; order = np.argsort([len(x) for x in ids]); E = np.zeros((len(smi), cfg["embed_dim"]), np.float32); t0 = time.time(); B = 32
with torch.no_grad():
    for b in range(0, len(order), B):
        idx = order[b:b + B]; L = max(len(ids[i]) for i in idx); X = torch.zeros(len(idx), L, dtype=torch.long); M = torch.zeros(len(idx), L, dtype=torch.long)
        for r, i in enumerate(idx): X[r, :len(ids[i])] = torch.tensor(ids[i]); M[r, :len(ids[i])] = 1
        _, h = m(X, M, return_hidden=True); mm = M.unsqueeze(-1).float(); E[idx] = ((h * mm).sum(1) / mm.sum(1)).numpy()
        if (b // B) % 20 == 0: print(b, len(order), round(time.time() - t0), "s", flush=True)
np.savez(os.path.join(HERE, "data", f"emb_{size}.npz"), smiles=np.array(smi), emb=E, n_unk=np.array([sum(1 for t in x if t == tk.unk_id) if hasattr(tk, "unk_id") else -1 for x in ids]))
print("done", E.shape, "missing/unexpected keys:", res, round(time.time() - t0), "s")
