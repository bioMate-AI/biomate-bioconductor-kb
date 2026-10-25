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
import experience_kb            # the pragmatic-knowledge resolver (rule-constraint layer)
import score as score_mod       # operative KB gate providers (developability + rule + FTO), as loop_batch uses
import acceptance_gate, fto_score

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


def _cluster_disjoint_split(rows, seed=0, thr=0.6, n_max=3000):
    """LEAKAGE-SAFE split: cluster peptides by monomer-set Tanimoto (the peptide analog of Murcko
    scaffold clustering; cf. c2_retro_loop) and assign WHOLE clusters to A or B, so near-analogs never
    straddle the reward oracle and the independent evaluator. Caps rows (random subsample) for tractability."""
    rng = np.random.default_rng(seed)
    if len(rows) > n_max:
        idx = rng.choice(len(rows), n_max, replace=False); rows = [rows[i] for i in idx]
    vocab = sorted({m for monos, _ in rows for m in monos}); vi = {m: i for i, m in enumerate(vocab)}
    B = np.zeros((len(rows), len(vocab)), bool)
    for r, (monos, _) in enumerate(rows):
        for m in monos:
            B[r, vi[m]] = True
    card = B.sum(1).astype(np.float32)
    assigned = -np.ones(len(rows), int); cid = 0
    for i in rng.permutation(len(rows)):
        if assigned[i] >= 0:
            continue
        inter = (B & B[i]).sum(1).astype(np.float32)
        tani = inter / (card + card[i] - inter + 1e-9)
        members = np.where((tani >= thr) & (assigned < 0))[0]
        assigned[members] = cid; cid += 1
    # assign clusters to A/B (alternate, so both halves get comparable size + chemotype coverage)
    corder = rng.permutation(cid)
    side = {c: (0 if k % 2 == 0 else 1) for k, c in enumerate(corder)}
    A = [rows[i] for i in range(len(rows)) if side[assigned[i]] == 0]
    Bset = [rows[i] for i in range(len(rows)) if side[assigned[i]] == 1]
    return A, Bset, cid


def train_oracles(rows, feat, seed=0):
    """Two HistGBM oracles on CLUSTER-DISJOINT halves: A=reward, B=independent (leakage-safe) evaluator."""
    from sklearn.ensemble import HistGradientBoostingRegressor
    from sklearn.metrics import r2_score

    A, B, n_clusters = _cluster_disjoint_split(rows, seed=seed)

    def fit(split):
        X = np.array([feat(m) for m, _ in split]); y = np.array([p for _, p in split])
        mdl = HistGradientBoostingRegressor(max_iter=400, learning_rate=0.05, max_depth=8, random_state=seed)
        mdl.fit(X, y)
        return mdl

    oa, ob = fit(A), fit(B)
    # cross-split R2 (A predicting leakage-safe held-out B) — the honest generalization signal
    yb = np.array([p for _, p in B]); pb = oa.predict(np.array([feat(m) for m, _ in B]))
    cross_r2 = float(r2_score(yb, pb))
    return oa, ob, {"n_A": len(A), "n_B": len(B), "n_clusters": n_clusters,
                    "split": "cluster-disjoint(monomer-Tanimoto>=0.6)", "oracleA_on_B_r2": round(cross_r2, 3)}


def load_display_binding(target_key):
    """Return [(monos:list[str], enrichment_log2fc:float)] for one target from the collected display NGS set.
    Sequences are canonical-AA strings (one monomer per residue) — the SAME token space v4 emits."""
    import gzip
    path = os.path.join(ROOT, "data/display/display_ngs_multitarget.csv.gz")
    rows, seen = [], set()
    with gzip.open(path, "rt") as fh:
        for r in csv.DictReader(fh):
            if target_key.lower() not in (r.get("target") or "").lower():
                continue
            seq = (r.get("sequence") or "").strip().upper()
            try:
                enr = float(r.get("enrichment_log2fc"))
            except Exception:
                continue
            if not seq or not (3 <= len(seq) <= 24) or not all(c in CANON for c in seq):
                continue
            key = (seq, round(enr, 4))
            if key in seen:
                continue
            seen.add(key)
            rows.append((list(seq), enr))
    return rows


