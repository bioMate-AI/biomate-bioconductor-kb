#!/usr/bin/env python3
"""L7a arm (e): frontier general LLM used IN CONTEXT as the loop learner (PREREG_LOOP.md amendment L7a). No fine-tuning: each round the model sees revealed (SMILES, within-source label) examples
in the prompt and ranks a seeded candidate subset. Same L5 task, init sets, pools, E slice (E is removed from the pool; the LLM never sees E).
usage: run_l7a_llm.py CycPeptMPDB.csv OUTDIR [--regimes AB] [--seeds 0-4] [--model anthropic/claude-sonnet-5.5] [--cap-usd 22] [--estimate] [--control] [--smoke]
Arms: llm_loop, llm_kb, llm_shuffled, llm_zeroshot, llm_oneshot, subset_random, subset_gbm. Cost accounting from returned usage; hard cap aborts."""
import os, sys, re, json, time, random, argparse, collections, threading, urllib.request
from concurrent.futures import ThreadPoolExecutor
import numpy as np
os.environ.setdefault("FP_CHIRAL", "1"); os.environ.setdefault("LABEL_COL", "PAMPA")
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import run_loop as R, run_loop_par as P, run_loop_prior as K, run_l7a as L, loop_models as LM

PRICE_IN, PRICE_OUT = 2.0e-6, 10.0e-6          # anthropic/claude-sonnet-5.5 via OpenRouter (checked 2026-10-28)
N_CAND, N_PICK, N_SHOW, ROUNDS, N_INIT, N_EVAL = 150, 50, 80, 10, 100, 800
KEY = open(os.path.expanduser("~/.config/biomate/openrouter.key")).read().strip()
SYSTEM = "You are an expert in cyclic-peptide medicinal chemistry and passive membrane permeability."


class Cost:
    def __init__(self, cap): self.cap, self.usd, self.api_usd, self.tin, self.tout, self.calls, self.lock = cap, 0.0, 0.0, 0, 0, 0, threading.Lock()
    def add(self, u):
        with self.lock:
            self.tin += u.get("prompt_tokens", 0); self.tout += u.get("completion_tokens", 0); self.calls += 1
            self.api_usd += float(u.get("cost") or 0.0)                       # API-reported cost (authoritative); token-based figure kept as a cross-check
            self.usd = max(self.api_usd, self.tin * PRICE_IN + self.tout * PRICE_OUT)
            if self.usd > self.cap: raise SystemExit(f"COST CAP {self.cap} USD exceeded ({self.usd:.2f}) after {self.calls} calls — aborting")


def kb_block():
    """Evidence-backed permeability statements from the in-repo KB (medchem_kb), with citations (T1, verified)."""
    sys.path.insert(0, os.path.join(HERE, "..")); import medchem_kb as M
    st = [e for e in M.physchem_for("cyclic_peptide") if "permeab" in e["statement"].lower()] + [e for e in M.modality_heuristics("cyclic_peptide") if "permeab" in e["statement"].lower()]
    return "Established knowledge (literature-cited):\n" + "\n".join(f"- {e['statement']} [{e['source']}]" for e in st) + "\n\n"


def build_prompt(examples, cands, smiles, kb=""):
    ex = "".join(f"{smiles[i]}\t{l:.1f}\n" for i, l in examples)
    head = "Labels are within-literature-source z-scores of measured PAMPA log Papp (higher = more permeable).\n\n" + kb
    if examples: head += f"Measured examples (SMILES<TAB>label):\n{ex}\n"
    cd = "".join(f"{j}: {smiles[i]}\n" for j, i in enumerate(cands))
    return head + f"Candidates (index: SMILES):\n{cd}\nSelect the {N_PICK} candidates most likely to have the HIGHEST label. Return ONLY JSON: {{\"ranking\": [indices, best first]}}"


def call(prompt, model, cost, tries=4):
    body = json.dumps({"model": model, "temperature": 0, "max_tokens": 700, "messages": [{"role": "system", "content": SYSTEM}, {"role": "user", "content": prompt}]}).encode()
    for k in range(tries):
        try:
            rq = urllib.request.Request("https://openrouter.ai/api/v1/chat/completions", body, {"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"})
            d = json.load(urllib.request.urlopen(rq, timeout=180)); cost.add(d.get("usage", {})); return d["choices"][0]["message"]["content"]
        except SystemExit: raise
        except Exception as e:
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


def shown(labeled, ylab, n=N_SHOW):
    o = np.argsort(ylab); h = n // 2; sel = list(o[:h]) + list(o[-h:]) if len(o) > n else list(o)
    return [(labeled[i], float(ylab[i])) for i in sel]


def subset(pool, seed, r, revealed):
    rr = random.Random(777 * seed + r); c = rr.sample(list(pool), N_CAND); rv = set(revealed); return [i for i in c if i not in rv]


