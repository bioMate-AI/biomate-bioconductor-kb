#!/usr/bin/env python3
"""L7a/L7b: large general LLMs used IN CONTEXT as the loop learner (PREREG_LOOP.md amendments L7a, L7b). No fine-tuning: each round the model sees revealed (SMILES, within-source label) examples
in the prompt and ranks a seeded 150-candidate subset (the SAME subsets the small-model *_sub arms use). Same L5 task, init sets, pools, E and E_f slices.
usage: run_l7a_llm.py CycPeptMPDB.csv OUTDIR --model M [--regimes AB] [--seeds 0-3] [--cap-usd 0.75] [--control] [--probe]
Arms: llm_loop (feedback), llm_kb (feedback + KB text), llm_frozen (initial 100 examples only), llm_zeroshot (no labels), llm_shuffled, llm_oneshot, subset_random, subset_gbm; stereo-resolved ranking at the final round.
Cost accounted per arm from the API-reported cost (hard cap aborts; HTTP 402 stops without retry)."""
import os, sys, re, json, time, random, argparse, collections, threading, difflib, urllib.request, urllib.error
from concurrent.futures import ThreadPoolExecutor
import numpy as np
os.environ.setdefault("FP_CHIRAL", "1"); os.environ.setdefault("LABEL_COL", "PAMPA")
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import run_loop as R, run_loop_par as P, run_loop_prior as K, run_l7a as L, loop_models as LM

N_CAND, N_PICK, N_SHOW, ROUNDS, N_INIT, N_EVAL, N_FLAT = 150, 50, 80, 10, 100, 800, 60
_kf = os.path.expanduser("~/.config/biomate/openrouter.key"); KEY = open(_kf).read().strip() if os.path.exists(_kf) else ""      # absent on compute instances (they never call the API)
SYSTEM = "You are an expert in cyclic-peptide medicinal chemistry and passive membrane permeability."
LLM_ARMS = ("llm_loop", "llm_kb", "llm_kb_contra", "llm_frozen", "llm_zeroshot", "llm_shuffled", "subset_random", "subset_gbm")
STEREO_ARMS = ("llm_loop", "llm_kb", "llm_frozen", "llm_zeroshot")


class Cost:
    def __init__(self, cap): self.cap, self.usd, self.tin, self.tout, self.calls, self.lock = cap, 0.0, 0, 0, 0, threading.Lock()
    def add(self, u, acc=None):
        c = float(u.get("cost") or 0.0)
        with self.lock:
            self.tin += u.get("prompt_tokens", 0); self.tout += u.get("completion_tokens", 0); self.calls += 1; self.usd += c
            if acc is not None: acc["usd"] += c; acc["tin"] += u.get("prompt_tokens", 0); acc["tout"] += u.get("completion_tokens", 0); acc["calls"] += 1
            if self.usd > self.cap: raise SystemExit(f"COST CAP {self.cap} USD exceeded ({self.usd:.3f}) after {self.calls} calls — aborting")


def new_acc(): return dict(usd=0.0, tin=0, tout=0, calls=0, seconds=0.0)


def kb_block():
    """Evidence-backed permeability statements from the in-repo KB (medchem_kb), with citations (T1, verified)."""
    sys.path.insert(0, os.path.join(HERE, "..")); import medchem_kb as M
    st = [e for e in M.physchem_for("cyclic_peptide") if "permeab" in e["statement"].lower()] + [e for e in M.modality_heuristics("cyclic_peptide") if "permeab" in e["statement"].lower()]
    return "Established knowledge (literature-cited):\n" + "\n".join(f"- {e['statement']} [{e['source']}]" for e in st) + "\n\n"


def kb_contra_block():
    """COUNTERFACTUAL knowledge for the dimension-5 probe: the N-methylation relation is stated in the wrong direction (no citation; the log marks the arm as counterfactual)."""
    return "Established knowledge:\n- Backbone N-methylation LOWERS passive permeability of cyclic peptides (added steric bulk and lipophilic desolvation penalty); fewer N-methyl groups give higher permeability.\n\n"


