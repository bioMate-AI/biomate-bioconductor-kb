"""methodology_close.py — RUN the closed loop for real on the COLLECTED model + COLLECTED measured data.

This is the generator-close edge the system never actually ran (only SIMULATED_* artifacts existed): does a
VERIFIED reward, fed through preference optimization, measurably improve what the trained generator produces?

Real assets used (no toy, no simulation, no bespoke physics, no cost):
  - generator  : the collected unified v4 cyclic LM  runs_helm/unified_cyclic_llm_v4.pt  (design.load/generate/loglik)
  - reward      : a VERIFIED oracle trained on the collected CycPeptMPDB MEASURED permeability (8,466 cyclic peptides)
  - anti-circular evaluator : a SECOND oracle trained on a DISJOINT half of the same measured data. If DPO merely
                  games the reward oracle, the independent evaluator will NOT move — that is the honesty gate.

Protocol (verifiable-reward RLVR via DPO on the real sequence LM):
  1. load CycPeptMPDB measured permeability; featurize each peptide in the SAME monomer-sequence space the v4
     generator emits (composition over the 393-monomer vocab + length + ncAA/charge/N-methyl/aromatic proxies),
     so generated monomer sequences are scored directly — no SMILES round-trip, no OOD gap.
  2. split the measured set into two DISJOINT halves by sequence hash -> oracle_A (reward), oracle_B (evaluator).
  3. baseline: sample from v4 (p_hi); score with the INDEPENDENT oracle_B; record validity/novelty/diversity.
  4. build preference pairs: sample a pool from v4, score with oracle_A, chosen(high-A) >- rejected(low-A).
  5. DPO-tune v4 against those pairs (frozen reference = the original v4; standard DPO loss; v4 has a tractable
     sequence log-likelihood via design.loglik, so no diffusion machinery needed here).
  6. after: re-sample from the tuned v4; score with oracle_B. Success = oracle_B of generations RISES after DPO
     with validity/novelty/diversity preserved (no mode collapse, no reward-hacking).

CPU-runnable at the default scale; --big scales it for the Spark/GPU box. Writes a fine-tuned ckpt + a results
JSON with the before/after independent-evaluator shift and the anti-circularity check.
"""
from __future__ import annotations
import argparse, ast, csv, hashlib, json, os, copy
import numpy as np
import torch

import design  # the real v4 interface (load/generate/loglik); imports train_cyclic_llm_v3 (make_model/TFEAT_DIM)
from train_cyclic_llm_v3 import TFEAT_DIM

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
CSV = os.path.join(ROOT, "data/raw/CycPeptMPDB_Peptide_All.csv")
CKPT = os.path.join(ROOT, "runs_helm/unified_cyclic_llm_v4.pt")
CANON = set("ACDEFGHIKLMNPQRSTVWY")


# ---------------------------------------------------------------- data + verified-reward oracles
def load_cycpept():
    """Return [(monos:list[str], perm:float)] from the collected measured set."""
    rows = []
    for r in csv.DictReader(open(CSV)):
        try:
            perm = float(r["Permeability"])
        except Exception:
            continue
        seq = (r.get("Sequence") or "").strip()
        if not seq:
            continue
        try:
            monos = [str(m) for m in ast.literal_eval(seq)]
        except Exception:
            continue
        if 3 <= len(monos) <= 24:
            rows.append((monos, perm))
    return rows


def _mono_props(m):
    """Cheap, monomer-identity physchem proxies (same space the generator emits)."""
    lm = m.lower()
    nmethyl = 1.0 if (lm.startswith("me") or lm.startswith("sar") or "nme" in lm or m in ("Sar",)) else 0.0
    arom = 1.0 if any(a in m for a in ("F", "Y", "W", "H", "Nal", "Bmt", "Phe")) else 0.0
    pos = 1.0 if (m in ("K", "R", "H") or "Lys" in m or "Arg" in m) else 0.0
    neg = 1.0 if (m in ("D", "E") or "Asp" in m or "Glu" in m) else 0.0
    dres = 1.0 if (m.startswith("d") and len(m) >= 2 and m[1].isupper()) else 0.0
    return nmethyl, arom, pos, neg, dres