def run_seq(arm, ctx, init, pool, seed, a, cost, smiles, kb, gbm=None, loop_final=None):
    y = ctx["y"]; rng = np.random.default_rng(seed); labeled = list(init); ylab = list(y[init]); rec = dict(hits=[], hits_g=[], src=[], fills=0, ef_sub=[])
    last_c = None
    rounds = 1 if arm == "llm_oneshot" else ROUNDS
    for r in range(rounds):
        cands = subset(pool, seed, (ROUNDS - 1) if arm == "llm_oneshot" else r, labeled if arm != "llm_oneshot" else init)
        if arm == "llm_oneshot": labeled, ylab = list(loop_final["labeled"]), list(loop_final["ylab"]); cands = [i for i in cands if i not in set(labeled)]
        if arm == "subset_random": pick = list(rng.choice(cands, N_PICK, replace=False))
        elif arm == "subset_gbm":
            st = gbm.fit(None, labeled, np.array(ylab), 0, seed * 1000 + r); s = gbm.predict(st, cands); pick = [cands[j] for j in np.argsort(-s, kind="stable")[:N_PICK]]
        else:
            ex = [] if arm == "llm_zeroshot" else shown(labeled, np.array(ylab))
            if arm == "llm_shuffled": ex = [(i, l) for (i, _), l in zip(ex, rng.permutation([l for _, l in ex]))]
            if arm == "llm_oneshot": ex = [(labeled[i], float(ylab[i])) for i in range(len(labeled))]
            rk = parse(call(build_prompt(ex, cands, smiles, kb if arm == "llm_kb" else ""), a.model, cost), len(cands))[:N_PICK]
            if len(rk) < N_PICK:
                rec["fills"] += N_PICK - len(rk); left = [j for j in range(len(cands)) if j not in set(rk)]; rk += [int(j) for j in rng.choice(left, N_PICK - len(rk), replace=False)]
            pick = [cands[j] for j in rk]
        pick = [int(i) for i in pick]; pk = set(pick); pool = [i for i in pool if i not in pk] if arm != "llm_oneshot" else pool
        rec["hits"].append(int(sum(y[i] >= ctx["thr"] for i in pick))); rec["hits_g"].append(int(sum(y[i] >= ctx["thr_g"][i] for i in pick)))
        c = collections.Counter(ctx["srcs"][i] for i in pick); rec["src"].append({"2020_Townsend": c.get("2020_Townsend", 0), "2021_Kelly": c.get("2021_Kelly", 0), "other": len(pick) - c.get("2020_Townsend", 0) - c.get("2021_Kelly", 0)})
        rec["ef_sub"].append(float(np.mean([y[i] >= ctx["thr"] for i in pick]) / max(1e-9, np.mean([y[i] >= ctx["thr"] for i in cands]))))   # enrichment of picks over the subset's own hit rate
        if arm != "llm_oneshot":
            labeled += pick; new = y[pick].copy()
            if arm == "llm_shuffled": new = rng.permutation(new)
            ylab += list(new)
    rec["labeled"], rec["ylab"] = (labeled, [float(v) for v in ylab]) if arm == "llm_loop" else (None, None)
    return rec