# ---------------------------------------------------------------- KB rule-constraint (experience_kb gate)
def to_helm(monos):
    """Monomer list -> the cyclo(...) string the KB gate providers (acceptance_gate/score) parse.

    FIXED 2026-10-25: this previously emitted 'PEPTIDE1{A.R.[dP]}$PEPTIDE1,...$$$', which acceptance_gate.raw_tokens parses
    as ONE token -> developability() saw no residues (Asn-Gly / free Cys / double Trp all 'passed'), and the avb6 RGD gate
    rejected even a valid RGD peptide. So `kb_admissible` was a no-op for the permeability signal and rejected everything
    for the binding signal; the earlier 'rule-constrained arm == unconstrained' result was therefore UNINFORMATIVE (the gate
    never fired), not evidence that the gate does not bind. Regression test: test_kb_gate_format.py."""
    body = "-".join(m if (len(m) == 1 and m in CANON) else f"[{m}]" for m in monos)
    return "cyclo(" + body + ")"


def kb_admissible(monos, target):
    """Apply the KB's operative HARD gates to a candidate (the same providers resolve() references and
    loop_batch enforces via score()): developability is the general cyclic-peptide hard gate; for avb6
    the decisive RGD rule + FTO-genus clearance also apply. Fails OPEN on a parse error (never fabricate a
    rejection). Returns (ok, reasons)."""
    helm = to_helm(monos); reasons = {}
    try:
        reasons["developability"] = bool(score_mod.developability(helm).get("pass"))
    except Exception:
        reasons["developability"] = True
    ok = reasons["developability"]
    if target == "avb6":
        try:
            reasons["rule_rgd"] = bool(acceptance_gate.avb6_gate(helm).get("PASS_H1_H5"))
            reasons["fto_not_infringing"] = not fto_score.fto_score(helm, "avb6")["claim"]["verdict"].startswith("INSIDE")
            ok = ok and reasons["rule_rgd"] and reasons["fto_not_infringing"]
        except Exception:
            pass
    return ok, reasons


# ---------------------------------------------------------------- v4 generation + metrics
def gen(model, toks, stoi, tf, dev, block, n, temp, max_len=20, e_tok="<e_na>", p_tok="<p_hi>"):
    return design.generate(model, toks, stoi, tf, dev, n, block, max_len, temp, e_tok=e_tok, p_tok=p_tok)


def frechet_feature_distance(gen_feats, ref_feats):
    """FCD-analog: Fréchet distance between generated and a REFERENCE (real measured peptide) set in feature
    space (the peptide-space stand-in for Fréchet ChemNet Distance; lower = generations match real-peptide
    distribution). FCD proper uses a small-molecule ChemNet on SMILES, which does not apply to ncAA macrocycle
    monomer sequences — so we report the same Fréchet construction on the shared feature space, labelled as an analog."""
    import numpy as _np
    from scipy.linalg import sqrtm
    g = _np.asarray(gen_feats, float); r = _np.asarray(ref_feats, float)
    mu_g, mu_r = g.mean(0), r.mean(0)
    cg = _np.cov(g, rowvar=False) + 1e-6 * _np.eye(g.shape[1])
    cr = _np.cov(r, rowvar=False) + 1e-6 * _np.eye(r.shape[1])
    covmean = sqrtm(cg @ cr)
    if _np.iscomplexobj(covmean):
        covmean = covmean.real
    return float(((mu_g - mu_r) ** 2).sum() + _np.trace(cg + cr - 2 * covmean))


def oracle_budget_auc(pool_scores):
    """PMO-style sample efficiency: running best (top-10 mean) reward vs cumulative oracle calls, normalized AUC."""
    import numpy as _np
    s = _np.asarray(pool_scores, float)
    if len(s) < 10:
        return None
    run = _np.array([_np.sort(s[:i + 1])[-10:].mean() for i in range(len(s))])
    lo, hi = run.min(), run.max()
    return round(float((run - lo).mean() / (hi - lo + 1e-9)), 4)