def build_featurizer(rows):
    """Monomer-composition + aggregate-property featurizer over the observed vocab. Generated sequences
    (same vocab) featurize identically, so the oracle scores them directly."""
    vocab = sorted({m for monos, _ in rows for m in monos})
    vi = {m: i for i, m in enumerate(vocab)}
    V = len(vocab)

    def feat(monos):
        x = np.zeros(V + 8, dtype=np.float32)
        for m in monos:
            if m in vi:
                x[vi[m]] += 1.0
        L = max(len(monos), 1)
        x[:V] /= L                                   # composition (length-normalized)
        nm = ar = po = ne = dr = 0.0
        for m in monos:
            a, b, c, d, e = _mono_props(m)
            nm += a; ar += b; po += c; ne += d; dr += e
        ncaa = sum(1 for m in monos if m not in CANON)
        x[V:V + 8] = [L, ncaa / L, nm / L, ar / L, po / L, ne / L, dr / L, po - ne]
        return x

    return feat, vocab


def train_oracles(rows, feat, seed=0):
    """Two HistGBM permeability oracles on DISJOINT sequence-hash halves: A=reward, B=independent evaluator."""
    from sklearn.ensemble import HistGradientBoostingRegressor
    from sklearn.metrics import r2_score

    def half(m):
        return int(hashlib.md5(".".join(m).encode()).hexdigest(), 16) % 2

    A = [(m, p) for m, p in rows if half(m) == 0]
    B = [(m, p) for m, p in rows if half(m) == 1]

    def fit(split):
        X = np.array([feat(m) for m, _ in split]); y = np.array([p for _, p in split])
        mdl = HistGradientBoostingRegressor(max_iter=400, learning_rate=0.05, max_depth=8, random_state=seed)
        mdl.fit(X, y)
        return mdl

    oa, ob = fit(A), fit(B)
    # honest in-sample vs cross-split sanity (not the headline; just records the oracles are real signal)
    yb = np.array([p for _, p in B]); pb = oa.predict(np.array([feat(m) for m, _ in B]))
    cross_r2 = float(r2_score(yb, pb))
    return oa, ob, {"n_A": len(A), "n_B": len(B), "oracleA_on_B_r2": round(cross_r2, 3)}


# ---------------------------------------------------------------- v4 generation + metrics
def gen(model, toks, stoi, tf, dev, block, n, temp, max_len=20, p_tok="<p_hi>"):
    return design.generate(model, toks, stoi, tf, dev, n, block, max_len, temp, e_tok="<e_na>", p_tok=p_tok)


def metrics(samples, oracle, feat, train_keys):
    uniq = {tuple(m) for m in samples}
    scores = np.array([oracle.predict(feat(m)[None])[0] for m in samples]) if samples else np.array([0.0])
    novel = sum(1 for m in uniq if m not in train_keys) / max(len(uniq), 1)
    return {"n": len(samples), "n_unique": len(uniq), "oracle_mean": round(float(scores.mean()), 4),
            "oracle_p50": round(float(np.median(scores)), 4), "oracle_p90": round(float(np.quantile(scores, 0.9)), 4),
            "validity": round(len(samples) / max(len(samples), 1), 3),  # design.generate already filters to valid
            "novelty": round(novel, 3), "diversity": round(len(uniq) / max(len(samples), 1), 3)}


# ---------------------------------------------------------------- DPO on the real v4 LM
def seq_logp(model, stoi, monos, e_tok, p_tok, tf_t, dev):
    """Grad-enabled sequence log-prob over the monomer span — mirrors design.loglik's exact indexing."""
    ids = [stoi[e_tok], stoi[p_tok], stoi[design.BOS]] + [stoi[m] for m in monos if m in stoi] + [stoi[design.EOS]]
    x = torch.tensor([ids], device=dev)
    lp = torch.log_softmax(model(x, tf_t)[0], -1)
    tok = lp[torch.arange(len(ids), device=dev), x[0]]
    return tok[3:3 + len([m for m in monos if m in stoi])].sum()


