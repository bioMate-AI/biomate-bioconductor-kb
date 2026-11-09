"""Masked vs unmasked seeded completion with ChemFM-1B (GPU spot). Same seeds, prefix protocol and metrics as pilot 3 (generation_pilot/gen_pilot.py), so Y is comparable.
usage: masked_sampling.py OUT --frac 0.85 --n 5000 [--temp 1.0] [--seed 0] [--lora PATH] [--modes masked,unmasked]
Env: CHEMFM_DIR (weights + tokenizer), CPM_CSV (CycPeptMPDB, for the seed split / novelty exactly as pilot 3).
Reported per mode: completion rate (ended on eos before the length cap), validity, uniqueness, novelty, Y per 1000 (denominator = all n incl. failures), fraction satisfying C
(masked: must be 1.0 among completed by construction; checked with RDKit here), sequence-level KL(q_masked || p) = -sum_t log Z_t (nats, mean over completed rows; Z_t = unmasked mass of
the feasible tokens), internal diversity, wall time per step. Nothing here is binding or permeability evidence."""
import os, sys, json, time, argparse, random, gzip, collections
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..")); sys.path.insert(0, os.path.join(HERE, "..", "..", "generation_pilot")); sys.path.insert(0, os.path.join(HERE, "..", ".."))
import torch
from rdkit import Chem
import gen_pilot
from rules import spec, vocab as V
from rules.constraint import ChemFMConstraint

MAXLEN = 500


def load_model(d, lora=None):
    from transformers import AutoTokenizer, AutoModelForCausalLM
    tok = AutoTokenizer.from_pretrained(d); dev = "cuda" if torch.cuda.is_available() else "cpu"
    m = AutoModelForCausalLM.from_pretrained(d, torch_dtype=torch.bfloat16 if dev == "cuda" else torch.float32).to(dev).eval()
    if lora:
        from peft import PeftModel
        m = PeftModel.from_pretrained(m, lora).eval()
    return tok, m, dev


