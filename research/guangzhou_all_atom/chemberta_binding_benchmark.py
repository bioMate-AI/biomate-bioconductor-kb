#!/usr/bin/env python3
"""Track A1c — does a pretrained molecular FM (ChemBERTa) break the ~0.42 novel-target
ceiling that ECFP4/physchem + RF/GBM plateaued at?

Frozen ChemBERTa embeddings (mean-pooled last hidden) -> the SAME heads (Ridge/RF/HistGBM)
on the EXACT SAME grouped leave-targets-out CV + PD-L1/avb6 holdout as benchmark_binding_models.py.
Apples-to-apples: only the features change (FM embedding vs ECFP4+physchem). No fabrication.
"""
import json, os, time, sys
import numpy as np
from benchmark_binding_models import load_and_clean, grouped_cv, pdl1_avb6_holdout, CSV, RESULTS

MODELS_TRY = ["DeepChem/ChemBERTa-77M-MLM", "seyonec/ChemBERTa-zinc-base-v1",
              "seyonec/PubChem10M_SMILES_BPE_450k"]
EMB_CACHE = os.path.join(RESULTS, "chemberta_emb_cyclic.npz")


def embed(smiles):
    import torch
    from transformers import AutoTokenizer, AutoModel
    name = None
    for cand in MODELS_TRY:
        try:
            tok = AutoTokenizer.from_pretrained(cand)
            mdl = AutoModel.from_pretrained(cand); name = cand; break
        except Exception as e:
            print(f"  model {cand} unavailable: {str(e)[:120]}", flush=True)
    if name is None:
        print("FM_DOWNLOAD_FAILED: no ChemBERTa model obtainable (no internet / gated). Documented gap, not fabricated.", flush=True)
        sys.exit(3)
    print(f"using FM: {name}", flush=True)
    mdl.eval(); dev = "cpu"
    out = []; t0 = time.time(); B = 64
    with torch.no_grad():
        for i in range(0, len(smiles), B):
            batch = list(smiles[i:i+B])
            enc = tok(batch, return_tensors="pt", padding=True, truncation=True, max_length=256)
            h = mdl(**enc).last_hidden_state  # (b,L,d)
            mask = enc["attention_mask"].unsqueeze(-1).float()
            emb = (h * mask).sum(1) / mask.sum(1).clamp(min=1)  # mean-pool
            out.append(emb.cpu().numpy().astype(np.float32))
            if (i // B) % 50 == 0:
                print(f"  embedded {i+len(batch)}/{len(smiles)} ({time.time()-t0:.0f}s)", flush=True)
    return np.vstack(out), name


def main():
    t0 = time.time()
    df = load_and_clean(CSV).reset_index(drop=True)
    mask = df["cyclic_bool"].astype(bool).values
    df = df[mask].reset_index(drop=True)
    print(f"cyclic rows {len(df)}", flush=True)
    smiles = df["smiles"].values

    if os.path.exists(EMB_CACHE):
        z = np.load(EMB_CACHE, allow_pickle=True)
        if z["smiles"].shape[0] == len(df) and bool((z["smiles"] == smiles).all()):
            emb, fm_name = z["emb"], str(z["fm_name"]); print(f"loaded cached FM emb ({emb.shape}) from {fm_name}", flush=True)
        else:
            emb, fm_name = embed(smiles); np.savez_compressed(EMB_CACHE, emb=emb, smiles=smiles, fm_name=fm_name)
    else:
        emb, fm_name = embed(smiles); np.savez_compressed(EMB_CACHE, emb=emb, smiles=smiles, fm_name=fm_name)
    emb = np.nan_to_num(emb, nan=0.0, posinf=0.0, neginf=0.0)
    print(f"FM embedding dim {emb.shape[1]}  ({time.time()-t0:.0f}s)", flush=True)

    y = df["pAff"].values.astype(np.float32)
    held = (df["is_pdl1"].astype(bool) | df["is_avb6"].astype(bool)).values
    tgt = df["target_uniprot"].fillna("").astype(str).values
    gmask = tgt != ""

    res = {"fm_name": fm_name, "emb_dim": int(emb.shape[1]), "n_cyclic": int(len(df)),
           "splits": {}}
    print("== FM grouped leave-targets-out CV ==", flush=True)
    res["splits"]["grouped_cv_fm"] = grouped_cv(emb[gmask], y[gmask], tgt[gmask])
    print(json.dumps(res["splits"]["grouped_cv_fm"], indent=1), flush=True)
    print(f"== FM PD-L1/avb6 holdout ==  ({time.time()-t0:.0f}s)", flush=True)
    res["splits"]["pdl1_avb6_holdout_fm"] = pdl1_avb6_holdout(
        emb, y, held, df["is_pdl1"].astype(bool).values, df["is_avb6"].astype(bool).values)
    print(json.dumps(res["splits"]["pdl1_avb6_holdout_fm"], indent=1), flush=True)

    # append into the main benchmark json
    mj = os.path.join(RESULTS, "binding_model_benchmark_cyclic.json")
    d = json.load(open(mj)); d["fm_chemberta"] = res; json.dump(d, open(mj, "w"), indent=2)
    print(f"appended fm_chemberta to {mj}  ({time.time()-t0:.0f}s total)", flush=True)


if __name__ == "__main__":
    main()