def planted_control(a, cost, smiles, recs):
    """Plumbing check: label = - (N-methyl count). Zero-shot prior prefers N-methylated peptides (wrong direction here); with in-context examples showing the reversed relation the picks must flip; shuffled must not."""
    from rdkit import Chem
    NME = Chem.MolFromSmarts("[CX3](=O)[NX3]([CH3])"); rng = np.random.default_rng(0); idx = rng.choice(len(smiles), 230, replace=False)
    nm = np.array([len(Chem.MolFromSmiles(smiles[i]).GetSubstructMatches(NME)) for i in idx], float); lab = -(nm - nm.mean()) / (nm.std() + 1e-9)
    ex_i, cand_i = idx[:80], idx[80:]; cl = lab[80:]; exl = lab[:80]; res = {}
    for name, labs, use in (("zeroshot", exl, False), ("planted", exl, True), ("flipped", -exl, True), ("shuffled", rng.permutation(exl), True)):
        ex = [(int(i), float(l)) for i, l in zip(ex_i, labs)] if use else []
        rk = parse(call(build_prompt(ex, [int(i) for i in cand_i], smiles), a.model, cost), len(cand_i))[:N_PICK]
        res[name] = dict(mean_label_of_picks=float(np.mean(cl[rk])), mean_label_candidates=float(np.mean(cl)), n=len(rk))
    res["effect_planted_minus_flipped"] = res["planted"]["mean_label_of_picks"] - res["flipped"]["mean_label_of_picks"]      # prior-independent: examples with opposite relations must move the picks in opposite directions
    res["pass"] = bool(res["effect_planted_minus_flipped"] >= 0.4 and abs(res["shuffled"]["mean_label_of_picks"] - res["zeroshot"]["mean_label_of_picks"]) < 0.4)
    print(json.dumps(res, indent=1)); return res


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("csv"); ap.add_argument("out"); ap.add_argument("--regimes", default="AB"); ap.add_argument("--seeds", default="0-4"); ap.add_argument("--model", default="anthropic/claude-sonnet-5.5")
    ap.add_argument("--cap-usd", type=float, default=22.0); ap.add_argument("--estimate", action="store_true"); ap.add_argument("--control", action="store_true"); ap.add_argument("--workers", type=int, default=8)
    a = ap.parse_args(); os.makedirs(a.out, exist_ok=True); cost = Cost(a.cap_usd)
    recs, d = L.build(a.csv, "gbm", "cpu"); smiles = [r["smiles"] for r in recs]; kb = kb_block(); gbm = d["B"]
    if a.control:
        r = planted_control(a, cost, smiles, recs); json.dump(r, open(f"{a.out}/planted_control.json", "w"), indent=1); print("cost so far USD %.3f (%d calls, %d in / %d out tokens)" % (cost.usd, cost.calls, cost.tin, cost.tout)); return
    ctx = {k: d[k] for k in ("y", "thr", "thr_g", "srcs")}; seeds = L.parse_seeds(a.seeds)
    if a.estimate:    # real prompts for round 1 and round 10 (examples = what the loop would show), characters/3.0 as a conservative token proxy for SMILES
        tot = 0.0; per = {}
        for reg in a.regimes:
            init, pool = P.setup(reg, 0, d["srcs"], d["scaf"], N_INIT, d["flat"]); E, pool = L.make_eval_slice(pool, 0, N_EVAL)
            y = d["y"]; lab = list(init) + list(pool[:500]); ylab = list(y[lab])
            for r_, nlab in ((0, N_INIT), (9, N_INIT + 450)):
                ex = shown(lab[:nlab], np.array(ylab[:nlab])); cands = subset(pool, 0, r_, lab[:nlab])
                for arm, kbs, e in (("llm_loop", "", ex), ("llm_kb", kb, ex), ("llm_zeroshot", "", [])):
                    per[(reg, r_, arm)] = len(build_prompt(e, cands, smiles, kbs))
        avg = {arm: np.mean([v for (g, r_, ar), v in per.items() if ar == arm]) for arm in ("llm_loop", "llm_kb", "llm_zeroshot")}
        one = len(build_prompt([(lab[i], float(ylab[i])) for i in range(N_INIT + 500)], subset(pool, 0, 9, lab), smiles))
        print("avg prompt chars", {k: int(v) for k, v in avg.items()}, "| one-shot chars", one)
        n_seq = len(a.regimes) * len(seeds); out = {}
        for tok_per_char in (1 / 3.0, 1 / 2.2):
            tin = n_seq * (ROUNDS * (avg["llm_loop"] * 2 + avg["llm_kb"] + avg["llm_zeroshot"]) + one) * tok_per_char; tout = n_seq * (ROUNDS * 4 + 1) * 280
            out[round(tok_per_char, 3)] = dict(input_tokens=int(tin), output_tokens=int(tout), usd=round(tin * PRICE_IN + tout * PRICE_OUT, 2), calls=n_seq * (ROUNDS * 4 + 1))
        print(json.dumps(out, indent=1)); return
    def task(arg):
        reg, seed = arg; f = f"{a.out}/llm_{reg}_{seed}.json"
        if os.path.exists(f): return
        init, pool = P.setup(reg, seed, d["srcs"], d["scaf"], N_INIT, d["flat"]); E, pool = L.make_eval_slice(pool, seed, N_EVAL); out = {"seed": seed, "regime": reg, "model": a.model}
        for arm in ("llm_loop", "llm_kb", "llm_shuffled", "llm_zeroshot", "subset_random", "subset_gbm"):
            out[arm] = run_seq(arm, ctx, init, pool, seed, a, cost, smiles, kb, gbm)
        out["llm_oneshot"] = run_seq("llm_oneshot", ctx, init, pool, seed, a, cost, smiles, kb, loop_final=out["llm_loop"])
        out["llm_loop"].pop("labeled"); out["llm_loop"].pop("ylab"); json.dump(out, open(f + ".tmp", "w")); os.replace(f + ".tmp", f)
        print("done", reg, seed, {k: sum(out[k]["hits"]) for k in out if isinstance(out[k], dict) and "hits" in out[k]}, "USD %.2f" % cost.usd, flush=True)
    with ThreadPoolExecutor(a.workers) as ex: list(ex.map(task, [(g, s) for g in a.regimes for s in seeds]))
    print("TOTAL USD %.2f calls %d tokens in %d out %d" % (cost.usd, cost.calls, cost.tin, cost.tout))


if __name__ == "__main__":
    main()
