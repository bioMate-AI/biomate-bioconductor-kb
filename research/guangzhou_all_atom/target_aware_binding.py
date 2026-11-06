#!/usr/bin/env python3
"""Track A1d — TARGET-AWARE binding model: does adding target information break the
~0.42 novel-target ceiling that LIGAND-ONLY models (ECFP, ChemBERTa) plateaued at?

Hypothesis: ligand-only models structurally cannot adapt to a held-out target (no target
input), so ~0.42 is a ligand-only ceiling. Give the model the TARGET (ESM protein-LM
embedding of the target sequence) concatenated with ligand ECFP -> can it learn transferable
target-ligand matching and generalize to held-out targets?

Same leakage-safe grouped leave-targets-out CV + PD-L1/avb6 holdout + heads as
benchmark_binding_models.py (apples-to-apples). Three feature sets:
  ligand_only  = ECFP4+physchem+assay           (reproduces ~0.42)
  target_only  = ESM(target)+assay              (LEAKAGE PROBE: must be ~0 on held-out targets)
  target_aware = ECFP4+physchem + ESM(target) + assay   (THE TEST)
No fabrication; numbers from this run.
"""
import json, os, time, io, urllib.request
import numpy as np
from benchmark_binding_models import load_and_clean, grouped_cv, pdl1_avb6_holdout, CSV, RESULTS

SEQ_CACHE = os.path.join(RESULTS, "target_uniprot_seqs.json")
EMB_CACHE = os.path.join(RESULTS, "target_esm_emb.npz")
LIG_CACHE = os.path.join(RESULTS, "binding_feature_cache.npz")
ESM_MODEL = "facebook/esm2_t12_35M_UR50D"
ASSAY = ["IC50", "Ki", "EC50", "Kd"]