def metrics(samples, oracle, feat, train_keys, gate_target=None):
    uniq = {tuple(m) for m in samples}
    scores = np.array([oracle.predict(feat(m)[None])[0] for m in samples]) if samples else np.array([0.0])
    novel = sum(1 for m in uniq if m not in train_keys) / max(len(uniq), 1)
    adm = round(sum(1 for m in samples if kb_admissible(m, gate_target)[0]) / max(len(samples), 1), 3)
    return {"n": len(samples), "n_unique": len(uniq), "oracle_mean": round(float(scores.mean()), 4),
            "oracle_p50": round(float(np.median(scores)), 4), "oracle_p90": round(float(np.quantile(scores, 0.9)), 4),
            "validity": round(len(samples) / max(len(samples), 1), 3),  # design.generate already filters to valid
            "novelty": round(novel, 3), "diversity": round(len(uniq) / max(len(samples), 1), 3),
            "kb_admissible": adm}


# ---------------------------------------------------------------- DPO on the real v4 LM
def seq_logp(model, stoi, monos, e_tok, p_tok, tf_t, dev):
    """Grad-enabled sequence log-prob over the monomer span — mirrors design.loglik's exact indexing."""
    ids = [stoi[e_tok], stoi[p_tok], stoi[design.BOS]] + [stoi[m] for m in monos if m in stoi] + [stoi[design.EOS]]
    x = torch.tensor([ids], device=dev)
    lp = torch.log_softmax(model(x, tf_t)[0], -1)
    tok = lp[torch.arange(len(ids), device=dev), x[0]]
    return tok[3:3 + len([m for m in monos if m in stoi])].sum()