def prompts_for(tok, seeds, n, frac, rng):
    """pilot-3 protocol: P tokens of the seed (rounded down to a multiple of 8 when >= 8), prompt = [ids[0]] + body[:P]; grouped by length."""
    groups = collections.defaultdict(list)
    for i in range(n):
        s = rng.choice(seeds); ids = tok(s, add_special_tokens=True)["input_ids"]
        body = ids[1:-1] if (len(ids) > 2 and ids[-1] == tok.eos_token_id) else ids[1:]
        P = max(2, min(len(body) - 1, int(round(frac * len(body))))); P = max(2, (P // 8) * 8) if P >= 8 else P
        groups[P].append((i, [ids[0]] + body[:P]))
    return groups


def dead_info(st, con):
    """why is the mask empty? record tracker state + which component of C the (possibly complete) string violates."""
    d = dict(n=st.n, mass=round(st.mass, 1), nme_lb=st.nme_lower_bound(), open_branches=len(st.stack), open_rings=len(st.rings), complete=bool(st.complete()), pend=st.pend, tail=st.string()[-50:], feasible_now=bool(st.feasible(1400.0, 6, 500 - st.n)))
    if st.complete():
        m = Chem.MolFromSmiles(st.string())
        if m is None: d["rdkit_parse"] = False
        else:
            from rdkit.Chem import Descriptors, rdMolDescriptors
            mr, nme = spec.mol_stats(m); d.update(rdkit_parse=True, max_ring=mr, nme=nme, mw=round(Descriptors.MolWt(m), 1), tpsa=round(rdMolDescriptors.CalcTPSA(m), 1), pains=bool(spec.PAINS.HasMatch(m)), frags=len(Chem.GetMolFrags(m)))
    return d


@torch.no_grad()
def sample_group(model, dev, con, items, temp, masked, gen, stats):
    """items: [(row, prompt_ids)] with identical prompt length. returns {row: (ids_generated, finished, logZ)}."""
    B = len(items); x = torch.tensor([p for _, p in items], device=dev); P = x.shape[1]
    out = model(input_ids=x, use_cache=True); past = out.past_key_values; logits = out.logits[:, -1].float().cpu().numpy()
    gen_ids = [[] for _ in range(B)]; done = [False] * B; fin = [False] * B; logz = [0.0] * B; dead = [False] * B; states = None; why = ["length_cap"] * B
    if masked:
        states = []
        for k, (_, p) in enumerate(items):
            try: states.append(con.init_state(p))
            except ValueError: states.append(None); done[k] = True; dead[k] = True; why[k] = "prompt_illegal"        # prompt outside the tracker's SMILES subset
    for step in range(min(300, MAXLEN - P)):
        nxt = np.full(B, con.eos, dtype=np.int64); t0 = time.perf_counter()
        for i in range(B):
            if done[i]: continue
            lg = logits[i].astype(np.float64) / temp; lg = lg - lg.max(); p = np.exp(lg); p /= p.sum()
            if masked:
                m = con.mask(states[i])
                if not m.any():
                    done[i] = True; dead[i] = True; why[i] = "dead_end"
                    if len(stats.setdefault("dead_info", [])) < 40: stats["dead_info"].append(dead_info(states[i], con))
                    continue
                z = float(p[m].sum()); logz[i] += float(np.log(max(z, 1e-30))); q = np.where(m, p, 0.0)
                if con.lam: q = q * np.exp(con.soft_logits(states[i]))
                q /= q.sum()
            else: q = p
            t = int(gen.choice(len(q), p=q)); nxt[i] = t
            if t == con.eos: done[i] = True; fin[i] = True; why[i] = "ok"
            else:
                gen_ids[i].append(t)
                if masked: con.advance(states[i], t)
        stats["mask_seconds"] += time.perf_counter() - t0; stats["row_steps"] += sum(1 for d in done if not d)
        if all(done): break
        o = model(input_ids=torch.tensor(nxt[:, None], device=dev), past_key_values=past, use_cache=True); past = o.past_key_values; logits = o.logits[:, -1].float().cpu().numpy()
    return {items[i][0]: (gen_ids[i], fin[i], logz[i], items[i][1], why[i]) for i in range(B)}


def make_soft(name, lam):
    from rules.soft import SoftSource
    AP = os.path.join(HERE, "..")
    if name == "none": return None
    if name == "literature_uniform": return SoftSource.literature_uniform()
    if name == "literature_kb": return SoftSource.from_knowledge(os.path.join(AP, "knowledge", "knowledge_kb_v1.json"))
    if name == "groupA": return SoftSource.groupA_descriptive(os.path.join(AP, "rules_mining", "groupA_sensitivity.json"))
    raise ValueError(name)


def run(args):
    ctx = gen_pilot.context(); tok, model, dev = load_model(os.environ["CHEMFM_DIR"], args.lora)
    voc = V.load(os.path.join(os.environ["CHEMFM_DIR"], "tokenizer.json"))
    soft = make_soft(args.soft, args.lam); con = ChemFMConstraint(voc, max_len=MAXLEN, lam_soft=args.lam, soft=soft, lookahead_nme=not args.no_lookahead)
    for seed in [int(x) for x in str(args.seeds).split(",")]:
        args.seed = seed; run_seed(args, ctx, tok, model, dev, voc, con)


def run_seed(args, ctx, tok, model, dev, voc, con):
    res = {}
    for mode in args.modes.split(","):
        masked = mode == "masked"; rng = random.Random(args.seed * 7919 + 13); gen = np.random.default_rng(args.seed); torch.manual_seed(args.seed)
        groups = prompts_for(tok, ctx["S"], args.n, args.frac, rng); raw = [""] * args.n; fins = 0; logzs = []; reasons = collections.Counter(); stats = {"mask_seconds": 0.0, "row_steps": 0}; t_all = time.time()
        for P, items in sorted(groups.items()):
            for k in range(0, len(items), args.batch):
                r = sample_group(model, dev, con, items[k:k + args.batch], args.temp, masked, gen, stats)
                for row, (gids, fin, lz, prompt, why) in r.items():
                    reasons[why] += 1
                    if masked and not fin: continue                      # failed to finish within the length cap (or dead end): empty string = invalid
                    s = voc.decode(list(prompt) + gids)
                    raw[row] = s
                    if masked: fins += 1; logzs.append(lz)
                    else: fins += int(fin)
        met, cons = gen_pilot.evaluate(raw, ctx["seeds_set"], ctx["cpm_set"], ctx["ref_ring"], ctx["ref_nme"], random.Random(args.seed))
        comp = [s for s in raw if s]; sat = [spec.satisfies_smiles(s) for s in comp]
        met.update(mode=mode, soft=args.soft, lam=args.lam, lookahead_nme=not args.no_lookahead, tag=args.tag, frac=args.frac, temp=args.temp, seed=args.seed, completion_rate=round(fins / args.n, 4), frac_satisfying_of_completed=round(float(np.mean(sat)), 4) if sat else None,
                   n_completed=len(comp), seconds=round(time.time() - t_all, 1), mask_ms_per_row_step=round(1000 * stats["mask_seconds"] / max(1, stats["row_steps"]), 3))
        if masked and logzs: met["kl_seq_nats_mean"] = round(-float(np.mean(logzs)), 4); met["kl_seq_nats_median"] = round(-float(np.median(logzs)), 4)
        met["row_outcomes"] = dict(reasons); met["dead_info"] = stats.get("dead_info", []); res[mode] = met; print(json.dumps(met), flush=True)
        os.makedirs(args.out, exist_ok=True)
        with gzip.open(os.path.join(args.out, f"raw_{mode}{args.tag}_f{args.frac}_s{args.seed}.smi.gz"), "wt") as f: f.write("\n".join(raw))
    json.dump(res, open(os.path.join(args.out, f"masked_sampling{args.tag}_f{args.frac}_s{args.seed}.json"), "w"), indent=1)


if __name__ == "__main__":
    ap = argparse.ArgumentParser(); ap.add_argument("out"); ap.add_argument("--frac", type=float, default=0.85); ap.add_argument("--n", type=int, default=5000)
    ap.add_argument("--temp", type=float, default=1.0); ap.add_argument("--seed", type=int, default=0); ap.add_argument("--batch", type=int, default=64)
    ap.add_argument("--lora", default=None); ap.add_argument("--modes", default="masked,unmasked"); ap.add_argument("--seeds", default="0")
    ap.add_argument("--soft", default="none"); ap.add_argument("--lam", type=float, default=0.0); ap.add_argument("--tag", default=""); ap.add_argument("--no-lookahead", action="store_true"); run(ap.parse_args())