def fetch_seqs(accs):
    cache = json.load(open(SEQ_CACHE)) if os.path.exists(SEQ_CACHE) else {}
    todo = [a for a in accs if a not in cache]
    print(f"fetching {len(todo)} UniProt seqs (cached {len(cache)})", flush=True)
    for i in range(0, len(todo), 100):
        chunk = todo[i:i+100]
        url = "https://rest.uniprot.org/uniprotkb/accessions?accessions=" + ",".join(chunk) + "&format=fasta"
        try:
            txt = urllib.request.urlopen(url, timeout=60).read().decode()
            cur = None
            for line in txt.splitlines():
                if line.startswith(">"):
                    acc = line.split("|")[1] if "|" in line else line[1:].split()[0]
                    cur = acc; cache[cur] = ""
                elif cur is not None:
                    cache[cur] += line.strip()
        except Exception as e:
            print(f"  chunk {i} failed: {str(e)[:100]}", flush=True)
        if (i // 100) % 2 == 0:
            json.dump(cache, open(SEQ_CACHE, "w"))
    json.dump(cache, open(SEQ_CACHE, "w"))
    return cache


def esm_embed(acc2seq, accs):
    if os.path.exists(EMB_CACHE):
        z = np.load(EMB_CACHE, allow_pickle=True)
        d = {a: z["emb"][i] for i, a in enumerate(z["accs"])}
        if all(a in d for a in accs):
            print("loaded cached ESM target embeddings", flush=True); return d
    import torch
    from transformers import EsmModel, EsmTokenizer
    tok = EsmTokenizer.from_pretrained(ESM_MODEL); mdl = EsmModel.from_pretrained(ESM_MODEL); mdl.eval()
    emb = {}; t0 = time.time()
    with torch.no_grad():
        for i, a in enumerate(accs):
            seq = acc2seq.get(a, "")
            if not seq:
                emb[a] = np.zeros(mdl.config.hidden_size, np.float32); continue
            enc = tok(seq[:1022], return_tensors="pt", truncation=True, max_length=1022)
            h = mdl(**enc).last_hidden_state[0]  # (L,d)
            emb[a] = h.mean(0).cpu().numpy().astype(np.float32)
            if i % 100 == 0:
                print(f"  esm {i}/{len(accs)} ({time.time()-t0:.0f}s)", flush=True)
    np.savez_compressed(EMB_CACHE, accs=np.array(accs), emb=np.vstack([emb[a] for a in accs]))
    return emb


def main():
    t0 = time.time()
    df = load_and_clean(CSV).reset_index(drop=True)
    z = np.load(LIG_CACHE, allow_pickle=True)
    assert bool((z["smiles"] == df["smiles"].values).all()), "ligand cache mismatch"
    fp, desc = z["fp"].astype(np.float32), z["desc"].astype(np.float32)
    mask = df["cyclic_bool"].astype(bool).values
    df = df[mask].reset_index(drop=True); fp, desc = fp[mask], desc[mask]
    onehot = np.zeros((len(df), 4), np.float32)
    for j, a in enumerate(ASSAY):
        onehot[:, j] = (df["affinity_type"].values == a).astype(np.float32)

    tgt = df["target_uniprot"].fillna("").astype(str).str.split(",").str[0].values
    gmask = tgt != ""
    accs = sorted(set(tgt[gmask]))
    acc2seq = fetch_seqs(accs)
    n_resolved = sum(1 for a in accs if acc2seq.get(a))
    print(f"targets {len(accs)} resolved-seq {n_resolved}  ({time.time()-t0:.0f}s)", flush=True)
    emb = esm_embed(acc2seq, accs)
    D = len(next(iter(emb.values())))
    T = np.vstack([emb.get(a, np.zeros(D, np.float32)) for a in tgt])  # per-row target emb
    print(f"ESM dim {D}  ({time.time()-t0:.0f}s)", flush=True)

    lig = np.nan_to_num(np.hstack([fp, desc]), nan=0.0, posinf=0.0, neginf=0.0)
    lig[:, fp.shape[1]:] = np.clip(lig[:, fp.shape[1]:], -1e6, 1e6)
    Xlig = np.hstack([lig, onehot])
    Xtgt = np.hstack([T, onehot])
    Xaware = np.hstack([lig, T, onehot])
    y = df["pAff"].values.astype(np.float32)
    held = (df["is_pdl1"].astype(bool) | df["is_avb6"].astype(bool)).values

    # restrict to rows with a resolved target seq for a fair comparison across all 3 sets
    keep = np.array([bool(acc2seq.get(a)) for a in tgt]) & gmask
    print(f"rows kept (resolved target + grouped) {int(keep.sum())}/{len(df)}", flush=True)

    rep = {"n_rows_kept": int(keep.sum()), "n_targets": len(accs), "n_resolved": n_resolved,
           "esm_model": ESM_MODEL, "esm_dim": int(D),
           "note": "grouped leave-targets-out CV; target_only is the leakage probe (should be low on held-out targets)",
           "splits": {}}
    for tag, X in [("ligand_only", Xlig), ("target_only", Xtgt), ("target_aware", Xaware)]:
        print(f"== grouped CV: {tag} ==  ({time.time()-t0:.0f}s)", flush=True)
        rep["splits"][f"grouped_cv_{tag}"] = grouped_cv(X[keep], y[keep], tgt[keep])
        print(json.dumps(rep["splits"][f"grouped_cv_{tag}"], indent=1), flush=True)
        if held.sum() >= 20:
            rep["splits"][f"pdl1_avb6_{tag}"] = pdl1_avb6_holdout(
                X, y, held, df["is_pdl1"].astype(bool).values, df["is_avb6"].astype(bool).values)

    mj = os.path.join(RESULTS, "binding_model_benchmark_cyclic.json")
    d = json.load(open(mj)); d["target_aware"] = rep; json.dump(d, open(mj, "w"), indent=2)
    print(f"appended target_aware to {mj}  ({time.time()-t0:.0f}s total)", flush=True)


if __name__ == "__main__":
    main()