def dpo_finetune(model, stoi, pairs, tf_t, dev, steps, beta, lr, batch, e_tok="<e_na>", p_tok="<p_hi>", log=print):
    ref = copy.deepcopy(model).eval()
    for p in ref.parameters():
        p.requires_grad_(False)
    opt = torch.optim.Adam([p for p in model.parameters() if p.requires_grad], lr=lr)
    # cache reference log-probs (frozen)
    with torch.no_grad():
        for pr in pairs:
            pr["ref_c"] = seq_logp(ref, stoi, pr["chosen"], e_tok, p_tok, tf_t, dev).item()
            pr["ref_r"] = seq_logp(ref, stoi, pr["rejected"], e_tok, p_tok, tf_t, dev).item()
    rng = np.random.default_rng(0)
    model.train()
    for step in range(steps):
        idx = rng.choice(len(pairs), size=min(batch, len(pairs)), replace=False)
        opt.zero_grad(); loss = 0.0; accd = 0.0
        for j in idx:
            pr = pairs[j]
            lc = seq_logp(model, stoi, pr["chosen"], e_tok, p_tok, tf_t, dev)
            lr_ = seq_logp(model, stoi, pr["rejected"], e_tok, p_tok, tf_t, dev)
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
    ap.add_argument("--signal", choices=["permeability", "binding"], default="permeability",
                    help="permeability = CycPeptMPDB measured logPapp (target-agnostic); "
                         "binding = display-NGS enrichment_log2fc for --target (target-conditioned)")
    ap.add_argument("--target", default="PADI4", help="binding signal only: target key (display + tfeat)")
    ap.add_argument("--targets-json", default=os.path.join(ROOT, "data/display/target_proteins.json"))
    ap.add_argument("--kb-gate", dest="kb_gate", action="store_true", default=True,
                    help="enforce the experience_kb rule-constraint (default ON): chosen candidates must be KB-admissible")
    ap.add_argument("--no-kb-gate", dest="kb_gate", action="store_false",
                    help="ablation: generative + verified-reward only, no KB gate")
    ap.add_argument("--pool", type=int, default=1200, help="candidates sampled to build preference pairs")
    ap.add_argument("--pairs", type=int, default=1500, help="max preference pairs")
    ap.add_argument("--eval-n", type=int, default=400, help="samples for before/after evaluation")
    ap.add_argument("--steps", type=int, default=150); ap.add_argument("--beta", type=float, default=0.1)
    ap.add_argument("--lr", type=float, default=1e-5); ap.add_argument("--batch", type=int, default=8)
    ap.add_argument("--temp", type=float, default=1.0)
    ap.add_argument("--big", action="store_true", help="scale up (Spark/GPU): pool 6000, pairs 8000, steps 600, eval 1500")
    ap.add_argument("--seed", type=int, default=0, help="RNG seed (torch+numpy) for replication")
    ap.add_argument("--shuffle-reward", action="store_true",
                    help="PLACEBO CONTROL: permute the reward scores before building pairs so chosen/rejected are "
                         "random w.r.t. true reward. If delta_B ~ 0 here while the real reward gives delta_B>0, the "
                         "gain is attributable to the verified signal, not to DPO pressure/diversity collapse. "
                         "Use with --no-kb-gate (pairs are purely reward-ranked).")
    ap.add_argument("--out", default=os.path.join(ROOT, "results/methodology_close_result.json"))
    ap.add_argument("--save-ckpt", default=os.path.join(ROOT, "runs_helm/unified_cyclic_llm_v4_dpo.pt"))
    args = ap.parse_args()
    if args.big:
        args.pool, args.pairs, args.steps, args.eval_n = 6000, 8000, 600, 1500

    torch.manual_seed(args.seed); np.random.seed(args.seed)
    if args.signal == "permeability":
        print("loading collected measured permeability (CycPeptMPDB) ...", flush=True)
        rows = load_cycpept()
        e_tok, p_tok, reward_name = "<e_na>", "<p_hi>", "CycPeptMPDB measured permeability"
    else:
        print(f"loading collected display-NGS enrichment for target {args.target} ...", flush=True)
        rows = load_display_binding(args.target)
        e_tok, p_tok, reward_name = "<e_hi>", "<p_na>", f"display-NGS enrichment_log2fc ({args.target})"
    if len(rows) < 200:
        raise SystemExit(f"too few rows ({len(rows)}) for signal={args.signal} target={args.target}")
    feat, vocab = build_featurizer(rows)
    oa, ob, ostat = train_oracles(rows, feat)
    train_keys = {tuple(m) for m, _ in rows}
    print(f"  measured rows={len(rows)}  vocab={len(vocab)}  oracles: {ostat}", flush=True)

    print(f"loading collected generator {os.path.relpath(args.ckpt, ROOT)} ...", flush=True)
    model, toks, stoi, a, dev = design.load(args.ckpt); block = a["block"]
    if args.signal == "permeability":
        tf = np.zeros(TFEAT_DIM, dtype=np.float32)               # target-agnostic: permeability is target-independent
    else:
        tf = design.tfeat_for(args.target, args.targets_json)     # target-conditioned binding
    tf_t = torch.tensor(np.asarray(tf), device=dev)[None]
    print(f"  device={dev} block={block} vocab={len(toks)} signal={args.signal} cond=({e_tok},{p_tok})", flush=True)

    # KB RULE-CONSTRAINT: resolve the pragmatic-knowledge gate-set (experience_kb). The gate is enforced in
    # pair construction (chosen must be KB-admissible) so the close is rule-constrained + generative + verified-reward.
    gate_target = args.target if (args.kb_gate and args.signal == "binding") else None
    kb_prov = []
    if args.kb_gate:
        try:
            kb = experience_kb.resolve(gate_target or args.target)
            hard = [c for e in ([kb] if isinstance(kb, dict) else []) for c in e.get("eval_criteria", []) if c.get("mode") == "hard"]
            kb_prov = kb.get("provenance", []) if isinstance(kb, dict) else []
            print(f"  KB rule-constraint ON (experience_kb.resolve): gate_target={gate_target or args.target} "
                  f"hard_gates={[c.get('criterion') for c in hard]} provenance_entries={len(kb_prov)}", flush=True)
        except Exception as ex:
            print(f"  KB resolve note: {type(ex).__name__}: {str(ex)[:120]} (falling back to general developability gate)", flush=True)
    else:
        print("  KB rule-constraint OFF (--no-kb-gate): generative + verified-reward only (ablation)", flush=True)

    # 3) baseline (independent evaluator oracle_B)
    base = gen(model, toks, stoi, tf, dev, block, args.eval_n, args.temp, e_tok=e_tok, p_tok=p_tok)
    m_before = metrics(base, ob, feat, train_keys, gate_target)
    base_A = metrics(base, oa, feat, train_keys, gate_target)["oracle_mean"]
    print(f"BEFORE  evalB_mean={m_before['oracle_mean']}  (rewardA_mean={base_A})  valid={m_before['validity']} "
          f"novelty={m_before['novelty']} diversity={m_before['diversity']} kb_admissible={m_before['kb_admissible']}", flush=True)

    # 4) build verified-reward preference pairs (reward oracle_A)
    pool = gen(model, toks, stoi, tf, dev, block, args.pool, args.temp, e_tok=e_tok, p_tok=p_tok)
    pool = list({tuple(m): m for m in pool}.values())
    pool_scores_genorder = [float(oa.predict(feat(m)[None])[0]) for m in pool]   # generation order (PMO acquisition)
    budget_auc = oracle_budget_auc(pool_scores_genorder)
    # PLACEBO CONTROL: permute the reward labels across candidates so pair chosen/rejected is random w.r.t.
    # the true reward (the DPO machinery is otherwise identical). A sound loop gives delta_B ~ 0 here.
    pair_scores = pool_scores_genorder
    if args.shuffle_reward:
        pair_scores = list(np.random.default_rng(args.seed + 777).permutation(np.asarray(pool_scores_genorder)))
        print(f"  [PLACEBO] reward labels PERMUTED before pair construction (shuffle-reward control, seed {args.seed})", flush=True)
    scored = sorted(zip(pair_scores, pool), key=lambda t: -t[0])
    if args.kb_gate:
        # rule-constrained: CHOSEN must pass the KB gate; gate-FAILS are the cleanest negatives, then low-property
        adm = [(s, m) for s, m in scored if kb_admissible(m, gate_target)[0]]
        inadm = [(s, m) for s, m in scored if not kb_admissible(m, gate_target)[0]]
        chosen = adm[:args.pairs]
        negs = inadm + adm[::-1]                      # gate-fails first (strongest neg), then admissible low-property
        # a negative is valid iff it is a GATE-FAIL (inadmissible, regardless of property) OR genuinely
        # lower-reward than the chosen; this prevents contradictory crossing pairs when the pool is all-admissible.
        pairs = [{"chosen": chosen[i][1], "rejected": negs[i][1], "margin": float(chosen[i][0] - negs[i][0]),
                  "kb_clean_neg": i < len(inadm)}
                 for i in range(min(len(chosen), len(negs)))
                 if chosen[i][1] != negs[i][1] and (i < len(inadm) or chosen[i][0] - negs[i][0] > 0)]
        print(f"built {len(pairs)} RULE-CONSTRAINED verified-reward pairs "
              f"(chosen=KB-admissible high-{args.signal}; {len(inadm)}/{len(scored)} pool candidates gate-failed)", flush=True)
    else:
        k = min(len(scored) // 2, args.pairs)
        hi, lo = scored[:k], scored[::-1][:k]
        pairs = [{"chosen": hi[i][1], "rejected": lo[i][1], "margin": float(hi[i][0] - lo[i][0]), "kb_clean_neg": False}
                 for i in range(k) if hi[i][1] != lo[i][1]]
        print(f"built {len(pairs)} verified-reward pairs (property only; KB gate OFF)", flush=True)
    if not pairs:
        raise SystemExit("no preference pairs (all pool candidates gate-failed or identical) — relax gate or raise pool")

    # 5) DPO close on the real v4
    model = dpo_finetune(model, stoi, pairs, tf_t, dev, args.steps, args.beta, args.lr, args.batch,
                         e_tok=e_tok, p_tok=p_tok)

    # 6) after (independent evaluator oracle_B)
    aft = gen(model, toks, stoi, tf, dev, block, args.eval_n, args.temp, e_tok=e_tok, p_tok=p_tok)
    m_after = metrics(aft, ob, feat, train_keys, gate_target)
    aft_A = metrics(aft, oa, feat, train_keys, gate_target)["oracle_mean"]
    print(f"AFTER   evalB_mean={m_after['oracle_mean']}  (rewardA_mean={aft_A})  valid={m_after['validity']} "
          f"novelty={m_after['novelty']} diversity={m_after['diversity']} kb_admissible={m_after['kb_admissible']}", flush=True)

    dB = round(m_after["oracle_mean"] - m_before["oracle_mean"], 4)
    dA = round(aft_A - base_A, 4)

    # ---- publication-standard extras: FCD-analog (distribution match to real peptides), random baseline ----
    rng = np.random.default_rng(0)
    ref_idx = rng.choice(len(rows), min(len(rows), 1000), replace=False)
    ref_feats = np.array([feat(rows[i][0]) for i in ref_idx])
    fcd_before = round(frechet_feature_distance([feat(m) for m in base], ref_feats), 4)
    fcd_after = round(frechet_feature_distance([feat(m) for m in aft], ref_feats), 4)
    # random baseline: uniform-random monomer sequences (floor the oracle/property must beat)
    vocab_canon = [m for m, _ in [(x, 0) for x in {mm for mo, _ in rows for mm in mo}]]
    rand = [[vocab_canon[j] for j in rng.integers(0, len(vocab_canon), rng.integers(5, 16))] for _ in range(args.eval_n)]
    rand_B = round(float(np.mean([ob.predict(feat(m)[None])[0] for m in rand])), 4)

    verdict = ("LOOP IMPROVES GENERATOR (independent evaluator rose, diversity held)"
               if dB > 0 and m_after["diversity"] >= 0.5 * m_before["diversity"] and m_after["novelty"] >= 0.5 * m_before["novelty"]
               else "INCONCLUSIVE / possible reward-hacking (see dA vs dB + diversity)")
    print(f"FCD-analog (gen vs real): {fcd_before} -> {fcd_after}  | random-baseline evalB={rand_B}  "
          f"| oracle-budget AUC={budget_auc}", flush=True)
    res = {"what": f"RULE-CONSTRAINED verified-reward generator-close on the COLLECTED v4 model + COLLECTED {reward_name}",
           "signal": args.signal, "target": (args.target if args.signal == "binding" else None),
           "seed": args.seed, "shuffle_reward_placebo": bool(args.shuffle_reward),
           "kb_rule_constraint": {"enabled": bool(args.kb_gate), "resolver": "experience_kb.resolve",
                                  "gate_target": gate_target, "provenance_entries": len(kb_prov),
                                  "kb_admissible_before": m_before["kb_admissible"], "kb_admissible_after": m_after["kb_admissible"]},
           "reward": f"oracle_A trained on {reward_name} (disjoint half); CHOSEN must pass the KB gate",
           "evaluator": "oracle_B trained on the OTHER disjoint half (anti-circular)",
           "oracle_stats": ostat, "n_pairs": len(pairs), "dpo": {"steps": args.steps, "beta": args.beta, "lr": args.lr},
           "before": m_before, "after": m_after, "reward_oracleA_before": base_A, "reward_oracleA_after": aft_A,
           "delta_independent_evaluatorB": dB, "delta_reward_oracleA": dA,
           "publication_metrics": {"split": ostat.get("split"), "fcd_analog_before": fcd_before,
                                   "fcd_analog_after": fcd_after, "random_baseline_evalB": rand_B,
                                   "oracle_budget_auc": budget_auc,
                                   "note": "cluster-disjoint (leakage-safe) oracles; FCD-analog = Fréchet feature "
                                           "distance to real peptides (ChemNet-FCD N/A for ncAA monomer seqs); "
                                           "random baseline = uniform-random monomer sequences; budget AUC = PMO-style."},
           "verdict": verdict}
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    json.dump(res, open(args.out, "w"), indent=2)
    torch.save({"model": model.state_dict(), "toks": toks, "args": a}, args.save_ckpt)
    print(f"\nΔ independent-evaluator(B) = {dB:+}   Δ reward-oracle(A) = {dA:+}")
    print(f"VERDICT: {verdict}")
    print(f"wrote {os.path.relpath(args.out, ROOT)} + fine-tuned ckpt {os.path.relpath(args.save_ckpt, ROOT)}")


if __name__ == "__main__":
    main()