def build_prompt(examples, cands, smiles, kb=""):
    ex = "".join(f"{smiles[i]}\t{l:.1f}\n" for i, l in examples)
    head = "Labels are within-literature-source z-scores of measured PAMPA log Papp (higher = more permeable).\n\n" + kb
    if examples: head += f"Measured examples (SMILES<TAB>label):\n{ex}\n"
    cd = "".join(f"{j}: {smiles[i]}\n" for j, i in enumerate(cands))
    return head + f"Candidates (index: SMILES):\n{cd}\nSelect the {N_PICK} candidates most likely to have the HIGHEST label. Return ONLY JSON: {{\"ranking\": [indices, best first], \"rationale\": \"<=40 words\"}}"


MAXTOK = [4000]          # set from --max-tokens (reasoning models need more headroom)


def call(prompt, model, cost, acc=None, tries=4, max_tokens=None):      # reasoning models spend part of this budget on hidden reasoning before the JSON answer
    max_tokens = max_tokens or MAXTOK[0]
    if os.environ.get("L7_MOCK"):                      # offline dry run: deterministic fake ranking, zero cost (pipeline/logging tests only; never used for results)
        h = abs(hash(prompt)) % 1000; cost.add({"prompt_tokens": len(prompt) // 3, "completion_tokens": 50, "cost": 0.0}, acc)
        return json.dumps({"ranking": [(h + 3 * j) % 100 for j in range(50)], "rationale": "mock", **{str(g): [3, 1, 0, 2, 4, 5] for g in range(80)}})
    body = json.dumps({"model": model, "temperature": 0, "max_tokens": max_tokens, "messages": [{"role": "system", "content": SYSTEM}, {"role": "user", "content": prompt}]}).encode()
    t0 = time.time()
    for k in range(tries):
        try:
            rq = urllib.request.Request("https://openrouter.ai/api/v1/chat/completions", body, {"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"})
            d = json.load(urllib.request.urlopen(rq, timeout=240)); cost.add(d.get("usage", {}), acc)
            if acc is not None: acc["seconds"] += time.time() - t0
            return d["choices"][0]["message"]["content"] or ""
        except SystemExit: raise
        except urllib.error.HTTPError as e:
            if e.code == 402: raise SystemExit("HTTP 402 Payment Required: OpenRouter credit exhausted — stopping, no retry")
            if k == tries - 1: raise
            time.sleep(3 * (k + 1))
        except Exception:
            if k == tries - 1: raise
            time.sleep(3 * (k + 1))


def parse(txt, n_cand):
    m = re.search(r"\{.*\}", txt, re.S)
    try: r = [int(x) for x in json.loads(m.group(0))["ranking"]]
    except Exception: r = [int(x) for x in re.findall(r"\d+", txt)]
    seen, out = set(), []
    for x in r:
        if 0 <= x < n_cand and x not in seen: seen.add(x); out.append(x)
    return out


def shown(labeled, ylab, n=None):
    n = n or N_SHOW                                  # module global so --nshow (Tier A: 40) takes effect
    o = np.argsort(ylab, kind="stable"); h = n // 2; sel = list(o[:h]) + list(o[-h:]) if len(o) > n else list(o)
    return [(labeled[i], float(ylab[i])) for i in sel]


def subset(pool0, seed, r, revealed): return L.subset(pool0, seed, r, revealed, N_CAND)


def run_seq(arm, ctx, init, pool, seed, a, cost, smiles, kb, gbm=None, loop_final=None, kb_contra=""):
    y = ctx["y"]; rng = np.random.default_rng(seed); labeled = list(init); ylab = list(y[init]); pool0 = list(pool); acc = new_acc(); t0 = time.time()
    rec = dict(hits=[], hits_g=[], src=[], fills=0, ef_sub=[], calls=[]); ypool = y[np.array(pool0)]; rounds = 1 if arm == "llm_oneshot" else ROUNDS
    for r in range(rounds):
        cands = subset(pool0, seed, (ROUNDS - 1) if arm == "llm_oneshot" else r, labeled if arm != "llm_oneshot" else init)
        if arm == "llm_oneshot": labeled, ylab = list(loop_final["labeled"]), list(loop_final["ylab"]); cands = [i for i in cands if i not in set(labeled)]
        if arm == "subset_random": pick = list(rng.choice(cands, N_PICK, replace=False))
        elif arm == "subset_gbm":
            st = gbm.fit(None, labeled, np.array(ylab), 0, seed * 1000 + r); s = gbm.predict(st, cands); pick = [cands[j] for j in np.argsort(-s, kind="stable")[:N_PICK]]
        else:
            if arm == "llm_zeroshot": ex = []
            elif arm == "llm_frozen": ex = shown(list(init), np.array(list(y[init])))        # initial labels only, every round (no feedback)
            elif arm == "llm_oneshot": ex = [(labeled[i], float(ylab[i])) for i in range(len(labeled))]
            else: ex = shown(labeled, np.array(ylab))
            prompt_kb = kb if arm == "llm_kb" else (kb_contra if arm == "llm_kb_contra" else "")
            a0 = dict(acc); txt = call(build_prompt(ex, cands, smiles, prompt_kb), a.model, cost, acc); rk = parse(txt, len(cands))[:N_PICK]
            rec["calls"].append(dict(round=r, n_cands=len(cands), cands=[int(i) for i in cands], examples=[[int(i), float(l)] for i, l in ex], response=txt, n_valid=len(rk), tin=acc["tin"] - a0["tin"], tout=acc["tout"] - a0["tout"],
                                     usd=round(acc["usd"] - a0["usd"], 6), seconds=round(acc["seconds"] - a0["seconds"], 2)))
            if len(rk) < N_PICK:
                rec["fills"] += N_PICK - len(rk); left = [j for j in range(len(cands)) if j not in set(rk)]; rk += [int(j) for j in rng.choice(left, N_PICK - len(rk), replace=False)]
            pick = [cands[j] for j in rk]
        pick = [int(i) for i in pick]
        rec["hits"].append(int(sum(y[i] >= ctx["thr"] for i in pick))); rec["hits_g"].append(int(sum(y[i] >= ctx["thr_g"][i] for i in pick)))
        c = collections.Counter(ctx["srcs"][i] for i in pick); rec["src"].append({"2020_Townsend": c.get("2020_Townsend", 0), "2021_Kelly": c.get("2021_Kelly", 0), "other": len(pick) - c.get("2020_Townsend", 0) - c.get("2021_Kelly", 0)})
        rec["ef_sub"].append(float(np.mean([y[i] >= ctx["thr"] for i in pick]) / max(1e-9, np.mean([y[i] >= ctx["thr"] for i in cands]))))
        rec.setdefault("picks", []).append(pick)
        if arm not in ("llm_oneshot", "llm_frozen", "llm_zeroshot"):
            labeled += pick; new = y[pick].copy()
            if arm == "llm_shuffled": new = rng.choice(ypool, len(pick), replace=False)          # L7d: global draw from the pool's label vector
            ylab += list(new)
    rec["cost"] = dict(acc, wall_seconds=round(time.time() - t0, 1))
    rec["_final"] = (list(labeled), [float(v) for v in ylab])          # examples this arm would show at the end (used for the stereo call; stripped before saving)
    return rec


def stereo_call(arm, rec, ctx, init, Ef_groups, Ef_sib, smiles, a, cost, kb):
    """One call at the final round (L7d): per flat group the REVEALED sibling and its label are shown (SAR setting) and the TARGET stereoisomers are ranked, using THIS arm's own examples.
    Returns mean within-group Spearman over groups (an unparsable or incomplete group counts as rho = 0 and is counted in n_failed)."""
    y = ctx["y"]; labeled, ylab = rec["_final"]
    ex = [] if arm in ("llm_zeroshot",) else (shown(list(init), np.array(list(y[init]))) if arm == "llm_frozen" else shown(labeled, np.array(ylab)))
    head = "Labels are within-literature-source z-scores of measured PAMPA log Papp (higher = more permeable).\n\n" + (kb if arm == "llm_kb" else "")
    if ex: head += "Measured examples (SMILES<TAB>label):\n" + "".join(f"{smiles[i]}\t{l:.1f}\n" for i, l in ex) + "\n"
    body = "Each group below contains STEREOISOMERS of one constitution (identical atoms and connectivity, different stereochemistry). One isomer per group has a KNOWN label; rank the UNKNOWN isomers of the group from highest to lowest expected label.\n"
    for g, mem in enumerate(Ef_groups): body += f"Group {g}: known isomer {smiles[Ef_sib[g]]}\tlabel {y[Ef_sib[g]]:.1f}\n" + "".join(f"  {j}: {smiles[i]}\n" for j, i in enumerate(mem))
    body += "Return ONLY JSON: {\"0\": [unknown-isomer indices best first], \"1\": [...], ...}"
    acc = new_acc(); txt = call(head + body, a.model, cost, acc, max_tokens=2 * MAXTOK[0]); rs = []; failed = 0
    try: obj = json.loads(re.search(r"\{.*\}", txt, re.S).group(0))
    except Exception: obj = {}
    for g, mem in enumerate(Ef_groups):
        lab = y[mem]
        if np.std(lab) == 0: continue
        try: order = [int(v) for v in obj[str(g)]]; order = [v for v in order if 0 <= v < len(mem)]
        except Exception: order = []
        if len(set(order)) < len(mem): rs.append(0.0); failed += 1; continue
        score = np.zeros(len(mem))
        for k, v in enumerate(order): score[v] = len(order) - k
        rs.append(L.spearman(score, lab))
    return dict(mean_rho=float(np.mean(rs)) if rs else float("nan"), n_groups=len(rs), n_failed=failed, response=txt, cost=acc)


def planted_control(a, cost, smiles):
    """Prior-independent plumbing check: the same examples with the planted relation (label = -N-methyl count) vs sign-flipped must move the picks in OPPOSITE directions; shuffled must stay near zero-shot."""
    from rdkit import Chem
    NME = Chem.MolFromSmarts("[CX3](=O)[NX3]([CH3])"); rng = np.random.default_rng(0); idx = rng.choice(len(smiles), 230, replace=False)
    nm = np.array([len(Chem.MolFromSmiles(smiles[i]).GetSubstructMatches(NME)) for i in idx], float); lab = -(nm - nm.mean()) / (nm.std() + 1e-9)
    ex_i, cand_i = idx[:80], idx[80:]; cl = lab[80:]; exl = lab[:80]; res = {}; acc = new_acc()
    for name, labs, use in (("zeroshot", exl, False), ("planted", exl, True), ("flipped", -exl, True), ("shuffled", rng.permutation(exl), True)):
        ex = [(int(i), float(l)) for i, l in zip(ex_i, labs)] if use else []
        rk = parse(call(build_prompt(ex, [int(i) for i in cand_i], smiles), a.model, cost, acc), len(cand_i))[:N_PICK]
        res[name] = dict(mean_label_of_picks=float(np.mean(cl[rk])) if rk else float("nan"), n=len(rk))
    ex = [(int(i), float(l)) for i, l in zip(ex_i, exl)]; pr = build_prompt(ex, [int(i) for i in cand_i], smiles)                  # determinism probe (dimension 9): the SAME prompt twice
    ra = parse(call(pr, a.model, cost, acc), len(cand_i))[:N_PICK]; rb = parse(call(pr, a.model, cost, acc), len(cand_i))[:N_PICK]
    res["determinism_top50_overlap"] = len(set(ra) & set(rb)) / float(N_PICK)
    res["effect_planted_minus_flipped"] = res["planted"]["mean_label_of_picks"] - res["flipped"]["mean_label_of_picks"]
    res["pass"] = bool(res["effect_planted_minus_flipped"] >= 0.4 and abs(res["shuffled"]["mean_label_of_picks"] - res["zeroshot"]["mean_label_of_picks"]) < 0.4)
    res["tokens_per_call_in"] = acc["tin"] / max(1, acc["calls"]); res["tokens_per_call_out"] = acc["tout"] / max(1, acc["calls"]); res["usd"] = acc["usd"]; res["model"] = a.model; return res


def stereo_scramble(smi, rng):
    """Invert 2 random stereocentre tags: a near-identical molecule absent from any public source (memorisation-probe decoy)."""
    pos = [m.start() for m in re.finditer(r"@@?", smi)]
    if len(pos) < 2: return None
    out = smi
    for p_ in sorted(rng.choice(len(pos), 2, replace=False), reverse=True):
        s = pos[p_]; e = s + (2 if smi[s:s + 2] == "@@" else 1); out = out[:s] + ("@" if smi[s:e] == "@@" else "@@") + out[e:]
    return out


def memo_probe(a, cost, smiles, n=30, frac=0.6):
    """Prefix-completion memorisation probe: dataset peptides vs stereo-scrambled decoys of the same peptides. Flag if mean(real - decoy) similarity has a lower 95 % bound > 0.05."""
    rng = np.random.default_rng(1); idx = rng.choice(len(smiles), n * 3, replace=False); real, dec = [], []; acc = new_acc()
    for i in idx:
        s = smiles[i]; d = stereo_scramble(s, rng)
        if d is None or len(s) < 60: continue
        sims = []
        for t in (s, d):
            cut = int(len(t) * frac); pre, suf = t[:cut], t[cut:]
            txt = (call(f"Complete this peptide SMILES string. Output ONLY the remaining characters, nothing else.\n{pre}", a.model, cost, acc, max_tokens=1500) or "").strip().replace("`", "")
            txt = txt.split()[0] if txt.split() else ""
            sims.append(difflib.SequenceMatcher(None, txt[:len(suf) + 20], suf).ratio())
        real.append(sims[0]); dec.append(sims[1])
        if len(real) >= n: break
    diff = np.array(real) - np.array(dec); bs = [float(np.mean(rng.choice(diff, len(diff)))) for _ in range(2000)]
    return dict(model=a.model, n=len(diff), mean_real=float(np.mean(real)), mean_decoy=float(np.mean(dec)), mean_diff=float(diff.mean()), lower95=float(np.percentile(bs, 2.5)), flagged=bool(np.percentile(bs, 2.5) > 0.05), usd=acc["usd"])


def run_curve(ctx, init, pool, seed, a, cost, smiles):
    """L7c dimension 1: one call per k in {0, 25, 50, 100} initial labels on the round-0 candidate subset."""
    y = ctx["y"]; cands = subset(list(pool), seed, 0, init); out = {}; acc = new_acc()
    for k in (0, 25, 50, 100):
        ex = shown(list(init[:k]), np.array(list(y[init[:k]]))) if k > 0 else []; txt = call(build_prompt(ex, cands, smiles), a.model, cost, acc); rk = parse(txt, len(cands))[:N_PICK]
        pick = [cands[j] for j in rk]; out[str(k)] = dict(sub_hits=int(sum(y[i] >= ctx["thr"] for i in pick)), sub_hits_g=int(sum(y[i] >= ctx["thr_g"][i] for i in pick)), n_valid=len(rk), picks=[int(i) for i in pick])
    out["cost"] = acc; return out


def main():
    global ROUNDS, N_SHOW, LLM_ARMS, STEREO_ARMS
    ap = argparse.ArgumentParser(); ap.add_argument("csv"); ap.add_argument("out"); ap.add_argument("--model", required=True); ap.add_argument("--regimes", default="AB"); ap.add_argument("--seeds", default="0-3")
    ap.add_argument("--cap-usd", type=float, default=0.75); ap.add_argument("--control", action="store_true"); ap.add_argument("--probe", action="store_true"); ap.add_argument("--workers", type=int, default=8); ap.add_argument("--max-tokens", type=int, default=4000)
    ap.add_argument("--rounds", type=int, default=10); ap.add_argument("--nshow", type=int, default=80); ap.add_argument("--arms", default=",".join(LLM_ARMS)); ap.add_argument("--stereo-arms", default=",".join(STEREO_ARMS))
    ap.add_argument("--extras", default="oneshot,curve")
    a = ap.parse_args(); MAXTOK[0] = a.max_tokens; ROUNDS, N_SHOW = a.rounds, a.nshow; LLM_ARMS = tuple(a.arms.split(",")); STEREO_ARMS = tuple(x for x in a.stereo_arms.split(",") if x); extras = set(a.extras.split(",")); os.makedirs(a.out, exist_ok=True); cost = Cost(a.cap_usd); tag = a.model.replace("/", "__")
    recs, d = L.build(a.csv, "gbm", "cpu"); smiles = [r["smiles"] for r in recs]; kb = kb_block(); gbm = d["B"]
    if a.control:
        r = planted_control(a, cost, smiles); json.dump(r, open(f"{a.out}/{tag}__control.json", "w"), indent=1); print(json.dumps(r)); print("USD %.3f" % cost.usd); return
    if a.probe:
        r = memo_probe(a, cost, smiles); json.dump(r, open(f"{a.out}/{tag}__probe.json", "w"), indent=1); print(json.dumps(r)); print("USD %.3f" % cost.usd); return
    ctx = {k: d[k] for k in ("y", "thr", "thr_g", "srcs")}
    def task(arg):
        reg, seed = arg; f = f"{a.out}/{tag}__{reg}_{seed}.json"
        if os.path.exists(f): return
        init, pool = P.setup(reg, seed, d["srcs"], d["scaf"], N_INIT, d["flat"]); E, pool = L.make_eval_slice(pool, seed, N_EVAL); Ef, Efg, Efs, pool = L.make_flat_slice(pool, d["flat"], seed, N_FLAT, d["y"]); Es, pool = L.make_source_slice(pool, d["srcs"], seed)
        out = {"seed": seed, "regime": reg, "model": a.model, "n_pool": len(pool), "n_Ef": len(Ef), "init": [int(i) for i in init], "E": [int(i) for i in E], "Es": [int(i) for i in Es]}
        for arm in LLM_ARMS: out[arm] = run_seq(arm, ctx, init, pool, seed, a, cost, smiles, kb, gbm, kb_contra=kb_contra_block())
        out["protocol"] = dict(rounds=ROUNDS, n_show=N_SHOW, arms=list(LLM_ARMS), stereo_arms=list(STEREO_ARMS), extras=sorted(extras), max_tokens=MAXTOK[0])
        if "curve" in extras: out["llm_curve"] = run_curve(ctx, init, pool, seed, a, cost, smiles)
        if "oneshot" in extras: out["llm_oneshot"] = run_seq("llm_oneshot", ctx, init, pool, seed, a, cost, smiles, kb, loop_final=dict(labeled=out["llm_loop"]["_final"][0], ylab=out["llm_loop"]["_final"][1]))
        for arm in STEREO_ARMS: out[arm]["stereo"] = stereo_call(arm, out[arm], ctx, init, Efg, Efs, smiles, a, cost, kb)
        for arm in LLM_ARMS + ("llm_oneshot",):
            if arm in out: out[arm].pop("_final", None)
        json.dump(out, open(f + ".tmp", "w")); os.replace(f + ".tmp", f)
        print("done", reg, seed, {k: sum(out[k]["hits"]) for k in out if isinstance(out[k], dict) and "hits" in out[k]}, "USD %.3f" % cost.usd, flush=True)
    with ThreadPoolExecutor(a.workers) as ex: list(ex.map(task, [(g, s) for g in a.regimes for s in L.parse_seeds(a.seeds)]))
    print("TOTAL USD %.3f calls %d tokens in %d out %d" % (cost.usd, cost.calls, cost.tin, cost.tout))


if __name__ == "__main__":
    main()
