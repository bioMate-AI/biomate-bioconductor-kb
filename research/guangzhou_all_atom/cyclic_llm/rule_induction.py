"""ILP-style rule induction (SNG learning L1): learn the design spec from a target's few actives, instead of
hand-coding acceptance_gate. First version = greedy discriminative-conjunction learner over peptide predicates;
swap in Popper/Aleph later for full ILP. Emits the induced rule as a first-class artifact (the H in SNG's (H,X))."""
import json, sys, os
sys.path.insert(0, os.path.dirname(__file__))
from acceptance_gate import raw_tokens, _is_arom, _strip_mods, _canon1, p6_of

AROM_CANON = {"F", "Y", "W"}

def predicates(helm):
    """HELM -> boolean logical facts about the candidate."""
    toks = raw_tokens(helm)
    seq1 = "".join(_canon1(t) for t in toks); w = seq1 + seq1[:6]
    has_rgd = "RGD" in w; has_rgdl = "RGDL" in w
    has_dpro = any(t == "dP" or (t.startswith("d") and _strip_mods(t) == "P") for t in toks)
    has_nme = any(t.startswith("NMe") for t in toks)
    nlys = sum(1 for t in toks if _strip_mods(t) == "K")
    i = w.find("RGDL")
    p1 = toks[i - 1] if i > 0 else (toks[-1] if i == 0 else None)
    dpi = next((j for j, t in enumerate(toks) if t == "dP" or (t.startswith("d") and _strip_mods(t) == "P")), None)
    p7 = toks[dpi - 1] if dpi is not None and dpi > 0 else None
    cyclic = helm.strip().lower().startswith("cyclo(")
    return {
        "has_rgd": has_rgd,
        "has_rgdl": has_rgdl,
        "has_turn_dpro": has_dpro,
        "has_nmethyl": has_nme,
        "single_handle": nlys == 1,
        "has_handle": nlys >= 1,
        "flank_aromatic_p1": bool(p1 and _is_arom(p1)),
        "flank_aromatic_p7": bool(p7 and _is_arom(p7)),
        "head_to_tail": cyclic,
    }

def induce(actives, non_actives):
    """Greedy discriminative conjunction: predicates true for ALL actives and NOT true for all non-actives."""
    pos = [predicates(h) for h in actives]
    neg = [predicates(h) for h in non_actives]
    keys = list(pos[0].keys())
    # candidate predicates: true for every active
    true_all_pos = [k for k in keys if all(p[k] for p in pos)]
    # discriminative: among those, keep ones that are NOT true for at least one negative (they separate)
    rule = [k for k in true_all_pos if any(not n[k] for n in neg)]
    # if some pos-true predicate is also true for ALL negatives it is non-discriminative -> dropped
    dropped = [k for k in true_all_pos if k not in rule]
    def covers(p): return all(p[k] for k in rule)
    tp = sum(1 for p in pos if covers(p)); fn = len(pos) - tp
    fp = sum(1 for n in neg if covers(n)); tn = len(neg) - fp
    return {"rule": rule, "non_discriminative_dropped": dropped,
            "coverage": {"pos_covered": f"{tp}/{len(pos)}", "neg_excluded": f"{tn}/{len(neg)}", "fp": fp, "fn": fn}}

if __name__ == "__main__":
    for tgt in ("avb6", "pdl1"):
        kb = json.load(open(os.path.join(os.path.dirname(__file__), "target_kb", f"{tgt}.json")))
        ex = kb["examples"]
        res = induce(ex["actives"], ex["non_actives"])
        print(f"=== {tgt} : induced binder rule (from {len(ex['actives'])} actives, {len(ex['non_actives'])} non-actives) ===")
        print("  binder(X) :- " + ", ".join(res["rule"]) + ".")
        print("  coverage:", res["coverage"], "| dropped(non-discriminative):", res["non_discriminative_dropped"])
        # emit the induced rule as a first-class artifact (the H)
        out = os.path.join(os.path.dirname(__file__), "target_kb", f"{tgt}_induced_rule.json")
        json.dump({"target": tgt, "induced_rule": res["rule"], "coverage": res["coverage"]}, open(out, "w"), indent=2)
        print("  wrote", os.path.basename(out))
