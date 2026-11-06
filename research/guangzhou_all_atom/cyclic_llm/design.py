"""design.py — the end-to-end 'best cyclic LLM' SYSTEM interface, over the unified v4 model.

Input a target -> generate ncAA-native cyclic candidates conditioned on (target, high-enrichment,
high-permeability) -> rank them by the binding SELECTOR (LLR = logP(seq|target,hi) - logP(seq|target,lo))
and report permeability-conditioned ncAA designs. One call = target in, ranked macrocycle designs out.
Composes everything this session built (ncAA representation + multi-target binding brain + property
conditioning) into a usable pipeline. Uses the unified v4 checkpoint.
"""
from __future__ import annotations
import argparse, json
import numpy as np
import torch
import train_cyclic_llm_v3 as v3
from train_cyclic_llm_v3 import target_feature, TFEAT_DIM, make_model

CANON = set("ACDEFGHIKLMNPQRSTVWY")
PAD, BOS, EOS = "<pad>", "<bos>", "<eos>"


def load(ckpt_path):
    d = torch.load(ckpt_path, map_location="cpu", weights_only=False)
    toks = d["toks"]; a = d["args"]; stoi = {t: i for i, t in enumerate(toks)}
    dev = "cuda" if torch.cuda.is_available() else ("mps" if torch.backends.mps.is_available() else "cpu")
    model = make_model(len(toks), TFEAT_DIM, d_model=a["d_model"], n_layer=a["n_layer"], n_head=a["n_head"], block=a["block"]).to(dev)
    model.load_state_dict(d["model"]); model.eval()
    return model, toks, stoi, a, dev


def tfeat_for(target, targets_json):
    tp = json.load(open(targets_json))
    if target in tp: return target_feature(tp[target]["seq"]).astype("float32")
    # allow a raw protein sequence
    if all(c in CANON for c in target.upper()) and len(target) > 20:
        return target_feature(target.upper()).astype("float32")
    raise SystemExit(f"unknown target '{target}' (not in {list(tp)}; or pass a protein sequence)")


def loglik(model, stoi, monos, e_tok, p_tok, tfeat, dev):
    ids = [stoi[e_tok], stoi[p_tok], stoi[BOS]] + [stoi[m] for m in monos if m in stoi] + [stoi[EOS]]
    x = torch.tensor([ids], device=dev); tf = torch.tensor(np.asarray(tfeat), device=dev)[None]
    with torch.no_grad(): lp = torch.log_softmax(model(x, tf)[0], -1)
    tgt = x[0]; tok = lp[torch.arange(len(tgt)), tgt]
    return float(tok[3:3 + len(monos)].sum())


def generate(model, toks, stoi, tfeat, dev, n, block, max_len, temp, e_tok="<e_hi>", p_tok="<p_hi>"):
    itos = {i: t for t, i in stoi.items()}; specials = {PAD, BOS, EOS} | {t for t in toks if t.startswith("<e_") or t.startswith("<p_")}
    tf = torch.tensor(np.asarray(tfeat), device=dev)[None]; out = []
    for _ in range(n):
        ids = [stoi[e_tok], stoi[p_tok], stoi[BOS]]
        for _ in range(max_len + 1):
            with torch.no_grad():
                lg = model(torch.tensor([ids[-block:]], device=dev), tf)[0, -1] / temp
            nx = int(torch.multinomial(torch.softmax(lg, -1), 1))
            if nx == stoi[EOS]: break
            ids.append(nx)
        monos = [itos[i] for i in ids[3:]]
        if 3 <= len(monos) <= max_len and all(m not in specials for m in monos):
            out.append(monos)
    return out


def main():
    ap = argparse.ArgumentParser(description="Target -> ranked ncAA cyclic-peptide designs (unified v4).")
    ap.add_argument("--ckpt", default="../runs_helm/unified_cyclic_llm_v4.pt")
    ap.add_argument("--targets", default="../data/display/target_proteins.json")
    ap.add_argument("--target", required=True, help="target name (PADI4/hPCSK9/FIKK13/Abeta42/hIAPP) or a protein sequence")
    ap.add_argument("--n", type=int, default=500, help="candidates to generate")
    ap.add_argument("--topk", type=int, default=20); ap.add_argument("--temp", type=float, default=1.0)
    ap.add_argument("--max-len", type=int, default=16); ap.add_argument("--out")
    args = ap.parse_args()
    model, toks, stoi, a, dev = load(args.ckpt); block = a["block"]
    tfeat = tfeat_for(args.target, args.targets)
    gens = generate(model, toks, stoi, tfeat, dev, args.n, block, args.max_len, args.temp)
    # rank by binding selector LLR (hi vs lo), report ncAA fraction; dedup
    seen = set(); ranked = []
    for m in gens:
        key = tuple(m)
        if key in seen: continue
        seen.add(key)
        llr = loglik(model, stoi, m, "<e_hi>", "<p_na>", tfeat, dev) - loglik(model, stoi, m, "<e_lo>", "<p_na>", tfeat, dev)
        ncaa = sum(1 for x in m if x not in CANON) / len(m)
        ranked.append({"design": m, "binding_LLR": round(llr, 3), "ncAA_frac": round(ncaa, 3), "len": len(m)})
    ranked.sort(key=lambda r: -r["binding_LLR"])
    top = ranked[:args.topk]
    res = {"target": args.target, "n_generated": len(gens), "n_unique": len(ranked), "top_k": top,
           "note": "Generated ncAA-native cyclic candidates conditioned on (target, high-enrichment, "
                   "high-permeability); ranked by the binding-selector LLR. One pipeline: target -> ranked "
                   "macrocycle designs. IN-SILICO ranking (display-trained), not wet-lab affinity."}
    print(f"=== {args.target}: {len(gens)} generated, {len(ranked)} unique; top {len(top)} by binding LLR ===")
    for r in top[:args.topk]:
        print(f"  LLR={r['binding_LLR']:+7.2f} ncAA={r['ncAA_frac']:.2f} len={r['len']:2d}  {'.'.join(r['design'])}")
    if args.out:
        from pathlib import Path; Path(args.out).parent.mkdir(parents=True, exist_ok=True); json.dump(res, open(args.out, "w"), indent=2)


if __name__ == "__main__":
    main()