def dpo_finetune(model, stoi, pairs, tf_t, dev, steps, beta, lr, batch, log=print):
    ref = copy.deepcopy(model).eval()
    for p in ref.parameters():
        p.requires_grad_(False)
    opt = torch.optim.Adam([p for p in model.parameters() if p.requires_grad], lr=lr)
    # cache reference log-probs (frozen)
    with torch.no_grad():
        for pr in pairs:
            pr["ref_c"] = seq_logp(ref, stoi, pr["chosen"], "<e_na>", "<p_hi>", tf_t, dev).item()
            pr["ref_r"] = seq_logp(ref, stoi, pr["rejected"], "<e_na>", "<p_hi>", tf_t, dev).item()
    rng = np.random.default_rng(0)
    model.train()
    for step in range(steps):
        idx = rng.choice(len(pairs), size=min(batch, len(pairs)), replace=False)
        opt.zero_grad(); loss = 0.0; accd = 0.0
        for j in idx:
            pr = pairs[j]
            lc = seq_logp(model, stoi, pr["chosen"], "<e_na>", "<p_hi>", tf_t, dev)
            lr_ = seq_logp(model, stoi, pr["rejected"], "<e_na>", "<p_hi>", tf_t, dev)
            logits = beta * ((lc - pr["ref_c"]) - (lr_ - pr["ref_r"]))
            loss = loss + (-torch.nn.functional.logsigmoid(logits))
            accd += float(logits.item() > 0)
        loss = loss / len(idx)
        loss.backward(); opt.step()
        if step % max(1, steps // 10) == 0 or step == steps - 1:
            log(f"  dpo step {step:4d}/{steps}  loss={loss.item():.4f}  pref_acc={accd/len(idx):.2f}")
    model.eval()
    return model


def main():
    ap = argparse.ArgumentParser(description="Run the verified-reward generator-close on the collected v4 model.")
    ap.add_argument("--ckpt", default=CKPT)
    ap.add_argument("--pool", type=int, default=1200, help="candidates sampled to build preference pairs")
    ap.add_argument("--pairs", type=int, default=1500, help="max preference pairs")
    ap.add_argument("--eval-n", type=int, default=400, help="samples for before/after evaluation")
    ap.add_argument("--steps", type=int, default=150); ap.add_argument("--beta", type=float, default=0.1)
    ap.add_argument("--lr", type=float, default=1e-5); ap.add_argument("--batch", type=int, default=8)
    ap.add_argument("--temp", type=float, default=1.0)
    ap.add_argument("--big", action="store_true", help="scale up (Spark/GPU): pool 6000, pairs 8000, steps 600, eval 1500")
    ap.add_argument("--out", default=os.path.join(ROOT, "results/methodology_close_result.json"))
    ap.add_argument("--save-ckpt", default=os.path.join(ROOT, "runs_helm/unified_cyclic_llm_v4_dpo.pt"))
    args = ap.parse_args()
    if args.big:
        args.pool, args.pairs, args.steps, args.eval_n = 6000, 8000, 600, 1500

    torch.manual_seed(0); np.random.seed(0)
    print("loading collected measured permeability (CycPeptMPDB) ...", flush=True)
    rows = load_cycpept()
    feat, vocab = build_featurizer(rows)
    oa, ob, ostat = train_oracles(rows, feat)
    train_keys = {tuple(m) for m, _ in rows}
    print(f"  measured peptides={len(rows)}  vocab={len(vocab)}  oracles: {ostat}", flush=True)

    print(f"loading collected generator {os.path.relpath(args.ckpt, ROOT)} ...", flush=True)
    model, toks, stoi, a, dev = design.load(args.ckpt); block = a["block"]
    tf = np.zeros(TFEAT_DIM, dtype=np.float32)                    # target-agnostic: permeability is target-independent
    tf_t = torch.tensor(tf, device=dev)[None]
    print(f"  device={dev} block={block} vocab={len(toks)}", flush=True)

    # 3) baseline (independent evaluator oracle_B)
    base = gen(model, toks, stoi, tf, dev, block, args.eval_n, args.temp)
    m_before = metrics(base, ob, feat, train_keys)
    base_A = metrics(base, oa, feat, train_keys)["oracle_mean"]
    print(f"BEFORE  evalB_mean={m_before['oracle_mean']}  (rewardA_mean={base_A})  "
          f"valid={m_before['validity']} novelty={m_before['novelty']} diversity={m_before['diversity']}", flush=True)

    # 4) build verified-reward preference pairs (reward oracle_A)
    pool = gen(model, toks, stoi, tf, dev, block, args.pool, args.temp)
    pool = list({tuple(m): m for m in pool}.values())
    scored = sorted(((oa.predict(feat(m)[None])[0], m) for m in pool), key=lambda t: -t[0])
    k = min(len(scored) // 2, args.pairs)
    hi, lo = scored[:k], scored[::-1][:k]
    pairs = [{"chosen": hi[i][1], "rejected": lo[i][1], "margin": float(hi[i][0] - lo[i][0])}
             for i in range(k) if hi[i][1] != lo[i][1]]
    print(f"built {len(pairs)} verified-reward preference pairs (reward=oracle_A measured-permeability)", flush=True)

    # 5) DPO close on the real v4
    model = dpo_finetune(model, stoi, pairs, tf_t, dev, args.steps, args.beta, args.lr, args.batch)

    # 6) after (independent evaluator oracle_B)
    aft = gen(model, toks, stoi, tf, dev, block, args.eval_n, args.temp)
    m_after = metrics(aft, ob, feat, train_keys)
    aft_A = metrics(aft, oa, feat, train_keys)["oracle_mean"]
    print(f"AFTER   evalB_mean={m_after['oracle_mean']}  (rewardA_mean={aft_A})  "
          f"valid={m_after['validity']} novelty={m_after['novelty']} diversity={m_after['diversity']}", flush=True)

    dB = round(m_after["oracle_mean"] - m_before["oracle_mean"], 4)
    dA = round(aft_A - base_A, 4)
    verdict = ("LOOP IMPROVES GENERATOR (independent evaluator rose, diversity held)"
               if dB > 0 and m_after["diversity"] >= 0.5 * m_before["diversity"] and m_after["novelty"] >= 0.5 * m_before["novelty"]
               else "INCONCLUSIVE / possible reward-hacking (see dA vs dB + diversity)")
    res = {"what": "verified-reward generator-close on the COLLECTED v4 model + COLLECTED measured permeability",
           "reward": "oracle_A trained on CycPeptMPDB measured permeability (disjoint half)",
           "evaluator": "oracle_B trained on the OTHER disjoint half (anti-circular)",
           "oracle_stats": ostat, "n_pairs": len(pairs), "dpo": {"steps": args.steps, "beta": args.beta, "lr": args.lr},
           "before": m_before, "after": m_after, "reward_oracleA_before": base_A, "reward_oracleA_after": aft_A,
           "delta_independent_evaluatorB": dB, "delta_reward_oracleA": dA, "verdict": verdict}
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    json.dump(res, open(args.out, "w"), indent=2)
    torch.save({"model": model.state_dict(), "toks": toks, "args": a}, args.save_ckpt)
    print(f"\nΔ independent-evaluator(B) = {dB:+}   Δ reward-oracle(A) = {dA:+}")
    print(f"VERDICT: {verdict}")
    print(f"wrote {os.path.relpath(args.out, ROOT)} + fine-tuned ckpt {os.path.relpath(args.save_ckpt, ROOT)}")


if __name__ == "__main__":
    main()
